import Foundation
import XCTest
@testable import Pass

// BESLUT B158 · METOD M85. Adaptern mellan en tid och nattens tidshjul. Allt nedan är påhittat.

final class PassClockTests: XCTestCase {
    func zon(_ id: String) -> TimeZone { TimeZone(identifier: id) ?? TimeZone.current }

    func kal(_ id: String) -> Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = zon(id)
        return k
    }

    func tid(_ id: String, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        kal(id).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) ?? Date.distantPast
    }

    func testHjulKringMiddagOchMidnatt() {
        let z: TimeZone = zon("UTC")
        XCTAssertEqual(PassClock.wheelMinutes(tid("UTC", 2027, 3, 10, 0, 0), timeZone: z), 0)
        XCTAssertEqual(PassClock.wheelMinutes(tid("UTC", 2027, 3, 10, 11, 59), timeZone: z), 719)
        XCTAssertEqual(PassClock.wheelMinutes(tid("UTC", 2027, 3, 10, 12, 0), timeZone: z), -720)
        XCTAssertEqual(PassClock.wheelMinutes(tid("UTC", 2027, 3, 10, 23, 59), timeZone: z), -1)
        XCTAssertEqual(PassClock.lowest, -720)
        XCTAssertEqual(PassClock.highest, 719)
    }

    func testKlockslagetFårDenNärmasteDagen() {
        let z: TimeZone = zon("UTC")
        // Referens 23:50: klockslaget 00:10 är 20 minuter bort dagen efter, inte 23 h 40 dagen före.
        let ref: Date = tid("UTC", 2027, 3, 10, 23, 50)
        XCTAssertEqual(PassClock.date(wheelMinutes: 10, near: ref, timeZone: z), tid("UTC", 2027, 3, 11, 0, 10))
        // Referens 00:10: klockslaget 23:50 (hjulets −10) ligger dagen före.
        let ref2: Date = tid("UTC", 2027, 3, 11, 0, 10)
        XCTAssertEqual(PassClock.date(wheelMinutes: -10, near: ref2, timeZone: z), tid("UTC", 2027, 3, 10, 23, 50))
        // Samma dag när klockslaget ligger nära.
        XCTAssertEqual(PassClock.date(wheelMinutes: 600, near: ref2, timeZone: z), tid("UTC", 2027, 3, 11, 10, 0))
        // Runt kl 12: hjulets 719 (11:59) och −720 (12:00) från referens 12:00.
        let middag: Date = tid("UTC", 2027, 3, 10, 12, 0)
        XCTAssertEqual(PassClock.date(wheelMinutes: 719, near: middag, timeZone: z), tid("UTC", 2027, 3, 10, 11, 59))
        XCTAssertEqual(PassClock.date(wheelMinutes: -720, near: middag, timeZone: z), middag)
    }

    func testFramOchTillbakaGerSammaKlockslag() {
        let z: TimeZone = zon("Europe/Stockholm")
        let ref: Date = tid("Europe/Stockholm", 2027, 6, 1, 13, 20)
        for m in stride(from: PassClock.lowest, through: PassClock.highest, by: 37) {
            let t: Date = PassClock.date(wheelMinutes: m, near: ref, timeZone: z)
            XCTAssertEqual(PassClock.wheelMinutes(t, timeZone: z), m)
            XCTAssertLessThanOrEqual(abs(t.timeIntervalSince(ref)), 13 * 3600)
        }
    }

    func testSommartidsbyteHållerKlockslagetIZonen() {
        // Sverige 2027: klockan går från 02:00 till 03:00 natten mot söndag 28 mars.
        let z: TimeZone = zon("Europe/Stockholm")
        let ref: Date = tid("Europe/Stockholm", 2027, 3, 28, 6, 0)
        // 22:00 kvällen före är väggklockan 22:00, och bara 7 timmar före 06:00 den natten.
        let kväll: Date = PassClock.date(wheelMinutes: -120, near: ref, timeZone: z)
        XCTAssertEqual(kväll, tid("Europe/Stockholm", 2027, 3, 27, 22, 0))
        XCTAssertEqual(ref.timeIntervalSince(kväll), 7 * 3600)
        XCTAssertEqual(PassClock.date(wheelMinutes: 480, near: ref, timeZone: z),
                       tid("Europe/Stockholm", 2027, 3, 28, 8, 0))
        // Klockslaget som inte finns (02:30) blir något efter hoppet, aldrig en dag bort.
        let hopp: Date = PassClock.date(wheelMinutes: 150, near: ref, timeZone: z)
        XCTAssertLessThan(abs(hopp.timeIntervalSince(ref)), 6 * 3600)
        // Hösten (31 oktober, tillbaka från 03:00 till 02:00): 01:00 och 05:00 är rätt klockslag.
        let höst: Date = tid("Europe/Stockholm", 2027, 10, 31, 4, 0)
        XCTAssertEqual(PassClock.wheelMinutes(PassClock.date(wheelMinutes: 60, near: höst, timeZone: z), timeZone: z), 60)
        XCTAssertEqual(PassClock.wheelMinutes(PassClock.date(wheelMinutes: 300, near: höst, timeZone: z), timeZone: z), 300)
    }

    func testAttSättaKantenKlampasSomFlyttad() {
        let nu: Date = Date(timeIntervalSince1970: 1_800_000_000)
        let start: Date = nu.addingTimeInterval(-3600)
        let stopp: Date = nu.addingTimeInterval(-1800)
        let g = PassEdit.Limits(start: start, stop: stopp, now: nu)
        XCTAssertEqual(PassEdit.set(start: start, stop: stopp, edge: .start, to: start.addingTimeInterval(-600),
                                    limits: g).start, start.addingTimeInterval(-600))
        // Mer än en timme utanför, och aldrig efter nu.
        XCTAssertEqual(PassEdit.set(start: start, stop: stopp, edge: .start, to: start.addingTimeInterval(-9000),
                                    limits: g).start, g.earliest)
        XCTAssertEqual(PassEdit.set(start: start, stop: stopp, edge: .stop, to: nu.addingTimeInterval(3600),
                                    limits: g).stop, g.latest)
        // Minst en minut: Start efter Stopp hamnar en minut före Stopp.
        XCTAssertEqual(PassEdit.set(start: start, stop: stopp, edge: .start, to: stopp.addingTimeInterval(600),
                                    limits: g).start, stopp.addingTimeInterval(-PassEdit.shortestSeconds))
        // `moved` är samma sak med en flytt.
        XCTAssertEqual(PassEdit.moved(start: start, stop: stopp, edge: .stop, minutes: 5, limits: g).stop,
                       PassEdit.set(start: start, stop: stopp, edge: .stop, to: stopp.addingTimeInterval(300),
                                    limits: g).stop)
    }
}
