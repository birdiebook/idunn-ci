import Foundation

/// METOD M34 · BESLUT B41 · METOD M24 · METOD M12
/// Dygnsarkivet (PLAN.md L1, det ljumma lagret): ett dygns ramar som packade
/// binärposter. Dygnsfilen (`dygn-<datum>.t2.jsonl`) är rå och stor, runt 210
/// byte JSON per K18-post som är 112 byte; arkivet sparar de 112 byten, hela
/// inre delen med alla okända fält, och packar dem med DEFLATE där det finns.
/// Rådygnet får raderas först när arkivet är skrivet, läst tillbaka och lika
/// (`ArchiveRule`); analysen kan räkna om ur arkivet när metoden ändras.
///
/// Ett arkiv hör till en dygnsfil, alltså till datumet notiserna *hördes*
/// (METOD M27), inte till postens egen tid: en natt som Whoop synkar först på
/// morgonen ligger i morgonens dygn. Därför påverkar sena synkar aldrig ett
/// färdigt arkiv, och `K18Days` läser arkiven av samma namn som filerna.
///
/// **Vad som sparas:** hela ramar med giltig CRC32 av de typer som bär bandets
/// mätningar, händelser och synkmärken (`keptTypes`: 40, 43, 47, 48, 49, 51, 52,
/// 53, 54, 56, alltså typ 47 med alla familjer: K18, K26 …, händelserna och
/// metadatan), och dygnets sidofil ordagrant (zon, zonbyten, märken).
/// **Vad som inte sparas:** kommandosvar och loggtext (36, 38, 50, 55) och
/// okända typer (räknas i `droppedFrames`), ramar med fel CRC32 (räknas), ofullständiga
/// ramar, `…0007`:s textström och uppdelningen i notiser (en ram blir en notis
/// vid återskapandet), och tiderna är hela millisekunder.
public struct DayArchive: Equatable, Sendable {
    /// Formatversionen i huvudet. Höjs när bytelayouten ändras; en äldre
    /// läsare vägrar en nyare (`Failure.unsupportedVersion`).
    public static let version = 1

    /// Typerna vars ramar sparas: de som har en egen tid i posten (jfr
    /// `OffWrist.recordTimes`), alltså mätningar, händelser och metadata.
    public static let keptTypes: Set<Int> = [40, 43, 47, 48, 49, 51, 52, 53, 54, 56]

    /// En sparad ram: när telefonen hörde den, på vilken karakteristik, huvudets
    /// byte 4–5 och hela inre delen.
    public struct Entry: Equatable, Sendable {
        /// Notisen som gjorde ramen hel, i hela millisekunder sedan 1970.
        public var heardMilliseconds: Int
        public var characteristic: String
        /// Huvudets byte 4 och 5 (betydelse okänd), alltid två byte.
        public var headerBytes: [UInt8]
        /// Hela inre delen, utan huvud och CRC32.
        public var inner: [UInt8]

        public init(heardMilliseconds: Int, characteristic: String, headerBytes: [UInt8], inner: [UInt8]) {
            self.heardMilliseconds = heardMilliseconds
            self.characteristic = characteristic
            self.headerBytes = headerBytes.count == 2 ? headerBytes : [0, 0]
            self.inner = inner
        }

        public var heard: Date { Date(timeIntervalSince1970: Double(heardMilliseconds) / 1000) }

        /// Pakettypen: inre delens första byte.
        public var type: Int? { inner.first.map { Int($0) } }

        /// Typ 47, familj 18: en K18-post (jfr `K18Record`).
        public var isK18: Bool {
            type == K18Record.packetType && inner.count > 1 && Int(inner[1]) == K18Record.family
        }

        /// Hela ramen som bandet skickade den: huvud, inre del och CRC32.
        public var frameBytes: [UInt8] {
            let length = inner.count + 4
            var b: [UInt8] = [RawFrame.startByte, 0x01, UInt8(length & 0xFF), UInt8((length >> 8) & 0xFF),
                              headerBytes[0], headerBytes[1]]
            let h = FrameAssembly.crc16Modbus(b)
            b += [UInt8(h & 0xFF), UInt8(h >> 8)]
            b += inner
            let c = FrameAssembly.crc32(inner)
            for k in 0..<4 { b.append(UInt8((c >> UInt32(8 * k)) & 0xFF)) }
            return b
        }
    }

    /// Dygnet arkivet gäller (dygnsfilens datum).
    public var day: DayLog.Day
    /// Rådygnets storlek när arkivet byggdes: `.t2.jsonl` och sidofilen. Det är
    /// så appen ser att rådygnet vuxit sedan dess (`ArchiveRule.needsArchive`).
    public var sourceFrameBytes: Int
    public var sourceSidecarBytes: Int
    /// Notiser i rådygnet.
    public var notifications = 0
    /// K18-ramar med fel CRC32. De räknas inte med (som `K18Series`).
    public var badK18Checksums = 0
    /// Övriga ramar med fel CRC32.
    public var otherBadChecksums = 0
    /// Hela ramar av typer som inte sparas.
    public var droppedFrames = 0
    /// Dygnets sidofil ordagrant (`RecordingLog`: zon, zonbyten, märken).
    public var sidecar: Data
    /// K18-posterna, alla med samma längd (`stride`), i den ordning de hördes.
    public private(set) var k18Frames: [Entry] = []
    /// Övriga sparade ramar (K26, händelser, metadata, en K18 av annan längd),
    /// i den ordning de hördes.
    public private(set) var otherFrames: [Entry] = []

    public init(day: DayLog.Day, sourceFrameBytes: Int = 0, sourceSidecarBytes: Int = 0, sidecar: Data = Data()) {
        self.day = day
        self.sourceFrameBytes = sourceFrameBytes
        self.sourceSidecarBytes = sourceSidecarBytes
        self.sidecar = sidecar
    }

    /// Alla sparade ramar: K18-posterna först, sedan de övriga.
    public var frames: [Entry] { k18Frames + otherFrames }

    /// K18-posternas längd (inre delen). Den första K18:ns längd avgör; en K18
    /// av annan längd hamnar bland de övriga.
    public var stride: Int? { k18Frames.first?.inner.count }

    /// Lägger en ram sist, på rätt lista.
    public mutating func add(_ e: Entry) {
        if e.isK18, k18Frames.isEmpty || e.inner.count == k18Frames[0].inner.count {
            k18Frames.append(e)
        } else {
            otherFrames.append(e)
        }
    }

    // MARK: Ur rådygnet

    /// Arkivet ur dygnets rådata: sidofilen och `.t2.jsonl`, fogade till ramar
    /// som `K18Series(notifications:)` gör (en ram per karakteristik i taget).
    /// En ram får tiden för sin sista notis (`FrameAssembly.Frame.time`).
    public static func build(day: DayLog.Day, sidecar: Data?, frames log: Data?) -> DayArchive {
        var a = DayArchive(day: day, sourceFrameBytes: log?.count ?? 0, sourceSidecarBytes: sidecar?.count ?? 0,
                           sidecar: sidecar ?? Data())
        guard let log else { return a }
        var stream = FrameAssembly.Stream()
        RawFrameLog.forEach(log) { (n: RawFrame) -> Void in
            a.notifications += 1
            if let f = stream.add(n) { a.take(f) }
        }
        return a
    }

    private mutating func take(_ f: FrameAssembly.Frame) {
        let k18 = f.type == K18Record.packetType && f.inner.count > 1 && Int(f.inner[1]) == K18Record.family
        guard f.crc32OK else {
            if k18 { badK18Checksums += 1 } else { otherBadChecksums += 1 }
            return
        }
        guard let t = f.type, Self.keptTypes.contains(t) else {
            droppedFrames += 1
            return
        }
        add(Entry(heardMilliseconds: Int((f.time.timeIntervalSince1970 * 1000).rounded()),
                  characteristic: f.characteristic, headerBytes: f.headerBytes, inner: f.inner))
    }

    // MARK: Det som läses ur arkivet

    /// K18-posterna avkodade, i den ordning de hördes (K18-listan, sedan en
    /// eventuell K18 av annan längd). Samma poster som rådygnet ger.
    public var k18Records: [K18Record] {
        let alla = otherFrames.filter { (e: Entry) -> Bool in e.isK18 }
        return (k18Frames + alla).compactMap { (e: Entry) -> K18Record? in K18Record.decode(inner: e.inner) }
    }

    /// Antal sparade ramar per pakettyp, för mätningen.
    public var typeCounts: [Int: Int] {
        var ut: [Int: Int] = [:]
        for e in frames { if let t = e.type { ut[t, default: 0] += 1 } }
        return ut
    }

    /// Dygnets notiser återskapade som en `.t2.jsonl` (`RawFrameLog`), i
    /// tidsordning efter när telefonen hörde dem: en notis per sparad ram,
    /// med huvud och kontrollsummor, så att `FrameAssembly`, exporten och
    /// `ListenerStatus` läser den som en riktig dygnsfil. Det som inte sparas
    /// står i filhuvudet här ovan.
    public func rawLog() -> Data {
        let ordnade = frames.enumerated()
            .sorted { (a: (offset: Int, element: Entry), b: (offset: Int, element: Entry)) -> Bool in
                (a.element.heardMilliseconds, a.offset) < (b.element.heardMilliseconds, b.offset)
            }
            .map { (p: (offset: Int, element: Entry)) -> Entry in p.element }
        var d = Data()
        for e in ordnade {
            d.append(RawFrameLog.line(RawFrame(time: e.heard, characteristic: e.characteristic,
                                                bytes: e.frameBytes)))
        }
        return d
    }

    /// Innehåller det här arkivet allt som `other` har? Sant om `other`s ramar
    /// är de sista i varje lista, sidofilen slutar med `other`s och inga
    /// räknare är mindre. Lika arkiv täcker varandra. Det är vad som prövas
    /// innan ett rådygn raderas: arkivet läst tillbaka ska täcka rådygnet.
    public func covers(_ other: DayArchive) -> Bool {
        day == other.day
            && Self.endsWith(k18Frames, other.k18Frames)
            && Self.endsWith(otherFrames, other.otherFrames)
            && sidecar.count >= other.sidecar.count
            && sidecar.suffix(other.sidecar.count) == other.sidecar
            && badK18Checksums >= other.badK18Checksums
            && otherBadChecksums >= other.otherBadChecksums
            && droppedFrames >= other.droppedFrames
            && notifications >= other.notifications
    }

    private static func endsWith(_ a: [Entry], _ b: [Entry]) -> Bool {
        a.count >= b.count && Array(a.suffix(b.count)) == b
    }

    private static func startsWith(_ a: [Entry], _ b: [Entry]) -> Bool {
        a.count >= b.count && Array(a.prefix(b.count)) == b
    }

    /// Arkivet efter att rådygnet `raw` (nybyggt ur filen) lästs om. Vanligt
    /// fall: rådygnet har vuxit sedan arkivet byggdes och är ett överskott av
    /// det, så det nya gäller. Sällsynt fall: rådygnet raderades och en fil för
    /// samma datum skapades på nytt (klockan flyttades tillbaka); då läggs det
    /// nya till det gamla i stället för att ersätta det. Inget som redan står i
    /// arkivet försvinner någon av vägarna.
    public func updated(with raw: DayArchive) -> DayArchive {
        if covers(raw) {
            var r = self
            r.sourceFrameBytes = raw.sourceFrameBytes
            r.sourceSidecarBytes = raw.sourceSidecarBytes
            return r
        }
        if day == raw.day, Self.startsWith(raw.k18Frames, k18Frames), Self.startsWith(raw.otherFrames, otherFrames),
           raw.sidecar.count >= sidecar.count, raw.sidecar.prefix(sidecar.count) == sidecar {
            return raw
        }
        var m = self
        for e in raw.frames { m.add(e) }
        m.sidecar.append(raw.sidecar)
        m.sourceFrameBytes = raw.sourceFrameBytes
        m.sourceSidecarBytes = raw.sourceSidecarBytes
        m.notifications += raw.notifications
        m.badK18Checksums += raw.badK18Checksums
        m.otherBadChecksums += raw.otherBadChecksums
        m.droppedFrames += raw.droppedFrames
        return m
    }
}

// MARK: - Filen

extension DayArchive {
    public enum Failure: Error, Equatable, Sendable {
        case tooShort
        case notAnArchive
        case unsupportedVersion(Int)
        /// Kroppen är DEFLATE-packad och plattformen kan inte packa upp den (Linux).
        case unsupportedCompression
        /// Längd, kontrollsumma eller innehåll stämmer inte.
        case corrupt
    }

    /// Filens fasta huvud, 38 byte: `IDA`, version, metod, reserv, datum,
    /// rådygnets storlekar, kroppens längd (lagrad och opackad) och CRC32 över
    /// den opackade kroppen. Läses utan att kroppen packas upp.
    public struct Header: Equatable, Sendable {
        public static let size = 38
        static let magic: [UInt8] = [0x49, 0x44, 0x41]   // "IDA"

        public var version: Int
        /// 0 = lagrad som den är, 1 = rå DEFLATE (RFC 1951, som ZipArchive).
        public var method: Int
        public var day: DayLog.Day
        public var sourceFrameBytes: Int
        public var sourceSidecarBytes: Int
        public var storedLength: Int
        public var bodyLength: Int
        public var crc32: UInt32

        public static func read(_ data: Data) throws -> Header {
            guard data.count >= size else { throw Failure.tooShort }
            let b = [UInt8](data.prefix(size))
            guard Array(b[0..<3]) == magic else { throw Failure.notAnArchive }
            var r = ByteReader(b)
            _ = try r.take(3)
            let version = Int(try r.u8())
            guard version == DayArchive.version else { throw Failure.unsupportedVersion(version) }
            let method = Int(try r.u8())
            _ = try r.u8()
            let year = Int(try r.u16())
            let month = Int(try r.u8())
            let dayOfMonth = Int(try r.u8())
            let sf = Int(try r.u64())
            let ss = Int(try r.u64())
            let stored = Int(try r.u32())
            let body = Int(try r.u32())
            let crc = try r.u32()
            return Header(version: version, method: method,
                          day: DayLog.Day(year: year, month: month, day: dayOfMonth),
                          sourceFrameBytes: sf, sourceSidecarBytes: ss, storedLength: stored,
                          bodyLength: body, crc32: crc)
        }
    }

    /// Arkivet som fil. `compress`: packa kroppen med DEFLATE om det finns
    /// (Apple) och blir mindre; annars lagras den som den är, som på Linux.
    public func encode(compress: Bool = true) -> Data {
        let body = Data(makeBody())
        var method: UInt8 = 0
        var stored = body
        if compress, let packed = ZipArchive.deflate(body), packed.count < body.count {
            method = 1
            stored = packed
        }
        var w = ByteWriter()
        w.bytes(Header.magic)
        w.u8(UInt8(Self.version))
        w.u8(method)
        w.u8(0)
        w.u16(UInt16(day.year))
        w.u8(UInt8(day.month))
        w.u8(UInt8(day.day))
        w.u64(UInt64(sourceFrameBytes))
        w.u64(UInt64(sourceSidecarBytes))
        w.u32(UInt32(stored.count))
        w.u32(UInt32(body.count))
        w.u32(FrameAssembly.crc32(body))
        var out = Data(w.out)
        out.append(stored)
        return out
    }

    /// Arkivet ur en fil. Kastar `Failure` vid fel version, okänd packning,
    /// trasig längd eller kontrollsumma.
    public static func decode(_ data: Data) throws -> DayArchive {
        let h = try Header.read(data)
        let stored = data.dropFirst(Header.size)
        guard stored.count == h.storedLength else { throw Failure.corrupt }
        var body = Data(stored)
        switch h.method {
        case 0: break
        case 1:
            guard let raw = inflate(body) else { throw Failure.unsupportedCompression }
            body = raw
        default: throw Failure.unsupportedCompression
        }
        guard body.count == h.bodyLength, FrameAssembly.crc32(body) == h.crc32 else { throw Failure.corrupt }
        return try parse(body: [UInt8](body), header: h)
    }

    static func inflate(_ data: Data) -> Data? {
        #if canImport(Darwin)
        return try? (data as NSData).decompressed(using: .zlib) as Data
        #else
        return nil
        #endif
    }

    // MARK: Kroppen

    /// Kroppen (allt little-endian):
    ///
    ///     u32 notiser · u32 K18 med fel CRC32 · u32 övriga med fel CRC32 · u32 ej sparade
    ///     u32 sidofilens längd, sidofilen
    ///     u16 antal karakteristiker, varje: u16 längd, namnet (ASCII)
    ///     u8 antal sektioner (0–2), varje:
    ///       1 = K18:   u8 1, u16 postlängd S, u32 antal n, kolumnerna
    ///       2 = övriga: u8 2, u32 antal n, kolumnerna, sedan inre delarna efter varandra
    ///
    /// En rad i K18-sektionen är `u64 hörd (ms) · u8 karakteristik · u8 u8 huvudets
    /// byte 4–5 · S byte inre del` (11 + S byte). I de övriga är raden
    /// `u64 · u8 · u8 u8 · u16 inre längd` (13 byte). Kolumnerna skrivs byteplan
    /// för byteplan: byte 0 i alla n rader, sedan byte 1 …, och varje plan som
    /// skillnaden mot föregående rad (mod 256). Det som är lika rad för rad
    /// (nollor, typen, familjen) blir långa nollor och tiden stegar med ett;
    /// det är det som gör att DEFLATE kommer åt posterna.
    func makeBody() -> [UInt8] {
        var w = ByteWriter()
        w.u32(UInt32(notifications))
        w.u32(UInt32(badK18Checksums))
        w.u32(UInt32(otherBadChecksums))
        w.u32(UInt32(droppedFrames))
        w.u32(UInt32(sidecar.count))
        w.bytes([UInt8](sidecar))

        var names: [String] = []
        var index: [String: Int] = [:]
        for e in k18Frames + otherFrames where index[e.characteristic] == nil {
            index[e.characteristic] = names.count
            names.append(e.characteristic)
        }
        precondition(names.count <= Int(UInt16.max), "för många karakteristiker")
        w.u16(UInt16(names.count))
        for n in names {
            let b = Array(n.utf8)
            precondition(b.count <= Int(UInt16.max), "för långt karakteristiknamn")
            w.u16(UInt16(b.count))
            w.bytes(b)
        }

        var sections = 0
        if !k18Frames.isEmpty { sections += 1 }
        if !otherFrames.isEmpty { sections += 1 }
        w.u8(UInt8(sections))

        if !k18Frames.isEmpty, let s = stride {
            w.u8(1)
            w.u16(UInt16(s))
            w.u32(UInt32(k18Frames.count))
            let width = 11 + s
            var rows: [UInt8] = []
            rows.reserveCapacity(k18Frames.count * width)
            for e in k18Frames {
                Self.appendFixed(&rows, e, index: index[e.characteristic] ?? 0)
                rows += e.inner
            }
            Self.writePlanes(&w, rows: rows, count: k18Frames.count, width: width)
        }
        if !otherFrames.isEmpty {
            w.u8(2)
            w.u32(UInt32(otherFrames.count))
            var rows: [UInt8] = []
            for e in otherFrames {
                Self.appendFixed(&rows, e, index: index[e.characteristic] ?? 0)
                precondition(e.inner.count <= Int(UInt16.max), "för lång ram")
                rows.append(UInt8(e.inner.count & 0xFF))
                rows.append(UInt8(e.inner.count >> 8))
            }
            Self.writePlanes(&w, rows: rows, count: otherFrames.count, width: 13)
            for e in otherFrames { w.bytes(e.inner) }
        }
        return w.out
    }

    /// Radens fasta del: hörd tid (u64), karakteristikens nummer, huvudets två byte.
    private static func appendFixed(_ rows: inout [UInt8], _ e: Entry, index: Int) {
        let t = UInt64(bitPattern: Int64(e.heardMilliseconds))
        for k in 0..<8 { rows.append(UInt8((t >> UInt64(8 * k)) & 0xFF)) }
        rows.append(UInt8(index))
        rows.append(e.headerBytes[0])
        rows.append(e.headerBytes[1])
    }

    private static func writePlanes(_ w: inout ByteWriter, rows: [UInt8], count n: Int, width: Int) {
        w.out.reserveCapacity(w.out.count + n * width)
        for j in 0..<width {
            var prev: UInt8 = 0
            for i in 0..<n {
                let v = rows[i * width + j]
                w.out.append(v &- prev)
                prev = v
            }
        }
    }

    private static func readPlanes(_ r: inout ByteReader, count n: Int, width: Int) throws -> [UInt8] {
        guard width > 0, n <= r.remaining / width else { throw Failure.corrupt }
        let planes = try r.take(n * width)
        var rows = [UInt8](repeating: 0, count: n * width)
        var p = planes.startIndex
        for j in 0..<width {
            var acc: UInt8 = 0
            for i in 0..<n {
                acc = acc &+ planes[p]
                rows[i * width + j] = acc
                p += 1
            }
        }
        return rows
    }

    private static func parse(body: [UInt8], header h: Header) throws -> DayArchive {
        var r = ByteReader(body)
        var a = DayArchive(day: h.day, sourceFrameBytes: h.sourceFrameBytes, sourceSidecarBytes: h.sourceSidecarBytes)
        a.notifications = Int(try r.u32())
        a.badK18Checksums = Int(try r.u32())
        a.otherBadChecksums = Int(try r.u32())
        a.droppedFrames = Int(try r.u32())
        let sideLength = Int(try r.u32())
        a.sidecar = Data(try r.take(sideLength))

        var names: [String] = []
        let nameCount = Int(try r.u16())
        for _ in 0..<nameCount {
            let len = Int(try r.u16())
            let namn = try r.take(len)
            names.append(String(decoding: namn, as: UTF8.self))
        }
        func entry(_ row: ArraySlice<UInt8>, inner: [UInt8]) throws -> Entry {
            var q = ByteReader(Array(row.prefix(11)))
            let t = Int64(bitPattern: try q.u64())
            let idx = Int(try q.u8())
            guard idx < names.count else { throw Failure.corrupt }
            let h0 = try q.u8()
            let h1 = try q.u8()
            return Entry(heardMilliseconds: Int(t), characteristic: names[idx], headerBytes: [h0, h1], inner: inner)
        }

        let sections = Int(try r.u8())
        var seen: Set<UInt8> = []
        for _ in 0..<sections {
            let kind = try r.u8()
            guard seen.insert(kind).inserted else { throw Failure.corrupt }
            switch kind {
            case 1:
                let s = Int(try r.u16())
                let n = Int(try r.u32())
                let width = 11 + s
                let rows = try readPlanes(&r, count: n, width: width)
                for i in 0..<n {
                    let base = i * width
                    let e = try entry(rows[base..<(base + 11)], inner: Array(rows[(base + 11)..<(base + width)]))
                    a.k18Frames.append(e)
                }
            case 2:
                let n = Int(try r.u32())
                let rows = try readPlanes(&r, count: n, width: 13)
                var lengths: [Int] = []
                var total = 0
                for i in 0..<n {
                    let len = Int(rows[i * 13 + 11]) | (Int(rows[i * 13 + 12]) << 8)
                    lengths.append(len)
                    total += len
                }
                guard total <= r.remaining else { throw Failure.corrupt }
                for i in 0..<n {
                    let inner = Array(try r.take(lengths[i]))
                    a.otherFrames.append(try entry(rows[(i * 13)..<(i * 13 + 11)], inner: inner))
                }
            default:
                throw Failure.corrupt
            }
        }
        guard r.remaining == 0 else { throw Failure.corrupt }
        return a
    }
}

// MARK: - Byte in och ut

struct ByteWriter {
    var out: [UInt8] = []

    mutating func u8(_ v: UInt8) { out.append(v) }

    mutating func u16(_ v: UInt16) {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8(v >> 8))
    }

    mutating func u32(_ v: UInt32) {
        for k in 0..<4 { out.append(UInt8((v >> UInt32(8 * k)) & 0xFF)) }
    }

    mutating func u64(_ v: UInt64) {
        for k in 0..<8 { out.append(UInt8((v >> UInt64(8 * k)) & 0xFF)) }
    }

    mutating func bytes(_ b: [UInt8]) { out += b }
}

struct ByteReader {
    private let b: [UInt8]
    private var pos = 0

    init(_ bytes: [UInt8]) { b = bytes }

    var remaining: Int { b.count - pos }

    mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, n <= remaining else { throw DayArchive.Failure.corrupt }
        defer { pos += n }
        return b[pos..<(pos + n)]
    }

    mutating func u8() throws -> UInt8 {
        let s = try take(1)
        return s[s.startIndex]
    }

    mutating func u16() throws -> UInt16 {
        let s = try take(2)
        return UInt16(s[s.startIndex]) | (UInt16(s[s.startIndex + 1]) << 8)
    }

    mutating func u32() throws -> UInt32 {
        let s = try take(4)
        var v: UInt32 = 0
        for k in 0..<4 { v |= UInt32(s[s.startIndex + k]) << UInt32(8 * k) }
        return v
    }

    mutating func u64() throws -> UInt64 {
        let s = try take(8)
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(s[s.startIndex + k]) << UInt64(8 * k) }
        return v
    }
}
