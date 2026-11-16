import Foundation

/// BESLUT B132 · METOD M77
/// Höjdmeter och paus i ett pass ute: stigningen ur spårets höjder, och tiden i rörelse, så att stillastående
/// (ett rödljus, en paus för att knyta skon) inte räknas in i tempot.
public enum PassTerrain {
    /// METOD M77. Höjden ska ha ändrats minst så här många meter från den senaste räknade höjden för att räknas;
    /// mindre svängningar är brus i telefonens höjd.
    public static let climbThresholdMeters = 5.0
    /// METOD M77. Ett steg räknas som stilla under den här farten (m/s).
    public static let stillSpeed = 0.5
    /// METOD M77. Stillheten ska vara minst så här många sekunder i följd för att räknas som en paus.
    public static let minPauseSeconds = 10.0

    /// Stigning och fall i meter.
    public struct Climb: Equatable, Sendable {
        public var ascent: Double
        public var descent: Double

        public init(ascent: Double, descent: Double) {
            self.ascent = ascent
            self.descent = descent
        }
    }

    /// METOD M77. Stigningen och fallet över spåret: höjden följs från en fast punkt, och först när den ändrats
    /// minst `climbThresholdMeters` därifrån räknas ändringen och punkten flyttas. `nil` när färre än två
    /// användbara positioner har höjd.
    public static func climb(_ track: [TrackPoint]) -> Climb? {
        let höjder: [Double] = PassRoute.usable(track).compactMap { $0.altitude }
        guard höjder.count > 1, var fast = höjder.first else { return nil }
        var upp = 0.0
        var ner = 0.0
        for h in höjder.dropFirst() {
            let d = h - fast
            if d >= climbThresholdMeters {
                upp += d
                fast = h
            } else if d <= -climbThresholdMeters {
                ner += -d
                fast = h
            }
        }
        return Climb(ascent: upp, descent: ner)
    }

    /// Tiden och sträckan i rörelse, och pausernas tid.
    public struct Movement: Equatable, Sendable {
        public var movingSeconds: Double
        public var pausedSeconds: Double
        /// Sträckan under tiden i rörelse.
        public var movingMeters: Double

        public init(movingSeconds: Double, pausedSeconds: Double, movingMeters: Double) {
            self.movingSeconds = movingSeconds
            self.pausedSeconds = pausedSeconds
            self.movingMeters = movingMeters
        }

        /// METOD M77. Tempot i rörelse, sekunder per kilometer; `nil` under 100 m (som METOD M65).
        public var pace: Double? { PassRoute.pace(distance: movingMeters, seconds: movingSeconds) }
    }

    /// METOD M77. Stegen (METOD M65) delas i rörelse och paus: en följd av steg under `stillSpeed` som varar minst
    /// `minPauseSeconds` är en paus; kortare stillhet räknas som rörelse. Tiden mellan två positioner som saknas
    /// (ett hopp, eller ingen position alls) räknas varken som rörelse eller paus.
    public static func movement(_ track: [TrackPoint]) -> Movement {
        let steg = PassRoute.steps(track)
        var ut = Movement(movingSeconds: 0, pausedSeconds: 0, movingMeters: 0)
        var stillaSekunder = 0.0
        var stillaMeter = 0.0
        func avslutaStillhet() {
            if stillaSekunder >= minPauseSeconds {
                ut.pausedSeconds += stillaSekunder
            } else {
                ut.movingSeconds += stillaSekunder
                ut.movingMeters += stillaMeter
            }
            stillaSekunder = 0
            stillaMeter = 0
        }
        for s in steg {
            if s.meters / s.seconds < stillSpeed {
                stillaSekunder += s.seconds
                stillaMeter += s.meters
            } else {
                avslutaStillhet()
                ut.movingSeconds += s.seconds
                ut.movingMeters += s.meters
            }
        }
        avslutaStillhet()
        return ut
    }
}
