import Foundation
import WhoopFrames

/// METOD M37 · BESLUT B37 · BESLUT B42 · BESLUT B45 · BESLUT B85
/// Sömnstadierna som ett band under en natt. Sömnperioden (METOD M26: insomning till uppvaknande) delas i
/// 30 s-epoker från insomningen. En epok är **mätt** när armens vinkel finns i minst fyra av dess sex
/// femsekundsepoker (samma krav som METOD M31); annars är den glapp, varken sömn eller vaken. En mätt epok
/// är **vaken** när sömn/vaken-modellen (BESLUT B37, METOD M31 regel (d)) ger P(vaken) ≥ tröskeln; annars är
/// stadiet det av lätt, djup och REM som stadiemodellen (BESLUT B42, METOD M35) ger störst sannolikhet.
/// Sedan slås följder av lätt, djup och REM kortare än 2 minuter ihop med en granne (BESLUT B85, `settle`);
/// vaken kortas aldrig. Sömntiden är summan av lätt, djup och REM (BESLUT B45).
///
/// Särdragen räknas i `NightFeatures` tal för tal som Python (`tools/natt_stadier.py`), vikterna kommer ur
/// `ModelData` (BESLUT B44), och `StadierSpegelTests` kräver samma tal som Python ger.
public enum SleepStage: Int, CaseIterable, Codable, Sendable {
    /// Klassernas ordning i `tools/modeller/stadier.json`.
    case wake = 0, light = 1, deep = 2, rem = 3
}

public enum NightStages {

    // MARK: Konstanter

    /// METOD M37. PSG-epoken. **Antagande** att den passar bandet.
    public static let epochSeconds: Int = 30
    /// BESLUT B45. Minst så här många av en epoks sex femsekundsepoker ska ha armens vinkel (som METOD M31).
    public static let minAngleEpochs: Int = 4
    /// BESLUT B45. Säkerhetens nivåer: under 0,5 är nivå 0, från 0,5 nivå 1, från 0,75 nivå 2. **Antagande.**
    public static let certaintyLimits: [Double] = [0.5, 0.75]
    /// BESLUT B85 · METOD M37. Lätt, djup och REM är minst så här många epoker i rad (2 min); vaken kortas aldrig.
    /// **Antagande.**
    public static let minSleepRunEpochs: Int = 4
    /// BESLUT B85. Poängens golv, som sannolikhetens golv i sammanfogningen.
    static let scoreFloor: Double = 1e-12

    /// BESLUT B45. Nivå 0, 1 eller 2 för en säkerhet ur `certaintyLimits`.
    public static func level(_ c: Double) -> Int {
        if c < certaintyLimits[0] { return 0 }
        if c < certaintyLimits[1] { return 1 }
        return 2
    }

    // MARK: Resultaten

    /// En 30 s-epok. Epok j börjar `onset + 30 j`.
    public struct Epoch: Equatable, Sendable {
        /// Unix-sekunder.
        public var start: Int
        /// Minst `minAngleEpochs` av sex femsekundsepoker har armens vinkel (BESLUT B45).
        public var measured: Bool
        /// P(vaken) ur sömn/vaken-modellen (BESLUT B37).
        public var wakeProbability: Double
        /// Stadiemodellen (BESLUT B42): [vaken, lätt, djup, REM], summa 1.
        public var probabilities: [Double]
        /// BESLUT B45. `nil` när epoken inte är mätt.
        public var stage: SleepStage?

        public init(start: Int, measured: Bool, wakeProbability: Double,
                    probabilities: [Double], stage: SleepStage?) {
            self.start = start
            self.measured = measured
            self.wakeProbability = wakeProbability
            self.probabilities = probabilities
            self.stage = stage
        }

        public var end: Int { start + NightStages.epochSeconds }

        /// BESLUT B45. Hur säkert stadiet är: P(vaken) för en vaken epok, annars stadiets sannolikhet delad med
        /// summan för lätt, djup och REM. `nil` när `stage` är `nil`.
        public var certainty: Double? {
            guard let s = stage else { return nil }
            if s == .wake { return wakeProbability }
            guard probabilities.count == 4 else { return nil }
            let sleep: Double = probabilities[1] + probabilities[2] + probabilities[3]
            return probabilities[s.rawValue] / sleep
        }

        /// BESLUT B45. 0, 1 eller 2 ur `certaintyLimits`.
        public var certaintyLevel: Int? {
            guard let c = certainty else { return nil }
            return NightStages.level(c)
        }
    }

    /// Natten från insomning till uppvaknande, en epok per 30 s. En rest kortare än 30 s i slutet är ingen epok.
    public struct Night: Equatable, Sendable {
        public var onset: Int
        public var wake: Int
        public var epochs: [Epoch]

        public init(onset: Int, wake: Int, epochs: [Epoch]) {
            self.onset = onset
            self.wake = wake
            self.epochs = epochs
        }

        /// Minuter i ett stadium: epoker × 0,5.
        public func minutes(_ stage: SleepStage) -> Double {
            var n: Int = 0
            for e in epochs where e.stage == stage { n += 1 }
            return Double(n) * Double(NightStages.epochSeconds) / 60
        }
    }

    // MARK: Räkningen

    /// METOD M37. Natten per epok. `beats` = `RRCleaning.clean(K18Beats.recording(series, onset:, wake:))`.
    /// `nil` när perioden är kortare än en epok eller vikterna inte går att läsa.
    public static func estimate(_ series: K18Series, onset: Int, wake: Int, beats: [Beat]) -> Night? {
        let n30: Int = (wake - onset) / epochSeconds
        guard n30 >= 1, let wakeModel = SleepModels.wake, let stageModel = SleepModels.stage else { return nil }

        let move = NightFeatures.movement(series, onset: onset, epochs: n30)
        let heart: [[Double]] = NightFeatures.heart(beats, onset: onset, epochs: n30)
        let q: [[Double]] = stageProbabilities(heart: heart, movement: move.rows, model: stageModel)

        var epochs: [Epoch] = []
        epochs.reserveCapacity(n30)
        for j in 0..<n30 {
            let pWake: Double = wakeModel.probability(move.rows[j])
            let stage: SleepStage? = decide(measured: move.measured[j], wakeProbability: pWake,
                                            probabilities: q[j], threshold: wakeModel.troskel)
            epochs.append(Epoch(start: onset + epochSeconds * j, measured: move.measured[j],
                                wakeProbability: pWake, probabilities: q[j], stage: stage))
        }
        // BESLUT B85. Efter B45:s beslut per epok: korta följder av lätt, djup och REM slås ihop med en granne.
        return Night(onset: onset, wake: wake, epochs: settle(epochs, threshold: wakeModel.troskel))
    }

    /// BESLUT B45. Omätt epok: ingenting. Mätt: vaken när P(vaken) ≥ tröskeln, annars det av lätt, djup och REM
    /// med störst sannolikhet (det första vid lika).
    static func decide(measured: Bool, wakeProbability: Double, probabilities q: [Double],
                       threshold: Double) -> SleepStage? {
        guard measured else { return nil }
        if wakeProbability >= threshold { return .wake }
        var best: SleepStage = .light
        if q[2] > q[best.rawValue] { best = .deep }
        if q[3] > q[best.rawValue] { best = .rem }
        return best
    }

    // MARK: Lugnare stadier (BESLUT B85)

    /// BESLUT B85 · METOD M37. Fyra log-poäng för en mätt epok, vars arg max (vaken vid lika) är `decide`. Vaken:
    /// log P′, där P′ är P(vaken) flyttad så att tröskeln blir 0,5 (logit P′ = logit P − logit tröskeln). Ett
    /// sömnstadium: log(1 − P′) + log(r / r_max), där r är stadiets andel av lätt + djup + REM.
    /// Rad för rad som `natt_stadier.poang`.
    static func score(wakeProbability: Double, probabilities q: [Double], threshold t: Double) -> [Double] {
        let pv: Double = min(max(wakeProbability, scoreFloor), 1 - scoreFloor)
        var pp: Double = pv * (1 - t) / (pv * (1 - t) + (1 - pv) * t)
        pp = min(max(pp, scoreFloor), 1 - scoreFloor)
        let sleep: Double = q[1] + q[2] + q[3]
        var r: [Double] = [0, 0, 0]
        for s in 0..<3 { r[s] = max(q[s + 1] / sleep, scoreFloor) }
        let rmax: Double = max(r[0], max(r[1], r[2]))
        var out: [Double] = [log(pp)]
        for s in 0..<3 { out.append(log(1 - pp) + log(r[s] / rmax)) }
        return out
    }

    /// BESLUT B85. [första, efter sista, stadium] för följderna av samma stadium inom [a, b) (`natt_stadier.foljder`).
    static func runs(_ st: [Int], _ a: Int, _ b: Int) -> [[Int]] {
        var out: [[Int]] = []
        for j in a..<b {
            if let last = out.last, last[2] == st[j] {
                out[out.count - 1][1] = j + 1
            } else {
                out.append([j, j + 1, st[j]])
            }
        }
        return out
    }

    /// BESLUT B85 · METOD M37. Lugnare stadier efter `decide`. Varje mätt sträcka för sig (en omätt epok bryter och
    /// rörs inte): ta den kortaste följden av lätt, djup eller REM som är kortare än `minSleepRunEpochs`, den
    /// tidigaste vid lika, och ge hela följden stadiet hos den granne vars stadium har störst summa av poängen
    /// (`score`) över följdens epoker, vänster vid lika; grannen kan vara vaken. Om tills ingen följd är för kort
    /// eller sträckan är en enda följd. Vaken kortas aldrig. Heltalsslingor och summor från vänster, rad för rad som
    /// `natt_stadier.lugna`.
    static func settle(_ epochs: [Epoch], threshold: Double) -> [Epoch] {
        let n: Int = epochs.count
        var st = [Int](repeating: -1, count: n)
        var p = [[Double]](repeating: [], count: n)
        for j in 0..<n {
            guard let s = epochs[j].stage else { continue }
            st[j] = s.rawValue
            p[j] = score(wakeProbability: epochs[j].wakeProbability, probabilities: epochs[j].probabilities,
                         threshold: threshold)
        }
        var j: Int = 0
        while j < n {
            if st[j] < 0 {
                j += 1
                continue
            }
            let a: Int = j
            while j < n && st[j] >= 0 { j += 1 }
            let b: Int = j
            while true {
                let f: [[Int]] = runs(st, a, b)
                if f.count < 2 { break }
                var kand: Int = -1
                for i in 0..<f.count {
                    let length: Int = f[i][1] - f[i][0]
                    if f[i][2] != SleepStage.wake.rawValue && length < minSleepRunEpochs
                        && (kand < 0 || length < f[kand][1] - f[kand][0]) {
                        kand = i
                    }
                }
                if kand < 0 { break }
                let s0: Int = f[kand][0]
                let s1: Int = f[kand][1]
                let best: Int
                if kand == 0 {
                    best = f[1][2]
                } else if kand == f.count - 1 || f[kand - 1][2] == f[kand + 1][2] {
                    best = f[kand - 1][2]
                } else {
                    let left: Int = f[kand - 1][2]
                    let right: Int = f[kand + 1][2]
                    var sumLeft: Double = 0
                    var sumRight: Double = 0
                    for k in s0..<s1 {
                        sumLeft += p[k][left]
                        sumRight += p[k][right]
                    }
                    best = sumRight > sumLeft ? right : left
                }
                for k in s0..<s1 { st[k] = best }
            }
        }
        var out: [Epoch] = epochs
        for k in 0..<n where st[k] >= 0 { out[k].stage = SleepStage(rawValue: st[k]) }
        return out
    }

    /// METOD M37. Stadiemodellen på hjärtats tolv och rörelsens sju råa särdrag per epok: HRV-särdragen mot
    /// nattens nivå och den rullande, grannepokerna, standardiseringen, softmax för HRV-delen och rörelsedelen,
    /// och sammanfogningen (`stadier_sekvens.forutsag_stadier`). Rader med fyra sannolikheter.
    static func stageProbabilities(heart: [[Double]], movement: [[Double]], model: StageModel) -> [[Double]] {
        let n: Int = heart.count
        let base: Int = model.hrv.grund.count                          // 10
        var h = [[Double]](repeating: [Double](repeating: Double.nan, count: base), count: n)
        for j in 0..<n { for c in 0..<base { h[j][c] = heart[j][c] } }
        let normalized: [[Double]] = normalize(h, rolling: model.hrv.normering.rullandeEpoker)

        var shifted: [[[Double]]] = []
        for s in model.hrv.grannar.skift { shifted.append(shift(normalized, by: s)) }
        var smoothed: [[[Double]]] = []
        for w in model.hrv.grannar.utjamning { smoothed.append(smooth(normalized, radius: w)) }

        let part = model.hrv.part
        let rpart = model.rorelse
        let mal: [Double] = model.sammanfogning.mal
        var out: [[Double]] = []
        out.reserveCapacity(n)
        for j in 0..<n {
            var x: [Double] = normalized[j]
            for m in shifted { x.append(contentsOf: m[j]) }
            for m in smoothed { x.append(contentsOf: m[j]) }
            x.append(contentsOf: heart[j][base...])                    // andel av natten, timmar
            let ph: [Double] = part.probabilities(x)

            let mv: [Double] = movement[j]
            let xr: [Double] = [mv[0], mv[1], mv[2], mv[3], mv[6], heart[j][base + 1]]
            let pr: [Double] = rpart.probabilities(xr)
            out.append(fuse(ph, part.forekomst, pr, rpart.forekomst, mal))
        }
        return out
    }

    /// `stadier_sekvens.foga`: Π P_i(klass | x_i) / π_i(klass) gånger målets förekomst, normerat.
    static func fuse(_ p1: [Double], _ prior1: [Double], _ p2: [Double], _ prior2: [Double],
                     _ target: [Double]) -> [Double] {
        var l = [Double](repeating: 0, count: 4)
        for c in 0..<4 {
            let e1: Double = log(max(p1[c], 1e-12)) - log(prior1[c])
            let e2: Double = log(max(p2[c], 1e-12)) - log(prior2[c])
            l[c] = (e1 + e2) + log(target[c])
        }
        return SleepModels.softmax(l)
    }

    // MARK: Normering och grannar (stadier_hmc.normera, stadier_sekvens.skifta/utjamna)

    /// `normera(H, "natt+rullande")`: [mot nattens median och IQR | mot medianen över ±`rolling` epoker och
    /// nattens IQR], per kolumn. Saknade värden räknas inte; en kolumn utan värden ger `nan`.
    static func normalize(_ h: [[Double]], rolling: Int) -> [[Double]] {
        let n: Int = h.count
        let cols: Int = h.first?.count ?? 0
        var out = [[Double]](repeating: [Double](repeating: Double.nan, count: 2 * cols), count: n)
        for c in 0..<cols {
            var column = [Double](repeating: 0, count: n)
            for j in 0..<n { column[j] = h[j][c] }
            let median: Double = NightFeatures.finiteMedian(column)
            let spread: Double = NightFeatures.iqr(column)
            for j in 0..<n {
                let lo: Int = max(0, j - rolling)
                let hi: Int = min(n, j + rolling + 1)
                let r: Double = NightFeatures.finiteMedian(Array(column[lo..<hi]))
                out[j][c] = (column[j] - median) / spread
                out[j][cols + c] = (column[j] - r) / spread
            }
        }
        return out
    }

    /// `skifta(M, s)`: rad j får rad j + s, `nan` utanför natten.
    static func shift(_ m: [[Double]], by s: Int) -> [[Double]] {
        let n: Int = m.count
        let cols: Int = m.first?.count ?? 0
        var out = [[Double]](repeating: [Double](repeating: Double.nan, count: cols), count: n)
        for j in 0..<n {
            let k: Int = j + s
            if k >= 0 && k < n { out[j] = m[k] }
        }
        return out
    }

    /// `utjamna(M, w)`: medel över raderna j − w … j + w (klippt), saknade värden utelämnade, `nan` om inget finns.
    /// Som Python med löpande summor.
    static func smooth(_ m: [[Double]], radius w: Int) -> [[Double]] {
        let n: Int = m.count
        let cols: Int = m.first?.count ?? 0
        var out = [[Double]](repeating: [Double](repeating: Double.nan, count: cols), count: n)
        for c in 0..<cols {
            var values = [Double](repeating: 0, count: n)
            var present = [Double](repeating: 0, count: n)
            for j in 0..<n where m[j][c].isFinite {
                values[j] = m[j][c]
                present[j] = 1
            }
            let c1: [Double] = NightFeatures.running(values)
            let c0: [Double] = NightFeatures.running(present)
            for j in 0..<n {
                let lo: Int = min(max(j - w, 0), n)
                let hi: Int = min(max(j + w + 1, 0), n)
                let count: Double = c0[hi] - c0[lo]
                if count > 0 { out[j][c] = (c1[hi] - c1[lo]) / max(count, 1) }
            }
        }
        return out
    }

    // MARK: Perioden (BESLUT B37, BESLUT B45)

    /// BESLUT B37 · BESLUT B45. Samma insomning, uppvaknande, block och tröskel; sömn, vaken, glapp, vakna stunder
    /// och sömnminuter ur epokerna. Sömn är lätt, djup och REM; vaken är vaken; glapp är de omätta epokerna och
    /// resten efter sista hela epoken. Sömnminuterna (METOD M25, hudtemperaturen) är minuterna där minst
    /// `SleepDetection.minAsleepEpochsPerMinute` av tolv femsekundsepoker är sömn.
    public static func refine(_ period: SleepPeriod, with night: Night) -> SleepPeriod {
        var sleepEpochs: Int = 0
        var wakeEpochs: Int = 0
        var perMinute: [Int: Int] = [:]
        var wakeBouts: [SleepInterval] = []
        var gaps: [SleepInterval] = []
        for e in night.epochs {
            switch e.stage {
            case nil:
                extend(&gaps, start: e.start, end: e.end)
            case .some(.wake):
                wakeEpochs += 1
                extend(&wakeBouts, start: e.start, end: e.end)
            case .some:
                sleepEpochs += 1
                for k in 0..<(epochSeconds / SleepDetection.epochSeconds) {
                    let t: Int = e.start + SleepDetection.epochSeconds * k
                    perMinute[t / 60, default: 0] += 1
                }
            }
        }
        let rest: Int = night.onset + epochSeconds * night.epochs.count
        if period.wake > rest {
            if let last = gaps.last, last.end == rest {
                gaps[gaps.count - 1] = SleepInterval(start: last.start, end: period.wake)
            } else {
                gaps.append(SleepInterval(start: rest, end: period.wake))
            }
        }
        var out: SleepPeriod = period
        out.wakeBouts = wakeBouts
        out.gaps = gaps
        out.asleepSeconds = epochSeconds * sleepEpochs
        out.awakeSeconds = epochSeconds * wakeEpochs
        out.gapSeconds = (period.wake - period.onset) - out.asleepSeconds - out.awakeSeconds
        out.asleepMinutes = perMinute.filter { $0.value >= SleepDetection.minAsleepEpochsPerMinute }.keys.sorted()
        return out
    }

    /// Lägger intervallet [start, end) till listan, ihop med det sista om det slutar där intervallet börjar.
    private static func extend(_ list: inout [SleepInterval], start: Int, end: Int) {
        if let last = list.last, last.end == start {
            list[list.count - 1] = SleepInterval(start: last.start, end: end)
        } else {
            list.append(SleepInterval(start: start, end: end))
        }
    }
}
