import Foundation
import XCTest
@testable import Sound

// METOD M38. Händelserna och klippen, på korta påhittade sekundföljder.

final class SoundEventsTests: XCTestCase {

    func testEnHögStundEfterTystnadÄrEnHändelseMedKlass() throws {
        let secs: [SoundSecond] = SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 5, .traffic)
            + SoundFixtures.quiet(45, 20)
        let events = SoundEvents.detect(secs)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.start, 40)
        XCTAssertEqual(e.end, 44)
        XCTAssertEqual(e.soundClass, .traffic)
        XCTAssertEqual(e.activeSeconds, 5)
        XCTAssertEqual(try XCTUnwrap(e.aboveFloor), 20, accuracy: 0.5)
        XCTAssertEqual(e.peak, SoundSecond.tenths(-34), "toppen är 6 dB över A-nivån −40")
    }

    func testTreSekundersUppehållHållerIhopEnHändelseMenFyraDelarDen() {
        let ihop = SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 1) + SoundFixtures.quiet(41, 3)
            + SoundFixtures.loud(44, 1) + SoundFixtures.quiet(45, 20)
        let a = SoundEvents.detect(ihop)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.start, 40)
        XCTAssertEqual(a.first?.end, 44)
        XCTAssertEqual(a.first?.activeSeconds, 2)

        let isär = SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 1) + SoundFixtures.quiet(41, 4)
            + SoundFixtures.loud(45, 1) + SoundFixtures.quiet(46, 20)
        let b = SoundEvents.detect(isär)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b.map { $0.start }, [40, 45])
    }

    func testEnHändelseDelasEfter60Sekunder() {
        let secs = SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 130) + SoundFixtures.quiet(170, 10)
        let events = SoundEvents.detect(secs)
        XCTAssertEqual(events.map { $0.start }, [40, 100, 160])
        XCTAssertEqual(events.map { $0.length }, [60, 60, 10])
    }

    func testKlassenMedStörstSummaGäller() throws {
        var loud = SoundFixtures.loud(40, 6)
        for i in 0..<3 { loud[i].classes[SoundClass.traffic.rawValue] = 70 }
        for i in 3..<6 { loud[i].classes[SoundClass.snoring.rawValue] = 40 }
        let events = SoundEvents.detect(SoundFixtures.quiet(0, 40) + loud + SoundFixtures.quiet(46, 10))
        XCTAssertEqual(try XCTUnwrap(events.first).soundClass, .traffic)
        // Utan någon klass alls blir det övrigt.
        let utan = SoundEvents.detect(SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 4)
                                      + SoundFixtures.quiet(44, 10))
        XCTAssertEqual(try XCTUnwrap(utan.first).soundClass, .other)
    }

    func testEnKlassPå50GörSekundenAktivÄvenUtanGolvOchUtanNivå() throws {
        // De första 10 sekunderna finns inget golv; sekund 5 har tal, men är lika tyst som resten.
        var secs = SoundFixtures.quiet(0, 20)
        secs[5].classes[SoundClass.speech.rawValue] = 80
        let events = SoundEvents.detect(secs)
        XCTAssertEqual(events.count, 1)
        let e = try XCTUnwrap(events.first)
        XCTAssertEqual(e.soundClass, .speech)
        XCTAssertNil(e.aboveFloor, "golvet fanns inte än")
        // Andning och övrigt räknas inte som aktivitet.
        var andas = SoundFixtures.quiet(0, 60)
        for i in 40..<50 {
            andas[i].classes[SoundClass.breathing.rawValue] = 95
            andas[i].classes[SoundClass.other.rawValue] = 95
        }
        XCTAssertEqual(SoundEvents.detect(andas), [])
    }

    func testEnKlassUnder50GörIngenSekundAktiv() {
        var secs = SoundFixtures.quiet(0, 60)
        for i in 40..<50 { secs[i].classes[SoundClass.speech.rawValue] = 49 }
        XCTAssertEqual(SoundEvents.detect(secs), [])
    }

    func testTystaSekunderGerIngaHändelser() {
        XCTAssertEqual(SoundEvents.detect(SoundFixtures.quiet(0, 200)), [])
        XCTAssertEqual(SoundEvents.detect([]), [])
    }

    func testEnSekundSomSaknasÄrEnLucka() {
        // Sekunderna 43 och 44 saknas: avståndet 42 → 45 räknas som tre sekunders uppehåll.
        var secs = SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 3)
        secs += SoundFixtures.loud(45, 2) + SoundFixtures.quiet(47, 10)
        let events = SoundEvents.detect(secs)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.end, 46)
    }

    func testEnHändelseAvslutasFemSekunderEfterSistaAktiva() {
        var d = SoundEvents.Detector()
        var out: [SoundEvent] = []
        for s in SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 1) { out += d.push(s) }
        XCTAssertEqual(out, [])
        XCTAssertEqual(d.openStart, 40)
        for s in SoundFixtures.quiet(41, 4) { out += d.push(s) }
        XCTAssertEqual(out, [], "fyra tysta sekunder: händelsen kan fortfarande fortsätta")
        out += d.push(SoundFixtures.second(45))
        XCTAssertEqual(out.count, 1)
        XCTAssertNil(d.openStart)
        let rest = d.finish()
        XCTAssertEqual(rest, [])
        // En händelse som är öppen när lyssnaren slutar lämnas av finish().
        var e = SoundEvents.Detector()
        for s in SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 3) { _ = e.push(s) }
        let last = e.finish()
        XCTAssertEqual(last.count, 1)
    }

    func testPeakOchGolvetRäknasPerHändelse() throws {
        var secs = SoundFixtures.quiet(0, 40) + SoundFixtures.loud(40, 3)
        secs[41] = SoundFixtures.second(41, levelA: -30)
        let e = try XCTUnwrap(SoundEvents.detect(secs).first)
        XCTAssertEqual(e.peak, secs[41].peak)
        XCTAssertEqual(try XCTUnwrap(e.aboveFloor), 30, accuracy: 0.5)
    }
}

final class ClipPolicyTests: XCTestCase {

    func event(_ start: Int, _ cls: SoundClass, peak: Int, length: Int = 5) -> SoundEvent {
        SoundEvent(start: start, end: start + length - 1, soundClass: cls, peak: Int16(peak), aboveFloor: 20,
                   activeSeconds: length)
    }

    func testKlippetSpänner3SekunderFöreOch2Efter() {
        XCTAssertEqual(ClipPolicy.span(of: event(100, .speech, peak: -300)), 97..<107)
        XCTAssertEqual(ClipPolicy.span(of: event(100, .speech, peak: -300, length: 60)), 97..<127,
                       "högst 30 sekunder")
        XCTAssertEqual(ClipPolicy.span(of: event(1, .speech, peak: -300, length: 1)), -2..<4)
    }

    func testTalOchAllaAndraGerEttKlippVarderaSparas() {
        var p = ClipPolicy()
        XCTAssertEqual(p.decide(event(100, .speech, peak: -300)), .save)
        XCTAssertEqual(p.decide(event(200, .traffic, peak: -400)), .save)
        XCTAssertEqual(p.decide(event(300, .door, peak: -500)), .save)
        XCTAssertEqual(p.count, 3)
    }

    /// En snarkepisod är sammanhängande händelser à 60 sekunder (METOD M38).
    func snore(_ k: Int, peak: Int, from: Int = 1_000) -> SoundEvent {
        event(from + 60 * k, .snoring, peak: peak, length: 60)
    }

    func testSnarkningenGerHögstEttKlippPer10MinuterDetHögsta() {
        var p = ClipPolicy()
        XCTAssertEqual(p.decide(snore(0, peak: -300)), .save)
        XCTAssertEqual(p.decide(snore(1, peak: -250)), .replace(1_000), "ett högre klipp ersätter")
        XCTAssertEqual(p.decide(snore(2, peak: -400)), .skip, "ett lägre uteblir")
        XCTAssertEqual(p.decide(snore(3, peak: -250)), .skip, "lika högt ersätter inte")
        XCTAssertEqual(p.decide(snore(4, peak: -100)), .replace(1_060))
        XCTAssertEqual(p.count, 1, "ett klipp i blocket hela tiden")
        for k in 5..<10 { XCTAssertEqual(p.decide(snore(k, peak: -500)), .skip) }
        // 10 minuter efter blockets början (1 000 s) öppnas ett nytt block.
        XCTAssertEqual(p.decide(snore(10, peak: -450)), .save)
        XCTAssertEqual(p.count, 2)
    }

    func testBlockenRäknasFrånEpisodensBörjan() {
        var p = ClipPolicy()
        var sparade = 0
        // 25 minuters sammanhängande snarkning, alla lika höga.
        for k in 0..<25 {
            if p.decide(snore(k, peak: -300, from: 0)) == .save { sparade += 1 }
        }
        XCTAssertEqual(sparade, 3, "ett i varje 10-minutersblock: 0, 600 och 1 200 s")
    }

    func testEnNyEpisodGerAlltidEttKlipp() {
        var p = ClipPolicy()
        XCTAssertEqual(p.decide(event(1_000, .snoring, peak: -100)), .save)
        // 31 sekunder efter slutet (1 004): en ny episod, trots att blocket är 90 s gammalt.
        XCTAssertEqual(p.decide(event(1_035, .snoring, peak: -500)), .save)
        XCTAssertEqual(p.count, 2)
    }

    func testTaketPå150ErsätterDetLägstaMedEttHögre() {
        var p = ClipPolicy()
        for i in 0..<150 {
            XCTAssertEqual(p.decide(event(i * 100, .speech, peak: -500 + i)), .save)
        }
        XCTAssertEqual(p.count, 150)
        XCTAssertEqual(p.decide(event(20_000, .speech, peak: -600)), .skip, "lägre än allt")
        XCTAssertEqual(p.decide(event(20_100, .speech, peak: -500)), .skip, "lika med det lägsta ersätter inte")
        XCTAssertEqual(p.decide(event(20_200, .speech, peak: 0)), .replace(0), "det lägsta (det första) går")
        XCTAssertEqual(p.decide(event(20_300, .speech, peak: 0)), .replace(100), "och sedan det näst lägsta")
        XCTAssertEqual(p.count, 150)
    }
}
