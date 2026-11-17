import Foundation

/// BESLUT B134 · METOD M78
/// Träningen över tid, för sidan bakom veckokortet: en period (vecka, fyra veckor, halvår, år) delad i staplar
/// (dagar, veckor eller månader), var och en summerad som en vecka i `PassWeek` (METOD M72).
public enum PassPeriod: String, CaseIterable, Sendable {
    /// Den här veckan, en stapel per dag.
    case week
    /// De fyra senaste veckorna, en stapel per vecka.
    case month
    /// De sex senaste kalendermånaderna, en stapel per månad.
    case halfYear
    /// De tolv senaste kalendermånaderna, en stapel per månad.
    case year

    /// En stapel: första dagen (dagar sedan 1970-01-01), antalet dagar och summan över dem.
    public struct Bucket: Equatable, Sendable {
        public var startDay: Int
        public var days: Int
        public var summary: PassWeek.Summary

        public init(startDay: Int, days: Int, summary: PassWeek.Summary) {
            self.startDay = startDay
            self.days = days
            self.summary = summary
        }
    }

    /// Perioden: staplarna i tidsordning, den sista innehåller dagen.
    public struct Overview: Equatable, Sendable {
        public var period: PassPeriod
        public var buckets: [Bucket]

        public init(period: PassPeriod, buckets: [Bucket]) {
            self.period = period
            self.buckets = buckets
        }

        public var passes: Int { buckets.reduce(0) { $0 + $1.summary.passes } }
        public var seconds: TimeInterval { buckets.reduce(0) { $0 + $1.summary.seconds } }
        public var meters: Double { buckets.reduce(0) { $0 + $1.summary.meters } }
        public var load: Double { buckets.reduce(0) { $0 + $1.summary.load } }
        public var days: Int { buckets.reduce(0) { $0 + $1.days } }

        /// METOD M78. Medlet per stapel, tomma staplar medräknade.
        public var averageSeconds: Double { buckets.isEmpty ? 0 : seconds / Double(buckets.count) }

        /// METOD M78. Tiden per vecka över perioden: tiden delad med periodens dagar genom sju.
        public var secondsPerWeek: Double { days > 0 ? seconds / (Double(days) / 7) : 0 }

        /// METOD M78. Tiden per pulszon över hela perioden, i zonernas ordning.
        public var zones: [PassZones.Share] {
            var perZon: [Int: TimeInterval] = [:]
            for b in buckets { for z in b.summary.zones { perZon[z.zone, default: 0] += z.seconds } }
            return perZon.keys.sorted().map { (z: Int) -> PassZones.Share in PassZones.Share(zone: z, seconds: perZon[z] ?? 0) }
        }
    }

    // MARK: Kalendern (gregoriansk, utan Foundation-kalender, så att telefonens inställningar inte spelar in)

    /// År, månad och dag för en dag räknad från 1970-01-01.
    public static func civil(day: Int) -> (year: Int, month: Int, day: Int) {
        let z = day + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    /// Dagen räknad från 1970-01-01 för ett datum.
    public static func day(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Första dagen i månaden som ligger `offset` månader från månaden med dagen `day` (0 är samma månad).
    public static func monthStart(day: Int, offset: Int = 0) -> Int {
        let c = civil(day: day)
        let månader = c.year * 12 + (c.month - 1) + offset
        let år = månader >= 0 ? månader / 12 : (månader - 11) / 12
        return PassPeriod.day(year: år, month: månader - år * 12 + 1, day: 1)
    }

    /// METOD M78. Veckans nummer enligt ISO 8601: veckan hör till det år dess torsdag ligger i, och vecka 1 är
    /// veckan med årets första torsdag.
    public static func isoWeek(day: Int) -> Int {
        let torsdag = PassWeek.weekStart(day: day) + 3
        let nyår = PassPeriod.day(year: civil(day: torsdag).year, month: 1, day: 1)
        return (torsdag - nyår) / 7 + 1
    }

    // MARK: Staplarna

    /// METOD M78. Staplarnas dagar för perioden som innehåller `day`: (första dagen, antalet dagar), i tidsordning.
    public func ranges(day: Int) -> [(start: Int, days: Int)] {
        switch self {
        case .week:
            let måndag = PassWeek.weekStart(day: day)
            return (0..<7).map { (i: Int) -> (start: Int, days: Int) in (måndag + i, 1) }
        case .month:
            let måndag = PassWeek.weekStart(day: day)
            return (0..<4).map { (i: Int) -> (start: Int, days: Int) in (måndag - 7 * (3 - i), 7) }
        case .halfYear, .year:
            let antal = self == .halfYear ? 6 : 12
            return (0..<antal).map { (i: Int) -> (start: Int, days: Int) in
                let start = PassPeriod.monthStart(day: day, offset: i - (antal - 1))
                return (start, PassPeriod.monthStart(day: day, offset: i - (antal - 1) + 1) - start)
            }
        }
    }

    /// METOD M78. Perioden som innehåller `day`, summerad per stapel som i `PassWeek.summary` (METOD M72).
    public func overview(_ passes: [Pass], day: Int, dayOf: (Pass) -> Int, load: (Pass) -> Double,
                         classify: ((Int) -> Int)?) -> Overview {
        let staplar = ranges(day: day).map { (r: (start: Int, days: Int)) -> Bucket in
            Bucket(startDay: r.start, days: r.days,
                   summary: PassWeek.summary(passes, fromDay: r.start, days: r.days, dayOf: dayOf, load: load,
                                             classify: classify))
        }
        return Overview(period: self, buckets: staplar)
    }
}
