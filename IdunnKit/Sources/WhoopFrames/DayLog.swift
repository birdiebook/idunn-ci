import Foundation

/// METOD M27 · BESLUT B30 · BESLUT B15 · METOD M12
/// Dygnsfilen (PLAN.md A1): lyssnaren sparar allt bandet skickar i en fil per
/// lokalt datum, `dygn-<yyyy-MM-dd>.t2.jsonl` (samma rader som en natts
/// `.t2.jsonl`), med `dygn-<yyyy-MM-dd>.jsonl` bredvid för zonen, zonbyten och
/// användaren märken. Här bor namnen och växlingen, utan Bluetooth och utan
/// filer, så att de provas på Linux.
///
/// Datumet räknas för hand ur telefonens zon (BESLUT B6), inte med
/// DateFormatter eller Calendar.
public enum DayLog {
    public static let prefix = "dygn-"

    /// Ett lokalt datum.
    public struct Day: Equatable, Hashable, Sendable {
        public var year: Int
        public var month: Int
        public var day: Int

        public init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        /// `2026-10-13`.
        public var text: String { Self.pad(year, 4) + "-" + Self.pad(month, 2) + "-" + Self.pad(day, 2) }

        /// Dagar sedan 1970-01-01, så att andra moduler kan räkna med datum
        /// (uppvakningsdagen i `Night`) utan att kunna Hinnants formler.
        public var daysSince1970: Int { DayLog.days(self) }

        public init(daysSince1970 n: Int) {
            self = DayLog.day(fromDays: n)
        }

        static func pad(_ v: Int, _ n: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, n - s.count)) + s
        }
    }

    // MARK: Datum utan Calendar

    /// Heltalsdivision som avrundar nedåt (Swifts `/` avrundar mot noll).
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    /// Dagar sedan 1970-01-01 för ett datum i den proleptiska gregorianska
    /// kalendern (Howard Hinnants `days_from_civil`).
    static func days(_ d: Day) -> Int {
        let y = d.month <= 2 ? d.year - 1 : d.year
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let mp = (d.month + 9) % 12
        let doy = (153 * mp + 2) / 5 + d.day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Datumet för dagar sedan 1970-01-01 (`civil_from_days`).
    static func day(fromDays z0: Int) -> Day {
        let z = z0 + 719_468
        let era = floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return Day(year: m <= 2 ? y + 1 : y, month: m, day: d)
    }

    /// Det lokala datumet för ett ögonblick, i en zon given som sekunder öster
    /// om Greenwich.
    public static func localDay(_ date: Date, utcOffsetSeconds: Int) -> Day {
        let local = Int(date.timeIntervalSince1970.rounded(.down)) + utcOffsetSeconds
        return day(fromDays: floorDiv(local, 86_400))
    }

    /// Ögonblicket då klockan i zonen är `hour:minute` på datumet.
    public static func date(of d: Day, hour: Int = 0, minute: Int = 0, utcOffsetSeconds: Int) -> Date {
        Date(timeIntervalSince1970: Double(days(d) * 86_400 + hour * 3600 + minute * 60 - utcOffsetSeconds))
    }

    /// Dagen före (`by` = −1) eller efter (+1).
    public static func shifted(_ d: Day, by n: Int) -> Day { day(fromDays: days(d) + n) }

    /// Dygnsfilerna som kan ha notiser i `[from, to)`: datumen i telefonens
    /// zon, med ett dygn på var sida eftersom en fil heter efter zonen när den
    /// skrevs (en resa eller sommartid kan flytta en notis till grannfilen).
    public static func stems(touching from: Date, to: Date, utcOffsetSeconds: Int) -> [String] {
        guard to > from else { return [] }
        let a = days(localDay(from, utcOffsetSeconds: utcOffsetSeconds)) - 1
        let b = days(localDay(to, utcOffsetSeconds: utcOffsetSeconds)) + 1
        return (a...b).map { stem(for: day(fromDays: $0)) }
    }

    // MARK: Namnen

    /// `dygn-2026-10-13`, filernas stam.
    public static func stem(for date: Date, utcOffsetSeconds: Int) -> String {
        stem(for: localDay(date, utcOffsetSeconds: utcOffsetSeconds))
    }

    public static func stem(for d: Day) -> String { prefix + d.text }

    public static func isDayStem(_ s: String) -> Bool { day(ofStem: s) != nil }

    /// Datumet ur en stam; `nil` för allt som inte är `dygn-yyyy-MM-dd`.
    public static func day(ofStem s: String) -> Day? {
        guard s.hasPrefix(prefix) else { return nil }
        let rest = s.dropFirst(prefix.count)
        let parts = rest.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return Day(year: y, month: m, day: d)
    }

    // MARK: Växlingen

    /// METOD M27. Håller reda på vilken dygnsfil som gäller. Appen frågar vid
    /// varje notis; svaret säger om filen ska bytas eller en zonrad skrivas.
    ///
    /// - Nytt lokalt datum (midnatt, eller en resa över datumgränsen): en ny
    ///   fil. Ett byte *tillbaka* till ett tidigare datum (resa västerut) öppnar
    ///   den filen igen och fortsätter längst bak; en fil är alltså i
    ///   skrivordning, inte i tidsordning, och läsare sorterar.
    /// - Samma datum men ny zon (sommartid, en resa inom dygnet): samma fil och
    ///   en zonrad i `.jsonl` (`RecordingLog.zoneChange`).
    public struct Cursor: Equatable, Sendable {
        public enum Change: Equatable, Sendable {
            case none
            /// Första notisen, eller datumet ändrades. Öppna `stem`; zonen
            /// skrivs som sidofilens huvud om den är ny.
            case file(stem: String, utcOffsetSeconds: Int)
            /// Samma fil, ny zon.
            case zone(utcOffsetSeconds: Int)
        }

        public private(set) var stem: String?
        public private(set) var utcOffsetSeconds: Int?

        public init() {}

        public mutating func advance(to date: Date, utcOffsetSeconds offset: Int) -> Change {
            let nytt = DayLog.stem(for: date, utcOffsetSeconds: offset)
            defer {
                stem = nytt
                utcOffsetSeconds = offset
            }
            if nytt != stem { return .file(stem: nytt, utcOffsetSeconds: offset) }
            if offset != utcOffsetSeconds { return .zone(utcOffsetSeconds: offset) }
            return .none
        }
    }
}
