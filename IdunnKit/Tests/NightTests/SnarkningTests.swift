import Foundation
import XCTest
import DemoData
import WhoopFrames
import WhoopImport
@testable import Night

// METOD M44 · BESLUT B54 (J3). Dina snarkminuter per timme sömn som mått i Över tid, och Morgons snarkrad
// bara när natten ligger utanför ditt normalområde. Påhittade nätter, bara tal.

final class SnarkningTests: XCTestCase {
    let idag = WakeDay(daysSince1970: 20_000)

    /// 35 nätter bakåt från idag med `värde(k)` snarkminuter per timme; `nil` = en natt utan ljud.
    func nätter(_ värde: (Int) -> Double?) -> [Trends.IdunNight] {
        (0..<35).map { (k: Int) -> Trends.IdunNight in
            Trends.IdunNight(day: idag - k, validWindows: 60, rmssd: 50, restingHeartRate: 50, breathsPerMinute: 14,
                             snoringPerHour: värde(k), source: .k18)
        }
    }

    // MARK: Måttet

    func testSnarkningÄrEttMåttMedEgetOmrådeUtanLäge() {
        let m = Trends.Measure.snoring
        XCTAssertEqual(m.rawValue, "snoring")
        XCTAssertTrue(m.hasRange)
        XCTAssertFalse(m.rangeFollowsResearch, "formen är ett antagande (METOD M44)")
        XCTAssertFalse(m.hasStatus)
        XCTAssertFalse(m.isLogarithmic)
        XCTAssertFalse(m.isWeekly)
        XCTAssertTrue(m.accepts(0), "noll minuter är ett tal")
        XCTAssertFalse(m.accepts(.nan))
        // Efter minuterna i rörelse, före regelbundenheten.
        XCTAssertEqual(Trends.Measure.allCases,
                       [.hrv, .restingHeartRate, .meanHeartRate, .sleep, .movement, .snoring, .regularity, .breathing,
                        .skinTemperature, .efficiency, .awakeTime, .lightSleep, .deepSleep, .remSleep, .sleepOnset,
                        .sleepWake])
    }

    func testBaraNätterMedLjudHarEnPunktOchEttOmråde() throws {
        let v = Trends.idunValues(nätter { (k: Int) -> Double? in k % 2 == 0 ? 8 : (k == 5 ? nil : 4) })
        XCTAssertEqual(v[.snoring]?.count, 34, "natt 5 saknar ljud: ingen punkt, ingen nolla")
        XCTAssertNil(v[.snoring]?[idag - 5])
        XCTAssertEqual(v[.snoring]?[idag], 8)
        let s = Trends.series(.snoring, idun: v[.snoring] ?? [:], whoop: [:])
        XCTAssertEqual(s.points.count, 34)
        XCTAssertTrue(s.points.allSatisfy { (p: Trends.Point) -> Bool in p.source == .idun })
        XCTAssertNil(s.latest?.status)
        let band = try XCTUnwrap(s.bands.last, "fem veckors nätter med ljud ger ett normalområde")
        XCTAssertEqual(band.day, idag)
        XCTAssertLessThan(band.lower, 6)
        XCTAssertGreaterThan(band.upper, 6)
    }

    func testEnNattUtanLjudGerIngenPunktOchEnGammalNattInte() {
        let ingen = Trends.idunValues(nätter { (_: Int) -> Double? in nil })
        XCTAssertEqual(ingen[.snoring]?.count ?? 0, 0)
        let s = Trends.series(.snoring, idun: ingen[.snoring] ?? [:], whoop: [:])
        XCTAssertTrue(s.points.isEmpty, "Över tid filtrerar bort ett mått utan nätter")
        // Whoops nätter har inget ljud: serien är Idunns.
        XCTAssertNil(Trends.whoopValues(cycles: [], sleeps: [])[.snoring])
    }

    // MARK: Morgons rad

    func testRadenKommerBaraNärNattenLiggerUtanförOmrådet() throws {
        // Fyra veckors nätter kring 4–6 min/h; idag 15: utanför området.
        let basen: (Int) -> Double? = { (k: Int) -> Double? in k == 0 ? 15 : (k % 2 == 0 ? 6 : 4) }
        let kort = MorningCard.day(idag, idun: Trends.idunValues(nätter(basen)))
        let rad = try XCTUnwrap(kort.snoring, "15 min/h är över normalområdet")
        XCTAssertEqual(rad.measure, .snoring)
        XCTAssertEqual(rad.day, idag)
        XCTAssertEqual(rad.value, 15)
        XCTAssertEqual(rad.source, .idun)
        let område = try XCTUnwrap(rad.range)
        XCTAssertGreaterThan(rad.value, område.upperBound)
        XCTAssertFalse(kort.rows.contains { (r: MorningCard.Row) -> Bool in r.measure == .snoring },
                       "raden hör inte till måtten som alltid står på kortet")

        // Inom området: ingen rad.
        let inom = MorningCard.day(idag, idun: Trends.idunValues(nätter { (k: Int) -> Double? in
            k == 0 ? 5 : (k % 2 == 0 ? 8 : 2)
        }))
        XCTAssertNil(inom.snoring, "5 min/h är inom området 3,5–6,5")
        // Under området är också utanför: en natt utan snarkning efter nätter med.
        let under = MorningCard.day(idag, idun: Trends.idunValues(nätter { (k: Int) -> Double? in
            k == 0 ? 0 : (k % 2 == 0 ? 8 : 6)
        }))
        let r2 = try XCTUnwrap(under.snoring)
        XCTAssertLessThan(r2.value, try XCTUnwrap(r2.range).lowerBound)
    }

    func testIngenRadUtanLjudDenNattenEllerUtanOmråde() {
        // Natten saknar ljud: ingen rad, även om en tidigare natt hade ett värde utanför området.
        let utanLjud = MorningCard.day(idag, idun: Trends.idunValues(nätter { (k: Int) -> Double? in
            k == 0 ? nil : (k == 1 ? 15 : (k % 2 == 0 ? 6 : 4))
        }))
        XCTAssertNil(utanLjud.snoring, "raden gäller den här natten, inte en äldre")
        // Färre än sju nätter med ljud före morgonen: inget område, ingen rad.
        let kort = MorningCard.day(idag, idun: Trends.idunValues(nätter { (k: Int) -> Double? in k < 7 ? 15 : nil }))
        XCTAssertNil(kort.snoring, "inget normalområde innan sju nätter med ljud")
        // Ingen natt alls med ljud.
        XCTAssertNil(MorningCard.day(idag, idun: Trends.idunValues(nätter { (_: Int) -> Double? in nil })).snoring)
    }

    func testEnMorgonMedNollSnarkningHarIngenRad() {
        // Alla nätter noll: noll är inom området (SD noll, ingen avvikelse), ingen rad varje morgon.
        let kort = MorningCard.day(idag, idun: Trends.idunValues(nätter { (_: Int) -> Double? in 0 }))
        XCTAssertNil(kort.snoring)
    }

    // MARK: Sammanfattningen

    func testSammanfattningenBärLjudetOchGamlaSammanfattningarAvkodasUtanDet() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false, stages: true)
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        var r = try XCTUnwrap(K18Night.analyze(K18Series(records: n.records), wakeDay: dag,
                                               startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        XCTAssertNil(NightDigest(r).sound, "en natt utan ljud har inget ljud i sammanfattningen")
        XCTAssertNil(NightDigest(r).idunNight.snoringPerHour)

        let tid = Double(n.onset + 1_800)
        let event = NightSound.Event(time: tid, seconds: 6, soundClass: 5, owner: nil, aboveFloor: 22,
                                     clip: NightSound.Clip(stem: "ljud-x", second: 100), woke: true, pulse: true,
                                     movement: false)
        r.sound = NightSound(start: tid - 600, end: tid + 600, levels: [], events: [event], yoursMinutes: 9.5,
                             someoneElseMinutes: 0, unknownMinutes: 0, asleepSeconds: 4_000, coverage: 0.9,
                             snoringPerHour: 7.5, clockReliable: true)
        let d = NightDigest(r)
        let ljud = try XCTUnwrap(d.sound)
        XCTAssertEqual(ljud.snoringPerHour, 7.5)
        XCTAssertEqual(ljud.wakers, [NightSoundDigest.Waker(time: tid, soundClass: 5, owner: nil)])
        XCTAssertEqual(d.idunNight.snoringPerHour, 7.5)
        XCTAssertEqual(Trends.idunValues([d.idunNight])[.snoring]?[d.wakeDay], 7.5)

        // Sparas och läses tillbaka; en äldre sparad sammanfattning utan fältet avkodas ändå.
        let data = try JSONEncoder().encode(d)
        XCTAssertEqual(try JSONDecoder().decode(NightDigest.self, from: data), d)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["sound"])
        json.removeValue(forKey: "sound")
        let gammal = try JSONSerialization.data(withJSONObject: json)
        let avkodad = try JSONDecoder().decode(NightDigest.self, from: gammal)
        XCTAssertNil(avkodad.sound)
        XCTAssertEqual(avkodad.wakeDay, d.wakeDay)
    }
}
