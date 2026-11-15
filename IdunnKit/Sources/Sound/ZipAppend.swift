import Foundation
import WhoopFrames

/// BESLUT B22 · BESLUT B55
/// Lägger filer till en zip som `ZipArchive.make` redan skrivit, utan att
/// röra de som finns: nattens zip (`ExportPackage`) packas av en annan modul
/// och lämnas som den är, och ljudet läggs efter. De gamla filernas byte
/// kopieras ordagrant; bara katalogen i slutet skrivs om.
///
///     gammal zip   [lokala filer][katalog][slut]
///     ny zip       [gamla lokala][nya lokala][gamla katalogen][nya katalogen, flyttad][slut]
///
/// Katalogposterna för de nya filerna pekar på var filen ligger i *sin* zip,
/// så varje startplats flyttas lika långt som de gamla lokala filerna tar plats.
/// Bara zip-filer som `ZipArchive` skriver förstås (inga kommentarer, ingen
/// zip64): allt annat ger `nil`.
public enum ZipAppend {
    private static let localEnd: Int = 0x0605_4B50
    private static let centralHeader: Int = 0x0201_4B50

    private struct Directory {
        var count: Int
        var size: Int
        var offset: Int
    }

    /// Zip-filen med `entries` efter de som fanns. `nil` om `zip` inte är en
    /// zip-fil av det slag `ZipArchive` skriver, eller om resultatet blir för
    /// stort för formatet (65 535 filer, 4 GB).
    public static func append(_ entries: [ZipArchive.Entry], to zip: Data, date: Date = Date(),
                              compress: Bool = true) -> Data? {
        if entries.isEmpty { return zip }
        let old: [UInt8] = [UInt8](zip)
        guard let oldDir: Directory = directory(old) else { return nil }
        let added: [UInt8] = [UInt8](ZipArchive.make(entries, date: date, compress: compress))
        guard let newDir: Directory = directory(added) else { return nil }
        let total: Int = oldDir.count + newDir.count
        guard total <= 0xFFFF else { return nil }

        var out = Data()
        out.reserveCapacity(old.count + added.count)
        out.append(contentsOf: old[0..<oldDir.offset])
        out.append(contentsOf: added[0..<newDir.offset])
        let centralStart: Int = out.count
        guard centralStart <= 0xFFFF_FFFF else { return nil }
        out.append(contentsOf: old[oldDir.offset..<(oldDir.offset + oldDir.size)])

        var pos: Int = newDir.offset
        let end: Int = newDir.offset + newDir.size
        while pos < end {
            guard pos + 46 <= end, u32(added, pos) == centralHeader else { return nil }
            let length: Int = 46 + u16(added, pos + 28) + u16(added, pos + 30) + u16(added, pos + 32)
            guard pos + length <= end else { return nil }
            var record: [UInt8] = Array(added[pos..<(pos + length)])
            let moved: Int = u32(added, pos + 42) + oldDir.offset
            guard moved <= 0xFFFF_FFFF else { return nil }
            put32(&record, 42, moved)
            out.append(contentsOf: record)
            pos += length
        }

        let centralSize: Int = out.count - centralStart
        var tail: [UInt8] = []
        put32(&tail, 0, localEnd)
        tail.append(contentsOf: [0, 0, 0, 0])
        put16(&tail, 8, total)
        put16(&tail, 10, total)
        put32(&tail, 12, centralSize)
        put32(&tail, 16, centralStart)
        put16(&tail, 20, 0)
        out.append(contentsOf: tail)
        return out
    }

    /// Katalogens plats ur slutposten, eller `nil` om zip-filen inte är som `ZipArchive` skriver den.
    private static func directory(_ b: [UInt8]) -> Directory? {
        let n: Int = b.count
        guard n >= 22, u32(b, n - 22) == localEnd, u16(b, n - 2) == 0 else { return nil }
        let d = Directory(count: u16(b, n - 12), size: u32(b, n - 10), offset: u32(b, n - 6))
        guard d.offset + d.size + 22 == n else { return nil }
        return d
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }

    private static func u32(_ b: [UInt8], _ o: Int) -> Int { u16(b, o) | (u16(b, o + 2) << 16) }

    /// Skriver `v` på plats `o`; växer listan om den är för kort.
    private static func put16(_ b: inout [UInt8], _ o: Int, _ v: Int) {
        while b.count < o + 2 { b.append(0) }
        b[o] = UInt8(v & 0xFF)
        b[o + 1] = UInt8((v >> 8) & 0xFF)
    }

    private static func put32(_ b: inout [UInt8], _ o: Int, _ v: Int) {
        put16(&b, o, v & 0xFFFF)
        put16(&b, o + 2, (v >> 16) & 0xFFFF)
    }
}
