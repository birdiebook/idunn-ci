import Foundation
import XCTest
@testable import Sound

// METOD M38. Klasstabellen och golvet.

final class SoundClassesTests: XCTestCase {

    func testTolvKlasserIFastOrdning() {
        XCTAssertEqual(SoundClass.allCases.count, 12)
        XCTAssertEqual(SoundClass.allCases.map { $0.rawValue }, Array(0..<12))
        XCTAssertEqual(SoundClass.snoring.rawValue, 0, "snarkning är först: filen bär bara index")
        XCTAssertEqual(SoundClass.other.rawValue, 11)
        XCTAssertEqual(Set(SoundClass.allCases.map { $0.label }).count, 12, "tolv olika namn")
        XCTAssertEqual(SoundClasses.table.count, 12)
        XCTAssertTrue(SoundClasses.table[11].isEmpty, "övrigt har ingen lista")
        for c in SoundClass.allCases where c != .other {
            XCTAssertFalse(SoundClasses.identifiers(of: c).isEmpty, c.label)
        }
    }

    func testIngenIdentifierareHörTillTvåKlasserEllerÄrSilence() {
        let all = SoundClasses.allIdentifiers
        XCTAssertEqual(Set(all).count, all.count, "varje identifierare i en klass")
        XCTAssertFalse(all.contains("silence"))
        XCTAssertEqual(SoundClasses.soundClass(of: "snoring"), .snoring)
        XCTAssertEqual(SoundClasses.soundClass(of: "gasp"), .breathing)
        XCTAssertEqual(SoundClasses.soundClass(of: "car_horn"), .traffic)
        XCTAssertEqual(SoundClasses.soundClass(of: "banjo"), .other)
        XCTAssertNil(SoundClasses.soundClass(of: "silence"))
    }

    func testHögstaSannolikhetenIKlassenGäller() {
        let g = SoundClasses.group(["snoring": 0.93, "breathing": 0.2, "gasp": 0.7, "sigh": 0.1,
                                    "speech": 0.4, "whispering": 0.61])
        XCTAssertEqual(g.count, 12)
        XCTAssertEqual(g[0], 93)
        XCTAssertEqual(g[1], 70, "högsta av andning, flämtning och suck")
        XCTAssertEqual(g[2], 61, "högsta av tal och viskning")
        XCTAssertEqual(g[5], 0)
    }

    func testÖvrigtÄrHögstaAvAllaAndraUtomSilence() {
        let g = SoundClasses.group(["banjo": 0.4, "kazoo": 0.55, "silence": 0.99, "snoring": 0.9])
        XCTAssertEqual(g[11], 55)
        XCTAssertEqual(g[0], 90)
        XCTAssertEqual(SoundClasses.group(["snoring": 0.9])[11], 0, "en listad identifierare är inte övrigt")
        XCTAssertEqual(SoundClasses.group(["silence": 1])[11], 0)
    }

    func testVärdenBegränsasTill0Till100() {
        let g = SoundClasses.group(["speech": 1.5, "cough": -0.2, "dog": Double.nan, "door": 0.004, "rain": 0.996])
        XCTAssertEqual(g[2], 100)
        XCTAssertEqual(g[3], 0)
        XCTAssertEqual(g[8], 0)
        XCTAssertEqual(g[7], 0, "0,4 % avrundas till 0")
        XCTAssertEqual(g[9], 100, "99,6 % avrundas till 100")
        XCTAssertEqual(SoundClasses.group([:]), [UInt8](repeating: 0, count: 12))
    }
}

final class NoiseFloorTests: XCTestCase {

    func testIngetGolvFörstFörrän30Sekunder() {
        var f = NoiseFloor()
        for _ in 0..<29 { f.add(-60) }
        XCTAssertNil(f.value)
        f.add(-60)
        XCTAssertEqual(f.value, -60)
        XCTAssertEqual(f.count, 30)
    }

    func testGolvetÄr10ePercentilen() {
        var f = NoiseFloor()
        for i in 0..<100 { f.add(Double((i * 37) % 100)) }
        // 0…99 i blandad ordning: rang ceil(0,1 · 100) = 10 → det tionde minsta, 9.
        XCTAssertEqual(f.value, 9)
    }

    func testBaraDeSenaste600SekundernaRäknas() {
        var f = NoiseFloor()
        for _ in 0..<600 { f.add(-70) }
        XCTAssertEqual(f.value, -70)
        for _ in 0..<600 { f.add(-40) }
        XCTAssertEqual(f.value, -40, "de tysta sekunderna är glömda")
        XCTAssertEqual(f.count, 600)
    }

    func testSerienÄrGolvetFöreVarjeSekund() {
        let seconds: [SoundSecond] = SoundFixtures.quiet(0, 40)
        let s = NoiseFloor.series(seconds)
        XCTAssertEqual(s.count, 40)
        XCTAssertNil(s[29], "29 sekunder före")
        XCTAssertEqual(s[30], -60)
        XCTAssertEqual(s[39], -60)
    }
}
