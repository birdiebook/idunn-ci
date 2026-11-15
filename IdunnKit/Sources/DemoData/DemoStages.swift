// PÅHITTADE sömnstadier för demonätterna (METOD M35 · METOD M37, BESLUT B46).
// Inget kommer från ett riktigt band eller en riktig natt: hypnogrammet är en
// formel och en seedad slumpgenerator, och slagen följer det. Lägg ALDRIG in
// riktiga värden här — se CLAUDE.md §Dataregeln.
//
// Hypnogrammet: cykler på 75–100 minuter. Djup sömn mest i de två första,
// REM i slutet av varje cykel och längre mot morgonen, lätt däremellan, och
// korta vakna stunder mellan cyklerna. Slagen följer stadiet så som METOD M35
// jämför dem mot nattens egen nivå och en rullande timme:
//
//   djup  lägre puls, liten och jämn variation, en tydlig och regelbunden
//         andningsvåg (~0,25 Hz) och mest vitt brus (lågt DDFA α1)
//   REM   högre puls, större och långsam, oregelbunden variation (högt α1) och
//         en otydlig andningstopp
//   lätt  däremellan
//   vaken högst puls
//
// Pulsen faller dessutom långsamt över natten, som i `DemoNights.beats`. Gravi-
// tationen (och därmed rörelsen, som ger vaken ur sömnmodellen) är `DemoSleep`:s
// faser och ändras inte här.

import Foundation

enum DemoStages {

    /// Stadierna, i samma ordning som modellens klasser.
    enum Stage: Int {
        case wake = 0, light = 1, deep = 2, rem = 3
    }

    /// Hypnogrammet per 30-sekundersepok, minst `n` långt. Epoker i `wakeWindows`
    /// (sekunder efter insomning, från och med till och med) är vakna: där ligger
    /// den oroliga stunden i nattens rörelse.
    static func hypnogram(epochs n: Int, wakeWindows: [(from: Int, to: Int)], random r: inout Seeded) -> [Stage] {
        var out: [Stage] = []
        out.reserveCapacity(n + 300)
        let deepShare: [Double] = [0.40, 0.30, 0.12, 0.03]
        let remShare: [Double] = [0.10, 0.18, 0.24, 0.30]
        var cycle: Int = 0
        while out.count < n {
            let c: Int = min(cycle, 3)
            let length: Int = 150 + Int(r.uniform() * 50)
            let dShare: Double = deepShare[c] + 0.04 * r.gauss()
            let rShare: Double = remShare[c] + 0.04 * r.gauss()
            let deepN: Int = max(0, Int(Double(length) * dShare))
            let remN: Int = max(0, Int(Double(length) * rShare))
            let lightN: Int = max(2, length - deepN - remN)
            let before: Int = Int(Double(lightN) * 0.3)
            out += [Stage](repeating: .light, count: before)
            out += [Stage](repeating: .deep, count: deepN)
            out += [Stage](repeating: .light, count: lightN - before)
            out += [Stage](repeating: .rem, count: remN)
            if r.uniform() < 0.5 {
                out += [Stage](repeating: .wake, count: 1 + Int(r.uniform() * 3))
            }
            cycle += 1
        }
        out = Array(out.prefix(n))
        for w in wakeWindows {
            let a: Int = max(0, w.from / 30)
            let b: Int = min(n, w.to / 30 + 1)
            if a < b {
                for j in a..<b { out[j] = .wake }
            }
        }
        return out
    }

    /// Hur ett stadium färgar slagen.
    private struct Shape {
        /// Pulsen över nattens kurva, slag per minut.
        var pulse: Double
        /// Andningsvågens storlek, millisekunder.
        var breathing: Double
        /// Hur mycket andningens takt slingrar (0 = jämn).
        var irregular: Double
        /// Den långsamma slumpvandringens steg, millisekunder.
        var drift: Double
        /// Vitt brus, millisekunder.
        var noise: Double
    }

    private static func shape(_ s: Stage) -> Shape {
        switch s {
        case .wake: return Shape(pulse: 9, breathing: 25, irregular: 0.5, drift: 14, noise: 20)
        case .light: return Shape(pulse: 0, breathing: 40, irregular: 0.15, drift: 7, noise: 17)
        case .deep: return Shape(pulse: -3, breathing: 70, irregular: 0.02, drift: 2, noise: 7)
        case .rem: return Shape(pulse: 4, breathing: 14, irregular: 0.8, drift: 20, noise: 15)
        }
    }

    /// Slagen (millisekunder) i `seconds` sekunder, stadiet ur `hypnogram` per
    /// 30 sekunder. Samma form som `DemoNights.beats`: pulsen faller mot en botten
    /// och stiger mot morgonen, en andningsvåg, ett extraslag då och då.
    static func beats(seconds: TimeInterval, hypnogram: [Stage], random r: inout Seeded) -> [Double] {
        let pulsStart: Double = 63 + 2 * r.gauss()
        let botten: Double = 50.5 + 1.5 * r.gauss()
        let stigning: Double = 6 + r.gauss()
        let tau: Double = 2_400 + 900 * r.uniform()
        let andning: Double = 14.2 + 0.6 * r.gauss()   // andetag per minut
        let vågBas: Double = 50 + 6 * r.gauss()        // andningsvågens storlek, ms
        var vandring: Double = 0
        var långsam: Double = 0
        var takt: Double = 0
        var fas: Double = 0
        var t: Double = 0
        var ut: [Double] = []
        ut.reserveCapacity(Int(seconds * 1.1))
        while t < seconds {
            let epok: Int = min(Int(t / 30), hypnogram.count - 1)
            let f: Shape = shape(hypnogram[epok])
            let andel: Double = t / seconds
            let sen: Double = max(0, (andel - 0.45) / 0.55)
            let fall: Double = botten + (pulsStart - botten) * exp(-t / tau)
            let puls: Double = fall + stigning * sen * sen + vandring + f.pulse
            vandring = 0.999 * vandring + 0.02 * r.gauss()
            långsam = 0.9 * långsam + f.drift * r.gauss()
            takt = 0.95 * takt + 0.4 * r.gauss()
            let våg: Double = f.breathing * (vågBas / 50) * sin(fas)
            var x: Double = 60_000 / puls + våg + långsam
            x += f.noise * r.gauss()
            if r.uniform() < 0.0006 {
                // Ett extraslag: kort, och ett långt efter (kompensatorisk paus).
                let kort: Double = 0.68 * x
                ut.append(kort)
                t += kort / 1000
                x = 1.3 * x
            }
            ut.append(x)
            t += x / 1000
            fas += 2 * Double.pi * (andning + f.irregular * 6 * takt) / 60 * x / 1000
        }
        return ut
    }
}
