import Foundation
import XCTest
@testable import HeartRate
@testable import WhoopFrames

// METOD M34 · BESLUT B41 · METOD M24. Dygnsarkivet (L1) mot rådygnet, på
// påhittade dygn: samma K18-serie båda vägarna, okända fält bevarade bit för bit,
// formatets huvud, och regeln för när ett rådygn får raderas. Inga byte kommer
// från ett riktigt band; "brus" är en deterministisk slumpgenerator.

/// Ett påhittat dygn: ramarna som notiser, K18-posternas inre delar i den
/// ordning de hördes, dygnsfilen och sidofilen.
struct ArkivDygn {
    var notiser: [RawFrame] = []
    var k18: [[UInt8]] = []
    var kvar: [[UInt8]] = []       // övriga sparade inre delar, i den ordning de hördes
    var log = Data()
    var sidofil = Data()
}

enum ArkivFixtur {
    static let dag = DayLog.Day(year: 2026, month: 10, day: 13)
    /// Första sekunden (Unix) i det påhittade dygnet.
    static let t0 = 1_760_300_000
    /// Ett dygn som Linux och Apple båda kan läsa: hörda tider i hela ms.
    static let heard0 = 1_760_300_000_000

    struct Slump {
        var s: UInt64
        mutating func byte() -> UInt8 {
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: s >> 33)
        }
    }

    static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for k in 0..<4 { b[o + k] = UInt8((v >> UInt32(8 * k)) & 0xFF) }
    }

    static func put16(_ b: inout [UInt8], _ o: Int, _ v: UInt16) {
        b[o] = UInt8(v & 0xFF)
        b[o + 1] = UInt8(v >> 8)
    }

    /// En K18-post: allt brus utom det som ska avkodas till ändliga tal. Byten
    /// som ingen avkodar (i51 och resten) är slumpade, för att visa att de
    /// följer med.
    static func k18(_ second: Int, _ rng: inout Slump, length: Int = 112) -> [UInt8] {
        var b = (0..<length).map { _ in rng.byte() }
        b[0] = 47
        b[1] = 18
        put32(&b, 7, UInt32(second))
        b[14] = UInt8(48 + Int(rng.byte()) % 20)
        let n = Int(rng.byte()) % 4
        b[15] = UInt8(n)
        for k in 0..<n { put16(&b, 16 + 2 * k, UInt16(700 + Int(rng.byte()) * 2)) }
        put32(&b, 37, (Float(Int(rng.byte())) / 4000).bitPattern)
        put32(&b, 41, (Float(Int(rng.byte())) / 4000).bitPattern)
        put32(&b, 45, (1 + Float(Int(rng.byte())) / 4000).bitPattern)
        put16(&b, 61, UInt16(280 + Int(rng.byte()) % 10))
        put16(&b, 65, UInt16(3200 + Int(rng.byte()) % 100))
        return b
    }

    static func inner(type: Int, family: Int, length: Int, _ rng: inout Slump) -> [UInt8] {
        var b = (0..<length).map { _ in rng.byte() }
        b[0] = UInt8(type)
        b[1] = UInt8(family)
        return b
    }

    /// En hel ram med riktiga kontrollsummor och huvudets byte 4–5 satta.
    static func ram(_ inner: [UInt8], hdr: [UInt8] = [0x00, 0x01], felCRC32: Bool = false) -> [UInt8] {
        let längd = inner.count + 4
        var b: [UInt8] = [0xAA, 0x01, UInt8(längd & 0xFF), UInt8(längd >> 8), hdr[0], hdr[1]]
        let c16 = FrameAssembly.crc16Modbus(b)
        b += [UInt8(c16 & 0xFF), UInt8(c16 >> 8)]
        b += inner
        var c32 = FrameAssembly.crc32(inner)
        if felCRC32 { c32 ^= 1 }
        for k in 0..<4 { b.append(UInt8((c32 >> UInt32(8 * k)) & 0xFF)) }
        return b
    }

    static func notis(_ ms: Int, _ k: String, _ b: [UInt8]) -> RawFrame {
        RawFrame(time: Date(timeIntervalSince1970: Double(ms) / 1000), characteristic: k, bytes: b)
    }

    /// `sekunder` K18-poster en per sekund, hörda i omgångar en timme senare
    /// (en synk), med det som en riktig synk bär runt dem: en dubblett av en
    /// sekund, en K18 med fel CRC32, en K18 av annan längd, K26, händelser,
    /// synkmärken, loggtext och kommandosvar (de två sista sparas inte), en K18
    /// uppdelad på två notiser, en notis som inte är en ram och en orphan.
    static func dygn(seconds: Int = 300, seed: UInt64 = 7) -> ArkivDygn {
        var rng = Slump(s: seed)
        var d = ArkivDygn()
        var ms = heard0 + 3_600_000
        func hör(_ k: String, _ b: [UInt8], step: Int = 7) {
            d.notiser.append(notis(ms, k, b))
            ms += step
        }
        hör("fd4b0005", ram([49, 0, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9]))            // HISTORY_START
        for s in 0..<seconds {
            let post = k18(t0 + s, &rng)
            d.k18.append(post)
            if s == 42 {
                // Delad på två notiser: ramens tid är den sista notisens.
                let r = ram(post, hdr: [0x00, 0x01])
                hör("fd4b0005", Array(r.prefix(60)), step: 3)
                hör("fd4b0005", Array(r.dropFirst(60)))
            } else {
                hör("fd4b0005", ram(post, hdr: [UInt8(s % 3), 0x01]))
            }
            if s % 15 == 0 {
                let k26 = inner(type: 47, family: 26, length: 76, &rng)
                d.kvar.append(k26)
                hör("fd4b0005", ram(k26))
            }
            if s % 100 == 0 {
                let händelse = inner(type: 48, family: 0, length: 40, &rng)
                d.kvar.append(händelse)
                hör("fd4b0004", ram(händelse))
            }
            if s == 120 { hör("fd4b0005", ram(inner(type: 50, family: 0, length: 30, &rng))) }   // loggtext
            if s == 130 { hör("fd4b0003", ram(inner(type: 36, family: 0, length: 12, &rng))) }   // kommandosvar
            if s == 140 { hör("fd4b0007", Array("f12.0.4".utf8)) }                              // inte en ram
            if s == 150 { hör("fd4b0005", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) }                     // orphan
            if s == 160 {                                                                        // dubblett av sekunden
                let dubbel = k18(t0 + s, &rng)
                d.k18.append(dubbel)
                hör("fd4b0005", ram(dubbel))
            }
            if s == 170 { hör("fd4b0005", ram(inner(type: 99, family: 1, length: 20, &rng))) }   // okänd typ
        }
        // Dubbletten av sekund 160 hörs sist, så den gäller (och är inte lika).
        let dubblett = k18(t0 + 160, &rng)
        d.k18.append(dubblett)
        hör("fd4b0005", ram(dubblett))
        // En K18 med fel CRC32 räknas men sparas inte.
        hör("fd4b0005", ram(k18(t0 + seconds + 10, &rng), felCRC32: true))
        // En K18 av annan längd hamnar bland de övriga och finns med i serien.
        let lång = k18(t0 + seconds + 20, &rng, length: 120)
        d.kvar.append(lång)
        hör("fd4b0005", ram(lång))
        let slut = [UInt8](ram([49, 0, 2, 5, 6, 7, 8, 9, 10, 11, 12, 13]))
        d.kvar.append(Array(slut[8..<(slut.count - 4)]))
        hör("fd4b0005", slut)                                                                    // HISTORY_END

        // Metadata START är också sparad (först i ordningen).
        d.kvar.insert([49, 0, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9], at: 0)

        d.log = Data()
        for n in d.notiser { d.log.append(RawFrameLog.line(n)) }
        var sida = RecordingLog.header(utcOffsetSeconds: 7200)
        sida.append(RecordingLog.marker("hämtning", at: Date(timeIntervalSince1970: Double(heard0) / 1000)))
        d.sidofil = sida
        return d
    }
}

final class DayArchiveTests: XCTestCase {

    private func arkiv(_ d: ArkivDygn) -> DayArchive {
        DayArchive.build(day: ArkivFixtur.dag, sidecar: d.sidofil, frames: d.log)
    }

    // MARK: Samma serie som rådygnet

    private func prövaSammaSerie(compress: Bool) throws {
        let d = ArkivFixtur.dygn()
        let a = arkiv(d)
        let fil = a.encode(compress: compress)
        let läst = try DayArchive.decode(fil)
        XCTAssertEqual(läst, a, "arkivet efter fil och tillbaka är arkivet")

        let rå = K18Series(notifications: RawFrameLog.decode(d.log).frames)
        let ur = K18Series(archive: läst)
        XCTAssertGreaterThan(rå.records.count, 250)
        XCTAssertEqual(ur.records, rå.records)
        XCTAssertEqual(ur.badChecksums, rå.badChecksums)
        XCTAssertEqual(rå.badChecksums, 1)
        XCTAssertEqual(ur.minutes, rå.minutes)
        XCTAssertEqual(ur.movementPerSecond, rå.movementPerSecond)
    }

    func testArkivetGerSammaSerieSomRådygnet_lagrat() throws { try prövaSammaSerie(compress: false) }

    /// Apple packar med DEFLATE, Linux lagrar (som `ZipArchive`): provet kräver
    /// bara att serien är densamma, vilken väg filen än tog.
    func testArkivetGerSammaSerieSomRådygnet_packat() throws { try prövaSammaSerie(compress: true) }

    func testFlerDygnEfterVarandraGerSammaSomRådygnenEfterVarandra() throws {
        let a = ArkivFixtur.dygn(seconds: 120, seed: 1)
        let b = ArkivFixtur.dygn(seconds: 200, seed: 2)   // samma sekunder: den senare gäller
        let ar = [DayArchive.build(day: ArkivFixtur.dag, sidecar: a.sidofil, frames: a.log),
                  DayArchive.build(day: DayLog.shifted(ArkivFixtur.dag, by: 1), sidecar: b.sidofil, frames: b.log)]
        let rå = K18Series(notifications: RawFrameLog.decode(a.log).frames + RawFrameLog.decode(b.log).frames)
        let ur = K18Series(archives: try ar.map { try DayArchive.decode($0.encode(compress: false)) })
        XCTAssertEqual(ur.records, rå.records)
        XCTAssertEqual(ur.badChecksums, rå.badChecksums)
        XCTAssertEqual(ur.duplicates, rå.duplicates)
    }

    func testInsamlarenGerSammaPosterIFönstretUrArkivetSomUrFilen() throws {
        let d = ArkivFixtur.dygn()
        let a = try DayArchive.decode(arkiv(d).encode(compress: false))
        let från = ArkivFixtur.t0 + 50
        let till = ArkivFixtur.t0 + 200
        var viaFil = K18Collector(from: från, to: till)
        viaFil.read(log: d.log)
        var viaArkiv = K18Collector(from: från, to: till)
        viaArkiv.read(archive: a)
        XCTAssertGreaterThan(viaFil.count, 100)
        XCTAssertEqual(viaArkiv.series().records, viaFil.series().records)
        XCTAssertEqual(viaArkiv.count, viaFil.count)
        XCTAssertEqual(viaArkiv.badChecksums, viaFil.badChecksums)
    }

    // MARK: Okända fält bit för bit

    func testHelaInreDelenFinnsKvarBitForBit() throws {
        let d = ArkivFixtur.dygn()
        let a = try DayArchive.decode(arkiv(d).encode(compress: true))
        XCTAssertEqual(a.stride, 112)
        // K18-posterna i den ordning de hördes, varje byte, också de ingen avkodar (i51 …).
        XCTAssertEqual(a.k18Frames.map(\.inner), d.k18, "alla 112 byte per post, i hörd ordning")
        XCTAssertTrue(a.k18Frames.allSatisfy { $0.inner.count == 112 })
        // K26, händelser, metadata och K18:n av annan längd.
        XCTAssertEqual(a.otherFrames.map(\.inner), d.kvar)
        // Huvudets okända byte 4–5 följer med.
        XCTAssertEqual(Set(a.k18Frames.map { $0.headerBytes[0] }), [0, 1, 2])
        XCTAssertTrue(a.otherFrames.allSatisfy { $0.headerBytes == [0x00, 0x01] })
    }

    func testVadSomSparasOchVadSomRäknas() {
        let d = ArkivFixtur.dygn()
        let a = arkiv(d)
        XCTAssertEqual(a.badK18Checksums, 1)
        XCTAssertEqual(a.otherBadChecksums, 0)
        XCTAssertEqual(a.droppedFrames, 3, "loggtext, kommandosvar och en okänd typ")
        let typer = a.typeCounts
        XCTAssertEqual(typer[36], nil)
        XCTAssertEqual(typer[50], nil)
        XCTAssertEqual(typer[99], nil)
        XCTAssertEqual(typer[48], 3)
        XCTAssertEqual(typer[49], 2)
        XCTAssertEqual(typer[47], a.k18Frames.count + a.otherFrames.filter { $0.type == 47 }.count)
        XCTAssertEqual(a.sidecar, d.sidofil, "sidofilen ordagrant")
        XCTAssertEqual(a.sourceFrameBytes, d.log.count)
        XCTAssertEqual(DayArchive.keptTypes, [40, 43, 47, 48, 49, 51, 52, 53, 54, 56])
    }

    func testEnRamBlirEnNotisMedSammaInreDelOchTid() throws {
        let d = ArkivFixtur.dygn()
        let a = arkiv(d)
        let tillbaka = RawFrameLog.decode(a.rawLog()).frames
        let (ramar, stat) = FrameAssembly.assemble(tillbaka)
        XCTAssertEqual(ramar.count, a.frames.count)
        XCTAssertTrue(ramar.allSatisfy(\.crc32OK))
        XCTAssertEqual(stat.values.map(\.crc32Failures).reduce(0, +), 0)
        // Tidsordning efter när telefonen hörde ramen.
        XCTAssertEqual(tillbaka.map(\.time), tillbaka.map(\.time).sorted())
        // Samma inre delar som i arkivet, och K18-serien densamma som ur rådygnet.
        XCTAssertEqual(Set(ramar.map(\.inner)), Set(a.frames.map(\.inner)))
        XCTAssertEqual(K18Series(notifications: tillbaka).records,
                       K18Series(notifications: RawFrameLog.decode(d.log).frames).records)
        // Huvudets byte 4–5 återskapas.
        XCTAssertEqual(Set(ramar.map { $0.headerBytes }), Set(a.frames.map(\.headerBytes)))
    }

    func testExportenUrArkivetGerSammaK18ISammaIntervallSomUrRådygnet() throws {
        let d = ArkivFixtur.dygn()
        let a = arkiv(d)
        let från = Date(timeIntervalSince1970: Double(ArkivFixtur.heard0 + 3_600_000 + 500) / 1000)
        let till = Date(timeIntervalSince1970: Double(ArkivFixtur.heard0 + 3_600_000 + 1500) / 1000)
        func ramar(_ delar: [ExportPackage.DayPart]) throws -> [(Double, [UInt8])] {
            let r = ExportPackage.interval(parts: delar, from: från, to: till, utcOffsetSeconds: 7200, compress: false)
            let zip = try XCTUnwrap(r.zip)
            let notiser = RawFrameLog.decode(Self.fil(zip, endsWith: ".t2.jsonl")).frames
            return FrameAssembly.assemble(notiser).frames
                .filter { (f: FrameAssembly.Frame) -> Bool in f.type == 47 && f.inner[1] == 18 }
                .map { (f: FrameAssembly.Frame) -> (Double, [UInt8]) in (f.time.timeIntervalSince1970, f.inner) }
        }
        let rå = try ramar([ExportPackage.DayPart(stem: "dygn-2026-10-13", pulse: d.sidofil, frames: d.log)])
        let ur = try ramar([ExportPackage.DayPart(stem: "dygn-2026-10-13", pulse: a.sidecar, frames: a.rawLog())])
        XCTAssertGreaterThan(rå.count, 20)
        XCTAssertEqual(ur.map(\.0), rå.map(\.0), "samma tider")
        XCTAssertEqual(ur.map(\.1), rå.map(\.1), "samma inre delar")
    }

    /// Läser en lagrad fil ur en zip utan kompression (metod 0).
    static func fil(_ zip: Data, endsWith suffix: String) -> Data {
        let b = [UInt8](zip)
        var i = 0
        func u16(_ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }
        func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }
        while i + 30 <= b.count, u32(i) == 0x0403_4B50 {
            let size = u32(i + 18)
            let nameLen = u16(i + 26)
            let extra = u16(i + 28)
            let name = String(decoding: b[(i + 30)..<(i + 30 + nameLen)], as: UTF8.self)
            let start = i + 30 + nameLen + extra
            if name.hasSuffix(suffix) { return Data(b[start..<(start + size)]) }
            i = start + size
        }
        return Data()
    }

    // MARK: Formatet

    func testHuvudetBärVersionMetodDatumOchStorlekar() throws {
        let d = ArkivFixtur.dygn()
        let fil = arkiv(d).encode(compress: false)
        let b = [UInt8](fil)
        XCTAssertEqual(Array(b[0..<3]), Array("IDA".utf8))
        XCTAssertEqual(b[3], 1, "version")
        XCTAssertEqual(DayArchive.version, 1)
        XCTAssertEqual(b[4], 0, "lagrad")
        let h = try DayArchive.Header.read(fil)
        XCTAssertEqual(h.version, 1)
        XCTAssertEqual(h.method, 0)
        XCTAssertEqual(h.day, ArkivFixtur.dag)
        XCTAssertEqual(h.sourceFrameBytes, d.log.count)
        XCTAssertEqual(h.sourceSidecarBytes, d.sidofil.count)
        XCTAssertEqual(h.storedLength, fil.count - DayArchive.Header.size)
        XCTAssertEqual(h.bodyLength, h.storedLength, "lagrad: samma längd")
        XCTAssertEqual(DayArchive.Header.size, 38)
        // Packad (Apple) eller lagrad (Linux): huvudet säger vilken, och kroppen
        // blir aldrig större packad än lagrad.
        let packad = arkiv(d).encode(compress: true)
        let hp = try DayArchive.Header.read(packad)
        XCTAssertEqual(hp.bodyLength, h.bodyLength)
        XCTAssertLessThanOrEqual(hp.storedLength, h.storedLength)
        #if canImport(Darwin)
        XCTAssertEqual(hp.method, 1)
        XCTAssertLessThan(packad.count, fil.count, "DEFLATE packar byteplanen")
        #else
        XCTAssertEqual(hp.method, 0, "inget DEFLATE på Linux: lagras")
        #endif
    }

    func testEnNyareVersionEllerFelFilVägras() throws {
        let fil = arkiv(ArkivFixtur.dygn()).encode(compress: false)
        var nyare = [UInt8](fil)
        nyare[3] = 2
        XCTAssertThrowsError(try DayArchive.decode(Data(nyare))) {
            XCTAssertEqual($0 as? DayArchive.Failure, .unsupportedVersion(2))
        }
        var annan = [UInt8](fil)
        annan[0] = 0x58
        XCTAssertThrowsError(try DayArchive.decode(Data(annan))) {
            XCTAssertEqual($0 as? DayArchive.Failure, .notAnArchive)
        }
        XCTAssertThrowsError(try DayArchive.decode(Data(fil.prefix(10)))) {
            XCTAssertEqual($0 as? DayArchive.Failure, .tooShort)
        }
        XCTAssertThrowsError(try DayArchive.decode(Data(fil.dropLast()))) {
            XCTAssertEqual($0 as? DayArchive.Failure, .corrupt, "avklippt fil")
        }
        var trasig = [UInt8](fil)
        trasig[trasig.count / 2] ^= 0x40
        XCTAssertThrowsError(try DayArchive.decode(Data(trasig))) {
            XCTAssertEqual($0 as? DayArchive.Failure, .corrupt, "en ändrad byte syns i kontrollsumman")
        }
        var okändPackning = [UInt8](fil)
        okändPackning[4] = 9
        XCTAssertThrowsError(try DayArchive.decode(Data(okändPackning))) {
            XCTAssertEqual($0 as? DayArchive.Failure, .unsupportedCompression)
        }
    }

    func testSammaArkivGerSammaByte() {
        let a = arkiv(ArkivFixtur.dygn())
        XCTAssertEqual(a.encode(compress: false), a.encode(compress: false))
        XCTAssertEqual(a.encode(compress: true), a.encode(compress: true))
    }

    func testEttTomtDygnOchEnBaraSidofilGårAttArkivera() throws {
        let tomt = DayArchive.build(day: ArkivFixtur.dag, sidecar: nil, frames: nil)
        XCTAssertEqual(try DayArchive.decode(tomt.encode()), tomt)
        XCTAssertTrue(tomt.frames.isEmpty)
        let sida = DayArchive.build(day: ArkivFixtur.dag, sidecar: RecordingLog.header(utcOffsetSeconds: 3600), frames: nil)
        let läst = try DayArchive.decode(sida.encode())
        XCTAssertEqual(läst.sidecar, RecordingLog.header(utcOffsetSeconds: 3600))
        XCTAssertEqual(K18Series(archive: läst).records, [])
    }

    /// Formatet bit för bit på ett litet dygn: samma byte skrivs av
    /// `tools/arkiv_storlek.py` (dess prov har samma hexsträng), så att
    /// storleken som verktyget räknar ut är storleken appen skriver.
    func testFormatetBitForBit() {
        var a = DayArchive(day: DayLog.Day(year: 2026, month: 10, day: 13), sourceFrameBytes: 1234,
                           sourceSidecarBytes: 56, sidecar: Data("zon\n".utf8))
        a.notifications = 5
        a.badK18Checksums = 1
        a.droppedFrames = 2
        for s in 0..<3 {
            var inner = [UInt8](repeating: 0, count: 112)
            inner[0] = 47
            inner[1] = 18
            ArkivFixtur.put32(&inner, 7, UInt32(1_760_300_000 + s))
            inner[14] = UInt8(60 + s)
            inner[51] = UInt8(200 + s)
            a.add(DayArchive.Entry(heardMilliseconds: 1_760_300_100_000 + 10 * s, characteristic: "fd4b0005",
                                   headerBytes: [0, 1], inner: inner))
        }
        a.add(DayArchive.Entry(heardMilliseconds: 1_760_300_100_050, characteristic: "fd4b0004",
                               headerBytes: [0, 1], inner: [48, 0, 17, 0, 9]))
        XCTAssertEqual(ArkivFixtur.hex(a.encode(compress: false)), ArkivFixtur.gyllene)
    }

    // MARK: Regeln

    private let zon = 7200
    private func dagen(_ n: Int) -> DayLog.Day { DayLog.shifted(ArkivFixtur.dag, by: n) }

    func testEttDygnÄrFärdigEfterMidnattOchMarginalen() {
        let slut = ArchiveRule.end(of: ArkivFixtur.dag, utcOffsetSeconds: zon)
        XCTAssertEqual(slut, DayLog.date(of: dagen(1), utcOffsetSeconds: zon))
        let m = ArchiveRule.closeMarginHours * 3600
        XCTAssertFalse(ArchiveRule.isClosed(ArkivFixtur.dag, now: slut.addingTimeInterval(-1), utcOffsetSeconds: zon))
        XCTAssertFalse(ArchiveRule.isClosed(ArkivFixtur.dag, now: slut.addingTimeInterval(m - 1), utcOffsetSeconds: zon))
        XCTAssertTrue(ArchiveRule.isClosed(ArkivFixtur.dag, now: slut.addingTimeInterval(m), utcOffsetSeconds: zon))
    }

    func testRådygnetÄrGammaltEfterFjortonDygn() {
        XCTAssertEqual(ArchiveRule.keepRawDays, 14)
        let slut = ArchiveRule.end(of: ArkivFixtur.dag, utcOffsetSeconds: zon)
        let fjorton = 14 * 86_400.0
        XCTAssertFalse(ArchiveRule.isRawExpired(ArkivFixtur.dag, now: slut.addingTimeInterval(fjorton - 1), utcOffsetSeconds: zon))
        XCTAssertTrue(ArchiveRule.isRawExpired(ArkivFixtur.dag, now: slut.addingTimeInterval(fjorton), utcOffsetSeconds: zon))
    }

    func testNärDygnetBehöverEttArkiv() throws {
        let d = ArkivFixtur.dygn()
        let a = arkiv(d)
        let h = try DayArchive.Header.read(a.encode(compress: false))
        let efter = ArchiveRule.end(of: ArkivFixtur.dag, utcOffsetSeconds: zon).addingTimeInterval(4 * 3600)
        func behov(_ nu: Date, frames: Int?, sida: Int?, _ huvud: DayArchive.Header?) -> Bool {
            ArchiveRule.needsArchive(day: ArkivFixtur.dag, now: nu, utcOffsetSeconds: zon,
                                     rawFrameBytes: frames, rawSidecarBytes: sida, header: huvud)
        }
        XCTAssertTrue(behov(efter, frames: d.log.count, sida: d.sidofil.count, nil), "inget arkiv än")
        XCTAssertFalse(behov(efter, frames: d.log.count, sida: d.sidofil.count, h), "arkivet är byggt ur samma rådygn")
        XCTAssertTrue(behov(efter, frames: d.log.count + 1, sida: d.sidofil.count, h), "rådygnet har vuxit")
        XCTAssertTrue(behov(efter, frames: d.log.count, sida: d.sidofil.count + 1, h), "sidofilen har vuxit")
        XCTAssertFalse(behov(efter, frames: nil, sida: nil, nil), "inget rådygn: inget att arkivera")
        XCTAssertFalse(behov(ArchiveRule.end(of: ArkivFixtur.dag, utcOffsetSeconds: zon).addingTimeInterval(60),
                             frames: d.log.count, sida: d.sidofil.count, nil), "dygnet är inte färdigt")
        var annan = h
        annan.version = 0
        XCTAssertTrue(behov(efter, frames: d.log.count, sida: d.sidofil.count, annan), "en annan version skrivs om")
    }

    private func raderaMedHjälp(arkiv fil: Data?, d: ArkivDygn, ålder: Double = 14 * 86_400,
                                frames: Data? = nil) -> Bool {
        let slut = ArchiveRule.end(of: ArkivFixtur.dag, utcOffsetSeconds: zon)
        return ArchiveRule.mayDeleteRaw(day: ArkivFixtur.dag, now: slut.addingTimeInterval(ålder),
                                        utcOffsetSeconds: zon, archive: fil, rawFrames: frames ?? d.log,
                                        rawSidecar: d.sidofil)
    }

    func testRådygnetRaderasBaraMedEttArkivSomLästsTillbakaOchTäckerDet() throws {
        let d = ArkivFixtur.dygn()
        let fil = arkiv(d).encode(compress: false)
        XCTAssertTrue(raderaMedHjälp(arkiv: fil, d: d), "arkivet täcker rådygnet och det är 14 dygn gammalt")
        XCTAssertTrue(raderaMedHjälp(arkiv: arkiv(d).encode(compress: true), d: d))

        XCTAssertFalse(raderaMedHjälp(arkiv: nil, d: d), "inget arkiv (kunde inte läsas tillbaka)")
        XCTAssertFalse(raderaMedHjälp(arkiv: Data(), d: d))
        XCTAssertFalse(raderaMedHjälp(arkiv: Data(fil.dropLast(5)), d: d), "avklippt arkiv")
        var trasig = [UInt8](fil)
        trasig[trasig.count - 3] ^= 0x10
        XCTAssertFalse(raderaMedHjälp(arkiv: Data(trasig), d: d), "kontrollsumman stämmer inte")

        // Ett arkiv av ett annat dygn (eller med färre poster) täcker inte rådygnet.
        let annat = ArkivFixtur.dygn(seconds: 100, seed: 99)
        XCTAssertFalse(raderaMedHjälp(arkiv: arkiv(annat).encode(compress: false), d: d))
        // Rådygnet har vuxit efter att arkivet skrevs: det nya finns bara i rådygnet.
        XCTAssertFalse(raderaMedHjälp(arkiv: fil, d: d, frames: växt(d).log))
        // Rådygnet raderades en gång och en ny fil för datumet skapades: det
        // sammanslagna arkivet täcker den nya filen, så den får raderas.
        let ny = ArkivFixtur.dygn(seconds: 30, seed: 4)
        let sammanslaget = arkiv(d).updated(
            with: DayArchive.build(day: ArkivFixtur.dag, sidecar: ny.sidofil, frames: ny.log))
        XCTAssertTrue(raderaMedHjälp(arkiv: sammanslaget.encode(compress: false), d: ny))
        XCTAssertFalse(raderaMedHjälp(arkiv: fil, d: ny), "men det gamla arkivet täcker inte den nya filen")
    }

    func testIngetYngreÄnFjortonDygnRaderasHurBraArkivetÄr() {
        let d = ArkivFixtur.dygn()
        let fil = arkiv(d).encode(compress: false)
        XCTAssertFalse(raderaMedHjälp(arkiv: fil, d: d, ålder: 0))
        XCTAssertFalse(raderaMedHjälp(arkiv: fil, d: d, ålder: 13 * 86_400))
        XCTAssertFalse(raderaMedHjälp(arkiv: fil, d: d, ålder: 14 * 86_400 - 1))
        XCTAssertTrue(raderaMedHjälp(arkiv: fil, d: d, ålder: 14 * 86_400))
    }

    func testSkrivetRättKräverAttDetLästaÄrDetSomSkulleSkrivas() throws {
        let a = arkiv(ArkivFixtur.dygn())
        let fil = a.encode(compress: false)
        XCTAssertTrue(ArchiveRule.isWrittenCorrectly(readBack: fil, expected: a))
        XCTAssertFalse(ArchiveRule.isWrittenCorrectly(readBack: nil, expected: a))
        XCTAssertFalse(ArchiveRule.isWrittenCorrectly(readBack: Data(fil.dropLast()), expected: a))
        XCTAssertFalse(ArchiveRule.isWrittenCorrectly(readBack: fil, expected: arkiv(ArkivFixtur.dygn(seconds: 50))))
    }

    // MARK: Ett rådygn som växt eller skapats på nytt

    /// Rådygnet efter att en ny K18 hörts sist i filen.
    private func växt(_ d: ArkivDygn) -> ArkivDygn {
        var rng = ArkivFixtur.Slump(s: 5)
        var v = d
        v.log.append(RawFrameLog.line(ArkivFixtur.notis(ArkivFixtur.heard0 + 9_000_000, "fd4b0005",
                                                         ArkivFixtur.ram(ArkivFixtur.k18(ArkivFixtur.t0 + 5000, &rng)))))
        return v
    }

    func testEttRådygnSomVäxtErsätterArkivetOchIngetFörsvinner() {
        let d = ArkivFixtur.dygn(seconds: 100)
        let kort = arkiv(d)
        let större = växt(d)
        let nytt = DayArchive.build(day: ArkivFixtur.dag, sidecar: större.sidofil, frames: större.log)
        let uppdaterat = kort.updated(with: nytt)
        XCTAssertEqual(uppdaterat, nytt)
        XCTAssertEqual(uppdaterat.k18Frames.count, kort.k18Frames.count + 1)
        XCTAssertFalse(kort.covers(nytt), "det gamla arkivet täcker inte det som hörts sedan")
        XCTAssertTrue(uppdaterat.covers(nytt))
    }

    func testEnNyFilFörSammaDatumLäggsTillDetGamlaOchErsätterDetInte() {
        let gammalt = arkiv(ArkivFixtur.dygn(seconds: 200, seed: 3))
        let nyttDygn = ArkivFixtur.dygn(seconds: 30, seed: 4)
        let ny = DayArchive.build(day: ArkivFixtur.dag, sidecar: nyttDygn.sidofil, frames: nyttDygn.log)
        let sammanslaget = gammalt.updated(with: ny)
        XCTAssertTrue(sammanslaget.k18Frames.starts(with: gammalt.k18Frames), "allt som stod i arkivet står kvar, först")
        XCTAssertTrue(sammanslaget.otherFrames.starts(with: gammalt.otherFrames))
        XCTAssertTrue(sammanslaget.sidecar.starts(with: gammalt.sidecar))
        XCTAssertTrue(sammanslaget.covers(ny), "och det nya med")
        XCTAssertEqual(sammanslaget.k18Frames.count, gammalt.k18Frames.count + ny.k18Frames.count)
        XCTAssertEqual(sammanslaget.sourceFrameBytes, ny.sourceFrameBytes, "arkivet följer den nya filens storlek")
        XCTAssertEqual(sammanslaget.badK18Checksums, gammalt.badK18Checksums + ny.badK18Checksums)
        // Rådygnet godkänns för radering mot det sammanslagna arkivet, inte mot det gamla.
        XCTAssertFalse(gammalt.covers(ny))
        // Samma rådygn igen ändrar ingenting.
        XCTAssertEqual(sammanslaget.updated(with: ny).k18Frames, sammanslaget.k18Frames)
    }

    // MARK: Storleken

    func testArkivetÄrKortareÄnRådygnetUtanPackning() {
        let d = ArkivFixtur.dygn(seconds: 600)
        let a = arkiv(d)
        let lagrad = a.encode(compress: false).count
        // Rådygnet är en JSON-rad med base64 per ram (runt 210 byte för en post
        // på 112); arkivet 123 byte per post även utan DEFLATE.
        XCTAssertLessThan(lagrad * 3, d.log.count * 2, "redan lagrat: under två tredjedelar av rådygnet")
        let packad = a.encode(compress: true).count
        XCTAssertLessThanOrEqual(packad, lagrad)
    }
}

extension ArkivFixtur {
    static func hex(_ d: Data) -> String {
        d.map { String(format: "%02x", $0) }.joined()
    }

    /// Facit för `testFormatetBitForBit`: skrivs av `tools/arkiv_storlek.py`
    /// (`python tools/arkiv_storlek.py --gyllene`), som har samma sträng i sitt prov.
    static let gyllene =
        "494441010000ea070a0dd2040000000000003800000000000000be010000be01000092ee153a05000000010000000000000002000000040000007a6f6e0a020008006664346230303035080066643462303030340201700003000000a00a0ae900000f0000da00009900000100000000000000000000000000000100002f0000120000000000000000000000000000000000e001010b0000ec00006800000000000000000000003c0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c801010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000201000000d2e90fda9901000001000105003000110009"
}
