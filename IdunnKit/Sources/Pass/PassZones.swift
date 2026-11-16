import Foundation

/// BESLUT B124 · METOD M71
/// Tiden per pulszon i ett pass, för översikten medan passet pågår. Zonen för en puls kommer utifrån (appen ger
/// `PassLoad.zone`, METOD M53), så att indelningen står på ett ställe.
public enum PassZones {
    /// METOD M71. Ett prov gäller fram till nästa när nästa kommer inom så här många sekunder; ett längre glapp
    /// räknas inte (samma regel som belastningen, METOD M53).
    public static let sampleGapSeconds: TimeInterval = 5

    /// En zon och tiden i den.
    public struct Share: Equatable, Sendable {
        public var zone: Int
        public var seconds: TimeInterval

        public init(zone: Int, seconds: TimeInterval) {
            self.zone = zone
            self.seconds = seconds
        }
    }

    /// METOD M71. Sekunderna per zon över proven, i zonernas ordning; bara zoner med tid är med. Proven ska stå i
    /// tidsordning (som i passet).
    public static func time(_ samples: [PassSample], classify: (Int) -> Int) -> [Share] {
        guard samples.count > 1 else { return [] }
        var perZon: [Int: TimeInterval] = [:]
        for i in 0..<(samples.count - 1) {
            let dt = samples[i + 1].t.timeIntervalSince(samples[i].t)
            guard dt > 0, dt <= sampleGapSeconds else { continue }
            perZon[classify(samples[i].bpm), default: 0] += dt
        }
        return perZon.keys.sorted().map { (z: Int) -> Share in Share(zone: z, seconds: perZon[z] ?? 0) }
    }

    /// METOD M71. Så gammalt får det senaste provet vara för att räknas som "nu" (samma gräns som vyns "Bandet hörs
    /// inte", METOD M68).
    public static let currentSeconds: TimeInterval = 10

    /// METOD M71. Zonen just nu: zonen för det senaste provet, om det är högst `currentSeconds` gammalt; annars
    /// `nil` (bandet hörs inte).
    public static func current(_ samples: [PassSample], now: Date, classify: (Int) -> Int) -> Int? {
        guard let sist = samples.last, now.timeIntervalSince(sist.t) <= currentSeconds else { return nil }
        return classify(sist.bpm)
    }
}
