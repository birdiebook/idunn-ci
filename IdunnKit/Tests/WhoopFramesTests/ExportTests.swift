import Foundation
import XCTest
@testable import HeartRate
@testable import WhoopFrames

// Påhittade ramar med riktiga kontrollsummor (METOD M12) och en påhittad natt
// med märken (METOD M20). Inga byte kommer från ett riktigt band.

final class FrameAssemblyTests: XCTestCase {
    private let t0 = 1_760_300_000.0

    static func ram(_ inner: [UInt8], felCRC32: Bool = false) -> [UInt8] {
        let längd = inner.count + 4
        var b: [UInt8] = [0xAA, 0x01, UInt8(längd & 0xFF), UInt8(längd >> 8), 0x00, 0x01]
        let c16 = FrameAssembly.crc16Modbus(b)
        b += [UInt8(c16 & 0xFF), UInt8(c16 >> 8)]
        b += inner
        var c32 = FrameAssembly.crc32(inner)
        if felCRC32 { c32 ^= 1 }
        b += [UInt8(c32 & 0xFF), UInt8((c32 >> 8) & 0xFF), UInt8((c32 >> 16) & 0xFF), UInt8(c32 >> 24)]
        return b
    }

    private func notis(_ dt: Double, _ k: String, _ b: [UInt8]) -> RawFrame {
        RawFrame(time: Date(timeIntervalSince1970: t0 + dt), characteristic: k, bytes: b)
    }

    func testKontrollsummornasKändaVärden() {
        XCTAssertEqual(FrameAssembly.crc16Modbus(Array("123456789".utf8)), 0x4B37)
        XCTAssertEqual(FrameAssembly.crc32(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testHelaDeladeOchTrasigaRamar() {
        let stor = Self.ram([47, 24] + [UInt8](repeating: 7, count: 298))
        let notiser = [
            notis(0, "fd4b0003", Self.ram([36, 0, 22, 1, 1])),
            notis(1, "fd4b0005", Array(stor.prefix(180))),
            notis(1.1, "fd4b0003", Self.ram([36, 0, 23], felCRC32: true)),
            notis(1.2, "fd4b0005", Array(stor.dropFirst(180))),
            notis(2, "fd4b0007", Array("f12.0.4".utf8)),
            notis(3, "fd4b0004", [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0x00, 0x00, 48]),
            notis(4, "fd4b0005", Array(Self.ram([49, 1, 2, 3, 4]).prefix(10))),
        ]
        let (ramar, stat) = FrameAssembly.assemble(notiser)
        XCTAssertEqual(ramar.map(\.type), [36, 36, 47], "i den ordning de blir hela")
        XCTAssertEqual(ramar.map(\.crc32OK), [true, false, true])
        XCTAssertEqual(ramar[2].notifications, [1, 3])
        XCTAssertEqual(ramar[2].time, Date(timeIntervalSince1970: t0 + 1.2), "ramens tid är sista notisens")
        XCTAssertEqual(ramar[2].inner.count, 300)
        XCTAssertEqual(stat["fd4b0005"]?.continuations, 1)
        XCTAssertEqual(stat["fd4b0005"]?.incomplete, 1)
        XCTAssertEqual(stat["fd4b0003"]?.crc32Failures, 1)
        XCTAssertEqual(stat["fd4b0004"]?.crc16Failures, 1)
        XCTAssertEqual(stat["fd4b0007"]?.nonFrames, 1)
    }
}

final class ZipArchiveTests: XCTestCase {
    /// Läser en zip med lagrade filer (metod 0), som Linux skriver.
    private func läs(_ zip: Data) -> [String: Data] {
        let b = [UInt8](zip)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var ut: [String: Data] = [:]
        var o = 0
        while o + 30 <= b.count, u32(o) == 0x0403_4B50 {
            XCTAssertEqual(u16(o + 8), 0)
            let storlek = u32(o + 18)
            let namnLängd = u16(o + 26)
            let extra = u16(o + 28)
            let namn = String(decoding: b[(o + 30)..<(o + 30 + namnLängd)], as: UTF8.self)
            let start = o + 30 + namnLängd + extra
            let data = Data(b[start..<(start + storlek)])
            XCTAssertEqual(FrameAssembly.crc32(data), UInt32(u32(o + 14)))
            ut[namn] = data
            o = start + storlek
        }
        XCTAssertEqual(u32(b.count - 22), 0x0605_4B50, "katalogens slut")
        XCTAssertEqual(u16(b.count - 12), ut.count)
        return ut
    }

    func testFilernaFramOchTillbaka() {
        let a = Data("{\"zon\":7200}\n".utf8)
        let c = Data((0..<1000).map { UInt8($0 % 251) })
        let zip = ZipArchive.make([.init(name: "natt.jsonl", data: a), .init(name: "natt.t2.jsonl", data: c)],
                                  date: Date(timeIntervalSince1970: 1_760_300_000), compress: false)
        XCTAssertEqual(läs(zip), ["natt.jsonl": a, "natt.t2.jsonl": c])
    }

    func testDosTid() {
        // 2025-10-12 20:13:20 UTC
        let (tid, dag) = ZipArchive.dos(Date(timeIntervalSince1970: 1_760_300_000))
        XCTAssertEqual(Int(dag) >> 9, 2025 - 1980)
        XCTAssertEqual((Int(dag) >> 5) & 0xF, 10)
        XCTAssertEqual(Int(dag) & 0x1F, 12)
        XCTAssertEqual(Int(tid) >> 11, 20)
    }
}

final class OffWristExportTests: XCTestCase {
    private let t0 = 1_760_300_000.0

    func testIntervallenFrånAvTillPå() {
        let m: [(Double, String)] = [(0, "på"), (100, "av"), (200, "skak"), (300, "still"), (400, "på"),
                                     (500, "kyl"), (600, "rum")]
        let s = OffWrist.spans(markers: m, end: 700)
        XCTAssertEqual(s, [130...370, 530...670])
        XCTAssertEqual(OffWrist.spans(markers: [(0, "på")], end: 100), [])
        XCTAssertEqual(OffWrist.spans(markers: [(0, "av"), (40, "på")], end: 100), [], "kortare än marginalerna")
    }

    /// BESLUT B53. IMU-provet: "still" och "rotera" utan band, "sving",
    /// "chip" och "putt" med bandet på handleden.
    func testImuProvetsSlagÄrBurna() {
        let m: [(Double, String)] = [(0, "imu-start"), (10, "still"), (100, "rotera x"), (200, "sving"),
                                     (400, "putt"), (500, "paus"), (600, "imu-stopp knapp")]
        XCTAssertEqual(OffWrist.spans(markers: m, end: 700), [40...170])
        for o in ["sving", "chip", "putt"] {
            XCTAssertTrue(ImuControl.markerLabels.contains(o))
            XCTAssertTrue(OffWrist.wornLabels.contains(o))
        }
        XCTAssertTrue(OffWrist.labels.contains("still"))
    }

    /// En natt: puls hela tiden, "av" vid 100 s, "på" vid 400 s. Historikposter
    /// (typ 47, tid i i7) skickas under provet, en med egen tid i provet och
    /// en med tid före; kommandosvar (typ 36) bär ingen egen tid.
    private func natt() -> (pulse: Data, frames: Data) {
        var p = RecordingLog.header(utcOffsetSeconds: 7200)
        for s in stride(from: 0.0, through: 500, by: 1) {
            p.append(RecordingLog.line(HeartRateSample(time: Date(timeIntervalSince1970: t0 + s), bpm: 61,
                                                       rrMilliseconds: [983], sensorContact: .detected)))
        }
        p.append(RecordingLog.marker("av", at: Date(timeIntervalSince1970: t0 + 100)))
        p.append(RecordingLog.marker("kyl", at: Date(timeIntervalSince1970: t0 + 200)))
        p.append(RecordingLog.marker("på", at: Date(timeIntervalSince1970: t0 + 400)))
        p.append(RecordingLog.stopped(at: Date(timeIntervalSince1970: t0 + 500)))

        func post(_ tid: Double) -> [UInt8] {
            let u = UInt32(t0 + tid)
            return FrameAssemblyTests.ram([47, 24, 0, 1, 0, 0, 0,
                                           UInt8(u & 0xFF), UInt8((u >> 8) & 0xFF), UInt8((u >> 16) & 0xFF),
                                           UInt8(u >> 24), 0, 0, 77, 0, 0])
        }
        let notiser: [RawFrame] = [
            RawFrame(time: Date(timeIntervalSince1970: t0 + 50), characteristic: "fd4b0005", bytes: post(50)),
            RawFrame(time: Date(timeIntervalSince1970: t0 + 250), characteristic: "fd4b0005", bytes: post(240)),
            RawFrame(time: Date(timeIntervalSince1970: t0 + 251), characteristic: "fd4b0005", bytes: post(60)),
            RawFrame(time: Date(timeIntervalSince1970: t0 + 252), characteristic: "fd4b0003",
                     bytes: FrameAssemblyTests.ram([36, 0, 22, 1, 1])),
            RawFrame(time: Date(timeIntervalSince1970: t0 + 253), characteristic: "fd4b0007",
                     bytes: Array("logg".utf8)),
            RawFrame(time: Date(timeIntervalSince1970: t0 + 450), characteristic: "fd4b0005", bytes: post(450)),
        ]
        var f = Data()
        for n in notiser { f.append(RawFrameLog.line(n)) }
        return (p, f)
    }

    func testBaraUtanBandOchIngenPuls() {
        let (p, f) = natt()
        let (zip, sammanfattning) = ExportPackage.offWrist(stem: "natt", pulse: p, frames: f)
        XCTAssertEqual(sammanfattning.spans, [(t0 + 130)...(t0 + 370)])
        XCTAssertEqual(sammanfattning.framesKept, 2, "posten med tid i provet och kommandosvaret")
        XCTAssertEqual(sammanfattning.framesDropped, 3)
        XCTAssertEqual(sammanfattning.notificationsKept, 3, "plus loggtexten")
        XCTAssertNotNil(zip)

        let urval = OffWrist.select(RawFrameLog.decode(f).frames, spans: sammanfattning.spans)
        XCTAssertEqual(urval.indices, [1, 3, 4])
    }

    func testPulsfilenIExportenBärIngenPuls() {
        let (p, f) = natt()
        let contents = RecordingLog.decode(p)
        XCTAssertEqual(contents.recording.samples.count, 501)
        // Samma väg som exporten bygger pulsfilen.
        guard let zip = ExportPackage.offWrist(stem: "natt", pulse: p, frames: f).zip else {
            return XCTFail("ingen zip")
        }
        let text = String(decoding: zip, as: UTF8.self)
        #if !canImport(Darwin)
        // Lagrat okomprimerat på Linux: texten går att söka i.
        XCTAssertFalse(text.contains("bpm"), "ingen 2A37 i exporten utan band")
        XCTAssertTrue(text.contains("\"marke\":\"kyl\""))
        #endif
        XCTAssertTrue(text.contains("natt.t2.jsonl"))
    }

    func testUtanMärkenFinnsIngetAttDela() {
        let p = RecordingLog.header(utcOffsetSeconds: 0)
        let (zip, s) = ExportPackage.offWrist(stem: "natt", pulse: p, frames: Data())
        XCTAssertNil(zip)
        XCTAssertTrue(s.spans.isEmpty)
    }

    func testHelaNattenOchNamnen() {
        let (p, f) = natt()
        let zip = ExportPackage.full(stem: "natt", pulse: p, frames: f)
        XCTAssertGreaterThan(zip.count, 100)
        XCTAssertEqual(ExportPackage.fileName(stem: "2026-10-12T20-00-00Z", offWristOnly: false),
                       "idunn-2026-10-12T20-00-00Z.zip")
        XCTAssertEqual(ExportPackage.fileName(stem: "x", offWristOnly: true), "idunn-ejburen-x.zip")
    }
}
