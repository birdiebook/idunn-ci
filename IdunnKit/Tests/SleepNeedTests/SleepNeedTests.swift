import Foundation
import XCTest
import Night
import Pass
@testable import SleepNeed

// Alla nätter, pass och pulsvärden nedan är påhittade. Samma fall och samma väntade tal
// står i tools/tests/test_somnbehov.py (pariteten med tools/somnbehov.py, METOD M53):
// ändras ett fall här ändras det där.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Prov varje sekund i `sekunder`, med pulsen `bpm`.
private func prov(_ sekunder: [Int], _ bpm: Int) -> [PassSample] {
    sekunder.map { PassSample(t: t0.addingTimeInterval(Double($0)), bpm: bpm) }
}

final class PassLoadTests: XCTestCase {
    func testZonerMotMaxpulsen() {
        XCTAssertEqual(PassLoad.zone(bpm: 94, maxPulse: 190), 0)   // under 50 %
        XCTAssertEqual(PassLoad.zone(bpm: 95, maxPulse: 190), 1)   // precis 50 %
        XCTAssertEqual(PassLoad.zone(bpm: 170, maxPulse: 190), 4)
        XCTAssertEqual(PassLoad.zone(bpm: 171, maxPulse: 190), 5)  // precis 90 %
        XCTAssertEqual(PassLoad.zone(bpm: 150, maxPulse: 0), 0)
    }

    func testZonsummanRäknarTidenTillNästaProvOchHopparÖverGlapp() {
        // 600 prov i zon 4: 599 s × 4 / 60.
        XCTAssertEqual(PassLoad.zoneScore(prov(Array(0..<600), 152), maxPulse: 190), 39.93333333333364, accuracy: 1e-9)
        // Ett glapp på 10 s (300 → 310) räknas inte.
        let glapp = prov(Array(0..<300) + Array(310..<600), 152)
        XCTAssertEqual(PassLoad.zoneScore(glapp, maxPulse: 190), 39.20000000000027, accuracy: 1e-9)
    }

    func testBastuOchDuschGerIngenBelastningStyrkaMinstTvåPerMinut() {
        let hårt = Pass(start: t0, stop: t0.addingTimeInterval(599), kind: .bastu, samples: prov(Array(0..<600), 152))
        XCTAssertEqual(PassLoad.load(hårt, maxPulse: 190), 0)
        var utanTyp = hårt
        utanTyp.kind = nil
        XCTAssertEqual(PassLoad.load(utanTyp, maxPulse: 190), 39.93333333333364, accuracy: 1e-9)
        // 30 min styrka med låg puls: zonsumman 30, golvet 2 × 30 = 60.
        let styrka = Pass(start: t0, stop: t0.addingTimeInterval(1800), kind: .styrka, samples: prov(Array(0...1800), 100))
        XCTAssertEqual(PassLoad.zoneScore(styrka.activeSamples, maxPulse: 190), 30, accuracy: 1e-9)
        XCTAssertEqual(PassLoad.load(styrka, maxPulse: 190), 60, accuracy: 1e-9)
    }

    func testMaxpulsenÄrHögstaMedianenAvFemOchBastuRäknasInte() {
        let bpm = [120, 130, 200, 131, 132, 133, 134, 128]
        var p = Pass(start: t0, kind: .kondition)
        p.samples = bpm.enumerated().map { PassSample(t: t0.addingTimeInterval(Double($0.offset)), bpm: $0.element) }
        let bastu = Pass(start: t0, kind: .bastu, samples: prov(Array(0..<10), 180))
        XCTAssertEqual(PassLoad.maxPulse(from: [p, bastu]), 133)  // spiken 200 blir inte maxpuls
        XCTAssertNil(PassLoad.maxPulse(from: [bastu]))
        XCTAssertEqual(PassLoad.tanakaMaxPulse(age: 40), 180, accuracy: 1e-9)
    }
}

final class SleepNeedTests: XCTestCase {
    // Fyra nätter, natten som slutar dag 102 saknas. Pass dag 102 kl 14 (räknas) och
    // dag 103 kl 20 (för nära insomningen).
    private let nätter = [
        SleepNight(day: 100, asleepMinutes: 430, periodMinutes: 470, onsetMinute: -30, wakeMinute: 440),
        SleepNight(day: 101, asleepMinutes: 430, periodMinutes: 465, onsetMinute: -20, wakeMinute: 445),
        SleepNight(day: 103, asleepMinutes: 520, periodMinutes: 555, onsetMinute: -60, wakeMinute: 495),
        SleepNight(day: 104, asleepMinutes: 490, periodMinutes: 520, onsetMinute: -40, wakeMinute: 480),
    ]
    private let pass = [PassDay(day: 102, stopMinute: 840, load: 300), PassDay(day: 103, stopMinute: 1200, load: 800)]

    func testTilläggetBaraFörPassMinstÅttaTimmarFöreInsomningenOchMedTak() {
        let p = [PassDay(day: 9, stopMinute: 840, load: 400), PassDay(day: 9, stopMinute: 1020, load: 500)]
        XCTAssertEqual(SleepNeed.passAddition(p, day: 10, usualOnset: -30), 4, accuracy: 1e-9)   // 9,5 h räknas, 6,5 h inte
        XCTAssertEqual(SleepNeed.passAddition([PassDay(day: 9, stopMinute: 600, load: 1500)], day: 10, usualOnset: -30), 10)
        XCTAssertEqual(SleepNeed.passAddition(p, day: 10, usualOnset: nil), 0)
        XCTAssertEqual(SleepNeed.passAddition(p, day: 11, usualOnset: -30), 0)                   // fel dag
    }

    func testSkuldenNattFörNattStårStillNärNattenSaknas() {
        let b = SleepNeed.ledger(nights: nätter, passes: pass, base: 490)
        XCTAssertEqual(b.map(\.day), [100, 101, 102, 103, 104])
        XCTAssertEqual(b.map(\.passMinutes), [0, 0, 0, 3, 0])
        XCTAssertEqual(b[0].debtMinutes, 60, accuracy: 1e-9)
        XCTAssertEqual(b[1].debtMinutes, 90.80502714195552, accuracy: 1e-9)
        XCTAssertNil(b[2].sleptMinutes)
        XCTAssertEqual(b[2].debtMinutes, 90.80502714195552, accuracy: 1e-9)
        XCTAssertEqual(b[3].needMinutes, 493, accuracy: 1e-9)
        XCTAssertEqual(b[3].debtMinutes, 19.620855428899176, accuracy: 1e-9)
        XCTAssertEqual(b[4].debtMinutes, 10.07368306726039, accuracy: 1e-9)
    }

    func testSkuldenGårAldrigUnderNoll() {
        let lång = [SleepNight(day: 1, asleepMinutes: 600, periodMinutes: 620, onsetMinute: -60, wakeMinute: 540)]
        XCTAssertEqual(SleepNeed.ledger(nights: lång, passes: [], base: 490).last?.debtMinutes, 0)
        XCTAssertEqual(SleepNeed.ledger(nights: [], passes: [], base: 490), [])
    }

    func testKvällensBehovOchLäggdags() throws {
        let k = try XCTUnwrap(SleepNeed.tonight(nights: nätter, passes: pass, base: 490, day: 105))
        XCTAssertEqual(k.debtMinutes, 10.07368306726039, accuracy: 1e-9)
        XCTAssertEqual(k.debtPartMinutes, 10.07368306726039, accuracy: 1e-9)
        XCTAssertEqual(k.passMinutes, 0)
        XCTAssertEqual(k.needMinutes, 500.0736830672604, accuracy: 1e-9)
        XCTAssertEqual(k.wakeMinute, 462.5, accuracy: 1e-9)
        XCTAssertEqual(k.efficiency, 0.9308340598663178, accuracy: 1e-12)
        XCTAssertEqual(k.bedtimeMinute, -89.7318274849963, accuracy: 1e-9)   // 22.30
        // Kvällen före natten som slutar dag 103: skulden över taket och gårdagens pass räknas.
        let k103 = try XCTUnwrap(SleepNeed.tonight(nights: nätter, passes: pass, base: 490, day: 103))
        XCTAssertEqual(k103.debtPartMinutes, 60)
        XCTAssertEqual(k103.passMinutes, 3, accuracy: 1e-9)
        XCTAssertEqual(k103.needMinutes, 553, accuracy: 1e-9)
        XCTAssertEqual(k103.bedtimeMinute, -173.70955105086432, accuracy: 1e-9)
        XCTAssertNil(SleepNeed.tonight(nights: nätter, passes: pass, base: 490, day: 100))
    }

    func testSattVäcktidFlyttarBaraLäggdags() throws {
        // BESLUT B74: väcktiden 06.30 (390) ersätter medianen 462,5; behov och skuld är de samma.
        let k = try XCTUnwrap(SleepNeed.tonight(nights: nätter, passes: pass, base: 490, day: 105, wakeMinute: 390))
        XCTAssertEqual(k.wakeMinute, 390)
        XCTAssertEqual(k.needMinutes, 500.0736830672604, accuracy: 1e-9)
        XCTAssertEqual(k.debtMinutes, 10.07368306726039, accuracy: 1e-9)
        XCTAssertEqual(k.bedtimeMinute, -162.2318274849963, accuracy: 1e-9)   // 21.18
        let k103 = try XCTUnwrap(SleepNeed.tonight(nights: nätter, passes: pass, base: 490, day: 103, wakeMinute: 390))
        XCTAssertEqual(k103.bedtimeMinute, -226.20955105086432, accuracy: 1e-9)
        XCTAssertNil(SleepNeed.tonight(nights: nätter, passes: pass, base: 490, day: 100, wakeMinute: 390))
        let d = SleepNeed.days(nights: nätter, passes: pass, whoopBase: 510, wakeMinute: 390)
        XCTAssertEqual(try XCTUnwrap(d[0].tonight).bedtimeMinute, -241.46511627906978, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d[4].tonight).bedtimeMinute, -206.03436471837222, accuracy: 1e-9)
        XCTAssertEqual(d[4].debtMinutes, 36.84657663264932, accuracy: 1e-9)   // skulden som utan väcktid
        XCTAssertEqual(d[1].needMinutes, 564, accuracy: 1e-9)
    }

    func testGrundbehovetÄrPriornOchWhoops() {
        XCTAssertEqual(SleepNeed.baseNeed(whoopBase: nil), BaseNeed(minutes: 480, sdMinutes: 30, fromWhoop: false))
        let g = SleepNeed.baseNeed(whoopBase: 510)
        XCTAssertEqual(g.minutes, 503.99999999999994, accuracy: 1e-9)     // 0,2 × 480 + 0,8 × 510
        XCTAssertEqual(g.sdMinutes, 13.416407864998737, accuracy: 1e-9)
        XCTAssertTrue(g.fromWhoop)
    }

    func testWhoopsGrundbehovEfterDeLugnasteDygnen() {
        let par: [(strain: Double, base: Double)] = [(4, 500), (12, 520), (8, 515), (15, 530), (6, 505), (10, 518),
                                                     (14, 528), (5, 498), (9, 516)]
        XCTAssertEqual(SleepNeed.whoopBase(pairs: par), 500)              // strain ≤ 6: 500, 505, 498
        XCTAssertNil(SleepNeed.whoopBase(pairs: Array(par.prefix(6))))
    }

    func testDagFörDag() throws {
        let d = SleepNeed.days(nights: nätter, passes: pass, whoopBase: 510)
        XCTAssertEqual(d.map(\.day), [100, 101, 102, 103, 104])
        let behov: [Double] = [503.99999999999994, 564, 564, 567, 548.4990550289754]
        let skuld: [Double] = [73.99999999999994, 111.99286680841169, 111.99286680841169, 44.49905502897548,
                               36.84657663264932]
        for i in 0..<5 {
            XCTAssertEqual(d[i].base.minutes, 503.99999999999994, accuracy: 1e-9)
            XCTAssertEqual(d[i].needMinutes, behov[i], accuracy: 1e-9, "dag \(d[i].day)")
            XCTAssertEqual(d[i].debtMinutes, skuld[i], accuracy: 1e-9, "dag \(d[i].day)")
        }
        XCTAssertEqual(d[3].passMinutes, 3, accuracy: 1e-9)
        XCTAssertNil(d[2].sleptMinutes)
        XCTAssertEqual(try XCTUnwrap(d[0].tonight).bedtimeMinute, -191.46511627906978, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d[4].tonight).bedtimeMinute, -133.53436471837222, accuracy: 1e-9)
        XCTAssertTrue(SleepNeed.days(nights: [], passes: []).isEmpty)
    }

    // MARK: Läggdags för bästa sömnpoäng (BESLUT B75)

    /// En natt där perioden är uppvaknande − insomning (som `natt` i test_somnbehov.py).
    private func natt(_ dag: Int, _ sov: Double, _ upp: Double, _ ins: Double) -> SleepNight {
        SleepNight(day: dag, asleepMinutes: sov, periodMinutes: upp - ins, onsetMinute: ins, wakeMinute: upp)
    }

    /// Fem nätter nära behovet och med insomning 23.20–23.35.
    private var vanliga: [SleepNight] {
        [natt(200, 490, 495, -35), natt(201, 480, 490, -40), natt(202, 495, 500, -30), natt(203, 485, 495, -25),
         natt(204, 490, 495, -40)]
    }

    /// Sex korta nätter: skulden över taket, och de fyra senaste somnar 23.00–00.00.
    private var korta: [SleepNight] {
        [natt(300, 400, 420, -20), natt(301, 380, 410, -10), natt(302, 390, 415, -60), natt(303, 370, 405, 0),
         natt(304, 385, 410, -30), natt(305, 360, 400, -15)]
    }

    func testVanligKvällGerLäggdagsFörFullSömn() throws {
        let k = try XCTUnwrap(SleepNeed.tonight(nights: vanliga, passes: [], base: 490, day: 205))
        XCTAssertEqual(k.needMinutes, 492.60245273695045, accuracy: 1e-9)
        XCTAssertEqual(k.bedtimeMinute, -52.81489785833412, accuracy: 1e-9)       // 23.07
        XCTAssertEqual(k.bestBedtimeMinute, k.bedtimeMinute)
        XCTAssertEqual(k.bestAsleepMinutes, 492.6024527369504, accuracy: 1e-9)
        XCTAssertEqual(k.bestScore, 97.72916642677015, accuracy: 1e-6)
        XCTAssertEqual(k.fullScore, k.bestScore)
    }

    func testStorSkuldGerFullSömnMedTrögheten() throws {
        // Fallet som hoppade förut (B75): läggdags 22.42 i stället för 20.17 för 0,15 poäng. Med trögheten (B84) krävs
        // minst 1 poäng mer, så full sömn gäller.
        let k = try XCTUnwrap(SleepNeed.tonight(nights: korta, passes: [], base: 490, day: 306))
        XCTAssertEqual(k.needMinutes, 550, accuracy: 1e-9)
        XCTAssertEqual(k.bedtimeMinute, -223.0602006688964, accuracy: 1e-9)       // 20.17 för full sömn
        XCTAssertEqual(k.bestBedtimeMinute, k.bedtimeMinute)
        XCTAssertEqual(k.bestAsleepMinutes, 550, accuracy: 1e-9)
        XCTAssertEqual(k.bestScore, 83.01151144520581, accuracy: 1e-6)
        XCTAssertEqual(k.fullScore, k.bestScore)
        // Med satt väcktid 06.30 (BESLUT B74).
        let s = try XCTUnwrap(SleepNeed.tonight(nights: korta, passes: [], base: 490, day: 306, wakeMinute: 390))
        XCTAssertEqual(s.bedtimeMinute, -243.0602006688964, accuracy: 1e-9)
        XCTAssertEqual(s.bestBedtimeMinute, s.bedtimeMinute)
        XCTAssertEqual(s.fullScore, 81.16089779456952, accuracy: 1e-6)
        // Dag för dag med grundbehovet 504 min: varje kväll full sömn.
        let d = SleepNeed.days(nights: korta, passes: [], whoopBase: 510)
        let väntat: [Double] = [-215.39999999999998, -221.8806682577566, -223.36842105263156, -224.3806682577566,
                                -228.36842105263156, -238.79264214046827]
        for (dag, full) in zip(d, väntat) {
            let t = try XCTUnwrap(dag.tonight)
            XCTAssertEqual(t.bedtimeMinute, full, accuracy: 1e-9, "dag \(dag.day)")
            XCTAssertEqual(t.bestBedtimeMinute, t.bedtimeMinute, "dag \(dag.day)")
        }
        XCTAssertEqual(try XCTUnwrap(d[5].tonight).bestScore, 82.02538450329428, accuracy: 1e-6)
    }

    func testTröghetenVidEnPoäng() throws {
        // B84: bästa poäng gäller bara med minst 1 poäng mer än full sömn. Grundbehovet 528 ger 0,99 poäng mer med den
        // vanliga insomningen (full sömn gäller), 530 ger 1,03 (läggdags flyttar till 22.42).
        let a = try XCTUnwrap(SleepNeed.tonight(nights: korta, passes: [], base: 528, day: 306))
        XCTAssertEqual(a.bedtimeMinute, -265.76254180602007, accuracy: 1e-9)
        XCTAssertEqual(a.bestBedtimeMinute, a.bedtimeMinute)
        XCTAssertEqual(a.bestScore, 80.25035600785355, accuracy: 1e-6)
        let b = try XCTUnwrap(SleepNeed.tonight(nights: korta, passes: [], base: 530, day: 306))
        XCTAssertEqual(b.bedtimeMinute, -268.01003344481614, accuracy: 1e-9)
        XCTAssertEqual(b.bestBedtimeMinute, -78.01003344481614, accuracy: 1e-9)  // 22.42
        XCTAssertEqual(b.bestAsleepMinutes, 420.9226190476191, accuracy: 1e-9)
        XCTAssertEqual(b.bestScore, 81.08119859877661, accuracy: 1e-6)
        XCTAssertEqual(b.fullScore, 80.05313061947125, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(b.bestScore - b.fullScore, SleepNeedRules.bestBedtimeMinGainScore)
        let vanlig = try XCTUnwrap(SleepNeed.usualOnset(korta, before: 306)) - SleepNeedRules.sleepLatencyMinutes
        XCTAssertGreaterThan(b.bestBedtimeMinute, b.bedtimeMinute)
        XCTAssertLessThan(b.bestBedtimeMinute, vanlig)
    }

    func testUtanNätterFöreGällerFullSömn() throws {
        // Ingen natt bland de fyra före natten som slutar dag 311.
        let k = try XCTUnwrap(SleepNeed.tonight(nights: korta, passes: [], base: 490, day: 311))
        XCTAssertEqual(k.bestBedtimeMinute, k.bedtimeMinute)
        XCTAssertEqual(k.bestAsleepMinutes, 550, accuracy: 1e-9)
        XCTAssertEqual(k.bestScore, 95.49107142857142, accuracy: 1e-6)            // mängd och kontinuitet
        XCTAssertEqual(k.fullScore, k.bestScore)
    }

    func testBehovetDärRegelbundenhetenTarÖver() throws {
        // Mängden tappar 120 · eff / behov delpoäng per minut, regelbundenheten vinner högst 0,2216 · eff när de
        // jämförda nätterna är vakna: över cirka 541,5 min behov ger den vanliga insomningen en högre poäng. Strax över
        // tröskeln är vinsten en hundradels poäng, och trögheten (B84) håller kvar full sömn.
        for grund in [481.0, 482.0] {
            let k = try XCTUnwrap(SleepNeed.tonight(nights: korta, passes: [], base: grund, day: 306))
            XCTAssertEqual(k.bestBedtimeMinute, k.bedtimeMinute, "grund \(grund)")
        }
    }

    func testPlaneradNattGerSammaTalSomNattensRegelbundenhet() throws {
        let dag = WakeDay(daysSince1970: 306)
        let före: [Regularity.Episode] = korta.filter { $0.day >= 302 }.compactMap(SleepNeed.episode)
        let r = try XCTUnwrap(Regularity.PlannedNight(före, day: dag, sleepFraction: 0.9))
        let t0 = 306.0 * 86400
        for (ins, upp) in [(-200.0, 400.0), (-60.0, 410.0), (-20.0, 390.0), (30.0, 450.0)] {
            let på = Date(timeIntervalSince1970: t0 + ins * 60)
            let av = Date(timeIntervalSince1970: t0 + upp * 60)
            let span = Int(upp - ins)
            let natten = Regularity.Episode(onset: på, wake: av, utcOffsetSeconds: 0, isNap: false,
                                            asleepMinutes: span * 9 / 10, inBedMinutes: span)
            let väntat = try XCTUnwrap(Regularity.nightIndex(före + [natten], day: dag))
            XCTAssertEqual(r.index(onset: på, wake: av, utcOffsetSeconds: 0), väntat, accuracy: 1e-9, "insomning \(ins)")
        }
        XCTAssertNil(Regularity.PlannedNight(före, day: WakeDay(daysSince1970: 311), sleepFraction: 0.9))
    }

    func testNattOchPassUrTiderIEnZon() {
        let zon = TimeZone(secondsFromGMT: 3600)!
        // Insomning 23.40 lokal tid, uppvaknande 06.30 dagen efter (2026-11-05).
        let n = SleepNight(onset: Date(timeIntervalSince1970: 1_793_832_000),
                           wake: Date(timeIntervalSince1970: 1_793_856_600), asleepMinutes: 380, timeZone: zon)
        XCTAssertEqual(n.day, 20762)
        XCTAssertEqual(n.onsetMinute, -20, accuracy: 1e-9)
        XCTAssertEqual(n.wakeMinute, 390, accuracy: 1e-9)
        XCTAssertEqual(n.periodMinutes, 410, accuracy: 1e-9)
        // Ett pass som stoppas 14.00 lokal tid dagen före.
        let stopp = Date(timeIntervalSince1970: 1_793_797_200)
        let p = PassDay(Pass(start: stopp.addingTimeInterval(-600), stop: stopp, kind: .bastu), maxPulse: 190, timeZone: zon)
        XCTAssertEqual(p.day, 20761)
        XCTAssertEqual(p.stopMinute, 840, accuracy: 1e-9)
        XCTAssertEqual(p.load, 0)
    }
}
