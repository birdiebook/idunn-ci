import Foundation

/// BESLUT B127 · METOD M73
/// Kopplingen till coachen som användaren klistrar in en gång: var datan ska (värden), nyckeln som släpper in
/// anropet och en engångskod. Texten är `IDUNN1.` följt av base64url av JSON `{"h":…,"k":…,"c":…}`.
///
/// Ingen adress står i koden: den kommer med kopplingen, så att det speglade, publika repot (BESLUT B115) inte
/// säger var datan ligger. Bara värdar hos databastjänsten godtas, och alltid över TLS.
public struct CoachLink: Equatable, Sendable {
    public static let prefix: String = "IDUNN1."
    /// METOD M73. Värden ska sluta så här: en adress någon annanstans godtas inte.
    public static let hostSuffix: String = ".supabase.co"

    public var host: String
    public var key: String
    public var code: String

    public init(host: String, key: String, code: String) {
        self.host = host
        self.key = key
        self.code = code
    }

    private struct Wire: Codable {
        var h: String
        var k: String
        var c: String
    }

    /// Kopplingen ur den inklistrade texten, eller `nil` när den inte är en koppling. Blanktecken runt om tas bort.
    public static func parse(_ text: String) -> CoachLink? {
        let ren: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ren.hasPrefix(prefix) else { return nil }
        var b64: String = String(ren.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let w = try? JSONDecoder().decode(Wire.self, from: data) else {
            return nil
        }
        let link = CoachLink(host: w.h.lowercased(), key: w.k, code: w.c.uppercased())
        return link.isValid ? link : nil
    }

    /// Texten att klistra in (det `parse` läser).
    public var text: String {
        let data: Data = (try? JSONEncoder().encode(Wire(h: host, k: key, c: code))) ?? Data()
        let b64: String = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return CoachLink.prefix + b64
    }

    var isValid: Bool {
        CoachLink.validHost(host) && CoachLink.validKey(key) && CoachLink.only(code, CoachLink.codeChars, 8...64)
    }

    private static let hostChars: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let keyChars: Set<Character> =
        Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
    private static let codeChars: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    private static func only(_ s: String, _ tillåtna: Set<Character>, _ längd: ClosedRange<Int>) -> Bool {
        längd.contains(s.count) && s.allSatisfy { (c: Character) -> Bool in tillåtna.contains(c) }
    }

    /// METOD M73. En värd är ett projektnamn (bokstäver och siffror) följt av tjänstens domän, inget annat.
    static func validHost(_ host: String) -> Bool {
        guard host.hasSuffix(hostSuffix) else { return false }
        return only(String(host.dropLast(hostSuffix.count)), hostChars, 8...40)
    }

    static func validKey(_ key: String) -> Bool { only(key, keyChars, 20...400) }
}

/// BESLUT B127 · METOD M73
/// Det telefonen sparar när den är kopplad (i nyckelringen): värden, nyckeln och telefonens egen hemlighet.
/// Hemligheten skapas på telefonen och lämnar den bara i anropen; mottagaren sparar bara dess hash.
public struct CoachConfig: Codable, Equatable, Sendable {
    public var host: String
    public var key: String
    public var token: String

    public init(host: String, key: String, token: String) {
        self.host = host
        self.key = key
        self.token = token
    }

    /// En sparad koppling som inte längre är giltig (fel värd, för kort hemlighet) används inte.
    public var isValid: Bool {
        CoachLink.validHost(host) && CoachLink.validKey(key) && token.count >= CoachToken.minimumLength
    }
}

/// METOD M73. Telefonens hemlighet: 32 slumpade byte som 64 hextecken, ur systemets slumpkälla.
public enum CoachToken {
    public static let bytes: Int = 32
    /// Mottagaren kräver minst så här många tecken.
    public static let minimumLength: Int = 40

    public static func make() -> String {
        var g = SystemRandomNumberGenerator()
        return make(using: &g)
    }

    public static func make<G: RandomNumberGenerator>(using g: inout G) -> String {
        let hex: [Character] = Array("0123456789abcdef")
        var ut: String = ""
        for _ in 0..<bytes {
            let b: UInt8 = UInt8.random(in: 0...255, using: &g)
            ut.append(hex[Int(b >> 4)])
            ut.append(hex[Int(b & 0x0F)])
        }
        return ut
    }
}

/// BESLUT B127 · METOD M73
/// Ett anrop till coachen, utan nätverk: värden, vägen, huvudena och kroppen. Appens sändare
/// (`App/CoachSandare.swift`) gör det till en förfrågan över TLS; ingen annan kod i appen talar med nätet.
public struct CoachCall: Equatable, Sendable {
    public var host: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    static let pairPath: String = "/rest/v1/rpc/idunn_pair"
    static let ingestPath: String = "/rest/v1/rpc/idunn_ingest"

    private static func headers(key: String) -> [String: String] {
        ["apikey": key, "Content-Type": "application/json", "Accept": "application/json"]
    }

    private struct PairBody: Encodable {
        var p_code: String
        var p_token: String
        var p_device: String?
    }

    /// Kopplar telefonen: engångskoden byts mot rätten att skicka med telefonens hemlighet.
    public static func pair(link: CoachLink, token: String, device: String?) -> CoachCall? {
        guard link.isValid else { return nil }
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        guard let body = try? e.encode(PairBody(p_code: link.code, p_token: token, p_device: device)) else {
            return nil
        }
        return CoachCall(host: link.host, path: pairPath, headers: headers(key: link.key), body: body)
    }

    /// Skickar dokument. Yttre nycklar (`p_token`, `p_items`) är mottagarens; dokumentens egna kodas i snake_case.
    public static func ingest(config: CoachConfig, items: [CoachItem]) -> CoachCall? {
        guard config.isValid, !items.isEmpty, items.count <= CoachRules.batchSize else { return nil }
        // Dokumenten kodas var för sig med sin egen kodning och sätts in som färdig JSON, så att de yttre nycklarna
        // inte räknas om till snake_case och dokumentets byte är desamma som loggen räknar på.
        var delar: [String] = []
        let yttre = JSONEncoder()
        for i in items {
            guard let kind = try? yttre.encode(i.kind.rawValue), let key = try? yttre.encode(i.key),
                  let k = String(data: kind, encoding: .utf8), let n = String(data: key, encoding: .utf8) else {
                return nil
            }
            let data: String
            if i.data == nil {
                data = "null"
            } else {
                guard let d = CoachCoding.json(i), let s = String(data: d, encoding: .utf8) else { return nil }
                data = s
            }
            delar.append("{\"kind\":" + k + ",\"key\":" + n + ",\"data\":" + data + "}")
        }
        guard let tok = try? yttre.encode(config.token), let t = String(data: tok, encoding: .utf8) else { return nil }
        let text: String = "{\"p_token\":" + t + ",\"p_items\":[" + delar.joined(separator: ",") + "]}"
        return CoachCall(host: config.host, path: ingestPath, headers: headers(key: config.key),
                         body: Data(text.utf8))
    }
}

/// BESLUT B127 · METOD M73
/// Svaret på ett anrop. Mottagaren svarar alltid med `{"ok":…}`; allt annat är ett fel på vägen.
public enum CoachReply: Equatable, Sendable {
    /// Mottaget; antalet dokument som skrevs eller togs bort (0 för en koppling).
    case ok(count: Int)
    /// Mottagaren sa nej, med sitt skäl: `okand` (telefonen är inte kopplad eller har stängts av), `fel-kod`,
    /// `sparrad`, `fel-form`, `fullt`.
    case refused(String)
    /// Ett svar utan `ok`: HTTP-koden.
    case http(Int)
    /// Inget svar alls (inget nät, tidsgränsen).
    case unreachable

    private struct Wire: Decodable {
        var ok: Bool
        var error: String?
        var count: Int?
    }

    public static func parse(status: Int, body: Data) -> CoachReply {
        guard (200..<300).contains(status) else { return .http(status) }
        guard let w = try? JSONDecoder().decode(Wire.self, from: body) else { return .http(status) }
        if w.ok { return .ok(count: w.count ?? 0) }
        return .refused(w.error ?? "")
    }

    /// Telefonen är inte längre kopplad hos mottagaren: kopplingen på telefonen tas bort.
    public var isUnknownDevice: Bool { self == .refused("okand") }
}

/// METOD M73. Sändningens konstanter.
public enum CoachRules {
    /// **antagande**. Så många dokument per anrop; mottagaren tar högst 200.
    public static let batchSize: Int = 100
    /// **antagande**. Så länge väntar appen efter en ändring innan den skickar, så att en natt som räknas om i
    /// flera steg skickas en gång.
    public static let debounceSeconds: TimeInterval = 10
    /// **antagande**. Efter ett misslyckat försök väntar appen minst så här länge innan nästa.
    public static let retrySeconds: TimeInterval = 300
}

/// BESLUT B127 · METOD M73
/// Loggen över det skickade: ett fingeravtryck per dokument. Ett dokument skickas när det är nytt eller har
/// ändrats sedan sist, och bara då; räknas en natt om till samma tal skickas den inte igen.
public struct CoachLedger: Codable, Equatable, Sendable {
    /// `slag/nyckel` → fingeravtrycket av dokumentets JSON.
    public private(set) var sent: [String: String]

    public init() { sent = [:] }

    /// METOD M73. Fingeravtrycket: FNV-1a över dokumentets byte, 64 bitar som hex. Det skyddar inget; det säger
    /// bara om innehållet har ändrats.
    public static func fingerprint(_ data: Data) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(h, radix: 16)
    }

    /// METOD M73. Det som ska skickas: varje dokument som är nytt eller ändrat, i den ordning de gavs, och sist en
    /// borttagning för varje skickat dokument av slagen i `deletable` som inte längre finns. Nätter tas aldrig bort
    /// av sig själva: en lista som råkar vara tom (telefonen låst, en omräkning på väg) får inte tömma coachen.
    public func pending(_ items: [CoachItem], deletable: Set<CoachKind> = []) -> [CoachItem] {
        var ut: [CoachItem] = []
        var finns: Set<String> = []
        for i in items {
            finns.insert(i.name)
            guard let json = CoachCoding.json(i) else { continue }
            if sent[i.name] != CoachLedger.fingerprint(json) { ut.append(i) }
        }
        for namn in sent.keys.sorted() where !finns.contains(namn) {
            guard let snedstreck = namn.firstIndex(of: "/"),
                  let kind = CoachKind(rawValue: String(namn[..<snedstreck])), deletable.contains(kind) else {
                continue
            }
            ut.append(CoachItem(kind: kind, key: String(namn[namn.index(after: snedstreck)...]), data: nil))
        }
        return ut
    }

    /// Dokumenten kom fram: de står som skickade (en borttagning stryks).
    public mutating func mark(_ items: [CoachItem]) {
        for i in items {
            if let json = CoachCoding.json(i) {
                sent[i.name] = CoachLedger.fingerprint(json)
            } else {
                sent[i.name] = nil
            }
        }
    }

    /// Det som ska skickas, i bitar om högst `CoachRules.batchSize`.
    public static func batches(_ items: [CoachItem]) -> [[CoachItem]] {
        stride(from: 0, to: items.count, by: CoachRules.batchSize).map { (i: Int) -> [CoachItem] in
            Array(items[i..<min(i + CoachRules.batchSize, items.count)])
        }
    }

    public var count: Int { sent.count }
}
