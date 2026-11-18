import Foundation
import XCTest
@testable import Night

// Påhittade nätter, bara tal. METOD M19.

final class MorningCardTests: XCTestCase {
    let idag = WakeDay(daysSince1970: 20_000)

    /// Fem veckor bakåt från idag: varannan natt `hög` och varannan `låg`, idag `hög`.
    func växlande(_ hög: Double, _ låg: Double, dagar: Int = 35, slut: Int = 0) -> [WakeDay: Double] {
        var ut: [WakeDay: Double] = [:]
        for k in 0..<dagar { ut[idag - (k + slut)] = k % 2 == 0 ? hög : låg }
        return ut
    }

    func testHRVRadenFöljerBaseline() throws {
        let x = växlande(70, 50)
        let rader = MorningCard.rows(idun: [:], whoop: [.hrv: x])
        XCTAssertEqual(rader.map(\.measure), [.hrv])
        let r = try XCTUnwrap(rader.first)
        XCTAssertEqual(r.source, .whoop)
        XCTAssertEqual(r.day, idag)
        XCTAssertEqual(r.value, 70)
        // Bandet och läget är Baseline:s (METOD M7), visat i ms.
        let nätter = x.map { NightPoint(day: $0.key, rmssd: $0.value, restingHeartRate: nil, source: .whoop) }
        let morgon = Baseline.morning(idag, nights: nätter)
        let område = try XCTUnwrap(morgon.range)
        let band = try XCTUnwrap(r.range)
        XCTAssertEqual(band.lowerBound, exp(område.lower), accuracy: 1e-9)
        XCTAssertEqual(band.upperBound, exp(område.upper), accuracy: 1e-9)
        XCTAssertEqual(r.status, morgon.status)
        XCTAssertEqual(log(try XCTUnwrap(r.rolling)), try XCTUnwrap(morgon.rollingLnRMSSD), accuracy: 1e-12)
        XCTAssertFalse(r.rangeIsAssumption)
        // Axeln spänner över nätterna: 50 till 70.
        XCTAssertEqual(r.track.lowerBound, 50)
        XCTAssertEqual(r.track.upperBound, 70)
        XCTAssertEqual(r.position(r.value), 1)
        XCTAssertLessThan(r.position(band.lowerBound), r.position(band.upperBound))
    }

    func testPrickensLägePåAxeln() {
        let r = MorningCard.Row(measure: .restingHeartRate, source: .idun, day: idag, value: 50,
                                range: 48...52, track: 40...80, rolling: nil, status: nil)
        XCTAssertEqual(r.position(50), 0.25, accuracy: 1e-12)
        XCTAssertEqual(r.position(48), 0.2, accuracy: 1e-12)
        XCTAssertEqual(r.position(40), 0)
        XCTAssertEqual(r.position(100), 1, "utanför axeln hamnar pricken vid kanten")
        XCTAssertEqual(r.position(0), 0)
    }

    func testIdunFöreWhoopSammaDag() throws {
        let rader = MorningCard.rows(idun: [.restingHeartRate: [idag: 48]],
                                     whoop: [.restingHeartRate: växlande(52, 54)])
        let r = try XCTUnwrap(rader.first)
        XCTAssertEqual(r.source, .idun)
        XCTAssertEqual(r.value, 48)
        // Idunns enda natt: inget område, och Whoops nätter blandas inte in (BESLUT B16).
        XCTAssertNil(r.range)
        XCTAssertNil(r.status)
        XCTAssertEqual(r.track.lowerBound, 47)
        XCTAssertEqual(r.track.upperBound, 49)
        XCTAssertEqual(r.position(48), 0.5, accuracy: 1e-12)
    }

    func testSenareNattIWhoopVinner() throws {
        let rader = MorningCard.rows(idun: [.breathing: [idag - 1: 14]],
                                     whoop: [.breathing: [idag: 15.5]])
        let r = try XCTUnwrap(rader.first)
        XCTAssertEqual(r.source, .whoop)
        XCTAssertEqual(r.day, idag)
    }

    func testRadernasOrdningOchKortetsNatt() throws {
        let rader = MorningCard.rows(
            idun: [.hrv: [idag - 2: 60], .breathing: [idag - 2: 14]],
            whoop: [.sleep: [idag: 7.5], .regularity: [idag - 1: 82], .skinTemperature: [idag: 33.9]])
        XCTAssertEqual(rader.map(\.measure), [.hrv, .breathing, .skinTemperature, .sleep, .regularity])
        XCTAssertEqual(MorningCard.night(rader), idag)
        XCTAssertNil(MorningCard.night([]))
        XCTAssertTrue(try XCTUnwrap(rader.last).rangeIsAssumption)
    }

    func testSömnensOmrådeHarSammaFormSomBaslinjen() throws {
        let x = växlande(8, 7)
        let r = try XCTUnwrap(MorningCard.rows(idun: [:], whoop: [.sleep: x]).first)
        let o = try XCTUnwrap(Baseline.normalRange(before: idag, value: { (d: WakeDay) -> Double? in x[d] }))
        XCTAssertEqual(try XCTUnwrap(r.range).lowerBound, o.lower, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(r.range).upperBound, o.upper, accuracy: 1e-12)
        XCTAssertNil(r.status, "bara HRV får ett läge")
        XCTAssertNil(r.rolling)
        XCTAssertTrue(r.rangeIsAssumption)
    }

    func testVärdenSomInteGårAttRäknaMedHoppasÖver() throws {
        // En HRV på 0 ms har ingen ln: natten före gäller.
        let rader = MorningCard.rows(idun: [.hrv: [idag: 0, idag - 1: 55]], whoop: [:])
        let r = try XCTUnwrap(rader.first)
        XCTAssertEqual(r.day, idag - 1)
        XCTAssertEqual(r.value, 55)
    }

    // MARK: Hudtemperaturen — METOD M25

    func testHudtempRadenHarAvvikelsenMotOmrådetsMedel() throws {
        let x = växlande(34.4, 34.0)
        let r = try XCTUnwrap(MorningCard.rows(idun: [:], whoop: [.skinTemperature: x]).first)
        XCTAssertEqual(r.measure, .skinTemperature)
        XCTAssertEqual(r.source, .whoop)
        XCTAssertEqual(r.value, 34.4)
        let o = try XCTUnwrap(Baseline.normalRange(before: idag, value: { (d: WakeDay) -> Double? in x[d] }))
        XCTAssertEqual(try XCTUnwrap(r.range).lowerBound, o.lower, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(r.range).upperBound, o.upper, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(r.reference), o.mean, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(r.deviation), 34.4 - o.mean, accuracy: 1e-12)
        XCTAssertNil(r.status, "bara HRV får ett läge")
        XCTAssertNil(r.rolling)
        XCTAssertTrue(r.rangeIsAssumption, "formen är forskningens bara för HRV och vilopuls")
        XCTAssertFalse(r.usesWhoopHistory)
    }

    func testIdunnsHudtempFårOmrådeUrWhoopsFlyttadeHistorik() throws {
        // Idunn har tre nätter, Whoop fem veckor på en annan nivå.
        let whoop = växlande(34.4, 34.0)
        let idun: [WakeDay: Double] = [idag: 33.5, idag - 1: 33.3, idag - 2: 33.7]
        let r = try XCTUnwrap(MorningCard.rows(idun: [.skinTemperature: idun],
                                               whoop: [.skinTemperature: whoop]).first)
        XCTAssertEqual(r.source, .idun)
        XCTAssertEqual(r.value, 33.5)
        XCTAssertTrue(r.usesWhoopHistory)

        // Nivåskillnaden i °C ur de tre nätterna med båda: Idunn − Whoop.
        let nivå = try XCTUnwrap(Baseline.levelOffset(idun: idun, whoop: whoop))
        XCTAssertEqual(nivå, ((33.5 - 34.4) + (33.3 - 34.0) + (33.7 - 34.4)) / 3, accuracy: 1e-12)
        var flyttad = idun
        for (d, v) in whoop where flyttad[d] == nil { flyttad[d] = v + nivå }
        let o = try XCTUnwrap(Baseline.normalRange(before: idag, value: { (d: WakeDay) -> Double? in flyttad[d] }))
        XCTAssertEqual(try XCTUnwrap(r.range).lowerBound, o.lower, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.range).upperBound, o.upper, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.deviation), 33.5 - o.mean, accuracy: 1e-9)
        // Området ligger på Idunns nivå (omkring 33,4), inte Whoops (34,2).
        XCTAssertLessThan(o.upper, 34.0)
        XCTAssertGreaterThan(o.lower, 32.8)
        // Och bandet ligger på axeln.
        XCTAssertGreaterThanOrEqual(r.position(r.range!.lowerBound), 0)
        XCTAssertLessThanOrEqual(r.position(r.range!.upperBound), 1)
    }

    func testUtanNivåskillnadFlyttasIngenWhoopNatt() throws {
        // Två nätter med båda räcker inte för en nivåskillnad: området finns
        // inte, och ingen Whoop-natt blandas in utan känd nivå (BESLUT B16).
        let r = try XCTUnwrap(MorningCard.rows(
            idun: [.skinTemperature: [idag: 33.5, idag - 1: 33.3]],
            whoop: [.skinTemperature: växlande(34.4, 34.0)]).first)
        XCTAssertEqual(r.source, .idun)
        XCTAssertNil(r.range)
        XCTAssertNil(r.deviation)
        XCTAssertFalse(r.usesWhoopHistory)
        XCTAssertEqual(r.track.lowerBound, 33.3, accuracy: 1e-12, "axeln ur Idunns två nätter")
        XCTAssertEqual(r.track.upperBound, 33.5, accuracy: 1e-12)
    }

    func testSenareWhoopNattGerWhoopsEgnaOmråde() throws {
        // Whoops natt är en dag senare än Idunns: raden är Whoops, med Whoops
        // eget område, oflyttat.
        let whoop = växlande(34.4, 34.0, slut: 0)
        let r = try XCTUnwrap(MorningCard.rows(idun: [.skinTemperature: [idag - 1: 33.5]],
                                               whoop: [.skinTemperature: whoop]).first)
        XCTAssertEqual(r.source, .whoop)
        XCTAssertFalse(r.usesWhoopHistory)
        let o = try XCTUnwrap(Baseline.normalRange(before: idag, value: { (d: WakeDay) -> Double? in whoop[d] }))
        XCTAssertEqual(try XCTUnwrap(r.reference), o.mean, accuracy: 1e-12)
    }

    func testEnHudtempNattUtanVärdeGerIngenRad() {
        let nätter = [Trends.IdunNight(day: idag, validWindows: 50, rmssd: nil, restingHeartRate: nil,
                                       breathsPerMinute: nil, skinTemperature: nil)]
        let rader = MorningCard.rows(idun: Trends.idunValues(nätter), whoop: [:])
        XCTAssertTrue(rader.isEmpty, "en natt under minsta täckning ger ingen prick")
    }

    // MARK: Medelpulsen (BESLUT B34)

    func testKortetHarÅttaMåttMedMedelpulsenEfterVilopulsenOchRörelsenEfterSömnen() {
        XCTAssertEqual(MorningCard.measures,
                       [.hrv, .restingHeartRate, .meanHeartRate, .breathing, .skinTemperature, .sleep, .movement,
                        .regularity])
        XCTAssertEqual(MorningCard.measures.count, 8)
    }

    func testMedelpulsRadenHarSittEgetOmrådeUtanLäge() throws {
        let x = växlande(58, 54)
        let rader = MorningCard.rows(idun: [.restingHeartRate: växlande(51, 49), .meanHeartRate: x], whoop: [:])
        XCTAssertEqual(rader.map(\.measure), [.restingHeartRate, .meanHeartRate], "direkt efter vilopulsen")
        let r = try XCTUnwrap(rader.last)
        XCTAssertEqual(r.source, .idun)
        XCTAssertEqual(r.day, idag)
        XCTAssertEqual(r.value, 58)
        XCTAssertNil(r.status, "bara HRV får ett läge")
        XCTAssertNil(r.rolling)
        XCTAssertTrue(r.rangeIsAssumption, "formen är ett antagande, som för andningen")
        let band = try XCTUnwrap(r.range, "fem veckors nätter ger ett normalområde")
        // Vilopulsens område är ett annat än medelpulsens.
        let vilo = try XCTUnwrap(rader.first?.range)
        XCTAssertNotEqual(vilo.lowerBound, band.lowerBound)
        XCTAssertLessThan(r.position(band.lowerBound), r.position(band.upperBound))
        XCTAssertEqual(r.track.lowerBound, 54)
        XCTAssertEqual(r.track.upperBound, 58)
    }

    /// METOD M81 · BESLUT B141. Andelen är stadiets minuter mot de fyra stadiernas summa, och området räknas ur
    /// andelarna före natten, inte ur minuterna: en kort natt med samma fördelning hamnar inom området.
    func testStadietsAndelOchOmrådetRäknasIAndelar() throws {
        var v: Trends.Values = [:]
        for k in 1..<36 {
            // Fem veckor bakåt: 8 h nätter med djupsömnen kring 20 % (19 eller 21 %).
            let djup: Double = k % 2 == 0 ? 0.19 : 0.21
            let summa: Double = 480
            v[.deepSleep, default: [:]][idag - k] = djup * summa
            v[.remSleep, default: [:]][idag - k] = 0.22 * summa
            v[.awakeTime, default: [:]][idag - k] = 0.08 * summa
            v[.lightSleep, default: [:]][idag - k] = (1 - djup - 0.22 - 0.08) * summa
        }
        // Natten är kort (5 h) men har samma fördelning.
        v[.deepSleep, default: [:]][idag] = 60
        v[.remSleep, default: [:]][idag] = 66
        v[.awakeTime, default: [:]][idag] = 24
        v[.lightSleep, default: [:]][idag] = 150
        let a = try XCTUnwrap(MorningCard.stageShare(.deepSleep, day: idag, idun: v))
        XCTAssertEqual(a.value, 0.2, accuracy: 1e-9)
        let område = try XCTUnwrap(a.range)
        XCTAssertTrue(område.contains(a.value))
        XCTAssertLessThan(område.upperBound, 0.25)
        // Minuterna ligger däremot långt under sitt område.
        let minuter = try XCTUnwrap(MorningCard.nightRow(.deepSleep, day: idag, idun: v)?.range)
        XCTAssertLessThan(60, minuter.lowerBound)
    }

    /// METOD M81. En natt där något av de fyra stadierna saknas har ingen andel, och andra mått ger ingen.
    func testAndelenKräverAllaFyraStadier() {
        let v: Trends.Values = [.deepSleep: [idag: 60], .remSleep: [idag: 66], .lightSleep: [idag: 150]]
        XCTAssertNil(MorningCard.stageShare(.deepSleep, day: idag, idun: v))
        XCTAssertNil(MorningCard.stageShare(.hrv, day: idag, idun: v))
    }
}
