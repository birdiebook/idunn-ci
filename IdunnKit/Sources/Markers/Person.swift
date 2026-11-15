import Foundation

/// BESLUT B104 · METOD M59
/// Könet som normtabellerna delar på. Källorna har två grupper (män och kvinnor), så fler finns inte här.
public enum Sex: String, Codable, CaseIterable, Sendable {
    case male
    case female
}

/// BESLUT B104 · METOD M59
/// Det normtabellerna behöver veta om den som bär bandet: födelseåret och könet. En inställning i appen, inte en
/// mätning. Födelsedagen frågas inte efter: tabellerna är i tioårsband, så året räcker.
public struct Person: Codable, Equatable, Sendable {
    public var birthYear: Int
    public var sex: Sex

    public init(birthYear: Int, sex: Sex) {
        self.birthYear = birthYear
        self.sex = sex
    }

    /// METOD M59. Kalenderårets medellängd i dagar (gregorianska kalendern).
    static let daysPerYear: Double = 365.2425

    /// METOD M59. Mitten av året `year` som dagar sedan 1970-01-01. **Antagande**: födelsedagen ligger mitt i året,
    /// så åldern är som mest ett halvår fel.
    static func midYearDay(_ year: Int) -> Double {
        (Double(year) - 1970 + 0.5) * daysPerYear
    }

    /// METOD M59. Åldern i år dagen `day` (dagar sedan 1970-01-01), räknad från mitten av födelseåret.
    public func age(onDay day: Int) -> Double {
        (Double(day) - Person.midYearDay(birthYear)) / Person.daysPerYear
    }
}
