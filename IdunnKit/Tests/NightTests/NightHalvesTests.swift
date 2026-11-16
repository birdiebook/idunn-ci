import XCTest
import DemoData
import WhoopFrames
@testable import Night

/// BESLUT B131 · METOD M76. Nattens två halvor. Alla skillnader och stadier här är påhittade, och fallen är samma
/// som i `tools/tests/test_hrv_varianter.py` (serierna `kväll` och `morgon`), så att appen och verktyget räknar lika.
final class NightHalvesTests: XCTestCase {

    private let t0: TimeInterval = 1_900_000_000

    /// En skillnad per sekund, omväxlande +d och −d, så att RMSSD är exakt d i varje fönster inom en del.
    private func skillnader(_ delar: [(sekunder: Int, d: Double)]) -> [RRCleaning.Difference] {
        var ut: [RRCleaning.Difference] = []
        var t: TimeInterval = t0
        for del in delar {
            for i in 0..<del.sekunder {
                ut.append(RRCleaning.Difference(time: t, milliseconds: i % 2 == 0 ? del.d : -del.d))
                t += 1
            }
        }
        return ut
    }

    private func natt(_ stadier: [SleepStage?]) -> NightStages.Night {
        var epoker: [NightStages.Epoch] = []
        for (i, s) in stadier.enumerated() {
            epoker.append(NightStages.Epoch(start: Int(t0) + 30 * i, measured: s != nil, wakeProbability: 0,
                                            probabilities: [0.25, 0.25, 0.25, 0.25], stage: s))
        }
        return NightStages.Night(onset: Int(t0), wake: Int(t0) + 30 * stadier.count, epochs: epoker)
    }

    func testFönstrenHarKändRMSSDOchStegetÄr30Sekunder() {
        let f = NightHalves.slidingWindows(skillnader([(3_600, 25)]), first: t0, last: t0 + 3_600)
        XCTAssertEqual(f.count, (3_600 - 300) / 30 + 1)
        XCTAssertEqual(f[1].start - f[0].start, 30)
        for w in f { XCTAssertEqual(w.rmssd, 25, accuracy: 1e-9) }
    }

    func testLågFörstaHalvaOchHögAndra() {
        // Sex timmar: en låg första halva och en hög andra, som en kväll med sen måltid.
        let h = NightHalves.compute(differences: skillnader([(10_800, 30), (10_800, 60)]),
                                    first: t0, last: t0 + 21_600, stages: nil)
        XCTAssertEqual(try XCTUnwrap(h.early), 30, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(h.late), 60, accuracy: 1e-6)
    }

    func testAndelenVakenIEttFönsterSomBörjarMittIEnEpok() {
        // Fönstret börjar 15 s in: 15 s av första epoken (vaken), nio hela (lätt) och 15 s av den elfte (vaken).
        var stadier: [SleepStage?] = [SleepStage?](repeating: .light, count: 11)
        stadier[0] = .wake
        stadier[10] = .wake
        let n = natt(stadier)
        XCTAssertEqual(NightHalves.wakeFraction(start: t0 + 15, stages: n), 30.0 / 300.0, accuracy: 1e-12)
        // En epok som inte är mätt är inte vaken.
        XCTAssertEqual(NightHalves.wakeFraction(start: t0, stages: natt([SleepStage?](repeating: nil, count: 10))), 0)
        XCTAssertEqual(NightHalves.wakeFraction(start: t0, stages: natt([SleepStage?](repeating: .wake, count: 10))), 1)
    }

    func testMestVaknaFönsterRäknasInte() {
        // Hela första halvan vaken: den har inget värde, och den andra räknas som vanligt.
        var stadier: [SleepStage?] = [SleepStage?](repeating: .light, count: 720)
        for i in 0..<360 { stadier[i] = .wake }
        let h = NightHalves.compute(differences: skillnader([(10_800, 30), (10_800, 60)]),
                                    first: t0, last: t0 + 21_600, stages: natt(stadier))
        XCTAssertNil(h.early)
        XCTAssertEqual(try XCTUnwrap(h.late), 60, accuracy: 1e-6)
        // Tio minuter vaken i början ändrar inte medianen i en halva på tre timmar.
        var kort: [SleepStage?] = [SleepStage?](repeating: .deep, count: 720)
        for i in 0..<20 { kort[i] = .wake }
        let g = NightHalves.compute(differences: skillnader([(10_800, 30), (10_800, 60)]),
                                    first: t0, last: t0 + 21_600, stages: natt(kort))
        XCTAssertEqual(try XCTUnwrap(g.early), 30, accuracy: 1e-6)
    }

    func testFörFåFönsterGerIngetVärde() {
        // Tio minuter: elva fönster, färre än tjugo i varje halva.
        let h = NightHalves.compute(differences: skillnader([(600, 30)]), first: t0, last: t0 + 600, stages: nil)
        XCTAssertNil(h.early)
        XCTAssertNil(h.late)
        XCTAssertEqual(NightHalves.compute(differences: [], first: t0, last: t0 + 21_600, stages: nil),
                       NightHalves.Halves(early: nil, late: nil))
    }

    func testMönstretMotNormalområdena() {
        let område: ClosedRange<Double> = 40...60
        XCTAssertEqual(NightHalves.pattern(early: 35, earlyRange: område, late: 50, lateRange: område), .lowEarly)
        XCTAssertEqual(NightHalves.pattern(early: 50, earlyRange: område, late: 39, lateRange: område), .lowLate)
        XCTAssertEqual(NightHalves.pattern(early: 30, earlyRange: område, late: 30, lateRange: område), .lowBoth)
        // På gränsen och över området är inte lågt.
        XCTAssertNil(NightHalves.pattern(early: 40, earlyRange: område, late: 70, lateRange: område))
        // Utan värde eller område sägs ingenting.
        XCTAssertNil(NightHalves.pattern(early: nil, earlyRange: område, late: 30, lateRange: område))
        XCTAssertNil(NightHalves.pattern(early: 30, earlyRange: nil, late: 30, lateRange: område))
    }

    func testSammanfattningenBärHalvornaUrNatten() throws {
        // En påhittad natt ur K18, räknad som appen räknar den.
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: true)
        let z: Int = n.utcOffsetSeconds
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: z)
        let r = try XCTUnwrap(K18Night.analyze(K18Series(notifications: DemoK18Frames.notifications(n.records)),
                                               wakeDay: dag, startOffsetSeconds: z, endOffsetSeconds: z))
        let h = NightHalves.compute(r)
        let d = NightDigest(r)
        XCTAssertEqual(d.rmssdEarly, h.early)
        XCTAssertEqual(d.rmssdLate, h.late)
        XCTAssertNotNil(h.early, "en hel natt har en första halva")
        XCTAssertNotNil(h.late, "en hel natt har en andra halva")
    }
}
