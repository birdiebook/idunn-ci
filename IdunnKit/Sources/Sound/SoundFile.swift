import Foundation
import Night

/// METOD M38 · BESLUT B47
/// Märken som ljudsessionen lämnar vid sidan av måtten: start, stopp och
/// avbrotten (samtal, larm, annat) med sin orsak. De skrivs som en JSON-rad
/// per märke i `ljud-<start>.markningar`, och ett glapp i måtten förklaras
/// av märket närmast före (`SoundGap.cause`).
public struct SoundMark: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Lyssnaren startade.
        case started
        /// Lyssnaren slutade (morgon, eller för att reglaget stängdes av).
        case stopped
        /// Avbrott av ett samtal (iOS-avbrottets orsak).
        case interruptedCall
        /// Avbrott av en väckarklocka eller en annan ljudapp.
        case interruptedAlarm
        /// Avbrott av annat, eller av okänd orsak.
        case interruptedOther
        /// Lyssnaren återupptogs efter ett avbrott.
        case resumed
        /// Mikrofonen försvann (en rutt byttes, eller motorn stannade).
        case routeLost
        /// Appen hörde ingenting av ljudsessionen, eller motorn gick inte att starta.
        case failed
    }

    /// Unix-sekunder, telefonens klocka.
    public var time: Int
    public var kind: Kind

    public init(time: Int, kind: Kind) {
        self.time = time
        self.kind = kind
    }

    /// Märket som en rad att lägga sist i märkesfilen.
    public func line() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        var d: Data = (try? enc.encode(self)) ?? Data()
        d.append(0x0A)
        return d
    }

    /// Märkena i en märkesfil, i filens ordning. Rader som inte går att läsa hoppas över.
    public static func decode(_ data: Data) -> [SoundMark] {
        let dec = JSONDecoder()
        var out: [SoundMark] = []
        for part in data.split(separator: 0x0A) {
            if let m = try? dec.decode(SoundMark.self, from: Data(part)) { out.append(m) }
        }
        return out
    }
}

/// Fel vid läsning av en `.ljud`-fil. Bär aldrig något värde ur filen.
public enum SoundFileError: Error, Equatable, Sendable {
    case tooShort
    case badMagic
    case unsupportedVersion
}

/// METOD M38 · BESLUT B47
/// `ljud-<start>.ljud`: måtten per sekund för en natt.
///
///     huvud   magin `IDLJ` (4 byte), version (u8), starten som Unix-sekund i
///             telefonens klocka (i64), klasslistans version (u8)  = 14 byte
///     post    sekunder sedan start (u32), level, levelA, peak och åtta band
///             (Int16 vardera), onset (u8) och tolv klasser (u8)   = 39 byte
///
/// Allt i little endian. En sekund som saknas är ett glapp. Huvudet skrivs en
/// gång och posterna läggs till en i taget, så att en avstängd app förlorar
/// högst en sekund; en halv post sist i filen hoppas över vid läsning.
public enum SoundFile {
    public static let magic: [UInt8] = [0x49, 0x44, 0x4C, 0x4A]
    public static let version: UInt8 = 1
    public static let headerBytes = 14
    /// METOD M38. En post: 4 + 11 · 2 + 1 + 12 byte.
    public static let recordBytes = 39

    /// Det en fil innehåller.
    public struct Contents: Equatable, Sendable {
        /// Unix-sekunder, telefonens klocka, när lyssnaren startade.
        public var start: Int
        public var classListVersion: UInt8
        public var seconds: [SoundSecond]
        /// Byte sist i filen som inte räckte till en hel post.
        public var truncatedBytes: Int

        public init(start: Int, classListVersion: UInt8 = SoundClasses.version, seconds: [SoundSecond],
                    truncatedBytes: Int = 0) {
            self.start = start
            self.classListVersion = classListVersion
            self.seconds = seconds
            self.truncatedBytes = truncatedBytes
        }
    }

    /// Filstammen för en start: `ljud-2026-10-14T21-03-00Z`, UTC. Till filens
    /// namn läggs `.ljud` eller `.markningar`.
    public static func stem(start: Int) -> String {
        let days: Int = Int((Double(start) / 86_400).rounded(.down))
        let rest: Int = start - days * 86_400
        let (y, m, d) = civil(daysSince1970: days)
        let hh: Int = rest / 3_600
        let mm: Int = (rest % 3_600) / 60
        let ss: Int = rest % 60
        return "ljud-" + String(format: "%04d-%02d-%02dT%02d-%02d-%02dZ", y, m, d, hh, mm, ss)
    }

    /// Starten (Unix-sekunder) ur en filstam, `ljud-2026-10-14T21-03-00Z`; `nil` för allt annat. Tolkningen är
    /// för hand (BESLUT B6) och samma som för en gammal inspelning (`RecordingStem`).
    public static func start(ofStem s: String) -> Int? {
        guard s.hasPrefix("ljud-") else { return nil }
        return RecordingStem.start(ofStem: String(s.dropFirst(5))).map { (d: Date) -> Int in
            Int(d.timeIntervalSince1970.rounded())
        }
    }

    /// Datum ur dagar sedan 1970-01-01 (Howard Hinnants algoritm); ingen DateFormatter,
    /// så att telefonens språk och zon inte spelar in.
    static func civil(daysSince1970 z0: Int) -> (Int, Int, Int) {
        let z: Int = z0 + 719_468
        let era: Int = (z >= 0 ? z : z - 146_096) / 146_097
        let doe: Int = z - era * 146_097
        let yoe: Int = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy: Int = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp: Int = (5 * doy + 2) / 153
        let d: Int = doy - (153 * mp + 2) / 5 + 1
        let m: Int = mp < 10 ? mp + 3 : mp - 9
        let y: Int = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, m, d)
    }

    // MARK: Skrivning

    public static func header(start: Int, classListVersion: UInt8 = SoundClasses.version) -> Data {
        var b: [UInt8] = magic
        b.append(version)
        let s: UInt64 = UInt64(bitPattern: Int64(start))
        for k in 0..<8 { b.append(UInt8((s >> UInt64(8 * k)) & 0xFF)) }
        b.append(classListVersion)
        return Data(b)
    }

    /// En post. Bandens och klassernas antal fylls ut eller kortas till 8 och 12.
    public static func record(_ s: SoundSecond) -> Data {
        var b: [UInt8] = []
        b.reserveCapacity(recordBytes)
        let t: UInt32 = UInt32(truncatingIfNeeded: max(0, s.second))
        for k in 0..<4 { b.append(UInt8((t >> UInt32(8 * k)) & 0xFF)) }
        putInt16(&b, s.level)
        putInt16(&b, s.levelA)
        putInt16(&b, s.peak)
        for i in 0..<SoundSecond.bandCount {
            putInt16(&b, i < s.bands.count ? s.bands[i] : Int16(-1200))
        }
        b.append(s.onset)
        for i in 0..<SoundSecond.classCount {
            b.append(i < s.classes.count ? s.classes[i] : 0)
        }
        return Data(b)
    }

    /// Hela filen på en gång.
    public static func encode(start: Int, seconds: [SoundSecond],
                              classListVersion: UInt8 = SoundClasses.version) -> Data {
        var d: Data = header(start: start, classListVersion: classListVersion)
        for s in seconds { d.append(record(s)) }
        return d
    }

    private static func putInt16(_ b: inout [UInt8], _ v: Int16) {
        let u: UInt16 = UInt16(bitPattern: v)
        b.append(UInt8(u & 0xFF))
        b.append(UInt8(u >> 8))
    }

    // MARK: Läsning

    public static func decode(_ data: Data) throws -> Contents {
        let b: [UInt8] = [UInt8](data)
        guard b.count >= headerBytes else { throw SoundFileError.tooShort }
        guard Array(b[0..<4]) == magic else { throw SoundFileError.badMagic }
        guard b[4] == version else { throw SoundFileError.unsupportedVersion }
        var raw: UInt64 = 0
        for k in 0..<8 { raw |= UInt64(b[5 + k]) << UInt64(8 * k) }
        let start: Int = Int(Int64(bitPattern: raw))
        let classVersion: UInt8 = b[13]
        let body: Int = b.count - headerBytes
        let n: Int = body / recordBytes
        var out: [SoundSecond] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let o: Int = headerBytes + i * recordBytes
            var t: UInt32 = 0
            for k in 0..<4 { t |= UInt32(b[o + k]) << UInt32(8 * k) }
            var bands: [Int16] = []
            for j in 0..<SoundSecond.bandCount { bands.append(int16(b, o + 10 + 2 * j)) }
            let classes: [UInt8] = Array(b[(o + 27)..<(o + 39)])
            out.append(SoundSecond(second: Int(t), level: int16(b, o + 4), levelA: int16(b, o + 6),
                                   peak: int16(b, o + 8), bands: bands, onset: b[o + 26], classes: classes))
        }
        return Contents(start: start, classListVersion: classVersion, seconds: out,
                        truncatedBytes: body - n * recordBytes)
    }

    private static func int16(_ b: [UInt8], _ o: Int) -> Int16 {
        Int16(bitPattern: UInt16(b[o]) | (UInt16(b[o + 1]) << 8))
    }
}
