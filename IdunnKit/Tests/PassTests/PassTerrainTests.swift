import Foundation
import XCTest
@testable import Pass

// BESLUT B132 · METOD M77. Höjdmeter och paus. Spåren är påhittade (CLAUDE.md §Dataregeln).

final class PassTerrainTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// Meter per grad latitud.
    let meterPerGrad = PassRoute.earthRadius * Double.pi / 180

    /// Ett spår rakt norrut med en position per sekund: farten `fart(s)` i m/s och höjden `höjd(s)`.
    func spår(sekunder: Int, höjd: (Int) -> Double? = { _ in 20 }, fart: (Int) -> Double) -> [TrackPoint] {
        var lat = 59.0
        var ut: [TrackPoint] = []
        for s in 0...sekunder {
            if s > 0 { lat += fart(s) / meterPerGrad }
            ut.append(TrackPoint(t: t0.addingTimeInterval(Double(s)), lat: lat, lon: 18.0, speed: fart(s),
                                 altitude: höjd(s), accuracy: 5))
        }
        return ut
    }

    func testStigningenRäknarBaraÄndringarÖverTröskeln() throws {
        // Upp 30 m på 60 s (5 m var tionde sekund), plant, ner 12 m på 100 s.
        let upp = spår(sekunder: 300, höjd: { s in
            if s <= 60 { return 20 + 0.5 * Double(s) }
            if s <= 200 { return 50 }
            return 50 - 0.12 * Double(s - 200)
        }, fart: { _ in 3 })
        let k = try XCTUnwrap(PassTerrain.climb(upp))
        XCTAssertEqual(k.ascent, 30, accuracy: 0.5)
        // Fallet räknas i hela steg om minst 5 m: 12 m ner ger 10 m räknade och 2 m kvar under tröskeln.
        XCTAssertEqual(k.descent, 10, accuracy: 0.5)
    }

    func testBrusIHöjdenGerIngenStigning() throws {
        // Höjden svänger ± 2 m kring 20 m: ingenting räknas.
        let brus = spår(sekunder: 300, höjd: { s in 20 + (s % 2 == 0 ? 2 : -2) }, fart: { _ in 3 })
        XCTAssertEqual(try XCTUnwrap(PassTerrain.climb(brus)), PassTerrain.Climb(ascent: 0, descent: 0))
        // Precis 5 m räknas, 4,9 m gör det inte.
        let fem = spår(sekunder: 1, höjd: { s in s == 0 ? 20 : 25 }, fart: { _ in 3 })
        XCTAssertEqual(PassTerrain.climb(fem)?.ascent, 5)
        let nästan = spår(sekunder: 1, höjd: { s in s == 0 ? 20 : 24.9 }, fart: { _ in 3 })
        XCTAssertEqual(PassTerrain.climb(nästan)?.ascent, 0)
    }

    func testUtanHöjdIngenStigning() {
        XCTAssertNil(PassTerrain.climb(spår(sekunder: 60, höjd: { _ in nil }, fart: { _ in 3 })))
        XCTAssertNil(PassTerrain.climb([]))
        // En enda position med höjd räcker inte.
        XCTAssertNil(PassTerrain.climb(spår(sekunder: 60, höjd: { s in s == 0 ? 20 : nil }, fart: { _ in 3 })))
    }

    func testEnPausRäknasInteITempot() throws {
        // 300 s i 3 m/s, 60 s stilla, 300 s i 3 m/s: 1800 m på 600 s i rörelse, alltså 333 s/km.
        let pass = spår(sekunder: 660, fart: { s in (s > 300 && s <= 360) ? 0 : 3 })
        let r = PassTerrain.movement(pass)
        XCTAssertEqual(r.movingSeconds, 600, accuracy: 1e-6)
        XCTAssertEqual(r.pausedSeconds, 60, accuracy: 1e-6)
        XCTAssertEqual(r.movingMeters, 1800, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(r.pace), 1000.0 / 3, accuracy: 0.5)
        // Över hela tiden är tempot långsammare: 660 s på 1800 m.
        XCTAssertEqual(try XCTUnwrap(PassRoute.pace(distance: PassRoute.distance(pass), seconds: 660)), 366.7, accuracy: 0.5)
    }

    func testKortStillhetÄrIngenPaus() {
        // 9 s stilla räknas som rörelse; 10 s är en paus.
        let kort = spår(sekunder: 109, fart: { s in (s > 50 && s <= 59) ? 0 : 3 })
        XCTAssertEqual(PassTerrain.movement(kort).pausedSeconds, 0)
        XCTAssertEqual(PassTerrain.movement(kort).movingSeconds, 109, accuracy: 1e-6)
        let lång = spår(sekunder: 110, fart: { s in (s > 50 && s <= 60) ? 0 : 3 })
        XCTAssertEqual(PassTerrain.movement(lång).pausedSeconds, 10, accuracy: 1e-6)
        XCTAssertEqual(PassTerrain.movement(lång).movingSeconds, 100, accuracy: 1e-6)
    }

    func testLångsamGångÄrRörelseOchStillaISlutetÄrPaus() {
        // 0,6 m/s är över gränsen: allt är rörelse.
        XCTAssertEqual(PassTerrain.movement(spår(sekunder: 100, fart: { _ in 0.6 })).pausedSeconds, 0)
        // Passet slutar med 30 s stilla: paus.
        let slut = spår(sekunder: 130, fart: { s in s > 100 ? 0 : 3 })
        XCTAssertEqual(PassTerrain.movement(slut).pausedSeconds, 30, accuracy: 1e-6)
        // Utan spår: ingenting, och inget tempo.
        let tomt = PassTerrain.movement([])
        XCTAssertEqual(tomt, PassTerrain.Movement(movingSeconds: 0, pausedSeconds: 0, movingMeters: 0))
        XCTAssertNil(tomt.pace)
    }
}
