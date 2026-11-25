import Foundation
import Night

/// BESLUT B65 · BESLUT B161 · METOD M53
/// Idunns nätter som sömnbehovet räknar med (`Trends.IdunNight`, samma nätter som vyerna ser): bara nätter ur K18,
/// för bara de har en sömnperiod och en sovtid (METOD M26, M37), och bara med minst `Trends.minValidWindows` giltiga
/// fönster (METOD M14), samma gräns som vyerna. En gammal inspelning, eller en natt som bandet bara hörde en bit av,
/// räknas inte; den natten saknas för skulden, som då står still (M53).
extension SleepNight {
    /// Natten ur Idunns natt, eller `nil` när den saknar sovtid eller period eller har för få giltiga fönster för att
    /// räknas som en natt. Insomning och uppvaknande tas ur nattens minuter (METOD M52) och annars ur sömnperioden
    /// (en sammanfattning från före D2).
    public init?(_ n: Trends.IdunNight) {
        // BESLUT B161. En natt som vyerna inte visar (för lite av natten hördes) är en natt som saknas, inte en kort
        // natt: annars blev skulden ett helt behov större för en natt som inte syntes.
        guard n.source == .k18, n.validWindows >= Trends.minValidWindows,
              let timmar = n.sleepHours, timmar > 0 else { return nil }
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
    /// METOD M53 · BESLUT B65 · BESLUT B161. En natt per uppvakningsdag ur Idunns nätter, äldst först. Finns två
    /// nätter ur K18 samma dag gäller den med längst sovtid. Nätter under `Trends.minValidWindows` giltiga fönster
    /// (METOD M14) räknas inte, som i vyerna: där hördes för lite av natten för att sovtiden ska säga något.
    public static func nights(_ idun: [Trends.IdunNight]) -> [SleepNight] {
        var perDag: [Int: SleepNight] = [:]
        for n in idun {
            guard let s = SleepNight(n) else { continue }
            if let finns = perDag[s.day], finns.asleepMinutes >= s.asleepMinutes { continue }
            perDag[s.day] = s
        }
        return perDag.values.sorted { $0.day < $1.day }
    }

    /// METOD M56 · BESLUT B71. Idunns natt bakom varje natt i `nights`: samma val (K18 med sovtid, period och nog med
    /// giltiga fönster, den med längst sovtid samma dag), så att sömnpoängen räknar på samma natt som sömnbehovet.
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
