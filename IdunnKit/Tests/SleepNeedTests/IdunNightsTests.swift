import Foundation
import XCTest
import Night
import Pass
@testable import WhoopImport
@testable import SleepNeed

// Alla nätter nedan är påhittade (CLAUDE.md §Dataregeln). BESLUT B65, METOD M53.

final class IdunNightsTests: XCTestCase {
    func testDagFörDagGerKvällensPlanOchSkulden() throws {
        // Tolv nätter med en som saknas (dag 106) och ett pass dag 103 kl 12.
        let sov: [Double] = [430, 410, 470, 380, 500, 0, 450, 420, 400, 480, 440, 455]
        let nätter = (0..<12).compactMap { (i: Int) -> SleepNight? in
            sov[i] > 0 ? SleepNight(day: 101 + i, asleepMinutes: sov[i], periodMinutes: 480, onsetMinute: -60,
                                    wakeMinute: 420) : nil
        }
        let pass = [PassDay(day: 103, stopMinute: 720, load: 500)]
        let dagar = SleepNeed.days(nights: nätter, passes: pass)
        let bok = SleepNeed.ledger(nights: nätter, passes: pass, base: 480)
        XCTAssertEqual(dagar.map(\.day), Array(101...112))
        XCTAssertEqual(dagar.map(\.debtMinutes), bok.map(\.debtMinutes))
        for d in dagar {
            if let före = SleepNeed.tonight(nights: nätter, passes: pass, base: 480, day: d.day) {
                XCTAssertEqual(d.needMinutes, före.needMinutes, accuracy: 1e-9, "dag \(d.day)")
            }
            XCTAssertEqual(d.tonight, SleepNeed.tonight(nights: nätter, passes: pass, base: 480, day: d.day + 1))
        }
        // Passet dag 103 ger tillägg natten som slutar dag 104: 500 × 0,01 = 5 min.
        XCTAssertEqual(try XCTUnwrap(dagar.first { $0.day == 104 }).passMinutes, 5, accuracy: 1e-9)
    }

    func testWhoopsGrundbehovUrExporten() {
        // Tio påhittade dygn: strain 4–13, behov − skuld 500–509; tuppluren och första dygnet (ingen gårdag) räknas inte.
        let t0 = Date(timeIntervalSince1970: 1_900_000_000)
        var cykler: [Cycle] = []
        var pass: [Sleep] = []
        for i in 0..<10 {
            let start = t0.addingTimeInterval(Double(i) * 86_400)
            cykler.append(Cycle(start: start, end: start.addingTimeInterval(86_400), utcOffsetSeconds: 3600,
                                recoveryScore: nil, restingHeartRate: nil, hrv: nil, skinTempCelsius: nil,
                                bloodOxygenPercent: nil, respiratoryRate: nil, dayStrain: Double(4 + i),
                                sleepOnset: nil, wakeOnset: nil))
            pass.append(Sleep(cycleStart: start, utcOffsetSeconds: 3600, onset: start,
                              wake: start.addingTimeInterval(28_800), isNap: false, performancePercent: nil,
                              respiratoryRate: nil, asleepMinutes: nil, inBedMinutes: nil, lightMinutes: nil,
                              deepMinutes: nil, remMinutes: nil, awakeMinutes: nil, needMinutes: 530 + i,
                              debtMinutes: 30, efficiencyPercent: nil, consistencyPercent: nil))
        }
        var lur = pass[5]
        lur.isNap = true
        lur.needMinutes = 900
        let export = WhoopExport(cycles: cykler.reversed(), sleeps: pass + [lur], journal: [])
        // Paren: gårdagens strain 4…12 mot 501…509; lägsta fjärdedelen strain ≤ 6 ger 501, 502, 503.
        XCTAssertEqual(SleepNeed.whoopBase(export), 502)
        XCTAssertNil(SleepNeed.whoopBase(WhoopExport(cycles: cykler, sleeps: Array(pass.prefix(5)), journal: [])))
    }

    func testIdunsNätterBaraK18MedPeriodOchLängstaSovtiden() throws {
        let zon = 3600
        let dag = WakeDay(daysSince1970: 20_000)
        // Insomning 22.30 och uppvaknande 06.45 lokal tid dag 20 000, som sömnperiod.
        let midnatt = Double(20_000) * 86_400 - Double(zon)
        let period = try XCTUnwrap(Regularity.Episode.idun(onset: Date(timeIntervalSince1970: midnatt - 90 * 60),
                                                         wake: Date(timeIntervalSince1970: midnatt + 405 * 60),
                                                         utcOffsetSeconds: zon, sleepMinutes: 450))
        let urPerioden = Trends.IdunNight(day: dag, validWindows: 1, rmssd: nil, restingHeartRate: nil,
                                          breathsPerMinute: nil, sleepHours: 7.5, sleepEpisode: period, source: .k18)
        let urMinuterna = Trends.IdunNight(day: dag + 1, validWindows: 40, rmssd: nil, restingHeartRate: nil,
                                           breathsPerMinute: nil, sleepHours: 7, source: .k18,
                                           onsetMinutes: -30, wakeMinutes: 420)
        let kortare = Trends.IdunNight(day: dag + 1, validWindows: 40, rmssd: nil, restingHeartRate: nil,
                                       breathsPerMinute: nil, sleepHours: 6, source: .k18,
                                       onsetMinutes: -30, wakeMinutes: 420)
        let gammal = Trends.IdunNight(day: dag + 2, validWindows: 40, rmssd: nil, restingHeartRate: nil,
                                      breathsPerMinute: nil, sleepHours: 7, source: .notification,
                                      onsetMinutes: -30, wakeMinutes: 420)
        let n = SleepNeed.nights([kortare, gammal, urMinuterna, urPerioden])
        XCTAssertEqual(n.map(\.day), [20_000, 20_001])
        XCTAssertEqual(n[0].onsetMinute, -90, accuracy: 1e-9)
        XCTAssertEqual(n[0].wakeMinute, 405, accuracy: 1e-9)
        XCTAssertEqual(n[0].periodMinutes, 495, accuracy: 1e-9)
        XCTAssertEqual(n[0].asleepMinutes, 450, accuracy: 1e-9)
        XCTAssertEqual(n[1].asleepMinutes, 420, accuracy: 1e-9, "längsta sovtiden samma dag")
        // Utan sovtid eller period: ingen natt.
        let utan = Trends.IdunNight(day: dag, validWindows: 40, rmssd: nil, restingHeartRate: nil, breathsPerMinute: nil,
                                    source: .k18)
        XCTAssertNil(SleepNight(utan))
    }
}
