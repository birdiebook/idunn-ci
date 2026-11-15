import Foundation
import HeartRate

/// METOD M4 · METOD M5 · METOD M10
/// Natten i siffror (PLAN.md I3): de rensade slagen (METOD M3) delas i
/// 5-minutersfönster, och varje fönster får RMSSD, medelpuls och andning.
/// Nattens värden räknas ur fönstren: HRV-kandidaterna, vilopulsen (10:e
/// percentilen, BESLUT B76) och andningsfrekvensen.
///
/// Insomning och uppvaknande är inte skattade än (METOD M8). Tills de är det
/// räknas alla fönster i inspelningen, eller i det tidsintervall som skickas in.
public enum NightAnalysis {

    // MARK: Gränserna — METOD M4

    /// METOD M4. Fönstrens längd: Task Force-standardens kortidsmätning.
    public static let windowSeconds: TimeInterval = 300
    /// METOD M4. Ett fönster räknas bara med minst så här många skillnader
    /// mellan slag som båda överlevt rensningen.
    public static let minDifferencesPerWindow = 120
    /// METOD M4. Kandidat (c): så många av de lugnaste fönstren i nattens sista tredjedel.
    public static let lateQuietWindows = 3
    /// METOD M4. Kandidat (c): den sista tredjedelen börjar här, räknat i nattens längd.
    public static let lateStartFraction = 2.0 / 3.0
    /// METOD M4. Kandidat (d), den Whoop-lika: överlappande 5-minutersfönster
    /// som glider fram så här många sekunder åt gången (Whoop, ej verifierat).
    public static let slidingStepSeconds: TimeInterval = 30

    // MARK: Vilopulsen — METOD M5 · BESLUT B76

    /// METOD M5 · BESLUT B76. Vilopulsen är den här percentilen av de giltiga fönstrens medelpuls: den puls som en
    /// tiondel av fönstren ligger under, så att ett enstaka lågt fönster inte styr. Nattens absolut lägsta fönster är
    /// kurvans botten (METOD M18).
    public static let restingPercentile = 0.10

    // MARK: Resultaten

    /// Ett 5-minutersfönster. Måtten är `nil` när fönstret har för få skillnader.
    public struct Window: Equatable, Sendable {
        public var start: Date
        /// Alla slag vars tid ligger i fönstret, även de som kastades.
        public var beats: Int
        public var keptBeats: Int
        /// Skillnader mellan slag som båda överlevt (METOD M3).
        public var differences: Int
        /// METOD M4. Millisekunder.
        public var rmssd: Double?
        /// METOD M5. Slag per minut: 60000 / medel av de behållna intervallen.
        public var meanHeartRate: Double?
        /// METOD M10.
        public var breathing: Breathing.Estimate?

        public var isValid: Bool { rmssd != nil }
        public var end: Date { start.addingTimeInterval(NightAnalysis.windowSeconds) }
    }

    /// METOD M4 · BESLUT B13. Vilket nattvärde för HRV. (a) är förvalet: nattens
    /// medel har bäst stöd. De andra räknas vid sidan av, för jämförelsen mot Whoop.
    public enum Candidate: String, CaseIterable, Sendable {
        /// (a) Medel av fönstrens RMSSD. Förvalet.
        case mean
        /// (b) Median av fönstrens RMSSD.
        case median
        /// (c) Medel av de lugnaste fönstren (lägst medelpuls) i nattens sista tredjedel.
        case lateQuiet
        /// (d) Den Whoop-lika: medel av RMSSD i överlappande 5-minutersfönster
        /// med steg på 30 s över hela inspelningen, som Whoop beskriver sitt
        /// sätt 2025 (Whoop, ej verifierat) — utan Whoops viktning och utan att
        /// vaken tid plockas bort, eftersom Idunn saknar sömnstadier (METOD M8).
        case whoopLike
    }

    /// METOD M4. Nattens RMSSD-kandidater, var för sig, i millisekunder.
    public struct RMSSD: Equatable, Sendable {
        public var mean: Double?
        public var median: Double?
        public var lateQuiet: Double?
        public var whoopLike: Double?

        public init(mean: Double?, median: Double?, lateQuiet: Double?, whoopLike: Double?) {
            self.mean = mean
            self.median = median
            self.lateQuiet = lateQuiet
            self.whoopLike = whoopLike
        }

        public func value(_ c: Candidate) -> Double? {
            switch c {
            case .mean: return mean
            case .median: return median
            case .lateQuiet: return lateQuiet
            case .whoopLike: return whoopLike
            }
        }

        /// ln(RMSSD), som baslinjen räknar med (METOD M6).
        public func ln(_ c: Candidate) -> Double? {
            value(c).flatMap { $0 > 0 ? log($0) : nil }
        }
    }

    public struct Report: Equatable, Sendable {
        /// METOD M3. Andelen kastade slag, för de slag som räknats.
        public var cleaning: RRCleaning.Summary
        /// Första och sista slaget som räknats.
        public var start: Date?
        public var end: Date?
        public var windows: [Window]
        public var rmssd: RMSSD
        /// METOD M5 · BESLUT B76. 10:e percentilen av de giltiga fönstrens medelpuls (`restingPercentile`,
        /// `restingHeartRate(_:)`); `nil` utan giltigt fönster.
        public var restingHeartRate: Double?
        /// METOD M10. Median av fönstren med tydlig topp; `nil` om inget har det.
        public var breathsPerMinute: Double?
        /// BESLUT B34 · METOD M5. Medelpulsen över de giltiga fönstren: 60000 / (summan av de behållna
        /// intervallen / deras antal), alla giltiga fönster ihop. `nil` utan giltigt fönster.
        public var meanHeartRate: Double?

        public var validWindows: Int { windows.filter(\.isValid).count }
        /// METOD M10. Giltiga fönster där andningen gav en tydlig topp.
        public var clearBreathingWindows: Int {
            windows.filter { $0.breathing?.breathsPerMinute != nil }.count
        }

        /// Nattens punkt för baslinjen (METOD M6): uppvakningsdagen räknas ur
        /// sista slaget i telefonens zon, som appen skickar in. Förvalt är
        /// nattens medel (METOD M4, BESLUT B13).
        public func point(utcOffsetSeconds: Int, candidate: Candidate = .mean) -> NightPoint? {
            guard let e = end else { return nil }
            return NightPoint(day: WakeDay(e, utcOffsetSeconds: utcOffsetSeconds),
                              rmssd: rmssd.value(candidate),
                              restingHeartRate: restingHeartRate,
                              source: .idun)
        }
    }

    // MARK: Räkningen

    /// Rensar (METOD M3) och räknar natten. Med `within` räknas bara slag och
    /// skillnader vars tid ligger i intervallet; rensningens medianer tas ändå
    /// över hela natten, så att kanten inte beter sig annorlunda.
    public static func analyze(_ night: NightRecording, within interval: DateInterval? = nil) -> Report {
        analyze(beats: RRCleaning.clean(night), within: interval)
    }

    /// Samma räkning på slag som redan är rensade (`RRCleaning.clean`), så att
    /// nattens kurva (METOD M18) kan använda samma slag utan en rensning till.
    public static func analyze(beats alla: [Beat], within interval: DateInterval? = nil) -> Report {
        let inne: (TimeInterval) -> Bool = { t in
            interval.map { $0.contains(Date(timeIntervalSince1970: t)) } ?? true
        }
        let beats = alla.filter { inne($0.time) }
        let diffs = RRCleaning.differences(alla).filter { inne($0.time) }
        let summary = RRCleaning.summary(beats)

        guard let first = beats.map(\.time).min(), let last = beats.map(\.time).max() else {
            return Report(cleaning: summary, start: nil, end: nil, windows: [],
                          rmssd: RMSSD(mean: nil, median: nil, lateQuiet: nil, whoopLike: nil),
                          restingHeartRate: nil, breathsPerMinute: nil, meanHeartRate: nil)
        }

        // METOD M4. Fönstren börjar vid första slaget och följer varandra utan
        // överlapp. Ett slag och en skillnad hör till fönstret där deras tid ligger.
        let count = Int(((last - first) / windowSeconds).rounded(.down)) + 1
        func index(_ t: TimeInterval) -> Int {
            min(count - 1, max(0, Int(((t - first) / windowSeconds).rounded(.down))))
        }
        var alls = [Int](repeating: 0, count: count)
        var behållna = [[Beat]](repeating: [], count: count)
        var skillnader = [[Double]](repeating: [], count: count)
        for b in beats {
            let k = index(b.time)
            alls[k] += 1
            if b.isKept { behållna[k].append(b) }
        }
        for d in diffs { skillnader[index(d.time)].append(d.milliseconds) }

        var windows: [Window] = []
        // BESLUT B34. Summan av de behållna intervallen per fönster, vänster till höger, och totalen i fönstrens ordning.
        var rrSums = [Double](repeating: 0, count: count)
        for k in 0..<count {
            var w = Window(start: Date(timeIntervalSince1970: first + Double(k) * windowSeconds),
                           beats: alls[k], keptBeats: behållna[k].count,
                           differences: skillnader[k].count,
                           rmssd: nil, meanHeartRate: nil, breathing: nil)
            if skillnader[k].count >= minDifferencesPerWindow {
                let ss = skillnader[k].reduce(0.0) { (a: Double, d: Double) -> Double in a + d * d }
                w.rmssd = (ss / Double(skillnader[k].count)).squareRoot()
                let rr = behållna[k].map(\.rrMilliseconds)
                var summa: Double = 0
                for x in rr { summa += x }
                rrSums[k] = summa
                w.meanHeartRate = Statistics.mean(rr).map { 60_000 / $0 }
                w.breathing = Breathing.estimate(times: behållna[k].map(\.time), rrMilliseconds: rr)
            }
            windows.append(w)
        }

        let giltiga = windows.filter(\.isValid)
        let värden = giltiga.compactMap(\.rmssd)

        // BESLUT B34. Medelpulsen över periodens giltiga fönster: alla deras behållna intervall ihop.
        var antalRR: Int = 0
        var totalRR: Double = 0
        for k in 0..<count where windows[k].isValid {
            antalRR += windows[k].keptBeats
            totalRR += rrSums[k]
        }
        let medelpuls: Double? = antalRR > 0 ? 60_000 / (totalRR / Double(antalRR)) : nil

        // METOD M4, kandidat (c): fönster vars mitt ligger i sista tredjedelen,
        // de med lägst medelpuls först; vid lika vinner det tidigare.
        let sen = first + (last - first) * lateStartFraction
        let lugna = giltiga
            .filter { $0.start.timeIntervalSince1970 + windowSeconds / 2 >= sen }
            .sorted { ($0.meanHeartRate ?? .infinity, $0.start) < ($1.meanHeartRate ?? .infinity, $1.start) }
            .prefix(lateQuietWindows)

        return Report(
            cleaning: summary,
            start: Date(timeIntervalSince1970: first),
            end: Date(timeIntervalSince1970: last),
            windows: windows,
            rmssd: RMSSD(mean: Statistics.mean(värden),
                         median: Statistics.median(värden),
                         lateQuiet: Statistics.mean(lugna.compactMap(\.rmssd)),
                         whoopLike: Statistics.mean(slidingRMSSD(diffs, first: first, last: last))),
            restingHeartRate: NightAnalysis.restingHeartRate(giltiga.compactMap(\.meanHeartRate)),
            breathsPerMinute: Statistics.median(windows.compactMap { $0.breathing?.breathsPerMinute }),
            meanHeartRate: medelpuls
        )
    }

    /// METOD M5 · BESLUT B76. Vilopulsen ur fönstrens medelpuls: percentilen `restingPercentile` med linjär
    /// interpolation mellan rangerna (h = (n − 1) · p i den sorterade listan, som numpy:s och R:s förval, samma som
    /// `SleepDetection.percentile`). Med ett fönster är det fönstret, med 2–10 ligger den mellan det lägsta och det
    /// näst lägsta, och från 11 fönster väger det lägsta inte in. Ingen nedre gräns för antalet: `nil` utan fönster.
    public static func restingHeartRate(_ windowHeartRates: [Double]) -> Double? {
        guard !windowHeartRates.isEmpty else { return nil }
        return SleepDetection.percentile(windowHeartRates, restingPercentile)
    }

    /// METOD M4, kandidat (d). RMSSD i hela 5-minutersfönster som börjar vid
    /// första slaget och sedan var `slidingStepSeconds`, så länge fönstret
    /// ryms före sista slaget (minst ett fönster, även en kort natt). En
    /// skillnad hör till varje fönster där dess tid ligger, och ett fönster
    /// räknas bara med minst `minDifferencesPerWindow` skillnader, som de
    /// vanliga fönstren.
    static func slidingRMSSD(_ diffs: [RRCleaning.Difference],
                             first: TimeInterval, last: TimeInterval) -> [Double] {
        let d = diffs.sorted { $0.time < $1.time }
        // Löpande summa av kvadraterna: fönstrets summa är en skillnad mellan två.
        var summa: [Double] = [0]
        summa.reserveCapacity(d.count + 1)
        for x in d {
            let kvadrat: Double = x.milliseconds * x.milliseconds
            summa.append(summa[summa.count - 1] + kvadrat)
        }
        let steg: Double = ((last - first - windowSeconds) / slidingStepSeconds).rounded(.down)
        let antal: Int = max(0, Int(steg)) + 1
        var ut: [Double] = []
        var lo = 0
        var hi = 0
        for k in 0..<antal {
            let start: TimeInterval = first + Double(k) * slidingStepSeconds
            let slut: TimeInterval = start + windowSeconds
            while lo < d.count && d[lo].time < start { lo += 1 }
            while hi < d.count && d[hi].time < slut { hi += 1 }
            let n: Int = hi - lo
            guard n >= minDifferencesPerWindow else { continue }
            let medel: Double = (summa[hi] - summa[lo]) / Double(n)
            ut.append(max(0, medel).squareRoot())
        }
        return ut
    }
}
