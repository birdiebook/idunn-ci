import Foundation
import XCTest
@testable import HeartRate

// Nätterna är påhittade (NightFixtures.swift). METOD M15: diagnosen ska skilja
// de fyra förklaringarna till att "varje slag" fäller — en normal natt, bandet
// som upprepar förra notisens slag (framlänges eller omvänt), och tappade RR.
// Talen är provade i Python med en spegel av generatorn innan de skrevs in.

final class RecordingDiagnosticsTests: XCTestCase {
    func testNormalNattStämmerÖverallt() throws {
        let d = RecordingQuality.diagnostics(NightFixtures.night(NightFixtures.measuredBeats()))
        XCTAssertGreaterThan(d.rrPerNotification[1], 0.9, "en notis i sekunden, ett slag i sekunden")
        XCTAssertEqual(d.rrPerNotification.reduce(0, +), 1, accuracy: 1e-12)
        XCTAssertGreaterThan(d.pairs, 3000)
        XCTAssertLessThan(d.firstRepeatsPreviousLast, 0.05)
        XCTAssertLessThan(d.lastRepeatsPreviousFirst, 0.05)
        XCTAssertLessThan(d.sharesAnyWithPrevious, 0.05)
        XCTAssertGreaterThan(d.minutes, 50)
        XCTAssertEqual(try XCTUnwrap(d.countToBpm), 1, accuracy: 0.02)
        XCTAssertEqual(d.minutesBelow, 0)
        XCTAssertEqual(d.minutesAbove, 0)
        XCTAssertEqual(try XCTUnwrap(d.rrRateToBpm), 1, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(d.notificationsToBpm), 1, accuracy: 0.03)
        XCTAssertEqual(try XCTUnwrap(d.rrTimeToElapsed), 1, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(d.rrTimeToElapsedMedian), 1, accuracy: 0.05)
    }

    func testUpprepatSlagFramlänges() throws {
        let natt = NightFixtures.overlapping(NightFixtures.measuredBeats())
        let d = RecordingQuality.diagnostics(natt)
        XCTAssertGreaterThan(d.rrPerNotification[2], 0.9)
        XCTAssertGreaterThan(d.firstRepeatsPreviousLast, 0.95)
        XCTAssertLessThan(d.lastRepeatsPreviousFirst, 0.05)
        XCTAssertGreaterThan(d.sharesAnyWithPrevious, 0.95)
        XCTAssertEqual(try XCTUnwrap(d.countToBpm), 2, accuracy: 0.05)
        XCTAssertEqual(d.minutesAbove, 1)
        XCTAssertEqual(try XCTUnwrap(d.rrRateToBpm), 1, accuracy: 0.02, "värdena stämmer, det är antalet som är dubbelt")
        XCTAssertEqual(try XCTUnwrap(d.rrTimeToElapsed), 2, accuracy: 0.05)

        // Kontrollerna: 1 fäller, och framlänges ger det "samma värde som förra slaget".
        let r = RecordingQuality.report(natt)
        XCTAssertFalse(try XCTUnwrap(r.coverage).passes)
        XCTAssertGreaterThan(try XCTUnwrap(r.computed).fractionIdentical, 0.4)
    }

    func testUpprepatSlagOmväntSynsBaraIDiagnosen() throws {
        let natt = NightFixtures.overlapping(NightFixtures.measuredBeats(), reversed: true)
        let d = RecordingQuality.diagnostics(natt)
        XCTAssertLessThan(d.firstRepeatsPreviousLast, 0.05)
        XCTAssertGreaterThan(d.lastRepeatsPreviousFirst, 0.95)
        XCTAssertGreaterThan(d.sharesAnyWithPrevious, 0.95)
        XCTAssertEqual(try XCTUnwrap(d.countToBpm), 2, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(d.rrTimeToElapsed), 2, accuracy: 0.05)

        // Omvänt klarar kontroll 2 och 3 — bara "varje slag" fäller. Samma
        // mönster som användaren första prov, därför diagnosen.
        let r = RecordingQuality.report(natt)
        XCTAssertFalse(try XCTUnwrap(r.coverage).passes)
        XCTAssertTrue(try XCTUnwrap(r.computed).passes)
        XCTAssertTrue(try XCTUnwrap(r.smoothing).passes)
    }

    func testTappadeRR() throws {
        let d = RecordingQuality.diagnostics(NightFixtures.missingBeats(NightFixtures.measuredBeats()))
        XCTAssertGreaterThan(d.rrPerNotification[0], 0.45)
        XCTAssertLessThan(d.sharesAnyWithPrevious, 0.05)
        XCTAssertEqual(try XCTUnwrap(d.countToBpm), 0.5, accuracy: 0.05)
        XCTAssertEqual(d.minutesBelow, 1)
        XCTAssertEqual(d.minutesAbove, 0)
        XCTAssertEqual(try XCTUnwrap(d.rrRateToBpm), 1, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(d.notificationsToBpm), 1, accuracy: 0.03, "notiserna kom")
        XCTAssertEqual(try XCTUnwrap(d.rrTimeToElapsed), 0.5, accuracy: 0.05)
    }

    func testFältSomInteÄrRRStårStillFörst() throws {
        // Ett fält som läses som första RR i varje notis kryper långsamt, så
        // notisens första värde är förra notisens första.
        let d = RecordingQuality.diagnostics(NightFixtures.extraField(NightFixtures.measuredBeats()))
        XCTAssertGreaterThan(d.firstRepeatsPreviousFirst, 0.95)
        XCTAssertLessThan(d.firstRepeatsPreviousLast, 0.05)
        XCTAssertEqual(try XCTUnwrap(d.countToBpm), 2, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(d.rrRateToBpm), 1, accuracy: 0.02, "fältet ligger under 300 ms och räknas inte")
        XCTAssertEqual(d.flags, [.init(flags: 0x16, share: 1)])

        let normal = RecordingQuality.diagnostics(NightFixtures.night(NightFixtures.measuredBeats()))
        XCTAssertLessThan(normal.firstRepeatsPreviousFirst, 0.05)
        XCTAssertEqual(normal.flags, [], "fixturens notiser bär ingen flagga")
    }

    func testFlaggornaVanligastFörst() {
        let t = Date(timeIntervalSince1970: NightFixtures.t0)
        let flaggor: [UInt8?] = [0x16, 0x10, 0x16, 0x16, nil]
        let n = NightRecording(samples: flaggor.enumerated().map { (i: Int, f: UInt8?) -> HeartRateSample in
            HeartRateSample(time: t.addingTimeInterval(Double(i)), bpm: 60, rrMilliseconds: [1000], flags: f)
        })
        let d = RecordingQuality.diagnostics(n)
        XCTAssertEqual(d.flags, [.init(flags: 0x16, share: 0.75), .init(flags: 0x10, share: 0.25)])
        XCTAssertTrue(d.description.contains("0x16 75 %"), d.description)
    }

    func testSammaSlagInomEttSteg() {
        // METOD M15: högst ett steg (1/1024 s) isär räknas som samma slag.
        let t = Date(timeIntervalSince1970: NightFixtures.t0)
        let steg: Double = 1000.0 / 1024.0
        let n = NightRecording(samples: [
            HeartRateSample(time: t, bpm: 60, rrMilliseconds: [1000]),
            HeartRateSample(time: t.addingTimeInterval(1), bpm: 60, rrMilliseconds: [1000 + steg, 990]),
            HeartRateSample(time: t.addingTimeInterval(2), bpm: 60, rrMilliseconds: [990 + 2 * steg]),
            // Efter ett glapp jämförs inget med före.
            HeartRateSample(time: t.addingTimeInterval(100), bpm: 60, rrMilliseconds: [990 + 2 * steg]),
        ])
        let d = RecordingQuality.diagnostics(n)
        XCTAssertEqual(d.pairs, 2)
        XCTAssertEqual(d.firstRepeatsPreviousLast, 0.5)
        XCTAssertEqual(d.sharesAnyWithPrevious, 0.5)
        XCTAssertEqual(d.rrPerNotification, [0, 0.75, 0.25, 0])
    }

    func testTomNattGerIngaKvoter() {
        let d = RecordingQuality.diagnostics(NightRecording())
        XCTAssertEqual(d.notifications, 0)
        XCTAssertEqual(d.pairs, 0)
        XCTAssertNil(d.countToBpm)
        XCTAssertNil(d.rrTimeToElapsed)
        XCTAssertEqual(d.rrPerNotification, [0, 0, 0, 0])
    }

    func testDiagnosenBärBaraAndelar() {
        // BESLUT B3: inga intervall i texten; varje intervall är minst 300 ms.
        let d = RecordingQuality.diagnostics(NightFixtures.overlapping(NightFixtures.measuredBeats()))
        let tal = d.description.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertFalse(tal.isEmpty)
        XCTAssertTrue(tal.allSatisfy { $0 < 300 }, d.description)
    }
}
