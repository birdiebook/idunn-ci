import Foundation

/// METOD M59. Ett värde en dag (dagar sedan 1970-01-01): en natts mått, eller ett pass.
public struct DayValue: Equatable, Sendable {
    public var day: Int
    public var value: Double

    public init(day: Int, value: Double) {
        self.day = day
        self.value = value
    }
}

/// BESLUT B104 · METOD M59
/// En nattmarkörs nivå: medlet över ett kvartal. Profilen handlar om månader och år, så en natt eller en vecka
/// ska inte synas i den; det är trendvyns sak (METOD M51).
public struct MarkerLevel: Equatable, Sendable {
    public var mean: Double
    /// Antal nätter i fönstret.
    public var count: Int
    /// Fönstrets sista dag.
    public var endDay: Int

    /// METOD M59. Fönstrets längd i dagar, sista dagen inräknad. **Antagande**.
    public static let windowDays: Int = 90
    /// METOD M59. Minsta antal nätter i fönstret för att nivån ska räknas. **Antagande**.
    public static let minValues: Int = 20
    /// METOD M59. Avståndet bakåt till "för ett år sedan".
    public static let yearDays: Int = 365

    /// METOD M59. Medlet av värdena de `windowDays` dagarna som slutar `endDay`; `nil` med färre än `minValues`.
    /// Ett logaritmiskt mått (HRV, METOD M6) får medlet av logaritmerna, tillbaka i enheten.
    public static func level(_ series: [DayValue], endDay: Int, logarithmic: Bool = false) -> MarkerLevel? {
        let första: Int = endDay - windowDays + 1
        let xs: [Double] = series
            .filter { (p: DayValue) -> Bool in
                p.day >= första && p.day <= endDay && p.value.isFinite && (!logarithmic || p.value > 0)
            }
            .map { (p: DayValue) -> Double in logarithmic ? log(p.value) : p.value }
        guard xs.count >= minValues else { return nil }
        let medel: Double = xs.reduce(0, +) / Double(xs.count)
        return MarkerLevel(mean: logarithmic ? exp(medel) : medel, count: xs.count, endDay: endDay)
    }
}
