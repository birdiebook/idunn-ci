import Foundation
import Pass

/// BESLUT B114 · METOD M66
/// Pulsen vid samma tempo: det skarpaste måttet på förändring vid löpning och gång. Ur passets jämna bitar (M63)
/// räknas pulsen om till ett fast tempo, samma för alla pass, så att passen går att jämföra över tid. Lägre puls
/// vid samma tempo är bättre form.
public enum SteadyPulse {
    /// METOD M66. En bit räknas när dess fart ligger inom den här andelen från det fasta tempot.
    public static let tolerance = 0.10
    /// METOD M66. Det fasta tempot avrundas till så här många sekunder per kilometer.
    public static let paceStep = 5.0
    /// METOD M66. Ändringen räknas mot punkterna före den senaste, i så här många dagar.
    public static let changeWindowDays = 90

    /// Ett pass jämna bitar (`SpeedFitness.segments`), dagen (dagar sedan 1970-01-01) och vilopulsen bitarna
    /// räknas om med.
    public struct PassSegments: Equatable, Sendable {
        public var day: Int
        public var restingPulse: Double
        public var segments: [SpeedFitness.Segment]

        public init(day: Int, restingPulse: Double, segments: [SpeedFitness.Segment]) {
            self.day = day
            self.restingPulse = restingPulse
            self.segments = segments
        }
    }

    /// Ett pass i serien: dagen, pulsen vid det fasta tempot och antalet bitar bakom den.
    public struct Point: Equatable, Sendable {
        public var day: Int
        public var pulse: Double
        public var segments: Int

        public init(day: Int, pulse: Double, segments: Int) {
            self.day = day
            self.pulse = pulse
            self.segments = segments
        }
    }

    /// Serien: löpning eller gång, det fasta tempot i sekunder per kilometer, och ett värde per pass i dagordning.
    public struct Series: Equatable, Sendable {
        public var running: Bool
        public var paceSeconds: Double
        public var points: [Point]

        public init(running: Bool, paceSeconds: Double, points: [Point]) {
            self.running = running
            self.paceSeconds = paceSeconds
            self.points = points
        }

        /// Det fasta tempot som fart i m/min.
        public var speed: Double { 60_000 / paceSeconds }

        /// Det senaste passets puls vid tempot.
        public var latest: Point? { points.last }

        /// METOD M66. Det senaste passet minus medlet av passen före det, de senaste 90 dagarna; `nil` utan
        /// ett pass före. Under noll är bättre.
        public var change: Double? {
            guard let sist = points.last else { return nil }
            let före = points.dropLast().filter { $0.day > sist.day - SteadyPulse.changeWindowDays }
            guard !före.isEmpty else { return nil }
            return sist.pulse - före.reduce(0) { $0 + $1.pulse } / Double(före.count)
        }
    }

    /// METOD M66. Det fasta tempot: medianen av bitarnas fart, som tempo avrundat till hela fem sekunder per
    /// kilometer. `nil` utan bitar.
    public static func referencePace(_ segments: [SpeedFitness.Segment]) -> Double? {
        guard let fart = FitnessSummary.median(segments.map { $0.speed }), fart > 0 else { return nil }
        return (60_000 / fart / paceStep).rounded() * paceStep
    }

    /// METOD M66. Bitens puls omräknad till farten `speed` (m/min): pulsen över vilopulsen följer farten, som i
    /// M63. `nil` när biten ligger för långt från farten eller pulsen inte ligger över vilopulsen.
    public static func pulse(_ segment: SpeedFitness.Segment, at speed: Double, restingPulse: Double) -> Double? {
        guard speed > 0, segment.speed > 0, segment.pulse > restingPulse else { return nil }
        guard abs(segment.speed - speed) <= tolerance * speed else { return nil }
        return restingPulse + (segment.pulse - restingPulse) * speed / segment.speed
    }

    /// METOD M66. Serien för löpning (`running`) eller gång: det fasta tempot ur alla pass bitar av det slaget, och
    /// per pass medianen av bitarnas omräknade puls. Två pass samma dag ger en punkt var. `nil` utan någon punkt.
    public static func series(_ passes: [PassSegments], running: Bool) -> Series? {
        let alla = passes.flatMap { $0.segments }.filter { $0.running == running }
        guard let tempo = referencePace(alla) else { return nil }
        let fart = 60_000 / tempo
        var punkter: [Point] = []
        for p in passes.sorted(by: { $0.day < $1.day }) {
            let pulser = p.segments.filter { $0.running == running }
                .compactMap { pulse($0, at: fart, restingPulse: p.restingPulse) }
            guard let m = FitnessSummary.median(pulser) else { continue }
            punkter.append(Point(day: p.day, pulse: m, segments: pulser.count))
        }
        guard !punkter.isEmpty else { return nil }
        return Series(running: running, paceSeconds: tempo, points: punkter)
    }

    /// METOD M66. Serien som visas: den av löpning och gång som har flest pass, löpning när de är lika.
    public static func shown(_ passes: [PassSegments]) -> Series? {
        let löpning = series(passes, running: true)
        let gång = series(passes, running: false)
        guard let l = löpning else { return gång }
        guard let g = gång else { return l }
        return g.points.count > l.points.count ? g : l
    }
}
