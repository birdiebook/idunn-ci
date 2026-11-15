// PÅHITTADE nätter för kontrollerna i RecordingQuality. Inget här kommer från
// ett riktigt band — intervallen räknas fram ur en formel och en seedad
// slumpgenerator, så att varje körning ger exakt samma natt. Lägg ALDRIG in
// riktiga inspelningar här — se CLAUDE.md §Dataregeln.
//
// Nätterna härmar hur 2A37 kommer från bandet: en notis i sekunden, med de
// slag som hunnit bli klara sedan förra notisen (0–n RR), intervallen
// avrundade till 1/1024 s, och pulsen som ett heltal ur de senaste fem slagen.
// Siffrorna nedan är provade i Python med samma generator innan de skrevs in.

import Foundation
@testable import HeartRate
import DemoData

/// SplitMix64, delad med förhandsvisningens påhittade nätter (DemoData).
typealias Seeded = DemoData.Seeded

enum NightFixtures {
    /// En påhittad starttid, jämn minut.
    static let t0: TimeInterval = 1_792_900_800

    /// Slag som från ett hjärta i vila: 1000 ms, en andningsvåg på 4,5 slag och
    /// slumpmässig variation. Mätta slag för slag.
    static func measuredBeats(_ n: Int = 3600, seed: UInt64 = 1) -> [Double] {
        var r = Seeded(seed)
        return (0..<n).map { (i: Int) -> Double in
            let andning: Double = 40 * sin(2 * Double.pi * Double(i) / 4.5)
            return 1000 + andning + 25 * r.gauss()
        }
    }

    /// En jämn, långsam kurva utan variation från slag till slag — som ett band
    /// som lämnar ut en utjämnad kurva i stället för slagen.
    static func smoothCurve(_ n: Int = 3600) -> [Double] {
        (0..<n).map { (i: Int) -> Double in
            let våg: Double = 100 * sin(2 * Double.pi * Double(i) / 60)
            return 1000 + våg
        }
    }

    /// Exponentiellt utjämnade slag (α = 0,05).
    static func exponentiallySmoothed(_ beats: [Double], alpha: Double = 0.05) -> [Double] {
        var y = beats.first ?? 0
        return beats.map { x in
            y += alpha * (x - y)
            return y
        }
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
        var recent: [Double] = []
        for x in beats {
            t += x / 1000
            while t > next {
                let last5 = recent.suffix(5)
                let bpm = last5.isEmpty ? 60 : Int((60_000 / (last5.reduce(0, +) / Double(last5.count))).rounded())
                samples.append(HeartRateSample(time: Date(timeIntervalSince1970: next), bpm: bpm,
                                               rrMilliseconds: pending, sensorContact: .detected))
                pending = []
                next += 1
            }
            pending.append(quantized(x))
            recent.append(x)
        }
        return samples
    }

    static func night(_ beats: [Double]) -> NightRecording {
        NightRecording(samples: notifications(beats))
    }

    /// Bandet räknar fram RR ur heltalspulsen: varje intervall är 60000/puls.
    static func computedFromBpm(_ beats: [Double]) -> NightRecording {
        NightRecording(samples: notifications(beats).map { s in
            var c = s
            c.rrMilliseconds = s.rrMilliseconds.map { _ in quantized(60_000 / Double(s.bpm)) }
            return c
        })
    }

    /// Bandet tappar slag: varannan notis kommer utan RR.
    static func missingBeats(_ beats: [Double]) -> NightRecording {
        NightRecording(samples: notifications(beats).enumerated().map { i, s in
            var c = s
            if i % 2 == 1 { c.rrMilliseconds = [] }
            return c
        })
    }

    /// METOD M15. Bandet upprepar förra notisens sista slag först i nästa
    /// notis, så att varje slag kommer två gånger. Med `reversed` står
    /// notisens slag senaste först.
    static func overlapping(_ beats: [Double], reversed: Bool = false) -> NightRecording {
        var last: Double?
        var out: [HeartRateSample] = []
        for s in notifications(beats) {
            var c = s
            if let nyast = s.rrMilliseconds.last {
                var rr: [Double] = last.map { [$0] } ?? []
                rr.append(contentsOf: s.rrMilliseconds)
                last = nyast
                c.rrMilliseconds = reversed ? Array(rr.reversed()) : rr
            }
            out.append(c)
        }
        return NightRecording(samples: out)
    }

    /// METOD M15. Tolkningen läser ett fält som inte är RR som första
    /// intervall i varje notis: ett tal som kryper långsamt (som en räknare för
    /// energi), här 100 steg plus ett per minut. Flaggbyten 0x16 i alla.
    static func extraField(_ beats: [Double]) -> NightRecording {
        NightRecording(samples: notifications(beats).enumerated().map { (i: Int, s: HeartRateSample) -> HeartRateSample in
            var c = s
            let steg: Double = 100 + Double(i / 60)
            c.rrMilliseconds = [steg * 1000 / 1024] + s.rrMilliseconds
            c.flags = 0x16
            return c
        })
    }

    /// Ingen notis mellan två tider (sekunder efter t0).
    static func withHole(_ night: NightRecording, from a: TimeInterval, to b: TimeInterval) -> NightRecording {
        NightRecording(samples: night.samples.filter {
            let t = $0.time.timeIntervalSince1970 - t0
            return t < a || t >= b
        })
    }
}
