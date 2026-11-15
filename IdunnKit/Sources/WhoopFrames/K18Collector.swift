import Foundation

/// METOD M24 · METOD M28 · BESLUT B30
/// K18-poster ur dygnsfilernas notiser, en notis i taget (A2, appens koppling).
/// En dygnsfil kan vara tiotals MB, så den läses strömmande
/// (`RawFrameLog.forEach`) och hålls aldrig hel i minnet: ramarna fogas ihop
/// som i `K18Series(notifications:)` (samma `FrameAssembly.Stream`, en ram per
/// karakteristik i taget) och bara posterna med bandets tid i `[from, to)`
/// sparas. Tiden som filtreras på är postens egen (i7), inte notisens: en natt
/// som hörs först vid morgonens synk ligger i en senare fil än den mättes.
///
/// Ger exakt samma poster som `K18Series(notifications:)` över samma notiser
/// (provat), utom att poster utanför intervallet inte finns.
public struct K18Collector: Sendable {
    private var stream = FrameAssembly.Stream()
    private var records: [K18Record] = []
    /// Bara poster med bandets tid från och med `from` och före `to` (Unix-sekunder).
    public let from: Int
    public let to: Int
    /// K18-ramar vars CRC32 inte stämde. De räknas inte med.
    public private(set) var badChecksums = 0

    public init(from: Int = Int.min, to: Int = Int.max) {
        self.from = from
        self.to = to
    }

    public init(from: Date, to: Date) {
        self.from = Int(from.timeIntervalSince1970.rounded(.down))
        self.to = Int(to.timeIntervalSince1970.rounded(.up))
    }

    /// Matas med varje notis i den ordning den sparades.
    public mutating func add(_ n: RawFrame) {
        guard let frame = stream.add(n), frame.type == K18Record.packetType else { return }
        guard frame.inner.count > 1, Int(frame.inner[1]) == K18Record.family else { return }
        guard frame.crc32OK else {
            badChecksums += 1
            return
        }
        guard let r = K18Record.decode(inner: frame.inner), r.time >= from, r.time < to else { return }
        records.append(r)
    }

    /// Matar in en dygnsfils innehåll (`.t2.jsonl`) notis för notis. Ger antalet
    /// rader som inte gick att tolka.
    @discardableResult
    public mutating func read(log data: Data) -> Int {
        RawFrameLog.forEach(data) { (n: RawFrame) -> Void in add(n) }
    }

    /// BESLUT B41 · METOD M34. Matar in ett dygnsarkiv i stället för dygnsfilen:
    /// samma poster, samma tidsfilter och samma räkning av trasiga ramar som
    /// `read(log:)` över filen arkivet byggdes ur.
    public mutating func read(archive: DayArchive) {
        for r in archive.k18Records where r.time >= from && r.time < to { records.append(r) }
        badChecksums += archive.badK18Checksums
    }

    /// Antal poster som sparats hittills (före dubblettborttagning).
    public var count: Int { records.count }

    /// Serien: sorterad, högst en post per sekund (den senaste gäller, som
    /// `K18Series`).
    public func series() -> K18Series {
        K18Series(records: records)
    }
}
