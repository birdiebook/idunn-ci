// PÅHITTADE nätter för Night-testerna. Inget här kommer från ett riktigt band —
// intervallen räknas fram ur en formel och en seedad slumpgenerator, så att
// varje körning ger exakt samma natt. Lägg ALDRIG in riktiga inspelningar här —
// se CLAUDE.md §Dataregeln.
//
// Nätterna härmar 2A37 som i HeartRateTests/NightFixtures.swift: en notis i
// sekunden med de slag som hunnit bli klara, intervallen avrundade till
// 1/1024 s. Förväntade tal i testerna är provade i Python med en spegel av
// generatorn och algoritmerna innan de skrevs in.

import Foundation
@testable import HeartRate
import DemoData

/// SplitMix64, delad med förhandsvisningens påhittade nätter (DemoData).
typealias Seeded = DemoData.Seeded

enum NightGenerator {
    /// En påhittad starttid, jämn minut.
    static let t0: TimeInterval = 1_792_900_800

    /// Slag i `seconds` sekunder. `rr(i, t, &slump)` ger slag nummer `i`, som
    /// börjar `t` sekunder in i natten.
    static func beats(seconds: Double, seed: UInt64 = 1,
                      _ rr: (Int, Double, inout Seeded) -> Double) -> [Double] {
        var r = Seeded(seed)
        var t: Double = 0
        var i = 0
        var out: [Double] = []
        while t < seconds {
            let x: Double = rr(i, t, &r)
            out.append(x)
            t += x / 1000
            i += 1
        }
        return out
    }

    /// Varannat slag 975 och 1025 ms: varje skillnad är 50 ms, före avrundningen.
    static func alternating(seconds: Double) -> [Double] {
        beats(seconds: seconds) { (i: Int, _: Double, _: inout Seeded) -> Double in i % 2 == 0 ? 975 : 1025 }
    }

    /// Avrundat till bandets upplösning, 1/1024 s.
    static func quantized(_ ms: Double) -> Double {
        (ms * 1.024).rounded() * 1000 / 1024
    }

    /// Slagen som notiser, en i sekunden.
    static func notifications(_ beats: [Double]) -> [HeartRateSample] {
        var samples: [HeartRateSample] = []
        var t = t0
        var next = t0 + 1
        var pending: [Double] = []
        for x in beats {
            t += x / 1000
            while t > next {
                samples.append(HeartRateSample(time: Date(timeIntervalSince1970: next), bpm: 60,
                                               rrMilliseconds: pending, sensorContact: .detected))
                pending = []
                next += 1
            }
            pending.append(quantized(x))
        }
        return samples
    }

    static func night(_ beats: [Double]) -> NightRecording {
        NightRecording(samples: notifications(beats))
    }

    /// Notiserna mellan två tider (sekunder efter t0) kommer, men utan RR.
    static func withoutRR(_ night: NightRecording, from a: TimeInterval, to b: TimeInterval) -> NightRecording {
        NightRecording(samples: night.samples.map { (s: HeartRateSample) -> HeartRateSample in
            let t: TimeInterval = s.time.timeIntervalSince1970 - t0
            var c = s
            if t >= a && t < b { c.rrMilliseconds = [] }
            return c
        })
    }

    /// METOD M15. Bandet upprepar förra notisens sista slag först i nästa notis.
    static func overlapping(_ night: NightRecording) -> NightRecording {
        var last: Double?
        return NightRecording(samples: night.samples.map { (s: HeartRateSample) -> HeartRateSample in
            var c = s
            if let nyast = s.rrMilliseconds.last {
                c.rrMilliseconds = (last.map { [$0] } ?? []) + s.rrMilliseconds
                last = nyast
            }
            return c
        })
    }

    /// Ett slag per notis, exakt de givna värdena, en notis i sekunden.
    static func oneBeatPerSecond(_ rr: [Double], from start: TimeInterval = t0) -> NightRecording {
        var samples: [HeartRateSample] = []
        for (i, x) in rr.enumerated() {
            samples.append(HeartRateSample(time: Date(timeIntervalSince1970: start + Double(i)), bpm: 60,
                                           rrMilliseconds: [x]))
        }
        return NightRecording(samples: samples)
    }
}
