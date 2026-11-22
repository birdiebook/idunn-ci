import Foundation

/// BESLUT B121 · METOD M69
/// Från bandets sekunder till förslag i passlistan: sekunderna blir minuter, de hittade passen (`PassDetection`)
/// blir förslag, och ett förslag blir ett pass först när användaren säger det. Förslag som tagits bort kommer inte
/// tillbaka.
public enum PassSuggestions {
    /// En sekund ur bandets historik: tiden (Unix-sekunder), pulsen (0 när bandet inte har någon), gravitationen i g
    /// och hudtemperaturen i °C.
    public struct Second: Equatable, Sendable {
        public var time: Int
        public var pulse: Int
        public var x: Double
        public var y: Double
        public var z: Double
        public var skinTemperature: Double?

        public init(time: Int, pulse: Int, x: Double, y: Double, z: Double, skinTemperature: Double? = nil) {
            self.time = time
            self.pulse = pulse
            self.x = x
            self.y = y
            self.z = z
            self.skinTemperature = skinTemperature
        }
    }

    /// METOD M69. Pulsen räknas bara i det här området (som METOD M68).
    public static let bpmRange = 25...230

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// METOD M69. Sekunderna som minuter: pulsen är medianen över minutens sekunder med rimlig puls, rörelsen medlet
    /// av |Δg| mot sekunden närmast före (bara när den ligger precis en sekund före, som METOD M24), och hudens
    /// temperatur medianen. Sekunderna får komma i valfri ordning; samma sekund två gånger räknas en gång.
    public static func minutes(_ seconds: [Second]) -> [PassDetection.Minute] {
        var perSekund: [Int: Second] = [:]
        for s in seconds { perSekund[s.time] = s }
        let ordnade = perSekund.values.sorted { $0.time < $1.time }
        var pulser: [Int: [Double]] = [:]
        var rörelser: [Int: [Double]] = [:]
        var hud: [Int: [Double]] = [:]
        var minuter: Set<Int> = []
        var förra: Second?
        for s in ordnade {
            let m = s.time / 60
            minuter.insert(m)
            if bpmRange.contains(s.pulse) { pulser[m, default: []].append(Double(s.pulse)) }
            if let t = s.skinTemperature { hud[m, default: []].append(t) }
            if let f = förra, f.time == s.time - 1 {
                let dx = s.x - f.x, dy = s.y - f.y, dz = s.z - f.z
                rörelser[m, default: []].append((dx * dx + dy * dy + dz * dz).squareRoot())
            }
            förra = s
        }
        return minuter.sorted().map { (m: Int) -> PassDetection.Minute in
            let r = rörelser[m] ?? []
            return PassDetection.Minute(minute: m, pulse: median(pulser[m] ?? []),
                                        movement: r.isEmpty ? nil : r.reduce(0, +) / Double(r.count),
                                        skinTemperature: median(hud[m] ?? []))
        }
    }

    /// Ett förslag som tagits bort: minuterna det täckte. Ett nytt förslag som rör dem visas inte.
    public struct Dismissed: Codable, Equatable, Sendable {
        public var startMinute: Int
        public var endMinute: Int

        public init(startMinute: Int, endMinute: Int) {
            self.startMinute = startMinute
            self.endMinute = endMinute
        }
    }

    /// Det som sparas om förslagen (`passforslag.json`): de borttagna. Förslagen själva räknas om ur historiken.
    public struct Store: Codable, Equatable, Sendable {
        public var dismissed: [Dismissed]

        public init(dismissed: [Dismissed] = []) {
            self.dismissed = dismissed
        }

        enum CodingKeys: String, CodingKey {
            case dismissed
        }

        /// En fil från ett annat bygge får sakna nyckeln: den blir tom.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dismissed = try c.decodeIfPresent([Dismissed].self, forKey: .dismissed) ?? []
        }

        /// Tar bort ett förslag för gott. Borttagna äldre än `keepDays` dagar före förslaget rensas, så att filen
        /// inte växer.
        public mutating func dismiss(_ c: PassDetection.Candidate) {
            let gräns = c.startMinute - PassSuggestions.keepDays * 1440
            dismissed.removeAll { $0.endMinute < gräns }
            dismissed.append(Dismissed(startMinute: c.startMinute, endMinute: c.endMinute))
        }
    }

    public static let fileName = "passforslag.json"
    /// METOD M69. Borttagna förslag sparas så här många dagar (längre än historiken läses om, METOD M68).
    public static let keepDays = 30
    /// METOD M69. Efter passets slut räknas så här många sekunder som efterperiod (METOD M47), så att ett förslag
    /// inte läggs i ett pass efterperiod.
    public static let afterSeconds: TimeInterval = PassRules.afterSeconds

    /// METOD M69. Tiderna som inte ska ge förslag: passen som redan finns (från Start till efterperiodens slut, eller
    /// till Stopp plus efterperioden när den inte är stängd) och de borttagna förslagen.
    public static func excluded(passes: [Pass], store: Store) -> [ClosedRange<Int>] {
        var ut: [ClosedRange<Int>] = []
        for p in passes {
            let slut: Date = p.afterEnd ?? (p.stop ?? p.start).addingTimeInterval(afterSeconds)
            let a = Int(p.start.timeIntervalSince1970) / 60
            let b = max(a, Int(slut.timeIntervalSince1970) / 60)
            ut.append(a...b)
        }
        for d in store.dismissed where d.endMinute >= d.startMinute {
            ut.append(d.startMinute...d.endMinute)
        }
        return ut
    }

    /// METOD M69. Förslagen ur bandets sekunder: det som hittas utanför passen som finns och de borttagna.
    public static func suggestions(seconds: [Second], restingPulse: Double, maxPulse: Double, passes: [Pass],
                                   store: Store, rules: PassDetection.Rules = PassDetection.Rules())
        -> [PassDetection.Candidate] {
        PassDetection.candidates(minutes(seconds), restingPulse: restingPulse, maxPulse: maxPulse,
                                 excluded: excluded(passes: passes, store: store), rules: rules)
    }

    /// METOD M69 · METOD M68 · BESLUT B150. Förslaget som ett pass av typen `kind`: Start och Stopp är förslagets (eller
    /// de tider användaren flyttat dem till), efterperioden är stängd efter `PassRules.afterSeconds`, och pulsen fylls ur
    /// bandets historik (`PassHistory.fill`), prov för prov med källan historik. Förslaget som det var sparas i
    /// `suggested`, bredvid det som valdes.
    public static func pass(from c: PassDetection.Candidate, kind: PassKind?, readings: [PassHistory.Reading],
                            id: UUID = UUID(), label: PassLabel? = nil, start: Date? = nil, stop: Date? = nil) -> Pass {
        let början: Date = start ?? c.start
        let slut: Date = max(början, stop ?? c.end)
        var p = Pass(id: id, start: början, stop: slut, kind: kind)
        p.afterEnd = slut.addingTimeInterval(afterSeconds)
        if let l = label { PassEdit.apply(l, to: &p) }
        p.suggested = PassOrigin(start: c.start, end: c.end, kind: c.kind)
        return PassHistory.fill(p, readings: readings)
    }
}
