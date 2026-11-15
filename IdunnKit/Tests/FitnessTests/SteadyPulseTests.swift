import Foundation
import XCTest
import Pass
@testable import Fitness

// Alla bitar och pass nedan är påhittade (CLAUDE.md §Dataregeln). BESLUT B114, METOD M66.

final class SteadyPulseTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// En jämn bit med farten `fart` (m/min) och pulsen `puls`.
    func bit(_ fart: Double, _ puls: Double, löpning: Bool = true) -> SpeedFitness.Segment {
        SpeedFitness.Segment(start: t0, speed: fart, pulse: puls, running: löpning, oxygen: 0, value: 0)
    }

    func pass(_ dag: Int, _ bitar: [SpeedFitness.Segment], vila: Double = 50) -> SteadyPulse.PassSegments {
        SteadyPulse.PassSegments(day: dag, restingPulse: vila, segments: bitar)
    }

    func testDetFastaTempotÄrMedianenAvrundadTillFemSekunder() throws {
        // 180 m/min är 333,3 s/km: avrundat 335. 200 m/min är 300 s/km.
        XCTAssertEqual(SteadyPulse.referencePace([bit(170, 140), bit(180, 150), bit(200, 160)]), 335)
        XCTAssertEqual(SteadyPulse.referencePace([bit(200, 160)]), 300)
        // Jämnt antal: medlet av de två mittersta, 190 m/min är 315,8 s/km: 315.
        XCTAssertEqual(SteadyPulse.referencePace([bit(180, 150), bit(200, 160)]), 315)
        XCTAssertNil(SteadyPulse.referencePace([]))
    }

    func testPulsenRäknasOmMedPulsenÖverVilopulsen() throws {
        // Biten 180 m/min med puls 150 och vila 50, räknad till 200 m/min: 50 + 100 × 200/180 = 161,1.
        let upp = try XCTUnwrap(SteadyPulse.pulse(bit(180, 150), at: 200, restingPulse: 50))
        XCTAssertEqual(upp, 50 + 100 * 200.0 / 180, accuracy: 1e-9)
        // Samma fart: pulsen som den är.
        XCTAssertEqual(SteadyPulse.pulse(bit(200, 150), at: 200, restingPulse: 50), 150)
        // 10 % från farten räknas, längre bort inte.
        XCTAssertNotNil(SteadyPulse.pulse(bit(220, 150), at: 200, restingPulse: 50))
        XCTAssertNil(SteadyPulse.pulse(bit(221, 150), at: 200, restingPulse: 50))
        XCTAssertNil(SteadyPulse.pulse(bit(179, 150), at: 200, restingPulse: 50))
        // Pulsen under vilopulsen ger inget.
        XCTAssertNil(SteadyPulse.pulse(bit(200, 50), at: 200, restingPulse: 50))
    }

    func testSerienHarEnPunktPerPassVidSammaTempo() throws {
        // Tre pass i 200 m/min (300 s/km) med sjunkande puls, och ett fjärde i 210 m/min.
        let allaPass = [
            pass(100, [bit(200, 160), bit(200, 162), bit(200, 158)]),
            pass(107, [bit(200, 156)]),
            pass(114, [bit(200, 152), bit(200, 154)]),
            pass(121, [bit(210, 155)]),
        ]
        let s = try XCTUnwrap(SteadyPulse.series(allaPass, running: true))
        XCTAssertTrue(s.running)
        XCTAssertEqual(s.paceSeconds, 300)
        XCTAssertEqual(s.speed, 200, accuracy: 1e-9)
        XCTAssertEqual(s.points.map { $0.day }, [100, 107, 114, 121])
        XCTAssertEqual(s.points[0].pulse, 160, accuracy: 1e-9)      // medianen av tre
        XCTAssertEqual(s.points[0].segments, 3)
        XCTAssertEqual(s.points[2].pulse, 153, accuracy: 1e-9)      // medlet av två
        XCTAssertEqual(s.points[3].pulse, 50 + 105 * 200.0 / 210, accuracy: 1e-9)   // 150
        // Ändringen: 150 − medlet av 160, 156 och 153.
        let ändring = try XCTUnwrap(s.change)
        XCTAssertEqual(ändring, 150 - (160 + 156 + 153) / 3.0, accuracy: 1e-9)
        XCTAssertEqual(s.latest?.day, 121)
    }

    func testPassenSorterasOchEttPassLångtFrånTempotBlirIngenPunkt() throws {
        let allaPass = [
            pass(120, [bit(200, 150)]),
            pass(100, [bit(200, 160)]),
            pass(110, [bit(200, 155)]),
            pass(115, [bit(150, 130)]),             // 25 % långsammare än 200 m/min: ingen punkt
        ]
        let s = try XCTUnwrap(SteadyPulse.series(allaPass, running: true))
        XCTAssertEqual(s.points.map { $0.day }, [100, 110, 120])
    }

    func testÄndringenKräverEttPassFöreInom90Dagar() throws {
        let ett = try XCTUnwrap(SteadyPulse.series([pass(100, [bit(200, 160)])], running: true))
        XCTAssertNil(ett.change)
        let gammalt = try XCTUnwrap(SteadyPulse.series([pass(100, [bit(200, 160)]), pass(190, [bit(200, 150)])],
                                                       running: true))
        XCTAssertNil(gammalt.change)                 // 90 dagar före räknas inte
        let nära = try XCTUnwrap(SteadyPulse.series([pass(101, [bit(200, 160)]), pass(190, [bit(200, 150)])],
                                                    running: true))
        XCTAssertEqual(nära.change, -10)
    }

    func testLöpningOchGångHållsIsärOchDenMedFlestPassVisas() throws {
        let gång1 = pass(100, [bit(90, 110, löpning: false)])
        let gång2 = pass(101, [bit(90, 108, löpning: false)])
        let löp = pass(102, [bit(200, 160)])
        let g = try XCTUnwrap(SteadyPulse.series([gång1, gång2, löp], running: false))
        XCTAssertFalse(g.running)
        XCTAssertEqual(g.points.count, 2)
        XCTAssertEqual(g.paceSeconds, 665)           // 90 m/min är 666,7 s/km: 665
        XCTAssertEqual(SteadyPulse.series([gång1, gång2, löp], running: true)?.points.count, 1)
        XCTAssertEqual(SteadyPulse.shown([gång1, gång2, löp])?.running, false)      // flest pass
        XCTAssertEqual(SteadyPulse.shown([gång1, löp])?.running, true)              // lika många: löpning
        XCTAssertEqual(SteadyPulse.shown([gång1])?.running, false)
        XCTAssertNil(SteadyPulse.shown([]))
        XCTAssertNil(SteadyPulse.series([gång1], running: true))
    }

    func testVilopulsenÄrPassetsEgen() throws {
        // Samma bit med olika vilopuls: omräkningen från 190 till 200 m/min skiljer.
        let s = try XCTUnwrap(SteadyPulse.series([pass(100, [bit(200, 150)], vila: 50),
                                                  pass(101, [bit(200, 150)], vila: 50),
                                                  pass(102, [bit(190, 150)], vila: 60)], running: true))
        XCTAssertEqual(s.paceSeconds, 300)
        XCTAssertEqual(s.points[2].pulse, 60 + 90 * 200.0 / 190, accuracy: 1e-9)
    }

    func testBitarnaUrEttRiktigtByggtPassGårRaktIn() throws {
        // Ett pass ute i 160 m/min med puls 150, byggt som i ActiveFitnessTests, ger bitar som blir en punkt.
        let meterPerGrad = PassRoute.earthRadius * Double.pi / 180
        var lat = 59.0
        var spår: [TrackPoint] = []
        var prov: [PassSample] = []
        for s in 0...600 {
            if s > 0 { lat += 160.0 / 60 / meterPerGrad }
            let t = t0.addingTimeInterval(Double(s))
            spår.append(TrackPoint(t: t, lat: lat, lon: 18.0, speed: 160.0 / 60, altitude: 20, accuracy: 5))
            prov.append(PassSample(t: t, bpm: 150))
        }
        let p = Pass(start: t0, stop: t0.addingTimeInterval(600), kind: .kondition, samples: prov, track: spår)
        let bitar = SpeedFitness.segments(p, maxPulse: 190, restingPulse: 50)
        let s = try XCTUnwrap(SteadyPulse.shown([SteadyPulse.PassSegments(day: 100, restingPulse: 50, segments: bitar)]))
        XCTAssertEqual(s.paceSeconds, 375)           // 160 m/min är 375 s/km
        XCTAssertEqual(s.points.count, 1)
        XCTAssertEqual(s.points[0].segments, 3)
        XCTAssertEqual(s.points[0].pulse, 150, accuracy: 0.01)
    }
}
