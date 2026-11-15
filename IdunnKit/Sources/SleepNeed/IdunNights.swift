import Foundation
import Night

/// BESLUT B65 · METOD M53
/// Idunns nätter som sömnbehovet räknar med (`Trends.IdunNight`, samma nätter som vyerna ser): bara nätter ur K18,
/// för bara de har en sömnperiod och en sovtid (METOD M26, M37). En gammal inspelning har ingen period och räknas
/// inte; den natten saknas för skulden, som då står still (M53).
extension SleepNight {
    /// Natten ur Idunns natt, eller `nil` när den saknar sovtid eller period. Insomning och uppvaknande tas ur
    /// nattens minuter (METOD M52) och annars ur sömnperioden (en sammanfattning från före D2).
    public init?(_ n: Trends.IdunNight) {
        guard n.source == .k18, let timmar = n.sleepHours, timmar > 0 else { return nil }
        let insomning: Double
        let uppvaknande: Double
        if let o = n.onsetMinutes, let w = n.wakeMinutes {
            insomning = o
            uppvaknande = w
        } else if let p = n.sleepEpisode {
            insomning = Trends.clockMinutes(p.onset, day: n.day, utcOffsetSeconds: p.utcOffsetSeconds)
            uppvaknande = Trends.clockMinutes(p.wake, day: n.day, utcOffsetSeconds: p.utcOffsetSeconds)
        } else {
            return nil
        }
        guard uppvaknande > insomning else { return nil }
        self.init(day: n.day.daysSince1970, asleepMinutes: timmar * 60, periodMinutes: uppvaknande - insomning,
                  onsetMinute: insomning, wakeMinute: uppvaknande)
    }
}

extension SleepNeed {
    /// METOD M53 · BESLUT B65. En natt per uppvakningsdag ur Idunns nätter, äldst först. Finns två nätter ur K18
    /// samma dag gäller den med längst sovtid. Nätterna sållas inte på HRV:s fönster (METOD M14): sovtiden beror inte
    /// på dem.
    public static func nights(_ idun: [Trends.IdunNight]) -> [SleepNight] {
        var perDag: [Int: SleepNight] = [:]
        for n in idun {
            guard let s = SleepNight(n) else { continue }
            if let finns = perDag[s.day], finns.asleepMinutes >= s.asleepMinutes { continue }
            perDag[s.day] = s
        }
        return perDag.values.sorted { $0.day < $1.day }
    }

    /// METOD M56 · BESLUT B71. Idunns natt bakom varje natt i `nights`: samma val (K18 med sovtid och period, den med
    /// längst sovtid samma dag), så att sömnpoängen räknar på samma natt som sömnbehovet.
    public static func k18PerDay(_ idun: [Trends.IdunNight]) -> [Int: Trends.IdunNight] {
        var perDag: [Int: (SleepNight, Trends.IdunNight)] = [:]
        for n in idun {
            guard let s = SleepNight(n) else { continue }
            if let finns = perDag[s.day], finns.0.asleepMinutes >= s.asleepMinutes { continue }
            perDag[s.day] = (s, n)
        }
        return perDag.mapValues { $0.1 }
    }
}
