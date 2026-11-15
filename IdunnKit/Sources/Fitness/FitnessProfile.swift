import Foundation

/// BESLUT B106 · METOD M60
/// Profilen: det skattningarna av VO2 max behöver utöver bandets data. Varje fält
/// är valfritt, och inget fylls med ett standardvärde: en skattning som kräver ett
/// fält som saknas räknas inte.
public struct FitnessProfile: Codable, Equatable, Sendable {
    public enum Sex: String, Codable, CaseIterable, Sendable {
        case man
        case kvinna
    }

    public var birthYear: Int?
    public var sex: Sex?
    public var heightCm: Double?
    public var weightKg: Double?
    /// Midjemåttet i cm (METOD M61).
    public var waistCm: Double?
    /// Den egna maxpulsen, uppmätt eller inskriven; `nil` när den inte är känd.
    public var ownMaxPulse: Int?
    public var habits: TrainingHabits?

    public init(birthYear: Int? = nil, sex: Sex? = nil, heightCm: Double? = nil, weightKg: Double? = nil,
                waistCm: Double? = nil, ownMaxPulse: Int? = nil, habits: TrainingHabits? = nil) {
        self.birthYear = birthYear
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.ownMaxPulse = ownMaxPulse
        self.habits = habits
    }

    /// METOD M60. Åldern är året minus födelseåret (ingen födelsedag sparas).
    public func age(year: Int) -> Int? {
        birthYear.map { year - $0 }
    }

    /// METOD M60. Maxpulsen: den egna om den finns, annars åldersformeln; `nil` utan
    /// båda.
    public func maxPulse(year: Int) -> MaxPulse? {
        if let own = ownMaxPulse, own > 0 {
            return MaxPulse(bpm: Double(own), source: .own)
        }
        guard let a = age(year: year) else { return nil }
        let bpm = FitnessRules.maxPulseIntercept - FitnessRules.maxPulseSlope * Double(a)
        return MaxPulse(bpm: bpm, source: .age)
    }
}

/// METOD M60. Maxpulsen och var den kommer ifrån.
public struct MaxPulse: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// Profilens egna värde.
        case own
        /// Åldersformeln (Nes m.fl. 2013), SEE 10,8 slag/min.
        case age
    }

    public var bpm: Double
    public var source: Source

    public init(bpm: Double, source: Source) {
        self.bpm = bpm
        self.source = source
    }
}

/// BESLUT B106 · METOD M61
/// Träningsvanorna: HUNT:s tre frågor (hur ofta, hur hårt, hur länge). Svarens
/// vikter multipliceras till ett aktivitetsindex 0–45.
public struct TrainingHabits: Codable, Equatable, Sendable {
    /// "Hur ofta tränar du?"
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case never
        case lessThanWeekly
        case weekly
        case twoToThree
        case almostDaily

        /// METOD M61.
        public var weight: Double {
            switch self {
            case .never, .lessThanWeekly: return 0
            case .weekly: return 1
            case .twoToThree: return 2
            case .almostDaily: return 3
            }
        }
    }

    /// "Hur hårt tar du i?"
    public enum Intensity: String, Codable, CaseIterable, Sendable {
        /// Utan att bli svettig eller andfådd.
        case easy
        /// Svettig och andfådd.
        case sweat
        /// Tar ut mig nästan helt.
        case exhaustion

        /// METOD M61.
        public var weight: Double {
            switch self {
            case .easy: return 0
            case .sweat: return 5
            case .exhaustion: return 10
            }
        }
    }

    /// "Hur länge håller du på varje gång?"
    public enum Duration: String, Codable, CaseIterable, Sendable {
        case under15
        case to30
        case to60
        case over60

        /// METOD M61.
        public var weight: Double {
            switch self {
            case .under15, .to30: return 1
            case .to60, .over60: return 1.5
            }
        }
    }

    public var frequency: Frequency
    public var intensity: Intensity
    public var duration: Duration

    public init(frequency: Frequency, intensity: Intensity, duration: Duration) {
        self.frequency = frequency
        self.intensity = intensity
        self.duration = duration
    }

    /// METOD M61. Aktivitetsindexet: vikterna multiplicerade, 0–45.
    public var index: Double {
        frequency.weight * intensity.weight * duration.weight
    }
}
