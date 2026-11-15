import Foundation
import XCTest
@testable import Night

// Påhittade nätter, bara tal. METOD M6, M7.

final class BaselineTests: XCTestCase {
    let idag = WakeDay(daysSince1970: 20_000)

    /// Baslinjen: de fyra veckorna före veckan (dag −7 till −34), 28 nätter,
    /// varannan 4,2 och varannan 3,8 (ln-skala), vilopuls 50 och 54.
    /// Medel 4,0, SD 0,2·√(28/27).
    func historik(source: NightPoint.Source = .idun) -> [NightPoint] {
        (0..<28).map { (k: Int) -> NightPoint in
            NightPoint(day: idag - (7 + k), lnRMSSD: k % 2 == 0 ? 4.2 : 3.8,
                       restingHeartRate: k % 2 == 0 ? 50 : 54, source: source)
        }
    }

    /// Veckan: morgonens dag och de sex före, alla med samma värde.
    func vecka(_ x: Double, resting: Double = 52) -> [NightPoint] {
        (0..<7).map { (k: Int) -> NightPoint in
            NightPoint(day: idag - k, lnRMSSD: x, restingHeartRate: resting, source: .idun)
        }
    }

    var sd: Double { 0.2 * (28.0 / 27.0).squareRoot() }
    var övre: Double { 4.0 + 0.5 * sd }
    var undre: Double { 4.0 - 0.5 * sd }

    func testKonventionenUrKällorna() {
        // METOD M6, M7: 7-dagarsmedel, fyra veckors baslinje, medel ± 0,5 SD,
        // minst 3 nätter i varje vecka.
        XCTAssertEqual(Baseline.rollingDays, 7)
        XCTAssertEqual(Baseline.baselineWeeks, 4)
        XCTAssertEqual(Baseline.historyDays, 28)
        XCTAssertEqual(Baseline.rangeWidthSD, 0.5)
        XCTAssertEqual(Baseline.minNightsPerWeek, 3)
    }

    func testNormalområdetUrNätternaFöreVeckan() throws {
        let m = Baseline.morning(idag, nights: historik() + vecka(4.0))
        let r = try XCTUnwrap(m.range)
        XCTAssertEqual(r.nights, 28)
        XCTAssertEqual(r.mean, 4.0, accuracy: 1e-12)
        XCTAssertEqual(r.standardDeviation, sd, accuracy: 1e-12)
        XCTAssertEqual(r.upper, övre, accuracy: 1e-12)
        XCTAssertEqual(m.rollingNights, 7)
        XCTAssertEqual(try XCTUnwrap(m.rollingLnRMSSD), 4.0, accuracy: 1e-12)
        XCTAssertEqual(m.status, .within)
        XCTAssertEqual(try XCTUnwrap(m.lnRMSSD), 4.0)
    }

    func testUnderInomÖverVidGränserna() {
        XCTAssertEqual(Baseline.morning(idag, nights: historik() + vecka(övre + 1e-6)).status, .above)
        XCTAssertEqual(Baseline.morning(idag, nights: historik() + vecka(övre - 1e-6)).status, .within)
        XCTAssertEqual(Baseline.morning(idag, nights: historik() + vecka(undre + 1e-6)).status, .within)
        XCTAssertEqual(Baseline.morning(idag, nights: historik() + vecka(undre - 1e-6)).status, .below)
    }

    func testGränsenSjälvRäknasSomInom() {
        let r = Baseline.NormalRange(mean: 4, standardDeviation: 0.2, nights: 30)
        XCTAssertEqual(r.status(r.upper), .within)
        XCTAssertEqual(r.status(r.lower), .within)
    }

    func testVeckanIngårInteISittEgetNormalområde() throws {
        // Ett extremt värde i veckan och ett dagen efter de fyra veckorna
        // (dag −35) flyttar inte området.
        var nätter = historik() + vecka(9.0)
        nätter.append(NightPoint(day: idag - 35, lnRMSSD: 9, restingHeartRate: 90, source: .idun))
        let m = Baseline.morning(idag, nights: nätter)
        XCTAssertEqual(try XCTUnwrap(m.range).nights, 28)
        XCTAssertEqual(try XCTUnwrap(m.range).mean, 4.0, accuracy: 1e-12)
    }

    func testVarjeVeckaIBaslinjenBehöverTreNätter() throws {
        // Tre nätter i var och en av de fyra veckorna räcker: 12 nätter.
        let glesa = historik().filter { (p: NightPoint) -> Bool in
            let k = idag.daysSince1970 - p.day.daysSince1970 - 7
            return k % 7 < 3
        }
        XCTAssertEqual(glesa.count, 12)
        let m = Baseline.morning(idag, nights: glesa + vecka(4.0))
        XCTAssertEqual(try XCTUnwrap(m.range).nights, 12)
        XCTAssertNotNil(m.status)

        // Två nätter i tredje veckan (dag −21 till −27): inte en full baslinje, men 23 nätter finns.
        // METOD M7 (BESLUT B69): området räknas ur dem, bredare än det vanliga och märkt som under byggande.
        let hål = historik().filter { (p: NightPoint) -> Bool in
            let k = idag.daysSince1970 - p.day.daysSince1970 - 7
            return !(k >= 14 && k < 21 && k % 7 >= 2)
        }
        XCTAssertEqual(hål.count, 23)
        let h = Baseline.morning(idag, nights: hål + vecka(4.0))
        let hr = try XCTUnwrap(h.range)
        XCTAssertEqual(hr.nights, 23)
        XCTAssertTrue(hr.isBuilding)
        XCTAssertGreaterThan(hr.widthFactor, 1)
        XCTAssertNotNil(h.status)
        XCTAssertNotNil(h.restingHeartRateRange)
        XCTAssertNotNil(h.rollingLnRMSSD)
    }

    func testFörFåNätterGerIngenBedömning() {
        // Sex nätter före morgonen: inget normalområde (METOD M7, BESLUT B69: minst sju).
        let kort = nätterFöre(6)
        let m = Baseline.morning(idag, nights: kort + [NightPoint(day: idag, lnRMSSD: 4.0, restingHeartRate: 52, source: .idun)])
        XCTAssertNil(m.range)
        XCTAssertNil(m.status)
        XCTAssertNotNil(m.rollingLnRMSSD)

        // Två nätter i veckan: inget rullande medel.
        let glest = historik() + Array(vecka(4.0).prefix(2))
        let g = Baseline.morning(idag, nights: glest)
        XCTAssertEqual(g.rollingNights, 2)
        XCTAssertNil(g.rollingLnRMSSD)
        XCTAssertNil(g.status)
        XCTAssertNotNil(g.range)
    }

    // MARK: Normalområdet efter sju nätter (METOD M7, BESLUT B69)

    /// `n` nätter i följd, från dag −`från` och bakåt, varannan 4,2 och varannan 3,8.
    func nätterFöre(_ n: Int, från: Int = 1) -> [NightPoint] {
        (0..<n).map { (k: Int) -> NightPoint in
            NightPoint(day: idag - (från + k), lnRMSSD: k % 2 == 0 ? 4.2 : 3.8,
                       restingHeartRate: k % 2 == 0 ? 50 : 54, source: .idun)
        }
    }

    func testSexNätterGerIngetBandOchSjuGerEttBrettBand() throws {
        XCTAssertNil(Baseline.morning(idag, nights: nätterFöre(6)).range)
        let m = Baseline.morning(idag, nights: nätterFöre(7))
        let r = try XCTUnwrap(m.range)
        XCTAssertEqual(r.nights, 7)
        XCTAssertTrue(r.isBuilding)
        XCTAssertEqual(r.widthFactor, 2.447 / 2.052, accuracy: 1e-12)
        XCTAssertGreaterThan(r.widthFactor, 1.15)
        XCTAssertEqual(r.upper - r.lower, 2 * Baseline.rangeWidthSD * r.widthFactor * r.standardDeviation,
                       accuracy: 1e-12)
        XCTAssertNotNil(m.restingHeartRateRange, "samma regel för vilopulsen")
    }

    func testBandetSmalnarMedAntaletNätter() {
        var förra = Double.infinity
        for n in [7, 10, 14, 21, 27, 28] {
            let f = Baseline.widthFactor(nights: n)
            XCTAssertLessThan(f, förra, "n = \(n)")
            förra = f
        }
        XCTAssertEqual(Baseline.widthFactor(nights: 28), 1, accuracy: 1e-12)
        XCTAssertEqual(Baseline.widthFactor(nights: 40), 1, accuracy: 1e-12)
        // Samma sorts värden i fler nätter ger ett smalare band: SD är nästan densamma, faktorn minskar.
        let få = Baseline.morning(idag, nights: nätterFöre(8)).range
        let fler = Baseline.morning(idag, nights: nätterFöre(20)).range
        XCTAssertNotNil(få)
        XCTAssertNotNil(fler)
        XCTAssertGreaterThan((få?.upper ?? 0) - (få?.lower ?? 0), (fler?.upper ?? 0) - (fler?.lower ?? 0))
    }

    func testFyraFullaVeckorGerSammaBandSomFörut() throws {
        let r = try XCTUnwrap(Baseline.morning(idag, nights: historik() + vecka(4.0)).range)
        XCTAssertEqual(r.nights, 28)
        XCTAssertEqual(r.widthFactor, 1)
        XCTAssertFalse(r.isBuilding)
        XCTAssertEqual(r.lower, undre, accuracy: 1e-12)
        XCTAssertEqual(r.upper, övre, accuracy: 1e-12)
    }

    func testSenasteVeckanHoppasÖverNärDeAndraNättenaRäcker() throws {
        // Sju nätter i dag −7 till −13 och extrema värden i veckan före morgonen: bandet bygger på de sju.
        let gamla = nätterFöre(7, från: 7)
        let extrema = (1..<7).map { (k: Int) -> NightPoint in
            NightPoint(day: idag - k, lnRMSSD: 9, restingHeartRate: 90, source: .idun)
        }
        let r = try XCTUnwrap(Baseline.morning(idag, nights: gamla + extrema).range)
        XCTAssertEqual(r.nights, 7)
        XCTAssertEqual(r.mean, (4.2 * 4 + 3.8 * 3) / 7, accuracy: 1e-12)
    }

    func testSenasteVeckanTasMedBaraFörAttNåSju() throws {
        // Tre nätter i veckan före morgonen och fyra äldre: sju tillsammans, så veckan tas med.
        let nätter = nätterFöre(3) + nätterFöre(4, från: 10)
        let r = try XCTUnwrap(Baseline.morning(idag, nights: nätter).range)
        XCTAssertEqual(r.nights, 7)
        // En natt mindre ger inget område.
        XCTAssertNil(Baseline.morning(idag, nights: nätterFöre(3) + nätterFöre(3, från: 10)).range)
    }

    func testBaselineNightsRäknarNätterFöreMorgonen() {
        let x = Dictionary(uniqueKeysWithValues: nätterFöre(40).map { ($0.day, 1.0) })
        XCTAssertEqual(Baseline.baselineNights(before: idag, value: { x[$0] }), 28)
        let ny = Dictionary(uniqueKeysWithValues: nätterFöre(5).map { ($0.day, 1.0) })
        XCTAssertEqual(Baseline.baselineNights(before: idag, value: { ny[$0] }), 5)
        XCTAssertEqual(Baseline.baselineNights(before: idag, value: { _ in nil }), 0)
    }

    func testVilopulsenStårBredvid() throws {
        let m = Baseline.morning(idag, nights: historik() + vecka(4.0, resting: 58))
        XCTAssertEqual(try XCTUnwrap(m.restingHeartRate), 58)
        let r = try XCTUnwrap(m.restingHeartRateRange)
        XCTAssertEqual(r.mean, 52, accuracy: 1e-12)
        XCTAssertGreaterThan(58, r.upper)
    }

    func testBaslinjenKanBörjaIWhoopsNätter() {
        // Historiken bara från Whoop, veckan från Idunn: läget går att räkna.
        let m = Baseline.morning(idag, nights: historik(source: .whoop) + vecka(3.0))
        XCTAssertEqual(m.status, .below)
        // Utan Whoops nätter finns ingen historik — källorna går att hålla isär.
        let bara = (historik(source: .whoop) + vecka(3.0)).filter { $0.source == .idun }
        XCTAssertNil(Baseline.morning(idag, nights: bara).status)
    }

    func testIdunFöreWhoopSammaDag() throws {
        let whoop = NightPoint(day: idag, lnRMSSD: 5, restingHeartRate: 40, source: .whoop)
        let idun = NightPoint(day: idag, lnRMSSD: 4, restingHeartRate: 50, source: .idun)
        XCTAssertEqual(Baseline.morning(idag, nights: [idun, whoop]).lnRMSSD, 4)
        XCTAssertEqual(Baseline.morning(idag, nights: [whoop, idun]).lnRMSSD, 4)
    }

    func testSammanslagningFlyttarWhoopTillIdunsNivå() {
        let whoop = [
            NightPoint(day: idag - 2, lnRMSSD: 4.0, restingHeartRate: 50, source: .whoop),
            NightPoint(day: idag - 1, lnRMSSD: 4.5, restingHeartRate: 52, source: .whoop),
        ]
        let idun = [NightPoint(day: idag - 1, lnRMSSD: 3.9, restingHeartRate: 55, source: .idun)]
        let ihop = Baseline.combine(idun: idun, whoop: whoop, whoopLnOffset: -0.25, whoopRestingOffset: 2)
        XCTAssertEqual(ihop.map(\.day), [idag - 2, idag - 1])
        XCTAssertEqual(ihop[0].source, .whoop)
        XCTAssertEqual(ihop[0].lnRMSSD, 3.75)
        XCTAssertEqual(ihop[0].restingHeartRate, 52)
        XCTAssertEqual(ihop[1].source, .idun)
        XCTAssertEqual(ihop[1].lnRMSSD, 3.9)
    }

    func testMorgnarnaIDagordning() {
        let m = Baseline.mornings(vecka(4.0).reversed() + historik())
        XCTAssertEqual(m.count, 35)
        XCTAssertEqual(m.first?.day, idag - 34)
        XCTAssertEqual(m.last?.day, idag)
    }

    func testUppvakningsdagenISinZon() {
        // 23:30 UTC är 01:30 nästa dag i UTC+02:00.
        let t = Date(timeIntervalSince1970: TimeInterval(20_751 * 86_400 + 23 * 3600 + 1800))
        XCTAssertEqual(WakeDay(t, utcOffsetSeconds: 0).daysSince1970, 20_751)
        XCTAssertEqual(WakeDay(t, utcOffsetSeconds: 7200).daysSince1970, 20_752)
        XCTAssertEqual(WakeDay(t, utcOffsetSeconds: -5 * 3600).daysSince1970, 20_751)
        // Före 1970 avrundas nedåt, inte mot noll.
        XCTAssertEqual(WakeDay(Date(timeIntervalSince1970: -1), utcOffsetSeconds: 0).daysSince1970, -1)
    }

    func testNattUtanPositivRMSSDFårIngenLn() {
        XCTAssertNil(NightPoint(day: idag, rmssd: 0, restingHeartRate: nil, source: .idun).lnRMSSD)
        XCTAssertNil(NightPoint(day: idag, rmssd: nil, restingHeartRate: nil, source: .idun).lnRMSSD)
        XCTAssertEqual(NightPoint(day: idag, rmssd: 1, restingHeartRate: nil, source: .idun).lnRMSSD, 0)
    }

    // MARK: Hudtemperaturen — METOD M25

    /// Baslinjen för hudtemperaturen: dag −7 till −34, varannan 33,0 och varannan 33,4.
    func hudHistorik(source: NightPoint.Source = .idun, nivå: Double = 0) -> [NightPoint] {
        (0..<28).map { (k: Int) -> NightPoint in
            NightPoint(day: idag - (7 + k), lnRMSSD: nil, restingHeartRate: nil,
                       skinTemperature: (k % 2 == 0 ? 33.0 : 33.4) + nivå, source: source)
        }
    }

    func testHudtemperaturensOmrådeFölerSammaRegelSomVilopulsen() throws {
        let natt = NightPoint(day: idag, lnRMSSD: nil, restingHeartRate: nil, skinTemperature: 33.9, source: .idun)
        let m = Baseline.morning(idag, nights: hudHistorik() + [natt])
        let r = try XCTUnwrap(m.skinTemperatureRange)
        XCTAssertEqual(r.nights, 28)
        XCTAssertEqual(r.mean, 33.2, accuracy: 1e-12)
        let sd = 0.2 * (28.0 / 27.0).squareRoot()
        XCTAssertEqual(r.upper, 33.2 + 0.5 * sd, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(m.skinTemperature), 33.9)
        XCTAssertGreaterThan(33.9, r.upper)
        XCTAssertNil(m.status, "hudtemperaturen får inget läge")
    }

    func testHudtemperaturenKräverTreNätterIVarjeVecka() {
        XCTAssertNotNil(Baseline.morning(idag, nights: hudHistorik()).skinTemperatureRange)
        // Veckan dag −21 till −27 har kvar bara två nätter: inte full baslinje, men nätterna som finns
        // ger ett område under byggande (METOD M7, BESLUT B69).
        let veckaMedTvå = hudHistorik().filter { !(idag.daysSince1970 - 27 ... idag.daysSince1970 - 23).contains($0.day.daysSince1970) }
        let r = Baseline.morning(idag, nights: veckaMedTvå).skinTemperatureRange
        XCTAssertEqual(r?.nights, 23)
        XCTAssertEqual(r?.isBuilding, true)
    }

    func testNivåskillnadenRäknasIGraderOchKräverTreNätterMedBåda() throws {
        let idun: [WakeDay: Double] = [idag: 33.0, idag - 1: 33.2, idag - 2: 33.4]
        let whoop: [WakeDay: Double] = [idag: 33.9, idag - 1: 34.0, idag - 2: 34.3, idag - 3: 34.1]
        // (−0,9 − 0,8 − 0,9) / 3 °C: Idunn − Whoop, additivt.
        XCTAssertEqual(try XCTUnwrap(Baseline.levelOffset(idun: idun, whoop: whoop)), -2.6 / 3, accuracy: 1e-12)
        // Två nätter med båda räcker inte.
        XCTAssertNil(Baseline.levelOffset(idun: [idag: 33.0, idag - 1: 33.2], whoop: whoop))
        XCTAssertNil(Baseline.levelOffset(idun: [:], whoop: whoop))
    }

    func testFlyttadeNätterFyllerBaraDagarUtanIdunn() throws {
        let idun: [WakeDay: Double] = [idag: 33.0, idag - 1: 33.2, idag - 2: 33.4]
        let whoop: [WakeDay: Double] = [idag: 33.9, idag - 1: 34.0, idag - 2: 34.3, idag - 3: 34.1]
        let offset = -2.6 / 3
        let ihop = Baseline.levelled(idun: idun, whoop: whoop)
        XCTAssertEqual(ihop.count, 4)
        XCTAssertEqual(ihop[idag], 33.0, "en dag med båda får Idunns natt")
        XCTAssertEqual(try XCTUnwrap(ihop[idag - 3]), 34.1 + offset, accuracy: 1e-12)
        // Utan känd nivåskillnad ingår ingen Whoop-natt.
        let fåPar = Baseline.levelled(idun: [idag: 33.0], whoop: whoop)
        XCTAssertEqual(fåPar, [idag: 33.0])
    }

    func testSammanslagningFlyttarWhoopsHudtemperaturIGrader() throws {
        let whoop = [NightPoint(day: idag - 2, lnRMSSD: nil, restingHeartRate: nil, skinTemperature: 34.1, source: .whoop)]
        let idun = [NightPoint(day: idag - 1, lnRMSSD: nil, restingHeartRate: nil, skinTemperature: 33.3, source: .idun)]
        let ihop = Baseline.combine(idun: idun, whoop: whoop, whoopSkinOffset: -0.7)
        XCTAssertEqual(try XCTUnwrap(ihop[0].skinTemperature), 33.4, accuracy: 1e-12)
        XCTAssertEqual(ihop[1].skinTemperature, 33.3)
    }

    func testBaslinjenFörHudtemperaturKanBörjaIWhoopsFlyttadeNätter() throws {
        // Historiken från Whoop, 0,7 °C över Idunns nivå; nivåskillnaden ur tre
        // nätter med båda. Idunns natt idag ligger inom området först när Whoops
        // historik flyttats.
        let whoop = hudHistorik(source: .whoop, nivå: 0.7)
        let idun = (0..<3).map { (k: Int) -> NightPoint in
            NightPoint(day: idag - k, lnRMSSD: nil, restingHeartRate: nil, skinTemperature: 33.2, source: .idun)
        }
        let par = whoop + (0..<3).map { (k: Int) -> NightPoint in
            NightPoint(day: idag - k, lnRMSSD: nil, restingHeartRate: nil, skinTemperature: 33.9, source: .whoop)
        }
        let utanFlytt = Baseline.morning(idag, nights: Baseline.combine(idun: idun, whoop: par))
        XCTAssertEqual(try XCTUnwrap(utanFlytt.skinTemperatureRange).mean, 33.9, accuracy: 1e-12)
        let offset = try XCTUnwrap(Baseline.levelOffset(
            idun: Dictionary(uniqueKeysWithValues: idun.map { ($0.day, $0.skinTemperature!) }),
            whoop: Dictionary(uniqueKeysWithValues: par.filter { $0.day >= idag - 2 }.map { ($0.day, $0.skinTemperature!) })))
        XCTAssertEqual(offset, -0.7, accuracy: 1e-12)
        let flyttad = Baseline.morning(idag, nights: Baseline.combine(idun: idun, whoop: par, whoopSkinOffset: offset))
        XCTAssertEqual(try XCTUnwrap(flyttad.skinTemperatureRange).mean, 33.2, accuracy: 1e-12)
    }
}
