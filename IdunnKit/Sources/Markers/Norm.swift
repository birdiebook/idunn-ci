import Foundation

/// BESLUT B104 · METOD M59
/// Var ett värde ligger bland jämnåriga: percentilen i normtabellen, och om värdet ligger utanför tabellens kanter.
public struct NormPosition: Equatable, Sendable {
    public enum Bound: Equatable, Sendable {
        /// Mellan tabellens lägsta och högsta percentil.
        case inside
        /// Under tabellens lägsta percentil: `percentile` är den lägsta, och värdet ligger under den.
        case below
        /// Över tabellens högsta percentil.
        case above
    }

    public var percentile: Double
    public var bound: Bound

    public init(percentile: Double, bound: Bound) {
        self.percentile = percentile
        self.bound = bound
    }
}

/// BESLUT B104 · METOD M59
/// Åldern där tabellens median är lika med värdet ("motsvarar en 38-åring").
public enum EquivalentAge: Equatable, Sendable {
    /// Medianen är lika med värdet vid den här åldern.
    case years(Double)
    /// Värdet är minst lika bra som medianen i den ålder där medianen är som bäst (åldern anges).
    case best(Double)
    /// Värdet är sämre än medianen i tabellens högsta ålder (åldern anges).
    case beyond(Double)
}

/// BESLUT B104 · METOD M59
/// En normtabell ur en publicerad källa: percentiler per kön och ålder för en markör. Tabellen bär sin källa,
/// och en tabell som inte håller ihop (`init?`) blir ingen tabell.
public struct NormTable: Equatable, Sendable {
    /// Percentilernas värden vid en ålder: källans exakta ålder (Dodds: 40 år), eller mitten av ett åldersband.
    public struct Row: Equatable, Sendable {
        public var age: Double
        public var values: [Double]

        public init(age: Double, _ values: [Double]) {
            self.age = age
            self.values = values
        }
    }

    /// Ett åldersband, båda åldrarna inräknade (40–49), med ett värde per percentil.
    public struct Band: Equatable, Sendable {
        public var lowerAge: Int
        public var upperAge: Int
        public var values: [Double]

        public init(_ lowerAge: Int, _ upperAge: Int, _ values: [Double]) {
            self.lowerAge = lowerAge
            self.upperAge = upperAge
            self.values = values
        }

        /// METOD M59. Bandets mitt i år: 40–49 täcker åldrarna 40,0 till 50,0 och har mitten 45.
        public var midAge: Double { Double(lowerAge + upperAge + 1) / 2 }
    }

    /// Hur medianen rör sig med åldern efter sin bästa ålder. `flat` ger ingen motsvarande ålder (vilopulsen).
    public enum AgeTrend: Equatable, Sendable {
        case declines
        case rises
        case flat
    }

    public let marker: MarkerID
    /// Källan i kort form, för visningen och för METOD.
    public let source: String
    /// Percentilerna, stigande (5, 10, 25, 50 …).
    public let percentiles: [Double]
    public let trend: AgeTrend
    /// Åldrarna tabellen gäller för, i år. Utanför dem ges ingen plats.
    public let ages: ClosedRange<Double>
    /// Raderna per kön, yngst först.
    public let rows: [Sex: [Row]]

    /// `nil` när tabellen inte håller ihop: percentilerna stiger inte, en rad har fel antal värden, värdena
    /// sjunker med percentilen, eller raderna står inte i åldersordning.
    public init?(marker: MarkerID, source: String, percentiles: [Double], trend: AgeTrend,
                 ages: ClosedRange<Double>, rows: [Sex: [Row]]) {
        guard !percentiles.isEmpty, NormTable.stiger(percentiles, strikt: true),
              percentiles.allSatisfy({ (p: Double) -> Bool in p > 0 && p < 100 }) else { return nil }
        for (_, list) in rows {
            guard !list.isEmpty,
                  NormTable.stiger(list.map { (r: Row) -> Double in r.age }, strikt: true) else { return nil }
            for r in list {
                guard r.age.isFinite, r.values.count == percentiles.count,
                      r.values.allSatisfy({ (v: Double) -> Bool in v.isFinite }),
                      NormTable.stiger(r.values, strikt: false) else { return nil }
            }
        }
        self.marker = marker
        self.source = source
        self.percentiles = percentiles
        self.trend = trend
        self.ages = ages
        self.rows = rows
    }

    /// En tabell i åldersband (40–49): varje band blir en rad vid bandets mitt, och tabellen gäller från det
    /// yngsta bandets början till det äldstas slut. `nil` också när banden har en lucka eller ligger i fel ordning.
    public init?(marker: MarkerID, source: String, percentiles: [Double], trend: AgeTrend, bands: [Sex: [Band]]) {
        var rader: [Sex: [Row]] = [:]
        var lägst: Int?
        var högst: Int?
        for (kön, list) in bands {
            guard !list.isEmpty else { return nil }
            for (i, b) in list.enumerated() {
                guard b.lowerAge <= b.upperAge else { return nil }
                if i > 0, list[i - 1].upperAge + 1 != b.lowerAge { return nil }
                lägst = min(lägst ?? b.lowerAge, b.lowerAge)
                högst = max(högst ?? b.upperAge, b.upperAge)
            }
            rader[kön] = list.map { (b: Band) -> Row in Row(age: b.midAge, b.values) }
        }
        guard let från = lägst, let till = högst else { return nil }
        self.init(marker: marker, source: source, percentiles: percentiles, trend: trend,
                  ages: Double(från)...Double(till + 1), rows: rader)
    }

    /// METOD M59. Percentilerna som en källa med medel och standardavvikelse görs om till, och normalfördelningens
    /// kvantiler för dem (**standard**: z för 5, 10, 25, 50, 75, 90 och 95 %).
    public static let normalPercentiles: [Double] = [5, 10, 25, 50, 75, 90, 95]
    static let normalQuantiles: [Double] = [-1.644854, -1.281552, -0.674490, 0, 0.674490, 1.281552, 1.644854]

    /// METOD M59. En rad ur medel och standardavvikelse: värdena vid `normalPercentiles` i en normalfördelning.
    /// **Antagande** att måttet är normalfördelat bland jämnåriga; används bara där källan säger det.
    public static func normalRow(age: Double, mean: Double, sd: Double) -> Row {
        Row(age: age, normalQuantiles.map { (z: Double) -> Double in mean + z * sd })
    }

    private static func stiger(_ xs: [Double], strikt: Bool) -> Bool {
        guard xs.count > 1 else { return true }
        for i in 1..<xs.count {
            if strikt ? xs[i] <= xs[i - 1] : xs[i] < xs[i - 1] { return false }
        }
        return true
    }

    /// METOD M59. Percentilernas värden för en ålder: rät linje mellan raderna, och radens egna värden före den
    /// första raden och efter den sista. `nil` utanför tabellens åldrar och för ett kön utan rader.
    /// **Antagande**: källorna ger värden vid vissa åldrar; linjen mellan dem gör att en födelsedag inte ger ett hopp.
    public func values(age: Double, sex: Sex) -> [Double]? {
        guard let list = rows[sex], let first = list.first, let last = list.last, ages.contains(age) else {
            return nil
        }
        if age <= first.age { return first.values }
        if age >= last.age { return last.values }
        for i in 0..<(list.count - 1) {
            let a: Row = list[i]
            let b: Row = list[i + 1]
            guard age >= a.age, age <= b.age else { continue }
            let t: Double = (age - a.age) / (b.age - a.age)
            // (1 − t)·a + t·b ger radens egna tal exakt vid radens ålder.
            return zip(a.values, b.values).map { (p: (Double, Double)) -> Double in (1 - t) * p.0 + t * p.1 }
        }
        return nil
    }

    /// METOD M59. Värdets percentil bland jämnåriga: rät linje mellan tabellens percentiler. Utanför kanterna ges
    /// kantens percentil och `below` eller `above`, så att visningen säger "under 5" i stället för ett tal vi inte har.
    public func position(value: Double, age: Double, sex: Sex) -> NormPosition? {
        guard value.isFinite, let vs = values(age: age, sex: sex) else { return nil }
        let n: Int = vs.count
        if value < vs[0] { return NormPosition(percentile: percentiles[0], bound: .below) }
        if value > vs[n - 1] { return NormPosition(percentile: percentiles[n - 1], bound: .above) }
        if n == 1 { return NormPosition(percentile: percentiles[0], bound: .inside) }
        for i in 0..<(n - 1) where value >= vs[i] && value <= vs[i + 1] {
            let bredd: Double = vs[i + 1] - vs[i]
            // Två percentiler med samma värde: mitten av dem.
            let t: Double = bredd > 0 ? (value - vs[i]) / bredd : 0.5
            return NormPosition(percentile: percentiles[i] + t * (percentiles[i + 1] - percentiles[i]), bound: .inside)
        }
        return nil
    }

    /// METOD M59. Åldern där medianen är lika med värdet. Räknas bara från medianens bästa ålder och uppåt, där den
    /// ska röra sig åt ett håll: greppstyrkan stiger till trettioårsåldern och sjunker sedan, och ett värde ska inte
    /// kunna svara mot en tolvåring. `nil` när tabellen saknar medianen, trenden är `flat`, könet saknas, eller
    /// medianen inte rör sig åt ett håll efter sin bästa ålder.
    public func equivalentAge(value: Double, sex: Sex) -> EquivalentAge? {
        guard value.isFinite, trend != .flat, let mi = percentiles.firstIndex(of: 50),
              let list = rows[sex], list.count >= 2 else { return nil }
        // Vänd tecknet när medianen stiger med åldern, så att "bäst" alltid är störst och kurvan sjunker.
        let tecken: Double = trend == .declines ? 1 : -1
        let v: Double = tecken * value
        let ys: [Double] = list.map { (r: Row) -> Double in tecken * r.values[mi] }
        let åldrar: [Double] = list.map { (r: Row) -> Double in r.age }
        guard let topp = ys.max(), let första = ys.firstIndex(of: topp), let sista = ys.lastIndex(of: topp) else {
            return nil
        }
        for i in sista..<(ys.count - 1) where ys[i + 1] > ys[i] { return nil }
        if v >= topp { return .best(åldrar[första]) }
        if v < ys[ys.count - 1] { return .beyond(åldrar[åldrar.count - 1]) }
        for i in sista..<(ys.count - 1) where ys[i] > ys[i + 1] && v <= ys[i] && v >= ys[i + 1] {
            return .years(åldrar[i] + (ys[i] - v) / (ys[i] - ys[i + 1]) * (åldrar[i + 1] - åldrar[i]))
        }
        return nil
    }
}
