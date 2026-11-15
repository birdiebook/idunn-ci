import Foundation
import XCTest
import DemoData
@testable import Sound

// METOD M38. Mätaren på syntetiska signaler: en sinus, vitt brus (seedat) och
// ett steg mitt i sekunden. Inget kommer från en riktig mikrofon.

final class SoundMeterTests: XCTestCase {

    func sine(_ hz: Double, amplitude: Double) -> [Float] {
        var out = [Float](repeating: 0, count: 16_000)
        for n in 0..<16_000 {
            out[n] = Float(amplitude * sin(2 * Double.pi * hz * Double(n) / 16_000))
        }
        return out
    }

    func noise(_ seed: UInt64, sigma: Double) -> [Float] {
        var r = Seeded(seed)
        var out = [Float](repeating: 0, count: 16_000)
        for n in 0..<16_000 { out[n] = Float(sigma * r.gauss()) }
        return out
    }

    /// Mätaren som hört 30 sekunder tyst brus (−80 dBFS), så att golvet finns.
    func warmMeter() -> SoundMeter {
        var m = SoundMeter()
        for i in 0..<30 { _ = m.measure(noise(UInt64(100 + i), sigma: 0.0001), second: i) }
        return m
    }

    func power(_ db: Double) -> Double { pow(10, db / 10) }

    // MARK: Nivå och band

    func testSinusPåEnKilohertzGerMinus23DecibelOchEffektenIEttBand() throws {
        var m = SoundMeter()
        let sMaybe = m.measure(sine(1_000, amplitude: 0.1))
        let s = try XCTUnwrap(sMaybe)
        XCTAssertEqual(s.levelDB, -23.0, accuracy: 0.2, "0,1 i amplitud är −23,0 dBFS")
        let p: [Double] = s.bandsDB.map { (b: Double) -> Double in power(b) }
        let total: Double = p.reduce(0, +)
        XCTAssertGreaterThanOrEqual(p[4] / total, 0.95, "minst 95 % av effekten i 1 kHz-bandet")
        XCTAssertEqual(s.levelADB, s.levelDB, accuracy: 0.3, "A-vikten vid 1 kHz är 0 dB")
        XCTAssertEqual(s.second, 0)
        XCTAssertEqual(s.onset, SoundSecond.noOnset, "ett jämnt ljud har inget steg")
        XCTAssertEqual(s.classes, [UInt8](repeating: 0, count: 12), "klasserna sätts av den som äger sekunden")
    }

    func testSinusPå250HertzHamnarIRättBandOchAVägsNerMed8Komma6() throws {
        var m = SoundMeter()
        let sMaybe = m.measure(sine(250, amplitude: 0.1))
        let s = try XCTUnwrap(sMaybe)
        let p: [Double] = s.bandsDB.map { (b: Double) -> Double in power(b) }
        XCTAssertGreaterThanOrEqual(p[2] / p.reduce(0, +), 0.95)
        XCTAssertEqual(s.levelADB, s.levelDB - 8.6, accuracy: 0.4)
    }

    func testVittBrusGerBandSomTillsammansÄrLevelPlusMinusEnDecibel() throws {
        for seed in [1, 2, 3] as [UInt64] {
            var m = SoundMeter()
            let sMaybe = m.measure(noise(seed, sigma: 0.05))
            let s = try XCTUnwrap(sMaybe)
            XCTAssertEqual(s.levelDB, 20 * log10(0.05), accuracy: 0.2)
            let total: Double = s.bandsDB.reduce(0.0) { (a: Double, b: Double) -> Double in a + power(b) }
            XCTAssertEqual(10 * log10(total), s.levelDB, accuracy: 1.0, "Parseval: banden ger level")
            XCTAssertGreaterThanOrEqual(s.peakDB, s.levelDB - 0.3, "toppen är minst medelnivån")
        }
    }

    func testTystnadÄrMinus120OchGerInteNaN() throws {
        var m = SoundMeter()
        let sMaybe = m.measure([Float](repeating: 0, count: 16_000))
        let s = try XCTUnwrap(sMaybe)
        XCTAssertEqual(s.level, -1200)
        XCTAssertEqual(s.levelA, -1200)
        XCTAssertEqual(s.peak, -1200)
        XCTAssertEqual(s.bands, [Int16](repeating: -1200, count: 8))
        var bad = [Float](repeating: 0.01, count: 16_000)
        bad[5] = .nan
        bad[6] = .infinity
        let tMaybe = m.measure(bad)
        let t = try XCTUnwrap(tMaybe)
        XCTAssertGreaterThan(t.level, -1200, "icke ändliga prov räknas som 0, resten mäts")
    }

    func testFelLängdGerIngenSekund() {
        var m = SoundMeter()
        let kort = m.measure([Float](repeating: 0, count: 15_999))
        XCTAssertNil(kort)
        let långt = m.measure([Float](repeating: 0, count: 16_001))
        XCTAssertNil(långt)
        let tomt = m.measure([])
        XCTAssertNil(tomt)
    }

    // MARK: Onset

    func testEttStegMittISekundenGerRättOnset() throws {
        var m = warmMeter()
        XCTAssertNotNil(m.floor.value, "golvet finns efter 30 sekunder")
        // Tyst till prov 8 500, sedan en ton: steget ligger i ram 8 (prov 8 000–8 999).
        var x: [Float] = noise(200, sigma: 0.0001)
        let ton: [Float] = sine(1_000, amplitude: 0.1)
        for n in 8_500..<16_000 { x[n] += ton[n] }
        let sMaybe = m.measure(x, second: 30)
        let s = try XCTUnwrap(sMaybe)
        XCTAssertEqual(s.onset, 8)
    }

    func testEttStegISekundensBörjanJämförsMotFörraSekundensSlut() throws {
        var m = warmMeter()
        let sMaybe = m.measure(sine(1_000, amplitude: 0.1), second: 30)
        let s = try XCTUnwrap(sMaybe)
        XCTAssertEqual(s.onset, 0)
        let tMaybe = m.measure(sine(1_000, amplitude: 0.1), second: 31)
        let t = try XCTUnwrap(tMaybe)
        XCTAssertEqual(t.onset, SoundSecond.noOnset, "samma ljud en sekund till har inget nytt steg")
    }

    func testTystBrusEfterGolvetHarIngenOnset() throws {
        var m = warmMeter()
        for i in 0..<5 {
            let sMaybe = m.measure(noise(UInt64(300 + i), sigma: 0.0001), second: 30 + i)
            let s = try XCTUnwrap(sMaybe)
            XCTAssertEqual(s.onset, SoundSecond.noOnset)
        }
    }

    func testUtanGolvFinnsIngenOnset() throws {
        var m = SoundMeter()
        _ = m.measure(noise(1, sigma: 0.0001))
        let sMaybe = m.measure(sine(1_000, amplitude: 0.1), second: 1)
        let s = try XCTUnwrap(sMaybe)
        XCTAssertEqual(s.onset, SoundSecond.noOnset, "före 30 sekunder finns inget golv att jämföra mot")
    }

    func testMätarensGolvÄrDetNoiseFloorRäknarIEfterhand() throws {
        var m = SoundMeter()
        var f = NoiseFloor()
        for i in 0..<45 {
            let sMaybe = m.measure(noise(UInt64(400 + i), sigma: i % 7 == 0 ? 0.01 : 0.001), second: i)
            let s = try XCTUnwrap(sMaybe)
            f.add(s.levelADB)
        }
        XCTAssertNotNil(f.value)
        XCTAssertEqual(m.floor, f, "samma sekunder ger samma golv i mätaren och i analysen")
    }
}
