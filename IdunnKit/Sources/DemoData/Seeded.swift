// PÅHITTAD data. Inget i DemoData kommer från ett riktigt band eller en
// riktig export — allt räknas fram ur formler och en seedad slumpgenerator,
// så att varje körning ger exakt samma nätter. Lägg ALDRIG in riktiga värden
// här — se CLAUDE.md §Dataregeln.

import Foundation

/// SplitMix64: liten, seedad och likadan på alla plattformar. Delas av
/// testernas generatorer och förhandsvisningens påhittade nätter.
public struct Seeded {
    private var x: UInt64
    public init(_ seed: UInt64) { x = seed }

    public mutating func next() -> UInt64 {
        x = x &+ 0x9E37_79B9_7F4A_7C15
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Likformig i [0, 1).
    public mutating func uniform() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }

    /// Ungefär normalfördelad med medel 0 och spridning 1 (summan av fyra likformiga).
    public mutating func gauss() -> Double {
        let s: Double = uniform() + uniform() + uniform() + uniform()
        return (s - 2) * 3.0.squareRoot()
    }
}
