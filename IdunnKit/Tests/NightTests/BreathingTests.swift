import Foundation
import XCTest
import HeartRate
@testable import Night

// Nätterna är påhittade (NightGenerator.swift). METOD M10.

final class BreathingTests: XCTestCase {
    /// Slag med en andningsvåg på `hz` (respiratorisk sinusarytmi, 40 ms) och lite brus.
    func rsa(_ hz: Double, seed: UInt64) -> NightRecording {
        NightGenerator.night(NightGenerator.beats(seconds: 1800, seed: seed) {
            (_: Int, t: Double, r: inout Seeded) -> Double in
            let våg: Double = 40 * sin(2 * Double.pi * hz * t)
            return 1000 + våg + 10 * r.gauss()
        })
    }

    func testAndningPåFemtonPerMinutHittas() throws {
        let r = NightAnalysis.analyze(rsa(0.25, seed: 3))
        XCTAssertEqual(r.validWindows, 6)
        XCTAssertEqual(r.clearBreathingWindows, 6)
        for w in r.windows {
            XCTAssertEqual(try XCTUnwrap(w.breathing?.breathsPerMinute), 15, accuracy: 1)
        }
        XCTAssertEqual(try XCTUnwrap(r.breathsPerMinute), 15, accuracy: 1)
    }

    func testAndningPåTolvOchArtonPerMinut() throws {
        XCTAssertEqual(try XCTUnwrap(NightAnalysis.analyze(rsa(0.2, seed: 4)).breathsPerMinute), 12, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(NightAnalysis.analyze(rsa(0.3, seed: 5)).breathsPerMinute), 18, accuracy: 1)
    }

    func testBrusUtanAndningGerIngenTydligTopp() throws {
        let natt = NightGenerator.night(NightGenerator.beats(seconds: 3600, seed: 7) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 1000 + 25 * r.gauss()
        })
        let r = NightAnalysis.analyze(natt)
        XCTAssertEqual(r.validWindows, 12)
        XCTAssertEqual(r.clearBreathingWindows, 0)
        for w in r.windows {
            let b = try XCTUnwrap(w.breathing)
            XCTAssertLessThan(b.peakShare, Breathing.minPeakShare)
            XCTAssertNil(b.breathsPerMinute)
        }
        XCTAssertNil(r.breathsPerMinute)
    }

    func testPlattSerieGerIngenTopp() throws {
        let r = NightAnalysis.analyze(NightGenerator.night(NightGenerator.beats(seconds: 900) {
            (_: Int, _: Double, _: inout Seeded) -> Double in 1000
        }))
        XCTAssertGreaterThan(r.validWindows, 0)
        XCTAssertEqual(r.clearBreathingWindows, 0)
        XCTAssertNil(r.breathsPerMinute)
    }

    func testLångsamVågUnderBandetGerIngenTopp() {
        // 0,1 Hz (6 per minut) ligger under 0,15 Hz: bandets kant är en sluttning,
        // ingen topp.
        let natt = NightGenerator.night(NightGenerator.beats(seconds: 1800, seed: 9) {
            (_: Int, t: Double, r: inout Seeded) -> Double in
            let våg: Double = 60 * sin(2 * Double.pi * 0.1 * t)
            return 1000 + våg + 5 * r.gauss()
        })
        let r = NightAnalysis.analyze(natt)
        XCTAssertEqual(r.clearBreathingWindows, 0)
        XCTAssertNil(r.breathsPerMinute)
    }

    func testSkattarenDirektPåJämnSerie() throws {
        // Ett slag i sekunden i fem minuter, våg på 0,25 Hz: 15 per minut.
        let t: [Double] = (0..<300).map { Double($0) }
        let rr: [Double] = t.map { (x: Double) -> Double in 1000 + 30 * sin(2 * Double.pi * 0.25 * x) }
        let e = try XCTUnwrap(Breathing.estimate(times: t, rrMilliseconds: rr))
        XCTAssertTrue(e.isClear)
        XCTAssertEqual(try XCTUnwrap(e.breathsPerMinute), 15, accuracy: 0.5)
        XCTAssertGreaterThan(e.peakShare, 0.8)
    }

    func testKortareÄnEnBitGerIngenSkattning() {
        let t: [Double] = (0..<100).map { Double($0) }
        XCTAssertNil(Breathing.estimate(times: t, rrMilliseconds: t.map { _ in 1000 }))
        XCTAssertNil(Breathing.estimate(times: [], rrMilliseconds: []))
    }

    func testInterpolationenTillJämnAxel() {
        // 4 Hz mellan (0 s, 1000 ms) och (1 s, 1100 ms); en punkt som inte ligger
        // efter den förra hoppas över.
        let x = Breathing.resample(times: [0, 1, 0.5, 2], values: [1000, 1100, 5000, 1100])
        XCTAssertEqual(x, [1000, 1025, 1050, 1075, 1100, 1100, 1100, 1100, 1100])
    }
}
