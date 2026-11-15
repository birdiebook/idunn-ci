import Foundation
import XCTest
import Pass
@testable import Fitness

// Alla pass och spår nedan är påhittade (CLAUDE.md §Dataregeln). BESLUT B106, METOD M62, M63, M64.

final class ActiveFitnessTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// Meter per grad latitud med `PassRoute.earthRadius`.
    let meterPerGrad = PassRoute.earthRadius * Double.pi / 180

    // MARK: Steptestet

    /// Ett steptest med ett prov per sekund: pulsen 100, 114, 128, 142, 156 på nivåerna, stopp efter `sekunder`.
    func steptest(sekunder: Int, stopp: Bool = true, höjd: Double = 30) -> Pass {
        let pulser = [100, 114, 128, 142, 156]
        let prov = (0..<sekunder).map { (s: Int) -> PassSample in
            PassSample(t: t0.addingTimeInterval(Double(s)), bpm: pulser[min(s / 120, 4)])
        }
        return Pass(start: t0, stop: stopp ? t0.addingTimeInterval(Double(sekunder)) : nil, kind: .kondition,
                    samples: prov, stepHeightCm: höjd)
    }

    func testStegformelnOchMetronomen() {
        // 0,2 × 15 + 1,33 × 1,8 × 0,30 × 15 + 3,5 = 17,273.
        XCTAssertEqual(StepTest.oxygenCost(cadence: 15, heightCm: 30), 17.273, accuracy: 1e-9)
        // Källans kontroll: 20 cm ger 0,6788 per steg/min.
        XCTAssertEqual(StepTest.oxygenCost(cadence: 10, heightCm: 20), 10.288, accuracy: 1e-9)
        XCTAssertEqual(StepTest.metronome(level: 0), 60)
        XCTAssertEqual(StepTest.metronome(level: 4), 140)
        XCTAssertNil(StepTest.metronome(level: 5))
        XCTAssertEqual(StepTest.level(at: 0), 0)
        XCTAssertEqual(StepTest.level(at: 119.9), 0)
        XCTAssertEqual(StepTest.level(at: 120), 1)
        XCTAssertEqual(StepTest.level(at: 599), 4)
        XCTAssertNil(StepTest.level(at: 600))
        XCTAssertNil(StepTest.level(at: -1))
        XCTAssertEqual(StepTest.totalSeconds, 600)
    }

    func testNivåernasPulsÄrDeSista30Sekunderna() {
        // Tre klara nivåer; den fjärde hann inte bli klar.
        let nivåer = StepTest.levels(steptest(sekunder: 400))
        XCTAssertEqual(nivåer.map(\.index), [0, 1, 2])
        XCTAssertEqual(nivåer.map(\.pulse), [100, 114, 128])
        XCTAssertEqual(nivåer[2].oxygen, StepTest.oxygenCost(cadence: 25, heightCm: 30), accuracy: 1e-9)
        // Utan steghöjd är passet inget steptest.
        XCTAssertEqual(StepTest.levels(Pass(start: t0, stop: t0.addingTimeInterval(400))), [])
    }

    func testEnNivåMedFörFåProvHarIngenPuls() {
        var p = steptest(sekunder: 360)
        // Ta bort nästan alla prov i den andra nivåns sista 30 sekunder.
        p.samples.removeAll { $0.t >= t0.addingTimeInterval(210) && $0.t < t0.addingTimeInterval(238) }
        let nivåer = StepTest.levels(p)
        XCTAssertEqual(nivåer.count, 3)
        XCTAssertNil(nivåer[1].pulse)
        // Två nivåer med puls räcker inte för en skattning.
        XCTAssertNil(StepTest.estimate(p, maxPulse: 180))
    }

    func testSkattningenÄrLinjenDragenTillMaxpulsen() throws {
        // Pulsen stiger 14 slag per nivå och belastningen 4,591: vid maxpuls 180 blir det
        // 17,273 + 80 × 4,591 / 14 = 43,5072857.
        let r = try XCTUnwrap(StepTest.estimate(steptest(sekunder: 360), maxPulse: 180))
        XCTAssertEqual(r.value, 43.5072857, accuracy: 1e-6)
        XCTAssertEqual(r.uncertainty, 3.9)
        XCTAssertEqual(r.levels.count, 3)
        // Fem nivåer på samma linje ger samma tal.
        let fem = try XCTUnwrap(StepTest.estimate(steptest(sekunder: 600), maxPulse: 180))
        XCTAssertEqual(fem.value, 43.5072857, accuracy: 1e-6)
        XCTAssertEqual(fem.levels.count, 5)
        // En linje som inte stiger ger inget tal.
        let platt = [0, 1, 2].map { StepTest.Level(index: $0, cadence: 15, oxygen: 17 + Double($0), pulse: 120) }
        XCTAssertNil(StepTest.estimate(levels: platt, maxPulse: 180))
    }

    func testStoppetFöljerPulsenOchTiden() {
        // Maxpuls 160: 80 % är 128, som den tredje nivån når. Före den: fortsätt.
        let p = steptest(sekunder: 600, stopp: false)
        var tidig = p
        tidig.samples = p.samples.filter { $0.t < t0.addingTimeInterval(300) }
        XCTAssertNil(StepTest.stopReason(tidig, now: t0.addingTimeInterval(300), maxPulse: 160))
        var tredje = p
        tredje.samples = p.samples.filter { $0.t < t0.addingTimeInterval(360) }
        XCTAssertEqual(StepTest.stopReason(tredje, now: t0.addingTimeInterval(360), maxPulse: 160), .reachedLimit)
        // Maxpuls 140: 90 % är 126, och pulsen 128 mitt i den tredje nivån stoppar direkt.
        var mitt = p
        mitt.samples = p.samples.filter { $0.t < t0.addingTimeInterval(250) }
        XCTAssertEqual(StepTest.stopReason(mitt, now: t0.addingTimeInterval(250), maxPulse: 140), .tooHigh)
        // Alla nivåer klara.
        XCTAssertEqual(StepTest.stopReason(p, now: t0.addingTimeInterval(600), maxPulse: 250), .completed)
        // Ett stoppat pass och ett pass som inte är ett steptest frågar inte.
        XCTAssertNil(StepTest.stopReason(steptest(sekunder: 600), now: t0.addingTimeInterval(600), maxPulse: 160))
        XCTAssertNil(StepTest.stopReason(Pass(start: t0), now: t0.addingTimeInterval(600), maxPulse: 160))
    }

    // MARK: Puls mot fart

    /// Ett pass ute: rakt norrut med farten `fart(s)` i m/min, pulsen `puls`, höjden `höjd(s)`, ett värde per sekund.
    func ute(sekunder: Int = 600, puls: Int, typ: PassKind?, höjd: (Int) -> Double = { _ in 20 },
             fart: (Int) -> Double) -> Pass {
        var lat = 59.0
        var spår: [TrackPoint] = []
        var prov: [PassSample] = []
        for s in 0...sekunder {
            if s > 0 { lat += fart(s) / 60 / meterPerGrad }
            let t = t0.addingTimeInterval(Double(s))
            spår.append(TrackPoint(t: t, lat: lat, lon: 18.0, speed: fart(s) / 60, altitude: höjd(s), accuracy: 5))
            prov.append(PassSample(t: t, bpm: puls))
        }
        return Pass(start: t0, stop: t0.addingTimeInterval(Double(sekunder)), kind: typ, samples: prov, track: spår)
    }

    func testLöpningPåPlanMarkGerEttTal() throws {
        // 160 m/min: 0,2 × 160 + 3,5 = 35,5. Puls 150, max 190, vila 50: andelen 100/140.
        // 3,5 + 32 / (100/140) = 48,3.
        let p = ute(puls: 150, typ: .kondition) { _ in 160 }
        let bitar = SpeedFitness.segments(p, maxPulse: 190, restingPulse: 50)
        XCTAssertEqual(bitar.count, 3)
        XCTAssertEqual(bitar[0].speed, 160, accuracy: 0.01)
        XCTAssertTrue(bitar[0].running)
        XCTAssertEqual(bitar[0].oxygen, 35.5, accuracy: 0.01)
        let r = try XCTUnwrap(SpeedFitness.estimate(p, maxPulse: 190, restingPulse: 50))
        XCTAssertEqual(r.value, 48.3, accuracy: 0.01)
        XCTAssertEqual(r.uncertainty, 5.0)
    }

    func testGångRäknasMedGångformeln() throws {
        // 90 m/min: 0,1 × 90 + 3,5 = 12,5. Puls 120, max 190, vila 50: andelen 0,5. 3,5 + 9 / 0,5 = 21,5.
        let p = ute(puls: 120, typ: .promenad) { _ in 90 }
        let r = try XCTUnwrap(SpeedFitness.estimate(p, maxPulse: 190, restingPulse: 50))
        XCTAssertEqual(r.value, 21.5, accuracy: 0.01)
        XCTAssertFalse(r.segments[0].running)
    }

    func testFartenMellanGångOchLöpningRäknasBaraIEttKonditionspass() throws {
        // 120 m/min ligger mellan formlernas områden.
        XCTAssertNil(SpeedFitness.estimate(ute(puls: 130, typ: .promenad) { _ in 120 }, maxPulse: 190, restingPulse: 50))
        XCTAssertNil(SpeedFitness.estimate(ute(puls: 130, typ: nil) { _ in 120 }, maxPulse: 190, restingPulse: 50))
        let jogg = try XCTUnwrap(SpeedFitness.estimate(ute(puls: 130, typ: .kondition) { _ in 120 },
                                                       maxPulse: 190, restingPulse: 50))
        XCTAssertEqual(jogg.segments[0].oxygen, 27.5, accuracy: 0.01)
    }

    func testBitarSomInteHållerKravenRäknasInte() {
        // Pulsen under 110, och över 85 % av maxpulsen.
        XCTAssertNil(SpeedFitness.estimate(ute(puls: 100, typ: .kondition) { _ in 160 }, maxPulse: 190, restingPulse: 50))
        XCTAssertNil(SpeedFitness.estimate(ute(puls: 170, typ: .kondition) { _ in 160 }, maxPulse: 190, restingPulse: 50))
        // Ojämn fart: 30 sekunder i 120 och 30 i 200 m/min.
        let ojämn = ute(puls: 150, typ: .kondition) { (s: Int) -> Double in ((s - 1) / 30) % 2 == 0 ? 120 : 200 }
        XCTAssertNil(SpeedFitness.estimate(ojämn, maxPulse: 190, restingPulse: 50))
        // Uppför: 0,1 m per sekund vid 2,67 m/s är 3,75 %.
        let backe = ute(puls: 150, typ: .kondition, höjd: { (s: Int) -> Double in 20 + 0.1 * Double(s) }) { _ in 160 }
        XCTAssertNil(SpeedFitness.estimate(backe, maxPulse: 190, restingPulse: 50))
        // Ett pass inomhus har inget spår.
        XCTAssertNil(SpeedFitness.estimate(Pass(start: t0, stop: t0.addingTimeInterval(600)), maxPulse: 190,
                                           restingPulse: 50))
        // Ett pass kortare än en bit.
        XCTAssertNil(SpeedFitness.estimate(ute(sekunder: 170, puls: 150, typ: .kondition) { _ in 160 }, maxPulse: 190,
                                           restingPulse: 50))
    }

    func testVilopulsenÖverPulsenGerInget() {
        XCTAssertNil(SpeedFitness.value(oxygen: 35.5, pulse: 150, maxPulse: 190, restingPulse: 150))
        XCTAssertNil(SpeedFitness.value(oxygen: 35.5, pulse: 150, maxPulse: 140, restingPulse: 150))
    }

    // MARK: Ett tal

    func testTaletÄrMedianenAvDeAktivaMätningarnaI42Dagar() throws {
        let idag = 20_500
        let mätningar = [
            FitnessMeasurement(day: idag, value: 44, uncertainty: 3.9, kind: .stepTest),
            FitnessMeasurement(day: idag - 10, value: 48, uncertainty: 5.0, kind: .speed),
            FitnessMeasurement(day: idag - 41, value: 50, uncertainty: 5.0, kind: .speed),
            // Utanför fönstret, och efter dagen: räknas inte.
            FitnessMeasurement(day: idag - 42, value: 90, uncertainty: 5.0, kind: .speed),
            FitnessMeasurement(day: idag + 1, value: 90, uncertainty: 5.0, kind: .speed),
        ]
        let passiv = FitnessEstimate(value: 52, uncertainty: 5.7, restingPulse: 55, nights: 12)
        let ut = try XCTUnwrap(FitnessSummary.shown(passive: passiv, measurements: mätningar, day: idag))
        XCTAssertEqual(ut.value, 48)
        XCTAssertEqual(ut.uncertainty, (3.9 + 5.0 + 5.0) / 3, accuracy: 1e-9)
        XCTAssertEqual(ut.basis, .measurements(stepTests: 1, passes: 2, latestDay: idag))
    }

    func testUtanAktivMätningVisasDenPassiva() throws {
        let passiv = FitnessEstimate(value: 52, uncertainty: 5.7, restingPulse: 55, nights: 12)
        let gammal = [FitnessMeasurement(day: 20_000, value: 44, uncertainty: 3.9, kind: .stepTest)]
        let ut = try XCTUnwrap(FitnessSummary.shown(passive: passiv, measurements: gammal, day: 20_500))
        XCTAssertEqual(ut, FitnessSummary.Shown(value: 52, uncertainty: 5.7, basis: .passive(nights: 12)))
        XCTAssertNil(FitnessSummary.shown(passive: nil, measurements: gammal, day: 20_500))
    }

    func testMätningenUrEttPass() throws {
        let steg = try XCTUnwrap(FitnessSummary.measurement(steptest(sekunder: 360), day: 20_500, maxPulse: 180,
                                                            restingPulse: nil))
        XCTAssertEqual(steg.kind, .stepTest)
        XCTAssertEqual(steg.value, 43.5072857, accuracy: 1e-6)
        let löp = ute(puls: 150, typ: .kondition) { _ in 160 }
        let fart = try XCTUnwrap(FitnessSummary.measurement(löp, day: 20_500, maxPulse: 190, restingPulse: 50))
        XCTAssertEqual(fart.kind, .speed)
        XCTAssertEqual(fart.value, 48.3, accuracy: 0.01)
        // Ett pass ute utan känd vilopuls, och ett vanligt pass, ger ingen mätning.
        XCTAssertNil(FitnessSummary.measurement(löp, day: 20_500, maxPulse: 190, restingPulse: nil))
        XCTAssertNil(FitnessSummary.measurement(Pass(start: t0), day: 20_500, maxPulse: 190, restingPulse: 50))
    }

    func testReferensenFörKönOchÅlder() throws {
        XCTAssertEqual(try XCTUnwrap(FitnessReference.band(sex: .man, age: 44)).mean, 47.2)
        XCTAssertEqual(try XCTUnwrap(FitnessReference.band(sex: .kvinna, age: 25)).mean, 43.0)
        XCTAssertEqual(try XCTUnwrap(FitnessReference.band(sex: .kvinna, age: 59)).sd, 5.7)
        XCTAssertNil(FitnessReference.band(sex: .man, age: 60))
        XCTAssertNil(FitnessReference.band(sex: .man, age: 19))
    }

    func testSteghöjdenSparasILagret() throws {
        let lager = FitnessStore(stepHeightCm: 28.5)
        XCTAssertEqual(try FitnessFile.decode(try FitnessFile.encode(lager)), lager)
        XCTAssertNil(try FitnessFile.decode(Data("{}".utf8)).stepHeightCm)
    }
}
