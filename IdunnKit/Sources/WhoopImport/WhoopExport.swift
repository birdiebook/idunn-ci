import Foundation

/// Ett Whoop-dygn ("cycle") ur `physiological_cycles.csv`: från insomning till
/// nästa insomning, med nattens återhämtning. Det är Whoops facit för de nätter
/// du hade medlemskap — och baslinjen Idunn räknar vidare från.
public struct Cycle: Equatable, Sendable {
    public var start: Date
    /// `nil` för det pågående dygnet; då är även måtten tomma.
    public var end: Date?
    public var utcOffsetSeconds: Int
    public var recoveryScore: Int?
    public var restingHeartRate: Int?
    /// RMSSD i millisekunder, mätt under sömnen.
    public var hrv: Int?
    public var skinTempCelsius: Double?
    public var bloodOxygenPercent: Double?
    public var respiratoryRate: Double?
    public var dayStrain: Double?
    public var sleepOnset: Date?
    public var wakeOnset: Date?
}

/// Ett sömnpass ur `sleeps.csv`. Ett dygn kan ha flera: tupplurar har `isNap`.
public struct Sleep: Equatable, Sendable {
    public var cycleStart: Date
    public var utcOffsetSeconds: Int
    public var onset: Date
    public var wake: Date
    public var isNap: Bool
    public var performancePercent: Int?
    public var respiratoryRate: Double?
    public var asleepMinutes: Int?
    public var inBedMinutes: Int?
    public var lightMinutes: Int?
    public var deepMinutes: Int?
    public var remMinutes: Int?
    public var awakeMinutes: Int?
    public var needMinutes: Int?
    public var debtMinutes: Int?
    public var efficiencyPercent: Int?
    public var consistencyPercent: Int?
}

/// Ett svar i dagboken ur `journal_entries.csv`: en fråga per rad, flera per dygn.
public struct JournalAnswer: Equatable, Sendable {
    public var cycleStart: Date
    public var utcOffsetSeconds: Int
    public var question: String
    public var answeredYes: Bool
    public var notes: String?
}

/// Hela exporten, sorterad med äldst först (filerna har senast först).
public struct WhoopExport: Equatable, Sendable {
    public var cycles: [Cycle]
    public var sleeps: [Sleep]
    public var journal: [JournalAnswer]

    public static let cyclesFile = "physiological_cycles.csv"
    public static let sleepsFile = "sleeps.csv"
    public static let journalFile = "journal_entries.csv"
    public static let knownFiles: Set<String> = [cyclesFile, sleepsFile, journalFile]

    public init(cycles: [Cycle], sleeps: [Sleep], journal: [JournalAnswer]) {
        self.cycles = cycles
        self.sleeps = sleeps
        self.journal = journal
    }

    /// Läser en uppackad export ur en mapp. `nil` om dygnsfilen inte finns
    /// (inget importerat än); sömn och dagbok är valfria.
    public static func load(directory: URL) throws -> WhoopExport? {
        func text(_ name: String) throws -> String? {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try String(contentsOf: url, encoding: .utf8)
        }
        guard let cycles = try text(cyclesFile) else { return nil }
        return WhoopExport(
            cycles: try parseCycles(cycles),
            sleeps: try text(sleepsFile).map(parseSleeps) ?? [],
            journal: try text(journalFile).map(parseJournal) ?? []
        )
    }

    public static func parseCycles(_ text: String) throws -> [Cycle] {
        let t = try CSVTable(file: cyclesFile, text: text)
        let r = try RowReader.Columns(t, [
            "Cycle start time", "Cycle end time", "Cycle timezone",
            "Recovery score %", "Resting heart rate (bpm)", "Heart rate variability (ms)",
            "Skin temp (celsius)", "Blood oxygen %", "Respiratory rate (rpm)", "Day Strain",
            "Sleep onset", "Wake onset",
        ])
        return try t.rows.enumerated().map { (n, row) -> Cycle in
            let x = try RowReader(table: t, columns: r, row: row, line: n + 2)
            return Cycle(
                start: try x.requiredDate("Cycle start time"),
                end: try x.date("Cycle end time"),
                utcOffsetSeconds: x.offset,
                recoveryScore: try x.int("Recovery score %"),
                restingHeartRate: try x.int("Resting heart rate (bpm)"),
                hrv: try x.int("Heart rate variability (ms)"),
                skinTempCelsius: try x.double("Skin temp (celsius)"),
                bloodOxygenPercent: try x.double("Blood oxygen %"),
                respiratoryRate: try x.double("Respiratory rate (rpm)"),
                dayStrain: try x.double("Day Strain"),
                sleepOnset: try x.date("Sleep onset"),
                wakeOnset: try x.date("Wake onset")
            )
        }.sorted { $0.start < $1.start }
    }

    public static func parseSleeps(_ text: String) throws -> [Sleep] {
        let t = try CSVTable(file: sleepsFile, text: text)
        let r = try RowReader.Columns(t, [
            "Cycle start time", "Cycle timezone", "Sleep onset", "Wake onset", "Nap",
            "Sleep performance %", "Respiratory rate (rpm)",
            "Asleep duration (min)", "In bed duration (min)", "Light sleep duration (min)",
            "Deep (SWS) duration (min)", "REM duration (min)", "Awake duration (min)",
            "Sleep need (min)", "Sleep debt (min)", "Sleep efficiency %", "Sleep consistency %",
        ])
        return try t.rows.enumerated().map { (n, row) -> Sleep in
            let x = try RowReader(table: t, columns: r, row: row, line: n + 2)
            return Sleep(
                cycleStart: try x.requiredDate("Cycle start time"),
                utcOffsetSeconds: x.offset,
                onset: try x.requiredDate("Sleep onset"),
                wake: try x.requiredDate("Wake onset"),
                isNap: try x.bool("Nap"),
                performancePercent: try x.int("Sleep performance %"),
                respiratoryRate: try x.double("Respiratory rate (rpm)"),
                asleepMinutes: try x.int("Asleep duration (min)"),
                inBedMinutes: try x.int("In bed duration (min)"),
                lightMinutes: try x.int("Light sleep duration (min)"),
                deepMinutes: try x.int("Deep (SWS) duration (min)"),
                remMinutes: try x.int("REM duration (min)"),
                awakeMinutes: try x.int("Awake duration (min)"),
                needMinutes: try x.int("Sleep need (min)"),
                debtMinutes: try x.int("Sleep debt (min)"),
                efficiencyPercent: try x.int("Sleep efficiency %"),
                consistencyPercent: try x.int("Sleep consistency %")
            )
        }.sorted { $0.onset < $1.onset }
    }

    public static func parseJournal(_ text: String) throws -> [JournalAnswer] {
        let t = try CSVTable(file: journalFile, text: text)
        let r = try RowReader.Columns(t, [
            "Cycle start time", "Cycle timezone", "Question text", "Answered yes", "Notes",
        ])
        return try t.rows.enumerated().map { (n, row) -> JournalAnswer in
            let x = try RowReader(table: t, columns: r, row: row, line: n + 2)
            return JournalAnswer(
                cycleStart: try x.requiredDate("Cycle start time"),
                utcOffsetSeconds: x.offset,
                question: try x.requiredString("Question text"),
                answeredYes: try x.bool("Answered yes"),
                notes: x.string("Notes")
            )
        }.sorted { ($0.cycleStart, $0.question) < ($1.cycleStart, $1.question) }
    }
}

/// Läser en rad. Alla fel pekar ut fil, rad och kolumn men aldrig värdet.
struct RowReader {
    /// Kolumnernas index, uppslagna en gång per fil. Saknas en kolumn felar
    /// importen direkt — även om varje rad råkar ha den tom.
    struct Columns {
        let index: [String: Int]
        init(_ table: CSVTable, _ names: [String]) throws {
            var index: [String: Int] = [:]
            for name in names { index[name] = try table.column(name) }
            self.index = index
        }
    }

    let file: String
    let columns: Columns
    let row: [String]
    let line: Int
    let offset: Int

    init(table: CSVTable, columns: Columns, row: [String], line: Int) throws {
        self.file = table.file
        self.columns = columns
        self.row = row
        self.line = line
        let tz = "Cycle timezone"
        guard let i = columns.index[tz], let offset = WhoopTime.offsetSeconds(row[i]) else {
            throw WhoopImportError.badValue(file: table.file, line: line, column: tz)
        }
        self.offset = offset
    }

    private func raw(_ column: String) -> String {
        // Kolumnen är redan kontrollerad i Columns; ett okänt namn här är ett programfel.
        let i = columns.index[column]!
        return row[i].trimmingCharacters(in: .whitespaces)
    }

    private func bad(_ column: String) -> WhoopImportError {
        .badValue(file: file, line: line, column: column)
    }

    func string(_ column: String) -> String? {
        let s = raw(column)
        return s.isEmpty ? nil : s
    }

    func requiredString(_ column: String) throws -> String {
        guard let s = string(column) else { throw bad(column) }
        return s
    }

    func int(_ column: String) throws -> Int? {
        guard let s = string(column) else { return nil }
        guard let v = Int(s) else { throw bad(column) }
        return v
    }

    func double(_ column: String) throws -> Double? {
        guard let s = string(column) else { return nil }
        guard let v = Double(s), v.isFinite else { throw bad(column) }
        return v
    }

    func bool(_ column: String) throws -> Bool {
        switch raw(column).lowercased() {
        case "true": return true
        case "false": return false
        default: throw bad(column)
        }
    }

    func date(_ column: String) throws -> Date? {
        guard let s = string(column) else { return nil }
        guard let d = WhoopTime.date(s, offsetSeconds: offset) else { throw bad(column) }
        return d
    }

    func requiredDate(_ column: String) throws -> Date {
        guard let d = try date(column) else { throw bad(column) }
        return d
    }
}
