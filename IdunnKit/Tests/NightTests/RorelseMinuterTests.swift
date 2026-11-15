import Foundation
import XCTest
import HeartRate
import WhoopFrames
import DemoData
@testable import Night

// METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden (PLAN.md R3): räkningen ur lagrens minuter,
// sammanfattningen, Trends och Morgon. Nätterna är påhittade: minuter byggda för hand och en natt ur
// DemoK18Nights. Inget kommer från ett riktigt band (CLAUDE.md §Dataregeln).

final class RorelseMinuterTests: XCTestCase {
    let idag = WakeDay(daysSince1970: 20_000)

    private func minut(_ k: Int, _ rörelse: Double?) -> NightLayers.Minute {
        NightLayers.Minute(start: Double(k) * 60, movement: rörelse, skinTemperature: rörelse == nil ? nil : 33)
    }

    // MARK: Räkningen

    func testMinuterIRörelseÄrHelaMinuterInomPeriodenOchGränsenRäknas() {
        let g: Double = NightLayers.movementThreshold
        XCTAssertEqual(g, SkinTemperature.stillMovement, "samma gräns som kurvans rörelselager (METOD M32)")
        let minuter: [NightLayers.Minute] = [
            minut(0, 0.5), minut(1, 0.5),
            minut(2, 0.001), minut(3, g), minut(4, 0.019), minut(5, nil), minut(6, 0.3),
            minut(7, 0.5),
        ]
        // Perioden 90…420 s: hela minuter är 2…6 (start 120…360). Minut 1 och 7 är bara delvis med och räknas inte.
        XCTAssertEqual(NightLayers.movementMinutes(minuter, period: 90...420), 2,
                       "gränsen räknas, 0,019 gör det inte, minuten utan tal hoppas över")
        XCTAssertEqual(NightLayers.movementMinutes(minuter, period: 120...420), 2, "perioden på hel minut")
        XCTAssertEqual(NightLayers.movementMinutes(minuter, period: 0...480), 5, "minuterna 0, 1, 3, 6 och 7")
        // Samma räkning över lagren: perioden är lagrens sömnperiod.
        let lager = NightLayers.Layers(start: 0, end: 480, minutes: minuter, gaps: [], period: 120...420,
                                       asleep: [], awake: [], coverage: nil)
        XCTAssertEqual(NightLayers.movementMinutes(lager), 2)
    }

    func testMinuterIRörelseKräverAttHälftenAvPeriodensMinuterHarEttTal() {
        var minuter: [NightLayers.Minute] = []
        for k in 0..<10 { minuter.append(minut(k, k < 5 ? 0.5 : nil)) }
        XCTAssertEqual(NightLayers.movementMinCoverage, SkinTemperature.minCoverage, "som hudtemperaturen (METOD M25)")
        XCTAssertEqual(NightLayers.movementMinutes(minuter, period: 0...600), 5, "exakt hälften är känd")
        minuter[4] = minut(4, nil)
        XCTAssertNil(NightLayers.movementMinutes(minuter, period: 0...600), "fyra av tio är för lite: inget tal")
    }

    func testIngenHelMinutEllerIngaMinuterGerIngetMenNollMinuterÄrEttTal() {
        XCTAssertNil(NightLayers.movementMinutes([], period: 0...600))
        XCTAssertNil(NightLayers.movementMinutes([minut(0, 0.5), minut(1, 0.5)], period: 10...50),
                     "perioden rymmer ingen hel minut")
        XCTAssertNil(NightLayers.movementMinutes([minut(0, nil), minut(1, nil)], period: 0...120),
                     "ingen minut har ett tal")
        XCTAssertEqual(NightLayers.movementMinutes([minut(0, 0.001), minut(1, 0.002)], period: 0...120), 0,
                       "noll minuter i rörelse är ett tal, inte inget")
    }

    /// Facit ur K18Series.minutes: de hela minuterna inom [onset, wake] som har ett rörelsetal, och av dem
    /// de över gränsen.
    private func facit(_ serie: K18Series, onset: Int, wake: Int) -> (rörelse: Int, kända: Int, inne: Int) {
        let första: Int = (onset + 59) / 60
        let sista: Int = wake / 60
        guard sista > första else { return (rörelse: 0, kända: 0, inne: 0) }
        var perMinut: [Int: Double] = [:]
        for m in serie.minutes {
            if let v = m.movement { perMinut[m.minute] = v }
        }
        var rörelse: Int = 0
        var kända: Int = 0
        for k in första..<sista {
            guard let v = perMinut[k] else { continue }
            kända += 1
            if v >= NightLayers.movementThreshold { rörelse += 1 }
        }
        return (rörelse: rörelse, kända: kända, inne: sista - första)
    }

    // MARK: En natt ur K18

    func testEnNattMedFyraRörligaMinuterGerMinutenIRörelseOchSammanfattningenBärDem() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false, movementBout: true)
        let serie = K18Series(records: n.records)
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let r = try XCTUnwrap(K18Night.analyze(serie, wakeDay: dag, startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        let l = try XCTUnwrap(r.layers)
        let tal = try XCTUnwrap(r.movementMinutes)
        XCTAssertEqual(tal, NightLayers.movementMinutes(l), "resultatet räknar över lagrens minuter och period")
        let f = facit(serie, onset: Int(l.period.lowerBound), wake: Int(l.period.upperBound))
        XCTAssertEqual(tal, f.rörelse, "samma tal räknat direkt ur K18-serien")
        XCTAssertGreaterThan(f.kända, 100, "en hel natt med tal")
        // Fyra minuter med armen i rörelse ger minst tre hela minuter; vändningarna ger minutmedel under gränsen
        // (METOD M32) och räknas inte. Perioden hittas på några minuter när (METOD M26), så några uppe-minuter
        // vid kanten kan följa med, men inte de tjugo-trettio som natten har före insomning och efter uppvaknande.
        XCTAssertGreaterThanOrEqual(tal, 3, "minst de tre hela minuterna")
        XCTAssertLessThanOrEqual(tal, 14, "inte alla uppe-minuter före insomning och efter uppvaknande")

        // Sammanfattningen och Trends bär talet; en sparad sammanfattning utan fältet avkodas ändå.
        let d = NightDigest(r)
        XCTAssertEqual(d.movementMinutes, tal)
        XCTAssertEqual(d.idunNight.movementMinutes, tal)
        XCTAssertEqual(Trends.idunValues([d.idunNight])[.movement]?.count ?? 0,
                       d.validWindows >= Trends.minValidWindows ? 1 : 0)
        let data = try JSONEncoder().encode(d)
        XCTAssertEqual(try JSONDecoder().decode(NightDigest.self, from: data), d)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["movementMinutes"])
        obj.removeValue(forKey: "movementMinutes")
        let gammal = try JSONDecoder().decode(NightDigest.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(gammal.movementMinutes)
        XCTAssertEqual(try XCTUnwrap(gammal.rmssdMean), try XCTUnwrap(d.rmssdMean), accuracy: 1e-9)
    }

    func testEnNattUtanK18GerIngenRörelseOchIngenPunkt() {
        let n = DemoK18Nights.night(daysBeforeLast: 1, shortGaps: false)
        var rec = NightRecording()
        for x in n.measurements() where Int(x.time.timeIntervalSince1970) < n.onset + 3_600 {
            rec.append(x.measurement, at: x.time)
        }
        let r = NightResult.fromNotifications(rec, utcOffsetSeconds: n.utcOffsetSeconds)
        XCTAssertNil(r.layers)
        XCTAssertNil(r.movementMinutes, "en gammal inspelning har inga lager")
        let d = NightDigest(r)
        XCTAssertNil(d.movementMinutes)
        XCTAssertNil(d.idunNight.movementMinutes)
        XCTAssertEqual(Trends.idunValues([d.idunNight])[.movement]?.count ?? 0, 0, "ingen punkt")
    }

    // MARK: Trends och Morgon

    /// 35 nätter bakåt från idag, med `rörelse(k)` minuter natten k dagar före idag.
    private func nätter(_ rörelse: (Int) -> Int?) -> [Trends.IdunNight] {
        var ut: [Trends.IdunNight] = []
        for k in 0..<35 {
            ut.append(Trends.IdunNight(day: idag - k, validWindows: 60, rmssd: 50, restingHeartRate: 50,
                                       breathsPerMinute: 14, movementMinutes: rörelse(k), source: .k18))
        }
        return ut
    }

    func testMinuterIRörelseÄrEttMåttMedEgetOmrådeUtanLäge() {
        let m = Trends.Measure.movement
        XCTAssertEqual(m.rawValue, "movement")
        XCTAssertTrue(m.hasRange)
        XCTAssertFalse(m.rangeFollowsResearch, "formen är ett antagande (METOD M42)")
        XCTAssertFalse(m.hasStatus)
        XCTAssertFalse(m.isLogarithmic)
        XCTAssertFalse(m.isWeekly)
        XCTAssertTrue(m.accepts(0), "noll minuter är ett tal")
        XCTAssertFalse(m.accepts(.nan))
    }

    func testMinuterIRörelseHarPunktMedelOchOmrådeSomDeAndraMåtten() throws {
        let v = Trends.idunValues(nätter { (k: Int) -> Int? in k % 2 == 0 ? 12 : 8 })
        XCTAssertEqual(v[.movement]?.count, 35)
        XCTAssertEqual(v[.movement]?[idag], 12)
        XCTAssertEqual(v[.movement]?[idag - 1], 8)
        let s = Trends.series(.movement, idun: v[.movement] ?? [:], whoop: [:])
        XCTAssertEqual(s.points.count, 35)
        XCTAssertTrue(s.points.allSatisfy { (p: Trends.Point) -> Bool in p.source == .idun })
        let sista = try XCTUnwrap(s.latest)
        XCTAssertNil(sista.status, "bara HRV får ett läge")
        let band = try XCTUnwrap(s.bands.last, "fem veckors nätter ger ett normalområde")
        XCTAssertEqual(band.day, idag)
        XCTAssertLessThan(band.lower, 10)
        XCTAssertGreaterThan(band.upper, 10)
        // Raden på Morgon: nattens tal på det egna bandet, utan läge och utan 7-dagarsmedel.
        let kort = MorningCard.day(idag, idun: v)
        let rad = try XCTUnwrap(kort.rows.first { (r: MorningCard.Row) -> Bool in r.measure == .movement })
        XCTAssertEqual(rad.source, .idun)
        XCTAssertEqual(rad.day, idag)
        XCTAssertEqual(rad.value, 12)
        XCTAssertNotNil(rad.range)
        XCTAssertTrue(rad.rangeIsAssumption)
        XCTAssertNil(rad.status)
        XCTAssertNil(rad.rolling)
    }

    func testEnNattUtanTalHarIngenPunktOchKortetTarEnÄldreNattMedSittDatum() throws {
        let v = Trends.idunValues(nätter { (k: Int) -> Int? in k == 0 ? nil : (k % 2 == 0 ? 12 : 8) })
        XCTAssertNil(v[.movement]?[idag], "natten utan tal har ingen punkt")
        XCTAssertEqual(v[.movement]?.count, 34)
        let s = Trends.series(.movement, idun: v[.movement] ?? [:], whoop: [:])
        XCTAssertFalse(s.points.contains { (p: Trends.Point) -> Bool in p.day == idag })
        // Som de andra mått som bara ur K18 har ett värde: kortet visar måttets senaste natt med dess datum.
        let kort = MorningCard.day(idag, idun: v)
        let rad = try XCTUnwrap(kort.rows.first { (r: MorningCard.Row) -> Bool in r.measure == .movement })
        XCTAssertEqual(rad.day, idag - 1)
        // Före den äldsta natten med tal finns ingen rad alls.
        let före = MorningCard.day(idag - 40, idun: v)
        XCTAssertNil(före.rows.first { (r: MorningCard.Row) -> Bool in r.measure == .movement })
    }

    func testEnGammalNattUtanRörelseGerIngenRadPåKortet() {
        let gammal = Trends.IdunNight(day: idag, validWindows: 60, rmssd: 50, restingHeartRate: 50,
                                      breathsPerMinute: 14)
        XCTAssertNil(gammal.movementMinutes)
        let kort = MorningCard.day(idag, idun: Trends.idunValues([gammal]))
        XCTAssertFalse(kort.rows.contains { (r: MorningCard.Row) -> Bool in r.measure == .movement })
        XCTAssertTrue(kort.rows.contains { (r: MorningCard.Row) -> Bool in r.measure == .hrv }, "de andra måtten står kvar")
    }
}
