import XCTest
@testable import Fitness

// BESLUT B138 · METOD M80. Mätningarna är påhittade (CLAUDE.md §Dataregeln).

final class FitnessTrendTests: XCTestCase {
    func m(_ dag: Int, _ värde: Double) -> FitnessMeasurement {
        FitnessMeasurement(day: dag, value: värde, uncertainty: 4, kind: .stepTest)
    }

    func testPeriodensMätningarIDagordning() {
        let alla = [m(1000, 44), m(600, 40), m(970, 43), m(818, 41), m(1001, 50)]
        XCTAssertEqual(FitnessTrend.within(alla, span: .month, today: 1000).map { $0.day }, [970, 1000])
        XCTAssertEqual(FitnessTrend.within(alla, span: .halfYear, today: 1000).map { $0.day }, [818, 970, 1000])
        XCTAssertEqual(FitnessTrend.within(alla, span: .year, today: 1000).map { $0.day }, [818, 970, 1000])
        XCTAssertEqual(FitnessTrend.within(alla, span: .all, today: 1000).map { $0.day }, [600, 818, 970, 1000])
        XCTAssertEqual(FitnessTrend.within([m(969, 40)], span: .month, today: 1000), [])
        // Samma dag: ordningen de kom i.
        XCTAssertEqual(FitnessTrend.within([m(990, 41), m(990, 45)], span: .month, today: 1000).map { $0.value }, [41, 45])
    }

    func testÄndringenÖverPerioden() {
        let c = FitnessTrend.change([m(800, 41), m(900, 47), m(1000, 43)])
        XCTAssertEqual(c, FitnessTrend.Change(fromDay: 800, delta: 2, isNoticeable: false))
        XCTAssertEqual(FitnessTrend.change([m(800, 41), m(1000, 45)])?.isNoticeable, true)
        XCTAssertEqual(FitnessTrend.change([m(800, 45), m(1000, 40)]), FitnessTrend.Change(fromDay: 800, delta: -5, isNoticeable: true))
        XCTAssertNil(FitnessTrend.change([m(800, 41)]))
        XCTAssertNil(FitnessTrend.change([m(800, 41), m(800, 47)]))
        XCTAssertNil(FitnessTrend.change([]))
    }
}
