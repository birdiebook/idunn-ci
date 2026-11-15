import Foundation
import Pass

/// BESLUT B106 · METOD M64
/// En aktiv mätning av VO2 max: dagen (dagar sedan 1970-01-01, lokal tid), talet,
/// osäkerheten och vilken sorts mätning det var.
public struct FitnessMeasurement: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case stepTest
        case speed
    }

    public var day: Int
    public var value: Double
    public var uncertainty: Double
    public var kind: Kind

    public init(day: Int, value: Double, uncertainty: Double, kind: Kind) {
        self.day = day
        self.value = value
        self.uncertainty = uncertainty
        self.kind = kind
    }
}

/// BESLUT B106 · METOD M64
/// Ett tal: vilket som visas, osäkerheten och vad det bygger på.
public enum FitnessSummary {
    /// METOD M64. Aktiva mätningar räknas i så här många dagar.
    public static let windowDays = 42

    /// Medianen; `nil` för en tom lista.
    public static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Det som visas.
    public struct Shown: Equatable, Sendable {
        public enum Basis: Equatable, Sendable {
            /// Aktiva mätningar: antal steptest och pass med fart, och dagen för den senaste.
            case measurements(stepTests: Int, passes: Int, latestDay: Int)
            /// Vila och profil: antal nätter.
            case passive(nights: Int)
        }

        public var value: Double
        public var uncertainty: Double
        public var basis: Basis

        public init(value: Double, uncertainty: Double, basis: Basis) {
            self.value = value
            self.uncertainty = uncertainty
            self.basis = basis
        }
    }

    /// METOD M64. Talet för dagen `day`: medianen av de aktiva mätningarna de senaste 42 dagarna, med
    /// medlet av deras osäkerheter (ingen sammanvägning som krymper osäkerheten). Utan en aktiv mätning
    /// visas den passiva skattningen; utan den också, inget.
    public static func shown(passive: FitnessEstimate?, measurements: [FitnessMeasurement], day: Int) -> Shown? {
        let färska = measurements.filter { $0.day <= day && $0.day > day - windowDays }
        if let v = median(färska.map { $0.value }), let senast = färska.map({ $0.day }).max() {
            let osäkerhet = färska.reduce(0) { $0 + $1.uncertainty } / Double(färska.count)
            let steg = färska.filter { $0.kind == .stepTest }.count
            return Shown(value: v, uncertainty: osäkerhet,
                         basis: .measurements(stepTests: steg, passes: färska.count - steg, latestDay: senast))
        }
        if let p = passive {
            return Shown(value: p.value, uncertainty: p.uncertainty, basis: .passive(nights: p.nights))
        }
        return nil
    }

    /// METOD M62, M63. Mätningen ur ett pass: ett steptest ger sin skattning, ett pass ute sin; annars `nil`.
    /// `restingPulse` behövs bara för passet ute.
    public static func measurement(_ pass: Pass, day: Int, maxPulse: Double, restingPulse: Double?) -> FitnessMeasurement? {
        if pass.isStepTest {
            guard let r = StepTest.estimate(pass, maxPulse: maxPulse) else { return nil }
            return FitnessMeasurement(day: day, value: r.value, uncertainty: r.uncertainty, kind: .stepTest)
        }
        if pass.isOutdoor, let vila = restingPulse {
            guard let r = SpeedFitness.estimate(pass, maxPulse: maxPulse, restingPulse: vila) else { return nil }
            return FitnessMeasurement(day: day, value: r.value, uncertainty: r.uncertainty, kind: .speed)
        }
        return nil
    }
}

/// BESLUT B106 · METOD M64
/// Referensen: uppmätt VO2 max för friska i samma kön och ålder (Loe m.fl. 2013, HUNT 3).
public enum FitnessReference {
    public struct Band: Equatable, Sendable {
        public var fromAge: Int
        public var toAge: Int
        /// Medel och standardavvikelse i ml/kg/min.
        public var mean: Double
        public var sd: Double

        public init(fromAge: Int, toAge: Int, mean: Double, sd: Double) {
            self.fromAge = fromAge
            self.toAge = toAge
            self.mean = mean
            self.sd = sd
        }
    }

    /// METOD M64. Loe m.fl. 2013, tabell 2. Grupperna från 60 år är inte lästa och finns inte här.
    public static let men: [Band] = [
        Band(fromAge: 20, toAge: 29, mean: 54.4, sd: 8.4),
        Band(fromAge: 30, toAge: 39, mean: 49.1, sd: 7.5),
        Band(fromAge: 40, toAge: 49, mean: 47.2, sd: 7.7),
        Band(fromAge: 50, toAge: 59, mean: 42.6, sd: 7.4),
    ]
    public static let women: [Band] = [
        Band(fromAge: 20, toAge: 29, mean: 43.0, sd: 7.7),
        Band(fromAge: 30, toAge: 39, mean: 40.0, sd: 6.8),
        Band(fromAge: 40, toAge: 49, mean: 38.4, sd: 6.9),
        Band(fromAge: 50, toAge: 59, mean: 34.4, sd: 5.7),
    ]

    /// Bandet för ett kön och en ålder; `nil` utanför 20–59 år.
    public static func band(sex: FitnessProfile.Sex, age: Int) -> Band? {
        (sex == .man ? men : women).first { age >= $0.fromAge && age <= $0.toAge }
    }
}
