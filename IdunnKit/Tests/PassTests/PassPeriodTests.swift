import Foundation
import XCTest
@testable import Pass

// BESLUT B134 · METOD M78. Träningen över tid. Passen är påhittade (CLAUDE.md §Dataregeln).

final class PassPeriodTests: XCTestCase {
    /// Tisdagen 2026-11-17 är dag 20774; måndagen samma vecka 20773.
    let idag = 20774

    func pass(_ dag: Int, minuter: Int, typ: PassKind? = .kondition, puls: Int = 150) -> Pass {
        let start = Date(timeIntervalSince1970: Double(dag) * 86_400 + 43_200)
        let prov = (0...(minuter * 60)).map { (s: Int) -> PassSample in
            PassSample(t: start.addingTimeInterval(Double(s)), bpm: puls)
        }
        return Pass(start: start, stop: start.addingTimeInterval(Double(minuter * 60)), kind: typ, samples: prov)
    }

    func dag(_ p: Pass) -> Int { Int(p.start.timeIntervalSince1970) / 86_400 }
    func last(_ p: Pass) -> Double { p.duration / 60 }
    func zon(_ bpm: Int) -> Int { max(0, (bpm - 100) / 10) }

    func testDatumFramOchTillbaka() {
        XCTAssertEqual(PassPeriod.day(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(PassPeriod.day(year: 2026, month: 11, day: 17), idag)
        XCTAssertEqual(PassPeriod.day(year: 2027, month: 1, day: 1), 20819)
        XCTAssertEqual(PassPeriod.day(year: 1969, month: 12, day: 31), -1)
        let c = PassPeriod.civil(day: idag)
        XCTAssertEqual([c.year, c.month, c.day], [2026, 11, 17])
        let skott = PassPeriod.civil(day: PassPeriod.day(year: 2028, month: 2, day: 29))
        XCTAssertEqual([skott.year, skott.month, skott.day], [2028, 2, 29])
        let före = PassPeriod.civil(day: -1)
        XCTAssertEqual([före.year, före.month, före.day], [1969, 12, 31])
        // Varje dag i tio år går fram och tillbaka.
        for d in stride(from: 19_000, to: 22_700, by: 1) {
            let x = PassPeriod.civil(day: d)
            XCTAssertEqual(PassPeriod.day(year: x.year, month: x.month, day: x.day), d)
        }
    }

    func testMånadensFörstaDag() {
        XCTAssertEqual(PassPeriod.monthStart(day: idag), PassPeriod.day(year: 2026, month: 11, day: 1))
        XCTAssertEqual(PassPeriod.monthStart(day: idag, offset: -1), PassPeriod.day(year: 2026, month: 10, day: 1))
        XCTAssertEqual(PassPeriod.monthStart(day: idag, offset: 2), PassPeriod.day(year: 2027, month: 1, day: 1))
        XCTAssertEqual(PassPeriod.monthStart(day: idag, offset: -11), PassPeriod.day(year: 2025, month: 12, day: 1))
        XCTAssertEqual(PassPeriod.monthStart(day: idag, offset: -23), PassPeriod.day(year: 2024, month: 12, day: 1))
    }

    func testVeckansNummer() {
        XCTAssertEqual(PassPeriod.isoWeek(day: idag), 47)
        XCTAssertEqual(PassPeriod.isoWeek(day: idag - 2), 46)                                  // söndagen före
        XCTAssertEqual(PassPeriod.isoWeek(day: PassPeriod.day(year: 2026, month: 12, day: 31)), 53)
        XCTAssertEqual(PassPeriod.isoWeek(day: PassPeriod.day(year: 2027, month: 1, day: 1)), 53)   // fredag: hör till 2026
        XCTAssertEqual(PassPeriod.isoWeek(day: PassPeriod.day(year: 2027, month: 1, day: 4)), 1)
        XCTAssertEqual(PassPeriod.isoWeek(day: PassPeriod.day(year: 2024, month: 12, day: 30)), 1)  // måndag: hör till 2025
    }

    func testStaplarnasDagar() {
        let måndag = idag - 1
        XCTAssertEqual(PassPeriod.week.ranges(day: idag).map { $0.start }, Array(måndag...(måndag + 6)))
        XCTAssertEqual(PassPeriod.week.ranges(day: idag).map { $0.days }, [1, 1, 1, 1, 1, 1, 1])
        XCTAssertEqual(PassPeriod.month.ranges(day: idag).map { $0.start }, [måndag - 21, måndag - 14, måndag - 7, måndag])
        XCTAssertEqual(PassPeriod.month.ranges(day: idag).map { $0.days }, [7, 7, 7, 7])
        let halvår = PassPeriod.halfYear.ranges(day: idag)
        XCTAssertEqual(halvår.count, 6)
        XCTAssertEqual(halvår.first?.start, PassPeriod.day(year: 2026, month: 6, day: 1))
        XCTAssertEqual(halvår.map { $0.days }, [30, 31, 31, 30, 31, 30])                       // juni till november
        let år = PassPeriod.year.ranges(day: idag)
        XCTAssertEqual(år.count, 12)
        XCTAssertEqual(år.first?.start, PassPeriod.day(year: 2025, month: 12, day: 1))
        XCTAssertEqual(år.last?.start, PassPeriod.day(year: 2026, month: 11, day: 1))
        XCTAssertEqual(år.map { $0.days }.reduce(0, +), 365)
    }

    func testFyraVeckorSummeras() {
        let måndag = idag - 1
        let alla = [pass(måndag, minuter: 40), pass(måndag - 7 + 3, minuter: 60, puls: 130),
                    pass(måndag - 21, minuter: 20), pass(måndag - 22, minuter: 500),           // före perioden
                    pass(måndag, minuter: 30, typ: .bastu)]                                    // räknas inte
        let ö = PassPeriod.month.overview(alla, day: idag, dayOf: dag, load: last, classify: zon)
        XCTAssertEqual(ö.period, .month)
        XCTAssertEqual(ö.buckets.map { $0.summary.passes }, [1, 0, 1, 1])
        XCTAssertEqual(ö.passes, 3)
        XCTAssertEqual(ö.seconds, 120 * 60)
        XCTAssertEqual(ö.load, 120)
        XCTAssertEqual(ö.days, 28)
        XCTAssertEqual(ö.averageSeconds, 30 * 60)                                              // tomma veckan räknas
        XCTAssertEqual(ö.secondsPerWeek, 30 * 60)
        XCTAssertEqual(ö.zones, [PassZones.Share(zone: 3, seconds: 3600), PassZones.Share(zone: 5, seconds: 3600)])
    }

    func testVeckanPerDagOchÅretPerMånad() {
        let måndag = idag - 1
        let alla = [pass(måndag, minuter: 40), pass(måndag + 1, minuter: 20), pass(måndag + 1, minuter: 10),
                    pass(PassPeriod.day(year: 2026, month: 3, day: 10), minuter: 90),
                    pass(PassPeriod.day(year: 2025, month: 11, day: 30), minuter: 500)]        // före året
        let vecka = PassPeriod.week.overview(alla, day: idag, dayOf: dag, load: last, classify: nil)
        XCTAssertEqual(vecka.buckets.map { $0.summary.passes }, [1, 2, 0, 0, 0, 0, 0])
        XCTAssertEqual(vecka.seconds, 70 * 60)
        XCTAssertEqual(vecka.zones, [])
        let år = PassPeriod.year.overview(alla, day: idag, dayOf: dag, load: last, classify: nil)
        XCTAssertEqual(år.passes, 4)
        XCTAssertEqual(år.buckets[3].summary.passes, 1)                                        // mars är den fjärde stapeln
        XCTAssertEqual(år.buckets[11].summary.passes, 3)
        XCTAssertEqual(år.secondsPerWeek, år.seconds / (365.0 / 7), accuracy: 1e-9)
        let tom = PassPeriod.halfYear.overview([], day: idag, dayOf: dag, load: last, classify: zon)
        XCTAssertEqual(tom.passes, 0)
        XCTAssertEqual(tom.averageSeconds, 0)
        XCTAssertEqual(tom.buckets.count, 6)
    }
}
