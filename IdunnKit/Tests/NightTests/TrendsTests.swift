import Foundation
import XCTest
import WhoopImport
@testable import Night

// Påhittade nätter, bara tal. METOD M16.

final class TrendsTests: XCTestCase {
    let idag = WakeDay(daysSince1970: 20_000)

    /// Fem veckor bakåt från idag: varannan natt 70 och varannan 50 ms.
    func växlande(_ hög: Double = 70, _ låg: Double = 50, dagar: Int = 35) -> [WakeDay: Double] {
        var ut: [WakeDay: Double] = [:]
        for k in 0..<dagar { ut[idag - k] = k % 2 == 0 ? hög : låg }
        return ut
    }

    // MARK: 7-dagarsmedlet

    func testMedletKräverTreNätterIVeckan() throws {
        let x: [WakeDay: Double] = [idag - 6: 50, idag - 3: 54, idag: 58]
        let s = Trends.series(.restingHeartRate, idun: x, whoop: [:])
        XCTAssertEqual(s.points.count, 3)
        // Bara sista dagen har tre nätter i sin vecka.
        XCTAssertEqual(s.rolling.map(\.day), [idag])
        XCTAssertEqual(try XCTUnwrap(s.rolling.first).value, 54, accuracy: 1e-12)
        XCTAssertTrue(s.bands.isEmpty, "fyra veckors baslinje saknas")
    }

    func testHRVMedletRäknasIlnOchVisasIms() throws {
        let x: [WakeDay: Double] = [idag - 2: 40, idag - 1: 50, idag: 80]
        let s = Trends.series(.hrv, idun: x, whoop: [:])
        let m = try XCTUnwrap(s.rolling.last)
        let väntat: Double = exp((log(40.0) + log(50.0) + log(80.0)) / 3)
        XCTAssertEqual(m.value, väntat, accuracy: 1e-9)
        XCTAssertEqual(s.points.map(\.value), [40, 50, 80])
    }

    func testLinjenBrytsDärMedletSaknas() throws {
        // Två veckor med nätter, ett glapp på tio dagar, och två veckor till.
        var x: [WakeDay: Double] = [:]
        for k in 0..<14 { x[idag - k] = 50 }
        for k in 24..<38 { x[idag - k] = 52 }
        let s = Trends.series(.restingHeartRate, idun: x, whoop: [:])
        XCTAssertEqual(Set(s.rolling.map(\.segment)), [1, 2])
        // Glappet: dag −19 till −12 har färre än 3 nätter i sin vecka.
        let segment1 = s.rolling.filter { $0.segment == 1 }.map(\.day)
        let segment2 = s.rolling.filter { $0.segment == 2 }.map(\.day)
        XCTAssertLessThan(try XCTUnwrap(segment1.max()), try XCTUnwrap(segment2.min()))
        XCTAssertEqual(segment1.max(), idag - 20)
        XCTAssertEqual(segment2.min(), idag - 11)
        XCTAssertNotEqual(s.rolling.first { $0.segment == 1 }?.line, s.rolling.first { $0.segment == 2 }?.line)
        // Dagarna i varje segment följer på varandra.
        for seg in [segment1, segment2] {
            XCTAssertEqual(seg.last!.daysSince1970 - seg.first!.daysSince1970 + 1, seg.count)
        }
    }

    // MARK: Normalområdet och läget

    func testHRVBandetOchLägetFöljerBaseline() throws {
        let x = växlande()
        let s = Trends.series(.hrv, idun: x, whoop: [:])
        let nätter = x.map { NightPoint(day: $0.key, rmssd: $0.value, restingHeartRate: nil, source: .idun) }
        let morgon = Baseline.morning(idag, nights: nätter)
        let område = try XCTUnwrap(morgon.range)
        let band = try XCTUnwrap(s.bands.last)
        XCTAssertEqual(band.day, idag)
        XCTAssertEqual(band.lower, exp(område.lower), accuracy: 1e-9)
        XCTAssertEqual(band.upper, exp(område.upper), accuracy: 1e-9)
        let senast = try XCTUnwrap(s.rolling.last)
        XCTAssertEqual(log(senast.value), try XCTUnwrap(morgon.rollingLnRMSSD), accuracy: 1e-12)
        XCTAssertEqual(senast.status, morgon.status)
        // Varje dag med område och medel har samma läge som Baseline.morning.
        for r in s.rolling {
            XCTAssertEqual(r.status, Baseline.morning(r.day, nights: nätter).status, "\(r.day)")
        }
    }

    func testLägetUnderOchÖver() throws {
        var x = växlande()
        for k in 0..<7 { x[idag - k] = 30 }
        XCTAssertEqual(Trends.series(.hrv, idun: x, whoop: [:]).latest?.status, .below)
        for k in 0..<7 { x[idag - k] = 120 }
        XCTAssertEqual(Trends.series(.hrv, idun: x, whoop: [:]).latest?.status, .above)
    }

    func testVilopulsenFårBandMenInteLäge() throws {
        let s = Trends.series(.restingHeartRate, idun: växlande(54, 50), whoop: [:])
        let band = try XCTUnwrap(s.bands.last)
        // Aritmetiskt, i slag per minut: medel 52 över baslinjens fyra veckor.
        XCTAssertEqual((band.lower + band.upper) / 2, 52, accuracy: 1e-9)
        XCTAssertTrue(s.rolling.allSatisfy { $0.status == nil })
    }

    func testHudtempFårBandMenInteLäge() throws {
        // METOD M25. Som vilopulsen: normalområde, 7-dagarsmedel, inget läge.
        let s = Trends.series(.skinTemperature, idun: växlande(33.6, 33.2), whoop: [:])
        let band = try XCTUnwrap(s.bands.last)
        XCTAssertEqual((band.lower + band.upper) / 2, 33.4, accuracy: 1e-9)
        XCTAssertTrue(s.rolling.allSatisfy { $0.status == nil })
        XCTAssertFalse(s.rolling.isEmpty)
    }

    func testHudtempIdunnFylldOchWhoopIhåligHållsIsär() throws {
        let s = Trends.series(.skinTemperature, idun: växlande(33.6, 33.2), whoop: växlande(34.4, 34.0))
        XCTAssertEqual(s.sources, [.idun, .whoop])
        let bi = try XCTUnwrap(s.bands.last { $0.source == .idun })
        let bw = try XCTUnwrap(s.bands.last { $0.source == .whoop })
        XCTAssertLessThan(bi.upper, bw.lower, "var sitt område, ur var sina nätter (BESLUT B16)")
    }

    func testNattUnderMinstaTäckningGerIngenPrick() {
        // En natt med temperatur och en utan (K18 täckte för lite).
        let nätter = [
            Trends.IdunNight(day: idag - 1, validWindows: 50, rmssd: 55, restingHeartRate: 50,
                             breathsPerMinute: 14, skinTemperature: 33.4),
            Trends.IdunNight(day: idag, validWindows: 50, rmssd: 56, restingHeartRate: 50,
                             breathsPerMinute: 14, skinTemperature: nil),
        ]
        let v = Trends.idunValues(nätter)
        XCTAssertEqual(v[.skinTemperature], [idag - 1: 33.4])
        XCTAssertEqual(v[.hrv]?.count, 2, "natten finns kvar för de andra måtten")
        let s = Trends.series(.skinTemperature, idun: v[.skinTemperature] ?? [:], whoop: [:])
        XCTAssertEqual(s.points.map(\.day), [idag - 1])
    }

    func testSömnOchAndningFårInget() {
        for m in [Trends.Measure.sleep, .breathing] {
            let s = Trends.series(m, idun: växlande(8, 7), whoop: växlande(8, 7))
            XCTAssertTrue(s.bands.isEmpty, "\(m)")
            XCTAssertTrue(s.rolling.allSatisfy { $0.status == nil }, "\(m)")
            XCTAssertFalse(s.rolling.isEmpty, "\(m)")
        }
    }

    // MARK: Källorna hålls isär

    func testKällornaBlandasInte() throws {
        let s = Trends.series(.hrv, idun: växlande(90, 80), whoop: växlande(50, 40))
        XCTAssertEqual(s.sources, [.idun, .whoop])
        XCTAssertEqual(s.points.count, 70)
        let idun = s.rolling.filter { $0.source == .idun }
        let whoop = s.rolling.filter { $0.source == .whoop }
        XCTAssertTrue(idun.allSatisfy { $0.value > 80 * 0.99 })
        XCTAssertTrue(whoop.allSatisfy { $0.value < 50 * 1.01 })
        XCTAssertTrue(Set(idun.map(\.line)).isDisjoint(with: Set(whoop.map(\.line))))
        // Var sitt normalområde, ur var sina nätter.
        let bi = try XCTUnwrap(s.bands.last { $0.source == .idun })
        let bw = try XCTUnwrap(s.bands.last { $0.source == .whoop })
        XCTAssertGreaterThan(bi.lower, bw.upper)
        // Samma dag: Idunn före Whoop.
        XCTAssertEqual(s.points.prefix(2).map(\.source), [.idun, .whoop])
    }

    func testSenasteGårTillIdunVidLikaDag() throws {
        let s = Trends.series(.restingHeartRate, idun: växlande(60, 58, dagar: 7), whoop: växlande(50, 48, dagar: 7))
        let l = try XCTUnwrap(s.latest)
        XCTAssertEqual(l.day, idag)
        XCTAssertEqual(l.source, .idun)
        // Whoop en dag senare vinner.
        var w = växlande(50, 48, dagar: 7)
        w[idag + 1] = 49
        XCTAssertEqual(Trends.series(.restingHeartRate, idun: växlande(60, 58, dagar: 7), whoop: w).latest?.source, .whoop)
    }

    func testOgiltigaVärdenHoppasÖver() {
        let x: [WakeDay: Double] = [idag - 2: 0, idag - 1: -3, idag: .nan, idag - 3: 45]
        XCTAssertEqual(Trends.series(.hrv, idun: x, whoop: [:]).points.map(\.value), [45])
        // Vilopuls får inte noll heller i diagrammet, men det är bara ln som kräver > 0.
        XCTAssertEqual(Trends.series(.restingHeartRate, idun: [idag: 0], whoop: [:]).points.count, 1)
    }

    // MARK: Avläsningen

    func testAvläsningenPerKälla() throws {
        let s = Trends.series(.restingHeartRate, idun: [idag - 2: 50, idag - 1: 52, idag: 54],
                              whoop: [idag: 60])
        let r = s.readings(on: idag)
        XCTAssertEqual(r.map(\.source), [.idun, .whoop])
        XCTAssertEqual(r[0].night, 54)
        XCTAssertEqual(try XCTUnwrap(r[0].rolling), 52, accuracy: 1e-12)
        XCTAssertEqual(r[1].night, 60)
        XCTAssertNil(r[1].rolling)
        XCTAssertTrue(s.readings(on: idag - 10).isEmpty)
    }

    // MARK: Perioden

    func testPeriodenSlutarVidSenasteNatten() throws {
        let serier = [
            Trends.series(.hrv, idun: [idag - 3: 50], whoop: [idag - 200: 50]),
            Trends.series(.sleep, idun: [:], whoop: [idag - 1: 7]),
        ]
        // Senaste natten är sömnen dag −1; perioden räknar den dagen som en av 30.
        XCTAssertEqual(Trends.window(.days30, serier), (idag - 30)...(idag - 1))
        XCTAssertEqual(Trends.window(.days90, serier), (idag - 90)...(idag - 1))
        XCTAssertEqual(Trends.window(.all, serier), (idag - 200)...(idag - 1))
        XCTAssertNil(Trends.window(.all, [Trends.series(.hrv, idun: [:], whoop: [:])]))
    }

    func testUtsnittetBehållerMedletUrHistoriken() throws {
        let s = Trends.series(.hrv, idun: växlande(), whoop: [:])
        let u = s.clipped(to: (idag - 2)...idag)
        XCTAssertEqual(u.points.count, 3)
        XCTAssertEqual(u.rolling.count, 3)
        XCTAssertEqual(u.bands.count, 3)
        XCTAssertEqual(u.rolling.last, s.rolling.last)
    }

    // MARK: Indata

    func testIdunEnNattPerDagMedNogFönster() {
        let n = [
            Trends.IdunNight(day: idag, validWindows: 10, rmssd: 99, restingHeartRate: 40, breathsPerMinute: 12),
            Trends.IdunNight(day: idag, validWindows: 80, rmssd: 60, restingHeartRate: 50, breathsPerMinute: 14),
            Trends.IdunNight(day: idag, validWindows: 90, rmssd: 62, restingHeartRate: 51, breathsPerMinute: nil),
            Trends.IdunNight(day: idag - 1, validWindows: 35, rmssd: 70, restingHeartRate: 48, breathsPerMinute: 13),
        ]
        XCTAssertEqual(Trends.minValidWindows, 36)
        let v = Trends.idunValues(n)
        XCTAssertEqual(v[.hrv], [idag: 62])
        XCTAssertEqual(v[.restingHeartRate], [idag: 51])
        XCTAssertEqual(v[.breathing], [:])
        XCTAssertEqual(v[.sleep], [:], "gamla inspelningar har ingen sömnperiod")
    }

    // MARK: K18 före gamla inspelningar (A2, S1)

    private func natt(_ dag: WakeDay, fönster: Int, källa: NightSource, id: String, rmssd: Double = 60,
                      sömn: Double? = nil) -> Trends.IdunNight {
        Trends.IdunNight(day: dag, validWindows: fönster, rmssd: rmssd, restingHeartRate: 50,
                         breathsPerMinute: 14, sleepHours: sömn, source: källa, id: id)
    }

    func testK18GårFöreEnGammalInspelningSammaDagOavsettOrdningOchFönster() {
        let gammal = natt(idag, fönster: 120, källa: .notification, id: "gammal", rmssd: 99)
        let k18 = natt(idag, fönster: 40, källa: .k18, id: "k18", rmssd: 61, sömn: 7.2)
        for ordning in [[gammal, k18], [k18, gammal]] {
            let ut = Trends.idunPerDay(ordning)
            XCTAssertEqual(ut[idag]?.id, "k18")
            XCTAssertEqual(ut.count, 1)
        }
        let v = Trends.idunValues([gammal, k18])
        XCTAssertEqual(v[.hrv], [idag: 61])
        XCTAssertEqual(v[.sleep], [idag: 7.2])
    }

    func testEnK18NattUnderMinstaFönsterLämnarDagenTillDenGamla() {
        let kort = natt(idag, fönster: Trends.minValidWindows - 1, källa: .k18, id: "kort")
        let gammal = natt(idag, fönster: 50, källa: .notification, id: "gammal")
        XCTAssertEqual(Trends.idunPerDay([kort, gammal])[idag]?.id, "gammal")
        XCTAssertNil(Trends.idunPerDay([kort])[idag], "ett prov är ingen natt")
    }

    func testAvTvåK18NätterGällerMestFönsterOchVidLikaDenFörsta() {
        let a = natt(idag, fönster: 60, källa: .k18, id: "a")
        let b = natt(idag, fönster: 70, källa: .k18, id: "b")
        let c = natt(idag, fönster: 70, källa: .k18, id: "c")
        XCTAssertEqual(Trends.idunPerDay([a, b])[idag]?.id, "b")
        XCTAssertEqual(Trends.idunPerDay([b, c])[idag]?.id, "b")
    }

    func testIdunsSömntidBlirEnSerieIOverTidBredvidWhoops() {
        let n = (0..<5).map { (k: Int) -> Trends.IdunNight in
            natt(idag - k, fönster: 80, källa: .k18, id: "n\(k)", sömn: 7 + Double(k) / 10)
        }
        let v = Trends.idunValues(n)
        XCTAssertEqual(v[.sleep]?.count, 5)
        let s = Trends.series(.sleep, idun: v[.sleep] ?? [:], whoop: [idag: 6.5])
        XCTAssertEqual(s.sources, [.idun, .whoop])
        XCTAssertEqual(s.points.filter { $0.source == .idun }.count, 5)
    }

    static let sleeps = """
    Cycle start time,Cycle end time,Cycle timezone,Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %,Nap
    2026-10-26 23:30:00,2026-10-27 23:00:00,UTC+01:00,2026-10-27 04:00:00,2026-10-27 07:00:00,80,14.0,170,180,90,40,40,10,480,30,90,70,false
    2026-10-26 23:30:00,2026-10-27 23:00:00,UTC+01:00,2026-10-26 23:30:00,2026-10-27 02:00:00,30,16.0,140,150,80,30,30,10,480,60,90,70,false
    2026-10-25 22:40:00,2026-10-26 23:30:00,UTC+01:00,2026-10-26 14:10:00,2026-10-26 14:35:00,100,14.9,22,25,15,3,4,3,0,0,88,,true
    2026-10-25 22:40:00,2026-10-26 23:30:00,UTC+01:00,2026-10-25 22:40:00,2026-10-26 06:55:00,88,14.6,452,495,231,102,119,43,510,25,91,80,false
    2026-10-24 23:10:00,2026-10-25 23:40:00,UTC+02:00,2026-10-24 23:10:00,2026-10-25 06:20:00,71,15.1,,430,210,71,100,49,505,60,88,76,false
    """

    func testSömnenPerUppvakningsdag() throws {
        let h = Trends.sleepHours(try WhoopExport.parseSleeps(Self.sleeps))
        // 26/10: bara nattpasset (tuppluren räknas inte). 27/10: två pass, summan.
        // 25/10: passet saknar längd och dagen saknas.
        XCTAssertEqual(h[WakeDay(daysSince1970: 20_752)], 452.0 / 60)
        XCTAssertEqual(h[WakeDay(daysSince1970: 20_753)], 310.0 / 60)
        XCTAssertNil(h[WakeDay(daysSince1970: 20_751)])
        XCTAssertEqual(h.count, 2)
    }

    // MARK: Tidsaxeln

    func testDagenPåTidsaxeln() {
        let d = WakeDay(daysSince1970: 20_752)
        XCTAssertEqual(d.noonUTC.timeIntervalSince1970, 20_752 * 86_400 + 43_200)
        XCTAssertEqual(WakeDay(nearest: d.noonUTC), d)
        XCTAssertEqual(WakeDay(nearest: d.startUTC), d)
        XCTAssertEqual(WakeDay(nearest: d.startUTC.addingTimeInterval(86_399)), d)
        XCTAssertEqual(WakeDay(nearest: (d + 1).startUTC), d + 1)
        // Mitt på dagen i UTC är samma datum i Sverige, sommar som vinter.
        for zon in [3_600, 7_200, -36_000, 39_600] {
            XCTAssertEqual(WakeDay(d.noonUTC, utcOffsetSeconds: zon), d, "\(zon)")
        }
    }

    // MARK: Medelpulsen (BESLUT B34)

    func testMedelpulsenÄrEgetMåttBredvidVilopulsenOchMåttenÄrSexton() {
        // METOD M42 · METOD M44. Minuter i rörelse står efter sömnen, snarkminuterna efter dem.
        XCTAssertEqual(Trends.Measure.allCases,
                       [.hrv, .restingHeartRate, .meanHeartRate, .sleep, .movement, .snoring, .regularity, .breathing,
                        .skinTemperature, .efficiency, .awakeTime, .lightSleep, .deepSleep, .remSleep, .sleepOnset,
                        .sleepWake])
        XCTAssertEqual(Trends.Measure.allCases.count, 16)
        let m = Trends.Measure.meanHeartRate
        XCTAssertTrue(m.hasRange)
        XCTAssertFalse(m.rangeFollowsResearch, "formen är ett antagande, som för andningen")
        XCTAssertFalse(m.hasStatus)
        XCTAssertFalse(m.isLogarithmic)
        XCTAssertFalse(m.isWeekly)
        XCTAssertEqual(m.rawValue, "meanHeartRate")
    }

    func testMedelpulsenKommerUrIdunnsNätterOchInteUrWhoop() {
        let nätter: [Trends.IdunNight] = (0..<10).map { (k: Int) -> Trends.IdunNight in
            Trends.IdunNight(day: idag - k, validWindows: 60, rmssd: 50, restingHeartRate: 50, breathsPerMinute: 14,
                             meanHeartRate: 56 + Double(k % 3), source: .k18)
        }
        let v = Trends.idunValues(nätter)
        XCTAssertEqual(v[.meanHeartRate]?.count, 10)
        XCTAssertEqual(v[.meanHeartRate]?[idag], 56)
        XCTAssertEqual(v[.meanHeartRate]?[idag - 1], 57)
        XCTAssertEqual(v[.restingHeartRate]?.count, 10, "vilopulsen står kvar bredvid")
        XCTAssertNil(Trends.whoopValues(cycles: [], sleeps: [])[.meanHeartRate], "Whoop har ingen medelpuls")
        // En gammal inspelning har ingen sömnperiod och därmed ingen medelpuls.
        let gammal = Trends.IdunNight(day: idag, validWindows: 60, rmssd: 50, restingHeartRate: 50, breathsPerMinute: 14)
        XCTAssertNil(gammal.meanHeartRate)
        XCTAssertEqual(Trends.idunValues([gammal])[.meanHeartRate]?.count ?? 0, 0)
        // Diagrammet: en prick per natt, och normalområdet efter fyra veckor.
        let s = Trends.series(.meanHeartRate, idun: v[.meanHeartRate] ?? [:], whoop: [:])
        XCTAssertEqual(s.points.count, 10)
        XCTAssertEqual(s.points.last?.value, 56)
        XCTAssertTrue(s.points.allSatisfy { (p: Trends.Point) -> Bool in p.source == .idun })
    }
}
