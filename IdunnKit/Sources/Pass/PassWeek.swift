import Foundation

/// BESLUT B126 · METOD M72
/// Veckans träning: tid, sträcka, belastning och tid per pulszon för en vecka, och samma tal för veckorna före, så
/// att den här veckan går att läsa mot det vanliga. Belastningen och zonen kommer utifrån (appen ger `PassLoad`,
/// METOD M53), så att de står på ett ställe.
public enum PassWeek {
    /// METOD M72. Så många veckor före den här jämförs den med.
    public static let previousWeeks = 4

    /// METOD M72. Måndagen i veckan som dagen `day` (dagar sedan 1970-01-01) ligger i. Veckan går måndag till
    /// söndag; 1970-01-01 var en torsdag.
    public static func weekStart(day: Int) -> Int {
        let sedanMåndag = ((day + 3) % 7 + 7) % 7
        return day - sedanMåndag
    }

    /// METOD M72. Räknas passet som träning? Bastu och dusch är värme, inte arbete (METOD M47, M53), och ett pass
    /// som pågår räknas inte förrän det stoppats.
    public static func counts(_ p: Pass) -> Bool {
        guard p.stop != nil else { return false }
        return p.kind != .bastu && p.kind != .dusch
    }

    /// En veckas träning.
    public struct Summary: Equatable, Sendable {
        /// Veckans måndag, dagar sedan 1970-01-01.
        public var weekStart: Int
        public var passes: Int
        /// Tiden från Start till Stopp, summerad.
        public var seconds: TimeInterval
        /// Sträckan i meter över passen ute; 0 utan pass ute.
        public var meters: Double
        public var load: Double
        /// Tiden per pulszon över passens prov, i zonernas ordning; tom utan maxpuls eller prov.
        public var zones: [PassZones.Share]

        public init(weekStart: Int, passes: Int = 0, seconds: TimeInterval = 0, meters: Double = 0, load: Double = 0,
                    zones: [PassZones.Share] = []) {
            self.weekStart = weekStart
            self.passes = passes
            self.seconds = seconds
            self.meters = meters
            self.load = load
            self.zones = zones
        }
    }

    /// METOD M72. Veckan som börjar måndagen `weekStart`. `dayOf` ger passets dag (dagar sedan 1970-01-01 i
    /// telefonens zon, efter Start), `load` passets belastning och `classify` zonen för en puls (`nil` utan
    /// maxpuls: då räknas inga zoner).
    public static func summary(_ passes: [Pass], weekStart: Int, dayOf: (Pass) -> Int, load: (Pass) -> Double,
                               classify: ((Int) -> Int)?) -> Summary {
        var ut = Summary(weekStart: weekStart)
        var perZon: [Int: TimeInterval] = [:]
        for p in passes where counts(p) {
            let dag = dayOf(p)
            guard dag >= weekStart, dag < weekStart + 7 else { continue }
            ut.passes += 1
            ut.seconds += p.duration
            ut.meters += PassRoute.distance(p.track ?? [])
            ut.load += load(p)
            if let c = classify {
                for z in PassZones.time(p.activeSamples, classify: c) { perZon[z.zone, default: 0] += z.seconds }
            }
        }
        ut.zones = perZon.keys.sorted().map { (z: Int) -> PassZones.Share in PassZones.Share(zone: z, seconds: perZon[z] ?? 0) }
        return ut
    }

    /// Den här veckan mot veckorna före.
    public struct Overview: Equatable, Sendable {
        /// Veckan som dagen ligger i, hittills.
        public var current: Summary
        /// De fyra veckorna före, äldst först. En vecka utan pass är med, med nollor.
        public var previous: [Summary]

        public init(current: Summary, previous: [Summary]) {
            self.current = current
            self.previous = previous
        }

        /// METOD M72. Medlet över veckorna före, tomma veckor medräknade.
        public var averageSeconds: Double { medel { $0.seconds } }
        public var averageMeters: Double { medel { $0.meters } }
        public var averageLoad: Double { medel { $0.load } }

        private func medel(_ v: (Summary) -> Double) -> Double {
            guard !previous.isEmpty else { return 0 }
            return previous.reduce(0) { $0 + v($1) } / Double(previous.count)
        }

        /// Finns det något att visa: ett pass den här veckan eller någon av veckorna före.
        public var hasTraining: Bool { current.passes > 0 || previous.contains { $0.passes > 0 } }
    }

    /// METOD M72. Veckan som `day` ligger i och de fyra veckorna före.
    public static func overview(_ passes: [Pass], day: Int, dayOf: (Pass) -> Int, load: (Pass) -> Double,
                                classify: ((Int) -> Int)?) -> Overview {
        let start = weekStart(day: day)
        let nu = summary(passes, weekStart: start, dayOf: dayOf, load: load, classify: classify)
        var före: [Summary] = []
        for i in stride(from: previousWeeks, through: 1, by: -1) {
            före.append(summary(passes, weekStart: start - 7 * i, dayOf: dayOf, load: load, classify: classify))
        }
        return Overview(current: nu, previous: före)
    }
}
