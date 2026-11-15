import Foundation
import HeartRate

/// METOD M3
/// Ett slag ur nattens RR-serie: när det slog, hur långt intervallet var, och
/// om det överlevde rensningen. Ett kastat slag finns kvar i serien med sitt
/// utslag, så att andelen kastade går att visa och tidsaxeln inte hoppar.
public struct Beat: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case kept
        /// Utanför 300–2000 ms.
        case outOfRange
        /// Mer än 20 % från den lokala medianen.
        case deviatesFromMedian
    }

    /// När intervallet tog slut, sekunder sedan 1970 (se `RRCleaning.beats`).
    public var time: TimeInterval
    public var rrMilliseconds: Double
    /// Obrutet avsnitt: ett glapp på mer än 60 s (METOD M13) börjar ett nytt,
    /// och ingen skillnad räknas över det.
    public var segment: Int
    public var verdict: Verdict
    /// METOD M15. Ett kastat slag som var för långt: över 2000 ms, eller över
    /// den lokala medianen. Annars för kort (eller behållet).
    public var tooLong: Bool
    /// METOD M15. Notisen slaget kom i, räknat i nattens ordning.
    public var notification: Int
    /// METOD M3 · METOD M15. Notisens slag lades om till notisens tid, för att
    /// klockan av intervall låg mer än 3 s fel. Inget slag kastas av det.
    public var reanchored: Bool
    /// METOD M3. Så många slag har bandet utelämnat närmast före det här,
    /// enligt den valda förklaringen av notisernas tider (`Omissions`).
    public var omittedBefore: Int
    /// METOD M3. Ett utelämnat slag kan ligga mellan det här slaget och förra,
    /// i den valda eller i en lika god förklaring: ingen skillnad räknas här.
    public var gapBefore: Bool

    public init(time: TimeInterval, rrMilliseconds: Double, segment: Int, verdict: Verdict = .kept,
                tooLong: Bool = false, notification: Int = 0, reanchored: Bool = false,
                omittedBefore: Int = 0, gapBefore: Bool = false) {
        self.time = time
        self.rrMilliseconds = rrMilliseconds
        self.segment = segment
        self.verdict = verdict
        self.tooLong = tooLong
        self.notification = notification
        self.reanchored = reanchored
        self.omittedBefore = omittedBefore
        self.gapBefore = gapBefore
    }

    public var isKept: Bool { verdict == .kept }
}

/// METOD M3 · METOD M13
/// Rensningen av nattens RR-intervall, före all HRV. Två steg: intervall
/// utanför 300–2000 ms kastas, och sedan slag som avviker mer än 20 % från den
/// lokala medianen (20 %-filtret, Malik m.fl. 1989). Skillnader mellan slag
/// räknas bara mellan två grannar som båda överlevt, inom samma avsnitt, och
/// aldrig över ett slag som bandet utelämnat (`Omissions`).
public enum RRCleaning {

    // MARK: Gränserna — METOD M3

    /// METOD M3. 300–2000 ms (30–200 slag/min), samma gräns som nattens kontroller.
    public static let plausibleRR: ClosedRange<Double> = RecordingQuality.plausibleRR
    /// METOD M3. Ett slag som avviker mer än så här från den lokala medianen kastas.
    public static let maxDeviation = 0.20
    /// METOD M3. Medianen tas över så här många giltiga slag på var sida, i samma
    /// avsnitt och utan slaget självt: 5 före och 5 efter, upp till 10 grannar.
    public static let medianNeighbours = 5
    /// METOD M3. Ligger slagens egen klocka mer än så här långt från notisens tid
    /// flyttas notisens slag till notisens tid.
    public static let reanchorSeconds: TimeInterval = 3
    /// METOD M13. Samma glappgräns som kontrollerna: över den börjar ett nytt avsnitt.
    public static let gapSeconds: TimeInterval = RecordingQuality.gapSeconds

    // MARK: Resultaten

    /// Andelen kastade slag, som visas i nattrapporten (METOD M3), och varför
    /// de kastades (METOD M15). Bara antal.
    public struct Summary: Equatable, Sendable {
        public var beats: Int
        /// Under 300 ms respektive över 2000 ms.
        public var outOfRangeShort: Int
        public var outOfRangeLong: Int
        /// Mer än 20 % under respektive över den lokala medianen.
        public var deviatingShort: Int
        public var deviatingLong: Int
        /// METOD M15. Notiser med minst ett slag.
        public var notifications: Int
        /// METOD M3 · METOD M15. Notiser vars slag lades om till notisens tid.
        public var reanchorings: Int
        /// Obrutna avsnitt (METOD M13): ett glapp på över 60 s börjar ett nytt.
        public var segments: Int
        /// METOD M3 · METOD M15. Slag som bandet utelämnat, skattade ur
        /// notisernas tider. De finns inte bland `beats`.
        public var omitted: Int = 0

        public var outOfRange: Int { outOfRangeShort + outOfRangeLong }
        public var deviating: Int { deviatingShort + deviatingLong }
        public var dropped: Int { outOfRange + deviating }
        public var fractionDropped: Double { share(dropped) }
        /// Andelen av alla slag.
        public func share(_ count: Int) -> Double { beats > 0 ? Double(count) / Double(beats) : 0 }
        /// METOD M15. Andelen notiser med slag som lades om.
        public var fractionReanchored: Double {
            notifications > 0 ? Double(reanchorings) / Double(notifications) : 0
        }
        /// METOD M3 · METOD M15. Andelen utelämnade av alla slag som slog:
        /// de som kom och de som fattas.
        public var fractionOmitted: Double {
            beats + omitted > 0 ? Double(omitted) / Double(beats + omitted) : 0
        }
    }

    /// En skillnad mellan två på varandra följande slag som båda överlevt.
    /// Tiden är det senare slagets, så att skillnaden hamnar i det fönster där
    /// den blev klar (METOD M4).
    public struct Difference: Equatable, Sendable {
        public var time: TimeInterval
        public var milliseconds: Double
    }

    // MARK: Rensningen

    /// METOD M3. Nattens slag med tid och utslag, i den ordning de kom.
    public static func clean(_ night: NightRecording) -> [Beat] {
        let samples = ordered(night)
        var beats = timedBeats(samples)
        // METOD M3. Utelämnade slag, ur notisernas tider. Slagen räknas i samma
        // ordning som i timedBeats.
        let luckor = Omissions.detect(samples)
        for i in beats.indices where i < luckor.omittedBefore.count {
            beats[i].omittedBefore = luckor.omittedBefore[i]
            beats[i].gapBefore = luckor.gapBefore[i]
        }
        for i in beats.indices where !plausibleRR.contains(beats[i].rrMilliseconds) {
            beats[i].verdict = .outOfRange
            beats[i].tooLong = beats[i].rrMilliseconds > plausibleRR.upperBound
        }
        var start = 0
        while start < beats.count {
            var end = start
            while end < beats.count && beats[end].segment == beats[start].segment { end += 1 }
            // Medianen tas över de giltiga slagen i avsnittet, före 20 %-steget,
            // så att ett kastat slag aldrig flyttar en grannes median. Medianen
            // tål att fyra av tio grannar är artefakter.
            let valid = (start..<end).filter { beats[$0].verdict == .kept }
            let values = valid.map { beats[$0].rrMilliseconds }
            var deviating: [(index: Int, long: Bool)] = []
            for (p, i) in valid.enumerated() {
                let lo = max(0, p - medianNeighbours)
                let hi = min(values.count - 1, p + medianNeighbours)
                var grannar: [Double] = []
                for q in lo...hi where q != p { grannar.append(values[q]) }
                guard let m = Statistics.median(grannar) else { continue }
                if abs(values[p] - m) > maxDeviation * m { deviating.append((i, values[p] > m)) }
            }
            for d in deviating {
                beats[d.index].verdict = .deviatesFromMedian
                beats[d.index].tooLong = d.long
            }
            start = end
        }
        return beats
    }

    public static func summary(_ beats: [Beat]) -> Summary {
        func count(_ v: Beat.Verdict, long: Bool) -> Int {
            beats.filter { $0.verdict == v && $0.tooLong == long }.count
        }
        return Summary(beats: beats.count,
                       outOfRangeShort: count(.outOfRange, long: false),
                       outOfRangeLong: count(.outOfRange, long: true),
                       deviatingShort: count(.deviatesFromMedian, long: false),
                       deviatingLong: count(.deviatesFromMedian, long: true),
                       notifications: Set(beats.map(\.notification)).count,
                       reanchorings: Set(beats.filter(\.reanchored).map(\.notification)).count,
                       segments: Set(beats.map(\.segment)).count,
                       omitted: beats.reduce(0) { (n: Int, b: Beat) -> Int in n + b.omittedBefore })
    }

    /// METOD M3 · METOD M4. Skillnaderna mellan grannar i serien där båda
    /// slagen överlevt och inget glapp ligger emellan. Ett kastat slag tar
    /// alltså bort två skillnader, och ingen skillnad räknas över det. Inte
    /// heller över ett slag som bandet utelämnat: de två intervallen runt
    /// luckan är inte grannar (Task Force s. 358, "adjacent NN intervals").
    public static func differences(_ beats: [Beat]) -> [Difference] {
        var out: [Difference] = []
        for i in beats.indices.dropFirst() {
            let a = beats[i - 1]
            let b = beats[i]
            guard a.segment == b.segment, a.isKept, b.isKept, !b.gapBefore else { continue }
            out.append(Difference(time: b.time, milliseconds: b.rrMilliseconds - a.rrMilliseconds))
        }
        return out
    }

    // MARK: Slagens tid

    /// METOD M3. Notisen bär inte slagens tider, bara att de blev klara före
    /// notisen. Inom ett avsnitt läggs slagen därför ut med intervallen själva
    /// som klocka (summan av RR), med början så att första notisens sista slag
    /// hamnar på notisens tid. Notistiden skakar med radion, men intervallen
    /// gör det inte, och andningens spektrum (METOD M10) kräver en jämn axel.
    ///
    /// Tappar bandet slag halkar klockan efter. Ligger den mer än
    /// `reanchorSeconds` från notisens tid läggs notisens slag om så att det
    /// sista hamnar på notisens tid, och klockan fortsätter därifrån.
    static func timedBeats(_ ordered: [HeartRateSample]) -> [Beat] {
        var beats: [Beat] = []
        var segment = -1
        var previous: TimeInterval?
        var clock: TimeInterval?
        for (n, s) in ordered.enumerated() {
            let t = s.time.timeIntervalSince1970
            if previous == nil || t - previous! > gapSeconds {
                segment += 1
                clock = nil
            }
            previous = t
            guard !s.rrMilliseconds.isEmpty else { continue }
            let total = s.rrMilliseconds.reduce(0, +) / 1000
            var c: TimeInterval
            var omlagd = false
            if let k = clock, abs(t - (k + total)) <= reanchorSeconds {
                c = k
            } else {
                // Avsnittets första notis är ingen omläggning.
                omlagd = clock != nil
                c = t - total
            }
            for r in s.rrMilliseconds {
                c += r / 1000
                beats.append(Beat(time: c, rrMilliseconds: r, segment: segment,
                                  notification: n, reanchored: omlagd))
            }
            clock = c
        }
        return beats
    }

    /// Notiserna i tidsordning. En avkodad inspelning har inte gått genom
    /// `NightRecording.init`, så ordningen kontrolleras här också.
    static func ordered(_ night: NightRecording) -> [HeartRateSample] {
        let s = night.samples
        return zip(s, s.dropFirst()).allSatisfy { $0.0.time <= $0.1.time } ? s : s.sorted { $0.time < $1.time }
    }
}

/// Små räknehjälpare utan beroenden, så att alla mått räknas likadant.
enum Statistics {
    static func mean(_ x: [Double]) -> Double? {
        x.isEmpty ? nil : x.reduce(0, +) / Double(x.count)
    }

    /// Mittvärdet; med jämnt antal medel av de två i mitten.
    static func median(_ x: [Double]) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// Stickprovets standardavvikelse (n − 1). `nil` med färre än två värden.
    static func sampleStandardDeviation(_ x: [Double]) -> Double? {
        guard x.count >= 2, let m = mean(x) else { return nil }
        let ss = x.reduce(0.0) { (acc: Double, v: Double) -> Double in acc + (v - m) * (v - m) }
        return (ss / Double(x.count - 1)).squareRoot()
    }
}
