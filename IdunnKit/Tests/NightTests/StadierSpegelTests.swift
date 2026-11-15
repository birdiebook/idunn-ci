import Foundation
import XCTest
import WhoopFrames
@testable import Night

// METOD M37. Paritet mot Python-spegeln tools/natt_stadier.py: samma påhittade nätter
// (StadierSpegelFixtur, som skrivs av tools/tests/stadier_fixtur.py) ska ge samma
// särdrag, samma sannolikheter, samma stadier (efter BESLUT B85:s utjämning), samma
// förfinade period och samma spann (nivån ur medlet per följd, B85). Fäller provet har
// spegeln och IdunnKit glidit isär, och talen i M37 gäller inte appen.
//
// Toleranser (M37): de råa särdragen |Swift − Python| <= 1e-7·|Python| + 1e-9 (saknat
// mot saknat); P(vaken) och sannolikheterna 1e-7 absolut; mätt, stadium, nivå, minuter,
// den förfinade perioden och spannen exakt. Fixturen kräver marginal >= 1e-6 till varje
// gräns, så att en exakt jämförelse inte kan fällas av avrundning. Spektrumet 1e-9
// relativt bandets största bin; DFA som särdragen. Raderna är påhittade (CLAUDE.md §Dataregeln).

final class StadierSpegelTests: XCTestCase {

    // MARK: Raderna blir poster (StadierFixturLasare)

    func tal(_ rad: Substring) -> [Double] { StadierFixturLasare.numbers(rad) }

    func poster(_ n: StadierSpegelFixtur.Natt) -> [K18Record] { StadierFixturLasare.records(n) }

    func serie(_ n: StadierSpegelFixtur.Natt) -> K18Series { StadierFixturLasare.series(n) }

    func slag(_ n: StadierSpegelFixtur.Natt, _ serie: K18Series) -> [Beat] {
        RRCleaning.clean(K18Beats.recording(serie, onset: n.onset, wake: n.wake))
    }

    // MARK: Jämförelser

    /// |a − b| <= 1e-7·|b| + 1e-9, eller båda saknade.
    func närNog(_ a: Double, _ b: Double) -> Bool {
        if a.isNaN || b.isNaN { return a.isNaN && b.isNaN }
        return abs(a - b) <= 1e-7 * abs(b) + 1e-9
    }

    func period(_ n: StadierSpegelFixtur.Natt) -> SleepPeriod {
        SleepPeriod(onset: n.onset, wake: n.wake, windowStart: n.onset - 600, windowEnd: n.wake + 600,
                    wakeBouts: [], gaps: [], asleepSeconds: 0, awakeSeconds: 0, gapSeconds: 0,
                    threshold: 0.25, asleepMinutes: [])
    }

    func par(_ i: SleepInterval) -> [Int] { [i.start, i.end] }

    // MARK: Nätterna

    func testFixturenHarFemNätterOchRadernaÄrHeltal() {
        XCTAssertEqual(StadierSpegelFixtur.natter.map { $0.namn }, ["cykler", "orolig", "kort", "utanslag", "pyttekort"])
        for n in StadierSpegelFixtur.natter {
            XCTAssertEqual(n.onset % 5, 0, "\(n.namn): insomning på en femsekundersgräns")
            XCTAssertNotEqual(n.onset % 30, 0, "\(n.namn): men inte på en epokgräns")
            XCTAssertNotEqual((n.wake - n.onset) % 30, 0, "\(n.namn): en rest efter sista epoken")
            XCTAssertEqual(n.epoker, (n.wake - n.onset) / 30, n.namn)
            XCTAssertGreaterThan(poster(n).count, 100, n.namn)
        }
    }

    func testSlagenOchSkillnadernaÄrDeSammaSomPythons() {
        for n in StadierSpegelFixtur.natter {
            let s = serie(n)
            let beats = slag(n, s)
            XCTAssertEqual(beats.filter { (b: Beat) -> Bool in b.isKept }.count, n.slag, "\(n.namn): behållna slag")
            XCTAssertEqual(RRCleaning.differences(beats).count, n.skillnader, "\(n.namn): skillnader")
        }
    }

    func testAllaNätterGerSammaStadierSomPythonSpegeln() throws {
        for n in StadierSpegelFixtur.natter {
            let s = serie(n)
            let beats = slag(n, s)
            let natt = try XCTUnwrap(NightStages.estimate(s, onset: n.onset, wake: n.wake, beats: beats), n.namn)
            XCTAssertEqual(natt.onset, n.onset)
            XCTAssertEqual(natt.wake, n.wake)
            XCTAssertEqual(natt.epochs.count, n.epoker, "\(n.namn): epoker")

            let rader: [Substring] = n.epokrader.split(separator: "\n")
            XCTAssertEqual(rader.count, n.epoker, n.namn)
            var matta: Int = 0
            var hist = [Int](repeating: 0, count: 5)
            for (j, rad) in rader.enumerated() {
                let f: [Double] = tal(rad)                   // mätt, P(vaken), Q0…Q3, stadium, nivå
                let e: NightStages.Epoch = natt.epochs[j]
                XCTAssertEqual(e.start, n.onset + 30 * j, "\(n.namn) epok \(j): start")
                XCTAssertEqual(e.end, e.start + 30)
                XCTAssertEqual(e.measured, f[0] == 1, "\(n.namn) epok \(j): mätt")
                XCTAssertEqual(e.wakeProbability, f[1], accuracy: 1e-7, "\(n.namn) epok \(j): P(vaken)")
                XCTAssertEqual(e.probabilities.count, 4)
                var summa: Double = 0
                for c in 0..<4 {
                    XCTAssertEqual(e.probabilities[c], f[2 + c], accuracy: 1e-7, "\(n.namn) epok \(j): Q\(c)")
                    summa += e.probabilities[c]
                }
                XCTAssertEqual(summa, 1.0, accuracy: 1e-12, "\(n.namn) epok \(j): summan")
                XCTAssertEqual(e.stage?.rawValue ?? -1, Int(f[6]), "\(n.namn) epok \(j): stadium")
                XCTAssertEqual(e.certaintyLevel ?? -1, Int(f[7]), "\(n.namn) epok \(j): nivå")
                if e.measured { matta += 1 }
                hist[(e.stage?.rawValue ?? -1) + 1] += 1
            }
            XCTAssertGreaterThan(matta, 0, n.namn)

            // Minuterna per stadium.
            XCTAssertEqual(n.minuter.count, 4)
            for st in SleepStage.allCases {
                XCTAssertEqual(natt.minutes(st), n.minuter[st.rawValue], accuracy: 1e-12, "\(n.namn): minuter \(st)")
            }
            let staged: Int = hist[1] + hist[2] + hist[3] + hist[4]
            var allaMinuter: Double = 0
            for st in SleepStage.allCases { allaMinuter += natt.minutes(st) }
            XCTAssertEqual(allaMinuter, Double(staged) * 0.5, accuracy: 1e-12, "\(n.namn): minuter är epoker × 0,5")
        }
    }

    func testFixturensNätterProvarDetDeSkaProva() throws {
        func natt(_ namn: String) throws -> StadierSpegelFixtur.Natt {
            try XCTUnwrap(StadierSpegelFixtur.natter.first { (n: StadierSpegelFixtur.Natt) -> Bool in n.namn == namn })
        }
        let cykler = try natt("cykler")
        XCTAssertGreaterThanOrEqual(cykler.epoker, 400)
        for m in cykler.minuter { XCTAssertGreaterThan(m, 0, "alla fyra stadierna finns i facit") }
        XCTAssertGreaterThanOrEqual(try natt("orolig").glapp.count, 2, "glappen på 4 min och 70 s")
        XCTAssertEqual(try natt("utanslag").slag, 0, "utan RR finns inga slag")
        XCTAssertEqual(try natt("pyttekort").epoker, 8)
    }

    func testDeRåaSärdragenGerSammaTalSomPython() throws {
        for n in StadierSpegelFixtur.natter {
            let s = serie(n)
            let beats = slag(n, s)
            let rorelse = NightFeatures.movement(s, onset: n.onset, epochs: n.epoker)
            let hjarta: [[Double]] = NightFeatures.heart(beats, onset: n.onset, epochs: n.epoker)
            XCTAssertEqual(rorelse.rows.count, n.epoker)
            XCTAssertEqual(hjarta.count, n.epoker)
            var prövade = 0
            var saknade = 0
            for rad in n.sardragsrader.split(separator: "\n") {
                let f: [Double] = tal(rad)
                XCTAssertEqual(f.count, 20, "\(n.namn): index och 19 särdrag")
                let j: Int = Int(f[0])
                let swift: [Double] = rorelse.rows[j] + hjarta[j]
                XCTAssertEqual(swift.count, 19)
                for c in 0..<19 {
                    XCTAssertTrue(närNog(swift[c], f[c + 1]),
                                  "\(n.namn) epok \(j) särdrag \(c): \(swift[c]) mot \(f[c + 1])")
                    if f[c + 1].isNaN { saknade += 1 }
                }
                prövade += 1
            }
            XCTAssertGreaterThanOrEqual(prövade, min(n.epoker, 24), n.namn)
            if n.namn == "utanslag" { XCTAssertGreaterThan(saknade, 0, "utan RR saknas alla HRV-värden") }
        }
    }

    func testDenFörfinadePeriodenGerSammaSomPython() throws {
        for n in StadierSpegelFixtur.natter {
            let s = serie(n)
            let natt = try XCTUnwrap(NightStages.estimate(s, onset: n.onset, wake: n.wake, beats: slag(n, s)), n.namn)
            let p = period(n)
            let r: SleepPeriod = NightStages.refine(p, with: natt)
            // Oförändrat: insomning, uppvaknande, blocket och tröskeln.
            XCTAssertEqual(r.onset, p.onset)
            XCTAssertEqual(r.wake, p.wake)
            XCTAssertEqual(r.windowStart, p.windowStart)
            XCTAssertEqual(r.windowEnd, p.windowEnd)
            XCTAssertEqual(r.threshold, p.threshold)
            XCTAssertEqual(r.asleepSeconds, n.somnSekunder, "\(n.namn): sömn")
            XCTAssertEqual(r.awakeSeconds, n.vakenSekunder, "\(n.namn): vaken")
            XCTAssertEqual(r.gapSeconds, n.glappSekunder, "\(n.namn): glapp")
            XCTAssertEqual(r.asleepSeconds + r.awakeSeconds + r.gapSeconds, r.wake - r.onset, "\(n.namn): summan")
            XCTAssertEqual(r.wakeBouts.map { self.par($0) }, n.vakna, "\(n.namn): vakna stunder")
            XCTAssertEqual(r.gaps.map { self.par($0) }, n.glapp, "\(n.namn): glapp")
            let minuter: [Int] = n.somnminuter.flatMap { (x: [Int]) -> [Int] in Array(x[0]...x[1]) }
            XCTAssertEqual(r.asleepMinutes, minuter, "\(n.namn): sömnminuter")
            XCTAssertEqual(r.asleepMinutesTotal, natt.minutes(.light) + natt.minutes(.deep) + natt.minutes(.rem),
                           accuracy: 1e-9, "\(n.namn): sömntiden är lätt + djup + REM")
        }
    }

    func testSpannenGerSammaSomPython() throws {
        for n in StadierSpegelFixtur.natter {
            let s = serie(n)
            let natt = try XCTUnwrap(NightStages.estimate(s, onset: n.onset, wake: n.wake, beats: slag(n, s)), n.namn)
            let spann: [NightLayers.StageSpan] = NightLayers.stageSpans(natt)
            let som: [[Int]] = spann.map { (x: NightLayers.StageSpan) -> [Int] in
                [Int(x.start), Int(x.end), x.stage.rawValue, x.certainty]
            }
            XCTAssertEqual(som, n.spann, "\(n.namn): spann")
            for x in spann {
                XCTAssertEqual(x.range, x.start...x.end)
            }
        }
    }

    // MARK: Delarna för sig

    func testSpektrumetGerSammaEffektSomNumpy() {
        let x: [Double] = StadierSpegelFixtur.spektrumVarden.split(separator: ",").map { (v: Substring) -> Double in
            Double(String(v)) ?? Double.nan
        }
        let facit: [Double] = tal(Substring(StadierSpegelFixtur.spektrumEffekt))
        XCTAssertEqual(x.count, 480)
        XCTAssertEqual(facit.count, 51)
        let p: [Double] = NightFeatures.periodogram(x)
        XCTAssertEqual(p.count, 51)
        let störst: Double = facit.max() ?? 1
        for m in 0..<51 {
            XCTAssertEqual(p[m], facit[m], accuracy: 1e-9 * störst, "bin \(m)")
        }
    }

    func testDFAGerSammaAlfaSomNumpy() {
        XCTAssertEqual(StadierSpegelFixtur.dfaprov.count, 3)
        for d in StadierSpegelFixtur.dfaprov {
            let a: Double = NightFeatures.dfaAlpha1(d.rr)
            XCTAssertTrue(närNog(a, d.alfa), "\(d.namn): \(a) mot \(d.alfa)")
        }
    }

    func testFrekvensbandenLiggerInomBinnarnaSomSpektrumetRäknar() {
        let hf: [Int] = NightFeatures.highBins
        let lf: [Int] = NightFeatures.lowBins
        XCTAssertFalse(hf.isEmpty)
        XCTAssertFalse(lf.isEmpty)
        XCTAssertGreaterThanOrEqual(hf.first ?? 0, 1)
        XCTAssertLessThanOrEqual((hf.last ?? 99) + 1, 49 + 1, "toppens granne ryms")
        XCTAssertLessThan(lf.last ?? 99, hf.first ?? 0, "LF ligger under HF")
        XCTAssertEqual(NightFeatures.frequencies.count, 51)
        // Python: LF 0,04 ≤ f < 0,15 och HF 0,15 ≤ f ≤ 0,40 i bin om 1/120 Hz.
        XCTAssertEqual(lf.first, 5)
        XCTAssertEqual(lf.last, 17)
        XCTAssertEqual(hf.first, 18)
        XCTAssertEqual(hf.last, 48)
    }

    func testBinärsökningenOchInterpolationenÄrNumpys() {
        let a: [Double] = [1, 2, 2, 4]
        XCTAssertEqual(NightFeatures.lowerBound(a, 0), 0)
        XCTAssertEqual(NightFeatures.lowerBound(a, 2), 1, "första index med värde >= x")
        XCTAssertEqual(NightFeatures.lowerBound(a, 3), 3)
        XCTAssertEqual(NightFeatures.lowerBound(a, 5), 4)
        let xp: [Double] = [0, 1, 3]
        let fp: [Double] = [10, 20, 40]
        XCTAssertEqual(NightFeatures.interpolate(-1, xp, fp), 10, "före första: första värdet")
        XCTAssertEqual(NightFeatures.interpolate(5, xp, fp), 40, "efter sista: sista värdet")
        XCTAssertEqual(NightFeatures.interpolate(0.5, xp, fp), 15, accuracy: 1e-12)
        XCTAssertEqual(NightFeatures.interpolate(2, xp, fp), 30, accuracy: 1e-12)
        XCTAssertEqual(NightFeatures.interpolate(3, xp, fp), 40, "på sista punkten")
        XCTAssertEqual(NightFeatures.interpolate(1, xp, fp), 20, "på en punkt")
    }

    func testEnPeriodKortareÄnEnEpokGerIngenNatt() throws {
        let n = try XCTUnwrap(StadierSpegelFixtur.natter.first)
        let s = serie(n)
        XCTAssertNil(NightStages.estimate(s, onset: n.onset, wake: n.onset + 25, beats: []))
        XCTAssertNil(NightStages.estimate(s, onset: n.onset, wake: n.onset, beats: []))
        XCTAssertNil(NightStages.estimate(s, onset: n.onset, wake: n.onset - 60, beats: []))
    }

    func testUtanPosterÄrAllaEpokerOmättaOchPeriodenEttGlapp() throws {
        let onset = 1_760_000_040
        let wake = onset + 3_600
        let natt = try XCTUnwrap(NightStages.estimate(K18Series(records: []), onset: onset, wake: wake, beats: []))
        XCTAssertEqual(natt.epochs.count, 120)
        XCTAssertTrue(natt.epochs.allSatisfy { (e: NightStages.Epoch) -> Bool in !e.measured && e.stage == nil })
        XCTAssertTrue(natt.epochs.allSatisfy { (e: NightStages.Epoch) -> Bool in
            e.certainty == nil && e.certaintyLevel == nil
        })
        for st in SleepStage.allCases { XCTAssertEqual(natt.minutes(st), 0) }
        let p = SleepPeriod(onset: onset, wake: wake, windowStart: onset, windowEnd: wake, wakeBouts: [], gaps: [],
                            asleepSeconds: 999, awakeSeconds: 999, gapSeconds: 0, threshold: 0.2,
                            asleepMinutes: [1])
        let r = NightStages.refine(p, with: natt)
        XCTAssertEqual(r.asleepSeconds, 0)
        XCTAssertEqual(r.awakeSeconds, 0)
        XCTAssertEqual(r.gapSeconds, 3_600)
        XCTAssertEqual(r.gaps, [SleepInterval(start: onset, end: wake)])
        XCTAssertTrue(r.wakeBouts.isEmpty)
        XCTAssertTrue(r.asleepMinutes.isEmpty)
    }
}
