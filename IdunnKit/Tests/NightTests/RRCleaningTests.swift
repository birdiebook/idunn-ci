import Foundation
import XCTest
import HeartRate
@testable import Night

// Nätterna är påhittade (NightGenerator.swift). METOD M3.

final class RRCleaningTests: XCTestCase {
    /// 975/1025 avrundade till 1/1024 s: 1025,390625 − 974,609375.
    let växling: Double = 50.78125

    func testRenaSlagBehållsAlla() {
        let natt = NightGenerator.night(NightGenerator.beats(seconds: 1800, seed: 7) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 1000 + 25 * r.gauss()
        })
        let s = RRCleaning.summary(RRCleaning.clean(natt))
        XCTAssertGreaterThan(s.beats, 1700)
        XCTAssertEqual(s.dropped, 0)
        XCTAssertEqual(s.fractionDropped, 0)
        // METOD M15: klockan av intervall håller, ingen omläggning, ett avsnitt.
        XCTAssertEqual(s.reanchorings, 0)
        XCTAssertEqual(s.segments, 1)
        XCTAssertGreaterThan(s.notifications, 1700)
    }

    func testArtefakterRensasOchIngenSkillnadRäknasÖverDem() {
        // Fem påhittade artefakter i en växlande serie: två utanför 300–2000 ms
        // och tre som avviker mer än 20 % från grannarna.
        var slag = NightGenerator.alternating(seconds: 1800)
        for (i, v) in [(100, 250.0), (200, 2600.0), (300, 700.0), (400, 1300.0), (500, 1500.0)] {
            slag[i] = v
        }
        let beats = RRCleaning.clean(NightGenerator.night(slag))
        let s = RRCleaning.summary(beats)
        XCTAssertEqual(s.beats, 1799)
        XCTAssertEqual(s.outOfRange, 2)
        XCTAssertEqual(s.deviating, 3)
        // METOD M15: varför — 250 för kort, 2600 för långt, 700 under och
        // 1300, 1500 över medianen.
        XCTAssertEqual([s.outOfRangeShort, s.outOfRangeLong, s.deviatingShort, s.deviatingLong], [1, 1, 1, 2])
        XCTAssertEqual(s.share(s.deviatingLong), 2.0 / 1799.0, accuracy: 1e-12)
        XCTAssertEqual(s.fractionDropped, 5.0 / 1799.0, accuracy: 1e-12)

        // Varje kastat slag tar bort två skillnader. En skillnad över ett kastat
        // slag skulle vara 0 här (samma fas i växlingen) och synas direkt.
        let d = RRCleaning.differences(beats)
        XCTAssertEqual(d.count, 1798 - 10)
        XCTAssertTrue(d.allSatisfy { abs(abs($0.milliseconds) - växling) < 1e-9 })
    }

    func testTjugoProcentFrånGrannarnasMedian() {
        // Slagets egen median är grannarnas, 5 före och 5 efter: 1000 ms.
        var rr = [Double](repeating: 1000, count: 60)
        rr[10] = 1201
        rr[20] = 1199
        rr[30] = 799
        rr[40] = 801
        let b = RRCleaning.clean(NightGenerator.oneBeatPerSecond(rr))
        XCTAssertEqual(b[10].verdict, .deviatesFromMedian)
        XCTAssertEqual(b[20].verdict, .kept)
        XCTAssertEqual(b[30].verdict, .deviatesFromMedian)
        XCTAssertEqual(b[40].verdict, .kept)
    }

    func testTvåExtraslagIRadKastasBåda() {
        // Slaget självt ingår inte i sin median, så grannen som också är ett
        // extraslag drar inte upp den.
        var rr = [Double](repeating: 1000, count: 40)
        rr[20] = 650
        rr[21] = 1350
        let b = RRCleaning.clean(NightGenerator.oneBeatPerSecond(rr))
        XCTAssertEqual(b[20].verdict, .deviatesFromMedian)
        XCTAssertEqual(b[21].verdict, .deviatesFromMedian)
        XCTAssertEqual(RRCleaning.summary(b).dropped, 2)
    }

    func testGlappBryterSkillnaderna() {
        let t = Date(timeIntervalSince1970: NightGenerator.t0)
        let n = NightRecording(samples: [
            HeartRateSample(time: t, bpm: 60, rrMilliseconds: [1000, 1010]),
            HeartRateSample(time: t.addingTimeInterval(120), bpm: 50, rrMilliseconds: [1200, 1190]),
        ])
        let b = RRCleaning.clean(n)
        XCTAssertEqual(b.map(\.segment), [0, 0, 1, 1])
        let s = RRCleaning.summary(b)
        XCTAssertEqual(s.segments, 2)
        XCTAssertEqual(s.notifications, 2)
        XCTAssertEqual(s.reanchorings, 0, "ett nytt avsnitt är ingen omläggning")
        XCTAssertEqual(RRCleaning.differences(b).map(\.milliseconds), [10, -10])
    }

    func testSlagensTidFöljerIntervallen() throws {
        let natt = NightGenerator.night(NightGenerator.alternating(seconds: 600))
        let b = RRCleaning.clean(natt)
        for i in b.indices.dropFirst() {
            XCTAssertEqual(b[i].time - b[i - 1].time, b[i].rrMilliseconds / 1000, accuracy: 1e-6)
        }
        let sista = try XCTUnwrap(natt.end).timeIntervalSince1970
        XCTAssertLessThanOrEqual(abs(try XCTUnwrap(b.last).time - sista), 1)
    }

    func testKlockanLäggsOmNärSlagTappas() throws {
        // Var hundrade notis kommer utan sina slag: utan omläggning skulle
        // klockan halka över en halv minut efter på en timme.
        let hel = NightGenerator.notifications(NightGenerator.beats(seconds: 3600, seed: 7) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 1000 + 25 * r.gauss()
        })
        var samples: [HeartRateSample] = []
        for (i, s) in hel.enumerated() {
            var c = s
            if i % 100 == 50 { c.rrMilliseconds = [] }
            samples.append(c)
        }
        let b = RRCleaning.clean(NightRecording(samples: samples))
        let sista = try XCTUnwrap(samples.last).time.timeIntervalSince1970
        XCTAssertLessThanOrEqual(abs(try XCTUnwrap(b.last).time - sista), RRCleaning.reanchorSeconds)

        // METOD M15: några få omläggningar, och de kastar inget slag.
        let s = RRCleaning.summary(b)
        XCTAssertGreaterThan(s.reanchorings, 0)
        XCTAssertLessThan(s.fractionReanchored, 0.02)
        XCTAssertEqual(s.dropped, 0)
    }

    func testUpprepadeSlagLäggsOmOftaMenKastasInte() {
        // METOD M15: bandet upprepar förra notisens sista slag. Klockan av
        // intervall springer före med ett slag per notis och läggs om ungefär
        // var fjärde notis. Rensningen ser inget fel: värdena är rimliga.
        let natt = NightGenerator.overlapping(NightGenerator.night(NightGenerator.beats(seconds: 3600, seed: 7) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 1000 + 25 * r.gauss()
        }))
        let s = RRCleaning.summary(RRCleaning.clean(natt))
        XCTAssertGreaterThan(s.fractionReanchored, 0.15)
        XCTAssertLessThan(s.fractionReanchored, 0.4)
        XCTAssertEqual(s.dropped, 0)
        XCTAssertEqual(s.segments, 1)
    }
}
