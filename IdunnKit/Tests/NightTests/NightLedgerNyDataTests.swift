import Foundation
import XCTest
import WhoopFrames
@testable import Night

// BESLUT B159 · METOD M87. En natt räknas om när telefonen har fler minuter med K18 i nattens fönster än natten
// räknades på, oavsett vem som hämtade datan eller hur sent den kom. En pågående natt bara när appen är öppen.
// Rena värden: dagar, klockslag och minuter; inga poster.

final class NightLedgerNyDataTests: XCTestCase {
    let zon = 3600
    let bygge = "42"

    func dag(_ d: Int) -> DayLog.Day { DayLog.Day(year: 2026, month: 11, day: d) }
    func natt(_ d: Int) -> WakeDay { WakeDay(daysSince1970: dag(d).daysSince1970) }
    func tid(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        DayLog.date(of: dag(d), hour: h, minute: m, utcOffsetSeconds: zon)
    }
    func stammar(_ dagar: [Int]) -> [String] { dagar.map { DayLog.stem(for: dag($0)) } }

    /// Unix-minuterna från `a` till (inte med) `b`.
    func minuter(_ a: Date, _ b: Date) -> Set<Int> {
        Set(Int(a.timeIntervalSince1970) / 60..<Int(b.timeIntervalSince1970) / 60)
    }

    func post(_ d: Int, räknad: Date, preliminär: Bool = false, satt: Bool = false, täckt: Int?) -> NightLedger.Entry {
        NightLedger.Entry(build: bygge, wakeDay: natt(d), computedAt: räknad, preliminary: preliminär,
                          settled: satt, digest: nil, coverage: täckt)
    }

    /// Jobben för natten som slutar dag 11, med dygnsfilerna 10–11 och posten `p`.
    func jobb(_ p: NightLedger.Entry, nu: Date, minuter m: Set<Int>?, vaken: Bool = true,
              tvingad: Set<WakeDay> = []) -> [NightLedger.Job] {
        NightLedger.jobs(dayStems: stammar([10, 11]), entries: [p.wakeDay: p], build: bygge, now: nu,
                         utcOffsetSeconds: zon, minutes: m, awake: vaken, forced: tvingad)
            .filter { $0.wakeDay == natt(11) }
    }

    func testFönstretRäknasFrånKväll18TillMiddag12() {
        let m = minuter(tid(10, 17, 50), tid(11, 12, 10))
        XCTAssertEqual(NightLedger.coveredMinutes(natt(11), minutes: m, utcOffsetSeconds: zon), 18 * 60)
        XCTAssertEqual(NightLedger.coveredMinutes(natt(11), minutes: minuter(tid(11, 11, 59), tid(11, 12, 1)),
                                                  utcOffsetSeconds: zon), 1, "11:59 med, 12:00 inte")
        XCTAssertEqual(NightLedger.coveredMinutes(natt(11), minutes: [], utcOffsetSeconds: zon), 0)
    }

    func testNattenSomKomIkappEfterAttDenRäknatsRäknasOmNärAppenÖppnas() {
        // Formen ur natten 23→24 nov: natten räknades 08:02 med data till strax före midnatt; synken var klar 08:04,
        // och appen öppnades 08:13. Inte 30 minuter än, men nattens fönster har fått nya minuter.
        let då = minuter(tid(10, 18), tid(10, 23, 50))
        let p = post(11, räknad: tid(11, 8, 2), preliminär: true,
                     täckt: NightLedger.coveredMinutes(natt(11), minutes: då, utcOffsetSeconds: zon))
        let nu = minuter(tid(10, 18), tid(11, 8, 13))
        XCTAssertEqual(jobb(p, nu: tid(11, 8, 13), minuter: då), [], "samma minuter: inget nytt")
        XCTAssertEqual(jobb(p, nu: tid(11, 8, 13), minuter: nu),
                       [NightLedger.Job(wakeDay: natt(11), preliminary: true, settled: false)])
    }

    func testEnPågåendeNattRäknasInteOmIBakgrunden() {
        let p = post(11, räknad: tid(11, 2), preliminär: true, täckt: 60)
        let nu = minuter(tid(10, 18), tid(11, 7))
        XCTAssertEqual(jobb(p, nu: tid(11, 7), minuter: nu, vaken: false), [], "ny data, men appen är inte öppen")
        XCTAssertEqual(jobb(p, nu: tid(11, 7), minuter: nil, vaken: false), [], "och inte efter 30 minuter heller")
        XCTAssertEqual(jobb(p, nu: tid(11, 7), minuter: nil, vaken: true),
                       [NightLedger.Job(wakeDay: natt(11), preliminary: true, settled: false)],
                       "öppen och äldre än 30 minuter: som förut")
    }

    func testEnFärdigNattMedNyDataRäknasOmOcksåIBakgrunden() {
        // Räknad kl 13 med en lucka; en synk på eftermiddagen fyllde luckan.
        let då = minuter(tid(10, 22), tid(11, 3))
        let p = post(11, räknad: tid(11, 13),
                     täckt: NightLedger.coveredMinutes(natt(11), minutes: då, utcOffsetSeconds: zon))
        XCTAssertEqual(jobb(p, nu: tid(11, 17), minuter: då, vaken: false), [])
        XCTAssertEqual(jobb(p, nu: tid(11, 17), minuter: minuter(tid(10, 22), tid(11, 8)), vaken: false),
                       [NightLedger.Job(wakeDay: natt(11), preliminary: false, settled: false)])
    }

    func testNyDataUtanförFönstretRäknarInteOm() {
        let då = minuter(tid(10, 22), tid(11, 8))
        let p = post(11, räknad: tid(11, 13),
                     täckt: NightLedger.coveredMinutes(natt(11), minutes: då, utcOffsetSeconds: zon))
        XCTAssertEqual(jobb(p, nu: tid(11, 17), minuter: då.union(minuter(tid(11, 13), tid(11, 17)))), [],
                       "eftermiddagen hör till nästa natts fönster först kl 18")
    }

    func testOkändaMinuterRäknarInteOm() {
        let p = post(11, räknad: tid(11, 13), täckt: nil)
        XCTAssertEqual(jobb(p, nu: tid(11, 17), minuter: nil), [], "statusen inte läst: regeln om ny data vilar")
        XCTAssertEqual(jobb(p, nu: tid(11, 17), minuter: minuter(tid(10, 22), tid(11, 6))).count, 1,
                       "en post utan täckning prövas en gång mot minuterna")
    }

    func testRäknaOmNätternaTvingarFram() {
        let p = post(11, räknad: tid(11, 13), täckt: 600)
        XCTAssertEqual(jobb(p, nu: tid(11, 17), minuter: nil), [])
        XCTAssertEqual(jobb(p, nu: tid(11, 17), minuter: nil, tvingad: [natt(11)]),
                       [NightLedger.Job(wakeDay: natt(11), preliminary: false, settled: false)])
    }

    func testPostenBärTäckningenDenRäknadesPå() {
        var sparade: [NightLedger.Entry] = []
        let m = minuter(tid(10, 23), tid(11, 7))
        NightLedger.computeDue(dayStems: stammar([10, 11]), entries: [:], build: bygge, now: tid(11, 13),
                               utcOffsetSeconds: zon, load: { _ in nil }, save: { sparade.append($0) }, minutes: m)
        let p = sparade.first { $0.wakeDay == natt(11) }
        XCTAssertEqual(p?.coverage, 8 * 60)
        XCTAssertEqual(jobb(p!, nu: tid(11, 14), minuter: m), [], "räknad på samma minuter: inget att göra")
        let data = try! JSONEncoder().encode(p!)
        XCTAssertEqual(try JSONDecoder().decode(NightLedger.Entry.self, from: data), p)
    }

    func testEnÄldrePostUtanTäckningGårAttLäsa() throws {
        let gammal = #"{"build":"42","wakeDayNumber":20403,"computedAt":0,"preliminary":false,"settled":true}"#
        let e = try JSONDecoder().decode(NightLedger.Entry.self, from: Data(gammal.utf8))
        XCTAssertNil(e.coverage)
    }
}
