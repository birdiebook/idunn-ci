import Foundation
import XCTest
import Night
@testable import SleepNeed

// Alla nätter nedan är påhittade (CLAUDE.md §Dataregeln). BESLUT B71, METOD M56.
// Pariteten: samma fall och samma tal som tools/tests/test_somnpoang.py (klasserna Delarna, Formeln och
// ParitetMedSwift). Ändras ett fall där ändras det här.

final class SleepScoreTests: XCTestCase {
    /// Ett pass med tider i minuter från uppvakningsdagens midnatt i zonen `zon` (som `pas` i test_somnpoang.py).
    private func pass(_ dag: Int, _ på: Double, _ av: Double, _ sov: Int, zon: Int = 0) -> Regularity.Episode {
        let midnatt = Double(dag) * 86_400 - Double(zon)
        return Regularity.Episode(onset: Date(timeIntervalSince1970: midnatt + på * 60),
                                  wake: Date(timeIntervalSince1970: midnatt + av * 60), utcOffsetSeconds: zon,
                                  isNap: false, asleepMinutes: sov, inBedMinutes: Int(av - på))
    }

    private func natt(_ pass: [Regularity.Episode], _ dag: Int, k: Int = Regularity.nightComparisons) -> Double? {
        Regularity.nightIndex(pass, day: WakeDay(daysSince1970: dag), nights: k)
    }

    // MARK: Delarna och formeln

    func testDelpoängenGer85Och70VidGränserna() {
        XCTAssertEqual(SleepScoring.part(85, good: 85, poor: 75), 85, accuracy: 1e-9)
        XCTAssertEqual(SleepScoring.part(75, good: 85, poor: 75), 70, accuracy: 1e-9)
        XCTAssertEqual(SleepScoring.part(95, good: 85, poor: 75), 100, accuracy: 1e-9)
        XCTAssertEqual(SleepScoring.part(100, good: 85, poor: 75), 100, accuracy: 1e-9)
        XCTAssertEqual(SleepScoring.part(10, good: 85, poor: 75), 0, accuracy: 1e-9)
        XCTAssertEqual(SleepScoring.part(81, good: SleepScoreRules.regularityGood, poor: SleepScoreRules.regularityPoor),
                       85, accuracy: 1e-9)
    }

    func testMängdenMotBehovetHarTak() throws {
        XCTAssertEqual(try XCTUnwrap(SleepScoring.amount(asleepMinutes: 420, needMinutes: 480)), 87.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(SleepScoring.amount(asleepMinutes: 540, needMinutes: 480)), 100, accuracy: 1e-9)
        XCTAssertNil(SleepScoring.amount(asleepMinutes: 420, needMinutes: 0))
    }

    func testPoängenÄrMedletAvDelarnaSomFinns() throws {
        let a = try XCTUnwrap(SleepScoring.score(asleepMinutes: 420, needMinutes: 480, efficiency: 85, regularity: 71.6))
        XCTAssertEqual(a.score, 80, accuracy: 1e-9)
        XCTAssertEqual(a.amount, 85, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a.continuity), 85, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a.regularity), 70, accuracy: 1e-9)

        // Första natten: ingen regelbundenhet, medlet av mängd och kontinuitet (BESLUT B65).
        let b = try XCTUnwrap(SleepScoring.score(asleepMinutes: 400, needMinutes: 470, efficiency: 90, regularity: nil))
        XCTAssertEqual(b.score, 87.31382978723404, accuracy: 1e-9)
        XCTAssertEqual(b.amount, 82.12765957446808, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.continuity), 92.5, accuracy: 1e-9)
        XCTAssertNil(b.regularity)

        let c = try XCTUnwrap(SleepScoring.score(asleepMinutes: 500, needMinutes: 480, efficiency: nil, regularity: 90))
        XCTAssertEqual(c.score, 99.68085106382978, accuracy: 1e-9)
        XCTAssertEqual(c.amount, 100, accuracy: 1e-9)
        XCTAssertNil(c.continuity)
        XCTAssertEqual(try XCTUnwrap(c.regularity), 99.36170212765957, accuracy: 1e-9)

        let d = try XCTUnwrap(SleepScoring.score(asleepMinutes: 300, needMinutes: 480, efficiency: 70, regularity: 60))
        XCTAssertEqual(d.score, 56.329787234042556, accuracy: 1e-9)
        XCTAssertEqual(d.amount, 55, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.continuity), 62.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.regularity), 51.48936170212768, accuracy: 1e-9)

        XCTAssertNil(SleepScoring.score(asleepMinutes: 420, needMinutes: 0, efficiency: 85, regularity: 80),
                     "utan behov ingen mängd och ingen poäng")
    }

    // MARK: Nattens regelbundenhet (METOD M56)

    func testLikadanaNätterGer100() throws {
        let lika: [Regularity.Episode] = (20_000...20_007).map { pass($0, -60, 420, 480) }
        XCTAssertEqual(try XCTUnwrap(natt(lika, 20_007)), 100, accuracy: 1e-9)
    }

    func testEnTimmeFörskjutenMotNattenFöre() throws {
        // Två nätter om 480 min utan vaken tid, en timme isär: 120 olika minuter av 1440.
        let p = [pass(20_000, -60, 420, 480), pass(20_001, 0, 480, 480)]
        XCTAssertEqual(try XCTUnwrap(natt(p, 20_001, k: 1)), -100 + 200 * (1320.0 / 1440), accuracy: 1e-9)
    }

    func testVakenTidenSprids() throws {
        // Lika pass med andelen sömn q: olika med sannolikheten 2q(1 − q) per minut i passet (M17).
        let p = [pass(20_000, -60, 420, 360), pass(20_001, -60, 420, 360)]
        let q = 360.0 / 480
        XCTAssertEqual(try XCTUnwrap(natt(p, 20_001, k: 1)), -100 + 200 * (1 - 480 * 2 * q * (1 - q) / 1440),
                       accuracy: 1e-9)
    }

    func testKräverEnNattFöre() {
        XCTAssertNil(natt([pass(20_000, -60, 420, 480)], 20_000))
        XCTAssertNil(natt([pass(20_000, -60, 420, 480)], 20_001), "natten själv saknas")
    }

    func testMedletÖverDeFyraFöre() throws {
        var p: [Regularity.Episode] = (0..<4).map { pass(20_000 + $0, -60, 420, 480) }
        p.append(pass(20_004, 0, 480, 480))
        let en = -100 + 200 * (1320.0 / 1440)
        XCTAssertEqual(try XCTUnwrap(natt(p, 20_004)), en, accuracy: 1e-9)
        p[3] = pass(20_003, 0, 480, 480)
        XCTAssertEqual(try XCTUnwrap(natt(p, 20_004)), (100 + 3 * en) / 4, accuracy: 1e-9)
    }

    func testOlikaNätterIEnZon() throws {
        // Samma väggklocka som fallet `test_olika_natter` i test_somnpoang.py, i zonen UTC+01:00.
        let p = [pass(20_000, -90, 400, 430, zon: 3600), pass(20_001, -30, 450, 400, zon: 3600),
                 pass(20_002, -60, 420, 450, zon: 3600), pass(20_003, -45, 435, 470, zon: 3600)]
        XCTAssertEqual(try XCTUnwrap(natt(p, 20_003)), 85.52380804752454, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(natt(p, 20_003, k: 1)), 90.79318576388889, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(natt(p, 20_001)), 72.07105064247921, accuracy: 1e-9)
        let alla = Regularity.nightly(p)
        XCTAssertEqual(alla.keys.map(\.daysSince1970).sorted(), [20_001, 20_002, 20_003])
        XCTAssertEqual(try XCTUnwrap(alla[WakeDay(daysSince1970: 20_003)]), 85.52380804752454, accuracy: 1e-9)
    }

    // MARK: Dag för dag ur Idunns nätter (bara Swift)

    func testDagFörDagUrIdunsNätter() throws {
        let zon = 3600
        // Fem nätter ur K18 med olika sovtid och insomning; dag 20 005 är en gammal inspelning som inte räknas.
        let sov: [Double] = [430, 400, 470, 380, 450]
        let på: [Double] = [-60, -30, -90, -60, 0]
        var idun: [Trends.IdunNight] = []
        for i in 0..<5 {
            let dag = 20_000 + i
            let midnatt = Double(dag) * 86_400 - Double(zon)
            let av = på[i] + 480
            let period = try XCTUnwrap(Regularity.Episode.idun(onset: Date(timeIntervalSince1970: midnatt + på[i] * 60),
                                                             wake: Date(timeIntervalSince1970: midnatt + av * 60),
                                                             utcOffsetSeconds: zon, sleepMinutes: sov[i]))
            idun.append(Trends.IdunNight(day: WakeDay(daysSince1970: dag), validWindows: 80, rmssd: 50,
                                         restingHeartRate: 50, breathsPerMinute: 14, sleepHours: sov[i] / 60,
                                         sleepEpisode: period, source: .k18, efficiency: 100 * sov[i] / 480,
                                         onsetMinutes: på[i], wakeMinutes: av))
        }
        idun.append(Trends.IdunNight(day: WakeDay(daysSince1970: 20_005), validWindows: 80, rmssd: 50,
                                     restingHeartRate: 50, breathsPerMinute: 14, sleepHours: 7,
                                     source: .notification))
        let behov = SleepNeed.days(nights: SleepNeed.nights(idun), passes: [])
        let poäng = SleepScoring.days(idun, need: behov)
        XCTAssertEqual(poäng.keys.sorted(), Array(20_000...20_004))
        let pass: [Regularity.Episode] = idun.compactMap(\.sleepEpisode)
        for d in behov {
            let s = try XCTUnwrap(poäng[d.day])
            let sovit: Double = try XCTUnwrap(d.sleptMinutes)
            let väntad = try XCTUnwrap(SleepScoring.score(asleepMinutes: sovit, needMinutes: d.needMinutes,
                                                          efficiency: 100 * sovit / 480,
                                                          regularity: natt(pass, d.day)))
            XCTAssertEqual(s.score, väntad.score, accuracy: 1e-9, "dag \(d.day)")
        }
        XCTAssertNil(try XCTUnwrap(poäng[20_000]).regularity, "första natten utan regelbundenhet")
        XCTAssertNotNil(try XCTUnwrap(poäng[20_001]).regularity, "från andra natten mot en natt")
    }
}
