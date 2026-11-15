import Foundation
import XCTest
@testable import WhoopFrames

// METOD M25. Påhittade poster, bara tal: en inspelning på 120 minuter från en
// minutgräns, med K18 i tre sekunder per minut (så att rörelsen har en Δ).

final class SkinTemperatureTests: XCTestCase {
    static let t0 = 1_760_000_040 // en minutgräns
    var start: Date { Date(timeIntervalSince1970: Double(Self.t0)) }
    func end(minuter: Int) -> Date { start.addingTimeInterval(Double(minuter) * 60) }

    /// Tre sekunder i minut `m` (från inspelningens start). `steg` är hur långt
    /// z hoppar mellan sekunderna: 0 är en stilla arm.
    func minut(_ m: Int, hud: Double, steg: Float = 0, sekunder: Int = 3) -> [K18Record] {
        (0..<sekunder).map { j in
            K18Record(time: Self.t0 + m * 60 + j, pulse: 55, rr: [],
                      gravity: .init(x: 0, y: 0, z: 1 + (j % 2 == 1 ? Double(steg) : 0)),
                      skinTemperature: hud, bandTemperature: 30)
        }
    }

    /// Minuterna `m` i `intervall` med samma temperatur och rörelse.
    func serie(_ intervall: Range<Int>, hud: Double, steg: Float = 0, sekunder: Int = 3) -> [K18Record] {
        intervall.flatMap { minut($0, hud: hud, steg: steg, sekunder: sekunder) }
    }

    // MARK: Medianen över de stilla minuterna

    func testMedianenTasBaraÖverDeStillaMinuterna() throws {
        // 40 stilla minuter på 33,0 och 80 rörliga på 35,0: medianen över allt
        // vore 35,0, över de stilla 33,0.
        let s = K18Series(records: serie(0..<40, hud: 33.0) + serie(40..<120, hud: 35.0, steg: 0.3))
        let n = SkinTemperature.night(s, from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(n.celsius), 33.0, accuracy: 1e-12)
        XCTAssertEqual(n.stillMinutes, 40)
        XCTAssertEqual(try XCTUnwrap(n.coverage), 1.0, accuracy: 1e-12)
    }

    func testMedianenAvJämntAntalÄrMedelAvDeTvåMittersta() throws {
        let s = K18Series(records: serie(0..<50, hud: 33.0) + serie(50..<100, hud: 33.4))
        let n = SkinTemperature.night(s, from: start, to: end(minuter: 100))
        XCTAssertEqual(try XCTUnwrap(n.celsius), 33.2, accuracy: 1e-12)
    }

    func testTröskelnÄrEnGräns() {
        // Rörelse per minut = medel av |Δg|: här d, d (tre sekunder, två steg).
        let under = K18Series(records: serie(0..<60, hud: 33.0, steg: Float(SkinTemperature.stillMovement) - 0.003))
        let över = K18Series(records: serie(0..<60, hud: 33.0, steg: Float(SkinTemperature.stillMovement) + 0.003))
        XCTAssertEqual(SkinTemperature.night(under, from: start, to: end(minuter: 60)).stillMinutes, 60)
        let n = SkinTemperature.night(över, from: start, to: end(minuter: 60))
        XCTAssertEqual(n.stillMinutes, 0)
        XCTAssertNil(n.celsius, "ingen stilla minut: ingen temperatur")
    }

    func testEnMinutUtanRörelseÄrInteStilla() throws {
        // En post per minut ger ingen Δ, alltså ingen rörelse (METOD M24):
        // minuten kan inte sägas vara stilla.
        let s = K18Series(records: serie(0..<120, hud: 33.0, sekunder: 1))
        let n = SkinTemperature.night(s, from: start, to: end(minuter: 120))
        XCTAssertEqual(n.stillMinutes, 0)
        XCTAssertNil(n.celsius)
        XCTAssertEqual(try XCTUnwrap(n.coverage), 1.0, accuracy: 1e-12)
    }

    // MARK: Minsta täckning och minsta antal stilla minuter

    func testUnderMinstaTäckningGerIngenTemperatur() throws {
        // 59 av 120 minuter: 49 %, under hälften. Alla minuter är stilla.
        let under = K18Series(records: serie(0..<59, hud: 33.0))
        let a = SkinTemperature.night(under, from: start, to: end(minuter: 120))
        XCTAssertNil(a.celsius)
        XCTAssertEqual(try XCTUnwrap(a.coverage), 59.0 / 120, accuracy: 1e-12)
        XCTAssertEqual(a.stillMinutes, 59, "täckningen, inte stillheten, fäller natten")

        // 60 av 120: exakt hälften räcker.
        let gräns = K18Series(records: serie(0..<60, hud: 33.0))
        let b = SkinTemperature.night(gräns, from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(b.celsius), 33.0, accuracy: 1e-12)
    }

    func testTäckningenRäknasÖverInspelningenOchInteÖverK18sEgnaSpann() throws {
        // K18 från 60 minuter i rad, inspelning på 240: 25 %. Hade täckningen
        // räknats mot K18:s eget spann hade den varit 100 %.
        let s = K18Series(records: serie(0..<60, hud: 33.0))
        let n = SkinTemperature.night(s, from: start, to: end(minuter: 240))
        XCTAssertNil(n.celsius)
        XCTAssertEqual(try XCTUnwrap(n.coverage), 0.25, accuracy: 1e-12)
    }

    func testEttGlappIMittenMinskarTäckningenMenStårInteIVägen() throws {
        // 30 minuter, ett glapp på 30, och 60 till: 90 av 120.
        let s = K18Series(records: serie(0..<30, hud: 33.0) + serie(60..<120, hud: 33.0))
        let n = SkinTemperature.night(s, from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(n.coverage), 0.75, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(n.celsius), 33.0, accuracy: 1e-12)
    }

    func testFörFåStillaMinuterGerIngenTemperatur() throws {
        // Full täckning, men bara 29 stilla minuter av 120.
        let få = K18Series(records: serie(0..<29, hud: 33.0) + serie(29..<120, hud: 35.0, steg: 0.3))
        let a = SkinTemperature.night(få, from: start, to: end(minuter: 120))
        XCTAssertEqual(a.stillMinutes, 29)
        XCTAssertNil(a.celsius)
        XCTAssertEqual(try XCTUnwrap(a.coverage), 1.0, accuracy: 1e-12)

        let nog = K18Series(records: serie(0..<30, hud: 33.0) + serie(30..<120, hud: 35.0, steg: 0.3))
        let b = SkinTemperature.night(nog, from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(b.celsius), 33.0, accuracy: 1e-12)
    }

    // MARK: Intervallet

    func testBaraMinuterInomInspelningenRäknas() throws {
        // Efter inspelningens slut kommer 60 stilla minuter på 40 °C (en sen
        // synk): de ingår varken i täckningen eller i medianen.
        let s = K18Series(records: serie(0..<120, hud: 33.0) + serie(120..<180, hud: 40.0))
        let n = SkinTemperature.night(s, from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(n.celsius), 33.0, accuracy: 1e-12)
        XCTAssertEqual(n.stillMinutes, 120)
        XCTAssertEqual(try XCTUnwrap(n.coverage), 1.0, accuracy: 1e-12)
    }

    func testTomtEllerVäntIntervallGerIngenTemperaturOchIngenTäckning() {
        let s = K18Series(records: serie(0..<120, hud: 33.0))
        for (a, b) in [(start, start), (end(minuter: 10), start)] {
            let n = SkinTemperature.night(s, from: a, to: b)
            XCTAssertNil(n.celsius)
            XCTAssertNil(n.coverage)
            XCTAssertEqual(n.stillMinutes, 0)
        }
    }

    func testIngaPosterGerTäckningNoll() throws {
        let n = SkinTemperature.night(K18Series(records: []), from: start, to: end(minuter: 120))
        XCTAssertNil(n.celsius)
        XCTAssertEqual(try XCTUnwrap(n.coverage), 0)
    }

    func testDubbletterRäknasEnGångIMedianen() throws {
        // Samma sekunder två gånger (Whoop synkade om): serien håller en post
        // per sekund, så täckning och median blir som utan dubbletter.
        let poster = serie(0..<60, hud: 33.0)
        let s = K18Series(records: poster + poster)
        XCTAssertEqual(s.duplicates, poster.count)
        let n = SkinTemperature.night(s, from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(n.celsius), 33.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(n.coverage), 0.5, accuracy: 1e-12)
    }

    // MARK: Sömnperioden som underlag (METOD M26)

    /// Unix-minuterna `m` i `intervall`, räknade från inspelningens start.
    func unixMinuter(_ intervall: Range<Int>) -> [Int] {
        intervall.map { (Self.t0 + $0 * 60) / 60 }
    }

    func testMedianenTasÖverSömnminuternaOchInteÖverDeStilla() throws {
        // 40 sömnminuter på 33,0 och 80 andra på 35,0. De 40 rör sig (steg 0,3)
        // och vore inte stilla, men sömnmetoden har redan avgjort att de är sömn.
        let s = K18Series(records: serie(0..<40, hud: 33.0, steg: 0.3) + serie(40..<120, hud: 35.0))
        let n = SkinTemperature.night(s, asleepMinutes: unixMinuter(0..<40),
                                      from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(n.celsius), 33.0, accuracy: 1e-12)
        XCTAssertEqual(n.stillMinutes, 40)
        XCTAssertEqual(n.basis, .sleepPeriod)
        XCTAssertEqual(try XCTUnwrap(n.coverage), 1.0, accuracy: 1e-12)
    }

    func testMinutSomSaknasIK18KanInteVaraSömnminut() {
        // Sömnmetoden ger 60 minuter men K18 finns bara i 25 av dem.
        let s = K18Series(records: serie(0..<25, hud: 33.0))
        let n = SkinTemperature.night(s, asleepMinutes: unixMinuter(0..<60),
                                      from: start, to: end(minuter: 60))
        XCTAssertEqual(n.stillMinutes, 25)
        XCTAssertNil(n.celsius, "25 minuter är under minsta antal, och täckningen är 42 %")
    }

    func testSömnperiodensGränserOchMinstaAntal() throws {
        let s = K18Series(records: serie(0..<120, hud: 33.0))
        // 29 sömnminuter: för få. 30: räcker.
        let få = SkinTemperature.night(s, asleepMinutes: unixMinuter(0..<29),
                                       from: start, to: end(minuter: 120))
        XCTAssertNil(få.celsius)
        XCTAssertEqual(få.stillMinutes, 29)
        let nog = SkinTemperature.night(s, asleepMinutes: unixMinuter(0..<30),
                                        from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(nog.celsius), 33.0, accuracy: 1e-12)
        // Sömnminuter utanför perioden räknas inte.
        let utanför = SkinTemperature.night(s, asleepMinutes: unixMinuter(0..<120),
                                            from: end(minuter: 60), to: end(minuter: 120))
        XCTAssertEqual(utanför.stillMinutes, 60)
    }

    func testTäckningenRäknasÖverSömnperiodenOchGerIngenTemperaturUnderHälften() throws {
        // Perioden är 120 minuter; K18 finns i 59 av dem, alla sömn.
        let s = K18Series(records: serie(0..<59, hud: 33.0))
        let a = SkinTemperature.night(s, asleepMinutes: unixMinuter(0..<120),
                                      from: start, to: end(minuter: 120))
        XCTAssertNil(a.celsius)
        XCTAssertEqual(try XCTUnwrap(a.coverage), 59.0 / 120, accuracy: 1e-12)
        let b = SkinTemperature.night(K18Series(records: serie(0..<60, hud: 33.0)),
                                      asleepMinutes: unixMinuter(0..<120),
                                      from: start, to: end(minuter: 120))
        XCTAssertEqual(try XCTUnwrap(b.celsius), 33.0, accuracy: 1e-12)
    }

    func testTomPeriodGerIngenTemperaturMedSömnunderlaget() {
        let s = K18Series(records: serie(0..<120, hud: 33.0))
        let n = SkinTemperature.night(s, asleepMinutes: [], from: start, to: start)
        XCTAssertNil(n.celsius)
        XCTAssertNil(n.coverage)
        XCTAssertEqual(n.basis, .sleepPeriod)
        XCTAssertEqual(SkinTemperature.night(s, from: start, to: end(minuter: 120)).basis, .recording)
    }
}
