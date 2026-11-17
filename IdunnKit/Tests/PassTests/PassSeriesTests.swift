import Foundation
import XCTest
@testable import Pass

// BESLUT B138 · METOD M79. Tempot och höjden över passets tid. Spåren är påhittade (CLAUDE.md §Dataregeln).

final class PassSeriesTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
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

    func testTempotPerMinut() {
        // Tre minuter: 3 m/s (333 s/km), 4 m/s (250 s/km), 3 m/s.
        let p = PassSeries.pace(spår(sekunder: 180, fart: { s in (s > 60 && s <= 120) ? 4 : 3 }), start: t0)
        XCTAssertEqual(p.map { $0.seconds }, [30, 90, 150])
        XCTAssertEqual(p[0].value, 1000.0 / 3, accuracy: 0.5)
        XCTAssertEqual(p[1].value, 250, accuracy: 0.5)
        XCTAssertEqual(p[2].value, 1000.0 / 3, accuracy: 0.5)
    }

    func testEnStillaMinutHarIngetTempo() {
        // Minut två står stilla: ingen punkt där.
        let p = PassSeries.pace(spår(sekunder: 180, fart: { s in (s > 60 && s <= 120) ? 0 : 3 }), start: t0)
        XCTAssertEqual(p.map { $0.seconds }, [30, 150])
        // Under 30 m på en minut (0,4 m/s ger 24 m) räknas inte; 0,6 m/s (36 m) gör det.
        XCTAssertEqual(PassSeries.pace(spår(sekunder: 60, fart: { _ in 0.4 }), start: t0), [])
        XCTAssertEqual(PassSeries.pace(spår(sekunder: 60, fart: { _ in 0.6 }), start: t0).count, 1)
        XCTAssertEqual(PassSeries.pace([], start: t0), [])
    }

    func testHöjdenÖverTiden() {
        let h = PassSeries.altitude(spår(sekunder: 4, höjd: { s in s == 2 ? nil : 20 + Double(s) }, fart: { _ in 3 }), start: t0)
        XCTAssertEqual(h.map { $0.seconds }, [0, 1, 3, 4])
        XCTAssertEqual(h.map { $0.value }, [20, 21, 23, 24])
        // Positioner före Start är inte med.
        let sent = PassSeries.altitude(spår(sekunder: 4, fart: { _ in 3 }), start: t0.addingTimeInterval(2))
        XCTAssertEqual(sent.map { $0.seconds }, [0, 1, 2])
        XCTAssertEqual(PassSeries.altitude(spår(sekunder: 4, höjd: { _ in nil }, fart: { _ in 3 }), start: t0), [])
    }

    func testPulsenOchPunktenNärmastMarkören() {
        let prov = [PassSample(t: t0, bpm: 100), PassSample(t: t0.addingTimeInterval(60), bpm: 140),
                    PassSample(t: t0.addingTimeInterval(700), bpm: 110)]
        let pass = Pass(start: t0, stop: t0.addingTimeInterval(600), samples: prov)
        let p = PassSeries.pulse(pass)
        XCTAssertEqual(p, [PassSeries.Point(seconds: 0, value: 100), PassSeries.Point(seconds: 60, value: 140),
                           PassSeries.Point(seconds: 700, value: 110)])       // provet efter stopp är med
        XCTAssertEqual(PassSeries.nearest(p, to: 40)?.value, 140)
        XCTAssertEqual(PassSeries.nearest(p, to: 20)?.value, 100)
        XCTAssertEqual(PassSeries.nearest(p, to: 5000)?.value, 110)
        XCTAssertNil(PassSeries.nearest([], to: 10))
    }
}
