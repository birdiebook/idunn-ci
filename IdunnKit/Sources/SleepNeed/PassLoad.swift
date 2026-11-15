import Foundation
import Pass

/// BESLUT B64 · METOD M53
/// Passets belastning: minuter i varje pulszon gånger zonens nummer (summated heart
/// rate zones, Edwards zoner som i Leota m.fl. 2025). Bastu och dusch är värme, inte
/// arbete, och ger ingen belastning (samma skäl som M47).
public enum PassLoad {
    /// METOD M53. Zonen 0–5 för en puls mot maxpulsen.
    public static func zone(bpm: Int, maxPulse: Double) -> Int {
        guard maxPulse > 0 else { return 0 }
        let f = Double(bpm) / maxPulse
        return SleepNeedRules.zoneLowerBounds.filter { f >= $0 }.count
    }

    /// METOD M53. Summan av minuter × zon över proven. Varje prov gäller fram till
    /// nästa, om nästa kommer inom 5 s; ett längre glapp räknas inte.
    public static func zoneScore(_ samples: [PassSample], maxPulse: Double) -> Double {
        guard samples.count > 1 else { return 0 }
        var sum = 0.0
        for i in 0..<(samples.count - 1) {
            let dt = samples[i + 1].t.timeIntervalSince(samples[i].t)
            guard dt > 0, dt <= SleepNeedRules.sampleGapSeconds else { continue }
            sum += dt / 60 * Double(zone(bpm: samples[i].bpm, maxPulse: maxPulse))
        }
        return sum
    }

    /// METOD M53. Passets belastning: 0 för bastu och dusch, minst 2 enheter per
    /// minut för styrka, annars zonsumman över den aktiva delen.
    public static func load(_ pass: Pass, maxPulse: Double) -> Double {
        switch pass.kind {
        case .some(.bastu), .some(.dusch):
            return 0
        case .some(.styrka):
            let score = zoneScore(pass.activeSamples, maxPulse: maxPulse)
            return max(score, SleepNeedRules.strengthLoadPerMinute * pass.duration / 60)
        case .some(.kondition), .some(.promenad), .none:
            return zoneScore(pass.activeSamples, maxPulse: maxPulse)
        }
    }

    /// METOD M53. Maxpulsen ur passen: den högsta medianen av fem prov i följd i den
    /// aktiva delen, utom bastu och dusch. `nil` utan tillräckligt många prov.
    public static func maxPulse(from passes: [Pass]) -> Double? {
        let n = SleepNeedRules.maxPulseMedianSamples
        var best: Double?
        for p in passes where p.kind != .bastu && p.kind != .dusch {
            let bpm = p.activeSamples.map { Double($0.bpm) }
            guard bpm.count >= n else { continue }
            for i in 0...(bpm.count - n) {
                let m = SleepNeed.median(Array(bpm[i..<(i + n)]))!
                if best == nil || m > best! { best = m }
            }
        }
        return best
    }

    /// METOD M53. Reserven när passen inte räcker: 208 − 0,7 × ålder (Tanaka m.fl. 2001).
    public static func tanakaMaxPulse(age: Double) -> Double { 208 - 0.7 * age }
}
