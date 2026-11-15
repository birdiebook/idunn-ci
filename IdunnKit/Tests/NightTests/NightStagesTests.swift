import Foundation
import XCTest
import HeartRate
import WhoopFrames
@testable import Night

// METOD M37 · BESLUT B45. Reglerna för natten per 30 s-epok på små, för hand räknade fall, och kedjan
// K18Night → NightResult → NightDigest på en påhittad natt ur StadierSpegelFixtur. Paritet mot Python
// ligger i StadierSpegelTests. Inget här kommer från ett riktigt band.

final class NightStagesTests: XCTestCase {

    /// En minutgräns, så att varje epok ligger inom en klockminut.
    static let onset = 1_700_000_040

    func epok(_ j: Int, _ stage: SleepStage?, wake: Double = 0.0, q: [Double] = [0.1, 0.5, 0.3, 0.1]) -> NightStages.Epoch {
        NightStages.Epoch(start: Self.onset + 30 * j, measured: stage != nil, wakeProbability: wake,
                          probabilities: q, stage: stage)
    }

    // MARK: B45: stadiet och säkerheten

    func testVakenNärPVakenNårTröskeln() {
        let q: [Double] = [0.1, 0.2, 0.5, 0.2]
        XCTAssertEqual(NightStages.decide(measured: true, wakeProbability: 0.30, probabilities: q, threshold: 0.30), .wake)
        XCTAssertEqual(NightStages.decide(measured: true, wakeProbability: 0.2999, probabilities: q, threshold: 0.30), .deep)
        XCTAssertNil(NightStages.decide(measured: false, wakeProbability: 0.99, probabilities: q, threshold: 0.30),
                     "en omätt epok är ingenting")
    }

    func testStadietÄrDetStörstaAvLättDjupOchREMOchDetFörstaViLika() {
        // Vaken i Q räknas inte, hur stor den än är.
        XCTAssertEqual(NightStages.decide(measured: true, wakeProbability: 0, probabilities: [0.9, 0.1, 0.1, 0.1],
                                          threshold: 0.3), .light)
        XCTAssertEqual(NightStages.decide(measured: true, wakeProbability: 0, probabilities: [0.0, 0.3, 0.3, 0.4],
                                          threshold: 0.3), .rem)
        XCTAssertEqual(NightStages.decide(measured: true, wakeProbability: 0, probabilities: [0.0, 0.2, 0.4, 0.4],
                                          threshold: 0.3), .deep, "lika: det första")
        XCTAssertEqual(NightStages.decide(measured: true, wakeProbability: 0, probabilities: [0.0, 0.4, 0.4, 0.2],
                                          threshold: 0.3), .light, "lika: det första")
    }

    func testSäkerhetenOchNivåerna() {
        // Vaken: P(vaken). Sömn: stadiets sannolikhet delad med summan för lätt, djup och REM.
        let vaken = epok(0, .wake, wake: 0.6)
        XCTAssertEqual(vaken.certainty, 0.6)
        XCTAssertEqual(vaken.certaintyLevel, 1)
        let latt = epok(1, .light, wake: 0.1, q: [0.4, 0.3, 0.1, 0.1])
        XCTAssertEqual(try XCTUnwrap(latt.certainty), 0.6, accuracy: 1e-12)
        XCTAssertEqual(latt.certaintyLevel, 1)
        let sakert = epok(2, .deep, wake: 0.0, q: [0.0, 0.05, 0.9, 0.05])
        XCTAssertEqual(try XCTUnwrap(sakert.certainty), 0.9, accuracy: 1e-12)
        XCTAssertEqual(sakert.certaintyLevel, 2)
        let osakert = epok(3, .rem, wake: 0.0, q: [0.0, 0.4, 0.3, 0.3])
        XCTAssertEqual(try XCTUnwrap(osakert.certainty), 0.3, accuracy: 1e-12)
        XCTAssertEqual(osakert.certaintyLevel, 0)
        let omatt = epok(4, nil)
        XCTAssertNil(omatt.certainty)
        XCTAssertNil(omatt.certaintyLevel)
        // Gränserna: under 0,5 är nivå 0, från 0,5 nivå 1, från 0,75 nivå 2.
        XCTAssertEqual(NightStages.certaintyLimits, [0.5, 0.75])
        for (c, nivå) in [(0.49999, 0), (0.5, 1), (0.74999, 1), (0.75, 2), (1.0, 2)] {
            XCTAssertEqual(epok(0, .wake, wake: c).certaintyLevel, nivå, "säkerhet \(c)")
        }
    }

    func testEpokenHarEnStartOchEttSlut() {
        let e = epok(3, .light)
        XCTAssertEqual(e.start, Self.onset + 90)
        XCTAssertEqual(e.end, Self.onset + 120)
        XCTAssertEqual(NightStages.epochSeconds, 30)
        XCTAssertEqual(NightStages.minAngleEpochs, 4)
        XCTAssertEqual(SleepStage.allCases, [.wake, .light, .deep, .rem])
        XCTAssertEqual(SleepStage.allCases.map { $0.rawValue }, [0, 1, 2, 3])
    }

    func testMinuterÄrEpokerGångerEnHalv() {
        let n = NightStages.Night(onset: Self.onset, wake: Self.onset + 150,
                                  epochs: [epok(0, .light), epok(1, .light), epok(2, .deep), epok(3, nil), epok(4, .wake)])
        XCTAssertEqual(n.minutes(.light), 1.0)
        XCTAssertEqual(n.minutes(.deep), 0.5)
        XCTAssertEqual(n.minutes(.rem), 0.0)
        XCTAssertEqual(n.minutes(.wake), 0.5)
    }

    // MARK: Perioden förfinas ur epokerna

    /// 24 epoker: lätt ×4, vaken ×2, djup ×6, omätt ×1, lätt ×1, REM ×10, och 20 s kvar efter sista epoken.
    func natt24(sistaOmätt: Bool = false) -> (period: SleepPeriod, natt: NightStages.Night) {
        var koder: [SleepStage?] = []
        koder += [SleepStage?](repeating: .light, count: 4)
        koder += [SleepStage?](repeating: .wake, count: 2)
        koder += [SleepStage?](repeating: .deep, count: 6)
        koder += [nil]
        koder += [SleepStage.light]
        koder += [SleepStage?](repeating: .rem, count: 10)
        if sistaOmätt { koder[23] = nil }
        var epoker: [NightStages.Epoch] = []
        for (j, k) in koder.enumerated() { epoker.append(epok(j, k, wake: k == .wake ? 0.8 : 0.0)) }
        let wake = Self.onset + 24 * 30 + 20
        let p = SleepPeriod(onset: Self.onset, wake: wake, windowStart: Self.onset - 300, windowEnd: wake + 300,
                            wakeBouts: [], gaps: [], asleepSeconds: 1, awakeSeconds: 2, gapSeconds: 3,
                            threshold: 0.21, asleepMinutes: [1, 2, 3])
        return (p, NightStages.Night(onset: Self.onset, wake: wake, epochs: epoker))
    }

    func testPeriodenFörfinas() {
        let (p, natt) = natt24()
        let r = NightStages.refine(p, with: natt)
        // Oförändrat: insomning, uppvaknande, blocket och tröskeln.
        XCTAssertEqual(r.onset, p.onset)
        XCTAssertEqual(r.wake, p.wake)
        XCTAssertEqual(r.windowStart, p.windowStart)
        XCTAssertEqual(r.windowEnd, p.windowEnd)
        XCTAssertEqual(r.threshold, 0.21)
        // Sömn är lätt + djup + REM: 5 + 6 + 10 epoker. Vaken: 2. Glapp: den omätta epoken och resten.
        XCTAssertEqual(r.asleepSeconds, 21 * 30)
        XCTAssertEqual(r.awakeSeconds, 2 * 30)
        XCTAssertEqual(r.gapSeconds, 30 + 20)
        XCTAssertEqual(r.asleepSeconds + r.awakeSeconds + r.gapSeconds, r.wake - r.onset, "sömn + vaken + glapp = perioden")
        XCTAssertEqual(r.wakeBouts, [SleepInterval(start: Self.onset + 120, end: Self.onset + 180)])
        XCTAssertEqual(r.gaps, [SleepInterval(start: Self.onset + 360, end: Self.onset + 390),
                                SleepInterval(start: Self.onset + 720, end: Self.onset + 740)])
        XCTAssertEqual(r.asleepMinutesTotal, natt.minutes(.light) + natt.minutes(.deep) + natt.minutes(.rem),
                       accuracy: 1e-12)
        // Sömnminuter: minst 7 av 12 femsekundsepoker. Minut 6 har bara en sömnepok (6 av 12): inte med.
        let m0: Int = Self.onset / 60
        XCTAssertEqual(r.asleepMinutes, [m0, m0 + 1, m0 + 3, m0 + 4, m0 + 5, m0 + 7, m0 + 8, m0 + 9, m0 + 10, m0 + 11])
    }

    func testRestenSlåsIhopMedEttGlappSomSlutarDär() {
        let (p, natt) = natt24(sistaOmätt: true)
        let r = NightStages.refine(p, with: natt)
        XCTAssertEqual(r.gaps, [SleepInterval(start: Self.onset + 360, end: Self.onset + 390),
                                SleepInterval(start: Self.onset + 690, end: Self.onset + 740)],
                       "sista epoken omätt och resten: ett glapp")
        XCTAssertEqual(r.gapSeconds, 30 + 30 + 20)
        XCTAssertEqual(r.asleepSeconds, 20 * 30)
    }

    func testEnPeriodUtanRestHarIngenRestGlapp() {
        let wake = Self.onset + 60
        let p = SleepPeriod(onset: Self.onset, wake: wake, windowStart: Self.onset, windowEnd: wake, wakeBouts: [],
                            gaps: [], asleepSeconds: 0, awakeSeconds: 0, gapSeconds: 0, threshold: 0.2, asleepMinutes: [])
        let r = NightStages.refine(p, with: NightStages.Night(onset: Self.onset, wake: wake,
                                                              epochs: [epok(0, .light), epok(1, .light)]))
        XCTAssertTrue(r.gaps.isEmpty)
        XCTAssertEqual(r.gapSeconds, 0)
        XCTAssertEqual(r.asleepMinutes, [Self.onset / 60])
    }

    // MARK: Spannen och lagren

    func testSpannenÄrFöljderMedSammaStadiumOchNivånUrMedlet() {
        // BESLUT B85: en ruta per följd med samma stadium, nivån ur medlet av epokernas säkerhet; den omätta
        // epoken bryter.
        let natt = NightStages.Night(onset: Self.onset, wake: Self.onset + 240, epochs: [
            epok(0, .light, q: [0.0, 0.6, 0.2, 0.2]),                // 0,6: nivå 1
            epok(1, .light, q: [0.0, 0.6, 0.2, 0.2]),                // 0,6
            epok(2, .light, q: [0.0, 0.9, 0.05, 0.05]),              // 0,9: nivå 2 för sig, men samma följd
            epok(3, nil),
            epok(4, .light, q: [0.0, 0.9, 0.05, 0.05]),              // efter ett hål: ny följd
            epok(5, .wake, wake: 0.7),
            epok(6, .wake, wake: 0.8),
            epok(7, .wake, wake: 0.8),
        ])
        let spann = NightLayers.stageSpans(natt)
        let o = Double(Self.onset)
        XCTAssertEqual(spann, [
            NightLayers.StageSpan(start: o, end: o + 90, stage: .light, certainty: 1),       // medel 0,7
            NightLayers.StageSpan(start: o + 120, end: o + 150, stage: .light, certainty: 2),
            NightLayers.StageSpan(start: o + 150, end: o + 240, stage: .wake, certainty: 2),  // medel 0,77
        ])
        XCTAssertEqual(NightLayers.stageSpans(nil), [])
        XCTAssertEqual(spann[0].range, o...(o + 90))
        // Den lätta följden: nivå 1, 1, 2 per epok, men en ruta.
        XCTAssertEqual(natt.epochs[0...2].map { $0.certaintyLevel }, [1, 1, 2])
    }

    // MARK: Lugnare stadier (BESLUT B85)

    typealias Påhittad = (wake: Double, q: [Double])
    // Samma fall och svar som `LugnareB85` i tools/tests/test_natt_stadier.py.
    static let W: Påhittad = (0.8, [0.1, 0.3, 0.3, 0.3])
    static let L: Påhittad = (0.05, [0.1, 0.63, 0.18, 0.09])
    static let D: Påhittad = (0.05, [0.1, 0.18, 0.63, 0.09])          // djup, lätt näst störst
    static let R: Påhittad = (0.05, [0.1, 0.18, 0.09, 0.63])          // REM, lätt näst störst
    static let Rd: Påhittad = (0.05, [0.1, 0.09, 0.18, 0.63])         // REM, djup näst störst
    static let X: Påhittad = (0.05, [0.1, 0.15, 0.15, 0.6])           // REM där lätt och djup är exakt lika
    static let Rv: Påhittad = (0.29, [0.1, 0.18, 0.09, 0.63])         // REM strax under tröskeln

    func n(_ e: Påhittad?, _ k: Int) -> [Påhittad?] { [Påhittad?](repeating: e, count: k) }

    /// B45 och sedan B85 för påhittade epoker (`nil` = omätt), som stadiernas råa värden (−1 = omätt).
    func lugnat(_ seq: [Påhittad?]) -> [Int] {
        var ep: [NightStages.Epoch] = []
        for (j, e) in seq.enumerated() {
            if let e = e {
                let s = NightStages.decide(measured: true, wakeProbability: e.wake, probabilities: e.q, threshold: 0.3)
                ep.append(NightStages.Epoch(start: Self.onset + 30 * j, measured: true, wakeProbability: e.wake,
                                            probabilities: e.q, stage: s))
            } else {
                ep.append(NightStages.Epoch(start: Self.onset + 30 * j, measured: false, wakeProbability: 0,
                                            probabilities: [0.25, 0.25, 0.25, 0.25], stage: nil))
            }
        }
        return NightStages.settle(ep, threshold: 0.3).map { (e: NightStages.Epoch) -> Int in e.stage?.rawValue ?? -1 }
    }

    func r(_ v: Int, _ k: Int) -> [Int] { [Int](repeating: v, count: k) }

    func testPoängensArgMaxÄrB45() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let pv = Double.random(in: 0..<1, using: &g)
            var q: [Double] = (0..<4).map { _ in Double.random(in: 0..<1, using: &g) + 1e-3 }
            let sum = q.reduce(0, +)
            q = q.map { $0 / sum }
            let p = NightStages.score(wakeProbability: pv, probabilities: q, threshold: 0.3)
            var best = 1
            for s in 2...3 where p[s] > p[best] { best = s }
            let viaPoäng = p[0] >= p[best] ? 0 : best
            XCTAssertEqual(viaPoäng, NightStages.decide(measured: true, wakeProbability: pv, probabilities: q,
                                                        threshold: 0.3)?.rawValue)
        }
    }

    func testMinstaLängdenÄrFyraEpoker() {
        XCTAssertEqual(NightStages.minSleepRunEpochs, 4)
        XCTAssertEqual(lugnat(n(Self.L, 6) + n(Self.D, 3) + n(Self.L, 6)), r(1, 15))
        XCTAssertEqual(lugnat(n(Self.L, 6) + n(Self.D, 4) + n(Self.L, 6)), r(1, 6) + r(2, 4) + r(1, 6))
    }

    func testVakenKortasAldrig() {
        // En ensam vaken epok står kvar; en ensam REM mellan vakna epoker blir vaken.
        XCTAssertEqual(lugnat(n(Self.L, 6) + [Self.W] + n(Self.L, 6) + [Self.W, Self.W, Self.R, Self.W]),
                       r(1, 6) + [0] + r(1, 6) + [0, 0, 0, 0])
    }

    func testEnKortSömnbitKanBliVakenGenomPoängen() {
        XCTAssertEqual(lugnat(n(Self.L, 4) + [Self.Rv] + n(Self.W, 4)), r(1, 4) + r(0, 5))
    }

    func testKortasteFöljdenFörst() {
        // REM (1) före djup (3): REM går till djup, som då är fyra epoker och står kvar.
        XCTAssertEqual(lugnat(n(Self.L, 4) + n(Self.D, 3) + [Self.Rd] + n(Self.W, 4)), r(1, 4) + r(2, 4) + r(0, 4))
    }

    func testTidigasteVidLikaLängd() {
        // Djup (2) före REM (2): djup går till lätt, sedan REM till lätt.
        XCTAssertEqual(lugnat(n(Self.L, 4) + n(Self.D, 2) + n(Self.Rd, 2) + n(Self.W, 4)), r(1, 8) + r(0, 4))
    }

    func testVänsterGrannVidLikaPoäng() {
        XCTAssertEqual(lugnat(n(Self.L, 4) + [Self.X] + n(Self.D, 4)), r(1, 5) + r(2, 4))
        XCTAssertEqual(lugnat(n(Self.D, 4) + [Self.X] + n(Self.L, 4)), r(2, 5) + r(1, 4))
    }

    func testGlappBryterOchRörsInte() {
        XCTAssertEqual(lugnat(n(Self.L, 5) + [nil, Self.D, nil] + n(Self.L, 5)), r(1, 5) + [-1, 2, -1] + r(1, 5))
        XCTAssertEqual(lugnat(n(Self.L, 5) + [Self.D, nil] + n(Self.R, 5)), r(1, 6) + [-1] + r(3, 5))
    }

    func testEnOmdöptEpokFårSäkerhetenFörSittNyaStadium() throws {
        // REM-epoken mellan lätta blir lätt; säkerheten är då lättas andel, 0,18 / 0,9 = 0,2: nivå 0.
        var ep: [NightStages.Epoch] = []
        for (j, x) in (n(Self.L, 4) + [Self.R] + n(Self.L, 4)).enumerated() {
            let e: Påhittad = try XCTUnwrap(x)
            ep.append(NightStages.Epoch(start: Self.onset + 30 * j, measured: true, wakeProbability: e.wake,
                                        probabilities: e.q,
                                        stage: NightStages.decide(measured: true, wakeProbability: e.wake,
                                                                  probabilities: e.q, threshold: 0.3)))
        }
        let ut = NightStages.settle(ep, threshold: 0.3)
        XCTAssertEqual(ut[4].stage, .light)
        XCTAssertEqual(try XCTUnwrap(ut[4].certainty), 0.2, accuracy: 1e-12)
        XCTAssertEqual(ut[4].certaintyLevel, 0)
        XCTAssertEqual(ut[4].wakeProbability, ep[4].wakeProbability, "modellernas tal är orörda")
        XCTAssertEqual(ut[4].probabilities, ep[4].probabilities)
        // Bandet: en ruta, nivån ur medlet (8 × 0,7 + 0,2) / 9 = 0,64: nivå 1.
        let spann = NightLayers.stageSpans(NightStages.Night(onset: Self.onset, wake: Self.onset + 270, epochs: ut))
        XCTAssertEqual(spann.count, 1)
        XCTAssertEqual(spann.first?.certainty, 1)
    }

    func testLagrenSlårUpStadietVidEnTid() {
        let o = Double(Self.onset)
        let spann: [NightLayers.StageSpan] = [
            NightLayers.StageSpan(start: o, end: o + 60, stage: .light, certainty: 1),
            NightLayers.StageSpan(start: o + 60, end: o + 90, stage: .deep, certainty: 2),
        ]
        let l = NightLayers.Layers(start: o, end: o + 120, minutes: [], gaps: [], period: o...(o + 120), asleep: [],
                                   awake: [], coverage: nil, stages: spann)
        XCTAssertEqual(l.stage(at: o)?.stage, .light)
        XCTAssertEqual(l.stage(at: o + 59.9)?.stage, .light)
        XCTAssertEqual(l.stage(at: o + 60)?.stage, .deep, "start <= t < end: gränsen hör till nästa")
        XCTAssertNil(l.stage(at: o + 90), "slutet ingår inte")
        XCTAssertNil(l.stage(at: o - 1))
        XCTAssertNil(l.stage(at: o + 100))
        // Utan stadier är spannen tomma.
        let utan = NightLayers.Layers(start: o, end: o + 120, minutes: [], gaps: [], period: o...(o + 120), asleep: [],
                                      awake: [], coverage: nil)
        XCTAssertTrue(utan.stages.isEmpty)
        XCTAssertNil(utan.stage(at: o))
    }

    // MARK: Kedjan: K18Night, NightResult, NightDigest

    func fixturnatt(_ namn: String) throws -> StadierSpegelFixtur.Natt {
        try XCTUnwrap(StadierSpegelFixtur.natter.first { (n: StadierSpegelFixtur.Natt) -> Bool in n.namn == namn })
    }

    func perioden(_ n: StadierSpegelFixtur.Natt) -> SleepPeriod {
        SleepPeriod(onset: n.onset, wake: n.wake, windowStart: n.onset, windowEnd: n.wake, wakeBouts: [], gaps: [],
                    asleepSeconds: n.wake - n.onset, awakeSeconds: 0, gapSeconds: 0, threshold: 0.3, asleepMinutes: [])
    }

    func testNattenUrK18HarStadierOchPeriodenÄrFörfinad() throws {
        let n = try fixturnatt("cykler")
        let serie = StadierFixturLasare.series(n)
        let r = K18Night.analyze(serie, sleep: perioden(n), utcOffsetSeconds: 0)
        let stadier = try XCTUnwrap(r.stages, "natten har stadier")
        let s = try XCTUnwrap(r.sleep)
        XCTAssertEqual(r.source, .k18)
        XCTAssertEqual(s.onset, n.onset)
        XCTAssertEqual(s.wake, n.wake)
        XCTAssertEqual(stadier.epochs.count, n.epoker)
        // Sömnen i perioden är summan av lätt, djup och REM (B45).
        let somn: Double = stadier.minutes(.light) + stadier.minutes(.deep) + stadier.minutes(.rem)
        XCTAssertEqual(s.asleepMinutesTotal, somn, accuracy: 1e-9)
        XCTAssertEqual(stadier.minutes(.light), n.minuter[1], accuracy: 1e-12)
        XCTAssertEqual(s.asleepSeconds + s.awakeSeconds + s.gapSeconds, s.wake - s.onset)
        XCTAssertGreaterThan(s.awakeSeconds, 0, "natten har vakna epoker")
        XCTAssertEqual(s.wakeBouts.count, StadierSpegelFixtur.cykler.vakna.count)
        // Lagren bär stadierna.
        let l = try XCTUnwrap(r.layers)
        XCTAssertFalse(l.stages.isEmpty)
        XCTAssertEqual(l.stages, NightLayers.stageSpans(stadier))
        XCTAssertEqual(l.period.lowerBound, Double(n.onset))
        XCTAssertEqual(l.period.upperBound, Double(n.wake))
        let mitt: Double = Double(n.onset) + 15
        XCTAssertNotNil(l.stage(at: mitt))
        XCTAssertEqual(l.stage(at: mitt)?.stage, stadier.epochs[0].stage)
        // Hudtemperaturen följer den förfinade periodens sömnminuter.
        XCTAssertEqual(r.skin?.basis, .sleepPeriod)
        // Samma resultat som utan lagren: stadierna lägger bara till.
        let utan = NightStages.estimate(serie, onset: n.onset, wake: n.wake,
                                        beats: RRCleaning.clean(K18Beats.recording(serie, onset: n.onset, wake: n.wake)))
        XCTAssertEqual(r.stages, utan)
    }

    func testSammanfattningenBärMedelpulsenOchMinuternaPerStadium() throws {
        let n = try fixturnatt("cykler")
        let r = K18Night.analyze(StadierFixturLasare.series(n), sleep: perioden(n), utcOffsetSeconds: 0)
        let d = NightDigest(r)
        let stadier = try XCTUnwrap(r.stages)
        XCTAssertEqual(d.lightMinutes, stadier.minutes(.light))
        XCTAssertEqual(d.deepMinutes, stadier.minutes(.deep))
        XCTAssertEqual(d.remMinutes, stadier.minutes(.rem))
        XCTAssertNotNil(r.analysis.meanHeartRate)
        XCTAssertEqual(d.meanHeartRate, r.analysis.meanHeartRate)
        let mp = try XCTUnwrap(d.meanHeartRate)
        XCTAssertTrue(mp > 40 && mp < 100, "en rimlig medelpuls: \(mp)")
        XCTAssertEqual(d.sleepMinutes, r.sleep?.asleepMinutesTotal)
        // Trenderna och kortet ser medelpulsen.
        XCTAssertEqual(d.idunNight.meanHeartRate, d.meanHeartRate)
        let v = Trends.idunValues([d.idunNight])
        XCTAssertEqual(v[.meanHeartRate]?.count ?? 0, d.validWindows >= Trends.minValidWindows ? 1 : 0)
        // Sparas och läses igen.
        let data = try JSONEncoder().encode(d)
        XCTAssertEqual(try JSONDecoder().decode(NightDigest.self, from: data), d)
    }

    func testEnGammalSparadSammanfattningUtanDeNyaFältenAvkodasÄndå() throws {
        let n = try fixturnatt("cykler")
        let d = NightDigest(K18Night.analyze(StadierFixturLasare.series(n), sleep: perioden(n), utcOffsetSeconds: 0))
        XCTAssertNotNil(d.deepMinutes)
        let data = try JSONEncoder().encode(d)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for k in ["meanHeartRate", "lightMinutes", "deepMinutes", "remMinutes"] {
            XCTAssertNotNil(obj[k], k)
            obj.removeValue(forKey: k)
        }
        let gammal = try JSONSerialization.data(withJSONObject: obj)
        let tillbaka = try JSONDecoder().decode(NightDigest.self, from: gammal)
        XCTAssertNil(tillbaka.meanHeartRate)
        XCTAssertNil(tillbaka.lightMinutes)
        XCTAssertNil(tillbaka.deepMinutes)
        XCTAssertNil(tillbaka.remMinutes)
        XCTAssertEqual(try XCTUnwrap(tillbaka.rmssdMean), try XCTUnwrap(d.rmssdMean), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(tillbaka.sleepMinutes), try XCTUnwrap(d.sleepMinutes), accuracy: 1e-9)
    }

    func testEnGammalInspelningHarIngaStadierOchIngenMedelpulsISammanfattningen() throws {
        let n = try fixturnatt("cykler")
        let serie = StadierFixturLasare.series(n)
        // Samma slag som en 2A37-inspelning: hela inspelningen är natten, ingen sömnperiod.
        let rec: NightRecording = K18Beats.recording(serie, onset: n.onset, wake: n.wake)
        let r = NightResult.fromNotifications(rec, utcOffsetSeconds: 0)
        XCTAssertEqual(r.source, .notification)
        XCTAssertNil(r.sleep)
        XCTAssertNil(r.stages)
        XCTAssertNil(r.layers)
        XCTAssertNotNil(r.analysis.meanHeartRate, "analysen räknar den ändå")
        let d = NightDigest(r)
        XCTAssertNil(d.meanHeartRate, "bara en natt med sömnperiod har medelpuls")
        XCTAssertNil(d.lightMinutes)
        XCTAssertNil(d.deepMinutes)
        XCTAssertNil(d.remMinutes)
        XCTAssertNil(d.idunNight.meanHeartRate)
    }
}
