import Foundation
import Night

/// METOD M56 · BESLUT B71
/// Konstanterna för sömnpoängen (PLAN.md H2). Varje värde har sin rad i METOD M56 med källa och status; källorna står
/// i docs/KALLOR.md.
public enum SleepScoreRules {
    /// METOD M56. Mängden (sovtid i % av nattens behov, H1) som ger 85 och 70: 7 och 6 h av 8 h (Watson 2015,
    /// Hirshkowitz 2015, PSQI). Att dela med 8 h är ett antagande.
    public static let amountGood: Double = 87.5
    public static let amountPoor: Double = 75
    /// METOD M56. Kontinuiteten (sömneffektiviteten, M50) som ger 85 och 70: ≥ 85 % bra, ≤ 74 % inte bra för vuxna
    /// (Ohayon 2017, NSF), samma steg som PSQI.
    public static let efficiencyGood: Double = 85
    public static let efficiencyPoor: Double = 75
    /// METOD M56 · BESLUT B71. Regelbundenheten (nattens SRI, M56) som ger 85 och 70: 81 är medianen i UK Biobank och
    /// 71,6 gränsen till den nedersta femtedelen (Windred 2024). Antagande förankrat i fördelningen.
    public static let regularityGood: Double = 81
    public static let regularityPoor: Double = 71.6
    /// METOD M56. Gränsen för bra ger delpoängen 85 och gränsen för inte bra 70; samma tal är poängens färger
    /// (grönt från 85, gult från 70).
    public static let goodScore: Double = 85
    public static let poorScore: Double = 70
}

/// METOD M56 · BESLUT B71
/// En natts sömnpoäng: medlet av delarna som finns, och delarna på poängens färgskala (0–100).
public struct SleepScore: Equatable, Sendable {
    public var day: Int
    /// Poängen, 0–100.
    public var score: Double
    /// Delpoängen: mängd, kontinuitet och regelbundenhet; `nil` när delen saknas (regelbundenheten första natten).
    public var amount: Double
    public var continuity: Double?
    public var regularity: Double?
    /// Delarnas mått: sovtid i % av behovet (högst 100), effektiviteten i %, nattens SRI.
    public var amountPercent: Double
    public var efficiency: Double?
    public var sri: Double?

    public init(day: Int, score: Double, amount: Double, continuity: Double?, regularity: Double?,
                amountPercent: Double, efficiency: Double?, sri: Double?) {
        self.day = day
        self.score = score
        self.amount = amount
        self.continuity = continuity
        self.regularity = regularity
        self.amountPercent = amountPercent
        self.efficiency = efficiency
        self.sri = sri
    }
}

/// METOD M56 · BESLUT B71
/// Sömnpoängen (PLAN.md H2): mängd mot H1:s behov, kontinuitet och nattens regelbundenhet med lika vikt. Spegel:
/// `tools/somnpoang.py` (`del_poang`, `somnpoang`, `sri_natt`), med samma påhittade fall i båda proven.
public enum SleepScoring {
    /// METOD M56. En del på poängens färgskala: gränsen för bra ger 85 och gränsen för inte bra 70, linjärt
    /// däremellan och utanför, mellan 0 och 100.
    public static func part(_ x: Double, good: Double, poor: Double) -> Double {
        let g = SleepScoreRules.goodScore
        let steg = SleepScoreRules.goodScore - SleepScoreRules.poorScore
        return min(100, max(0, g + steg * (x - good) / (good - poor)))
    }

    /// METOD M56. Mängden: 100 × min(1, sovtid / behov); `nil` utan behov.
    public static func amount(asleepMinutes: Double, needMinutes: Double) -> Double? {
        guard needMinutes > 0, asleepMinutes.isFinite else { return nil }
        return 100 * min(1, max(0, asleepMinutes) / needMinutes)
    }

    /// METOD M56 · BESLUT B71 · BESLUT B65. Poängen för en natt: medlet av delpoängen som finns, med lika vikt.
    /// Mängden krävs (H1:s behov finns från första natten); saknas effektiviteten eller regelbundenheten räknas
    /// medlet av de andra. `efficiency` i procent, `regularity` nattens SRI.
    public static func score(day: Int = 0, asleepMinutes: Double, needMinutes: Double, efficiency: Double?,
                             regularity: Double?) -> SleepScore? {
        guard let m = amount(asleepMinutes: asleepMinutes, needMinutes: needMinutes) else { return nil }
        let a = part(m, good: SleepScoreRules.amountGood, poor: SleepScoreRules.amountPoor)
        let c = efficiency.flatMap { (e: Double) -> Double? in
            e.isFinite ? part(e, good: SleepScoreRules.efficiencyGood, poor: SleepScoreRules.efficiencyPoor) : nil
        }
        let r = regularity.flatMap { (s: Double) -> Double? in
            s.isFinite ? part(s, good: SleepScoreRules.regularityGood, poor: SleepScoreRules.regularityPoor) : nil
        }
        let delar: [Double] = [a] + [c, r].compactMap { $0 }
        let medel = delar.reduce(0, +) / Double(delar.count)
        return SleepScore(day: day, score: medel, amount: a, continuity: c, regularity: r, amountPercent: m,
                          efficiency: c == nil ? nil : efficiency, sri: r == nil ? nil : regularity)
    }

    /// METOD M56 · BESLUT B65. Poängen dag för dag ur Idunns nätter och sömnbehovet (`SleepNeed.days`): natten per
    /// uppvakningsdag är den sömnbehovet räknar med (`SleepNeed.k18PerDay`), mängden dess sovtid mot nattens behov,
    /// kontinuiteten dess effektivitet (M50) och regelbundenheten natten mot de fyra före ur samma nätters
    /// sömnperioder (M33). En natt utan sovtid har ingen poäng.
    public static func days(_ idun: [Trends.IdunNight], need: [NeedDay]) -> [Int: SleepScore] {
        let perDag: [Int: Trends.IdunNight] = SleepNeed.k18PerDay(idun)
        let pass: [Regularity.Episode] = perDag.values.compactMap(\.sleepEpisode)
        let sri: [WakeDay: Double] = Regularity.nightly(pass)
        var ut: [Int: SleepScore] = [:]
        for d in need {
            guard let slept = d.sleptMinutes, let n = perDag[d.day] else { continue }
            let s = score(day: d.day, asleepMinutes: slept, needMinutes: d.needMinutes, efficiency: n.efficiency,
                          regularity: sri[WakeDay(daysSince1970: d.day)])
            if let s = s { ut[d.day] = s }
        }
        return ut
    }
}
