import Foundation
import Night
import WhoopFrames

/// METOD M40 · BESLUT B47
/// Klockskillnaden per natt. Mikrofonen går på telefonens klocka, K18 på
/// bandets (METOD M24, M27). Skillnaden skattas ur vändningarna, eftersom det
/// hörs när du rör dig: korrelationen mellan K18:s rörelse per sekund
/// (`movementPerSecond`) och ljudets steg över golvet (`levelA` − golv, minst
/// 0, utan sekunder med snarkning eller tal ≥ 50) för förskjutningar −120 till
/// +120 s. Den godkänns om toppen är minst 3 gånger medianen av |r| över alla
/// förskjutningar och natten har minst 5 rörelseskurar (över METOD M32:s
/// gräns). Annars räknas skillnaden som 0, natten märks "klockan osäker", och
/// ordningen mellan rörelse och ljud kräver 5 s i stället för 1 s.
///
/// Tecknet: `offset` är bandets tid minus telefonens, så ett ljud vid
/// telefonens sekund `t` hör ihop med bandets sekund `t + offset`.
public enum SoundClock {

    // MARK: Konstanter — METOD M40

    /// METOD M40. Förskjutningarna som prövas, sekunder åt vardera hållet. **Antagande.**
    public static let maxShiftSeconds = 120
    /// METOD M40. Toppen ska vara minst så många gånger medianen av |r|. **Antagande.**
    public static let peakToMedian: Double = 3
    /// METOD M40. Minsta antal rörelseskurar. **Antagande.**
    public static let minBursts = 5
    /// METOD M40. Rörelsesekunder med högst så här många sekunder emellan är en skur. **Antagande.**
    public static let burstJoinSeconds = 5
    /// METOD M40. Ordningen mellan rörelse och ljud kräver så här många sekunder
    /// med en säker klocka respektive en osäker. **Antagande.**
    public static let reliableToleranceSeconds = 1
    public static let unreliableToleranceSeconds = 5
    /// METOD M40. Minsta antal par sekunder för att en förskjutning ska räknas.
    static let minPairs = 60

    public struct Estimate: Equatable, Sendable {
        /// Bandets tid minus telefonens, sekunder; 0 när skattningen inte godkänns.
        public var offset: Int
        public var isReliable: Bool
        /// Toppens korrelation, och dess kvot mot medianen av |r|.
        public var peak: Double?
        public var ratio: Double?
        /// Rörelseskurar i natten.
        public var bursts: Int

        public init(offset: Int, isReliable: Bool, peak: Double?, ratio: Double?, bursts: Int) {
            self.offset = offset
            self.isReliable = isReliable
            self.peak = peak
            self.ratio = ratio
            self.bursts = bursts
        }

        /// Hur mycket klockan får skilja när rörelse och ljud ordnas (METOD M40).
        public var toleranceSeconds: Int {
            isReliable ? SoundClock.reliableToleranceSeconds : SoundClock.unreliableToleranceSeconds
        }
    }

    /// Starttiderna (bandets sekunder) för rörelseskurarna: rörelsesekunder över
    /// METOD M32:s gräns, ihopslagna när det är högst 5 sekunder mellan dem.
    public static func burstStarts(_ series: K18Series) -> [Int] {
        var out: [Int] = []
        var lastMoving: Int?
        for m in series.movementPerSecond where m.value >= NightLayers.movementThreshold {
            if let l = lastMoving, m.time - l - 1 <= burstJoinSeconds {
                lastMoving = m.time
            } else {
                out.append(m.time)
                lastMoving = m.time
            }
        }
        return out
    }

    /// Skattar skillnaden. `soundStart`: filens start (Unix, telefonens klocka).
    public static func estimate(_ seconds: [SoundSecond], soundStart: Int, series: K18Series) -> Estimate {
        let bursts: Int = burstStarts(series).count
        let none = Estimate(offset: 0, isReliable: false, peak: nil, ratio: nil, bursts: bursts)
        let movement = series.movementPerSecond
        guard let firstMove = movement.first, let lastMove = movement.last, !seconds.isEmpty else { return none }

        // Ljudets steg per sekund, i filens ordning; sekunder utan golv är 0.
        let sorted: [SoundSecond] = seconds.sorted { (a: SoundSecond, b: SoundSecond) -> Bool in a.second < b.second }
        let floors: [Double?] = NoiseFloor.series(sorted)
        var index: [Int] = []
        var step: [Double] = []
        for (i, s) in sorted.enumerated() {
            if s.value(of: .snoring) >= SnoreOwnership.snoreThreshold { continue }
            if s.value(of: .speech) >= SnoreOwnership.snoreThreshold { continue }
            let above: Double = floors[i].map { (f: Double) -> Double in max(0, s.levelADB - f) } ?? 0
            index.append(s.second)
            step.append(above)
        }
        guard !index.isEmpty else { return none }

        // Rörelsen på en tät axel över bandets sekunder.
        let lo: Int = firstMove.time
        let span: Int = lastMove.time - lo + 1
        var move = [Double](repeating: 0, count: span)
        var have = [Bool](repeating: false, count: span)
        for m in movement {
            move[m.time - lo] = m.value
            have[m.time - lo] = true
        }

        var corr: [Double] = []
        var shifts: [Int] = []
        for d in -maxShiftSeconds...maxShiftSeconds {
            var n: Double = 0
            var sa: Double = 0
            var sb: Double = 0
            var sab: Double = 0
            var saa: Double = 0
            var sbb: Double = 0
            for k in 0..<index.count {
                let j: Int = soundStart + index[k] + d - lo
                if j < 0 || j >= span || !have[j] { continue }
                let a: Double = step[k]
                let b: Double = move[j]
                n += 1
                sa += a
                sb += b
                sab += a * b
                saa += a * a
                sbb += b * b
            }
            var r: Double = 0
            if n >= Double(minPairs) {
                let cov: Double = sab - sa * sb / n
                let va: Double = saa - sa * sa / n
                let vb: Double = sbb - sb * sb / n
                if va > 1e-12 && vb > 1e-12 { r = cov / (va * vb).squareRoot() }
            }
            corr.append(r)
            shifts.append(d)
        }
        var best = 0
        for i in 1..<corr.count where corr[i] > corr[best] { best = i }
        let absolute: [Double] = corr.map { (r: Double) -> Double in abs(r) }.sorted()
        let median: Double = absolute[absolute.count / 2]
        let peak: Double = corr[best]
        let ratio: Double? = median > 0 ? peak / median : nil
        let reliable: Bool = bursts >= minBursts && peak > 0 && peak >= peakToMedian * median
        return Estimate(offset: reliable ? shifts[best] : 0, isReliable: reliable, peak: peak, ratio: ratio,
                        bursts: bursts)
    }
}
