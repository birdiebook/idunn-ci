import Foundation
import XCTest
import HeartRate
import WhoopFrames
@testable import Night

// METOD M28 · METOD M27. Zonerna vid dygnsfönstret kl 12–12, ur sidofilerna
// (huvud utan tid, zonrader med tid). Påhittade rader, inga värden.

final class DayZonesTests: XCTestCase {

    func dag(_ y: Int, _ m: Int, _ d: Int) -> DayLog.Day { DayLog.Day(year: y, month: m, day: d) }

    func wake(_ y: Int, _ m: Int, _ d: Int) -> WakeDay { WakeDay(daysSince1970: dag(y, m, d).daysSince1970) }

    /// Sidofilen som appen skriver den: huvudet, och zonrader med tid.
    func sida(header: Int?, ändringar: [(Date, Int)] = []) -> RecordingLog.Contents {
        var d = Data()
        if let h = header { d.append(RecordingLog.header(utcOffsetSeconds: h)) }
        for (t, z) in ändringar { d.append(RecordingLog.zoneChange(utcOffsetSeconds: z, at: t)) }
        return RecordingLog.decode(d)
    }

    func testUtanSidofilerGällerReservzonenBådaGångerna() {
        let z = DayZones(days: [])
        XCTAssertTrue(z.isEmpty)
        XCTAssertNil(z.offset(at: Date()))
        let w = z.windowOffsets(wakeDay: wake(2026, 10, 14), fallback: 7200)
        XCTAssertEqual(w.start, 7200)
        XCTAssertEqual(w.end, 7200)
    }

    func testBaraEttHuvudGällerFrånFilensMidnatt() {
        let z = DayZones(days: [(stem: "dygn-2026-10-13", contents: sida(header: 3600))])
        let midnatt = DayLog.date(of: dag(2026, 10, 13), utcOffsetSeconds: 3600)
        XCTAssertEqual(z.offset(at: midnatt), 3600)
        XCTAssertEqual(z.offset(at: midnatt.addingTimeInterval(86_400 * 3)), 3600)
        XCTAssertEqual(z.offset(at: midnatt.addingTimeInterval(-86_400)), 3600, "före första raden gäller den första")
        let w = z.windowOffsets(wakeDay: wake(2026, 10, 14), fallback: 7200)
        XCTAssertEqual(w.start, 3600)
        XCTAssertEqual(w.end, 3600)
    }

    func testSommartidenSlutarMittIFönstret() {
        // Söndag 25 oktober 2026: klockan 03:00 (UTC+2) blir 02:00 (UTC+1).
        let byte = DayLog.date(of: dag(2026, 10, 25), hour: 1, utcOffsetSeconds: 0)
        let z = DayZones(days: [
            (stem: "dygn-2026-10-24", contents: sida(header: 7200)),
            (stem: "dygn-2026-10-25", contents: sida(header: 7200, ändringar: [(byte, 3600)])),
        ])
        let w = z.windowOffsets(wakeDay: wake(2026, 10, 25), fallback: 3600)
        XCTAssertEqual(w.start, 7200, "kl 12 lördagen är sommartid")
        XCTAssertEqual(w.end, 3600, "kl 12 söndagen är normaltid")
        // Dagen efter ligger båda ändpunkterna i normaltid.
        let nästa = z.windowOffsets(wakeDay: wake(2026, 10, 26), fallback: 3600)
        XCTAssertEqual(nästa.start, 3600)
        XCTAssertEqual(nästa.end, 3600)
    }

    func testEnResaFörEnNyFilIEnAnnanZon() {
        // Dygn 10 i UTC+2, dygn 11 öppnas i UTC−5: fönstret börjar i den ena
        // och slutar i den andra.
        let z = DayZones(days: [
            (stem: "dygn-2026-10-10", contents: sida(header: 7200)),
            (stem: "dygn-2026-10-11", contents: sida(header: -18_000)),
        ])
        let w = z.windowOffsets(wakeDay: wake(2026, 10, 11), fallback: 7200)
        XCTAssertEqual(w.start, 7200)
        XCTAssertEqual(w.end, -18_000)
    }

    func testFilerIGodtyckligOrdningOchZonraderSorterasPåTid() {
        let a = DayLog.date(of: dag(2026, 3, 29), hour: 1, utcOffsetSeconds: 0)
        // Den senare filen först i listan.
        let z = DayZones(days: [
            (stem: "dygn-2026-03-29", contents: sida(header: 3600, ändringar: [(a, 7200)])),
            (stem: "dygn-2026-03-28", contents: sida(header: 3600)),
        ])
        XCTAssertEqual(z.offset(at: a.addingTimeInterval(-60)), 3600)
        XCTAssertEqual(z.offset(at: a), 7200)
        XCTAssertEqual(z.offset(at: a.addingTimeInterval(3600)), 7200)
    }

    func testEnStamUtanDatumGerBaraDeTideradeRaderna() {
        let t = DayLog.date(of: dag(2026, 10, 13), hour: 5, utcOffsetSeconds: 0)
        let z = DayZones(days: [(stem: "annat", contents: sida(header: 3600, ändringar: [(t, 7200)]))])
        XCTAssertEqual(z.entries.count, 1, "huvudet utan datum i stammen har ingen tid")
        XCTAssertEqual(z.offset(at: t), 7200)
    }
}
