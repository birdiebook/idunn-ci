import Foundation
import XCTest
@testable import Pass

// BESLUT B126 · METOD M72. Veckans träning. Passen är påhittade (CLAUDE.md §Dataregeln).

final class PassWeekTests: XCTestCase {
    /// Måndagen 2030-01-07 är dag 21921 (2030-01-01 är dag 21915, en tisdag).
    let måndag = 21921

    /// Ett stoppat pass på dagen `dag` (start kl 12 UTC), `minuter` långt, med ett prov per sekund i pulsen `puls`.
    func pass(_ dag: Int, minuter: Int, typ: PassKind? = .kondition, puls: Int = 150, stoppat: Bool = true) -> Pass {
        let start = Date(timeIntervalSince1970: Double(dag) * 86_400 + 43_200)
        let prov = (0...(minuter * 60)).map { (s: Int) -> PassSample in
            PassSample(t: start.addingTimeInterval(Double(s)), bpm: puls)
        }
        return Pass(start: start, stop: stoppat ? start.addingTimeInterval(Double(minuter * 60)) : nil, kind: typ,
                    samples: prov)
    }

    func dag(_ p: Pass) -> Int { Int(p.start.timeIntervalSince1970) / 86_400 }
    /// Belastningen i provet: en enhet per minut.
    func last(_ p: Pass) -> Double { p.duration / 60 }
    /// Zonen som tiotalet över 100.
    func zon(_ bpm: Int) -> Int { max(0, (bpm - 100) / 10) }

    func testVeckanBörjarPåMåndagen() {
        XCTAssertEqual(PassWeek.weekStart(day: 0), -3)                 // 1970-01-01 var en torsdag
        XCTAssertEqual(PassWeek.weekStart(day: 4), 4)                  // måndagen 1970-01-05
        XCTAssertEqual(PassWeek.weekStart(day: 10), 4)                 // söndagen samma vecka
        XCTAssertEqual(PassWeek.weekStart(day: 11), 11)
        XCTAssertEqual(PassWeek.weekStart(day: måndag), måndag)
        XCTAssertEqual(PassWeek.weekStart(day: måndag + 6), måndag)
        XCTAssertEqual(PassWeek.weekStart(day: måndag - 1), måndag - 7)
        XCTAssertEqual(PassWeek.weekStart(day: -4), -10)               // före 1970 också
    }

    func testVeckansTidBelastningOchZoner() {
        let alla = [pass(måndag, minuter: 30), pass(måndag + 6, minuter: 20, puls: 130),
                    pass(måndag + 7, minuter: 60),                     // nästa vecka
                    pass(måndag - 1, minuter: 60)]                     // veckan före
        let v = PassWeek.summary(alla, weekStart: måndag, dayOf: dag, load: last, classify: zon)
        XCTAssertEqual(v.passes, 2)
        XCTAssertEqual(v.seconds, 50 * 60)
        XCTAssertEqual(v.load, 50)
        XCTAssertEqual(v.meters, 0)
        XCTAssertEqual(v.zones, [PassZones.Share(zone: 3, seconds: 20 * 60), PassZones.Share(zone: 5, seconds: 30 * 60)])
        // Utan maxpuls (ingen zonfunktion) räknas inga zoner, men resten står kvar.
        let utan = PassWeek.summary(alla, weekStart: måndag, dayOf: dag, load: last, classify: nil)
        XCTAssertEqual(utan.zones, [])
        XCTAssertEqual(utan.seconds, 50 * 60)
    }

    func testBastuDuschOchPågåendePassRäknasInte() {
        let alla = [pass(måndag, minuter: 30, typ: .bastu), pass(måndag, minuter: 5, typ: .dusch),
                    pass(måndag + 1, minuter: 40, typ: .styrka), pass(måndag + 2, minuter: 25, typ: nil),
                    pass(måndag + 3, minuter: 50, stoppat: false)]
        let v = PassWeek.summary(alla, weekStart: måndag, dayOf: dag, load: last, classify: zon)
        XCTAssertEqual(v.passes, 2)                                    // styrka och passet utan typ
        XCTAssertEqual(v.seconds, 65 * 60)
        XCTAssertFalse(PassWeek.counts(alla[0]))
        XCTAssertFalse(PassWeek.counts(alla[4]))
        XCTAssertTrue(PassWeek.counts(alla[3]))
    }

    func testSträckanÄrPassenUte() {
        // Ett spår rakt norrut: 0,009 grader latitud är ungefär en kilometer.
        var ute = pass(måndag, minuter: 10)
        ute.track = (0...10).map { (i: Int) -> TrackPoint in
            TrackPoint(t: ute.start.addingTimeInterval(Double(i) * 60), lat: 59.0 + Double(i) * 0.0009, lon: 18.0,
                       speed: 1.7, altitude: 20, accuracy: 5)
        }
        let v = PassWeek.summary([ute, pass(måndag + 1, minuter: 10)], weekStart: måndag, dayOf: dag, load: last,
                                 classify: nil)
        XCTAssertEqual(v.meters, PassRoute.distance(ute.track ?? []), accuracy: 1e-6)
        XCTAssertGreaterThan(v.meters, 900)
        XCTAssertLessThan(v.meters, 1100)
    }

    func testVeckanMotDeFyraFöre() {
        // Onsdag i veckan: ett pass hittills. Veckorna före: 60, 0, 120 och 60 minuter (äldst först).
        let alla = [pass(måndag + 1, minuter: 45),
                    pass(måndag - 28, minuter: 60), pass(måndag - 14 + 2, minuter: 120), pass(måndag - 7 + 5, minuter: 60),
                    pass(måndag - 35, minuter: 500)]                   // fem veckor bakåt: utanför
        let ö = PassWeek.overview(alla, day: måndag + 2, dayOf: dag, load: last, classify: zon)
        XCTAssertEqual(ö.current.weekStart, måndag)
        XCTAssertEqual(ö.current.seconds, 45 * 60)
        XCTAssertEqual(ö.previous.map { $0.weekStart }, [måndag - 28, måndag - 21, måndag - 14, måndag - 7])
        let tider: [TimeInterval] = [3600, 0, 7200, 3600]
        XCTAssertEqual(ö.previous.map { (v: PassWeek.Summary) -> TimeInterval in v.seconds }, tider)
        XCTAssertEqual(ö.averageSeconds, 60 * 60)                      // tomma veckan räknas med
        XCTAssertEqual(ö.averageLoad, 60)
        XCTAssertEqual(ö.averageMeters, 0)
        XCTAssertTrue(ö.hasTraining)
    }

    func testIngenTräningAlls() {
        let ö = PassWeek.overview([pass(måndag, minuter: 30, typ: .bastu)], day: måndag + 2, dayOf: dag, load: last,
                                  classify: zon)
        XCTAssertFalse(ö.hasTraining)
        XCTAssertEqual(ö.previous.count, 4)
        XCTAssertEqual(ö.averageSeconds, 0)
        XCTAssertFalse(PassWeek.overview([], day: måndag, dayOf: dag, load: last, classify: nil).hasTraining)
    }
}
