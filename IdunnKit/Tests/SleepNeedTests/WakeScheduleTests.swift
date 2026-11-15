import XCTest
@testable import SleepNeed

/// BESLUT B102 · BESLUT B103 · METOD M53. Schemat för när användaren går upp och påminnelsen före läggdags. Nätterna är
/// påhittade (samma som i `SleepNeedTests`).
final class WakeScheduleTests: XCTestCase {
    private let nätter: [SleepNight] = [
        SleepNight(day: 100, asleepMinutes: 430, periodMinutes: 470, onsetMinute: -30, wakeMinute: 440),
        SleepNight(day: 101, asleepMinutes: 430, periodMinutes: 465, onsetMinute: -20, wakeMinute: 445),
        SleepNight(day: 103, asleepMinutes: 520, periodMinutes: 555, onsetMinute: -60, wakeMinute: 495),
        SleepNight(day: 104, asleepMinutes: 490, periodMinutes: 520, onsetMinute: -40, wakeMinute: 480),
    ]
    private let utc: TimeZone = TimeZone(secondsFromGMT: 0)!

    private func tid(dag: Int, minut: Double) -> Date {
        Date(timeIntervalSince1970: Double(dag) * 86_400 + minut * 60)
    }

    func testVeckodagenFörEnDag() {
        XCTAssertEqual(WakeSchedule.weekday(ofDay: 0), 3, "1970-01-01 var en torsdag")
        XCTAssertEqual(WakeSchedule.weekday(ofDay: 4), 0, "1970-01-05 var en måndag")
        XCTAssertEqual(WakeSchedule.weekday(ofDay: 3), 6)
        XCTAssertEqual(WakeSchedule.weekday(ofDay: -1), 2)
        XCTAssertEqual(WakeSchedule.weekday(ofDay: 20_407), 5, "2025-11-15 var en lördag")
    }

    func testTidenSomGällerEnMorgon() {
        var s = WakeSchedule()
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.minute(wakeDay: 105))
        s = s.setting(390, weekdays: [0, 1, 2, 3, 4]).setting(510, weekdays: [5, 6])
        XCTAssertFalse(s.isEmpty)
        XCTAssertEqual(s.minute(wakeDay: 105), 390, "dag 105 är en torsdag")
        XCTAssertEqual(s.minute(wakeDay: 107), 510, "dag 107 är en lördag")
        XCTAssertEqual(s.group(of: 0), [0, 1, 2, 3, 4])
        XCTAssertEqual(s.group(of: 6), [5, 6])
        // Engångstiden gäller bara sin morgon, och veckodagens tid står kvar under den.
        s = s.settingOnce(300, wakeDay: 105)
        XCTAssertEqual(s.minute(wakeDay: 105), 300)
        XCTAssertEqual(s.weekdayMinute(wakeDay: 105), 390)
        XCTAssertEqual(s.minute(wakeDay: 112), 390, "torsdagen veckan efter följer schemat")
        s = s.settingOnce(nil, wakeDay: 105)
        XCTAssertEqual(s.minute(wakeDay: 105), 390)
        // Återställda dagar räknas från det vanliga uppvaknandet.
        s = s.setting(nil, weekdays: [5, 6])
        XCTAssertNil(s.minute(wakeDay: 107))
        XCTAssertEqual(s.group(of: 5), [5, 6], "dagar utan tid hör ihop")
        XCTAssertEqual(WakeSchedule().group(of: 2), [0, 1, 2, 3, 4, 5, 6])
    }

    func testSchematSparasOchLäses() throws {
        let s = WakeSchedule(every: 420).setting(nil, weekdays: [6]).settingOnce(300, wakeDay: 20_500)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(WakeSchedule.self, from: data), s)
        let tomt = try JSONDecoder().decode(WakeSchedule.self, from: try JSONEncoder().encode(WakeSchedule()))
        XCTAssertTrue(tomt.isEmpty)
        XCTAssertEqual(WakeSchedule(weekdays: [390]).weekdays.count, 7, "en för kort lista fylls ut")
    }

    func testDagarnaFöljerSchemat() throws {
        let utan = SleepNeed.days(nights: nätter, passes: [], whoopBase: 510)
        let med = SleepNeed.days(nights: nätter, passes: [], whoopBase: 510, wakeMinute: 390)
        // En tid för alla dagar är den enda väcktiden (BESLUT B74), och ett tomt schema det vanliga uppvaknandet.
        XCTAssertEqual(SleepNeed.days(nights: nätter, passes: [], whoopBase: 510, schedule: WakeSchedule(every: 390)), med)
        XCTAssertEqual(SleepNeed.days(nights: nätter, passes: [], whoopBase: 510, schedule: WakeSchedule()), utan)
        // Bara torsdagar: kvällen efter dag 104 (upp dag 105, en torsdag) följer tiden, kvällen före inte.
        let torsdag = SleepNeed.days(nights: nätter, passes: [], whoopBase: 510,
                                     schedule: WakeSchedule().setting(390, weekdays: [3]))
        XCTAssertEqual(torsdag[4].tonight, med[4].tonight)
        XCTAssertEqual(torsdag[3].tonight, utan[3].tonight)
        XCTAssertEqual(try XCTUnwrap(torsdag[4].tonight).wakeMinute, 390)
        // Engångstiden för dag 104 flyttar bara den kvällens läggdags; behovet och skulden ändras inte.
        let engång = SleepNeed.days(nights: nätter, passes: [], whoopBase: 510,
                                    schedule: WakeSchedule().settingOnce(300, wakeDay: 104))
        XCTAssertEqual(try XCTUnwrap(engång[3].tonight).wakeMinute, 300)
        XCTAssertEqual(engång[4].tonight, utan[4].tonight)
        XCTAssertEqual(engång.map(\.needMinutes), utan.map(\.needMinutes))
        XCTAssertEqual(engång.map(\.debtMinutes), utan.map(\.debtMinutes))
    }

    func testKlockslagetFörEnPåminnelse() {
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: -87).day, 9)
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: -87).minuteOfDay, 22 * 60 + 33)
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: 5).day, 10)
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: 5).minuteOfDay, 5)
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: -1_440).day, 9)
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: -1_440).minuteOfDay, 0)
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: -1_441).day, 8)
        XCTAssertEqual(BedtimeReminder.wallClock(day: 10, minute: -1_441).minuteOfDay, 1_439)
    }

    func testPåminnelsernaFramförNu() throws {
        let bas = SleepNeed.baseNeed(whoopBase: nil).minutes
        let plan = try XCTUnwrap(SleepNeed.tonight(nights: nätter, passes: [], base: bas, day: 105))
        let före = SleepNeedRules.bedtimeReminderLeadMinutes
        XCTAssertEqual(före, 15)
        // Mitt på dagen efter natten som slutade dag 104: kvällens påminnelse och tre nätter i reserv.
        let p = SleepNeed.reminders(nights: nätter, passes: [], schedule: WakeSchedule(),
                                    now: tid(dag: 104, minut: 720), timeZone: utc)
        XCTAssertEqual(p.map(\.wakeDay), [105, 106, 107])
        XCTAssertEqual(p[0].bedtimeMinute, plan.bestBedtimeMinute, accuracy: 1e-9)
        XCTAssertEqual(p[0].fireMinute, plan.bestBedtimeMinute - 15, accuracy: 1e-9)
        XCTAssertLessThan(p[0].bedtimeMinute, 0, "läggdags före midnatt")
        XCTAssertEqual(p[0].fire.day, 104)
        // En minut före påminnelsen finns den kvar; en minut efter är den borta, och reserven står kvar.
        let strax = SleepNeed.reminders(nights: nätter, passes: [], schedule: WakeSchedule(),
                                        now: tid(dag: 105, minut: p[0].fireMinute - 1), timeZone: utc)
        XCTAssertEqual(strax.first?.wakeDay, 105)
        let efter = SleepNeed.reminders(nights: nätter, passes: [], schedule: WakeSchedule(),
                                        now: tid(dag: 105, minut: p[0].fireMinute + 1), timeZone: utc)
        XCTAssertEqual(efter.first?.wakeDay, 106)
        // Schemat flyttar läggdags och påminnelsen med den: torsdag (dag 105) upp 06.30.
        let schema = WakeSchedule().setting(390, weekdays: [3])
        let tidig = try XCTUnwrap(SleepNeed.tonight(nights: nätter, passes: [], base: bas, day: 105, wakeMinute: 390))
        let s = SleepNeed.reminders(nights: nätter, passes: [], schedule: schema,
                                    now: tid(dag: 104, minut: 720), timeZone: utc)
        XCTAssertEqual(s[0].bedtimeMinute, tidig.bestBedtimeMinute, accuracy: 1e-9)
        XCTAssertLessThan(s[0].fireMinute, p[0].fireMinute)
        XCTAssertEqual(s[1].fireMinute, p[1].fireMinute, accuracy: 1e-9, "fredagen följer inte torsdagens tid")
        // Zonen avgör vilken dag det är: kl 12 UTC dag 104 är redan dag 105 i en zon 13 h före.
        let öst: TimeZone = TimeZone(secondsFromGMT: 13 * 3_600)!
        let ö = SleepNeed.reminders(nights: nätter, passes: [], schedule: WakeSchedule(),
                                    now: tid(dag: 104, minut: 720), timeZone: öst)
        XCTAssertEqual(ö.map(\.wakeDay), [106, 107, 108])
        // Utan nätter finns ingen plan och ingen påminnelse.
        XCTAssertTrue(SleepNeed.reminders(nights: [], passes: [], schedule: WakeSchedule(),
                                          now: tid(dag: 104, minut: 720), timeZone: utc).isEmpty)
    }
}
