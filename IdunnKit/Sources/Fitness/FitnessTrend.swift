import Foundation

/// BESLUT B138 · METOD M80
/// Konditionen över tid på konditionsskärmen: vilka mätningar en period visar, och ändringen över perioden.
public enum FitnessTrend {
    /// METOD M80. Perioderna: en månad, ett halvår, ett år, eller allt.
    public enum Span: String, CaseIterable, Equatable, Sendable {
        case month
        case halfYear
        case year
        case all

        /// Periodens längd i dagar bakåt från i dag; `nil` är allt.
        public var days: Int? {
            switch self {
            case .month: return 30
            case .halfYear: return 182
            case .year: return 365
            case .all: return nil
            }
        }
    }

    /// METOD M64. En ändring under så här många ml/kg/min mellan två mätningar ryms i testets spridning.
    public static let noticeable = 4.0

    /// Ändringen över en period: från den första mätningens dag till den senaste.
    public struct Change: Equatable, Sendable {
        /// Dagen för periodens första mätning (dagar sedan 1970-01-01).
        public var fromDay: Int
        /// Senaste mätningen minus den första, i ml/kg/min.
        public var delta: Double
        /// Om ändringen är större än testets spridning (METOD M64).
        public var isNoticeable: Bool

        public init(fromDay: Int, delta: Double, isNoticeable: Bool) {
            self.fromDay = fromDay
            self.delta = delta
            self.isNoticeable = isNoticeable
        }
    }

    /// METOD M80. Periodens mätningar i dagordning: de vars dag ligger högst `days` dagar före `today` och inte
    /// efter den. Mätningar samma dag behåller ordningen de kom i.
    public static func within(_ measurements: [FitnessMeasurement], span: Span, today: Int) -> [FitnessMeasurement] {
        let från: Int = span.days.map { (d: Int) -> Int in today - d } ?? Int.min
        let kvar: [(offset: Int, element: FitnessMeasurement)] = measurements.enumerated().filter {
            (e: (offset: Int, element: FitnessMeasurement)) -> Bool in e.element.day >= från && e.element.day <= today
        }
        return kvar.sorted { (a: (offset: Int, element: FitnessMeasurement), b: (offset: Int, element: FitnessMeasurement)) -> Bool in
            a.element.day != b.element.day ? a.element.day < b.element.day : a.offset < b.offset
        }.map { (e: (offset: Int, element: FitnessMeasurement)) -> FitnessMeasurement in e.element }
    }

    /// METOD M80. Ändringen från periodens första mätning till den senaste; `nil` med färre än två mätningar
    /// eller när alla ligger på samma dag. `measurements` är i dagordning (som ur `within`).
    public static func change(_ measurements: [FitnessMeasurement]) -> Change? {
        guard let första = measurements.first, let sista = measurements.last, sista.day > första.day else { return nil }
        let delta: Double = sista.value - första.value
        return Change(fromDay: första.day, delta: delta, isNoticeable: abs(delta) >= noticeable)
    }
}
