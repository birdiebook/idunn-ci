import Foundation
import Pass

/// BESLUT B106 · METOD M62
/// Steptestet: kliv upp och ner på ett steg i takt med en metronom, fem nivåer om två
/// minuter (15 till 35 steg/min), tills pulsen når 80 % av maxpulsen. Belastningen per
/// nivå kommer ur ACSM:s stegformel, och VO2 max ur linjen genom nivåernas puls och
/// belastning, dragen till maxpulsen. Formen är Chester-testets.
public enum StepTest {
    /// METOD M62. Takterna i steg per minut, en per nivå.
    public static let cadences: [Double] = [15, 20, 25, 30, 35]
    /// METOD M62. Sekunder per nivå.
    public static let levelSeconds: TimeInterval = 120
    /// METOD M62. Testet stoppas efter nivån där pulsen nått den här andelen av maxpulsen.
    public static let stopFraction = 0.80
    /// METOD M62. Säkerhetsgräns: testet stoppas direkt om pulsen når den här andelen.
    public static let abortFraction = 0.90
    /// METOD M62. Nivåns puls är medlet av de sista sekunderna av nivån,
    public static let pulseWindowSeconds: TimeInterval = 30
    /// med minst så här många prov; annars har nivån ingen puls.
    public static let minPulseSamples = 5
    /// METOD M62. Minsta antal nivåer med puls för en skattning.
    public static let minLevels = 3
    /// METOD M62. Osäkerheten, ± en SEE i ml/kg/min.
    public static let uncertainty = 3.9
    /// METOD M62. Metronomens slag per steg: upp, upp, ner, ner.
    public static let beatsPerStep = 4.0
    /// METOD M62. Ett prov äldre än så här (sekunder) räknas inte som pulsen just nu.
    public static let freshSeconds: TimeInterval = 10

    /// Hela testets längd i sekunder.
    public static var totalSeconds: TimeInterval { levelSeconds * Double(cadences.count) }

    /// Nivån (0 är den första) efter `elapsed` sekunder; `nil` före start och efter sista nivån.
    public static func level(at elapsed: TimeInterval) -> Int? {
        guard elapsed >= 0 else { return nil }
        let i = Int(elapsed / levelSeconds)
        return i < cadences.count ? i : nil
    }

    /// Metronomens takt i slag per minut på en nivå.
    public static func metronome(level: Int) -> Double? {
        guard cadences.indices.contains(level) else { return nil }
        return cadences[level] * beatsPerStep
    }

    /// METOD M62. Belastningen i ml/kg/min för en takt (steg/min) och en steghöjd (cm): ACSM:s stegformel.
    public static func oxygenCost(cadence: Double, heightCm: Double) -> Double {
        0.2 * cadence + 1.33 * 1.8 * (heightCm / 100) * cadence + 3.5
    }

    /// En klar nivå: numret, takten, belastningen och pulsen (medlet av de sista 30 sekunderna).
    public struct Level: Equatable, Sendable {
        public var index: Int
        public var cadence: Double
        public var oxygen: Double
        public var pulse: Double?

        public init(index: Int, cadence: Double, oxygen: Double, pulse: Double?) {
            self.index = index
            self.cadence = cadence
            self.oxygen = oxygen
            self.pulse = pulse
        }
    }

    /// METOD M62. Nivåerna som hunnit bli klara fram till `until` (förval: stoppet, annars sista provet).
    public static func levels(_ pass: Pass, until: Date? = nil) -> [Level] {
        guard let höjd = pass.stepHeightCm, höjd > 0 else { return [] }
        let slut: Date = until ?? pass.stop ?? pass.samples.last?.t ?? pass.start
        let aktiv = slut.timeIntervalSince(pass.start)
        var ut: [Level] = []
        for (i, takt) in cadences.enumerated() {
            let nivåSlut = Double(i + 1) * levelSeconds
            // En sekunds marginal: stoppet sätts av en klocka som går en gång per sekund.
            guard aktiv >= nivåSlut - 1 else { break }
            let från = pass.start.addingTimeInterval(nivåSlut - pulseWindowSeconds)
            let till = pass.start.addingTimeInterval(nivåSlut)
            let bpm = pass.samples.filter { $0.t >= från && $0.t < till }.map { Double($0.bpm) }
            let puls: Double? = bpm.count >= minPulseSamples ? bpm.reduce(0, +) / Double(bpm.count) : nil
            ut.append(Level(index: i, cadence: takt, oxygen: oxygenCost(cadence: takt, heightCm: höjd), pulse: puls))
        }
        return ut
    }

    /// Varför testet stoppas.
    public enum Reason: String, Equatable, Sendable {
        /// Nivåns puls nådde 80 % av maxpulsen.
        case reachedLimit
        /// Pulsen just nu nådde 90 % av maxpulsen.
        case tooHigh
        /// Alla fem nivåerna är klara.
        case completed
    }

    /// METOD M62. Ska testet stoppas nu? `nil` betyder fortsätt.
    public static func stopReason(_ pass: Pass, now: Date, maxPulse: Double) -> Reason? {
        guard pass.isStepTest, pass.stop == nil, maxPulse > 0 else { return nil }
        if now.timeIntervalSince(pass.start) >= totalSeconds { return .completed }
        if let s = pass.samples.last, now.timeIntervalSince(s.t) <= freshSeconds,
           Double(s.bpm) >= abortFraction * maxPulse {
            return .tooHigh
        }
        if let sista = levels(pass, until: now).last, let p = sista.pulse, p >= stopFraction * maxPulse {
            return .reachedLimit
        }
        return nil
    }

    /// Skattningen ur ett steptest.
    public struct Result: Equatable, Sendable {
        /// VO2 max i ml/kg/min.
        public var value: Double
        /// ± en SEE.
        public var uncertainty: Double
        /// Nivåerna linjen dragits genom.
        public var levels: [Level]
        public var maxPulse: Double

        public init(value: Double, uncertainty: Double, levels: [Level], maxPulse: Double) {
            self.value = value
            self.uncertainty = uncertainty
            self.levels = levels
            self.maxPulse = maxPulse
        }
    }

    /// METOD M62. VO2 max: linjen puls = a + b × belastning genom nivåerna med puls (minsta kvadrater),
    /// löst för belastningen vid maxpulsen. `nil` med färre än tre nivåer eller en linje som inte stiger.
    public static func estimate(levels: [Level], maxPulse: Double) -> Result? {
        let med: [Level] = levels.filter { $0.pulse != nil }
        guard med.count >= minLevels, maxPulse > 0 else { return nil }
        let n = Double(med.count)
        let xs: [Double] = med.map { $0.oxygen }
        let ys: [Double] = med.map { $0.pulse ?? 0 }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var sxx = 0.0
        var sxy = 0.0
        for i in 0..<med.count {
            sxx += (xs[i] - mx) * (xs[i] - mx)
            sxy += (xs[i] - mx) * (ys[i] - my)
        }
        guard sxx > 0 else { return nil }
        let b = sxy / sxx
        guard b > 0 else { return nil }
        let a = my - b * mx
        return Result(value: (maxPulse - a) / b, uncertainty: uncertainty, levels: med, maxPulse: maxPulse)
    }

    /// Skattningen direkt ur ett pass.
    public static func estimate(_ pass: Pass, maxPulse: Double) -> Result? {
        estimate(levels: levels(pass), maxPulse: maxPulse)
    }
}
