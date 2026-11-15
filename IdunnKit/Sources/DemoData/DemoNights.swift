// PÅHITTADE nätter för förhandsvisningen (målet IdunnProv, `tools/prov.py`).
// Inget här kommer från ett riktigt band: slagen räknas fram ur en formel och
// en seedad slumpgenerator. Lägg ALDRIG in riktiga inspelningar här — se
// CLAUDE.md §Dataregeln.
//
// En natt härmar hur 2A37 kommer från bandet (som HeartRateTests/
// NightFixtures.swift): en notis i sekunden med de slag som hunnit bli klara,
// intervallen avrundade till 1/1024 s och pulsen ur de senaste fem slagen.
// Formen är en vanlig natt: pulsen faller mot en botten en tredjedel in och
// stiger mot morgonen, sömncykler på 90 minuter, andningsvågen i intervallen
// (starkast i den tidiga djupsömnen), enstaka extraslag, slag som bandet hoppar
// över, och ett glapp på några minuter då bandet tappade kontakten.

import Foundation
import HeartRate
import WhoopFrames

public enum DemoNights {
    /// Telefonens zon i de påhittade nätterna, sekunder öster om Greenwich.
    public static let utcOffsetSeconds = 7200

    /// Den sista påhittade morgonen: söndag 11 oktober 2026, midnatt UTC.
    public static let lastWakeDayUTC: TimeInterval = 1_791_676_800

    /// En natt som appen skulle ha skrivit den: JSONL i `RecordingLog`:s format.
    public struct Night: Sendable {
        /// Första notisen.
        public var start: Date
        /// Sista notisen.
        public var end: Date
        public var log: Data
        /// METOD M25. Nattens K18-poster, påhittade: tre sekunder i följd per
        /// minut som Whoop-appens synk hann få med (`DemoK18`).
        public var k18: [K18Record] = []
    }

    /// `count` nätter, en per morgon, äldst först; den sista vaknar
    /// `lastWakeDayUTC`. Samma seed ger samma nätter.
    public static func nights(count: Int, seed: UInt64 = 1) -> [Night] {
        (0..<count).reversed().map { (k: Int) -> Night in night(daysBeforeLast: k, seed: seed) }
    }

    /// Natten som slutar `k` morgnar före den sista.
    public static func night(daysBeforeLast k: Int, seed: UInt64 = 1) -> Night {
        var r = Seeded(seed &+ UInt64(k) &* 7919)
        // Midnatt på uppvakningsdagen i telefonens zon, som ett ögonblick.
        let midnatt: TimeInterval = lastWakeDayUTC - Double(k) * 86_400 - Double(utcOffsetSeconds)
        let insomning: TimeInterval = midnatt - 3_600 + 1_500 * clamp(r.gauss(), -2, 2)
        let längd: TimeInterval = 3_600 * (7.6 + 0.4 * clamp(r.gauss(), -2.2, 2.2))
        let slag = beats(seconds: längd, random: &r)
        let notiser = notifications(slag, start: insomning, seconds: längd, random: &r)

        var log = RecordingLog.header(utcOffsetSeconds: utcOffsetSeconds)
        let batteri = 96 - Int(r.uniform() * 8)
        log.append(RecordingLog.batteryAtStart(batteri))
        for s in notiser { log.append(RecordingLog.line(s)) }
        let slut = notiser.last?.time ?? Date(timeIntervalSince1970: insomning + längd)
        log.append(RecordingLog.batteryAtEnd(batteri - 7 - Int(r.uniform() * 5)))
        log.append(RecordingLog.stopped(at: slut))
        var natt = Night(start: notiser.first?.time ?? Date(timeIntervalSince1970: insomning), end: slut, log: log)
        natt.k18 = DemoK18.records(start: natt.start, end: natt.end, daysBeforeLast: k, seed: seed)
        return natt
    }

    // MARK: Slagen

    /// Slagen, i millisekunder, i `seconds` sekunder.
    static func beats(seconds: TimeInterval, random r: inout Seeded) -> [Double] {
        let pulsStart: Double = 63 + 2 * r.gauss()
        let botten: Double = 50.5 + 1.5 * r.gauss()
        let stigning: Double = 6 + r.gauss()
        let tau: Double = 2_400 + 900 * r.uniform()
        let andning: Double = 14.2 + 0.6 * r.gauss()   // andetag per minut
        let vågBas: Double = 50 + 6 * r.gauss()        // andningsvågens storlek, ms
        var vandring: Double = 0
        var fas: Double = 0
        var t: Double = 0
        var ut: [Double] = []
        ut.reserveCapacity(Int(seconds * 1.1))
        while t < seconds {
            let andel: Double = t / seconds
            let sen: Double = max(0, (andel - 0.45) / 0.55)
            let cykel: Double = max(0, sin(2 * Double.pi * t / 5_400 - 1.2))
            let puls: Double = botten + (pulsStart - botten) * exp(-t / tau)
                + stigning * sen * sen + 2.2 * cykel + vandring
            vandring = 0.999 * vandring + 0.02 * r.gauss()
            let djup: Double = exp(-pow((andel - 0.3) / 0.15, 2))
            let våg: Double = vågBas * (0.7 + 0.6 * djup - 0.3 * cykel)
            var x: Double = 60_000 / puls + våg * sin(fas) + 15 * r.gauss()
            if r.uniform() < 0.0006 {
                // Ett extraslag: kort, och ett långt efter (kompensatorisk paus).
                let kort: Double = 0.68 * x
                ut.append(kort)
                t += kort / 1000
                x = 1.3 * x
            }
            ut.append(x)
            t += x / 1000
            fas += 2 * Double.pi * andning / 60 * x / 1000
        }
        return ut
    }

    // MARK: Notiserna

    /// Avrundat till bandets upplösning, 1/1024 s.
    static func quantized(_ ms: Double) -> Double {
        (ms * 1.024).rounded() * 1000 / 1024
    }

    /// Slagen som notiser, en i sekunden. Bandet hoppar över enstaka slag
    /// (METOD M3), och under ett glapp på 3–7 minuter kommer inga notiser alls.
    static func notifications(_ beats: [Double], start: TimeInterval, seconds: TimeInterval,
                              random r: inout Seeded) -> [HeartRateSample] {
        let glappStart: Double = seconds * (0.52 + 0.1 * r.uniform())
        let glappSlut: Double = glappStart + 180 + 240 * r.uniform()
        var samples: [HeartRateSample] = []
        samples.reserveCapacity(Int(seconds) + 1)
        var t: Double = 0
        var next: Double = 1
        var pending: [Double] = []
        var recent: [Double] = []
        for x in beats {
            t += x / 1000
            while t > next {
                if next < glappStart || next >= glappSlut {
                    let last5 = recent.suffix(5)
                    let bpm: Int = last5.isEmpty ? 60
                        : Int((60_000 / (last5.reduce(0, +) / Double(last5.count))).rounded())
                    samples.append(HeartRateSample(time: Date(timeIntervalSince1970: start + next), bpm: bpm,
                                                   rrMilliseconds: pending, sensorContact: .detected,
                                                   flags: pending.isEmpty ? 0x06 : 0x16))
                }
                pending = []
                next += 1
            }
            recent.append(x)
            if recent.count > 5 { recent.removeFirst() }
            // Bandet hoppar över slaget: tiden går, men intervallet kommer inte.
            if r.uniform() < 0.003 { continue }
            pending.append(quantized(x))
        }
        return samples
    }

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
}
