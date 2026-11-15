import Foundation
import XCTest
import WhoopFrames
@testable import Night

// METOD M28 · BESLUT B28. Vilka nätter som ska räknas (om) ur dygnsfilerna, och
// bara då. Rena värden: dagar, bygge och klockan. Inga värden ur något band.

final class NightLedgerTests: XCTestCase {
    let zon = 7200
    let bygge = "42"

    func dag(_ d: Int) -> DayLog.Day { DayLog.Day(year: 2026, month: 10, day: d) }
    func natt(_ d: Int) -> WakeDay { WakeDay(daysSince1970: dag(d).daysSince1970) }

    /// Klockan `h:m` den lokala dagen `d`.
    func tid(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        DayLog.date(of: dag(d), hour: h, minute: m, utcOffsetSeconds: zon)
    }

    func stammar(_ dagar: [Int]) -> [String] { dagar.map { DayLog.stem(for: dag($0)) } }

    func post(_ d: Int, byggd: String? = nil, räknad: Date, preliminär: Bool = false, satt: Bool = false,
              utanNatt: Bool = false) -> NightLedger.Entry {
        NightLedger.Entry(build: byggd ?? bygge, wakeDay: natt(d), computedAt: räknad, preliminary: preliminär,
                          settled: satt, digest: nil)
    }

    func jobb(_ stammar: [String], _ poster: [NightLedger.Entry], nu: Date, bygge b: String? = nil) -> [NightLedger.Job] {
        var kända: [WakeDay: NightLedger.Entry] = [:]
        for p in poster { kända[p.wakeDay] = p }
        return NightLedger.jobs(dayStems: stammar, entries: kända, build: b ?? bygge, now: nu, utcOffsetSeconds: zon)
    }

    // MARK: Kandidaterna

    func testEnDagHarEnNattOmDygnetFöreEllerDygnetSjälvFinns() {
        let k = NightLedger.candidates(dayStems: stammar([12, 13]), today: natt(20))
        XCTAssertEqual(k, [natt(14), natt(13), natt(12)], "nyaste först: dygn 12 och 13 ger nätterna 12, 13 och 14")
        XCTAssertEqual(NightLedger.candidates(dayStems: [], today: natt(20)), [])
        XCTAssertEqual(NightLedger.candidates(dayStems: ["annat", "natt-2026-10-12"], today: natt(20)), [])
    }

    func testIngenNattIFramtiden() {
        let k = NightLedger.candidates(dayStems: stammar([14]), today: natt(14))
        XCTAssertEqual(k, [natt(14)], "morgondagens natt har inte börjat")
    }

    // MARK: Första gången

    func testAllaDagarUtanPostRäknasDeNyasteFörst() {
        let j = jobb(stammar([12, 13]), [], nu: tid(14, 15))
        XCTAssertEqual(j.map(\.wakeDay), [natt(14), natt(13), natt(12)])
        XCTAssertTrue(j.allSatisfy { !$0.preliminary }, "kl 15 har fönstret kl 12 passerats")
        XCTAssertEqual(j.map(\.settled), [false, true, true], "natten satt sig 24 timmar efter klockan 12")
    }

    func testFöreKlockan12RäknasDagensNattFramTillNuSomPreliminär() {
        let j = jobb(stammar([13]), [], nu: tid(14, 7, 30))
        XCTAssertEqual(j.first, NightLedger.Job(wakeDay: natt(14), preliminary: true, settled: false))
    }

    // MARK: Det som inte räknas om

    func testEnFärdigNattMedSammaByggeRäknasInteOm() {
        let nu = tid(14, 15)
        let poster = [
            post(14, räknad: tid(14, 12, 5)),
            post(13, räknad: tid(13, 13), satt: true),
            post(12, räknad: tid(12, 13), satt: true),
        ]
        XCTAssertEqual(jobb(stammar([12, 13]), poster, nu: nu), [])
    }

    func testEnDagUtanNattSparasOchRäknasInteOm() {
        // `digest: nil` är en känd dag utan sömnperiod, inte en saknad post.
        let nu = tid(14, 15)
        let poster = [post(14, räknad: tid(14, 12, 5)), post(13, räknad: tid(14, 12, 5), satt: true),
                      post(12, räknad: tid(14, 12, 5), satt: true)]
        XCTAssertTrue(poster.allSatisfy { $0.digest == nil })
        XCTAssertEqual(jobb(stammar([12, 13]), poster, nu: nu), [])
    }

    func testEttNyttByggeRäknarOmAlla() {
        let nu = tid(14, 15)
        let poster = [post(14, räknad: tid(14, 12, 5)), post(13, räknad: tid(14, 12, 5), satt: true)]
        let j = jobb(stammar([13]), poster, nu: nu, bygge: "43")
        XCTAssertEqual(j.map(\.wakeDay), [natt(14), natt(13)])
    }

    // MARK: Pågående natt

    func testEnPågåendeNattRäknasInteOmOftareÄnVarTrettionde() {
        let nu = tid(14, 7, 30)
        let igår = post(13, räknad: tid(13, 12, 5), satt: true)
        XCTAssertEqual(jobb(stammar([13]), [igår, post(14, räknad: nu.addingTimeInterval(-10 * 60), preliminär: true)],
                            nu: nu), [])
        let gammal = jobb(stammar([13]), [igår, post(14, räknad: nu.addingTimeInterval(-31 * 60), preliminär: true)],
                          nu: nu)
        XCTAssertEqual(gammal, [NightLedger.Job(wakeDay: natt(14), preliminary: true, settled: false)])
        XCTAssertEqual(NightLedger.preliminaryMinutes, 30)
    }

    func testEnPreliminärNattRäknasOmNärFönstretPasserats() {
        let poster = [post(13, räknad: tid(13, 12, 5), satt: true), post(14, räknad: tid(14, 11, 45), preliminär: true)]
        XCTAssertEqual(jobb(stammar([13]), poster, nu: tid(14, 11, 59)), [])
        let efter = jobb(stammar([13]), poster, nu: tid(14, 12, 1))
        XCTAssertEqual(efter, [NightLedger.Job(wakeDay: natt(14), preliminary: false, settled: false)])
    }

    // MARK: Satt natt

    func testEnNattRäknasEnGångTillNärDenSattSig() {
        // Räknad kl 12:05 som färdig; ett dygn senare räknas den om med dygnet efter.
        func nattens(_ j: [NightLedger.Job]) -> [NightLedger.Job] { j.filter { $0.wakeDay == natt(14) } }
        let färdig = [post(14, räknad: tid(14, 12, 5))]
        XCTAssertEqual(nattens(jobb(stammar([13, 14]), färdig, nu: tid(15, 11, 59))), [])
        let sen = nattens(jobb(stammar([13, 14]), färdig, nu: tid(15, 12, 1)))
        XCTAssertEqual(sen, [NightLedger.Job(wakeDay: natt(14), preliminary: false, settled: true)])
        // Efter omräkningen är den satt och lämnas i fred.
        let satt = [post(14, räknad: tid(15, 12, 2), satt: true)]
        XCTAssertEqual(nattens(jobb(stammar([13, 14]), satt, nu: tid(16, 9))), [])
        XCTAssertEqual(NightLedger.settleHours, 24)
    }

    func testSattHarSammaGränsSomJobbet() {
        XCTAssertFalse(NightLedger.isSettled(natt(13), now: tid(14, 11, 59), utcOffsetSeconds: zon))
        XCTAssertTrue(NightLedger.isSettled(natt(13), now: tid(14, 12), utcOffsetSeconds: zon))
        XCTAssertEqual(NightLedger.windowEnd(natt(13), utcOffsetSeconds: zon), tid(13, 12))
    }

    // MARK: Det som sparas

    func testPostenGårAttSparaOchLäsaIgen() throws {
        let p = post(14, räknad: tid(14, 12, 5), preliminär: true, satt: false)
        let data = try JSONEncoder().encode(p)
        let tillbaka = try JSONDecoder().decode(NightLedger.Entry.self, from: data)
        XCTAssertEqual(tillbaka, p)
        XCTAssertEqual(tillbaka.wakeDay, natt(14))
        XCTAssertNil(tillbaka.digest)
    }
}
