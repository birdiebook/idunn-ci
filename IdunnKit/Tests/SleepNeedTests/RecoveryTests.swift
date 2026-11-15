import Foundation
import XCTest
import Night
@testable import SleepNeed

// Alla nätter nedan är påhittade (CLAUDE.md §Dataregeln). BESLUT B72, METOD M57.
// Pariteten: samma fall och samma tal som tools/tests/test_aterhamtning.py (klassen ParitetMedSwift). Ändras ett
// fall där ändras det här.

final class RecoveryTests: XCTestCase {
    // MARK: Baslinjen

    func testBaslinjenKrymperSDMotPriorn() throws {
        let tom = Recovery.baseline([], priorSD: 0.26)
        XCTAssertEqual(tom.n, 0)
        XCTAssertNil(tom.mean)
        XCTAssertNil(tom.sd)
        let en = Recovery.baseline([4.0], priorSD: 0.26)
        XCTAssertEqual(try XCTUnwrap(en.mean), 4.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(en.sd), 0.26, accuracy: 1e-12, "med en natt är SD:n priorns")
        let tre = Recovery.baseline([3.8, 4.0, 4.3], priorSD: 0.26)
        XCTAssertEqual(tre.n, 3)
        XCTAssertEqual(try XCTUnwrap(tre.mean), 4.033333333333333, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(tre.sd), 0.25817019938763625, accuracy: 1e-12)
    }

    // MARK: Poängen och Vad som drog

    func testPoängenOchBidragen() throws {
        let a = try XCTUnwrap(Recovery.score(zHRV: 1.0, zHeartRate: -0.5, sleepShare: 0.9, zBreathing: 2.5))
        XCTAssertEqual(a.score, 76.75, accuracy: 1e-9)
        XCTAssertEqual(a.hrv, 13.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a.heartRate), 2.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a.sleep), -3, accuracy: 1e-9)
        XCTAssertTrue(a.breathingHigh, "andningen över 2 SD")
        XCTAssertEqual(RecoveryRules.middle + a.hrv + (a.heartRate ?? 0) + (a.sleep ?? 0), a.score, accuracy: 1e-9,
                       "bidragen summerar med mitten till poängen")

        // Utan puls bär HRV hela den autonoma delen; utan sömn drar sömnen inget.
        let b = try XCTUnwrap(Recovery.score(zHRV: -2, zHeartRate: nil, sleepShare: nil))
        XCTAssertEqual(b.score, 28, accuracy: 1e-9)
        XCTAssertEqual(b.hrv, -36, accuracy: 1e-9)
        XCTAssertNil(b.heartRate)
        XCTAssertNil(b.sleep)
        XCTAssertFalse(b.breathingHigh)

        // Klippt till 100; sömn över behovet ger inget plus.
        let c = try XCTUnwrap(Recovery.score(zHRV: 3, zHeartRate: -3, sleepShare: 1.2))
        XCTAssertEqual(c.score, 100, accuracy: 1e-9)
        XCTAssertEqual(c.hrv, 40.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(c.heartRate), 13.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(c.sleep), 0, accuracy: 1e-9)

        XCTAssertNil(Recovery.score(zHRV: nil, zHeartRate: 1, sleepShare: 1), "utan HRV ingen poäng (BESLUT B11)")
    }

    // MARK: Natt för natt

    /// Samma nätter som `NATTER` i test_aterhamtning.py: HRV, medelpuls, andning och sovtid / behov.
    static let nätter: [RecoveryNight] = [
        RecoveryNight(day: 20_000, rmssd: 50, heartRate: 55, breathing: 14.0, sleepShare: 0.95),
        RecoveryNight(day: 20_001, rmssd: 60, heartRate: 53, breathing: 14.2, sleepShare: 1.05),
        RecoveryNight(day: 20_002, rmssd: 45, heartRate: 57, breathing: nil, sleepShare: 0.80),
        RecoveryNight(day: 20_003, rmssd: nil, heartRate: 54, breathing: 14.0, sleepShare: 0.9),
        RecoveryNight(day: 20_004, rmssd: 55, heartRate: nil, breathing: 15.5, sleepShare: nil),
        RecoveryNight(day: 20_005, rmssd: 70, heartRate: 52, breathing: 14.1, sleepShare: 0.70),
        RecoveryNight(day: 20_040, rmssd: 50, heartRate: 55, breathing: 14.0, sleepShare: 1.0),
    ]

    func testNattFörNattFrånAndraNatten() throws {
        let d = Recovery.days(Self.nätter)
        // Natt 1 har ingen baslinje, natten utan HRV ingen poäng, och dag 20 040 har inga nätter inom 28 dagar.
        XCTAssertEqual(d.keys.sorted(), [20_001, 20_002, 20_004, 20_005])
        let a = try XCTUnwrap(d[20_001])
        XCTAssertEqual(a.score, 75.34169621814763, accuracy: 1e-9)
        XCTAssertEqual(a.hrv, 9.466696218147634, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a.heartRate), 1.875, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a.sleep), 0, accuracy: 1e-9)
        XCTAssertFalse(a.breathingHigh)
        XCTAssertEqual(a.baselineNights, 1)
        let b = try XCTUnwrap(d[20_002])
        XCTAssertEqual(b.score, 44.28992866604812, accuracy: 1e-9)
        XCTAssertEqual(b.hrv, -10.72185341187382, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.heartRate), -2.988217922078059, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.sleep), -6, accuracy: 1e-9)
        let c = try XCTUnwrap(d[20_004])
        XCTAssertEqual(c.score, 69.23856785510125, accuracy: 1e-9)
        XCTAssertEqual(c.hrv, 5.238567855101253, accuracy: 1e-9)
        XCTAssertNil(c.heartRate)
        XCTAssertNil(c.sleep)
        XCTAssertTrue(c.breathingHigh, "andningen 15,5 mot 14,0 och 14,2")
        let e = try XCTUnwrap(d[20_005])
        XCTAssertEqual(e.score, 75.38433665102326, accuracy: 1e-9)
        XCTAssertEqual(e.hrv, 17.383223083655434, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(e.heartRate), 3.0011135673678275, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(e.sleep), -9, accuracy: 1e-9)
    }

    // MARK: Idunns nätter (bara Swift)

    func testIdunsNätterMedMedelpulsenOchSovtidenMotBehovet() throws {
        let dag = WakeDay(daysSince1970: 20_000)
        func natt(_ i: Int, rmssd: Double, medel: Double, sov: Double) -> Trends.IdunNight {
            Trends.IdunNight(day: dag + i, validWindows: 80, rmssd: rmssd, restingHeartRate: 40,
                             breathsPerMinute: 14, sleepHours: sov / 60, meanHeartRate: medel, source: .k18,
                             onsetMinutes: -60, wakeMinutes: 420)
        }
        let idun = [natt(0, rmssd: 50, medel: 55, sov: 450), natt(1, rmssd: 60, medel: 53, sov: 400)]
        let behov = SleepNeed.days(nights: SleepNeed.nights(idun), passes: [])
        let n = Recovery.nights(idun, need: behov)
        XCTAssertEqual(n.map(\.day), [20_000, 20_001])
        XCTAssertEqual(try XCTUnwrap(n[1].heartRate), 53, accuracy: 1e-12, "medelpulsen, inte lägsta 5 min")
        let b1 = try XCTUnwrap(behov.first { $0.day == 20_001 })
        XCTAssertEqual(try XCTUnwrap(n[1].sleepShare), 400 / b1.needMinutes, accuracy: 1e-12)
        let d = Recovery.days(idun, need: behov)
        XCTAssertNil(d[20_000], "natt 1 utan baslinje")
        XCTAssertEqual(try XCTUnwrap(d[20_001]).score, try XCTUnwrap(Recovery.days(n)[20_001]).score, accuracy: 1e-12)
    }
}
