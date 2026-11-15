// PÅHITTADE gravitationer för sömnmetoden (METOD M26, BESLUT B29). Inget kommer
// från ett riktigt band: armens z-vinkel räknas fram ur faser och en seedad
// slumpgenerator, och gravitationen är enhetsvektorn med den vinkeln. Lägg
// ALDRIG in riktiga värden här — se CLAUDE.md §Dataregeln.
//
// En K18-post per sekund (till skillnad från `DemoK18`, som har tre per minut):
// sömnmetoden medelvärdesbildar per 5 sekunder och kräver minst tre sekunder
// i en epok.

import Foundation
import WhoopFrames

public enum DemoSleep {

    /// En fas av natten. Tiderna är sekunder.
    public enum Phase: Equatable, Sendable {
        /// Armen ligger stilla: bara brus kring ett läge.
        case still(seconds: Int)
        /// Ett lägesbyte (8–40 grader) var `every`:e sekund, första direkt:
        /// vaken i sängen, eller en orolig sömn.
        case restless(seconds: Int, every: Int)
        /// Armen rör sig hela tiden: vaken och uppe.
        case active(seconds: Int)
        /// Inga poster alls (bandet av, eller ingen synk): tiden går, K18 saknas.
        case gap(seconds: Int)
        /// Ett enda lägesbyte utan tid: man vänder sig.
        case turn
    }

    private struct Pose {
        var angle: Double = 25
        var flip: Bool = false

        /// Ett lägesbyte på 8–40 grader, växelvis upp och ned, inom ±70.
        mutating func jump(_ r: inout Seeded) {
            let magnitude: Double = 8 + 32 * r.uniform()
            let sign: Double = flip ? -1 : 1
            flip.toggle()
            var next: Double = angle + sign * magnitude
            if abs(next) > 70 { next = angle - sign * magnitude }
            angle = next
        }
    }

    /// Posterna för `phases` i ordning från Unix-sekunden `start`. Samma `seed`
    /// ger exakt samma poster.
    public static func records(start: Int, phases: [Phase], seed: UInt64) -> [K18Record] {
        var r = Seeded(seed)
        let azimuth: Double = 2 * Double.pi * r.uniform()
        var pose = Pose()
        var t: Int = start
        var out: [K18Record] = []
        // Hudtemperaturen stiger de första timmarna och svajar lite (METOD M49 behöver en form att lägga bandet kring).
        // Räknad ur tiden och seed, utan slumpgeneratorn, så att gravitationen och sömnen blir exakt som förut.
        let nivå: Double = 32.4 + 0.2 * sin(Double(seed % 97))
        let hud: (Int) -> Double = { (s: Int) -> Double in
            let m: Double = Double(s - start) / 60
            return ((nivå + 0.9 * (1 - exp(-m / 90)) + 0.08 * sin(m / 40)) * 100).rounded() / 100
        }
        for phase in phases {
            switch phase {
            case .turn:
                pose.jump(&r)
            case .gap(let seconds):
                t += seconds
            case .still(let seconds):
                for _ in 0..<seconds {
                    out.append(record(time: t, angle: pose.angle + 0.05 * r.gauss(), azimuth: azimuth, skin: hud(t)))
                    t += 1
                }
            case .restless(let seconds, let every):
                for k in 0..<seconds {
                    if k % every == 0 { pose.jump(&r) }
                    out.append(record(time: t, angle: pose.angle + 0.05 * r.gauss(), azimuth: azimuth, skin: hud(t)))
                    t += 1
                }
            case .active(let seconds):
                for _ in 0..<seconds {
                    let step: Double = 25 * r.gauss()
                    pose.angle = max(-80, min(80, pose.angle + step))
                    out.append(record(time: t, angle: pose.angle + 0.05 * r.gauss(), azimuth: azimuth, skin: hud(t)))
                    t += 1
                }
            }
        }
        return out
    }

    /// En rimlig natt: uppe en stund, två till tre timmars stilla sömn med
    /// några vändningar, en orolig stund, mer sömn, en vaken stund i sängen
    /// och uppe igen. Längderna varierar med `seed`. Ger också facit: var
    /// insomning och uppvaknande är tänkta att ligga.
    public static func plausibleNight(start: Int, seed: UInt64) -> (records: [K18Record], onset: Int, wake: Int) {
        var r = Seeded(seed &* 31 &+ 5)
        let minute = 60
        let up: Int = (20 + Int(r.uniform() * 20)) * minute
        let firstSleep: Int = (150 + Int(r.uniform() * 60)) * minute
        let restlessFor: Int = (10 + Int(r.uniform() * 10)) * minute
        let secondSleep: Int = (150 + Int(r.uniform() * 90)) * minute
        let phases: [Phase] = [
            .active(seconds: up),
            .still(seconds: firstSleep / 2), .turn, .still(seconds: firstSleep / 2),
            .restless(seconds: restlessFor, every: 100),
            .still(seconds: secondSleep / 2), .turn, .still(seconds: secondSleep / 2),
            .active(seconds: 25 * minute),
        ]
        let records: [K18Record] = Self.records(start: start, phases: phases, seed: seed)
        return (records, start + up, start + up + firstSleep + restlessFor + secondSleep)
    }

    private static func record(time: Int, angle: Double, azimuth: Double, skin: Double) -> K18Record {
        let theta: Double = angle * Double.pi / 180
        let g = K18Record.Gravity(x: cos(theta) * cos(azimuth),
                                  y: cos(theta) * sin(azimuth),
                                  z: sin(theta))
        return K18Record(time: time, pulse: 55, rr: [], gravity: g,
                         skinTemperature: skin, bandTemperature: ((skin - 3) * 10).rounded() / 10)
    }
}
