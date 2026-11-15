import Foundation
import XCTest
import DemoData
import Night
import WhoopFrames
@testable import Sound

// METOD M39 och M40 på den påhittade ljudnatten (DemoSound): två snarkepisoder,
// tre trafikhändelser, två rörelseljud, en talepisod och en klockskillnad på
// 7 s. Facit står i `DemoSound.Truth`.

final class SnoreOwnershipTests: XCTestCase {

    func testDenFörstaEpisodenÄrDinOchDenAndraÄrNågonAnnans() throws {
        let night = SoundFixtures.night
        let blocks = SoundFixtures.summary.blocks
        XCTAssertEqual(blocks.count, 2)
        let a = blocks[0]
        let b = blocks[1]
        XCTAssertEqual(a.start, night.truth.yoursEpisode.lowerBound)
        XCTAssertEqual(a.end, night.truth.yoursEpisode.upperBound)
        XCTAssertEqual(a.verdict, .yours)
        XCTAssertTrue(a.breathingClear)
        XCTAssertGreaterThanOrEqual(a.snores, 12)
        XCTAssertGreaterThan(try XCTUnwrap(a.r), 0.5, "fasen samlad kring ett ställe i andetaget")
        XCTAssertLessThan(try XCTUnwrap(a.p), 0.01)
        XCTAssertEqual(b.start, night.truth.othersEpisode.lowerBound)
        XCTAssertEqual(b.verdict, .someoneElse)
        XCTAssertTrue(b.ownRhythm, "snarkningen har en egen takt")
        XCTAssertGreaterThanOrEqual(b.snores, 20)
        XCTAssertGreaterThan(try XCTUnwrap(b.p), 0.2)
    }

    func testBlockenÄrHögst10MinuterOchEpisodenMinst60Sekunder() {
        var secs = SoundFixtures.quiet(0, 2_100)
        func snora(_ range: ClosedRange<Int>) {
            for i in range { secs[i].classes[SoundClass.snoring.rawValue] = 80 }
        }
        snora(100...159)       // 60 s: en episod
        snora(300...358)       // 59 s: för kort
        snora(1_000...2_000)   // 1 001 s: två block
        let b = SnoreOwnership.blocks(secs)
        XCTAssertEqual(b, [100...159, 1_000...1_599, 1_600...2_000])
    }

    func testUppehållPå30SekunderHållerIhopEpisodenMen31Delar() {
        var secs = SoundFixtures.quiet(0, 400)
        for i in 10...40 { secs[i].classes[0] = 80 }
        for i in 71...100 { secs[i].classes[0] = 80 }     // 30 s uppehåll: samma episod
        for i in 132...200 { secs[i].classes[0] = 80 }    // 31 s uppehåll: en ny
        XCTAssertEqual(SnoreOwnership.blocks(secs), [10...100, 132...200])
    }

    func testSnarkningensTidÄrSekundenPlusOnsetramensMitt() {
        var secs = SoundFixtures.quiet(0, 100)
        secs[10].classes[0] = 80
        secs[10].onset = 4
        secs[11].classes[0] = 80      // ingen onset: ingen tid
        secs[12].classes[0] = 40      // under 50: ingen snarkning
        secs[12].onset = 2
        let t = SnoreOwnership.snoreTimes(secs, in: 0...99, soundStart: 1_000)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0], 1_010 + 4.5 / 16, accuracy: 1e-9)
    }

    func testRayleighEnJämnFördelningOchEnSamladFas() {
        let jämn: [Double] = (0..<40).map { (k: Int) -> Double in 2 * Double.pi * Double(k) / 40 }
        let a = SnoreOwnership.rayleigh(jämn)
        XCTAssertEqual(a.r, 0, accuracy: 1e-9)
        XCTAssertEqual(a.p, 1, accuracy: 1e-9)
        let b = SnoreOwnership.rayleigh([Double](repeating: 1.0, count: 20))
        XCTAssertEqual(b.r, 1, accuracy: 1e-9)
        XCTAssertEqual(b.p, exp(-20), accuracy: 1e-12)
        let c = SnoreOwnership.rayleigh([])
        XCTAssertEqual(c.p, 1)
    }

    func testEgenTaktKräverEnTopp() {
        let jämn: [Double] = (0..<80).map { (k: Int) -> Double in 100 + Double(k) * 4.4 }
        let a = SnoreOwnership.ownRhythm(jämn)
        XCTAssertTrue(a.found)
        XCTAssertEqual(a.lagSeconds, 4.4, accuracy: 0.2)
        // Slumpade tider utan takt (seedade) har ingen topp över 0,25.
        var r = Seeded(5)
        let slump: [Double] = (0..<80).map { (_: Int) -> Double in 100 + 350 * r.uniform() }
        XCTAssertFalse(SnoreOwnership.ownRhythm(slump).found)
        XCTAssertFalse(SnoreOwnership.ownRhythm([1, 2]).found)
    }

    func testEnSnarkningUtanTydligAndningGerOkänd() throws {
        // Samma snarkning som den första episoden, men K18 utan andningsvåg i RR.
        let night = SoundFixtures.night
        var flat: [K18Record] = night.series.records
        for i in flat.indices { flat[i].rr = flat[i].rr.isEmpty ? [] : [1_000] }
        let blocks = SnoreOwnership.classify(night.seconds, soundStart: night.start,
                                             clockOffset: night.clockOffset, series: K18Series(records: flat))
        XCTAssertEqual(blocks.count, 2)
        for b in blocks {
            XCTAssertFalse(b.breathingClear)
            XCTAssertEqual(b.verdict, .unknown, "utan andning finns ingen fas att jämföra mot")
        }
    }

    /// Klart när: i 100 seedade nätter med en snarkning utan fas mot andningen blir högst 2 "din".
    func testIHundraNätterUtanFasBlirHögstTvåDin() {
        var din = 0
        var okända = 0
        for seed in 1...100 {
            let s = DemoSound.snippet(seed: UInt64(seed), inPhase: false)
            let blocks = SnoreOwnership.classify(s.seconds, soundStart: s.start, series: s.series)
            XCTAssertEqual(blocks.count, 1)
            if blocks.first?.verdict == .yours { din += 1 }
            if blocks.first?.verdict == .unknown { okända += 1 }
        }
        XCTAssertLessThanOrEqual(din, 2, "falska \"din\" av 100 nätter")
        print("PROV: falska din \(din) av 100, okända \(okända)")
    }

    func testSnarkningISammaFasSomAndningenÄrDinFörDeFlesta() {
        var din = 0
        for seed in 1...20 {
            let s = DemoSound.snippet(seed: UInt64(seed), inPhase: true)
            let blocks = SnoreOwnership.classify(s.seconds, soundStart: s.start, series: s.series)
            if blocks.first?.verdict == .yours { din += 1 }
        }
        XCTAssertGreaterThanOrEqual(din, 18, "snarkningen i fas hittas")
    }
}

final class SoundClockTests: XCTestCase {

    func testKlockskillnadenPå7SekunderHittas() {
        let c = SoundFixtures.summary.clock
        XCTAssertTrue(c.isReliable)
        XCTAssertEqual(c.offset, 7, accuracy: 1)
        XCTAssertEqual(c.bursts, 17, "tolv vändningar före sömnen, två i den, tre vakna pass")
        XCTAssertGreaterThanOrEqual(c.ratio ?? 0, SoundClock.peakToMedian)
        XCTAssertEqual(c.toleranceSeconds, 1)
    }

    func testUtanRörelseskurarÄrKlockanOsäkerOchSkillnaden0() {
        let s = DemoSound.snippet(seed: 3, inPhase: false)
        let c = SoundClock.estimate(s.seconds, soundStart: s.start, series: s.series)
        XCTAssertFalse(c.isReliable)
        XCTAssertEqual(c.offset, 0)
        XCTAssertEqual(c.bursts, 0)
        XCTAssertEqual(c.toleranceSeconds, 5)
    }
}

final class SoundResponseTests: XCTestCase {

    var items: [SoundResponse.Item] { SoundFixtures.summary.response.items }

    func trafik() -> [SoundResponse.Item] {
        items.filter { (i: SoundResponse.Item) -> Bool in i.event.soundClass == .traffic }
            .sorted { (a: SoundResponse.Item, b: SoundResponse.Item) -> Bool in a.event.start < b.event.start }
    }

    /// Klart när: två av tre trafikhändelser väckte.
    func testTvåAvTreTrafikhändelserVäckte() {
        let t = trafik()
        XCTAssertEqual(t.map { $0.event.start }, SoundFixtures.night.truth.traffic)
        XCTAssertEqual(t.map { $0.awakening }, SoundFixtures.night.truth.trafficWoke)
        XCTAssertEqual(t.map { $0.pulseReaction }, [true, true, false])
        XCTAssertTrue(t.allSatisfy { (i: SoundResponse.Item) -> Bool in !i.movementSound && i.counted })
        for i in t.prefix(2) { XCTAssertGreaterThanOrEqual(i.pulseRise ?? 0, 8) }
        XCTAssertLessThan(t[2].pulseRise ?? 99, 8)
        XCTAssertEqual(t.compactMap { $0.levelStep }, [1, 1, 1], "22 dB över bakgrunden: +20–30")
    }

    /// Klart när: rörelseljuden räknas aldrig som orsak.
    func testRörelseljudenRäknasAldrigSomOrsak() {
        let rörelse = items.filter { (i: SoundResponse.Item) -> Bool in i.movementSound }
        XCTAssertEqual(rörelse.map { $0.event.start }, SoundFixtures.night.truth.movementSounds)
        XCTAssertTrue(rörelse.allSatisfy { (i: SoundResponse.Item) -> Bool in !i.counted })
        // Det andra följs av ett uppvaknande, men det är armen som väckte, inte ljudet.
        XCTAssertEqual(rörelse.count, 2)
        XCTAssertTrue(rörelse.last?.awakening ?? false)
        let r = SoundFixtures.summary.response
        XCTAssertEqual(r.awakenings, 2)
        XCTAssertEqual(r.overall.awakenings, 2)
        XCTAssertEqual(SoundFixtures.summary.followedByAwakening, 2)
        XCTAssertEqual(SoundFixtures.summary.followedByPulse, 2)
    }

    func testDinSnarkningOchLjudFöreSömnenKommerInteMed() {
        let classes = items.map { $0.event.soundClass }
        // Din snarkning (10 händelser à 60 s) är utanför; någon annans (10) och talet är med.
        XCTAssertEqual(classes.filter { $0 == .snoring }.count, 10)
        XCTAssertEqual(classes.filter { $0 == .speech }.count, 1)
        // Tolv prassel före sömnen och två i den: bara de två i sömnen.
        XCTAssertEqual(classes.filter { $0 == .other }.count, 2)
        XCTAssertEqual(items.count, 10 + 1 + 2 + 3)
        let natt = SoundFixtures.night
        for i in items { XCTAssertGreaterThanOrEqual(i.event.start, natt.truth.onset + 60) }
    }

    func testKontrollernaGerEffektenPerKlassOchNivåsteg() throws {
        let r = SoundFixtures.summary.response
        let t = r.perClass[SoundClass.traffic.rawValue]
        XCTAssertEqual(t.events, 3)
        XCTAssertEqual(t.awakenings, 2)
        XCTAssertEqual(t.controls, 15, "fem kontroller per händelse")
        XCTAssertEqual(try XCTUnwrap(t.awakeningShare), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertGreaterThan(try XCTUnwrap(t.awakeningEffect), 0.3, "klart fler uppvaknanden efter trafik än vid kontrollerna")
        XCTAssertGreaterThan(try XCTUnwrap(t.pulseEffect), 0.3)
        XCTAssertEqual(r.perStep.count, 3)
        XCTAssertGreaterThanOrEqual(r.perStep[1].events, 3, "trafiken ligger i steget +20–30")
        XCTAssertLessThanOrEqual(r.perStep.reduce(0) { (a: Int, x: SoundResponse.Rate) -> Int in a + x.events },
                                 r.overall.events)
        XCTAssertEqual(r.overall.events, 14)
        XCTAssertEqual(r.overall.controls, 70)
    }

    func testEnOsäkerKlockKräverFemSekundersOrdning() {
        // Klockskillnaden är fel med 3 s: rörelsen börjar 3 s före ljudet. Med en säker klocka (1 s)
        // är det ingen rörelse bakom ljudet; med en osäker (5 s) är det.
        let n = SoundFixtures.night
        let events = SoundEvents.detect(n.seconds)
        func rörelseljud(reliable: Bool) -> Int {
            let clock = SoundClock.Estimate(offset: 10, isReliable: reliable, peak: nil, ratio: nil, bursts: 17)
            let r = SoundResponse.compute(events: events, blocks: SoundFixtures.summary.blocks,
                                          soundStart: n.start, clock: clock, series: n.series, layers: n.layers)
            return r.items.filter { (i: SoundResponse.Item) -> Bool in i.movementSound }.count
        }
        XCTAssertEqual(rörelseljud(reliable: true), 0)
        XCTAssertEqual(rörelseljud(reliable: false), 2)
    }

    func testSammaNattGerSammaKontroller() {
        let n = SoundFixtures.night
        let a = SoundNight.analyze(n.seconds, soundStart: n.start, series: n.series, layers: n.layers)
        XCTAssertEqual(a.response, SoundFixtures.summary.response)
    }
}

final class SoundNightTests: XCTestCase {

    let s = SoundFixtures.summary

    func testSnarkningensMinuterPerÄgare() {
        XCTAssertEqual(s.snore.yours, 9.5, accuracy: 1e-9, "570 sekunder")
        XCTAssertEqual(s.snore.someoneElse, 9.5, accuracy: 1e-9)
        XCTAssertEqual(s.snore.unknown, 0, accuracy: 1e-9)
        XCTAssertEqual(s.snore.total, 19, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(s.unknownShare), 0, accuracy: 1e-9)
    }

    func testDinSnarkningGenomNatten() throws {
        let p = s.snoring
        XCTAssertEqual(p.minutes, 9.5, accuracy: 1e-9)
        // 4 415 s sömn mätt utan de vakna passen.
        XCTAssertEqual(try XCTUnwrap(p.perHourAsleep), 9.5 / (4_415.0 / 3_600), accuracy: 0.01)
        XCTAssertEqual(p.perThird.count, 3)
        XCTAssertEqual(p.perThird[0], 9.5, accuracy: 1e-9, "episoden ligger i första tredjedelen av sömnperioden")
        XCTAssertEqual(p.perThird[1] + p.perThird[2], 0, accuracy: 1e-9)
        XCTAssertEqual(p.perStage, [], "natten har inga stadier")
        XCTAssertEqual(try XCTUnwrap(p.strengthDB), 22.8, accuracy: 1.5, "22 dB över bakgrunden plus golvets nivå")
    }

    func testTalOchHändelserPerKlass() {
        XCTAssertEqual(s.speechEpisodes, 1)
        XCTAssertEqual(s.eventsPerClass.count, 12)
        XCTAssertEqual(s.eventsPerClass[SoundClass.traffic.rawValue], 3)
        XCTAssertEqual(s.eventsPerClass[SoundClass.speech.rawValue], 1)
        XCTAssertEqual(s.eventsPerClass[SoundClass.snoring.rawValue], 20)
        XCTAssertEqual(s.eventsPerClass[SoundClass.other.rawValue], 14, "tolv vändningar före sömnen och två i den")
        XCTAssertEqual(s.eventsPerClass.reduce(0, +), s.events.count)
        XCTAssertEqual(s.secondsMeasured, 6_000)
        XCTAssertEqual(s.gaps, [])
        XCTAssertEqual(s.clock.offset, 7, accuracy: 1)
    }

    func testGlappenFörklarasAvAvbrottsmärken() {
        let n = SoundFixtures.night
        var secs: [SoundSecond] = n.seconds
        secs.removeAll { (x: SoundSecond) -> Bool in (1_300...1_309).contains(x.second) || x.second == 1_500 - 1 }
        let marks: [SoundMark] = [SoundMark(time: n.start + 1_299, kind: .interruptedCall),
                                  SoundMark(time: n.start + 1_310, kind: .resumed)]
        let a = SoundNight.analyze(secs, soundStart: n.start, series: n.series, layers: n.layers, marks: marks)
        XCTAssertEqual(a.gaps.count, 2)
        XCTAssertEqual(a.gaps[0].start, 1_300)
        XCTAssertEqual(a.gaps[0].end, 1_309)
        XCTAssertEqual(a.gaps[0].seconds, 10)
        XCTAssertEqual(a.gaps[0].cause, .interruptedCall)
        XCTAssertNil(a.gaps[1].cause, "inget märke förklarar sekunden före episoden")
    }

    func testUtanLagerRäknasIngetSomKrävSömnen() {
        let n = SoundFixtures.night
        let a = SoundNight.analyze(n.seconds, soundStart: n.start, series: n.series, layers: nil)
        XCTAssertEqual(a.response.items, [])
        XCTAssertEqual(a.followedByAwakening, 0)
        XCTAssertEqual(a.followedByPulse, 0)
        XCTAssertNil(a.snoring.perHourAsleep)
        XCTAssertEqual(a.blocks.count, 2, "snarkningens ägare räknas ändå")
        XCTAssertEqual(a.snore.yours, 9.5, accuracy: 1e-9)
        XCTAssertEqual(a.speechEpisodes, 1)
    }

    func testEnTomNattGerEnTomSammanfattning() {
        let a = SoundNight.analyze([], soundStart: 1_000, series: K18Series(records: []), layers: nil)
        XCTAssertEqual(a.secondsMeasured, 0)
        XCTAssertEqual(a.events, [])
        XCTAssertEqual(a.blocks, [])
        XCTAssertNil(a.unknownShare)
        XCTAssertFalse(a.clock.isReliable)
        XCTAssertEqual(a.snore.total, 0)
    }

    func testSammaSeedGerSammaNatt() {
        let a = DemoSound.night(seed: 4)
        XCTAssertEqual(a, DemoSound.night(seed: 4))
        XCTAssertNotEqual(a.seconds, DemoSound.night(seed: 5).seconds)
    }
}
