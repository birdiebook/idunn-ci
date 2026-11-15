import Foundation

/// BESLUT B104 · METOD M59
/// En mätning som användaren skriver in: markören, dagen, värdet och hur det mättes ("labbtest", "klocka").
public struct MarkerReading: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var marker: MarkerID
    /// Dagar sedan 1970-01-01, väggklockans dag.
    public var day: Int
    public var value: Double
    public var note: String?

    public init(marker: MarkerID, day: Int, value: Double, note: String? = nil, id: String = UUID().uuidString) {
        self.id = id
        self.marker = marker
        self.day = day
        self.value = value
        self.note = note
    }
}

/// BESLUT B104. Felen säger vad som var fel men aldrig värdet (dataregeln).
public enum MarkerError: Error, Equatable {
    /// Markören finns varken bland de inbyggda eller de egna.
    case unknownMarker
    /// Markören mäts av Idunn och går inte att skriva in.
    case notManual
    /// Värdet är inte ett ändligt tal över noll.
    case invalidValue
    /// En egen markör utan namn.
    case emptyName
    /// Filen är skriven av ett nyare bygge och läses inte, så att inget i den går förlorat.
    case newerVersion
}

/// BESLUT B104 · METOD M59
/// Allt som skrivs in för hand: de egna markörerna och mätningarna. En fil i appens mapp (JSON); hälsodata som
/// nätterna, så den lämnar telefonen bara med Exportera.
public struct MeasurementLog: Codable, Equatable, Sendable {
    public static let currentVersion: Int = 1

    public var version: Int
    /// Egna markörer, i den ordning de lades till.
    public private(set) var custom: [MarkerDefinition]
    /// Mätningarna, i den ordning de skrevs in.
    public private(set) var measurements: [MarkerReading]

    public init() {
        version = MeasurementLog.currentVersion
        custom = []
        measurements = []
    }

    /// Alla markörer: de inbyggda och sedan de egna.
    public var definitions: [MarkerDefinition] { MarkerDefinition.builtIn + custom }

    public func definition(_ id: MarkerID) -> MarkerDefinition? {
        definitions.first { (d: MarkerDefinition) -> Bool in d.id == id }
    }

    /// Lägger till en mätning. Bara markörer som skrivs in för hand, och bara ändliga värden över noll.
    public mutating func add(_ m: MarkerReading) throws {
        guard let d = definition(m.marker) else { throw MarkerError.unknownMarker }
        guard d.source == .manual else { throw MarkerError.notManual }
        guard m.value.isFinite, m.value > 0 else { throw MarkerError.invalidValue }
        measurements.append(m)
    }

    /// Tar bort mätningen med id `id`; ingenting händer om den inte finns.
    public mutating func remove(id: String) {
        measurements.removeAll { (m: MarkerReading) -> Bool in m.id == id }
    }

    /// Lägger till en egen markör (ett lyft, ett test) och ger tillbaka den.
    @discardableResult
    public mutating func addCustom(name: String, unit: String, better: MarkerDefinition.Direction, decimals: Int = 1,
                                   id: String = UUID().uuidString) throws -> MarkerDefinition {
        let rent: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rent.isEmpty else { throw MarkerError.emptyName }
        let d = MarkerDefinition(id: MarkerID(rawValue: "egen-" + id), name: rent,
                                 unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), better: better,
                                 source: .manual, decimals: max(0, decimals))
        custom.append(d)
        return d
    }

    /// Tar bort en egen markör och dess mätningar. En inbyggd markör går inte att ta bort.
    public mutating func removeCustom(_ id: MarkerID) {
        guard custom.contains(where: { (d: MarkerDefinition) -> Bool in d.id == id }) else { return }
        custom.removeAll { (d: MarkerDefinition) -> Bool in d.id == id }
        measurements.removeAll { (m: MarkerReading) -> Bool in m.marker == id }
    }

    /// En markörs mätningar, äldst först. Två mätningar samma dag står i den ordning de skrevs in.
    public func series(_ id: MarkerID) -> [MarkerReading] {
        measurements.enumerated()
            .filter { (p: (offset: Int, element: MarkerReading)) -> Bool in p.element.marker == id }
            .sorted { (a: (offset: Int, element: MarkerReading), b: (offset: Int, element: MarkerReading)) -> Bool in
                a.element.day != b.element.day ? a.element.day < b.element.day : a.offset < b.offset
            }
            .map { (p: (offset: Int, element: MarkerReading)) -> MarkerReading in p.element }
    }

    /// Filens innehåll: JSON med sorterade nycklar, så att samma logg alltid ger samma fil.
    public func encoded() throws -> Data {
        let kodare = JSONEncoder()
        kodare.outputFormatting = [.sortedKeys]
        return try kodare.encode(self)
    }

    /// Läser filen. En fil från ett nyare bygge läses inte (`MarkerError.newerVersion`).
    public static func decode(_ data: Data) throws -> MeasurementLog {
        let logg: MeasurementLog = try JSONDecoder().decode(MeasurementLog.self, from: data)
        guard logg.version <= currentVersion else { throw MarkerError.newerVersion }
        return logg
    }
}
