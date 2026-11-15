import Foundation
import XCTest
@testable import Pass

// Alla spår nedan är påhittade (CLAUDE.md §Dataregeln). BESLUT B107, METOD M63, M65.

final class PassRouteTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let meterPerGrad = PassRoute.earthRadius * Double.pi / 180

    /// Rakt norrut, en position per sekund, `fart` meter per sekund.
    func spår(punkter: Int, fart: Double = 3, noggrannhet: Double = 5) -> [TrackPoint] {
        (0..<punkter).map { (s: Int) -> TrackPoint in
            TrackPoint(t: t0.addingTimeInterval(Double(s)), lat: 59.0 + Double(s) * fart / meterPerGrad, lon: 18.0,
                       speed: fart, altitude: 20, accuracy: noggrannhet)
        }
    }

    func testSträckanÄrSummanAvStegen() {
        // 1 100 positioner med 3 m mellan: 1 099 steg, 3 297 m.
        XCTAssertEqual(PassRoute.distance(spår(punkter: 1_100)), 3_297, accuracy: 0.01)
        XCTAssertEqual(PassRoute.distance([]), 0)
        XCTAssertEqual(PassRoute.distance(spår(punkter: 1)), 0)
    }

    func testEnDåligPositionOchEttHoppRäknasInte() {
        var p = spår(punkter: 101)
        // En position med 100 m noggrannhet, långt bort: används inte, och steget över den är 6 m på 2 s.
        p[50].accuracy = 100
        p[50].lat += 1
        XCTAssertEqual(PassRoute.distance(p), 300, accuracy: 0.01)
        XCTAssertEqual(PassRoute.usable(p).count, 100)
        // En position med god noggrannhet 1 km bort: stegen dit och tillbaka kräver över 12 m/s och räknas inte.
        var q = spår(punkter: 101)
        q[50].lat += 1_000 / meterPerGrad
        XCTAssertEqual(PassRoute.distance(q), 294, accuracy: 0.01)
        // En negativ noggrannhet är ogiltig.
        var r = spår(punkter: 11)
        r[5].accuracy = -1
        XCTAssertEqual(PassRoute.usable(r).count, 10)
    }

    func testKilometertidernaOchTempot() {
        // 3 m/s: en kilometer tar 333,33 s. 3 297 m ger tre hela kilometrar.
        let delar = PassRoute.splits(spår(punkter: 1_100))
        XCTAssertEqual(delar.map(\.kilometer), [1, 2, 3])
        for d in delar { XCTAssertEqual(d.seconds, 1_000.0 / 3, accuracy: 0.01) }
        XCTAssertEqual(PassRoute.splits(spår(punkter: 300)), [])
        // 3 000 m på 900 s är 300 s per kilometer; under 100 m finns inget tempo.
        XCTAssertEqual(PassRoute.pace(distance: 3_000, seconds: 900), 300)
        XCTAssertNil(PassRoute.pace(distance: 99, seconds: 60))
    }

    func testKartansUtsnitt() throws {
        let b = try XCTUnwrap(PassRoute.bounds(spår(punkter: 101)))
        XCTAssertEqual(b.minLat, 59.0)
        XCTAssertEqual(b.maxLat, 59.0 + 300 / meterPerGrad, accuracy: 1e-9)
        XCTAssertEqual(b.minLon, 18.0)
        XCTAssertEqual(b.maxLon, 18.0)
        XCTAssertNil(PassRoute.bounds([]))
    }

    func testRuttenDelasEfterPulsen() {
        // 100 positioner; pulsen 120 de första 50 sekunderna och 160 sedan. Klassen 1 från 150 slag.
        let p = spår(punkter: 100)
        let prov = (0..<100).map { (s: Int) -> PassSample in
            PassSample(t: t0.addingTimeInterval(Double(s)), bpm: s < 50 ? 120 : 160)
        }
        let bitar = PassRoute.runs(p, samples: prov) { (bpm: Int) -> Int in bpm >= 150 ? 1 : 0 }
        XCTAssertEqual(bitar.map(\.klass), [0, 1])
        XCTAssertEqual(bitar[0].points.count, 50)
        // Den andra biten börjar i den förstas sista position, så att linjen blir hel.
        XCTAssertEqual(bitar[1].points.first, bitar[0].points.last)
        XCTAssertEqual(bitar[1].points.count, 51)
        // Utan puls nära i tid är klassen 0.
        let utan = PassRoute.runs(p, samples: []) { _ in 1 }
        XCTAssertEqual(utan.map(\.klass), [0])
        XCTAssertEqual(PassRoute.runs([], samples: prov) { _ in 1 }, [])
    }

    func testPassetBärSpåretOchSteghöjdenIFilen() throws {
        var r = PassRecorder()
        r.start(now: t0, outdoor: true)
        XCTAssertEqual(r.pass?.track, [])
        XCTAssertEqual(r.pass?.isOutdoor, true)
        XCTAssertEqual(r.pass?.isStepTest, false)
        r.add(TrackPoint(t: t0.addingTimeInterval(1), lat: 59, lon: 18, speed: 3, altitude: 20, accuracy: 5))
        // En ogiltig noggrannhet sparas inte.
        r.add(TrackPoint(t: t0.addingTimeInterval(2), lat: 59, lon: 18, accuracy: -1))
        XCTAssertEqual(r.pass?.track?.count, 1)
        // Efter stopp sparas inga positioner.
        r.stop(now: t0.addingTimeInterval(10))
        r.add(TrackPoint(t: t0.addingTimeInterval(11), lat: 59, lon: 18, accuracy: 5))
        XCTAssertEqual(r.pass?.track?.count, 1)

        let pass = try XCTUnwrap(r.pass)
        let läst = try PassFile.decode(try PassFile.encode(pass))
        XCTAssertEqual(läst.track?.count, 1)
        XCTAssertEqual(läst.track?.first?.lat, 59)
        XCTAssertNil(pass.withoutTrack().track)

        // Ett pass inomhus tar inte emot positioner, och ett steptest får typen kondition.
        var inne = PassRecorder()
        inne.start(now: t0)
        inne.add(TrackPoint(t: t0, lat: 59, lon: 18, accuracy: 5))
        XCTAssertNil(inne.pass?.track)
        var steg = PassRecorder()
        steg.start(now: t0, stepHeightCm: 30)
        XCTAssertEqual(steg.pass?.kind, .kondition)
        XCTAssertEqual(steg.pass?.isStepTest, true)
        XCTAssertEqual(steg.pass?.stepHeightCm, 30)
    }

    func testEnFilFrånEttÄldreByggeSaknarSpår() throws {
        let gammal = #"{"id":"11111111-2222-3333-4444-555555555555","samples":[],"start":"2026-11-01T10:00:00Z"}"#
        let p = try PassFile.decode(Data(gammal.utf8))
        XCTAssertNil(p.track)
        XCTAssertNil(p.stepHeightCm)
        XCTAssertFalse(p.isOutdoor)
    }
}
