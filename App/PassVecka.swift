import SwiftUI
import Pass
import SleepNeed

/// BESLUT B126 · METOD M72
/// Veckan i fliken Pass: tid, sträcka och belastning hittills i veckan mot snittet för de fyra veckorna före.
enum PassVecka {
    /// Översikten för veckan `idag` ligger i. Utan maxpuls räknas ingen belastning och inga zoner.
    static func oversikt(_ pass: [Pass], maxpuls: Double?, idag: Int = KonditionModell.idag()) -> PassWeek.Overview {
        let klass: ((Int) -> Int)? = maxpuls.map { (m: Double) -> ((Int) -> Int) in
            { (bpm: Int) -> Int in PassLoad.zone(bpm: bpm, maxPulse: m) }
        }
        return PassWeek.overview(pass, day: idag,
                                 dayOf: { (p: Pass) -> Int in KonditionModell.dag(för: p) },
                                 load: { (p: Pass) -> Double in
                                     maxpuls.map { (m: Double) -> Double in PassLoad.load(p, maxPulse: m) } ?? 0
                                 },
                                 classify: klass)
    }

    /// BESLUT B134 · METOD M78. Perioden (vecka, fyra veckor, halvår, år) som `idag` ligger i, summerad per stapel.
    static func period(_ pass: [Pass], period: PassPeriod, maxpuls: Double?, idag: Int) -> PassPeriod.Overview {
        let klass: ((Int) -> Int)? = maxpuls.map { (m: Double) -> ((Int) -> Int) in
            { (bpm: Int) -> Int in PassLoad.zone(bpm: bpm, maxPulse: m) }
        }
        return period.overview(pass, day: idag,
                               dayOf: { (p: Pass) -> Int in KonditionModell.dag(för: p) },
                               load: { (p: Pass) -> Double in
                                   maxpuls.map { (m: Double) -> Double in PassLoad.load(p, maxPulse: m) } ?? 0
                               },
                               classify: klass)
    }
}
