import Foundation
import XCTest
@testable import Pass

// BESLUT B117 · METOD M68. Passets puls ur bandets historik, med påhittade prov och poster.

final class PassHistoryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    var s0: Int { 1_760_000_000 }

    /// Ett stoppat och färdigt pass: Start t0, Stopp efter `minuter`, efterperioden 600 s.
    private func pass(minuter: Int = 30, live: [PassSample] = []) -> Pass {
        let stopp = t0.addingTimeInterval(Double(minuter) * 60)
        return Pass(start: t0, stop: stopp, afterEnd: stopp.addingTimeInterval(600), kind: .bastu, samples: live)
    }

    /// Historiken: en post per sekund från `från` till och med `till` (sekunder efter Start), pulsen 100 + s % 20.
    private func poster(_ från: Int, _ till: Int) -> [PassHistory.Reading] {
        (från...till).map { PassHistory.Reading(time: s0 + $0, bpm: 100 + $0 % 20) }
    }

    private func live(_ sekunder: ClosedRange<Int>, bpm: Int = 80) -> [PassSample] {
        sekunder.map { PassSample(t: t0.addingTimeInterval(Double($0)), bpm: bpm) }
    }

    // MARK: Fönstret och luckorna

    func testFönstretÄrStartTillEfterperiodensSlut() {
        let p = pass()
        XCTAssertEqual(PassHistory.window(p), t0...t0.addingTimeInterval(2400))
        // Stoppat men inte färdigt: efterperioden räknas ändå med.
        var q = p
        q.afterEnd = nil
        XCTAssertEqual(PassHistory.window(q), t0...t0.addingTimeInterval(2400))
        // Ett pass som pågår har inget fönster.
        XCTAssertNil(PassHistory.window(Pass(start: t0)))
        XCTAssertEqual(PassHistory.fill(Pass(start: t0), readings: poster(0, 100)).samples, [])
    }

    func testEttPassUtanProvÄrEnEndaLucka() {
        let p = pass()
        XCTAssertEqual(PassHistory.gaps(p), [t0...t0.addingTimeInterval(2400)])
        XCTAssertEqual(PassHistory.missingSeconds(p), 2400)
    }

    func testLuckorÄrLängreÄnTioSekunder() {
        // Prov 0–100, 110 (precis tio sekunder: ingen lucka), 121 (elva: lucka), sedan inget.
        var p = pass(live: live(0...100))
        p.samples += [PassSample(t: t0.addingTimeInterval(110), bpm: 80), PassSample(t: t0.addingTimeInterval(121), bpm: 80)]
        XCTAssertEqual(PassHistory.gaps(p), [t0.addingTimeInterval(110)...t0.addingTimeInterval(121),
                                             t0.addingTimeInterval(121)...t0.addingTimeInterval(2400)])
    }

    // MARK: Fyllningen

    func testEttPassHeltUtanLiveprovFyllsHeltUrHistoriken() {
        let fyllt = PassHistory.fill(pass(), readings: poster(-300, 3000), through: t0.addingTimeInterval(3000))
        // Varje sekund i fönstret, kanterna med, och inget utanför.
        XCTAssertEqual(fyllt.samples.count, 2401)
        XCTAssertEqual(fyllt.samples.first?.t, t0)
        XCTAssertEqual(fyllt.samples.last?.t, t0.addingTimeInterval(2400))
        XCTAssertTrue(fyllt.samples.allSatisfy { $0.source == .history })
        XCTAssertEqual(fyllt.samples.map(\.t), fyllt.samples.map(\.t).sorted())
        XCTAssertEqual(PassHistory.gaps(fyllt), [])
        // Talen räknas som vanligt på de fyllda proven (M47): den aktiva delen, och pulsen efter stopp.
        XCTAssertEqual(fyllt.minBpm, 100)
        XCTAssertEqual(fyllt.maxBpm, 119)
        XCTAssertEqual(fyllt.pulseAtStop, 100 + 1800 % 20)
        XCTAssertEqual(fyllt.pulse(after: 60), 100 + 1860 % 20)
        XCTAssertEqual(fyllt.recovery.map { $0.bpm != nil }, [true, true, true])
    }

    func testLiveprovBehållsOchBaraLuckornaFylls() {
        // Live 0–600 (telefonen med), sedan tyst till 1500, sedan live igen till slutet.
        let p = pass(live: live(0...600) + live(1500...2400))
        let fyllt = PassHistory.fill(p, readings: poster(0, 2400))
        let historik = fyllt.samples.filter { $0.source == .history }
        XCTAssertEqual(historik.first?.t, t0.addingTimeInterval(601))
        XCTAssertEqual(historik.last?.t, t0.addingTimeInterval(1499))
        XCTAssertEqual(historik.count, 899)
        // Varje liveprov ligger kvar orört, och inget prov står två gånger på samma tid.
        XCTAssertEqual(fyllt.samples.filter { $0.source == nil }, p.samples)
        XCTAssertEqual(Set(fyllt.samples.map(\.t)).count, fyllt.samples.count)
        XCTAssertEqual(PassHistory.gaps(fyllt), [])
    }

    func testKortaGlappILiveprovenFyllsInte() {
        // Ett glapp på åtta sekunder är inte en lucka: där står liveproven ensamma.
        let p = pass(live: live(0...100) + live(108...2400))
        XCTAssertEqual(PassHistory.fill(p, readings: poster(0, 2400)).samples, p.samples)
    }

    func testPosterUtanPulsOchOrimligaPosterÄrInteProv() {
        var rader = poster(0, 2400)
        for i in 100..<200 { rader[i].bpm = 0 }
        rader[300].bpm = 24
        rader[301].bpm = 231
        let fyllt = PassHistory.fill(pass(), readings: rader)
        XCTAssertEqual(fyllt.samples.count, 2401 - 102)
        XCTAssertFalse(fyllt.samples.contains { $0.bpm < 25 || $0.bpm > 230 })
        // Sträckan utan puls är en lucka som står kvar.
        XCTAssertEqual(PassHistory.gaps(fyllt), [t0.addingTimeInterval(99)...t0.addingTimeInterval(200)])
    }

    func testFyllningenÄrIdempotentOchVäxer() {
        let p = pass()
        let halv = PassHistory.fill(p, readings: poster(0, 1200))
        XCTAssertEqual(PassHistory.fill(halv, readings: poster(0, 1200)), halv)
        // Mer historik senare fyller resten, och det som redan fyllts ligger kvar även om det inte lämnas igen.
        let hel = PassHistory.fill(halv, readings: poster(1201, 2400))
        XCTAssertEqual(hel.samples.count, 2401)
        XCTAssertEqual(PassHistory.fill(hel, readings: []), hel)
        // Samma sekund igen med ett annat värde: den nya posten gäller, och det blir inte två prov.
        let om = PassHistory.fill(hel, readings: [PassHistory.Reading(time: s0 + 50, bpm: 150)])
        XCTAssertEqual(om.samples.count, 2401)
        XCTAssertEqual(om.pulse(at: t0.addingTimeInterval(50)), 150)
    }

    func testLiveprovSomKommerSenareTrängerUndanHistoriken() {
        // Ett pass som fyllts och sedan (i ett tänkt omtag) har liveprov på samma sträcka: historiken där tas bort.
        var p = PassHistory.fill(pass(), readings: poster(0, 2400))
        p.samples += live(0...2400)
        let igen = PassHistory.fill(p, readings: [])
        XCTAssertTrue(igen.samples.allSatisfy { $0.source == nil })
        XCTAssertEqual(igen.samples.count, 2401)
    }

    // MARK: Väntar passet på historiken?

    func testPassetVäntarTillsHistorikenNåttFörbiSlutet() {
        let p = pass()
        let strax = t0.addingTimeInterval(3600)
        XCTAssertTrue(PassHistory.awaitsHistory(p, now: strax))
        // Historiken har bara nått halvvägs: passet väntar fortfarande.
        let halv = PassHistory.fill(p, readings: poster(0, 1200), through: t0.addingTimeInterval(1200))
        XCTAssertTrue(PassHistory.awaitsHistory(halv, now: strax))
        // Fyllt: väntar inte.
        let hel = PassHistory.fill(halv, readings: poster(1201, 2400), through: t0.addingTimeInterval(2500))
        XCTAssertFalse(PassHistory.awaitsHistory(hel, now: strax))
        // Historiken nådde förbi slutet men bandet satt inte på en stund: luckan är bandets, passet väntar inte.
        let hål = PassHistory.fill(p, readings: poster(0, 1000) + poster(1400, 2400), through: t0.addingTimeInterval(2500))
        XCTAssertFalse(PassHistory.gaps(hål).isEmpty)
        XCTAssertFalse(PassHistory.awaitsHistory(hål, now: strax))
        // `through` backar aldrig.
        XCTAssertEqual(PassHistory.fill(hel, readings: [], through: t0).historyThrough, t0.addingTimeInterval(2500))
    }

    func testEttPassSomPågårEllerÄrGammaltVäntarInte() {
        XCTAssertFalse(PassHistory.awaitsHistory(Pass(start: t0), now: t0.addingTimeInterval(60)))
        XCTAssertTrue(PassHistory.awaitsHistory(pass(), now: t0.addingTimeInterval(14 * 86400)))
        XCTAssertFalse(PassHistory.awaitsHistory(pass(), now: t0.addingTimeInterval(14 * 86400 + 1)))
        // Ett pass med liveprov hela vägen väntar inte på något.
        XCTAssertFalse(PassHistory.awaitsHistory(pass(live: live(0...2400)), now: t0.addingTimeInterval(3600)))
    }

    // MARK: Filen

    func testKällanFöljerMedIFilenOchEnGammalFilLäsesSomLive() throws {
        let fyllt = PassHistory.fill(pass(live: live(0...5)), readings: poster(0, 2400), through: t0.addingTimeInterval(2500))
        let tillbaka = try PassFile.decode(PassFile.encode(fyllt))
        XCTAssertEqual(tillbaka, fyllt)
        XCTAssertEqual(tillbaka.samples.filter { $0.source == .history }.count, 2401 - 6)
        // Ett liveprov skriver ingen källa, så ett pass utan historik ger samma byte som förut.
        let text = String(decoding: try PassFile.encode(pass(live: live(0...5))), as: UTF8.self)
        XCTAssertFalse(text.contains("source"))
        XCTAssertFalse(text.contains("historyThrough"))
        // En fil från ett äldre bygge: inga nycklar för källan eller historiken.
        let gammal = #"{"id":"00000000-0000-0000-0000-000000000001","samples":[{"bpm":88,"t":"2025-10-09T09:00:00Z"}],"start":"2025-10-09T08:59:00Z","stop":"2025-10-09T09:30:00Z","afterEnd":"2025-10-09T09:40:00Z"}"#
        let läst = try PassFile.decode(Data(gammal.utf8))
        XCTAssertNil(läst.samples[0].source)
        XCTAssertNil(läst.historyThrough)
        XCTAssertTrue(PassHistory.awaitsHistory(läst, now: läst.start.addingTimeInterval(7200)))
    }
}
