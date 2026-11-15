import Foundation
import XCTest
import HeartRate
@testable import Night

// Nätterna är påhittade (NightGenerator.swift). METOD M4, M5.

final class NightAnalysisTests: XCTestCase {
    let växling: Double = 50.78125

    func testVäxlandeSerieGerKändRMSSD() throws {
        let r = NightAnalysis.analyze(NightGenerator.night(NightGenerator.alternating(seconds: 1800)))
        XCTAssertEqual(r.windows.count, 6)
        XCTAssertEqual(r.validWindows, 6)
        for w in r.windows {
            XCTAssertEqual(try XCTUnwrap(w.rmssd), växling, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(w.differences, 299)
        }
        XCTAssertEqual(try XCTUnwrap(r.rmssd.mean), växling, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.median), växling, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.lateQuiet), växling, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.whoopLike), växling, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.ln(.median)), log(växling), accuracy: 1e-12)
        // 975 och 1025 i medel: 1000 ms, 60 slag per minut (udda antal slag
        // i ett fönster flyttar medlet en tiondels millisekund).
        XCTAssertEqual(try XCTUnwrap(r.restingHeartRate), 60, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.meanHeartRate), 60, accuracy: 0.01, "BESLUT B34: medelpulsen")
        XCTAssertEqual(r.cleaning.dropped, 0)
    }

    func testOberoendeSlagGerRMSSDRotenUrTvåGångerSpridningen() throws {
        // Oberoende slag med spridning 25 ms: varje skillnad har spridning 25·√2.
        let natt = NightGenerator.night(NightGenerator.beats(seconds: 3600, seed: 7) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 1000 + 25 * r.gauss()
        })
        let r = NightAnalysis.analyze(natt)
        let väntat: Double = 25 * 2.0.squareRoot()
        XCTAssertEqual(r.validWindows, 12)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.mean), väntat, accuracy: 2.5)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.median), väntat, accuracy: 2.5)
    }

    func testKandidaternaSkiljerNärNattenSkiftar() throws {
        // Två timmar på 900 ms (RMSSD 30), en timme på 1000 ms (RMSSD 40) och
        // däri 20 lugna minuter på 1200 ms (RMSSD 80, puls 50).
        let slag = NightGenerator.beats(seconds: 10_800) { (i: Int, t: Double, _: inout Seeded) -> Double in
            var bas: Double = 1000
            var a: Double = 20
            if t < 7200 {
                bas = 900
                a = 15
            } else if t >= 9000 && t < 10_200 {
                bas = 1200
                a = 40
            }
            return i % 2 == 0 ? bas - a : bas + a
        }
        let r = NightAnalysis.analyze(NightGenerator.night(slag))
        XCTAssertEqual(r.windows.count, 36)
        XCTAssertEqual(r.validWindows, 36)
        // Facit ur Python-spegeln: 37,83 · 30,27 · 80,08, och 37,97 för de glidande
        // fönstren. Vilopulsen (METOD M5, BESLUT B76) är 10:e percentilen av 36 fönster
        // (4 på 50, 8 på 60, 24 på 66,7): mitt mellan det fjärde och femte, 54,99.
        XCTAssertEqual(try XCTUnwrap(r.rmssd.mean), 37.83, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.median), 30.27, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.lateQuiet), 80.08, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.whoopLike), 37.97, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.restingHeartRate), 55, accuracy: 0.05)
        XCTAssertEqual(r.rmssd.value(.lateQuiet), r.rmssd.lateQuiet)
        XCTAssertEqual(r.rmssd.value(.whoopLike), r.rmssd.whoopLike)
    }

    func testWhoopLikaFönstrenGliderÖverSkiftet() throws {
        // En halvtimme kring 1000 ms: första kvarten ±20 ms, andra ±40 ms.
        // Skillnaderna efter avrundningen till 1/1024 s är 39,06 och 80,08 ms.
        // Facit ur Python-spegeln: 6 vanliga fönster ger medlet 59,5846; 50
        // glidande fönster (steg 30 s) ger 59,6262, eftersom de nio som
        // spänner över skiftet blandar kvadraterna.
        let slag = NightGenerator.beats(seconds: 1800) { (i: Int, t: Double, _: inout Seeded) -> Double in
            let a: Double = t < 900 ? 20 : 40
            return i % 2 == 0 ? 1000 - a : 1000 + a
        }
        let r = NightAnalysis.analyze(NightGenerator.night(slag))
        XCTAssertEqual(r.cleaning.dropped, 0)
        XCTAssertEqual(r.validWindows, 6)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.mean), 59.5846, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.whoopLike), 59.6262, accuracy: 1e-4)
        let first: Double = try XCTUnwrap(r.start).timeIntervalSince1970
        let last: Double = try XCTUnwrap(r.end).timeIntervalSince1970
        let diffs = RRCleaning.differences(RRCleaning.clean(NightGenerator.night(slag)))
        let glidande = NightAnalysis.slidingRMSSD(diffs, first: first, last: last)
        XCTAssertEqual(glidande.count, 50)
        XCTAssertEqual(try XCTUnwrap(glidande.first), 39.0625, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(glidande.last), 80.078125, accuracy: 1e-9)
    }

    func testGlidandeFönstrenSomRäknatRakt() throws {
        // Löpande summor och två pekare mot en rak räkning fönster för fönster,
        // på en natt med ett hål utan RR (fönster med för få skillnader).
        let hel = NightGenerator.night(NightGenerator.beats(seconds: 3600, seed: 11) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 950 + 30 * r.gauss()
        })
        let natt = NightGenerator.withoutRR(hel, from: 1000, to: 1300)
        let diffs = RRCleaning.differences(RRCleaning.clean(natt))
        let r = NightAnalysis.analyze(natt)
        let first: Double = try XCTUnwrap(r.start).timeIntervalSince1970
        let last: Double = try XCTUnwrap(r.end).timeIntervalSince1970

        var rakt: [Double] = []
        var start: Double = first
        while start + NightAnalysis.windowSeconds <= last {
            let slut: Double = start + NightAnalysis.windowSeconds
            let inne: [Double] = diffs.filter { $0.time >= start && $0.time < slut }.map(\.milliseconds)
            if inne.count >= NightAnalysis.minDifferencesPerWindow {
                let ss: Double = inne.reduce(0.0) { (a: Double, d: Double) -> Double in a + d * d }
                rakt.append((ss / Double(inne.count)).squareRoot())
            }
            start += NightAnalysis.slidingStepSeconds
        }
        let glidande = NightAnalysis.slidingRMSSD(diffs, first: first, last: last)
        XCTAssertEqual(glidande.count, rakt.count)
        // 110 fönster ryms; runt tio kring hålet har för få skillnader.
        XCTAssertLessThan(glidande.count, 105, "fönstren över hålet räknas inte")
        XCTAssertGreaterThan(glidande.count, 90)
        for (a, b) in zip(glidande, rakt) { XCTAssertEqual(a, b, accuracy: 1e-6) }
        XCTAssertEqual(try XCTUnwrap(r.rmssd.whoopLike), try XCTUnwrap(Statistics.mean(rakt)), accuracy: 1e-6)
    }

    func testKortNattGerEttGlidandeFönster() throws {
        // Kortare än fem minuter: ett fönster, som de vanliga.
        let r = NightAnalysis.analyze(NightGenerator.night(NightGenerator.alternating(seconds: 200)))
        XCTAssertEqual(r.validWindows, 1)
        XCTAssertEqual(try XCTUnwrap(r.rmssd.whoopLike), växling, accuracy: 1e-9)
    }

    func testFönsterMedFörFåSlagRäknasInte() throws {
        // Notiserna kommer men utan RR i drygt fyra minuter av tredje fönstret.
        let hel = NightGenerator.night(NightGenerator.beats(seconds: 3600, seed: 7) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 1000 + 25 * r.gauss()
        })
        let r = NightAnalysis.analyze(NightGenerator.withoutRR(hel, from: 620, to: 880))
        XCTAssertEqual(r.windows.count, 12)
        XCTAssertLessThan(r.windows[2].differences, NightAnalysis.minDifferencesPerWindow)
        XCTAssertNil(r.windows[2].rmssd)
        XCTAssertNil(r.windows[2].meanHeartRate)
        XCTAssertFalse(r.windows[2].isValid)
        XCTAssertEqual(r.validWindows, 11)
    }

    func testBaraTidsintervalletRäknas() throws {
        let natt = NightGenerator.night(NightGenerator.beats(seconds: 3600, seed: 7) {
            (_: Int, _: Double, r: inout Seeded) -> Double in 1000 + 25 * r.gauss()
        })
        let från = Date(timeIntervalSince1970: NightGenerator.t0 + 1800)
        let r = NightAnalysis.analyze(natt, within: DateInterval(start: från, duration: 1800))
        XCTAssertEqual(r.windows.count, 6)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(r.start), från)
        XCTAssertLessThan(r.cleaning.beats, 1900)
    }

    // MARK: Vilopulsen (METOD M5 · BESLUT B76)

    func testVilopulsenÄrTiondePercentilenMedLinjärInterpolation() throws {
        XCTAssertNil(NightAnalysis.restingHeartRate([]))
        XCTAssertEqual(NightAnalysis.restingHeartRate([57]), 57)
        // Två fönster: h = 0,1, en tiondel från det lägsta mot det andra.
        XCTAssertEqual(try XCTUnwrap(NightAnalysis.restingHeartRate([60, 50])), 51, accuracy: 1e-12)
        // Elva fönster: h = 1, det näst lägsta; det enstaka låga fönstret styr inte.
        let elva: [Double] = [58, 41, 52, 53, 54, 55, 56, 57, 59, 60, 61]
        XCTAssertEqual(try XCTUnwrap(NightAnalysis.restingHeartRate(elva)), 52, accuracy: 1e-12)
        // 21 fönster 50...70 i blandad ordning: h = 2, alltså 52.
        let tjugoett: [Double] = (0...20).map { (k: Int) -> Double in Double(50 + (k * 8) % 21) }
        XCTAssertEqual(try XCTUnwrap(NightAnalysis.restingHeartRate(tjugoett)), 52, accuracy: 1e-12)
        // Samma tal som Python-spegeln (`natt_spegel.percentil`) och numpy.percentile(x, 10).
        XCTAssertEqual(try XCTUnwrap(NightAnalysis.restingHeartRate([55.5, 49.25, 61, 50.75, 52])),
                       49.85, accuracy: 1e-12)
        XCTAssertEqual(NightAnalysis.restingPercentile, 0.10)
    }

    func testPlattSerieGerIngenLn() throws {
        let r = NightAnalysis.analyze(NightGenerator.night(NightGenerator.beats(seconds: 900) {
            (_: Int, _: Double, _: inout Seeded) -> Double in 1000
        }))
        XCTAssertEqual(try XCTUnwrap(r.rmssd.mean), 0)
        XCTAssertNil(r.rmssd.ln(.mean), "ln(0) finns inte")
    }

    func testTomNatt() {
        let r = NightAnalysis.analyze(NightRecording())
        XCTAssertTrue(r.windows.isEmpty)
        XCTAssertNil(r.rmssd.mean)
        XCTAssertNil(r.rmssd.whoopLike)
        XCTAssertNil(r.restingHeartRate)
        XCTAssertNil(r.breathsPerMinute)
        XCTAssertNil(r.point(utcOffsetSeconds: 0, candidate: .mean))
    }

    func testNattensPunktFårUppvakningsdagenISinZon() throws {
        let r = NightAnalysis.analyze(NightGenerator.night(NightGenerator.alternating(seconds: 1800)))
        let p = try XCTUnwrap(r.point(utcOffsetSeconds: 7200, candidate: .median))
        let slut = try XCTUnwrap(r.end)
        XCTAssertEqual(p.day, WakeDay(slut, utcOffsetSeconds: 7200))
        XCTAssertEqual(p.source, .idun)
        XCTAssertEqual(try XCTUnwrap(p.lnRMSSD), log(växling), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(p.restingHeartRate), 60, accuracy: 0.01)
        // Förvalet är nattens medel (METOD M4).
        XCTAssertEqual(r.point(utcOffsetSeconds: 7200), r.point(utcOffsetSeconds: 7200, candidate: .mean))
        XCTAssertEqual(NightAnalysis.Candidate.allCases.count, 4)
    }

    // MARK: Medelpulsen över sömnperioden (BESLUT B34)

    func testMedelpulsenÄrAllaBehållnaIntervallIDeGiltigaFönstrenIhop() throws {
        // Två timmar på 900 ms (RMSSD 30), en timme på 1000 ms och 20 lugna minuter på 1200 ms: medelpulsen är
        // 60000 / medel av alla behållna intervall i de giltiga fönstren.
        let slag = NightGenerator.beats(seconds: 10_800) { (i: Int, t: Double, _: inout Seeded) -> Double in
            var bas: Double = 1000
            var a: Double = 20
            if t < 7200 {
                bas = 900
                a = 15
            } else if t >= 9000 && t < 10_200 {
                bas = 1200
                a = 40
            }
            return i % 2 == 0 ? bas - a : bas + a
        }
        let beats = RRCleaning.clean(NightGenerator.night(slag))
        let r = NightAnalysis.analyze(beats: beats)
        XCTAssertEqual(r.validWindows, r.windows.count, "alla fönster är giltiga")
        let behållna: [Double] = beats.filter { $0.isKept }.map { $0.rrMilliseconds }
        var summa: Double = 0
        for x in behållna { summa += x }
        let väntat: Double = 60_000 / (summa / Double(behållna.count))
        XCTAssertEqual(try XCTUnwrap(r.meanHeartRate), väntat, accuracy: 1e-9)
        // Vilopulsen (10:e percentilen av fönstren) ligger här under medlet.
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(r.meanHeartRate), try XCTUnwrap(r.restingHeartRate))
    }

    func testIngenMedelpulsUtanGiltigtFönster() {
        XCTAssertNil(NightAnalysis.analyze(NightRecording()).meanHeartRate)
        // Tio sekunder är inget giltigt fönster.
        let kort = NightGenerator.night(NightGenerator.alternating(seconds: 10))
        let r = NightAnalysis.analyze(kort)
        XCTAssertEqual(r.validWindows, 0)
        XCTAssertNil(r.meanHeartRate)
    }
}
