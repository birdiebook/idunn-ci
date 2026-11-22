import Foundation
import XCTest
@testable import Coach

// BESLUT B148 · METOD M84. Alla byte nedan är påhittade (dataregeln).

private let config = CoachConfig(host: "abcdefgh12345678.supabase.co", key: String(repeating: "k", count: 40),
                                 token: String(repeating: "ab", count: 32))
private let fil = Data((0..<700).map { (i: Int) -> UInt8 in UInt8(i % 249) })

final class MotionCopyTests: XCTestCase {
    func testAnropetHarVägHuvudenOchKropp() throws {
        let a = try XCTUnwrap(CoachCall.motionCopy(config: config, pass: "2026-11-22-180512", file: fil))
        XCTAssertEqual(a.host, config.host)
        XCTAssertEqual(a.path, "/functions/v1/idunn-rorelse")
        XCTAssertEqual(a.headers["apikey"], config.key)
        XCTAssertEqual(a.headers["Content-Type"], "application/octet-stream")
        XCTAssertEqual(a.headers["x-idunn-token"], config.token)
        XCTAssertEqual(a.headers["x-idunn-pass"], "2026-11-22-180512")
        XCTAssertEqual(a.headers["x-idunn-storlek"], "700")
        XCTAssertNil(a.headers["x-idunn-dag"])
        XCTAssertEqual(a.body, fil)
        XCTAssertNil(a.body.range(of: Data(config.token.utf8)))
    }

    func testNilFall() {
        XCTAssertNil(CoachCall.motionCopy(config: CoachConfig(host: "x.example.com", key: "k", token: "t"),
                                          pass: "2026-11-22-180512", file: fil))
        for p in ["2026-11-22", "2026-11-22-1805", "2026-11-22-240000", "2026-11-22-186000", "2026-11-22-180560",
                  "2026-13-22-180512", "2026-11-22-18051a", "pass-2026-11-22-180512", "2026-11-22-180512.json", ""] {
            XCTAssertNil(CoachCall.motionCopy(config: config, pass: p, file: fil), p)
        }
        XCTAssertNotNil(CoachCall.motionCopy(config: config, pass: "2026-01-01-000000", file: fil))
        XCTAssertNotNil(CoachCall.motionCopy(config: config, pass: "2026-12-31-235959", file: fil))
        XCTAssertNil(CoachCall.motionCopy(config: config, pass: "2026-11-22-180512", file: Data()))
        XCTAssertNil(CoachCall.motionCopy(config: config, pass: "2026-11-22-180512",
                                          file: Data(count: MotionCopyRules.maxBytes + 1)))
    }
}
