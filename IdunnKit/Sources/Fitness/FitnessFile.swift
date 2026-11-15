import Foundation

/// BESLUT B106 · METOD M64
/// Whoops VO2 max, avskrivet för hand: dagen (dagar sedan 1970-01-01, lokal tid)
/// och talet i ml/kg/min. Facit för avstämningen så länge Whoop räknar.
public struct WhoopFitnessNote: Codable, Equatable, Sendable {
    public var day: Int
    public var value: Double

    public init(day: Int, value: Double) {
        self.day = day
        self.value = value
    }
}

/// BESLUT B106 · METOD M60, M64
/// Det som sparas för VO2 max: profilen och de avskrivna Whoop-talen. En fil på
/// telefonen, med i Exportera (dataregeln).
public struct FitnessStore: Codable, Equatable, Sendable {
    public var profile: FitnessProfile
    public var whoopNotes: [WhoopFitnessNote]
    /// METOD M62. Höjden i cm på steget som steptestet görs på, som den skrevs in senast.
    public var stepHeightCm: Double?

    enum CodingKeys: String, CodingKey {
        case profile
        case whoopNotes
        case stepHeightCm
    }

    public init(profile: FitnessProfile = FitnessProfile(), whoopNotes: [WhoopFitnessNote] = [],
                stepHeightCm: Double? = nil) {
        self.profile = profile
        self.whoopNotes = whoopNotes
        self.stepHeightCm = stepHeightCm
    }

    /// En fil från ett äldre bygge får sakna en nyckel: den blir tom.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decodeIfPresent(FitnessProfile.self, forKey: .profile) ?? FitnessProfile()
        whoopNotes = try c.decodeIfPresent([WhoopFitnessNote].self, forKey: .whoopNotes) ?? []
        stepHeightCm = try c.decodeIfPresent(Double.self, forKey: .stepHeightCm)
    }

    /// Lägger till eller byter talet för en dag, och håller listan i dagordning.
    public mutating func setWhoopNote(day: Int, value: Double) {
        whoopNotes.removeAll { $0.day == day }
        whoopNotes.append(WhoopFitnessNote(day: day, value: value))
        whoopNotes.sort { $0.day < $1.day }
    }
}

/// Filen: `kondition.json`, med sorterade nycklar så att samma innehåll ger samma
/// byte.
public enum FitnessFile {
    public static let fileName = "kondition.json"

    public static func encode(_ store: FitnessStore) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(store)
    }

    public static func decode(_ data: Data) throws -> FitnessStore {
        try JSONDecoder().decode(FitnessStore.self, from: data)
    }
}
