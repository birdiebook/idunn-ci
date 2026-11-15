import Foundation

/// METOD M12 · METOD M20
/// Notiser blir ramar. En ram börjar med `AA 01`, längd (u16 LE = inre del
/// + 4), två byte och CRC16-Modbus över byte 0–5 (LE i byte 6–7); sedan inre
/// delen och CRC32 (zlib) över den. En ram som inte ryms i en notis fortsätter
/// i nästa notis på samma karakteristik. En notis vars huvud klarar CRC16
/// börjar alltid en ny ram. Ramens tid är dess sista notis tid
/// (docs/PROTOKOLL_W5.md §5 steg 0).
public enum FrameAssembly {
    public struct Frame: Equatable, Sendable {
        public var characteristic: String
        /// Index i indata för notiserna som bär ramen, i ordning.
        public var notifications: [Int]
        public var time: Date
        public var inner: [UInt8]
        public var crc32OK: Bool
        /// Huvudets byte 4 och 5: två byte vars betydelse är okänd. De sparas i
        /// dygnsarkivet så att ramen går att återskapa bit för bit (BESLUT B41).
        public var headerBytes: [UInt8]

        /// Pakettypen: inre delens första byte.
        public var type: Int? { inner.first.map { Int($0) } }
    }

    public struct Stats: Equatable, Sendable {
        public var notifications = 0
        public var frames = 0
        public var continuations = 0
        /// Notiser som varken börjar eller fortsätter en ram (`…0007`:s text).
        public var nonFrames = 0
        public var crc16Failures = 0
        public var crc32Failures = 0
        /// Ramar som aldrig blev hela (nästa ram eller slutet kom först).
        public var incomplete = 0
        public init() {}
    }

    public static let headerLength = 8

    /// METOD M12. CRC16-Modbus: polynom 0xA001 (reflekterat), start 0xFFFF.
    public static func crc16Modbus<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    private static let crcTable: [UInt32] = (0..<256).map { (n: Int) -> UInt32 in
        var c: UInt32 = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    /// CRC32 som zlib och zip (polynom 0xEDB88320, reflekterat).
    public static func crc32<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            let i: Int = Int((c ^ UInt32(b)) & 0xFF)
            c = crcTable[i] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }

    /// Ett huvud som klarar CRC16.
    public static func validHeader(_ b: [UInt8]) -> Bool {
        guard b.count >= headerLength, b[0] == 0xAA else { return false }
        let lagrad: UInt16 = UInt16(b[6]) | (UInt16(b[7]) << 8)
        return crc16Modbus(b[0..<6]) == lagrad
    }

    public static func assemble(_ notes: [RawFrame]) -> (frames: [Frame], stats: [String: Stats]) {
        var stream = Stream()
        var frames: [Frame] = []
        for n in notes {
            if let f = stream.add(n) { frames.append(f) }
        }
        stream.close()
        return (frames, stream.stats)
    }

    /// METOD M23. Samma ihopfogning en notis i taget, för hämtningen som
    /// måste se varje ram när den blir hel. `Frame.notifications` räknar
    /// notiserna i den ordning de lagts till.
    public struct Stream: Sendable {
        struct Pending: Sendable {
            var indices: [Int]
            var bytes: [UInt8]
            var total: Int
        }

        public private(set) var stats: [String: Stats] = [:]
        private var pending: [String: Pending] = [:]
        private var count = 0

        public init() {}

        /// Lägger till en notis. Ger ramen om notisen gjorde en ram hel.
        public mutating func add(_ n: RawFrame) -> Frame? {
            let i = count
            count += 1
            let k = n.characteristic
            let b = n.bytes
            stats[k, default: Stats()].notifications += 1
            if validHeader(b) {
                if pending.removeValue(forKey: k) != nil { stats[k, default: Stats()].incomplete += 1 }
                let total: Int = headerLength + (Int(b[2]) | (Int(b[3]) << 8))
                let p = Pending(indices: [i], bytes: b, total: total)
                if b.count >= total { return finish(k, p, time: n.time) }
                pending[k] = p
            } else if var p = pending[k] {
                p.indices.append(i)
                p.bytes.append(contentsOf: b)
                stats[k, default: Stats()].continuations += 1
                if p.bytes.count >= p.total {
                    pending[k] = nil
                    return finish(k, p, time: n.time)
                }
                pending[k] = p
            } else if b.count >= headerLength && b[0] == 0xAA && b[1] == 0x01 {
                stats[k, default: Stats()].crc16Failures += 1
            } else {
                stats[k, default: Stats()].nonFrames += 1
            }
            return nil
        }

        /// Ramar som aldrig blev hela räknas som ofullständiga.
        public mutating func close() {
            for k in pending.keys { stats[k, default: Stats()].incomplete += 1 }
            pending = [:]
        }

        private mutating func finish(_ k: String, _ p: Pending, time: Date) -> Frame? {
            let length: Int = Int(p.bytes[2]) | (Int(p.bytes[3]) << 8)
            guard length >= 4 else {
                stats[k, default: Stats()].crc32Failures += 1
                return nil
            }
            let inner = Array(p.bytes[headerLength..<(headerLength + length - 4)])
            let s: Int = p.total - 4
            let stored: UInt32 = UInt32(p.bytes[s]) | (UInt32(p.bytes[s + 1]) << 8)
                | (UInt32(p.bytes[s + 2]) << 16) | (UInt32(p.bytes[s + 3]) << 24)
            let ok = crc32(inner) == stored
            stats[k, default: Stats()].frames += 1
            if !ok { stats[k, default: Stats()].crc32Failures += 1 }
            return Frame(characteristic: k, notifications: p.indices, time: time, inner: inner, crc32OK: ok,
                         headerBytes: Array(p.bytes[4..<6]))
        }
    }

    /// u32 LE på `offset` i den inre delen, eller `nil` om den inte ryms.
    public static func u32(_ inner: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= inner.count else { return nil }
        return UInt32(inner[offset]) | (UInt32(inner[offset + 1]) << 8)
            | (UInt32(inner[offset + 2]) << 16) | (UInt32(inner[offset + 3]) << 24)
    }
}
