import Foundation
import Night

/// METOD M57 · BESLUT B72
/// Konstanterna för återhämtningen som poäng (PLAN.md H3). Varje värde har sin rad i METOD M57 med källa och status;
/// källorna står i docs/KALLOR.md.
public enum RecoveryRules {
    /// METOD M57. Baslinjen är de egna nätterna med uppvakningsdag 1–28 dagar före (Javaloyes 2019, Vesterinen 2016,
    /// Nuuttila 2022: fyra veckor).
    public static let baselineDays = 28
    /// METOD M57. SD:n krymps mot priorn med så många nätters vikt. Antagande.
    public static let priorNights: Double = 7
    /// METOD M57. Priorns SD för ln(HRV): HRV:s CV inom person 27 % (Miller 2020).
    public static let priorSDLnHRV: Double = 0.26
    /// METOD M57. Priorns SD för pulsen under sömnen: 4,83 slag/min inom person (Miller 2020, för vilopulsen).
    public static let priorSDHeartRate: Double = 4.8
    /// METOD M57. Priorns SD för andningen: 0,51 andetag/min inom person (Miller 2020).
    public static let priorSDBreathing: Double = 0.5
    /// METOD M57 · BESLUT B72. HRV:s andel av den autonoma delen; resten är medelpulsen under sömnen, med minus.
    public static let hrvShare: Double = 0.75
    /// METOD M57. Poängen vid z = 0 och sömn = behov, och poäng per SD av den autonoma delen (anpassat på Whoop).
    public static let middle: Double = 64
    public static let scale: Double = 18
    /// METOD M57. Poäng per procentenhet sömn under nattens behov; sömn över behovet ger 0 (anpassat på Whoop).
    public static let sleepWeight: Double = 0.3
    /// METOD M57 · BESLUT B72. Andningen vägs inte in men visas när den ligger mer än så många SD över ditt normala.
    public static let breathingFlagZ: Double = 2
    /// METOD M57 · BESLUT B72. Färgerna: grönt från 67, rött under 34 (Whoop).
    public static let green: Double = 67
    public static let red: Double = 34
}

/// METOD M57. Medel och SD ur de egna nätterna före; SD:n krympt mot priorn.
public struct RecoveryBaseline: Equatable, Sendable {
    public var n: Int
    public var mean: Double?
    public var sd: Double?
}

/// METOD M57. En natt som återhämtningen räknar med.
public struct RecoveryNight: Equatable, Sendable {
    public var day: Int
    /// Nattens HRV, RMSSD i ms (M4).
    public var rmssd: Double?
    /// Medelpulsen under sömnen (B34), slag/min.
    public var heartRate: Double?
    /// Andningen, andetag/min (M10).
    public var breathing: Double?
    /// Sovtid delad med nattens behov (H1), oklippt; `nil` utan sovtid.
    public var sleepShare: Double?

    public init(day: Int, rmssd: Double?, heartRate: Double?, breathing: Double?, sleepShare: Double?) {
        self.day = day
        self.rmssd = rmssd
        self.heartRate = heartRate
        self.breathing = breathing
        self.sleepShare = sleepShare
    }
}

/// METOD M57 · BESLUT B72
/// En natts återhämtning: poängen och "Vad som drog" i poäng. Bidragen summerar med mitten (64) till poängen före
/// klippningen till 0–100.
public struct RecoveryScore: Equatable, Sendable {
    public var day: Int
    public var score: Double
    /// Bidragen: HRV, medelpulsen (visas som Vilopuls) och sömnen; `nil` när måttet saknas.
    public var hrv: Double
    public var heartRate: Double?
    public var sleep: Double?
    /// Andningen ligger mer än 2 SD över ditt normala.
    public var breathingHigh: Bool
    /// Nätter i HRV:s baslinje.
    public var baselineNights: Int

    public init(day: Int, score: Double, hrv: Double, heartRate: Double?, sleep: Double?, breathingHigh: Bool,
                baselineNights: Int) {
        self.day = day
        self.score = score
        self.hrv = hrv
        self.heartRate = heartRate
        self.sleep = sleep
        self.breathingHigh = breathingHigh
        self.baselineNights = baselineNights
    }
}

/// METOD M57 · BESLUT B72
/// Återhämtningen som poäng (PLAN.md H3): autonomt = 0,75 · z(ln HRV) − 0,25 · z(medelpulsen under sömnen), poäng =
/// 64 + 18 · autonomt − 0,3 · (100 − min(100, sovtid / nattens behov · 100)), klippt till 0–100. Spegel:
/// `tools/aterhamtning.py` (`baslinje`, `poang`, `dagar`), med samma påhittade fall i båda proven.
public enum Recovery {
    /// METOD M57. Baslinjen ur värdena: sd² = (k · σ0² + (n − 1) · s²) / (k + n − 1), med k = 7 nätter. Med en natt
    /// är SD:n priorns.
    public static func baseline(_ values: [Double], priorSD: Double) -> RecoveryBaseline {
        let n = values.count
        guard n > 0 else { return RecoveryBaseline(n: 0, mean: nil, sd: nil) }
        let mu = values.reduce(0, +) / Double(n)
        let ss = values.reduce(0) { (s: Double, v: Double) -> Double in s + (v - mu) * (v - mu) }
        let k = RecoveryRules.priorNights
        let nämnare = k + Double(n) - 1
        guard nämnare > 0 else { return RecoveryBaseline(n: n, mean: mu, sd: nil) }
        let sd = ((k * priorSD * priorSD + ss) / nämnare).squareRoot()
        return RecoveryBaseline(n: n, mean: mu, sd: sd > 0 ? sd : nil)
    }

    /// METOD M57. (värde − medel) / SD; `nil` när något saknas.
    public static func z(_ v: Double?, _ b: RecoveryBaseline) -> Double? {
        guard let v = v, let m = b.mean, let s = b.sd else { return nil }
        return (v - m) / s
    }

    /// METOD M57 · BESLUT B72. Poängen ur z-talen och sömnen. Utan medelpuls bär HRV hela den autonoma delen; utan
    /// HRV finns ingen poäng (HRV är huvudvägen, BESLUT B11); utan sömn drar sömnen inget.
    public static func score(day: Int = 0, zHRV: Double?, zHeartRate: Double?, sleepShare: Double?,
                             zBreathing: Double? = nil, baselineNights: Int = 0) -> RecoveryScore? {
        guard let zh = zHRV else { return nil }
        let a = zHeartRate == nil ? 1 : RecoveryRules.hrvShare
        let hrv = RecoveryRules.scale * a * zh
        let puls: Double? = zHeartRate.map { (zv: Double) -> Double in -RecoveryRules.scale * (1 - a) * zv }
        let sömn: Double? = sleepShare.map { (s: Double) -> Double in
            -RecoveryRules.sleepWeight * (100 - min(100, 100 * s))
        }
        let rå = RecoveryRules.middle + hrv + (puls ?? 0) + (sömn ?? 0)
        let flagga = zBreathing.map { (za: Double) -> Bool in za > RecoveryRules.breathingFlagZ } ?? false
        return RecoveryScore(day: day, score: min(100, max(0, rå)), hrv: hrv, heartRate: puls, sleep: sömn,
                             breathingHigh: flagga, baselineNights: baselineNights)
    }

    /// METOD M57 · BESLUT B65. Poängen natt för natt: varje mått mot de egna nätterna med uppvakningsdag 1–28 dagar
    /// före som har måttet. Utan en natt före med HRV finns ingen poäng, så ringen kommer från natt 2.
    public static func days(_ nights: [RecoveryNight]) -> [Int: RecoveryScore] {
        let sorterade = nights.sorted { $0.day < $1.day }
        var ut: [Int: RecoveryScore] = [:]
        for n in sorterade {
            guard let r = n.rmssd, r > 0 else { continue }
            let före = sorterade.filter { (x: RecoveryNight) -> Bool in
                x.day >= n.day - RecoveryRules.baselineDays && x.day <= n.day - 1
            }
            let lnHRV: [Double] = före.compactMap { (x: RecoveryNight) -> Double? in
                guard let v = x.rmssd, v > 0 else { return nil }
                return log(v)
            }
            let bh = baseline(lnHRV, priorSD: RecoveryRules.priorSDLnHRV)
            guard bh.n > 0 else { continue }
            let bp = baseline(före.compactMap(\.heartRate), priorSD: RecoveryRules.priorSDHeartRate)
            let ba = baseline(före.compactMap(\.breathing), priorSD: RecoveryRules.priorSDBreathing)
            if let s = score(day: n.day, zHRV: z(log(r), bh), zHeartRate: z(n.heartRate, bp), sleepShare: n.sleepShare,
                             zBreathing: z(n.breathing, ba), baselineNights: bh.n) {
                ut[n.day] = s
            }
        }
        return ut
    }

    /// METOD M57 · BESLUT B72. Nätterna ur Idunns nätter (en per uppvakningsdag som vyerna, `Trends.idunPerDay`):
    /// HRV, medelpulsen under sömnen och andningen, och sovtiden mot nattens behov ur sömnbehovet (`SleepNeed.days`).
    public static func nights(_ idun: [Trends.IdunNight], need: [NeedDay]) -> [RecoveryNight] {
        var behov: [Int: Double] = [:]
        for d in need {
            if let s = d.sleptMinutes, d.needMinutes > 0 { behov[d.day] = s / d.needMinutes }
        }
        return Trends.idunPerDay(idun).values.map { (n: Trends.IdunNight) -> RecoveryNight in
            RecoveryNight(day: n.day.daysSince1970, rmssd: n.rmssd, heartRate: n.meanHeartRate,
                          breathing: n.breathsPerMinute, sleepShare: behov[n.day.daysSince1970])
        }.sorted { $0.day < $1.day }
    }

    /// METOD M57. Poängen dag för dag ur Idunns nätter och sömnbehovet.
    public static func days(_ idun: [Trends.IdunNight], need: [NeedDay]) -> [Int: RecoveryScore] {
        days(nights(idun, need: need))
    }
}
