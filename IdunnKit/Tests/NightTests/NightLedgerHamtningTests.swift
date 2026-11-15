import Foundation
import XCTest
import WhoopFrames
@testable import Night

// PLAN.md A3. Utan Whoop-appen kommer nattens data med Idunns egna hämtningar, och en hämtning kan sluta efter att
// natten räknats färdigt. `NightLedger.jobs(fetches:)` räknar då om natten direkt, om hämtningen hamnade i en
// dygnsfil natten läser. Rena värden: dagar, klockslag och hämtningarnas sluttider.

final class NightLedgerHamtningTests: XCTestCase {
    let zon = 3600
    let bygge = "42"

    func dag(_ d: Int) -> DayLog.Day { DayLog.Day(year: 2026, month: 11, day: d) }
    func natt(_ d: Int) -> WakeDay { WakeDay(daysSince1970: dag(d).daysSince1970) }
    func tid(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        DayLog.date(of: dag(d), hour: h, minute: m, utcOffsetSeconds: zon)
    }
    func stammar(_ dagar: [Int]) -> [String] { dagar.map { DayLog.stem(for: dag($0)) } }

    func post(_ d: Int, räknad: Date, preliminär: Bool = false, satt: Bool = false) -> NightLedger.Entry {
        NightLedger.Entry(build: bygge, wakeDay: natt(d), computedAt: räknad, preliminary: preliminär,
                          settled: satt, digest: nil)
    }

    /// Jobben för natten som slutar dag 11, med dygnsfilerna 10–13 och posten `p`.
    func jobb(_ p: NightLedger.Entry, nu: Date, hämtningar: [Date]) -> [NightLedger.Job] {
        NightLedger.jobs(dayStems: stammar([10, 11, 12, 13]), entries: [p.wakeDay: p], build: bygge, now: nu,
                         utcOffsetSeconds: zon, fetches: hämtningar).filter { $0.wakeDay == natt(11) }
    }

    func testEnHämtningDagenEfterEfterAttNattenSattSigRäknarOmDen() {
        // Natten satt sig kl 12 dag 12 och räknades då; hämtningen slutade kl 15 dag 12.
        let p = post(11, räknad: tid(12, 12, 5), satt: true)
        XCTAssertEqual(jobb(p, nu: tid(12, 18), hämtningar: []), [], "utan hämtning: inget att göra")
        XCTAssertEqual(jobb(p, nu: tid(12, 18), hämtningar: [tid(12, 15)]),
                       [NightLedger.Job(wakeDay: natt(11), preliminary: false, settled: true)])
    }

    func testEnHämtningPåEftermiddagenRäknarOmDenFärdigaNattenDirekt() {
        // Natten räknades kl 13 (efter fönstret, inte satt); hämtningen slutade kl 16 samma dag.
        let p = post(11, räknad: tid(11, 13))
        XCTAssertEqual(jobb(p, nu: tid(11, 17), hämtningar: [tid(11, 16)]),
                       [NightLedger.Job(wakeDay: natt(11), preliminary: false, settled: false)])
    }

    func testEnHämtningPåMorgonenRäknarOmDenPågåendeNattenUtanAttVänta() {
        // Räknad kl 07:20, hämtningen klar 07:30, öppnad 07:31: inte 30 minuter än, men hämtningen räknar om.
        let p = post(11, räknad: tid(11, 7, 20), preliminär: true)
        XCTAssertEqual(jobb(p, nu: tid(11, 7, 31), hämtningar: []), [], "utan hämtning väntar den in halvtimmen")
        XCTAssertEqual(jobb(p, nu: tid(11, 7, 31), hämtningar: [tid(11, 7, 30)]),
                       [NightLedger.Job(wakeDay: natt(11), preliminary: true, settled: false)])
    }

    func testEnHämtningFöreUträkningenRäknarInteOm() {
        let p = post(11, räknad: tid(12, 12, 5), satt: true)
        XCTAssertEqual(jobb(p, nu: tid(12, 18), hämtningar: [tid(12, 11), tid(11, 9)]), [],
                       "hämtningarna var redan med när natten räknades")
    }

    func testEnHämtningIEnFilNattenInteLäserRäknarInteOm() {
        // Dag 13 läses inte av natten som slutar dag 11; dag 12 läses bara när natten satt sig.
        let satt = post(11, räknad: tid(12, 12, 5), satt: true)
        XCTAssertEqual(jobb(satt, nu: tid(13, 18), hämtningar: [tid(13, 9)]), [])
        let osatt = post(11, räknad: tid(11, 13))
        XCTAssertEqual(jobb(osatt, nu: tid(12, 10), hämtningar: [tid(12, 9)]), [],
                       "dygnet efter läses först när natten satt sig, och då räknas den om ändå")
        XCTAssertTrue(NightLedger.reads(natt(11), fetchedAt: tid(10, 23), settled: false, utcOffsetSeconds: zon),
                      "kvällen före läses")
    }

    func testEnHämtningIFramtidenRäknasInte() {
        let p = post(11, räknad: tid(12, 12, 5), satt: true)
        XCTAssertEqual(jobb(p, nu: tid(12, 14), hämtningar: [tid(12, 15)]), [], "en klocka som ställts tillbaka")
    }
}
