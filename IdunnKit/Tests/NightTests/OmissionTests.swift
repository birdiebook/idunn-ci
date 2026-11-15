import Foundation
import XCTest
import HeartRate
@testable import Night

// PÅHITTADE nätter (NightGenerator.swift och generatorn nedan). METOD M3:
// slag som bandet utelämnar, och radions fördröjning. Förväntade tal är
// provade i Python med en spegel av generatorn och sökningen innan de skrevs in.

/// En natt där bandet utelämnar slag och notiserna kommer med fördröjning.
struct OmittingNight {
    var night: NightRecording
    /// Alla slag som slog, avrundade till 1/1024 s, även de utelämnade.
    var trueRR: [Double]
    /// Utelämnade slag.
    var omitted: Int
}

enum OmittingGenerator {
    /// Slagen andas: RR = `meanRR` + 50 ms · sin(2π t / 5 s) + brus (spridning
    /// 8 ms), alltså 12 andetag per minut. Andningen gör att två slag isär
    /// skiljer mer än grannar, så en skillnad över en lucka syns i RMSSD.
    ///
    /// Bandet skickar en notis i sekunden med slagen som blivit klara sedan
    /// förra, utom varje slag som utelämnas (sannolikhet `omit`, oberoende).
    /// Telefonen får notisen `latency` sekunder senare, likformigt dragen.
    static func night(seconds: Double, seed: UInt64, meanRR: Double, omit: Double,
                      latency: ClosedRange<Double> = 0.05...0.30) -> OmittingNight {
        let slag: [Double] = NightGenerator.beats(seconds: seconds, seed: seed) {
            (_: Int, t: Double, r: inout Seeded) -> Double in
            meanRR + 50 * sin(2 * Double.pi * t / 5) + 8 * r.gauss()
        }
        var r = Seeded(seed + 100)
        var utelämnad: [Bool] = []
        for _ in slag { utelämnad.append(r.uniform() < omit) }

        var samples: [HeartRateSample] = []
        var t: Double = NightGenerator.t0
        var next: Double = NightGenerator.t0 + 1
        var pending: [Double] = []
        for (i, x) in slag.enumerated() {
            t += x / 1000
            while t > next {
                let l: Double = latency.lowerBound + (latency.upperBound - latency.lowerBound) * r.uniform()
                samples.append(HeartRateSample(time: Date(timeIntervalSince1970: next + l), bpm: 60,
                                               rrMilliseconds: pending))
                pending = []
                next += 1
            }
            if !utelämnad[i] { pending.append(NightGenerator.quantized(x)) }
        }
        return OmittingNight(night: NightRecording(samples: samples),
                             trueRR: slag.map(NightGenerator.quantized),
                             omitted: utelämnad.filter { $0 }.count)
    }

    static func rmssd(_ d: [Double]) -> Double {
        let ss: Double = d.reduce(0.0) { (a: Double, x: Double) -> Double in a + x * x }
        return (ss / Double(d.count)).squareRoot()
    }

    /// Facit: RMSSD över alla slag som slog, utelämnade inräknade.
    static func trueRMSSD(_ n: OmittingNight) -> Double {
        rmssd(zip(n.trueRR, n.trueRR.dropFirst()).map { (p: (Double, Double)) -> Double in p.1 - p.0 })
    }

    /// Som `RRCleaning.differences`, men utan regeln om utelämnade slag: så
    /// räknades RMSSD före den.
    static func differencesIgnoringOmissions(_ beats: [Beat]) -> [Double] {
        var out: [Double] = []
        for i in beats.indices.dropFirst() {
            let a: Beat = beats[i - 1]
            let b: Beat = beats[i]
            guard a.segment == b.segment, a.isKept, b.isKept else { continue }
            out.append(b.rrMilliseconds - a.rrMilliseconds)
        }
        return out
    }
}

final class OmissionTests: XCTestCase {

    func testUtelämnadeSlagBlåserUppRMSSDUtanRegeln() throws {
        // En timme vid 61 slag/min: var tionde slag
        // utelämnas, och notiserna kommer 50–300 ms sent. Python-spegeln:
        // facit 42,76 ms, med regeln 42,87 (+0,3 %), utan 45,78 (+7,1 %).
        let n = OmittingGenerator.night(seconds: 3600, seed: 1, meanRR: 985, omit: 0.10)
        let facit: Double = OmittingGenerator.trueRMSSD(n)

        // Natten har både notiser utan RR och med två RR (METOD M15).
        let s = n.night.samples
        let tomma: Double = Double(s.filter { $0.rrMilliseconds.isEmpty }.count) / Double(s.count)
        let dubbla: Double = Double(s.filter { $0.rrMilliseconds.count == 2 }.count) / Double(s.count)
        XCTAssertGreaterThan(tomma, 0.05)
        XCTAssertGreaterThan(dubbla, 0.01)

        let beats = RRCleaning.clean(n.night)
        let summary = RRCleaning.summary(beats)
        XCTAssertEqual(summary.dropped, 0, "20 %-regeln ser inget: värdena är rimliga")

        let med: Double = OmittingGenerator.rmssd(RRCleaning.differences(beats).map(\.milliseconds))
        let utan: Double = OmittingGenerator.rmssd(OmittingGenerator.differencesIgnoringOmissions(beats))
        XCTAssertEqual(med / facit, 1, accuracy: 0.02, "med regeln: \(med) mot facit \(facit)")
        XCTAssertGreaterThan(utan / facit, 1.05, "utan regeln blir RMSSD för hög: \(utan) mot facit \(facit)")

        // Andelen utelämnade skattas nära den sanna (9 %; Python-spegeln 8,5 %).
        let sann: Double = Double(n.omitted) / Double(n.trueRR.count)
        XCTAssertEqual(summary.fractionOmitted, sann, accuracy: 0.02)
        XCTAssertGreaterThan(summary.omitted, 0)
    }

    func testLågPulsMedUtelämnadeSlag() throws {
        // 55 slag/min: RR över en sekund, så notiser utan RR kommer också av
        // sig själva. Python-spegeln: facit 46,74, med regeln +0,2 %, utan +6,1 %.
        let n = OmittingGenerator.night(seconds: 3600, seed: 1, meanRR: 1100, omit: 0.10)
        let facit: Double = OmittingGenerator.trueRMSSD(n)
        let beats = RRCleaning.clean(n.night)
        let med: Double = OmittingGenerator.rmssd(RRCleaning.differences(beats).map(\.milliseconds))
        let utan: Double = OmittingGenerator.rmssd(OmittingGenerator.differencesIgnoringOmissions(beats))
        XCTAssertEqual(med / facit, 1, accuracy: 0.02)
        XCTAssertGreaterThan(utan / facit, 1.04)
    }

    func testIngetUtelämnatGerIngenLuckaTrotsFördröjning() throws {
        // Utan utelämnade slag ska fördröjningen (50–300 ms, inom toleransen
        // 0,3 s) inte ge en enda lucka, vid hög, normal och låg puls.
        for (seed, meanRR) in [(UInt64(1), 900.0), (UInt64(1), 985.0), (UInt64(7), 985.0), (UInt64(7), 1100.0)] {
            let n = OmittingGenerator.night(seconds: 3600, seed: seed, meanRR: meanRR, omit: 0)
            let beats = RRCleaning.clean(n.night)
            let summary = RRCleaning.summary(beats)
            XCTAssertEqual(summary.omitted, 0, "RR \(meanRR), seed \(seed)")
            XCTAssertEqual(beats.filter(\.gapBefore).count, 0, "RR \(meanRR), seed \(seed)")
            let med: Double = OmittingGenerator.rmssd(RRCleaning.differences(beats).map(\.milliseconds))
            XCTAssertEqual(med / OmittingGenerator.trueRMSSD(n), 1, accuracy: 0.002)
        }
    }

    func testTommaNotiserUtanFördröjningLokaliserasExakt() throws {
        // En notis i sekunden, exakt i tid, RR 900 ms: en notis utan RR kan då
        // bara vara ett utelämnat slag, och luckan hamnar precis där.
        let rr: [Double] = (0..<600).map { (i: Int) -> Double in i % 2 == 0 ? 880 : 920 }
        let natt = NightGenerator.night(rr)
        var samples: [HeartRateSample] = []
        var tömda: Set<Int> = []
        for (i, s) in natt.samples.enumerated() {
            var c = s
            if i % 37 == 20 && s.rrMilliseconds.count == 1 {
                c.rrMilliseconds = []
                tömda.insert(i)
            }
            samples.append(c)
        }
        let beats = RRCleaning.clean(NightRecording(samples: samples))
        // Slaget efter varje tömd notis bär luckan, och inga andra.
        let medLucka: Set<Int> = Set(beats.filter(\.gapBefore).map(\.notification))
        var väntat: Set<Int> = []
        for i in tömda {
            if let nästa = (i + 1..<samples.count).first(where: { !samples[$0].rrMilliseconds.isEmpty }) {
                väntat.insert(nästa)
            }
        }
        XCTAssertEqual(medLucka, väntat)
        XCTAssertEqual(RRCleaning.summary(beats).omitted, tömda.count)
        // Växlingen 880/920 ger skillnaden ±40 (avrundat) mellan grannar; över
        // en lucka vore den 0. Ingen sådan räknas.
        XCTAssertTrue(RRCleaning.differences(beats).allSatisfy { abs($0.milliseconds) > 30 })
    }
}
