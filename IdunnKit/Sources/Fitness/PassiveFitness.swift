import Foundation

/// BESLUT B106 · METOD M60, M61
/// Konstanterna för maxpulsen och den passiva skattningen av VO2 max.
public enum FitnessRules {
    /// METOD M60. Maxpuls utan egen: 211 − 0,64 × ålder (Nes m.fl. 2013).
    public static let maxPulseIntercept = 211.0
    public static let maxPulseSlope = 0.64
    /// METOD M60. Åldersformelns fel, SEE i slag/min.
    public static let maxPulseSEE = 10.8

    /// METOD M61. Nes formel (Nes m.fl. 2011): koefficienterna och formelns SEE i
    /// ml/kg/min.
    public struct Nes: Equatable, Sendable {
        public var intercept: Double
        public var age: Double
        public var waist: Double
        public var restingPulse: Double
        public var activity: Double
        public var see: Double
    }

    public static let nesMan = Nes(intercept: 100.27, age: -0.296, waist: -0.369, restingPulse: -0.155,
                                   activity: 0.226, see: 5.70)
    public static let nesWoman = Nes(intercept: 74.736, age: -0.247, waist: -0.259, restingPulse: -0.114,
                                     activity: 0.198, see: 5.14)

    /// METOD M61. Vilopulsen är medianen av de senaste nätterna: högst så här många,
    public static let restingNights = 14
    /// inom så här många dagar,
    public static let restingWindowDays = 21
    /// och minst så här många; annars ingen skattning.
    public static let restingMinNights = 7

    /// METOD M61. Uths faktor mellan VO2 max och maxpuls/vilopuls (bara i verktyget).
    public static let ratioFactor = 15.3

    /// Året för en dag räknad från 1970-01-01.
    public static func year(ofDay day: Int) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.component(.year, from: Date(timeIntervalSince1970: Double(day) * 86_400))
    }
}

/// METOD M61. En natts vilopuls (M5): uppvakningsdagen (dagar sedan 1970-01-01 i
/// nattens zon, som `SleepNight.day`) och pulsen i slag/min.
public struct RestingNight: Equatable, Sendable {
    public var day: Int
    public var pulse: Double

    public init(day: Int, pulse: Double) {
        self.day = day
        self.pulse = pulse
    }
}

/// METOD M61. En skattning av VO2 max i ml/kg/min, med osäkerheten som ± en SEE.
public struct FitnessEstimate: Equatable, Sendable {
    public var value: Double
    public var uncertainty: Double
    /// Vilopulsen skattningen räknades på, och antalet nätter bakom den.
    public var restingPulse: Double
    public var nights: Int

    public init(value: Double, uncertainty: Double, restingPulse: Double, nights: Int) {
        self.value = value
        self.uncertainty = uncertainty
        self.restingPulse = restingPulse
        self.nights = nights
    }
}

/// BESLUT B106 · METOD M61
/// VO2 max passivt: Nes formel på nattens vilopuls och profilen. Ger en nivå, inte
/// en mätning.
public enum PassiveFitness {
    /// Det som saknas för att räkna.
    public enum Missing: String, CaseIterable, Sendable {
        case birthYear
        case sex
        case waist
        case habits
        case nights
    }

    public enum Outcome: Equatable, Sendable {
        case estimate(FitnessEstimate)
        case missing([Missing])
    }

    /// METOD M61. Medianen av vilopulsen över de senaste nätterna till och med
    /// `day`: högst 14 nätter inom 21 dagar, minst 7. En natt utan puls räknas inte.
    public static func restingPulse(_ nights: [RestingNight], day: Int) -> (pulse: Double, nights: Int)? {
        let first = day - FitnessRules.restingWindowDays
        let inWindow = nights.filter { $0.day > first && $0.day <= day && $0.pulse > 0 }
            .sorted { $0.day > $1.day }
        let chosen = inWindow.prefix(FitnessRules.restingNights).map { $0.pulse }.sorted()
        let n = chosen.count
        guard n >= FitnessRules.restingMinNights else { return nil }
        let median = n % 2 == 1 ? chosen[n / 2] : (chosen[n / 2 - 1] + chosen[n / 2]) / 2
        return (median, n)
    }

    /// METOD M61. Skattningen för dagen `day`, eller listan över det som saknas.
    public static func estimate(profile: FitnessProfile, nights: [RestingNight], day: Int) -> Outcome {
        let rest = restingPulse(nights, day: day)
        var missing: [Missing] = []
        if profile.birthYear == nil { missing.append(.birthYear) }
        if profile.sex == nil { missing.append(.sex) }
        if profile.waistCm == nil { missing.append(.waist) }
        if profile.habits == nil { missing.append(.habits) }
        if rest == nil { missing.append(.nights) }
        guard let born = profile.birthYear, let sex = profile.sex, let waist = profile.waistCm,
              let habits = profile.habits, let rest = rest else {
            return .missing(missing)
        }
        let k = sex == .man ? FitnessRules.nesMan : FitnessRules.nesWoman
        let age = Double(FitnessRules.year(ofDay: day) - born)
        let value = k.intercept + k.age * age + k.waist * waist + k.restingPulse * rest.pulse
            + k.activity * habits.index
        return .estimate(FitnessEstimate(value: value, uncertainty: k.see, restingPulse: rest.pulse,
                                         nights: rest.nights))
    }

    /// METOD M61. Uths kvot: 15,3 × maxpuls / vilopuls. Bara för avstämningen; den
    /// visas inte i appen.
    public static func pulseRatio(maxPulse: Double, restingPulse: Double) -> Double? {
        guard maxPulse > 0, restingPulse > 0 else { return nil }
        return FitnessRules.ratioFactor * maxPulse / restingPulse
    }
}
