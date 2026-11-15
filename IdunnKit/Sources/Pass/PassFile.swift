import Foundation

/// BESLUT B58 · METOD M47
/// Passet som fil: en JSON-fil per pass (`pass-yyyy-MM-dd-HHmmss.json`, start
/// i lokal tid). Appen skriver och läser i Application Support/pass; här finns
/// kodningen, namnen och läsningen av en mapp, utan skyddsklasser.
public enum PassFile {
    /// Kodningen: ISO-8601-datum och sorterade nycklar, så att samma pass ger
    /// samma byte.
    public static func encode(_ pass: Pass) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return try e.encode(pass)
    }

    public static func decode(_ data: Data) throws -> Pass {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(Pass.self, from: data)
    }

    /// `yyyy-MM-dd-HHmmss` ur start i zonen, utan DateFormatter (telefonens
    /// språk och kalender ska inte spela in).
    public static func stamp(start: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        return String(format: "%04d-%02d-%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// `pass-yyyy-MM-dd-HHmmss.json`.
    public static func fileName(start: Date, timeZone: TimeZone = .current) -> String {
        "pass-" + stamp(start: start, timeZone: timeZone) + ".json"
    }

    /// `idunn-pass-yyyy-MM-dd-HHmmss.zip`: exporten av ett pass.
    public static func exportName(start: Date, timeZone: TimeZone = .current) -> String {
        "idunn-pass-" + stamp(start: start, timeZone: timeZone) + ".zip"
    }

    /// Passfilerna i en mapp med sin adress, senast först. En trasig fil och
    /// en fil som inte är ett pass hoppas över.
    public static func entries(in folder: URL) -> [(url: URL, pass: Pass)] {
        let namn = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var ut: [(url: URL, pass: Pass)] = []
        for n in namn where n.hasPrefix("pass-") && n.hasSuffix(".json") {
            let url = folder.appendingPathComponent(n)
            guard let data = try? Data(contentsOf: url), let p = try? decode(data) else { continue }
            ut.append((url, p))
        }
        return ut.sorted { $0.pass.start > $1.pass.start }
    }

    /// Passen i en mapp, senast först; trasiga filer hoppas över.
    public static func loadAll(in folder: URL) -> [Pass] {
        entries(in: folder).map { $0.pass }
    }
}
