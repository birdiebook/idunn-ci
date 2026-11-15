import Foundation
import XCTest
@testable import WhoopFrames

// Påhittade ramar, byggda efter ramformen i METOD M12. Inga byten kommer från
// ett riktigt band, och kontrollsummorna är inte uträknade: T2 räknar bara
// formen.

final class WhoopFramesTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_760_300_000)

    /// En ram med pakettypen som inre delens första byte.
    private func ram(typ: UInt8, längd: Int = 20) -> [UInt8] {
        var b: [UInt8] = [0xAA, 0x01, UInt8(längd - 8), 0x00, 0x00, 0x00, 0x12, 0x34, typ]
        while b.count < längd { b.append(0x00) }
        return b
    }

    func testPakettypenÄrFörstaBytenEfterHuvudet() {
        XCTAssertEqual(RawFrame(time: t, characteristic: "fd4b0003", bytes: ram(typ: 36)).packetType, 36)
        XCTAssertEqual(RawFrame(time: t, characteristic: "fd4b0005", bytes: ram(typ: 49)).packetType, 49)
    }

    func testFortsättningLoggOchKortaNotiserHarIngenTyp() {
        XCTAssertNil(RawFrame(time: t, characteristic: "fd4b0004", bytes: [0x01, 0x02, 0x03]).packetType)
        // …0007 bär ASCII, inga AA-ramar.
        XCTAssertNil(RawFrame(time: t, characteristic: "fd4b0007", bytes: Array("f12.0.4".utf8)).packetType)
        // Bara huvudet: ingen inre del att läsa typen ur.
        XCTAssertNil(RawFrame(time: t, characteristic: "fd4b0003", bytes: Array(ram(typ: 36).prefix(8))).packetType)
    }

    func testKortNamnUrUUID() {
        XCTAssertEqual(RawFrame.shortName("FD4B0003-CCE1-4033-93CE-002D5875F58A"), "fd4b0003")
        XCTAssertEqual(RawFrame.shortName("2A37"), "2a37")
        XCTAssertEqual(RawFrame(time: t, characteristic: RawFrame.listened[3], bytes: []).characteristic, "fd4b0007")
    }

    func testSkrivkarakteristikenFinnsInteBlandDeLyssnade() {
        // BESLUT B14: Idunn lyssnar på …0003–0005 och …0007, aldrig på …0002.
        XCTAssertEqual(RawFrame.listened.map(RawFrame.shortName), ["fd4b0003", "fd4b0004", "fd4b0005", "fd4b0007"])
        XCTAssertFalse(RawFrame.listened.contains { $0.lowercased().hasPrefix("fd4b0002") })
    }

    func testRäkningenPerKarakteristikOchTyp() {
        let ramar = [
            RawFrame(time: t, characteristic: "fd4b0003", bytes: ram(typ: 36)),
            RawFrame(time: t, characteristic: "fd4b0003", bytes: ram(typ: 36)),
            RawFrame(time: t, characteristic: "fd4b0005", bytes: ram(typ: 48)),
            RawFrame(time: t, characteristic: "fd4b0005", bytes: [0x07, 0x08]),
            RawFrame(time: t, characteristic: "fd4b0007", bytes: Array("logg".utf8)),
        ]
        let r = FrameTally(ramar)
        XCTAssertEqual(r.total, 5)
        XCTAssertEqual(r.total(characteristic: "fd4b0003"), 2)
        XCTAssertEqual(r.total(characteristic: "fd4b0005"), 2)
        XCTAssertEqual(r.rows.map { $0.key.characteristic }, ["fd4b0003", "fd4b0005", "fd4b0005", "fd4b0007"])
        XCTAssertEqual(r.rows.map { $0.key.packetType }, [36, nil, 48, nil])
        XCTAssertEqual(r.rows.map { $0.count }, [2, 1, 1, 1])
    }

    func testRamarFramOchTillbakaPåDisk() {
        let a = RawFrame(time: t, characteristic: "fd4b0003", bytes: ram(typ: 36, längd: 24))
        let b = RawFrame(time: t.addingTimeInterval(0.5), characteristic: "fd4b0007", bytes: [])
        var fil = RawFrameLog.line(a)
        fil.append(RawFrameLog.line(b))
        fil.append(Data("{\"t\":1".utf8)) // halvskriven rad
        let ut = RawFrameLog.decode(fil)
        XCTAssertEqual(ut.frames, [a, b])
        XCTAssertEqual(ut.skippedLines, 1)
    }
}
