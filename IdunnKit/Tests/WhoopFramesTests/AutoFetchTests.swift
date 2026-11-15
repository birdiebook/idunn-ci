import Foundation
import XCTest
@testable import WhoopFrames

// PLAN.md A3. När Idunn själv hämtar bandets historik: rena tider och lägen in, ett skäl ut. Inga värden ur något band.

final class AutoFetchTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_762_840_000)

    func slutad(_ sekunderSedan: TimeInterval, _ o: HistorySession.Outcome = .complete) -> AutoFetch.State {
        var s = AutoFetch.State()
        s.started(at: t0.addingTimeInterval(-sekunderSedan - 20))
        s.ended(at: t0.addingTimeInterval(-sekunderSedan), o)
        return s
    }

    func beslut(_ s: AutoFetch.State, på: Bool = true, redo: Bool = true, upptagen: Bool = false,
                ansluten: Bool = false, om: TimeInterval = 0) -> AutoFetch.Reason? {
        AutoFetch.decide(enabled: på, bandReady: redo, busy: upptagen, justConnected: ansluten,
                         now: t0.addingTimeInterval(om), state: s)
    }

    func testAvHämtarAldrig() {
        XCTAssertNil(beslut(AutoFetch.State(), på: false))
        XCTAssertNil(beslut(slutad(10 * 3600), på: false, ansluten: true))
    }

    func testInteUtanBandEllerMedanNågotPågår() {
        XCTAssertNil(beslut(slutad(2 * 3600), redo: false))
        XCTAssertNil(beslut(slutad(2 * 3600), upptagen: true), "en hämtning eller ett IMU-prov pågår")
    }

    func testFörstaGångenHämtarDirekt() {
        XCTAssertEqual(beslut(AutoFetch.State()), .first)
    }

    func testEnGångITimmen() {
        XCTAssertNil(beslut(slutad(59 * 60)))
        XCTAssertEqual(beslut(slutad(60 * 60)), .interval)
        XCTAssertEqual(beslut(slutad(5 * 3600)), .interval, "en lång tystnad hämtar vid första vakna stund")
    }

    func testEnÅteranslutningHämtarOmFörraVarMinstFemMinuterSedan() {
        XCTAssertEqual(beslut(slutad(10 * 60), ansluten: true), .connected)
        XCTAssertNil(beslut(slutad(2 * 60), ansluten: true), "tätt efter en hämtning: ingen ny vid varje ny anslutning")
        XCTAssertNil(beslut(slutad(10 * 60), ansluten: false), "utan anslutning väntar den in timmen")
    }

    func testEttStoppFörsökerIgenEfterFemMinuter() {
        let s = slutad(4 * 60, .stopped(.disconnected))
        XCTAssertNil(beslut(s))
        XCTAssertEqual(beslut(s, om: 60), .retry)
        XCTAssertNil(beslut(s, ansluten: true), "inte heller vid en återanslutning före fem minuter")
    }

    func testWhoopAppenSomSynkarFårEnHalvtimme() {
        let s = slutad(10 * 60, .stopped(.otherApp(command: 34)))
        XCTAssertTrue(s.lastStopWasOtherApp)
        XCTAssertNil(beslut(s))
        XCTAssertEqual(beslut(s, om: 20 * 60), .retry)
    }

    func testEnHämtningSomAldrigSlutadeFörsökerIgenEfterTioMinuter() {
        // Förra slutade för en timme sedan; en ny började för fem minuter sedan och appen dödades.
        var s = slutad(3600)
        s.started(at: t0.addingTimeInterval(-5 * 60))
        XCTAssertNil(beslut(s), "kanske pågår den fortfarande i en annan process: vänta")
        XCTAssertEqual(beslut(s, om: 5 * 60), .retry)
        // Allra första hämtningen dödades.
        var första = AutoFetch.State()
        första.started(at: t0.addingTimeInterval(-11 * 60))
        XCTAssertEqual(beslut(första), .retry)
    }

    func testEnLyckadHämtningEfterEttStoppGårTillbakaTillTimmen() {
        var s = slutad(3600, .stopped(.idle))
        s.started(at: t0.addingTimeInterval(-60))
        s.ended(at: t0.addingTimeInterval(-40), .complete)
        XCTAssertFalse(s.lastStopped)
        XCTAssertNil(beslut(s))
        XCTAssertEqual(beslut(s, om: 3600), .interval)
    }

    func testTillståndetGårAttSparaOchLäsaIgen() throws {
        let s = slutad(100, .stopped(.otherApp(command: 23)))
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AutoFetch.State.self, from: data), s)
    }
}
