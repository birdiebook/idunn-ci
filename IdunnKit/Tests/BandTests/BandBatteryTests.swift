import XCTest
@testable import Band

/// BESLUT B123 · METOD M70. Bandets batteri. Alla nivåer här är påhittade.
final class BandBatteryTests: XCTestCase {

    /// Spelar upp en följd nivåer och ger påminnelserna i ordning (nivå, gräns).
    private func spela(_ nivåer: [Int], från: Int? = nil) -> [(Int, Int)] {
        var tillstånd: Int? = från
        var ut: [(Int, Int)] = []
        for n in nivåer {
            let s: BandBattery.Step = BandBattery.step(state: tillstånd, level: n)
            tillstånd = s.state
            if let g = s.reminder { ut.append((n, g)) }
        }
        return ut
    }

    func testGränserna() {
        XCTAssertEqual(BandBattery.lowLimit, 20)
        XCTAssertEqual(BandBattery.reminderLimits, [20, 10, 5])
        XCTAssertFalse(BandBattery.isLow(20))
        XCTAssertTrue(BandBattery.isLow(19))
    }

    func testIngenPåminnelseÖver20() {
        XCTAssertTrue(spela([100, 60, 30, 21, 20]).isEmpty)
    }

    func testEnVid19OchIngenNyVid18Och15() {
        let ut = spela([21, 19, 18, 15])
        XCTAssertEqual(ut.count, 1)
        XCTAssertEqual(ut[0].0, 19)
        XCTAssertEqual(ut[0].1, 20)
    }

    func testEnVid9OchEnVid4() {
        let ut = spela([19, 15, 11, 9, 8, 6, 4, 3, 0])
        XCTAssertEqual(ut.map { (p: (Int, Int)) -> Int in p.1 }, [20, 10, 5])
        XCTAssertEqual(ut.map { (p: (Int, Int)) -> Int in p.0 }, [19, 9, 4])
    }

    func testHoppetFrån25Till8GerEnPåminnelseFör10() {
        let ut = spela([25, 8])
        XCTAssertEqual(ut.count, 1)
        XCTAssertEqual(ut[0].1, 10)
        // 20 är avklarad: 7 ger inget, 4 ger 5.
        XCTAssertEqual(spela([25, 8, 7, 4]).map { (p: (Int, Int)) -> Int in p.1 }, [10, 5])
    }

    func testLaddningBeväpnarGränsernaIgen() {
        // Påminnelse vid 10, laddning till 15: 10 och 5 kan påminna igen, 20 inte förrän nivån varit 20 eller mer.
        let ut = spela([19, 9, 15, 14, 9, 4])
        XCTAssertEqual(ut.map { (p: (Int, Int)) -> Int in p.1 }, [20, 10, 10, 5])
        // Laddad till 20: alla tre kan påminna i nästa urladdning.
        let full = spela([19, 9, 4, 20, 19, 9, 4])
        XCTAssertEqual(full.map { (p: (Int, Int)) -> Int in p.1 }, [20, 10, 5, 20, 10, 5])
    }

    func testNyUrladdningEfterFullLaddning() {
        let ut = spela([4, 100, 80, 19])
        XCTAssertEqual(ut.map { (p: (Int, Int)) -> Int in p.1 }, [5, 20])
    }

    func testFörstaLäsningenRedanUnderEnGräns() {
        XCTAssertEqual(BandBattery.step(state: nil, level: 17), BandBattery.Step(state: 20, reminder: 20))
        XCTAssertEqual(BandBattery.step(state: nil, level: 7), BandBattery.Step(state: 10, reminder: 10))
        XCTAssertEqual(BandBattery.step(state: nil, level: 3), BandBattery.Step(state: 5, reminder: 5))
        // Och bara en gång.
        XCTAssertEqual(spela([7, 7, 6]).count, 1)
    }

    func testOgiltigaNivåerIgnoreras() {
        XCTAssertEqual(BandBattery.step(state: 10, level: -1), BandBattery.Step(state: 10, reminder: nil))
        XCTAssertEqual(BandBattery.step(state: nil, level: 101), BandBattery.Step(state: nil, reminder: nil))
        XCTAssertEqual(BandBattery.step(state: 20, level: 255), BandBattery.Step(state: 20, reminder: nil))
        // En ogiltig läsning mitt i en urladdning rubbar inget.
        XCTAssertEqual(spela([19, -5, 18, 300, 9]).map { (p: (Int, Int)) -> Int in p.1 }, [20, 10])
    }
}
