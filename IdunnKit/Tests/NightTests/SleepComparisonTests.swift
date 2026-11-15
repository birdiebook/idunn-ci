import Foundation
import XCTest
import WhoopFrames
import WhoopImport
import DemoData
@testable import Night

// METOD M26 · METOD M14. Påhittade sömnpass med exportens kolumner
// (som WhoopImportTests/Fixtures.swift) mot påhittade perioder, bara tal.

final class SleepComparisonTests: XCTestCase {
    static let header = "Cycle start time,Cycle end time,Cycle timezone,Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %,Nap"

    /// Ett pass i zonen UTC+01:00 med väggklockstider; `asleep` tom ger ingen sömntid.
    func pass(onset: String, wake: String, asleep: String, nap: Bool = false) -> String {
        "2026-10-25 22:00:00,2026-10-27 22:00:00,UTC+01:00,\(onset),\(wake),80,14.0,\(asleep),,,,,,,,90,,\(nap)"
    }

    func sleeps(_ rows: [String]) throws -> [Sleep] {
        try WhoopExport.parseSleeps(([Self.header] + rows).joined(separator: "\n"))
    }

    /// Perioden med givna Unix-sekunder; sömntiden anges direkt.
    func period(onset: Int, wake: Int, asleepSeconds: Int) -> SleepPeriod {
        SleepPeriod(onset: onset, wake: wake, windowStart: onset, windowEnd: wake,
                    wakeBouts: [], gaps: [], asleepSeconds: asleepSeconds,
                    awakeSeconds: wake - onset - asleepSeconds, gapSeconds: 0,
                    threshold: 0.2, asleepMinutes: [])
    }

    // 2026-10-26 23:00:00 UTC+01:00 = 22:00:00Z
    static let z = 1_793_052_000

    func testAvvikelsenÄrIdunnMinusWhoopIMinuter() throws {
        // Whoop: insomning 23:00, uppvaknande 07:00 (480 min i sängen), 450 min sömn.
        let s = try sleeps([pass(onset: "2026-10-26 23:00:00", wake: "2026-10-27 07:00:00", asleep: "450")])
        // Idunn: 12 min senare in, 5 min tidigare upp, 420 min sömn.
        let p = period(onset: Self.z + 12 * 60, wake: Self.z + 480 * 60 - 5 * 60, asleepSeconds: 420 * 60)
        let d = SleepComparison.deviation(idun: p, whoop: s[0])
        XCTAssertEqual(d.onsetMinutes, 12, accuracy: 1e-9)
        XCTAssertEqual(d.wakeMinutes, -5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.sleepMinutes), -30, accuracy: 1e-9)
    }

    func testEttPassUtanSömntidGerIngenSömnavvikelse() throws {
        let s = try sleeps([pass(onset: "2026-10-26 23:00:00", wake: "2026-10-27 07:00:00", asleep: "")])
        let p = period(onset: Self.z, wake: Self.z + 480 * 60, asleepSeconds: 400 * 60)
        let d = SleepComparison.deviation(idun: p, whoop: s[0])
        XCTAssertNil(d.sleepMinutes)
        XCTAssertEqual(d.onsetMinutes, 0, accuracy: 1e-9)
    }

    func testPassetÄrDetSomÖverlapparMestOchInteEnTupplur() throws {
        let s = try sleeps([
            pass(onset: "2026-10-26 14:00:00", wake: "2026-10-26 14:30:00", asleep: "25", nap: true),
            pass(onset: "2026-10-26 23:00:00", wake: "2026-10-27 07:00:00", asleep: "450"),
            pass(onset: "2026-10-25 23:00:00", wake: "2026-10-26 07:00:00", asleep: "440"),
        ])
        let p = period(onset: Self.z + 10 * 60, wake: Self.z + 470 * 60, asleepSeconds: 440 * 60)
        let valt = try XCTUnwrap(SleepComparison.whoopPass(for: p, in: s))
        XCTAssertEqual(valt.asleepMinutes, 450)
        // En tupplur som överlappar mest räknas ändå inte.
        let bara = try sleeps([pass(onset: "2026-10-26 23:00:00", wake: "2026-10-27 07:00:00", asleep: "450", nap: true)])
        XCTAssertNil(SleepComparison.whoopPass(for: p, in: bara))
        // Inget överlapp: inget par.
        let annan = period(onset: Self.z + 3 * 86_400, wake: Self.z + 3 * 86_400 + 3600, asleepSeconds: 3000)
        XCTAssertNil(SleepComparison.whoopPass(for: annan, in: s))
    }

    func testSammanfattningenGerBaraSamladeTal() throws {
        let s = try sleeps([
            pass(onset: "2026-10-26 23:00:00", wake: "2026-10-27 07:00:00", asleep: "450"),
            pass(onset: "2026-10-27 23:00:00", wake: "2026-10-28 07:00:00", asleep: "460"),
            pass(onset: "2026-10-28 23:00:00", wake: "2026-10-29 07:00:00", asleep: "470"),
        ])
        let dag = 86_400
        // Idunn mot Whoop: insomning +10/−10/+10 min, uppvaknande +4/+4/−8,
        // sömntid −20/−10/+30.
        let idun = [
            period(onset: Self.z + 10 * 60, wake: Self.z + 484 * 60, asleepSeconds: 430 * 60),
            period(onset: Self.z + dag - 10 * 60, wake: Self.z + dag + 484 * 60, asleepSeconds: 450 * 60),
            period(onset: Self.z + 2 * dag + 10 * 60, wake: Self.z + 2 * dag + 472 * 60, asleepSeconds: 500 * 60),
            period(onset: Self.z + 9 * dag, wake: Self.z + 9 * dag + 3600, asleepSeconds: 3000), // utan par
        ]
        let sum = SleepComparison.summary(idun: idun, whoop: s)
        XCTAssertEqual(sum.nights, 3)
        XCTAssertTrue(sum.isEnough)
        XCTAssertEqual(try XCTUnwrap(sum.onset.meanDifference), 10.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(sum.onset.meanAbsoluteDeviation), 10, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(sum.wake.meanDifference), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(sum.wake.meanAbsoluteDeviation), 16.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(sum.sleep.meanDifference), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(sum.sleep.meanAbsoluteDeviation), 20, accuracy: 1e-9)
        // BESLUT B3: texten bär samlade tal, inte nätternas tider.
        XCTAssertTrue(sum.description.contains("3 nätter"), sum.description)
        XCTAssertFalse(sum.description.contains("450"), sum.description)
    }

    func testFärreÄnTreNätterVisasInte() throws {
        let s = try sleeps([pass(onset: "2026-10-26 23:00:00", wake: "2026-10-27 07:00:00", asleep: "450")])
        let sum = SleepComparison.summary(
            idun: [period(onset: Self.z, wake: Self.z + 480 * 60, asleepSeconds: 450 * 60)], whoop: s)
        XCTAssertEqual(sum.nights, 1)
        XCTAssertFalse(sum.isEnough)
        XCTAssertEqual(SleepComparison.summary(idun: [], whoop: s).nights, 0)
        XCTAssertNil(SleepComparison.summary(idun: [], whoop: s).onset.meanDifference)
    }

    func testEnPåhittadNattMotEttPåhittatPass() throws {
        // Hela vägen: gravitationer → period → jämförelse. Natten ligger från
        // 23:00 till 06:30 (UTC+01:00) och Whoop säger 22:55–06:40.
        let m = 60
        let start = Self.z - 30 * m // uppe från 22:30 UTC+01:00
        let recs = DemoSleep.records(
            start: start,
            phases: [.active(seconds: 30 * m), .still(seconds: 450 * m), .active(seconds: 30 * m)],
            seed: 21)
        let found = try XCTUnwrap(SleepDetection.detect(
            K18Series(records: recs),
            from: Date(timeIntervalSince1970: Double(start - 600)),
            to: Date(timeIntervalSince1970: Double(start + 510 * m + 600))))
        let s = try sleeps([pass(onset: "2026-10-26 22:55:00", wake: "2026-10-27 06:40:00", asleep: "440")])
        let d = SleepComparison.deviation(idun: found, whoop: s[0])
        XCTAssertEqual(d.onsetMinutes, 5, accuracy: 3)    // 23:00 mot 22:55
        XCTAssertEqual(d.wakeMinutes, -10, accuracy: 3)   // 06:30 mot 06:40
        XCTAssertEqual(try XCTUnwrap(d.sleepMinutes), 10, accuracy: 3) // 450 mot 440
    }

    func testSparadePerioderGerSammaJämförelseSomPerioderna() throws {
        // S1: appen sparar bara insomning, uppvaknande och sömntid med natten.
        let s = try sleeps([
            pass(onset: "2026-10-26 23:00:00", wake: "2026-10-27 07:00:00", asleep: "450"),
            pass(onset: "2026-10-27 23:00:00", wake: "2026-10-28 07:00:00", asleep: "460"),
            pass(onset: "2026-10-28 23:00:00", wake: "2026-10-29 07:00:00", asleep: "470"),
        ])
        let dag = 86_400
        let perioder = [
            period(onset: Self.z + 10 * 60, wake: Self.z + 484 * 60, asleepSeconds: 430 * 60),
            period(onset: Self.z + dag - 10 * 60, wake: Self.z + dag + 484 * 60, asleepSeconds: 450 * 60),
            period(onset: Self.z + 2 * dag + 10 * 60, wake: Self.z + 2 * dag + 472 * 60, asleepSeconds: 500 * 60),
        ]
        let sparade: [SleepComparison.NightSleep] = perioder.map { (p: SleepPeriod) -> SleepComparison.NightSleep in
            SleepComparison.NightSleep(onset: p.onset, wake: p.wake, asleepMinutes: p.asleepMinutesTotal)
        }
        XCTAssertEqual(SleepComparison.summary(nights: sparade, whoop: s),
                       SleepComparison.summary(idun: perioder, whoop: s))
        XCTAssertEqual(SleepComparison.NightSleep(perioder[0]), sparade[0])
        XCTAssertEqual(SleepComparison.whoopPass(for: sparade[1], in: s)?.asleepMinutes, 460)
    }
}
