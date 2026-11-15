import Foundation
import XCTest
import WhoopFrames
import DemoData
@testable import Night

// METOD M25 · METOD M26. Hudtemperaturen över sömnperioden, med reserv.

final class SleepSkinTemperatureTests: XCTestCase {
    static let t0 = 1_760_000_040
    static let m = 60

    /// En natt med 33,0 °C under sömnen och 36,0 °C när man är uppe.
    func natt() throws -> (series: K18Series, period: SleepPeriod, from: Date, to: Date) {
        var recs = DemoSleep.records(
            start: Self.t0,
            phases: [.active(seconds: 40 * Self.m), .still(seconds: 300 * Self.m), .active(seconds: 40 * Self.m)],
            seed: 9)
        let sovStart = Self.t0 + 40 * Self.m
        let sovSlut = sovStart + 300 * Self.m
        for i in recs.indices {
            recs[i].skinTemperature = (recs[i].time >= sovStart && recs[i].time < sovSlut) ? 33.0 : 36.0
        }
        let series = K18Series(records: recs)
        let from = Date(timeIntervalSince1970: Double(Self.t0 - 600))
        let to = Date(timeIntervalSince1970: Double(Self.t0 + 380 * Self.m + 600))
        let p = try XCTUnwrap(SleepDetection.detect(series, from: from, to: to))
        return (series, p, from, to)
    }

    func testMedSömnperiodTasMedianenÖverSömnminuterna() throws {
        let n = try natt()
        let t = SkinTemperature.night(n.series, sleep: n.period, recordingFrom: n.from, recordingTo: n.to)
        XCTAssertEqual(try XCTUnwrap(t.celsius), 33.0, accuracy: 1e-9)
        XCTAssertEqual(t.basis, .sleepPeriod)
        XCTAssertEqual(Double(t.stillMinutes), 300, accuracy: 3)
        XCTAssertEqual(try XCTUnwrap(t.coverage), 1.0, accuracy: 0.01, "täckningen över perioden")
    }

    func testUtanSömnperiodGällerInspelningensStillaMinuterSomFörut() throws {
        let n = try natt()
        let t = SkinTemperature.night(n.series, sleep: nil, recordingFrom: n.from, recordingTo: n.to)
        XCTAssertEqual(t.basis, .recording)
        let gammal = SkinTemperature.night(n.series, from: n.from, to: n.to)
        XCTAssertEqual(t, gammal, "reserven är exakt det gamla")
    }

    func testEnOroligStundIPeriodenFårInteDraTemperaturen() throws {
        // Sömn, en orolig stund på 20 min (36 °C) och mer sömn: stunden är
        // vaken och ingår inte i sömnminuterna.
        let m = Self.m
        var recs = DemoSleep.records(
            start: Self.t0,
            phases: [.active(seconds: 30 * m), .still(seconds: 150 * m), .restless(seconds: 20 * m, every: 100),
                     .still(seconds: 150 * m), .active(seconds: 30 * m)],
            seed: 13)
        let oroStart = Self.t0 + 180 * m
        let oroSlut = oroStart + 20 * m
        // 33,0 °C rakt igenom utom stunden: DemoSleep ger numera en hudtemperatur som stiger genom natten.
        for i in recs.indices {
            recs[i].skinTemperature = (recs[i].time >= oroStart && recs[i].time < oroSlut) ? 36.0 : 33.0
        }
        let series = K18Series(records: recs)
        let from = Date(timeIntervalSince1970: Double(Self.t0 - 600))
        let to = Date(timeIntervalSince1970: Double(Self.t0 + 380 * m + 600))
        let p = try XCTUnwrap(SleepDetection.detect(series, from: from, to: to))
        XCTAssertGreaterThan(p.awakeSeconds, 15 * 60)
        let t = SkinTemperature.night(series, sleep: p, recordingFrom: from, recordingTo: to)
        XCTAssertEqual(try XCTUnwrap(t.celsius), 33.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(t.stillMinutes, p.asleepSeconds / 60 + 3)
    }
}
