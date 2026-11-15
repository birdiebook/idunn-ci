import Foundation
import XCTest
import WhoopImport
@testable import Night

// Påhittade serier och påhittade Whoop-dygn med exportens kolumner
// (som WhoopImportTests/Fixtures.swift). METOD M14.

final class ComparisonTests: XCTestCase {
    func testSpearmanFöljerOrdningenInteFormen() throws {
        let x: [Double] = [1, 2, 3, 4, 5]
        let y: [Double] = [1, 4, 9, 16, 100]
        XCTAssertEqual(try XCTUnwrap(Comparison.spearman(x, y)), 1, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Comparison.spearman(x, y.reversed())), -1, accuracy: 1e-12)
    }

    func testSpearmanMedLikaVärden() throws {
        // Rangerna [1, 2,5, 2,5, 4] och [1, 3, 2, 4]: 4,5 / √(4,5 · 5).
        let rho = try XCTUnwrap(Comparison.spearman([1, 2, 2, 3], [1, 3, 2, 4]))
        XCTAssertEqual(rho, 4.5 / (4.5 * 5.0).squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(Comparison.ranks([10, 30, 20, 20]), [1, 4, 2.5, 2.5])
    }

    func testSpearmanUtanUnderlag() {
        XCTAssertNil(Comparison.spearman([1, 2], [1, 2]), "färre än tre nätter")
        XCTAssertNil(Comparison.spearman([1, 2, 3], [5, 5, 5]), "ingen spridning")
        XCTAssertNil(Comparison.spearman([1, 2, 3], [1, 2]))
    }

    func testMedelavvikelse() throws {
        XCTAssertEqual(try XCTUnwrap(Comparison.meanAbsoluteDeviation([1, 2, 3], [2, 2, 5])), 1, accuracy: 1e-12)
        XCTAssertNil(Comparison.meanAbsoluteDeviation([], []))
        XCTAssertNil(Comparison.meanAbsoluteDeviation([1], [1, 2]))
    }

    func testSammanfattningenParasPåDagen() throws {
        let d = WakeDay(daysSince1970: 20_000)
        let idun: [WakeDay: Double] = [d: 50, d + 1: 60, d + 2: 55, d + 3: 70, d + 5: 99]
        let whoop: [WakeDay: Double] = [d: 45, d + 1: 58, d + 2: 50, d + 3: 66, d + 4: 1]
        let s = Comparison.summary(idun: idun, whoop: whoop)
        XCTAssertEqual(s.nights, 4)
        XCTAssertEqual(try XCTUnwrap(s.spearman), 1, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(s.meanAbsoluteDeviation), 4, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(s.meanDifference), 4, accuracy: 1e-12)
        XCTAssertEqual(Comparison.pairs(idun: idun, whoop: whoop).map(\.day), [d, d + 1, d + 2, d + 3])
        // BESLUT B3: texten bär samlade tal, inte nätternas värden.
        XCTAssertTrue(s.description.contains("4 nätter"), s.description)
        XCTAssertFalse(s.description.contains("70"), s.description)
    }

    // Påhittade dygn, senast först som i exporten. Två dygn vaknar samma dag
    // (2026-10-27): det med längst sömn gäller.
    static let cycles = """
    Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Skin temp (celsius),Blood oxygen %,Day Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %
    2026-10-28 23:00:00,,UTC+01:00,,,,,,,,,,,,,,,,,,,,,,,
    2026-10-27 04:00:00,2026-10-28 23:00:00,UTC+01:00,60,49,70,33.5,96.0,9.0,2300,150,66,2026-10-27 04:00:00,2026-10-27 08:00:00,80,14.0,230,240,120,50,50,10,480,30,90,70
    2026-10-26 23:30:00,2026-10-27 04:00:00,UTC+01:00,40,61,30,33.6,95.5,1.0,500,90,70,2026-10-26 23:30:00,2026-10-27 01:00:00,30,16.0,85,90,50,20,10,5,480,60,90,70
    2026-10-25 22:40:00,2026-10-26 23:30:00,UTC+01:00,71,52,63,33.9,96.4,8.2,2410,151,68,2026-10-25 22:40:00,2026-10-26 06:55:00,88,14.6,452,495,231,102,119,43,510,25,91,80
    2026-10-24 23:10:00,2026-10-25 23:40:00,UTC+02:00,34,58,41,34.2,95.8,12.7,2890,172,74,2026-10-24 23:10:00,2026-10-25 06:20:00,71,15.1,381,430,210,71,100,49,505,60,88,76
    """

    func testWhoopsDygnSomNätterPerUppvakningsdag() throws {
        let cycles = try WhoopExport.parseCycles(Self.cycles)
        let n = WhoopReference.nights(cycles)
        XCTAssertEqual(n.map(\.day.daysSince1970), [20_751, 20_752, 20_753])
        XCTAssertTrue(n.allSatisfy { $0.source == .whoop })
        XCTAssertEqual(try XCTUnwrap(n[0].lnRMSSD), log(41.0), accuracy: 1e-12)
        XCTAssertEqual(n[0].restingHeartRate, 58)
        // 2026-10-27: sömnen 04–08 (fyra timmar) före 23:30–01:00.
        XCTAssertEqual(try XCTUnwrap(n[2].lnRMSSD), log(70.0), accuracy: 1e-12)
        XCTAssertEqual(n[2].restingHeartRate, 49)

        let andning = WhoopReference.byWakeDay(cycles) { $0.respiratoryRate }
        XCTAssertEqual(andning[WakeDay(daysSince1970: 20_752)], 14.6)
        XCTAssertEqual(andning.count, 3)
    }

    func testIdunMotWhoopPåUppvakningsdagen() throws {
        let cycles = try WhoopExport.parseCycles(Self.cycles)
        let whoop = WhoopReference.byWakeDay(cycles) { $0.hrv.map { Double($0) } }
        let idun: [WakeDay: Double] = [
            WakeDay(daysSince1970: 20_751): 45,
            WakeDay(daysSince1970: 20_752): 60,
            WakeDay(daysSince1970: 20_753): 66,
        ]
        let s = Comparison.summary(idun: idun, whoop: whoop)
        XCTAssertEqual(s.nights, 3)
        XCTAssertEqual(try XCTUnwrap(s.spearman), 1, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(s.meanAbsoluteDeviation), (4.0 + 3.0 + 4.0) / 3.0, accuracy: 1e-12)
    }
}
