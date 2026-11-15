import Foundation

/// BESLUT B104 · METOD M59
/// En markörs namn i koden och i filen. De inbyggda har fasta id; en egen markör får sitt id när den läggs till.
public struct MarkerID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Nattens HRV (RMSSD, METOD M4).
    public static let hrv: MarkerID = "hrv"
    /// Nattens vilopuls (METOD M5).
    public static let restingHeartRate: MarkerID = "vilopuls"
    /// Sömnens regelbundenhet (SRI, METOD M17).
    public static let regularity: MarkerID = "regelbundenhet"
    /// Pulsens återhämtning en minut efter ett pass (METOD M47).
    public static let heartRateRecovery: MarkerID = "pulsaterhamtning"
    /// Maxpulsen ur passen (METOD M53): en uppgift, inget mål.
    public static let maxPulse: MarkerID = "maxpuls"
    /// Syreupptagningen (VO2 max), i appen kallad Kondition (BESLUT B111): räknad av Idunn ur steptest och pass
    /// (METOD M64), eller inskriven från ett test utanför Idunn.
    public static let vo2max: MarkerID = "vo2max"
    /// Greppstyrkan, mätt med en dynamometer.
    public static let gripStrength: MarkerID = "greppstyrka"
}

/// BESLUT B104 · METOD M59
/// En markör i profilen: vad den heter, i vilken enhet, åt vilket håll den är bättre och varifrån värdet kommer.
public struct MarkerDefinition: Codable, Equatable, Sendable, Identifiable {
    /// Åt vilket håll värdet är bättre. `neutral` visas utan omdöme.
    public enum Direction: String, Codable, Sendable {
        case higher
        case lower
        case neutral
    }

    /// Varifrån värdet kommer: Idunns nätter, Idunns pass, eller det användaren skriver in.
    public enum Source: String, Codable, Sendable {
        case night
        case pass
        case manual
    }

    public var id: MarkerID
    public var name: String
    public var unit: String
    public var better: Direction
    public var source: Source
    /// Antal decimaler värdet visas med.
    public var decimals: Int
    /// METOD M6. Nivån räknas i logaritmen (HRV) och visas i enheten.
    public var logarithmic: Bool

    public init(id: MarkerID, name: String, unit: String, better: Direction, source: Source, decimals: Int = 0,
                logarithmic: Bool = false) {
        self.id = id
        self.name = name
        self.unit = unit
        self.better = better
        self.source = source
        self.decimals = decimals
        self.logarithmic = logarithmic
    }

    /// METOD M59. De inbyggda markörerna, i profilens ordning: först det Idunn mäter, sedan det som skrivs in.
    public static let builtIn: [MarkerDefinition] = [
        MarkerDefinition(id: .hrv, name: "HRV", unit: "ms", better: .higher, source: .night, logarithmic: true),
        MarkerDefinition(id: .restingHeartRate, name: "Vilopuls", unit: "slag/min", better: .lower, source: .night),
        MarkerDefinition(id: .regularity, name: "Regelbundenhet", unit: "", better: .higher, source: .night),
        MarkerDefinition(id: .heartRateRecovery, name: "Pulsens återhämtning", unit: "slag", better: .higher,
                         source: .pass),
        MarkerDefinition(id: .maxPulse, name: "Maxpuls", unit: "slag/min", better: .neutral, source: .pass),
        MarkerDefinition(id: .vo2max, name: "Kondition", unit: "ml/kg/min", better: .higher, source: .manual,
                         decimals: 1),
        MarkerDefinition(id: .gripStrength, name: "Greppstyrka", unit: "kg", better: .higher, source: .manual,
                         decimals: 1),
    ]
}
