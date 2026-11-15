// PÅHITTADE K18-poster för förhandsvisningen (BESLUT B20, B26). Inget kommer
// från ett riktigt band: gravitation och temperatur räknas fram ur formler och
// en seedad slumpgenerator. Lägg ALDRIG in riktiga värden här — se CLAUDE.md
// §Dataregeln.
//
// Formen: tre sekunder i följd per minut (så att rörelsen har en Δ att räknas
// på), en stilla arm för det mesta och enstaka oroliga minuter, hudtemperaturen
// som stiger de första timmarna efter insomning och är högre i de oroliga
// minuterna (så att stillhetsregeln syns). Idunns nivå ligger ungefär 0,6 °C
// under Whoops i `DemoWhoop`, så att nivåskillnaden finns att räkna. Normala
// nätter saknar en tiondel (Whoop-appen hann inte synka); var sjunde natt
// (`daysBeforeLast % 7 == 3`) täcks bara första tredjedelen, under minsta
// täckning (METOD M25), så att Över tid får en natt utan prick.

import Foundation
import WhoopFrames

public enum DemoK18 {

    /// Natten som slutar `k` morgnar före den sista, för inspelningen `start`…`end`.
    public static func records(start: Date, end: Date, daysBeforeLast k: Int, seed: UInt64) -> [K18Record] {
        var r = Seeded(seed &+ UInt64(k) &* 104_729 &+ 31)
        let kort: Bool = k % 7 == 3
        let glappStart: Double = 0.45 + 0.2 * r.uniform()
        let nivå: Double = 32.6 + 0.22 * sin(Double(k) * 0.7) + 0.12 * r.gauss()

        let first: Int = Int((start.timeIntervalSince1970 / 60).rounded(.up))
        let last: Int = Int((end.timeIntervalSince1970 / 60).rounded(.down))
        guard last > first else { return [] }
        let längd: Double = Double(last - first)

        var ut: [K18Record] = []
        ut.reserveCapacity((last - first) * 3)
        for minut in first..<last {
            let andel: Double = Double(minut - first) / längd
            if kort {
                if andel >= 0.3 { continue }
            } else if andel >= glappStart && andel < glappStart + 0.1 {
                continue
            }
            let orolig: Bool = r.uniform() < 0.08
            let stigning: Double = 0.9 * (1 - exp(-Double(minut - first) / 90))
            for j in 0..<3 {
                let spridning: Double = orolig ? 0.15 : 0.004
                let g = K18Record.Gravity(x: spridning * r.gauss(),
                                          y: spridning * r.gauss(),
                                          z: 1 + spridning * r.gauss())
                let hud: Double = nivå + stigning + (orolig ? 0.3 : 0) + 0.04 * r.gauss()
                ut.append(K18Record(time: minut * 60 + j, pulse: 55, rr: [], gravity: g,
                                    skinTemperature: (hud * 100).rounded() / 100,
                                    bandTemperature: ((hud - 3) * 10).rounded() / 10))
            }
        }
        return ut
    }
}
