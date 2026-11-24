import Foundation

/// BESLUT B143 · METOD M82
/// Utvecklingskopian: ett dygns arkiv (`dygn-<datum>.arkiv`, METOD M34) som kropp i ett anrop till mottagaren
/// `idunn-dygn`. Arkivet kommer in som byte från appen; `Coach` känner inte dess innehåll.
public enum DayCopyRules {
    /// **antagande**. Största arkiv som mottagaren tar emot.
    public static let maxBytes: Int = 20 * 1024 * 1024
    public static let path: String = "/functions/v1/idunn-dygn"
    /// BESLUT B160 · METOD M82. **antagande**. Dagens dygn laddas upp högst så här ofta (sekunder).
    public static let todaySeconds: TimeInterval = 600

    /// Ett datum `yyyy-MM-dd`: fyra, två och två siffror, månad 1–12 och dag 1–31.
    public static func isValidDay(_ day: String) -> Bool {
        let delar: [Substring] = day.split(separator: "-", omittingEmptySubsequences: false)
        guard delar.count == 3, delar[0].count == 4, delar[1].count == 2, delar[2].count == 2 else { return false }
        for d in delar where !d.allSatisfy({ (c: Character) -> Bool in c >= "0" && c <= "9" }) { return false }
        guard let m = Int(delar[1]), let t = Int(delar[2]) else { return false }
        return (1...12).contains(m) && (1...31).contains(t)
    }
}

extension CoachCall {
    /// BESLUT B143 · METOD M82. Laddar upp ett dygns arkiv. `nil` när kopplingen är ogiltig, dagen inte är ett datum,
    /// arkivet är tomt eller större än `DayCopyRules.maxBytes`.
    public static func dayCopy(config: CoachConfig, day: String, archive: Data) -> CoachCall? {
        guard config.isValid, DayCopyRules.isValidDay(day), !archive.isEmpty,
              archive.count <= DayCopyRules.maxBytes else { return nil }
        let headers: [String: String] = [
            "apikey": config.key,
            "Content-Type": "application/octet-stream",
            "Accept": "application/json",
            "x-idunn-token": config.token,
            "x-idunn-dag": day,
            "x-idunn-storlek": String(archive.count),
        ]
        return CoachCall(host: config.host, path: DayCopyRules.path, headers: headers, body: archive)
    }
}

/// BESLUT B143 · METOD M82
/// Loggen över uppladdade dygn: dag → fingeravtryck av arkivet och dess storlek. Ett dygn laddas upp när det är
/// nytt eller arkivet ändrats sedan sist.
public struct DayCopyLedger: Codable, Equatable, Sendable {
    public private(set) var sent: [String: String]

    public init() { sent = [:] }

    private enum CodingKeys: String, CodingKey { case sent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sent = try c.decodeIfPresent([String: String].self, forKey: .sent) ?? [:]
    }

    public static func fingerprint(_ data: Data) -> String {
        CoachLedger.fingerprint(data) + ":" + String(data.count)
    }

    /// Dagarna vars fingeravtryck inte är det som skickats, nyast först.
    public func pending(_ available: [(day: String, fingerprint: String)]) -> [String] {
        available.filter { (a: (day: String, fingerprint: String)) -> Bool in sent[a.day] != a.fingerprint }
            .map { (a: (day: String, fingerprint: String)) -> String in a.day }
            .sorted(by: >)
    }

    public mutating func mark(day: String, fingerprint: String) {
        sent[day] = fingerprint
    }

    public var count: Int { sent.count }
}
