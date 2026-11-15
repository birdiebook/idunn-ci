import Foundation

/// BESLUT B6 · METOD M9
/// Whoops tider: väggklocka `yyyy-MM-dd HH:mm:ss` i den lokala tidszonen, och
/// zonen i en egen kolumn som `UTC+02:00`. Tolkas för hand i stället för med
/// DateFormatter, så att resultatet inte beror på telefonens språk, kalender
/// eller tidszon — och blir identiskt på Linux där testerna körs.
enum WhoopTime {
    /// `UTC+02:00`, `UTC-05:30`, `UTC` → sekunder öster om Greenwich.
    static func offsetSeconds(_ text: String) -> Int? {
        var s = Substring(text.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("UTC") || s.hasPrefix("GMT") { s = s.dropFirst(3) }
        if s.isEmpty || s == "Z" { return 0 }
        guard let sign = s.first, sign == "+" || sign == "-" else { return nil }
        let parts = s.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              h <= 14, m < 60 else { return nil }
        let total = h * 3600 + m * 60
        return sign == "-" ? -total : total
    }

    /// Väggklocka i en zon med känd förskjutning → ett absolut ögonblick.
    static func date(_ text: String, offsetSeconds: Int) -> Date? {
        let parts = text.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        let t = parts[1].split(separator: ":", omittingEmptySubsequences: false)
        guard d.count == 3, t.count == 3,
              d[0].count == 4, d[1].count == 2, d[2].count == 2,
              t.allSatisfy({ $0.count == 2 }),
              let year = Int(d[0]), let month = Int(d[1]), let day = Int(d[2]),
              let hour = Int(t[0]), let minute = Int(t[1]), let second = Int(t[2]),
              (1...12).contains(month), (1...daysIn(month: month, year: year)).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let local = days * 86_400 + hour * 3600 + minute * 60 + second
        return Date(timeIntervalSince1970: TimeInterval(local - offsetSeconds))
    }

    /// Dagar sedan 1970-01-01 i den proleptiska gregorianska kalendern
    /// (Howard Hinnants `days_from_civil`).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}
