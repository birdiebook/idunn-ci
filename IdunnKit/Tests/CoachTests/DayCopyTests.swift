import Foundation
import XCTest
@testable import Coach

// BESLUT B143 · METOD M82. Alla byte nedan är påhittade (dataregeln).

private let config = CoachConfig(host: "abcdefgh12345678.supabase.co", key: String(repeating: "k", count: 40),
                                 token: String(repeating: "ab", count: 32))
private let arkiv = Data((0..<500).map { (i: Int) -> UInt8 in UInt8(i % 251) })

final class DayCopyTests: XCTestCase {
    func testAnropetHarVägHuvudenOchKropp() throws {
        let a = try XCTUnwrap(CoachCall.dayCopy(config: config, day: "2026-11-18", archive: arkiv))
        XCTAssertEqual(a.host, config.host)
        XCTAssertEqual(a.path, "/functions/v1/idunn-dygn")
        XCTAssertEqual(a.headers["apikey"], config.key)
        XCTAssertEqual(a.headers["Content-Type"], "application/octet-stream")
        XCTAssertEqual(a.headers["Accept"], "application/json")
        XCTAssertEqual(a.headers["x-idunn-token"], config.token)
        XCTAssertEqual(a.headers["x-idunn-dag"], "2026-11-18")
        XCTAssertEqual(a.headers["x-idunn-storlek"], "500")
        XCTAssertEqual(a.body, arkiv)
    }

    func testHemlighetenStårInteIKroppen() throws {
        let a = try XCTUnwrap(CoachCall.dayCopy(config: config, day: "2026-11-18", archive: arkiv))
        XCTAssertNil(a.body.range(of: Data(config.token.utf8)))
        XCTAssertNil(a.body.range(of: Data(config.key.utf8)))
    }

    func testNilFall() {
        XCTAssertNil(CoachCall.dayCopy(config: CoachConfig(host: "x.example.com", key: "k", token: "t"),
                                       day: "2026-11-18", archive: arkiv))
        for dag in ["2026-13-01", "2026-00-10", "2026-11-32", "2026-11-00", "26-11-18", "2026-1-18", "2026/11/18",
                    "abcd-11-18", "", "2026-11-18x", "dygn-2026-11-18"] {
            XCTAssertNil(CoachCall.dayCopy(config: config, day: dag, archive: arkiv), dag)
        }
        XCTAssertNil(CoachCall.dayCopy(config: config, day: "2026-11-18", archive: Data()))
        let stor = Data(count: DayCopyRules.maxBytes + 1)
        XCTAssertNil(CoachCall.dayCopy(config: config, day: "2026-11-18", archive: stor))
        let exakt = Data(count: DayCopyRules.maxBytes)
        XCTAssertNotNil(CoachCall.dayCopy(config: config, day: "2026-11-18", archive: exakt))
    }

    func testLoggenOrdningOchÄndring() {
        var l = DayCopyLedger()
        let f1 = DayCopyLedger.fingerprint(arkiv)
        XCTAssertEqual(f1, CoachLedger.fingerprint(arkiv) + ":500")
        let alla: [(day: String, fingerprint: String)] = [("2026-11-16", f1), ("2026-11-18", f1), ("2026-11-17", f1)]
        XCTAssertEqual(l.pending(alla), ["2026-11-18", "2026-11-17", "2026-11-16"])
        l.mark(day: "2026-11-18", fingerprint: f1)
        XCTAssertEqual(l.pending(alla), ["2026-11-17", "2026-11-16"])
        var ändrat = arkiv
        ändrat.append(7)
        let f2 = DayCopyLedger.fingerprint(ändrat)
        XCTAssertNotEqual(f1, f2)
        XCTAssertEqual(l.pending([("2026-11-18", f2)]), ["2026-11-18"])
        XCTAssertEqual(l.count, 1)
    }

    func testLoggenKodasOchTolerantMotSaknadNyckel() throws {
        var l = DayCopyLedger()
        l.mark(day: "2026-11-18", fingerprint: "abc:1")
        let igen = try JSONDecoder().decode(DayCopyLedger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(igen, l)
        let tom = try JSONDecoder().decode(DayCopyLedger.self, from: Data("{}".utf8))
        XCTAssertEqual(tom, DayCopyLedger())
    }

    func testSvaren() {
        let ok = Data(#"{"ok":true,"count":1,"dygn":12,"mb":24.5,"tak":500}"#.utf8)
        XCTAssertEqual(CoachReply.parse(status: 200, body: ok), .copied(days: 12, megabytes: 24.5, capMegabytes: 500))
        XCTAssertEqual(CoachReply.parse(status: 200, body: Data(#"{"ok":true,"count":3}"#.utf8)), .ok(count: 3))
        let gammal = CoachReply.parse(status: 200, body: Data(#"{"ok":false,"error":"for-gammal"}"#.utf8))
        XCTAssertEqual(gammal, .refused("for-gammal"))
        XCTAssertFalse(gammal.isUnknownDevice)
        let okänd = CoachReply.parse(status: 200, body: Data(#"{"ok":false,"error":"okand"}"#.utf8))
        XCTAssertTrue(okänd.isUnknownDevice)
        XCTAssertEqual(CoachReply.parse(status: 200, body: Data(#"{"ok":false,"error":"fullt"}"#.utf8)),
                       .refused("fullt"))
        XCTAssertEqual(CoachReply.parse(status: 502, body: Data()), .http(502))
    }
}
