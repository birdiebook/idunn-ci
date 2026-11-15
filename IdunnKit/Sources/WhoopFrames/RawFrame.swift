import Foundation

/// METOD M12 · BESLUT B14 · BESLUT B3
/// T2 (PLAN.md §2): en notis från Whoops egen tjänst, sparad rå medan Idunn
/// lyssnar passivt. Idunn skriver aldrig till bandet — iOS delar anslutningen
/// med Whoop-appen, som sköter synken och kvittensen (BESLUT B14).
///
/// Ramarna kan bära hälsodata (historiken). De sparas bara på telefonen, och
/// det enda som visas är antal per karakteristik och pakettyp: formen, aldrig
/// innehållet.
public struct RawFrame: Equatable, Sendable {
    public var time: Date
    /// Karakteristikens första del i gemener, t.ex. `fd4b0003`.
    public var characteristic: String
    public var bytes: [UInt8]

    public init(time: Date, characteristic: String, bytes: [UInt8]) {
        self.time = time
        self.characteristic = RawFrame.shortName(characteristic)
        self.bytes = bytes
    }

    /// METOD M12. Whoops tjänst och de fyra notify-karakteristikerna Idunn
    /// lyssnar på. Skrivkarakteristiken (`…0002`) står medvetet inte här:
    /// Idunn har ingen kod som skriver till bandet (BESLUT B14).
    public static let service = "FD4B0001-CCE1-4033-93CE-002D5875F58A"
    public static let listened = [
        "FD4B0003-CCE1-4033-93CE-002D5875F58A",
        "FD4B0004-CCE1-4033-93CE-002D5875F58A",
        "FD4B0005-CCE1-4033-93CE-002D5875F58A",
        "FD4B0007-CCE1-4033-93CE-002D5875F58A",
    ]

    /// METOD M12. Ramhuvudet: `AA`, `01`, längd (2), två byte, CRC16 (2).
    public static let headerLength = 8
    public static let startByte: UInt8 = 0xAA

    /// METOD M12. Pakettypen är inre delens första byte, direkt efter huvudet,
    /// när notisen börjar en ram. `nil` för fortsättningar på en ram som inte
    /// fick plats i en notis, för `…0007`:s loggström och för korta notiser.
    public var packetType: Int? {
        guard bytes.count > Self.headerLength, bytes[0] == Self.startByte else { return nil }
        return Int(bytes[Self.headerLength])
    }

    /// `FD4B0003-CCE1-…` → `fd4b0003`. En kort UUID lämnas som den är, i gemener.
    public static func shortName(_ uuid: String) -> String {
        String(uuid.lowercased().split(separator: "-").first ?? "")
    }
}

/// Ramarna på disk: en JSON-rad per notis, bredvid nattens pulsfil
/// (BESLUT B15). Byten skrivs som base64.
public enum RawFrameLog {
    struct Line: Codable {
        var t: Double
        var k: String
        var b: Data
    }

    public static func line(_ f: RawFrame) -> Data {
        guard var d = try? JSONEncoder().encode(Line(t: f.time.timeIntervalSince1970,
                                                      k: f.characteristic, b: Data(f.bytes))) else {
            return Data()
        }
        d.append(0x0A)
        return d
    }

    /// Rader som inte går att tolka hoppas över och räknas.
    public static func decode(_ data: Data) -> (frames: [RawFrame], skippedLines: Int) {
        var frames: [RawFrame] = []
        let skipped = forEach(data) { frames.append($0) }
        return (frames, skipped)
    }

    /// Notis för notis, utan att hålla alla i minnet: en dygnsfil kan vara
    /// tiotals MB (BESLUT B30). Ger antalet rader som inte gick att tolka.
    @discardableResult
    public static func forEach(_ data: Data, _ body: (RawFrame) -> Void) -> Int {
        let decoder = JSONDecoder()
        var skipped = 0
        for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let l = try? decoder.decode(Line.self, from: Data(slice)) else {
                skipped += 1
                continue
            }
            body(RawFrame(time: Date(timeIntervalSince1970: l.t), characteristic: l.k, bytes: [UInt8](l.b)))
        }
        return skipped
    }
}

/// BESLUT B3. Antal notiser per karakteristik och pakettyp — det enda T2
/// visar. Inga värden, inga tider.
public struct FrameTally: Equatable, Sendable {
    public struct Key: Hashable, Comparable, Sendable {
        public var characteristic: String
        /// `nil`: notisen börjar inte en ram (METOD M12).
        public var packetType: Int?

        public static func < (a: Key, b: Key) -> Bool {
            if a.characteristic != b.characteristic { return a.characteristic < b.characteristic }
            return (a.packetType ?? -1) < (b.packetType ?? -1)
        }
    }

    public private(set) var counts: [Key: Int] = [:]

    public init() {}

    public init(_ frames: [RawFrame]) {
        for f in frames { add(f) }
    }

    public mutating func add(_ f: RawFrame) {
        counts[Key(characteristic: f.characteristic, packetType: f.packetType), default: 0] += 1
    }

    public var total: Int { counts.values.reduce(0, +) }

    public func total(characteristic: String) -> Int {
        counts.filter { $0.key.characteristic == characteristic }.values.reduce(0, +)
    }

    public struct Row: Hashable, Identifiable, Sendable {
        public var key: Key
        public var count: Int
        public var id: Key { key }
    }

    /// Sorterat på karakteristik, sedan pakettyp, för visningen.
    public var rows: [Row] {
        counts.keys.sorted().map { Row(key: $0, count: counts[$0]!) }
    }
}
