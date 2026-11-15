import Foundation

/// BESLUT B22. En zip-fil i minnet, för exporten av en natt. Bara det som
/// behövs: filer i roten, under 4 GB, utan kryptering. På Apple-plattformarna
/// komprimeras varje fil med DEFLATE (`NSData.compressed(using: .zlib)` ger
/// rå DEFLATE enligt RFC 1951, det zip vill ha) om det blir mindre; annars,
/// och på Linux, lagras den som den är. Båda läses av alla zip-program och av
/// Pythons `zipfile`.
public enum ZipArchive {
    public struct Entry: Sendable {
        public var name: String
        public var data: Data
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    public static func make(_ entries: [Entry], date: Date = Date(), compress: Bool = true) -> Data {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = dos(date)
        for e in entries {
            let name = Data(e.name.utf8)
            let crc: UInt32 = FrameAssembly.crc32(e.data)
            var method: UInt16 = 0
            var payload = e.data
            if compress, let packed = deflate(e.data), packed.count < e.data.count {
                method = 8
                payload = packed
            }
            let offset: UInt32 = UInt32(out.count)
            // Lokalt huvud.
            out.append(le32(0x0403_4B50))
            out.append(le16(20))
            out.append(le16(0x0800))        // namnet är UTF-8
            out.append(le16(method))
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(crc))
            out.append(le32(UInt32(payload.count)))
            out.append(le32(UInt32(e.data.count)))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))
            out.append(name)
            out.append(payload)
            // Katalogen.
            central.append(le32(0x0201_4B50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(0x0800))
            central.append(le16(method))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(crc))
            central.append(le32(UInt32(payload.count)))
            central.append(le32(UInt32(e.data.count)))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(name)
        }
        let centralOffset: UInt32 = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    static func deflate(_ data: Data) -> Data? {
        #if canImport(Darwin)
        return try? (data as NSData).compressed(using: .zlib) as Data
        #else
        return nil
        #endif
    }

    /// Zip-filens tid: MS-DOS-format i UTC, på två sekunder när.
    static func dos(_ date: Date) -> (time: UInt16, date: UInt16) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year: Int = max(1980, c.year ?? 1980)
        let time: Int = ((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2)
        let day: Int = ((year - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)
        return (UInt16(time), UInt16(day))
    }

    private static func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8(v >> 8)])
    }

    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
