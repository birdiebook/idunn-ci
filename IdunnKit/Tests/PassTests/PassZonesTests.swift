import Foundation
import XCTest
@testable import Pass

// BESLUT B124 · METOD M71. Tiden per pulszon. Proven är påhittade.

final class PassZonesTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Zonen som tiotalet över 100: 100–109 är zon 0, 110–119 zon 1 och så vidare.
    func zon(_ bpm: Int) -> Int { max(0, (bpm - 100) / 10) }

    func prov(_ sekund: Double, _ bpm: Int) -> PassSample { PassSample(t: t0.addingTimeInterval(sekund), bpm: bpm) }

    func testTidenPerZonIZonernasOrdning() {
        // 0–10 s i zon 2, 10–30 s i zon 4, 30–40 s i zon 2 igen; det sista provet har ingen tid efter sig.
        var alla: [PassSample] = []
        for s in 0..<10 { alla.append(prov(Double(s), 125)) }
        for s in 10..<30 { alla.append(prov(Double(s), 145)) }
        for s in 30...40 { alla.append(prov(Double(s), 125)) }
        let tid = PassZones.time(alla, classify: zon)
        XCTAssertEqual(tid, [PassZones.Share(zone: 2, seconds: 20), PassZones.Share(zone: 4, seconds: 20)])
    }

    func testEttGlappRäknasInte() {
        // Prov varje sekund i 10 s, 60 s tystnad, sedan 10 s till: 9 + 9 sekunder, glappet räknas inte.
        var alla: [PassSample] = []
        for s in 0..<10 { alla.append(prov(Double(s), 125)) }
        for s in 70..<80 { alla.append(prov(Double(s), 125)) }
        XCTAssertEqual(PassZones.time(alla, classify: zon), [PassZones.Share(zone: 2, seconds: 18)])
        // Precis 5 s mellan två prov räknas, 6 s gör det inte.
        XCTAssertEqual(PassZones.time([prov(0, 125), prov(5, 125)], classify: zon), [PassZones.Share(zone: 2, seconds: 5)])
        XCTAssertEqual(PassZones.time([prov(0, 125), prov(6, 125)], classify: zon), [])
    }

    func testFörFåProvGerInget() {
        XCTAssertEqual(PassZones.time([], classify: zon), [])
        XCTAssertEqual(PassZones.time([prov(0, 125)], classify: zon), [])
    }

    func testZonenJustNu() {
        let alla = [prov(0, 125), prov(1, 145)]
        XCTAssertEqual(PassZones.current(alla, now: t0.addingTimeInterval(2), classify: zon), 4)
        XCTAssertEqual(PassZones.current(alla, now: t0.addingTimeInterval(11), classify: zon), 4)
        XCTAssertNil(PassZones.current(alla, now: t0.addingTimeInterval(12), classify: zon))     // bandet hörs inte
        XCTAssertNil(PassZones.current([], now: t0, classify: zon))
    }
}
