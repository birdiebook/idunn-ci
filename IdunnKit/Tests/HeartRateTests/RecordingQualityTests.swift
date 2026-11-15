import Foundation
import XCTest
@testable import HeartRate

// Nätterna är påhittade (NightFixtures.swift). METOD M13.

final class RecordingQualityTests: XCTestCase {
    func testMättNattKlararAlltUtanGlapp() throws {
        let r = RecordingQuality.report(NightFixtures.night(NightFixtures.measuredBeats()))
        let g = try XCTUnwrap(r.gaps)
        XCTAssertEqual(g.count, 0)
        XCTAssertEqual(g.fraction, 0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(r.coverage).fractionComplete, 0.9)
        XCTAssertGreaterThan(try XCTUnwrap(r.coverage).minutes, 50)
        let c = try XCTUnwrap(r.computed)
        XCTAssertLessThan(c.fractionEqualToBpm, 0.05)
        XCTAssertLessThan(c.fractionIdentical, 0.05)
        XCTAssertLessThan(try XCTUnwrap(r.smoothing).ratio, 0.3)
        XCTAssertTrue(r.passes, r.description)
    }

    func testRRUträknadeUrHeltalspulsenFäller() throws {
        let r = RecordingQuality.report(NightFixtures.computedFromBpm(NightFixtures.measuredBeats()))
        let c = try XCTUnwrap(r.computed)
        XCTAssertEqual(c.fractionEqualToBpm, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(c.fractionIdentical, 0.3)
        XCTAssertFalse(c.passes)
        XCTAssertTrue(try XCTUnwrap(r.coverage).passes, "antalet stämmer — det är värdena som är fel")
        XCTAssertFalse(r.passes)
    }

    func testJämnKurvaFällerKvoten() throws {
        let s = try XCTUnwrap(RecordingQuality.smoothing(NightFixtures.night(NightFixtures.smoothCurve())))
        XCTAssertGreaterThan(s.ratio, 0.9)
        XCTAssertFalse(s.passes)
    }

    func testKraftigUtjämningFångasAvSammaVärdeInteAvKvoten() throws {
        // METOD M13: när det som är kvar av variationen är mindre än upplösningen
        // (0,977 ms) blir avrundningen brus, och kvoten ser mätt ut. Det är
        // "samma värde som förra slaget" som fäller en sådan natt.
        let natt = NightFixtures.night(NightFixtures.exponentiallySmoothed(NightFixtures.measuredBeats()))
        let r = RecordingQuality.report(natt)
        XCTAssertTrue(try XCTUnwrap(r.smoothing).passes)
        XCTAssertGreaterThan(try XCTUnwrap(r.computed).fractionIdentical, 0.1)
        XCTAssertFalse(r.passes)
    }

    func testTappadeSlagFällerTäckningen() throws {
        let r = RecordingQuality.report(NightFixtures.missingBeats(NightFixtures.measuredBeats()))
        let c = try XCTUnwrap(r.coverage)
        XCTAssertLessThan(c.fractionComplete, 0.1)
        XCTAssertFalse(c.passes)
        XCTAssertEqual(try XCTUnwrap(r.gaps).count, 0, "notiserna kom — de var bara tomma")
    }

    func testTioMinuterUtanNotisÄrEttGlapp() throws {
        let hel = NightFixtures.night(NightFixtures.measuredBeats())
        let g = try XCTUnwrap(RecordingQuality.gaps(NightFixtures.withHole(hel, from: 1200, to: 1800)))
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g.longest, 601, accuracy: 1e-6)
        XCTAssertEqual(g.total, g.longest)
        XCTAssertEqual(g.fraction, 601 / hel.span, accuracy: 1e-9)
        XCTAssertFalse(g.passes)
    }

    func testEnHalvMinutsPausÄrInteEttGlapp() throws {
        let hel = NightFixtures.night(NightFixtures.measuredBeats())
        let g = try XCTUnwrap(RecordingQuality.gaps(NightFixtures.withHole(hel, from: 1200, to: 1230)))
        XCTAssertEqual(g.count, 0)
        XCTAssertTrue(g.passes)
    }

    func testGlappetBryterSlagföljden() {
        // Två avsnitt: ingen skillnad räknas mellan sista slaget före glappet
        // och första efter.
        let t = Date(timeIntervalSince1970: NightFixtures.t0)
        let n = NightRecording(samples: [
            HeartRateSample(time: t, bpm: 60, rrMilliseconds: [1000, 1010]),
            HeartRateSample(time: t.addingTimeInterval(120), bpm: 50, rrMilliseconds: [1200, 1190]),
        ])
        XCTAssertEqual(RecordingQuality.segments(n), [[1000, 1010], [1200, 1190]])
        XCTAssertEqual(RecordingQuality.rmssd(RecordingQuality.segments(n)), 10)
    }

    func testKvotenSammaSomKollaRR() throws {
        // Facit räknat med rmssd() och samma medelkurva i tools/kolla_rr.py.
        let t = Date(timeIntervalSince1970: NightFixtures.t0)
        let rr: [Double] = (0..<80).map { (i: Int) -> Double in
            let x = Double(i)
            let våg: Double = 30 * sin(1.3 * x)
            let våg2: Double = 20 * cos(0.7 * x)
            return 1000 + våg + våg2
        }
        let n = NightRecording(samples: rr.enumerated().map { i, x in
            HeartRateSample(time: t.addingTimeInterval(Double(i)), bpm: 60, rrMilliseconds: [x])
        })
        let s = try XCTUnwrap(RecordingQuality.smoothing(n))
        XCTAssertEqual(s.intervals, 80)
        XCTAssertEqual(s.ratio, 0.20226441251302438, accuracy: 1e-12)
    }

    func testFörLiteDataGerIngenBedömning() {
        let t = Date(timeIntervalSince1970: NightFixtures.t0)
        let kort = NightRecording(samples: (0..<30).map { i in
            HeartRateSample(time: t.addingTimeInterval(Double(i)), bpm: 60, rrMilliseconds: [1000])
        })
        XCTAssertNil(RecordingQuality.computed(kort))
        XCTAssertNil(RecordingQuality.smoothing(kort))
        XCTAssertNil(RecordingQuality.coverage(kort), "ingen hel minut")
        XCTAssertNil(RecordingQuality.gaps(NightRecording()))
        XCTAssertFalse(RecordingQuality.report(kort).passes)
    }

    func testRapportenBärBaraAndelar() {
        // BESLUT B3: inga intervall i texten. Varje intervall är minst 300 ms, så
        // inget tal i rapporten får vara så stort (utom rubrikens 60000).
        let r = RecordingQuality.report(NightFixtures.night(NightFixtures.measuredBeats()))
        let tal = r.description.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertFalse(tal.isEmpty)
        XCTAssertTrue(tal.allSatisfy { $0 < 300 || $0 == 60_000 }, r.description)
        XCTAssertTrue(r.description.contains("RIMLIGT"))
    }
}
