import Foundation
import XCTest
@testable import Fitness

// Alla värden nedan är påhittade (CLAUDE.md §Dataregeln). BESLUT B106, METOD M60, M61, M64.

final class FitnessTests: XCTestCase {
    /// Dag 20 500 är 2026-02-16.
    let idag = 20_500

    func nätter(_ pulser: [Double], sistaDag: Int) -> [RestingNight] {
        pulser.enumerated().map { RestingNight(day: sistaDag - (pulser.count - 1) + $0.offset, pulse: $0.element) }
    }

    func testAktivitetsindexetÄrVikternasProdukt() {
        XCTAssertEqual(TrainingHabits(frequency: .twoToThree, intensity: .sweat, duration: .to60).index, 15)
        XCTAssertEqual(TrainingHabits(frequency: .almostDaily, intensity: .exhaustion, duration: .over60).index, 45)
        XCTAssertEqual(TrainingHabits(frequency: .weekly, intensity: .sweat, duration: .under15).index, 5)
        // Aldrig, eller utan att bli svettig, ger 0 vad de andra svaren än är.
        XCTAssertEqual(TrainingHabits(frequency: .never, intensity: .exhaustion, duration: .over60).index, 0)
        XCTAssertEqual(TrainingHabits(frequency: .almostDaily, intensity: .easy, duration: .over60).index, 0)
    }

    func testMaxpulsenÄrDenEgnaAnnarsÅldersformeln() throws {
        let egen = FitnessProfile(birthYear: 1986, ownMaxPulse: 192)
        XCTAssertEqual(egen.maxPulse(year: 2026), MaxPulse(bpm: 192, source: .own))
        // 211 − 0,64 × 40 = 185,4.
        let ålder = try XCTUnwrap(FitnessProfile(birthYear: 1986).maxPulse(year: 2026))
        XCTAssertEqual(ålder.bpm, 185.4, accuracy: 1e-9)
        XCTAssertEqual(ålder.source, .age)
        XCTAssertNil(FitnessProfile().maxPulse(year: 2026))
    }

    func testÅretFörEnDag() {
        XCTAssertEqual(FitnessRules.year(ofDay: 0), 1970)
        XCTAssertEqual(FitnessRules.year(ofDay: idag), 2026)
    }

    func testVilopulsenÄrMedianenAvDeSenasteNätterna() throws {
        // Sju nätter räcker, och medianen av 50…56 är 53.
        let sju = try XCTUnwrap(PassiveFitness.restingPulse(nätter([50, 56, 51, 55, 52, 54, 53], sistaDag: idag),
                                                            day: idag))
        XCTAssertEqual(sju.pulse, 53)
        XCTAssertEqual(sju.nights, 7)
        // Sex nätter räcker inte.
        XCTAssertNil(PassiveFitness.restingPulse(nätter([50, 51, 52, 53, 54, 55], sistaDag: idag), day: idag))
        // Tjugo nätter i rad: bara de 14 senaste räknas (57…70, median 63,5).
        let tjugo = try XCTUnwrap(PassiveFitness.restingPulse(nätter((51...70).map(Double.init), sistaDag: idag),
                                                              day: idag))
        XCTAssertEqual(tjugo.pulse, 63.5)
        XCTAssertEqual(tjugo.nights, 14)
    }

    func testNätterUtanförFönstretOchUtanPulsRäknasInte() {
        // Sju nätter som slutade för 21 dagar sedan ligger utanför fönstret.
        XCTAssertNil(PassiveFitness.restingPulse(nätter([50, 51, 52, 53, 54, 55, 56], sistaDag: idag - 21), day: idag))
        // Nätter efter dagen räknas inte, och inte en natt med puls 0.
        var blandat = nätter([50, 51, 52, 53, 54, 55], sistaDag: idag)
        blandat.append(RestingNight(day: idag + 1, pulse: 60))
        blandat.append(RestingNight(day: idag - 6, pulse: 0))
        XCTAssertNil(PassiveFitness.restingPulse(blandat, day: idag))
    }

    func testNesFormelFörEnMan() throws {
        // Ålder 40, midja 90, vilopuls 55, index 15:
        // 100,27 − 0,296 × 40 − 0,369 × 90 − 0,155 × 55 + 0,226 × 15 = 50,085.
        let profil = FitnessProfile(birthYear: 1986, sex: .man, waistCm: 90,
                                    habits: TrainingHabits(frequency: .twoToThree, intensity: .sweat, duration: .to60))
        let ut = PassiveFitness.estimate(profile: profil, nights: nätter(Array(repeating: 55, count: 10), sistaDag: idag),
                                         day: idag)
        guard case .estimate(let e) = ut else { return XCTFail("ingen skattning: \(ut)") }
        XCTAssertEqual(e.value, 50.085, accuracy: 1e-9)
        XCTAssertEqual(e.uncertainty, 5.70)
        XCTAssertEqual(e.restingPulse, 55)
        XCTAssertEqual(e.nights, 10)
    }

    func testNesFormelFörEnKvinna() throws {
        // Ålder 35, midja 75, vilopuls 60, index 5:
        // 74,736 − 0,247 × 35 − 0,259 × 75 − 0,114 × 60 + 0,198 × 5 = 40,816.
        let profil = FitnessProfile(birthYear: 1991, sex: .kvinna, waistCm: 75,
                                    habits: TrainingHabits(frequency: .weekly, intensity: .sweat, duration: .under15))
        let ut = PassiveFitness.estimate(profile: profil, nights: nätter(Array(repeating: 60, count: 7), sistaDag: idag),
                                         day: idag)
        guard case .estimate(let e) = ut else { return XCTFail("ingen skattning: \(ut)") }
        XCTAssertEqual(e.value, 40.816, accuracy: 1e-9)
        XCTAssertEqual(e.uncertainty, 5.14)
    }

    func testLägreVilopulsGerHögreTal() throws {
        // 5 slag lägre vilopuls ger +0,775 för en man (METOD M61).
        let profil = FitnessProfile(birthYear: 1986, sex: .man, waistCm: 90,
                                    habits: TrainingHabits(frequency: .twoToThree, intensity: .sweat, duration: .to60))
        func värde(_ puls: Double) -> Double? {
            let ut = PassiveFitness.estimate(profile: profil, nights: nätter(Array(repeating: puls, count: 7), sistaDag: idag),
                                             day: idag)
            if case .estimate(let e) = ut { return e.value }
            return nil
        }
        let låg = try XCTUnwrap(värde(50))
        let hög = try XCTUnwrap(värde(55))
        XCTAssertEqual(låg - hög, 0.775, accuracy: 1e-9)
    }

    func testDetSomSaknasRäknasUpp() {
        // Tom profil och inga nätter: allt saknas, i fältens ordning.
        XCTAssertEqual(PassiveFitness.estimate(profile: FitnessProfile(), nights: [], day: idag),
                       .missing([.birthYear, .sex, .waist, .habits, .nights]))
        // Bara midjemåttet saknas. Längd, vikt och maxpuls behövs inte.
        let profil = FitnessProfile(birthYear: 1986, sex: .man,
                                    habits: TrainingHabits(frequency: .weekly, intensity: .sweat, duration: .to30))
        XCTAssertEqual(PassiveFitness.estimate(profile: profil, nights: nätter(Array(repeating: 55, count: 7), sistaDag: idag),
                                               day: idag),
                       .missing([.waist]))
    }

    func testUthsKvot() throws {
        // 15,3 × 190 / 50 = 58,14.
        XCTAssertEqual(try XCTUnwrap(PassiveFitness.pulseRatio(maxPulse: 190, restingPulse: 50)), 58.14, accuracy: 1e-9)
        XCTAssertNil(PassiveFitness.pulseRatio(maxPulse: 190, restingPulse: 0))
    }

    func testFilenGårRuntOchTålEnTomFil() throws {
        var lager = FitnessStore(profile: FitnessProfile(birthYear: 1986, sex: .man, heightCm: 180, weightKg: 80,
                                                         waistCm: 90, ownMaxPulse: 192,
                                                         habits: TrainingHabits(frequency: .twoToThree, intensity: .sweat,
                                                                                duration: .to60)))
        lager.setWhoopNote(day: idag, value: 48)
        lager.setWhoopNote(day: idag - 7, value: 47)
        // Samma dag igen byter talet, och listan står i dagordning.
        lager.setWhoopNote(day: idag, value: 49)
        XCTAssertEqual(lager.whoopNotes, [WhoopFitnessNote(day: idag - 7, value: 47), WhoopFitnessNote(day: idag, value: 49)])
        let data = try FitnessFile.encode(lager)
        XCTAssertEqual(try FitnessFile.decode(data), lager)
        XCTAssertEqual(try FitnessFile.encode(try FitnessFile.decode(data)), data)
        // En tom fil och en fil utan fält blir ett tomt lager.
        XCTAssertEqual(try FitnessFile.decode(Data("{}".utf8)), FitnessStore())
        XCTAssertEqual(try FitnessFile.decode(Data(#"{"profile":{}}"#.utf8)), FitnessStore())
    }
}
