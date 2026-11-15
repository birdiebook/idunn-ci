import Foundation
import XCTest
import Night
@testable import Sound

// METOD M46 · BESLUT B56 (J5). Facit för klassningen: rätt eller fel på klassen per klipp, för snarkning
// också på ägaren, sammanräknat per klass. Påhittade klipp, bara tal.

final class SoundFacitTests: XCTestCase {
    let stam = "ljud-2026-10-14T21-03-00Z"

    func klipp(_ s: Int) -> NightSound.Clip { NightSound.Clip(stem: stam, second: s) }

    func testEttOmdömeSparasPerKlippOchTasBortNärBådaOmdömenaÄrBorta() throws {
        var f = SoundFacit()
        XCTAssertTrue(f.entries.isEmpty)
        f.rateClass(klipp(2_400), soundClass: SoundClass.traffic.rawValue, owner: nil, right: true, at: 100)
        XCTAssertEqual(f.entries.count, 1)
        let e = try XCTUnwrap(f.entry(for: klipp(2_400)))
        XCTAssertEqual(e.clip, stam + "/02400")
        XCTAssertEqual(e.soundClass, SoundClass.traffic.rawValue)
        XCTAssertEqual(e.classRight, true)
        XCTAssertNil(e.ownerRight)
        XCTAssertEqual(e.at, 100)
        // Ett nytt omdöme på samma klipp ersätter det förra.
        f.rateClass(klipp(2_400), soundClass: SoundClass.traffic.rawValue, owner: nil, right: false, at: 200)
        XCTAssertEqual(f.entries.count, 1)
        XCTAssertEqual(f.entry(for: klipp(2_400))?.classRight, false)
        XCTAssertEqual(f.entry(for: klipp(2_400))?.at, 200)
        // Tas omdömet bort försvinner klippet ur facit.
        f.rateClass(klipp(2_400), soundClass: SoundClass.traffic.rawValue, owner: nil, right: nil, at: 300)
        XCTAssertTrue(f.entries.isEmpty)
        XCTAssertNil(f.entry(for: klipp(2_400)))
    }

    func testEnSnarkningHarTvåOmdömenSomTasBortEnVarFörSig() throws {
        var f = SoundFacit()
        let c = SoundClass.snoring.rawValue
        f.rateClass(klipp(1_500), soundClass: c, owner: .yours, right: true, at: 1)
        f.rateOwner(klipp(1_500), soundClass: c, owner: .yours, right: false, at: 2)
        XCTAssertEqual(f.entries.count, 1)
        let e = try XCTUnwrap(f.entries.first)
        XCTAssertEqual(e.classRight, true)
        XCTAssertEqual(e.ownerRight, false)
        XCTAssertEqual(e.owner, .yours)
        f.rateClass(klipp(1_500), soundClass: c, owner: .yours, right: nil, at: 3)
        XCTAssertEqual(f.entries.count, 1, "ägaren är kvar")
        f.rateOwner(klipp(1_500), soundClass: c, owner: .yours, right: nil, at: 4)
        XCTAssertTrue(f.entries.isEmpty)
    }

    func testAndelenFelPerKlassOchAntalLyssnade() throws {
        var f = SoundFacit()
        let trafik = SoundClass.traffic.rawValue
        let tal = SoundClass.speech.rawValue
        let snarkning = SoundClass.snoring.rawValue
        // Trafik: 8 lyssnade, 1 fel. Tal: 5 lyssnade, 2 fel. Snarkning: 3 lyssnade, 3 fel (för få för en gräns).
        for k in 0..<8 { f.rateClass(klipp(k), soundClass: trafik, owner: nil, right: k != 3, at: 1) }
        for k in 10..<15 { f.rateClass(klipp(k), soundClass: tal, owner: nil, right: k > 11, at: 1) }
        for k in 20..<23 { f.rateClass(klipp(k), soundClass: snarkning, owner: .unknown, right: false, at: 1) }
        let t = f.classTally()
        XCTAssertEqual(t.map { $0.soundClass }, [snarkning, tal, trafik], "klassernas ordning, bara de lyssnade")
        let trafikT = try XCTUnwrap(t.first { $0.soundClass == trafik })
        XCTAssertEqual(trafikT.heard, 8)
        XCTAssertEqual(trafikT.wrong, 1)
        XCTAssertEqual(try XCTUnwrap(trafikT.wrongShare), 0.125, accuracy: 1e-12)
        XCTAssertFalse(trafikT.overThreshold)
        let talT = try XCTUnwrap(t.first { $0.soundClass == tal })
        XCTAssertEqual(talT.heard, 5)
        XCTAssertEqual(talT.wrong, 2)
        XCTAssertTrue(talT.overThreshold, "40 % fel av fem lyssnade")
        let snarkT = try XCTUnwrap(t.first { $0.soundClass == snarkning })
        XCTAssertEqual(snarkT.wrongShare, 1)
        XCTAssertFalse(snarkT.overThreshold, "tre klipp säger för lite")
        XCTAssertEqual(f.heard, 16)
        XCTAssertEqual(f.wrong, 6)
    }

    func testGränsenÄrÖverEnFemtedelOchKräverFemLyssnade() {
        func tally(_ heard: Int, _ wrong: Int) -> SoundFacit.ClassTally {
            SoundFacit.ClassTally(soundClass: 0, heard: heard, wrong: wrong)
        }
        XCTAssertFalse(tally(10, 2).overThreshold, "exakt en femtedel är inte över")
        XCTAssertTrue(tally(10, 3).overThreshold)
        XCTAssertFalse(tally(4, 4).overThreshold)
        XCTAssertTrue(tally(5, 2).overThreshold, "två av fem är över en femtedel")
        XCTAssertFalse(tally(5, 1).overThreshold)
        XCTAssertNil(tally(0, 0).wrongShare)
        XCTAssertEqual(SoundFacit.reviewShare, 0.2)
        XCTAssertEqual(SoundFacit.minHeard, 5)
    }

    func testÄgarensOmdömenRäknasSkiltFrånKlassens() {
        var f = SoundFacit()
        let c = SoundClass.snoring.rawValue
        f.rateClass(klipp(1), soundClass: c, owner: .yours, right: true, at: 1)
        f.rateOwner(klipp(1), soundClass: c, owner: .yours, right: true, at: 1)
        f.rateOwner(klipp(2), soundClass: c, owner: .someoneElse, right: false, at: 1)
        f.rateOwner(klipp(3), soundClass: c, owner: .yours, right: true, at: 1)
        XCTAssertEqual(f.heard, 1, "bara klipp 1 har ett omdöme om klassen")
        let o = f.ownerTally()
        XCTAssertEqual(o.heard, 3)
        XCTAssertEqual(o.wrong, 1)
        XCTAssertEqual(f.classTally().first?.heard, 1)
    }

    func testFilenÄrEnJSONSomLäsTillbakaOchEnTrasigFilGerEttTomtFacit() throws {
        var f = SoundFacit()
        f.rateClass(klipp(2_400), soundClass: 5, owner: nil, right: true, at: 10)
        f.rateOwner(klipp(1_500), soundClass: 0, owner: .someoneElse, right: false, at: 20)
        XCTAssertEqual(SoundFacit.decode(f.encode()), f)
        XCTAssertEqual(f.encode(), f.encode(), "samma facit ger samma fil")
        XCTAssertEqual(SoundFacit.decode(Data([1, 2, 3])), SoundFacit())
        XCTAssertEqual(SoundFacit.decode(Data()), SoundFacit())
        // Filen bär klippets nyckel och omdömet, inget annat.
        let text = String(decoding: f.encode(), as: UTF8.self)
        XCTAssertTrue(text.contains(stam + "/02400"))
        XCTAssertFalse(text.contains("m4a"))
    }
}
