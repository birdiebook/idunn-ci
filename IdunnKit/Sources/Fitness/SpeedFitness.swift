import Foundation
import Pass

/// BESLUT B106 · METOD M63
/// VO2 max ur puls mot fart i ett pass ute. Passet delas i bitar om tre minuter; en bit
/// räknas när farten och pulsen legat jämnt på plan mark och pulsen ligger i området
/// där linjen till maxpulsen håller. Belastningen kommer ur ACSM:s formler för gång och
/// löpning, och VO2 max ur andelen av pulsreserven.
public enum SpeedFitness {
    /// METOD M63. Bitens längd i sekunder,
    public static let segmentSeconds: TimeInterval = 180
    /// och delarna farten jämförs över.
    public static let partSeconds: TimeInterval = 30
    /// METOD M63. Spåret ska täcka minst den här andelen av bitens tid.
    public static let minCoverage = 0.8
    /// METOD M63. Farten är jämn när delarnas variationskoefficient är högst så här stor.
    public static let maxSpeedVariation = 0.10
    /// METOD M63. Pulsen är jämn när sista minuten skiljer högst så här många slag från minuten före.
    public static let maxPulseDrift = 5.0
    /// METOD M63. Minsta antal pulsprov i var och en av bitens två sista minuter.
    public static let minPulseSamples = 10
    /// METOD M63. Pulsen ska ligga mellan 110 slag/min och 85 % av maxpulsen.
    public static let minPulse = 110.0
    public static let maxPulseFraction = 0.85
    /// METOD M63. Lutningen får vara högst 2 %; första versionen räknar bara plan mark.
    public static let maxGrade = 0.02
    /// METOD M63. Gångformeln gäller 50–100 m/min och löpformeln från 134 m/min; däremellan räknas
    /// biten som löpning bara i ett pass av typen kondition.
    public static let walkMin = 50.0
    public static let walkMax = 100.0
    public static let runMin = 134.0
    /// METOD M63. Vila i ml/kg/min (1 MET).
    public static let restOxygen = 3.5
    /// METOD M63. Osäkerheten, ± i ml/kg/min.
    public static let uncertainty = 5.0

    /// METOD M63. Belastningen i ml/kg/min på plan mark för en fart i m/min: ACSM:s formel för löpning
    /// (0,2 × fart + 3,5) eller gång (0,1 × fart + 3,5).
    public static func oxygenCost(speed: Double, running: Bool) -> Double {
        (running ? 0.2 : 0.1) * speed + restOxygen
    }

    /// METOD M63. VO2 max ur en belastning och en puls: 3,5 + (VO2 − 3,5) / andelen av pulsreserven.
    public static func value(oxygen: Double, pulse: Double, maxPulse: Double, restingPulse: Double) -> Double? {
        guard maxPulse > restingPulse, pulse > restingPulse else { return nil }
        let andel = (pulse - restingPulse) / (maxPulse - restingPulse)
        return restOxygen + (oxygen - restOxygen) / andel
    }

    /// En bit som räknas: när den började, farten i m/min, pulsen, om den räknats som löpning,
    /// belastningen och bitens VO2 max.
    public struct Segment: Equatable, Sendable {
        public var start: Date
        public var speed: Double
        public var pulse: Double
        public var running: Bool
        public var oxygen: Double
        public var value: Double

        public init(start: Date, speed: Double, pulse: Double, running: Bool, oxygen: Double, value: Double) {
            self.start = start
            self.speed = speed
            self.pulse = pulse
            self.running = running
            self.oxygen = oxygen
            self.value = value
        }
    }

    /// METOD M63. Bitarna i passet som uppfyller kraven.
    public static func segments(_ pass: Pass, maxPulse: Double, restingPulse: Double) -> [Segment] {
        guard let spår = pass.track else { return [] }
        let slut: Date = pass.stop ?? pass.samples.last?.t ?? pass.start
        let steg = PassRoute.steps(spår)
        let punkter = PassRoute.usable(spår)
        let prov = pass.activeSamples
        var ut: [Segment] = []
        var från = pass.start
        while från.addingTimeInterval(segmentSeconds) <= slut {
            let till = från.addingTimeInterval(segmentSeconds)
            if let s = segment(from: från, to: till, steps: steg, points: punkter, samples: prov, kind: pass.kind,
                               maxPulse: maxPulse, restingPulse: restingPulse) {
                ut.append(s)
            }
            från = till
        }
        return ut
    }

    private static func segment(from: Date, to: Date, steps: [(t: Date, seconds: Double, meters: Double)],
                                points: [TrackPoint], samples: [PassSample], kind: PassKind?,
                                maxPulse: Double, restingPulse: Double) -> Segment? {
        // Farten: sträckan genom tiden över stegen i biten, och jämnheten över delarna.
        let iBiten = steps.filter { $0.t > from && $0.t <= to }
        let sekunder = iBiten.reduce(0) { $0 + $1.seconds }
        let meter = iBiten.reduce(0) { $0 + $1.meters }
        guard sekunder >= minCoverage * segmentSeconds, sekunder > 0 else { return nil }
        let fart = meter / sekunder * 60
        var delar: [Double] = []
        var d = from
        while d < to {
            let dSlut = d.addingTimeInterval(partSeconds)
            let del = iBiten.filter { $0.t > d && $0.t <= dSlut }
            let s = del.reduce(0) { $0 + $1.seconds }
            guard s > 0 else { return nil }
            delar.append(del.reduce(0) { $0 + $1.meters } / s * 60)
            d = dSlut
        }
        let medel = delar.reduce(0, +) / Double(delar.count)
        guard medel > 0 else { return nil }
        let varians = delar.reduce(0) { $0 + ($1 - medel) * ($1 - medel) } / Double(delar.count)
        guard varians.squareRoot() / medel <= maxSpeedVariation else { return nil }

        // Gång eller löpning.
        let löpning: Bool
        if fart >= walkMin, fart <= walkMax {
            löpning = false
        } else if fart >= runMin || (fart > walkMax && kind == .kondition) {
            löpning = true
        } else {
            return nil
        }

        // Lutningen, när höjden finns i bitens första och sista position.
        let iTid = points.filter { $0.t >= from && $0.t <= to }
        if let h0 = iTid.first?.altitude, let h1 = iTid.last?.altitude, meter > 0 {
            guard abs(h1 - h0) / meter <= maxGrade else { return nil }
        }

        // Pulsen: de två sista minuterna, jämn och i området.
        let sista = samples.filter { $0.t > to.addingTimeInterval(-60) && $0.t <= to }.map { Double($0.bpm) }
        let före = samples.filter { $0.t > to.addingTimeInterval(-120) && $0.t <= to.addingTimeInterval(-60) }
            .map { Double($0.bpm) }
        guard sista.count >= minPulseSamples, före.count >= minPulseSamples else { return nil }
        let pulsSista = sista.reduce(0, +) / Double(sista.count)
        let pulsFöre = före.reduce(0, +) / Double(före.count)
        guard abs(pulsSista - pulsFöre) <= maxPulseDrift else { return nil }
        let puls = (pulsSista + pulsFöre) / 2
        guard puls >= minPulse, puls <= maxPulseFraction * maxPulse else { return nil }

        let syre = oxygenCost(speed: fart, running: löpning)
        guard let v = value(oxygen: syre, pulse: puls, maxPulse: maxPulse, restingPulse: restingPulse) else {
            return nil
        }
        return Segment(start: from, speed: fart, pulse: puls, running: löpning, oxygen: syre, value: v)
    }

    /// Skattningen ur ett pass: medianen av bitarnas VO2 max.
    public struct Result: Equatable, Sendable {
        public var value: Double
        public var uncertainty: Double
        public var segments: [Segment]

        public init(value: Double, uncertainty: Double, segments: [Segment]) {
            self.value = value
            self.uncertainty = uncertainty
            self.segments = segments
        }
    }

    /// METOD M63. Passets skattning; `nil` när ingen bit uppfyller kraven.
    public static func estimate(_ pass: Pass, maxPulse: Double, restingPulse: Double) -> Result? {
        let bitar = segments(pass, maxPulse: maxPulse, restingPulse: restingPulse)
        guard let v = FitnessSummary.median(bitar.map { $0.value }) else { return nil }
        return Result(value: v, uncertainty: uncertainty, segments: bitar)
    }
}
