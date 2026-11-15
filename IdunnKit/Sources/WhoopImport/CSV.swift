import Foundation

/// CSV enligt RFC 4180: kommatecken, citerade fält, dubblade citattecken,
/// radbrytning inuti citat, CRLF eller LF. Whoops dagboksfrågor kan bära
/// kommatecken, så en `split(",")` räcker inte.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }

        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        // Ett citerat tomt fält ("") ska bli en tom kolumn, inte "ingen kolumn".
        var fieldStarted = false

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            fieldStarted = false
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append(c)
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                    fieldStarted = true
                case ",":
                    endField()
                case "\r":
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" { i += 1 }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.append(c)
                    fieldStarted = true
                }
            }
            i += 1
        }
        // Sista raden saknar ofta radbrytning; en avslutande radbrytning ger ingen tom rad.
        if fieldStarted || !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

/// En CSV-fil med rubrikrad, där kolumner hämtas på NAMN. Whoop har bytt
/// ordning på kolumner förr; namnen är det som bär betydelsen.
struct CSVTable {
    let file: String
    let header: [String]
    let rows: [[String]]
    private let index: [String: Int]

    init(file: String, text: String) throws {
        let all = CSV.parse(text)
        guard let header = all.first else { throw WhoopImportError.emptyFile(file: file) }
        self.file = file
        self.header = header.map { $0.trimmingCharacters(in: .whitespaces) }
        self.rows = Array(all.dropFirst())
        var index: [String: Int] = [:]
        for (i, name) in self.header.enumerated() { index[name] = i }
        self.index = index

        for (n, row) in rows.enumerated() where row.count != header.count {
            throw WhoopImportError.badRowLength(file: file, line: n + 2)
        }
    }

    /// BESLUT B7. Kräver att kolumnen finns. Ett tyst `nil` för en omdöpt kolumn skulle
    /// se ut som "ingen data" i stället för "exporten har bytt format".
    func column(_ name: String) throws -> Int {
        guard let i = index[name] else { throw WhoopImportError.missingColumn(file: file, column: name) }
        return i
    }
}

/// BESLUT B3. Felen nämner fil, rad och kolumn — aldrig värdet. Ett felmeddelande ska gå
/// att klistra in någonstans utan att hälsodata följer med.
public enum WhoopImportError: Error, Equatable, CustomStringConvertible {
    case emptyFile(file: String)
    case missingFile(file: String)
    case missingColumn(file: String, column: String)
    case badRowLength(file: String, line: Int)
    case badValue(file: String, line: Int, column: String)

    public var description: String {
        switch self {
        case .emptyFile(let f): return "\(f): filen är tom"
        case .missingFile(let f): return "\(f) saknas"
        case .missingColumn(let f, let c): return "\(f): kolumnen \"\(c)\" saknas"
        case .badRowLength(let f, let l): return "\(f) rad \(l): fel antal kolumner"
        case .badValue(let f, let l, let c): return "\(f) rad \(l): oväntat format i \"\(c)\""
        }
    }
}
