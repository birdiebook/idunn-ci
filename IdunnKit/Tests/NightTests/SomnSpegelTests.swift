import Foundation
import XCTest
import WhoopFrames
import DemoData
@testable import Night

// METOD M26 · METOD M31 · BESLUT B73. Paritet mot Python-spegeln tools/somn_regler.py: samma
// påhittade nätter (frö och faser ur SomnSpegelFixtur, som skrivs av
// tools/tests/somn_fixtur.py) ska ge samma insomning, uppvaknande, block,
// antal epoker, vakna stunder, glapp, sömnminuter och märkningen av ofullständiga nätter. Fäller provet har
// spegeln och IdunnKit glidit isär, och talen i M31 gäller inte appen.

final class SomnSpegelTests: XCTestCase {

    func poster(_ n: SomnSpegelFixtur.Natt) -> [K18Record] {
        switch n.kalla {
        case .faser(let phases, let seed):
            return DemoSleep.records(start: n.start, phases: phases, seed: seed)
        case .trolig(let seed):
            return DemoSleep.plausibleNight(start: n.start, seed: seed).records
        }
    }

    /// Fönstret: rakt av, eller kl 12–12 ur uppvakningstiden och zonerna.
    func fonster(_ n: SomnSpegelFixtur.Natt) -> (from: Date, to: Date) {
        guard let z = n.zon else {
            return (Date(timeIntervalSince1970: Double(n.from)), Date(timeIntervalSince1970: Double(n.to)))
        }
        let day = WakeDay(Date(timeIntervalSince1970: Double(z.wakeTime)), utcOffsetSeconds: z.endOffset)
        return SleepDetection.dayWindow(wakeDay: day, startOffsetSeconds: z.startOffset,
                                        endOffsetSeconds: z.endOffset)
    }

    func par(_ i: SleepInterval) -> [Int] { [i.start, i.end] }

    func testAllaNätterGerSammaSomPythonSpegeln() throws {
        XCTAssertFalse(SomnSpegelFixtur.nätter.isEmpty)
        for n in SomnSpegelFixtur.nätter {
            let w = fonster(n)
            XCTAssertEqual(Int(w.from.timeIntervalSince1970), n.from, "\(n.name): fönstrets början")
            XCTAssertEqual(Int(w.to.timeIntervalSince1970), n.to, "\(n.name): fönstrets slut")
            let p = SleepDetection.detect(K18Series(records: poster(n)), from: w.from, to: w.to)
            guard let f = n.facit else {
                XCTAssertNil(p, "\(n.name): ingen period väntas")
                continue
            }
            let period = try XCTUnwrap(p, "\(n.name): en period väntas")
            XCTAssertEqual(period.onset, f.onset, "\(n.name): insomning")
            XCTAssertEqual(period.wake, f.wake, "\(n.name): uppvaknande")
            XCTAssertEqual(period.windowStart, f.windowStart, "\(n.name): blockets början")
            XCTAssertEqual(period.windowEnd, f.windowEnd, "\(n.name): blockets slut")
            XCTAssertEqual(period.asleepSeconds / 5, f.sleepEpochs, "\(n.name): sömnepoker")
            XCTAssertEqual(period.awakeSeconds / 5, f.wakeEpochs, "\(n.name): vakna epoker")
            XCTAssertEqual(period.gapSeconds / 5, f.gapEpochs, "\(n.name): glappepoker")
            XCTAssertEqual(period.threshold, f.threshold, accuracy: 1e-9, "\(n.name): tröskeln")
            XCTAssertEqual(period.wakeBouts.map { self.par($0) }, f.wakeBouts, "\(n.name): vakna stunder")
            XCTAssertEqual(period.gaps.map { self.par($0) }, f.gaps, "\(n.name): glapp")
            let minuter: [Int] = f.minuteRuns.flatMap { (r: [Int]) -> [Int] in Array(r[0]...r[1]) }
            XCTAssertEqual(period.asleepMinutes, minuter, "\(n.name): sömnminuter")
            XCTAssertEqual(period.incompleteStart, f.incompleteStart, "\(n.name): början saknas (B73)")
            XCTAssertEqual(period.incompleteEnd, f.incompleteEnd, "\(n.name): slutet saknas (B73)")
        }
    }

    func testFixturenHarNätterMedOchUtanPeriod() {
        // Provet ovan ska inte kunna bli tomt: både en natt med period och en utan.
        XCTAssertTrue(SomnSpegelFixtur.nätter.contains { $0.facit != nil })
        XCTAssertTrue(SomnSpegelFixtur.nätter.contains { $0.facit == nil })
        XCTAssertTrue(SomnSpegelFixtur.nätter.contains { $0.zon != nil })
        // BESLUT B73: båda märkningarna och en natt utan dem finns med.
        XCTAssertTrue(SomnSpegelFixtur.nätter.contains { $0.facit?.incompleteStart == true })
        XCTAssertTrue(SomnSpegelFixtur.nätter.contains { $0.facit?.incompleteEnd == true })
        XCTAssertTrue(SomnSpegelFixtur.nätter.contains { $0.facit?.incompleteStart == false && $0.facit?.incompleteEnd == false })
    }
}
