import Foundation

/// METOD M13 · BESLUT B3
/// Duger natten? Glappen och RR-intervallens tre kontroller ur PLAN.md I2, som
/// rena funktioner över en inspelning. Resultaten bär bara andelar, kvoter och
/// antal — aldrig en puls eller ett intervall — så att en rapport går att
/// klistra in i en Claude-session utan att hälsodata följer med.
///
/// Kontroll 2 och 3 är desamma som i `tools/kolla_rr.py` och ska bete sig
/// likadant: samma rensning (300–2000 ms), samma trösklar för "samma värde"
/// och "litet steg", samma glidande medel och samma kvot.
public enum RecordingQuality {

    // MARK: Gränserna — METOD M13

    /// METOD M13. Ingen notis på mer än så här lång tid räknas som ett glapp.
    public static let gapSeconds: TimeInterval = 60
    /// METOD M13. Glappen tillsammans får vara högst så här stor del av natten.
    public static let maxGapFraction = 0.05
    /// METOD M13. En minut är fullständig när antalet RR ligger så här nära pulsen.
    public static let coverageTolerance = 0.05
    /// METOD M13. Så stor del av minuterna ska vara fullständiga.
    public static let minCoveredFraction = 0.90
    /// METOD M13. Högst så stor del av RR får vara lika med 60000/puls.
    public static let maxComputedFraction = 0.05
    /// METOD M13. Högst så stor del av stegen får ha samma värde som förra slaget.
    public static let maxIdenticalFraction = 0.05
    /// METOD M13. Steg under 0,5 ms är "samma värde" (upplösningen är 0,977 ms),
    /// steg under 2 ms är "litet".
    public static let identicalStepMilliseconds = 0.5
    public static let smallStepMilliseconds = 2.0
    /// METOD M13. Längden på det glidande medlet i kontroll 3.
    public static let smoothingWindow = 5
    /// METOD M13. RMSSD-kvoten medelkurva/rådata ska vara under detta.
    public static let maxSmoothingRatio = 0.6
    /// METOD M13. Färre intervall än så ger ingen bedömning (samma som kolla_rr).
    public static let minIntervals = 60
    /// METOD M3. Intervall utanför 300–2000 ms (30–200 slag/min) räknas inte.
    public static let plausibleRR: ClosedRange<Double> = 300...2000
    /// METOD M15. Två RR räknas som samma slag om de skiljer högst så här
    /// många steg i bandets enhet (1/1024 s).
    public static let repeatToleranceUnits = 1

    // MARK: Resultaten

    /// Glappen: tider utan en enda notis i mer än `gapSeconds`.
    public struct Gaps: Equatable, Sendable {
        public var count: Int
        public var total: TimeInterval
        public var longest: TimeInterval
        /// Glappens del av tiden från första till sista notisen.
        public var fraction: Double
        public var passes: Bool { fraction < RecordingQuality.maxGapFraction }
    }

    /// Kontroll 1, varje slag kommer med.
    public struct Coverage: Equatable, Sendable {
        /// Hela minuter inne i natten som har minst en notis. Minuter helt
        /// utan notis är glapp och räknas där, inte här.
        public var minutes: Int
        /// Andelen av dem där antalet RR ligger inom `coverageTolerance` av
        /// minutens medelpuls.
        public var fractionComplete: Double
        public var passes: Bool { fractionComplete >= RecordingQuality.minCoveredFraction }
    }

    /// Kontroll 2, intervallen är mätta och inte uträknade ur pulsen.
    public struct Computed: Equatable, Sendable {
        public var intervals: Int
        /// Andelen RR som är exakt 60000/puls avrundat till 1/1024 s, mot
        /// pulsen i samma notis.
        public var fractionEqualToBpm: Double
        /// Andelen steg där intervallet har samma värde som förra slaget.
        public var fractionIdentical: Double
        /// Andelen steg under 2 ms. Visas, men fäller inte (som i kolla_rr).
        public var fractionSmallSteps: Double
        public var passes: Bool {
            fractionEqualToBpm <= RecordingQuality.maxComputedFraction
                && fractionIdentical < RecordingQuality.maxIdenticalFraction
        }
    }

    /// Kontroll 3, intervallen är inte utjämnade.
    public struct Smoothing: Equatable, Sendable {
        public var intervals: Int
        /// RMSSD för ett glidande medel genom intervallen delat med RMSSD för
        /// intervallen själva. Nära 1 betyder att de redan är utjämnade.
        public var ratio: Double
        public var passes: Bool { ratio < RecordingQuality.maxSmoothingRatio }
    }

    /// Allt på en gång. En kontroll som saknar underlag är `nil` och fäller natten.
    public struct Report: Equatable, Sendable, CustomStringConvertible {
        public var gaps: Gaps?
        public var coverage: Coverage?
        public var computed: Computed?
        public var smoothing: Smoothing?

        public var passes: Bool {
            (gaps?.passes ?? false) && (coverage?.passes ?? false)
                && (computed?.passes ?? false) && (smoothing?.passes ?? false)
        }

        /// BESLUT B3. Bara andelar, kvoter och antal.
        public var description: String {
            var rader: [String] = []
            if let g = gaps {
                rader.append("glapp: \(g.count) st, \(procent(g.fraction)) av natten (gräns \(procent(RecordingQuality.maxGapFraction)))")
            } else {
                rader.append("glapp: för lite data")
            }
            if let c = coverage {
                rader.append("1. varje slag med: \(procent(c.fractionComplete)) av \(c.minutes) minuter (krav \(procent(RecordingQuality.minCoveredFraction)))")
            } else {
                rader.append("1. varje slag med: för lite data")
            }
            if let c = computed {
                rader.append("2. lika med 60000/puls: \(procent(c.fractionEqualToBpm)) (gräns \(procent(RecordingQuality.maxComputedFraction)))")
                rader.append("   samma värde som förra slaget: \(procent(c.fractionIdentical)) (gräns \(procent(RecordingQuality.maxIdenticalFraction)))")
                rader.append("   steg under 2 ms: \(procent(c.fractionSmallSteps))")
            } else {
                rader.append("2. mätta, inte uträknade: för lite data")
            }
            if let s = smoothing {
                rader.append("3. RMSSD-kvot medelkurva/rådata: \(String(format: "%.2f", s.ratio)) (gräns \(String(format: "%.1f", RecordingQuality.maxSmoothingRatio)))")
            } else {
                rader.append("3. inte utjämnade: för lite data")
            }
            rader.append(passes ? "RIMLIGT: natten duger" : "MISSTÄNKT: minst en kontroll fäller natten")
            return rader.joined(separator: "\n")
        }

        private func procent(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }
    }

    /// METOD M15 · BESLUT B3. Varför en kontroll fäller: hur RR kommer i
    /// notiserna. Bara andelar, kvoter och antal — ingen puls, inget intervall
    /// och ingen tid — så att diagnosen går att skärmdumpa.
    public struct Diagnostics: Equatable, Sendable, CustomStringConvertible {
        public var notifications: Int
        /// Andelen notiser med 0, 1, 2 och 3 eller fler RR, i den ordningen.
        public var rrPerNotification: [Double]

        /// Par: en notis med RR och den senaste tidigare notisen med RR, utan
        /// glapp emellan. Andelarna nedan är av paren.
        public var pairs: Int
        /// Notisens första RR är förra notisens sista: bandet upprepar slaget.
        public var firstRepeatsPreviousLast: Double
        /// Notisens sista RR är förra notisens första: upprepning med det
        /// senaste slaget först (omvänd ordning).
        public var lastRepeatsPreviousFirst: Double
        /// Notisens första RR är förra notisens första: ett fält som står still
        /// eller kryper, alltså troligen inget RR (tolkningen läser fel fält).
        public var firstRepeatsPreviousFirst: Double
        /// Något RR i notisen är samma som något i förra, var de än står.
        public var sharesAnyWithPrevious: Double

        /// Flaggbyten (METOD M1) och andelen notiser som bar den, vanligast
        /// först. Notiser utan sparad flagga (äldre filer) räknas inte.
        public var flags: [FlagShare]

        /// Hela minuter med puls, som i kontroll 1.
        public var minutes: Int
        /// Median per minut: antal RR delat med medelpulsen. 1 när varje slag kommer med.
        public var countToBpm: Double?
        /// Andelen minuter där kvoten är under 0,95 respektive över 1,05.
        public var minutesBelow: Double
        public var minutesAbove: Double
        /// Median per minut: pulsen som intervallen själva ger (60000 / medel-RR)
        /// delad med bandets puls. 1 när värdena stämmer, även om antalet inte gör det.
        public var rrRateToBpm: Double?
        /// Median per minut: antal notiser delat med medelpulsen. Nära 1 om
        /// bandet sänder en notis per slag.
        public var notificationsToBpm: Double?

        /// Median per notis: summan av notisens RR delad med tiden sedan förra notisen.
        public var rrTimeToElapsedMedian: Double?
        /// Hela nattens summa av RR delad med tiden mellan notiserna (glappen
        /// och avsnittens första notis oräknade). 1 när intervallen fyller tiden.
        public var rrTimeToElapsed: Double?

        public struct FlagShare: Equatable, Sendable {
            public var flags: UInt8
            public var share: Double
        }

        /// BESLUT B3. Bara andelar och kvoter.
        public var description: String {
            func p(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }
            func k(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "–" }
            let delar: [String] = flags.map { (f: FlagShare) -> String in
                let hex: String = String(f.flags, radix: 16)
                return "0x\(hex) \(p(f.share))"
            }
            let flaggor: String = delar.isEmpty ? "–" : delar.joined(separator: " · ")
            let rader: [String] = [
                "notiser med 0/1/2/3+ RR: " + rrPerNotification.map(p).joined(separator: " · "),
                "upprepat slag (första = förra sista): \(p(firstRepeatsPreviousLast))",
                "upprepat omvänt (sista = förra första): \(p(lastRepeatsPreviousFirst))",
                "första = förra första: \(p(firstRepeatsPreviousFirst))",
                "något RR som i förra notisen: \(p(sharesAnyWithPrevious))",
                "flaggor: " + flaggor,
                "RR per minut / puls: \(k(countToBpm)) (under \(p(minutesBelow)), över \(p(minutesAbove)) av minuterna)",
                "puls ur RR / puls: \(k(rrRateToBpm))",
                "notiser per minut / puls: \(k(notificationsToBpm))",
                "RR-tid / klocktid: \(k(rrTimeToElapsed)) (median per notis \(k(rrTimeToElapsedMedian)))",
            ]
            return rader.joined(separator: "\n")
        }
    }

    // MARK: Kontrollerna

    public static func report(_ night: NightRecording) -> Report {
        Report(gaps: gaps(night), coverage: coverage(night),
               computed: computed(night), smoothing: smoothing(night))
    }

    /// METOD M13. `nil` med färre än två notiser.
    public static func gaps(_ night: NightRecording) -> Gaps? {
        let s = ordered(night)
        guard s.count >= 2 else { return nil }
        let span = s[s.count - 1].time.timeIntervalSince(s[0].time)
        guard span > 0 else { return nil }
        var count = 0
        var total: TimeInterval = 0
        var longest: TimeInterval = 0
        for (a, b) in zip(s, s.dropFirst()) {
            let d = b.time.timeIntervalSince(a.time)
            if d > gapSeconds {
                count += 1
                total += d
                longest = max(longest, d)
            }
        }
        return Gaps(count: count, total: total, longest: longest, fraction: total / span)
    }

    /// METOD M13. Kontroll 1. Minuterna följer klockan (hela minuter sedan
    /// 1970), och bara minuter helt inne i natten räknas, så att den första
    /// och sista halva minuten inte fäller natten. `nil` utan en enda sådan minut.
    public static func coverage(_ night: NightRecording) -> Coverage? {
        let ms = minutes(night)
        guard !ms.isEmpty else { return nil }
        // En minut med puls 0 (ingen kontakt) är inte fullständig.
        let complete = ms.filter { m in
            m.bpm > 0 && abs(Double(m.rr) - m.bpm) <= coverageTolerance * m.bpm
        }.count
        return Coverage(minutes: ms.count, fractionComplete: Double(complete) / Double(ms.count))
    }

    /// En hel minut inne i natten med minst en notis: antal RR, deras summa
    /// (bara 300–2000 ms), antal notiser och medelpulsen över notiserna.
    struct Minute: Equatable {
        var rr = 0
        var plausibleRR = 0
        var plausibleSum = 0.0
        var notifications = 0
        var bpmSum = 0
        var bpm: Double { notifications > 0 ? Double(bpmSum) / Double(notifications) : 0 }
    }

    /// METOD M13. Minuterna som kontroll 1 och diagnosen (METOD M15) räknar:
    /// RR räknas till minuten där notisen kom. Minuter helt utan notis är glapp
    /// och saknas här.
    static func minutes(_ night: NightRecording) -> [Minute] {
        let s = ordered(night)
        guard let first = s.first?.time.timeIntervalSince1970,
              let last = s.last?.time.timeIntervalSince1970 else { return [] }

        var per: [Int: Minute] = [:]
        for x in s {
            let m = Int((x.time.timeIntervalSince1970 / 60).rounded(.down))
            var v = per[m] ?? Minute()
            v.rr += x.rrMilliseconds.count
            for r in x.rrMilliseconds where plausibleRR.contains(r) {
                v.plausibleRR += 1
                v.plausibleSum += r
            }
            v.notifications += 1
            v.bpmSum += x.bpm
            per[m] = v
        }

        let firstMinute = Int((first / 60).rounded(.up))
        let endMinute = Int((last / 60).rounded(.down))
        guard firstMinute < endMinute else { return [] }
        return (firstMinute..<endMinute).compactMap { per[$0] }
    }

    /// METOD M13. Kontroll 2. Ett band som räknar fram RR ur en heltalspuls ger
    /// intervall som är exakt 61440/puls i bandets enhet, och långa rader av
    /// samma värde. `nil` med färre än `minIntervals` intervall.
    public static func computed(_ night: NightRecording) -> Computed? {
        var intervals = 0
        var equal = 0
        for x in ordered(night) where x.bpm > 0 {
            // METOD M1: 60000 ms / puls i enheten 1/1024 s = 61440 / puls.
            let uträknat = Int((61_440 / Double(x.bpm)).rounded())
            for r in x.rrMilliseconds where plausibleRR.contains(r) {
                intervals += 1
                if HeartRateMeasurement.rrUnits(milliseconds: r) == uträknat { equal += 1 }
            }
        }
        let steg = segments(night).flatMap { seg in zip(seg, seg.dropFirst()).map { abs($0.1 - $0.0) } }
        guard intervals >= minIntervals, !steg.isEmpty else { return nil }
        let n = Double(steg.count)
        return Computed(
            intervals: intervals,
            fractionEqualToBpm: Double(equal) / Double(intervals),
            fractionIdentical: Double(steg.filter { $0 < identicalStepMilliseconds }.count) / n,
            fractionSmallSteps: Double(steg.filter { $0 < smallStepMilliseconds }.count) / n
        )
    }

    /// METOD M13. Kontroll 3. RMSSD räknas per obrutet avsnitt (glappen bryter
    /// slagföljden) och vägs ihop över alla steg. `nil` med färre än
    /// `minIntervals` intervall.
    public static func smoothing(_ night: NightRecording) -> Smoothing? {
        let segs = segments(night)
        let intervals = segs.reduce(0) { $0 + $1.count }
        guard intervals >= minIntervals, let rå = rmssd(segs) else { return nil }
        let medel = segs.map { movingAverage($0, window: smoothingWindow) }
        // Som i kolla_rr: helt platta intervall räknas som utjämnade.
        let ratio = rå > 0 ? (rmssd(medel) ?? 0) / rå : 1
        return Smoothing(intervals: intervals, ratio: ratio)
    }

    /// METOD M15. Diagnosen: hur RR kommer i notiserna. Räknas alltid, även
    /// på en kort inspelning; ett mått utan underlag är `nil` eller 0.
    public static func diagnostics(_ night: NightRecording) -> Diagnostics {
        let s = ordered(night)

        // Antal RR per notis.
        var perCount = [0, 0, 0, 0]
        for x in s { perCount[min(x.rrMilliseconds.count, 3)] += 1 }
        let n = s.count
        let rrPerNotification: [Double] = perCount.map { (c: Int) -> Double in
            n > 0 ? Double(c) / Double(n) : 0
        }

        // Upprepningar mot den senaste notisen med RR, och RR-tid mot klocktid.
        var pairs = 0
        var firstLast = 0
        var lastFirst = 0
        var firstFirst = 0
        var any = 0
        var ratios: [Double] = []
        var rrSeconds = 0.0
        var elapsed = 0.0
        var previousRR: [Int]?
        var previousTime: Date?
        for x in s {
            if let t = previousTime {
                let d: TimeInterval = x.time.timeIntervalSince(t)
                if d > gapSeconds {
                    previousRR = nil
                } else if d > 0 {
                    let sum: Double = x.rrMilliseconds.reduce(0, +) / 1000
                    ratios.append(sum / d)
                    rrSeconds += sum
                    elapsed += d
                }
            }
            previousTime = x.time

            let units: [Int] = x.rrMilliseconds.map { HeartRateMeasurement.rrUnits(milliseconds: $0) }
            guard let first = units.first, let last = units.last else { continue }
            if let p = previousRR, let pFirst = p.first, let pLast = p.last {
                pairs += 1
                if same(first, pLast) { firstLast += 1 }
                if same(last, pFirst) { lastFirst += 1 }
                if same(first, pFirst) { firstFirst += 1 }
                if units.contains(where: { (u: Int) -> Bool in p.contains { same(u, $0) } }) { any += 1 }
            }
            previousRR = units
        }
        func share(_ c: Int) -> Double { pairs > 0 ? Double(c) / Double(pairs) : 0 }

        // Flaggbyten.
        var perFlags: [UInt8: Int] = [:]
        for x in s { if let f = x.flags { perFlags[f, default: 0] += 1 } }
        let medFlagga = perFlags.values.reduce(0, +)
        let flags: [Diagnostics.FlagShare] = perFlags
            .map { Diagnostics.FlagShare(flags: $0.key, share: Double($0.value) / Double(medFlagga)) }
            .sorted { $0.share != $1.share ? $0.share > $1.share : $0.flags < $1.flags }

        // Minuterna, som i kontroll 1.
        let ms = minutes(night).filter { $0.bpm > 0 }
        let count: [Double] = ms.map { (m: Minute) -> Double in Double(m.rr) / m.bpm }
        let rate: [Double] = ms.compactMap { (m: Minute) -> Double? in
            guard m.plausibleRR > 0 else { return nil }
            let medel: Double = m.plausibleSum / Double(m.plausibleRR)
            return 60_000 / medel / m.bpm
        }
        let notes: [Double] = ms.map { (m: Minute) -> Double in Double(m.notifications) / m.bpm }
        let below = count.filter { $0 < 1 - coverageTolerance }.count
        let above = count.filter { $0 > 1 + coverageTolerance }.count
        let mc = Double(max(count.count, 1))

        return Diagnostics(
            notifications: n,
            rrPerNotification: rrPerNotification,
            pairs: pairs,
            firstRepeatsPreviousLast: share(firstLast),
            lastRepeatsPreviousFirst: share(lastFirst),
            firstRepeatsPreviousFirst: share(firstFirst),
            sharesAnyWithPrevious: share(any),
            flags: flags,
            minutes: ms.count,
            countToBpm: median(count),
            minutesBelow: Double(below) / mc,
            minutesAbove: Double(above) / mc,
            rrRateToBpm: median(rate),
            notificationsToBpm: median(notes),
            rrTimeToElapsedMedian: median(ratios),
            rrTimeToElapsed: elapsed > 0 ? rrSeconds / elapsed : nil
        )
    }

    /// METOD M15. Samma slag: högst `repeatToleranceUnits` steg isär.
    static func same(_ a: Int, _ b: Int) -> Bool { abs(a - b) <= repeatToleranceUnits }

    /// Mittvärdet; med jämnt antal medel av de två i mitten.
    static func median(_ x: [Double]) -> Double? {
        guard !x.isEmpty else { return nil }
        let v = x.sorted()
        let m = v.count / 2
        return v.count % 2 == 1 ? v[m] : (v[m - 1] + v[m]) / 2
    }

    // MARK: Hjälp

    /// Notiserna i tidsordning. En avkodad inspelning har inte gått genom
    /// `NightRecording.init`, så ordningen kontrolleras här också.
    static func ordered(_ night: NightRecording) -> [HeartRateSample] {
        let s = night.samples
        return zip(s, s.dropFirst()).allSatisfy { $0.0.time <= $0.1.time } ? s : s.sorted { $0.time < $1.time }
    }

    /// Nattens RR som obrutna avsnitt, rensade till `plausibleRR`. Ett glapp
    /// (`gapSeconds`) börjar ett nytt avsnitt, så att ingen skillnad räknas
    /// mellan två slag med minuter emellan.
    static func segments(_ night: NightRecording) -> [[Double]] {
        var out: [[Double]] = []
        var current: [Double] = []
        var previous: Date?
        for x in ordered(night) {
            if let p = previous, x.time.timeIntervalSince(p) > gapSeconds, !current.isEmpty {
                out.append(current)
                current = []
            }
            current.append(contentsOf: x.rrMilliseconds.filter { plausibleRR.contains($0) })
            previous = x.time
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// METOD M4. RMSSD över alla steg i alla avsnitt. `nil` utan ett enda steg.
    static func rmssd(_ segments: [[Double]]) -> Double? {
        var sum = 0.0
        var n = 0
        for seg in segments {
            for (a, b) in zip(seg, seg.dropFirst()) {
                sum += (b - a) * (b - a)
                n += 1
            }
        }
        return n > 0 ? (sum / Double(n)).squareRoot() : nil
    }

    /// Glidande medel utan utfyllnad: n − window + 1 värden, som kolla_rr.
    static func movingAverage(_ x: [Double], window k: Int) -> [Double] {
        guard k > 0, x.count >= k else { return [] }
        // Summan räknas om för varje fönster i stället för att löpa, så att
        // talen blir desamma som i kolla_rr ända ut i sista decimalen.
        return (0...(x.count - k)).map { i in x[i..<(i + k)].reduce(0, +) / Double(k) }
    }
}
