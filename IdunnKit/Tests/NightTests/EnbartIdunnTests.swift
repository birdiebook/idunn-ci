import Foundation
import XCTest
@testable import Night

// Påhittade nätter, bara tal. PLAN.md W1, BESLUT B40, METOD M33: vardagens vyer
// räknar bara ur Idunns egna nätter.

final class EnbartIdunnTests: XCTestCase {
    let idag = WakeDay(daysSince1970: 20_000)

    /// Så många nätter bakåt från idag, med HRV som växlar mellan två värden.
    func hrv(nätter: Int, slut: Int = 0) -> [WakeDay: Double] {
        var ut: [WakeDay: Double] = [:]
        for k in 0..<nätter { ut[idag - (k + slut)] = k % 2 == 0 ? 70 : 50 }
        return ut
    }

    // MARK: Baslinjen byggs — METOD M33

    func testBaslinjensNätterRäknasFöreMorgonenHögst28() {
        let x = hrv(nätter: 35)
        XCTAssertEqual(Baseline.baselineNights(before: idag, value: { x[$0] }), 28)
        // Dag 0 är morgonen själv och räknas inte (METOD M7, BESLUT B69: nätterna före morgonen).
        let ny = hrv(nätter: 7)
        XCTAssertEqual(Baseline.baselineNights(before: idag, value: { ny[$0] }), 6)
        let sjutton = hrv(nätter: 17)
        XCTAssertEqual(Baseline.baselineNights(before: idag, value: { sjutton[$0] }), 16)
        // Äldre än dag 34 räknas inte.
        let gammal = hrv(nätter: 5, slut: 40)
        XCTAssertEqual(Baseline.baselineNights(before: idag, value: { gammal[$0] }), 0)
    }

    func testKortetSägerHurLångtBaslinjenKommitTillsOmrådetFinns() throws {
        // Sex nätter före morgonen (sju med morgonens egen): ännu inget område (METOD M7, BESLUT B69).
        let kort = MorningCard.day(idag, idun: [.hrv: hrv(nätter: 7)])
        let r = try XCTUnwrap(kort.rows.first)
        XCTAssertNil(r.range, "färre än sju nätter före morgonen")
        XCTAssertNil(r.status, "läget först när området finns")
        XCTAssertEqual(kort.baselineBuilding, 6)
        XCTAssertEqual(r.value, 70, "värdet visas ändå, utan band")
    }

    func testBandetFinnsEfterSjuNätterOchMärksSomUnderByggande() throws {
        let kort = MorningCard.day(idag, idun: [.hrv: hrv(nätter: 8)])
        let r = try XCTUnwrap(kort.rows.first)
        XCTAssertNotNil(r.range)
        XCTAssertTrue(r.rangeBuilding)
        XCTAssertNil(kort.baselineBuilding, "byggraden bara medan färre än sju nätter finns")
        // Med 17 nätter finns bandet också, fortfarande under byggande.
        let sjutton = try XCTUnwrap(MorningCard.day(idag, idun: [.hrv: hrv(nätter: 17)]).rows.first)
        XCTAssertNotNil(sjutton.range)
        XCTAssertTrue(sjutton.rangeBuilding)
        // Fyra fulla veckor: bandet är inte längre märkt.
        let full = try XCTUnwrap(MorningCard.day(idag, idun: [.hrv: hrv(nätter: 35)]).rows.first)
        XCTAssertFalse(full.rangeBuilding)
    }

    func testIngenByggradNärOmrådetFinns() throws {
        let kort = MorningCard.day(idag, idun: [.hrv: hrv(nätter: 35)])
        let r = try XCTUnwrap(kort.rows.first)
        XCTAssertNotNil(r.range)
        XCTAssertNotNil(r.status)
        XCTAssertNil(kort.baselineBuilding)
        XCTAssertEqual(r.baselineNights, 28)
        XCTAssertFalse(r.rangeBuilding)
    }

    func testByggradenFöljerHRVOchFallerTillbakaPåEttMåttMedOmråde() {
        // Utan HRV styr vilopulsen; ett mått utan område (sömn) styr aldrig.
        let utanHRV = MorningCard.day(idag, idun: [.restingHeartRate: hrv(nätter: 5), .sleep: hrv(nätter: 35)])
        XCTAssertEqual(utanHRV.baselineBuilding, 4)
        let barasSömn = MorningCard.day(idag, idun: [.sleep: hrv(nätter: 12)])
        XCTAssertNil(barasSömn.baselineBuilding)
        XCTAssertNil(MorningCard.day(idag, idun: [:]).baselineBuilding)
    }

    func testHudtempOmrådetByggsBaraAvIdunnsNätter() throws {
        // Idunn har fyra nätter. Vardagens kort tar ingen Whoop-historik, så
        // området finns inte, och ingen rad bär märket för Whoops nätter.
        let kort = MorningCard.day(idag, idun: [.skinTemperature: [
            idag: 33.5, idag - 1: 33.3, idag - 2: 33.7, idag - 3: 33.4,
        ]])
        let r = try XCTUnwrap(kort.rows.first)
        XCTAssertEqual(r.source, .idun)
        XCTAssertNil(r.range)
        XCTAssertFalse(r.usesWhoopHistory)
        XCTAssertTrue(kort.rows.allSatisfy { $0.source == .idun })
    }

    // MARK: En tidigare morgon — svepet

    func testEnTidigareMorgonVisarDenNattensVärdenOchIngenSenare() throws {
        let x = hrv(nätter: 40)
        let igår = MorningCard.day(idag - 1, idun: [.hrv: x])
        let r = try XCTUnwrap(igår.rows.first)
        XCTAssertEqual(r.day, idag - 1)
        XCTAssertEqual(r.value, try XCTUnwrap(x[idag - 1]))
        // Området gäller den morgonen: samma som Baseline räknar för dagen.
        let nätter = x.map { NightPoint(day: $0.key, rmssd: $0.value, restingHeartRate: nil, source: .idun) }
        let område = try XCTUnwrap(Baseline.morning(idag - 1, nights: nätter).range)
        XCTAssertEqual(try XCTUnwrap(r.range).lowerBound, exp(område.lower), accuracy: 1e-9)
        XCTAssertEqual(MorningCard.night(igår.rows), idag - 1)
    }

    func testMorgnarnaÄrDagarMedNattÄldstFörstOchEnLuckaFårDenFörraNattensRad() throws {
        var x = hrv(nätter: 5)
        x[idag - 2] = nil // ingen HRV den natten
        let dagar = MorningCard.days(idun: [.hrv: x, .restingHeartRate: [idag - 2: 49]])
        XCTAssertEqual(dagar.map(\.day), [idag - 4, idag - 3, idag - 2, idag - 1, idag])
        // Natten utan HRV har ändå en vilopuls; HRV-raden är den förra nattens, med eget datum.
        let lucka = try XCTUnwrap(dagar.first { $0.day == idag - 2 })
        XCTAssertEqual(lucka.rows.first { $0.measure == .restingHeartRate }?.day, idag - 2)
        XCTAssertEqual(lucka.rows.first { $0.measure == .hrv }?.day, idag - 3)
        XCTAssertTrue(MorningCard.days(idun: [:]).isEmpty)
        XCTAssertTrue(MorningCard.days(idun: [.hrv: [idag: 0]]).isEmpty, "ett värde utan ln är ingen natt")
    }

    // MARK: Regelbundenheten ur Idunns sömnperioder — METOD M33

    /// En natt ur K18: insomning kl 01:00 och uppvaknande kl 07:00 väggklocka,
    /// så att varje natt ligger inom sin egen kalenderdag. `ändrad` skjuter
    /// insomningen så många minuter.
    func natt(_ dag: WakeDay, sömnMinuter: Double = 360, källa: NightSource = .k18,
              ändrad: Int = 0, zon: Int = 7200) -> Trends.IdunNight {
        let midnatt: Double = Double(dag.daysSince1970) * 86_400 - Double(zon)
        let insomning = Date(timeIntervalSince1970: midnatt + 3_600 + Double(ändrad) * 60)
        let vaken = Date(timeIntervalSince1970: midnatt + 7 * 3_600)
        return Trends.IdunNight(
            day: dag, validWindows: 60, rmssd: 55, restingHeartRate: 50, breathsPerMinute: 14,
            sleepHours: sömnMinuter / 60,
            sleepEpisode: Trends.sleepEpisode(source: källa, start: insomning, end: vaken,
                                              utcOffsetSeconds: zon, sleepMinutes: sömnMinuter),
            source: källa, id: "n\(dag.daysSince1970)")
    }

    func testLikadanätterUtanVakenTidGer100() throws {
        let nätter = (0..<9).map { natt(idag - $0) }
        let sri = try XCTUnwrap(Trends.idunValues(nätter)[.regularity]?[idag])
        XCTAssertEqual(sri, 100, accuracy: 1e-9)
    }

    func testVakenTidSpridsÖverPassetSomFörWhoopsPass() throws {
        // 324 av 360 minuter sömn: p = 0,9. Väntat antal olika minuter per
        // dygnspar är 360 · 2 · 0,9 · 0,1 = 64,8 av 1 440 (METOD M17, BESLUT B21).
        let nätter = (0..<9).map { natt(idag - $0, sömnMinuter: 324) }
        let sri = try XCTUnwrap(Trends.idunValues(nätter)[.regularity]?[idag])
        XCTAssertEqual(sri, -100 + 200 * (1 - 64.8 / 1440), accuracy: 1e-9)
        // Samma tal som passen ger direkt: samma Episode, samma räkning.
        let pass = nätter.compactMap(\.sleepEpisode)
        XCTAssertEqual(try XCTUnwrap(Regularity.rolling(pass)[idag]), sri, accuracy: 1e-12)
    }

    func testEttGlappIK18ÄrOkändTidInteVakenTid() throws {
        // 324 minuter sömn av 360, men K18 hördes bara 90 % av perioden (324 av
        // 324 hörda minuter sov): glappet är okänt, så passet räknas som helt
        // sömn och likadana nätter ger 100, inte 91.
        let nätter = (0..<9).map { (k: Int) -> Trends.IdunNight in
            var n = natt(idag - k, sömnMinuter: 324)
            n.sleepEpisode = Trends.sleepEpisode(source: .k18, start: n.sleepEpisode?.onset,
                                                 end: n.sleepEpisode?.wake, utcOffsetSeconds: 7200,
                                                 sleepMinutes: 324, coverage: 0.9)
            return n
        }
        let sri = try XCTUnwrap(Trends.idunValues(nätter)[.regularity]?[idag])
        XCTAssertEqual(sri, 100, accuracy: 1e-9)
        // Utan uppgift om täckning gäller hela perioden som hörd.
        let utan = try XCTUnwrap(Regularity.Episode.idun(onset: Date(timeIntervalSince1970: 0),
                                                         wake: Date(timeIntervalSince1970: 36_000),
                                                         utcOffsetSeconds: 0, sleepMinutes: 450))
        XCTAssertEqual(utan.asleepMinutes, 450)
        XCTAssertEqual(utan.inBedMinutes, 600)
        // Mer sömn än hörd tid är omöjligt men kapas: aldrig över hela passet.
        let kapad = try XCTUnwrap(Regularity.Episode.idun(onset: Date(timeIntervalSince1970: 0),
                                                          wake: Date(timeIntervalSince1970: 36_000),
                                                          utcOffsetSeconds: 0, sleepMinutes: 590, coverage: 0.5))
        XCTAssertEqual(kapad.asleepMinutes, 600)
    }

    func testEnNattSomFlyttasEnTimmeSänkerIndexetViaDeTvåDygnsparenOmkringDen() throws {
        // Natten idag−3 somnar 60 minuter senare: två dygnspar får 60 olika minuter.
        var nätter = (0..<9).map { natt(idag - $0) }
        nätter[3] = natt(idag - 3, sömnMinuter: 300, ändrad: 60)
        let sri = try XCTUnwrap(Trends.idunValues(nätter)[.regularity]?[idag])
        // Veckan idag−6…idag har sex dygnspar.
        XCTAssertEqual(sri, -100 + 200 * (1 - 120.0 / (6 * 1440)), accuracy: 1e-9)
    }

    func testEnGammalInspelningHarIngenSömnperiodOchGerIngenRegelbundenhet() {
        let gamla = (0..<9).map { natt(idag - $0, källa: .notification) }
        XCTAssertTrue(gamla.allSatisfy { $0.sleepEpisode == nil })
        XCTAssertEqual(Trends.idunValues(gamla)[.regularity], [:])
    }

    func testEnVeckaUtanTillräckligaParGerIngetIndex() {
        // Fem nätter i följd ger fyra dygnspar; veckan kräver fem (METOD M17).
        let fem = (0..<5).map { natt(idag - $0) }
        XCTAssertEqual(Trends.idunValues(fem)[.regularity], [:])
        // Sex nätter ger fem par: indexet finns, för den sista dagen.
        let sex = (0..<6).map { natt(idag - $0) }
        XCTAssertEqual(Trends.idunValues(sex)[.regularity]?.count, 1)
    }

    func testEnPeriodUtanLängdGerIngetPass() {
        let a = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(Regularity.Episode.idun(onset: a, wake: a, utcOffsetSeconds: 0, sleepMinutes: 0))
        XCTAssertNil(Regularity.Episode.idun(onset: a, wake: a.addingTimeInterval(-60), utcOffsetSeconds: 0,
                                             sleepMinutes: 10))
        XCTAssertNotNil(Regularity.Episode.idun(onset: a, wake: a.addingTimeInterval(3_600), utcOffsetSeconds: 0,
                                                sleepMinutes: 55))
    }

    func testRegelbundenhetenKommerPåKortetOchIÖverTidUtanWhoop() throws {
        let nätter = (0..<40).map { natt(idag - $0) }
        let värden = Trends.idunValues(nätter)
        let kort = MorningCard.day(idag, idun: värden)
        let rad = try XCTUnwrap(kort.rows.first { $0.measure == .regularity })
        XCTAssertEqual(rad.source, .idun)
        XCTAssertEqual(rad.value, 100, accuracy: 1e-9)
        // Över tid: serien finns, bara med Idunn.
        let serie = Trends.series(.regularity, idun: värden[.regularity] ?? [:], whoop: [:])
        XCTAssertEqual(serie.sources, [.idun])
        XCTAssertFalse(serie.rolling.isEmpty)
        XCTAssertTrue(serie.points.allSatisfy { $0.source == .idun })
    }

    func testHelaKortetVidFyraVeckorUtanWhoopHarAllaMåttOchIngetWhoopMärke() throws {
        let nätter = (0..<40).map { natt(idag - $0) }
        let dagar = MorningCard.days(idun: Trends.idunValues(nätter))
        XCTAssertEqual(dagar.count, 40)
        let senaste = try XCTUnwrap(dagar.last)
        XCTAssertEqual(senaste.day, idag)
        XCTAssertEqual(Set(senaste.rows.map(\.measure)), [.hrv, .restingHeartRate, .breathing, .sleep, .regularity])
        XCTAssertTrue(senaste.rows.allSatisfy { $0.source == .idun && !$0.usesWhoopHistory })
        XCTAssertNil(senaste.baselineBuilding)
        // Den första morgonen har ingen baslinje: kortet säger hur långt den kommit.
        let första = try XCTUnwrap(dagar.first)
        XCTAssertEqual(första.baselineBuilding, 0)
    }
}
