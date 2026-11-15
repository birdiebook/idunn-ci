import Foundation
import XCTest
@testable import Pass

// BESLUT B120 · METOD M69. Pass som hittas av sig själva. Alla dygn nedan är påhittade (CLAUDE.md §Dataregeln).
// Vilopuls 50 och maxpuls 190: 40 % av pulsreserven är 106 slag, 60 % är 134.

final class PassDetectionTests: XCTestCase {
    typealias Minut = PassDetection.Minute
    let m0 = 30_000_000

    /// `antal` minuter från `från` med samma puls, rörelse och hudtemperatur.
    func minuter(_ från: Int, _ antal: Int, puls: Double?, rörelse: Double? = 0.2, hud: Double? = 33) -> [Minut] {
        (0..<antal).map { (i: Int) -> Minut in
            Minut(minute: m0 + från + i, pulse: puls, movement: rörelse, skinTemperature: hud)
        }
    }

    /// En vardag: 600 minuter i vila (puls 65, stilla) med `pass` inlagda ovanpå (senare minuter gäller).
    func dag(_ pass: [Minut]) -> [Minut] {
        minuter(0, 600, puls: 65, rörelse: 0.005) + pass
    }

    func hitta(_ m: [Minut], uteslutet: [ClosedRange<Int>] = []) -> [PassDetection.Candidate] {
        PassDetection.candidates(m, restingPulse: 50, maxPulse: 190, excluded: uteslutet)
    }

    func testPulsreserven() {
        XCTAssertEqual(PassDetection.reserve(pulse: 120, restingPulse: 50, maxPulse: 190), 0.5)
        XCTAssertEqual(PassDetection.reserve(pulse: 50, restingPulse: 50, maxPulse: 190), 0)
        XCTAssertNil(PassDetection.reserve(pulse: 120, restingPulse: 190, maxPulse: 190))
    }

    func testEnVardagUtanPassGerInget() {
        XCTAssertEqual(hitta(dag([])), [])
        // Under gränsen hela dagen, också i rörelse: 105 slag är 39 % av reserven.
        XCTAssertEqual(hitta(dag(minuter(100, 60, puls: 105))), [])
        XCTAssertEqual(hitta([]), [])
    }

    func testEttKonditionspassHittasMedStartOchSlut() throws {
        // 40 minuter i 150 slag (71 % av reserven) i rörelse.
        let funna = hitta(dag(minuter(200, 40, puls: 150)))
        XCTAssertEqual(funna.count, 1)
        let p = try XCTUnwrap(funna.first)
        XCTAssertEqual(p.startMinute, m0 + 200)
        XCTAssertEqual(p.endMinute, m0 + 239)
        XCTAssertEqual(p.minutes, 40)
        XCTAssertEqual(p.elevatedMinutes, 40)
        XCTAssertEqual(p.kind, .kondition)
        XCTAssertEqual(p.meanReserve, 100.0 / 140, accuracy: 1e-9)
        XCTAssertEqual(p.start, Date(timeIntervalSince1970: Double((m0 + 200) * 60)))
        XCTAssertEqual(p.end, Date(timeIntervalSince1970: Double((m0 + 240) * 60)))
    }

    func testEnKortBitTillBussenÄrIngetPass() {
        // 9 förhöjda minuter räcker inte; 10 gör det.
        XCTAssertEqual(hitta(dag(minuter(200, 9, puls: 120))), [])
        XCTAssertEqual(hitta(dag(minuter(200, 10, puls: 120))).count, 1)
    }

    func testEttMåttligtPassIRörelseHarIngenGissadTyp() throws {
        // 30 minuter i 120 slag (50 %): ett pass, men varken hårt eller bastu.
        let p = try XCTUnwrap(hitta(dag(minuter(200, 30, puls: 120))).first)
        XCTAssertNil(p.kind)
        XCTAssertEqual(p.minutes, 30)
    }

    func testKortaAvbrottHållerIhopPassetOchLångaDelarDet() throws {
        // 15 min, 2 min under gränsen, 15 min: ett pass på 32 minuter med 30 förhöjda.
        let ihop = dag(minuter(200, 15, puls: 150) + minuter(215, 2, puls: 90) + minuter(217, 15, puls: 150))
        let ett = hitta(ihop)
        XCTAssertEqual(ett.count, 1)
        XCTAssertEqual(ett.first?.minutes, 32)
        XCTAssertEqual(ett.first?.elevatedMinutes, 30)
        // 3 minuters avbrott delar det i två.
        let delat = dag(minuter(200, 15, puls: 150) + minuter(215, 3, puls: 90) + minuter(218, 15, puls: 150))
        XCTAssertEqual(hitta(delat).map { $0.minutes }, [15, 15])
    }

    func testFörMångaAvbrottGerIngetPass() {
        // Var tredje minut förhöjd i en timme: 20 förhöjda av 58, under 80 %.
        var bitar: [Minut] = []
        for i in 0..<20 { bitar += minuter(200 + i * 3, 1, puls: 150) }
        XCTAssertEqual(hitta(dag(bitar)), [])
    }

    func testBastuÄrStillaMedVarmHud() throws {
        // 20 minuter i 125 slag, stilla, och huden går från 33 till 37 grader.
        let bastu = minuter(200, 20, puls: 125, rörelse: 0.005, hud: 37)
        let p = try XCTUnwrap(hitta(dag(bastu)).first)
        XCTAssertEqual(p.kind, .bastu)
        XCTAssertEqual(p.minutes, 20)
    }

    func testHögPulsIStillhetUtanVärmeÄrIngetPass() {
        // Samma puls och stillhet, men huden som förut: oro eller kaffe, inget förslag.
        XCTAssertEqual(hitta(dag(minuter(200, 20, puls: 125, rörelse: 0.005, hud: 33))), [])
        // Huden 1,9 grader varmare räcker inte; 2,0 gör det.
        XCTAssertEqual(hitta(dag(minuter(200, 20, puls: 125, rörelse: 0.005, hud: 34.9))), [])
        XCTAssertEqual(hitta(dag(minuter(200, 20, puls: 125, rörelse: 0.005, hud: 35))).first?.kind, .bastu)
    }

    func testUtanRörelseOchUtanTemperaturBlirDetEttPassUtanTyp() throws {
        let p = try XCTUnwrap(hitta(dag(minuter(200, 20, puls: 150, rörelse: nil, hud: nil))).first)
        XCTAssertNil(p.kind)
        // Stilla utan temperatur: värmen går inte att se, alltså inget pass.
        XCTAssertEqual(hitta(dag(minuter(200, 20, puls: 125, rörelse: 0.005, hud: nil))), [])
    }

    func testUteslutnaTiderGerIngaFörslag() {
        let pass = dag(minuter(200, 40, puls: 150))
        // Ett pass som redan finns (startat för hand) täcker tiden.
        XCTAssertEqual(hitta(pass, uteslutet: [(m0 + 190)...(m0 + 250)]), [])
        // Täcker det bara början blir resten ett förslag om den är lång nog.
        XCTAssertEqual(hitta(pass, uteslutet: [(m0 + 190)...(m0 + 219)]).map { $0.startMinute }, [m0 + 220])
        XCTAssertEqual(hitta(pass, uteslutet: [(m0 + 190)...(m0 + 231)]), [])
    }

    func testMinuterUtanPulsOchLuckorIHistoriken() throws {
        // En lucka i historiken på två minuter mitt i passet (inga poster alls) håller ihop det.
        let m = dag(minuter(200, 15, puls: 150)).filter { !(m0 + 207...m0 + 208).contains($0.minute) }
        let p = try XCTUnwrap(hitta(m).first)
        XCTAssertEqual(p.minutes, 15)
        XCTAssertEqual(p.elevatedMinutes, 13)
        // Minuter utan puls räknas inte som förhöjda.
        XCTAssertEqual(hitta(dag(minuter(200, 40, puls: nil))), [])
    }

    func testOrdningenOchDubbletterSpelarIngenRoll() {
        // En dag utan överlapp: vila, pass, vila. (`dag` lägger passet ovanpå vilan för samma minuter, och då
        // avgör ordningen vilken rad som gäller.)
        let m = minuter(0, 200, puls: 65, rörelse: 0.005) + minuter(200, 40, puls: 150)
            + minuter(240, 360, puls: 65, rörelse: 0.005)
        XCTAssertEqual(hitta(m).count, 1)
        XCTAssertEqual(hitta(m.reversed()), hitta(m))
        XCTAssertEqual(hitta(m + m), hitta(m))
        // Två olika rader för samma minut: den som står sist i listan gäller.
        let vila = minuter(200, 40, puls: 65, rörelse: 0.005)
        XCTAssertEqual(hitta(m + vila), [])
        XCTAssertEqual(hitta(vila + m).count, 1)
    }

    func testEgnaTrösklar() {
        var regler = PassDetection.Rules()
        regler.minElevatedMinutes = 20
        let m = dag(minuter(200, 15, puls: 150))
        XCTAssertEqual(PassDetection.candidates(m, restingPulse: 50, maxPulse: 190, rules: regler), [])
        XCTAssertEqual(PassDetection.candidates(m, restingPulse: 50, maxPulse: 190).count, 1)
        // Maxpuls som inte ligger över vilopulsen: ingenting.
        XCTAssertEqual(PassDetection.candidates(m, restingPulse: 190, maxPulse: 190), [])
    }

    func testTvåPassSammaDag() {
        let m = dag(minuter(100, 30, puls: 150) + minuter(400, 20, puls: 125, rörelse: 0.005, hud: 38))
        XCTAssertEqual(hitta(m).map { $0.kind }, [.kondition, .bastu])
    }
}
