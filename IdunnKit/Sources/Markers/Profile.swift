import Foundation

/// BESLUT B104 · METOD M59
/// Platsen bland jämnåriga för en markör, ur en normtabell.
public struct NormStanding: Equatable, Sendable {
    public enum Edge: Equatable, Sendable {
        case inside
        /// Värdet ligger utanför tabellen på den bra sidan: "bättre än minst 95 %".
        case atLeast
        /// Värdet ligger utanför tabellen på den dåliga sidan: "bättre än högst 5 %".
        case atMost
    }

    /// Källan i kort form (`NormTable.source`).
    public var source: String
    /// Åldern värdet jämfördes vid, i år.
    public var age: Double
    public var position: NormPosition
    /// Andelen jämnåriga med ett sämre värde, i procent; `nil` för en markör utan riktning.
    public var betterThan: Double?
    public var edge: Edge
    public var equivalentAge: EquivalentAge?

    /// Motsvarande ålder minus den egna, i år (negativt är yngre); bara när åldern är ett tal.
    public var ageGap: Double? {
        guard case .years(let år)? = equivalentAge else { return nil }
        return år - age
    }
}

/// BESLUT B104 · METOD M59
/// En markör i profilen, färdig att visa: värdet nu, vad det jämförs med och platsen bland jämnåriga.
public struct MarkerCard: Equatable, Sendable, Identifiable {
    public var definition: MarkerDefinition
    public var id: MarkerID { definition.id }
    /// Nattmarkör: kvartalets nivå. Pass och inskrivet: den senaste mätningen. `nil` utan värde.
    public var value: Double?
    /// Nivåns sista dag, eller mätningens dag.
    public var asOfDay: Int?
    /// Nattmarkör: nätter i kvartalet. Pass och inskrivet: antal mätningar.
    public var count: Int
    /// Nattmarkör: nivån kvartalet före. Pass och inskrivet: mätningen före den senaste.
    public var previous: Double?
    /// Nattmarkör: nivån ett år före. Annars `nil`.
    public var yearAgo: Double?
    /// Pass och inskrivet: det bästa värdet hittills, åt markörens håll. Annars `nil`.
    public var best: Double?
    public var norm: NormStanding?

    /// Värdet mot `previous`, i enheten.
    public var change: Double? {
        guard let v = value, let p = previous else { return nil }
        return v - p
    }

    /// Värdet mot `yearAgo`, i enheten.
    public var changeOverYear: Double? {
        guard let v = value, let y = yearAgo else { return nil }
        return v - y
    }

    /// Om ändringen `delta` är åt det bättre hållet; `nil` utan riktning och när inget ändrats.
    public func improved(_ delta: Double?) -> Bool? {
        guard let d = delta, d != 0 else { return nil }
        switch definition.better {
        case .higher: return d > 0
        case .lower: return d < 0
        case .neutral: return nil
        }
    }
}

/// BESLUT B104 · METOD M59
/// Profilen: en rad per markör, ur Idunns nätter och pass, det inskrivna och normtabellerna. Värden in och ut, så
/// att appen och provet räknar samma sak.
public enum MarkerProfile {

    /// METOD M59. Korten i profilens ordning (de inbyggda, sedan de egna). En markör utan värde får ett kort utan
    /// värde, så att vyn kan be om en mätning. `series` bär nätternas och passens värden per markör; `today` är
    /// dagen nivån räknas fram till. Utan `person` räknas ingen plats bland jämnåriga.
    public static func cards(person: Person?, series: [MarkerID: [DayValue]], log: MeasurementLog,
                             norms: [NormTable] = Norms.published, today: Int) -> [MarkerCard] {
        log.definitions.map { (d: MarkerDefinition) -> MarkerCard in
            var kort: MarkerCard
            switch d.source {
            case .night:
                kort = nattkort(d, series[d.id] ?? [], today: today)
            case .pass:
                kort = mätkort(d, (series[d.id] ?? []).filter { (p: DayValue) -> Bool in p.day <= today })
            case .manual:
                // BESLUT B111. Det Idunn själv räknat (`series`, till exempel konditionen ur steptest och pass) och
                // det inskrivna hör till samma markör: båda räknas i dagordning, och samma dag står det inskrivna sist.
                let räknat: [DayValue] = (series[d.id] ?? []).filter { (p: DayValue) -> Bool in p.day <= today }
                kort = mätkort(d, räknat + log.series(d.id).map { (m: MarkerReading) -> DayValue in
                    DayValue(day: m.day, value: m.value)
                })
            }
            if let p = person, let v = kort.value, let dag = kort.asOfDay,
               let tabell = norms.first(where: { (t: NormTable) -> Bool in t.marker == d.id }) {
                kort.norm = standing(value: v, age: p.age(onDay: dag), sex: p.sex, table: tabell, better: d.better)
            }
            return kort
        }
    }

    /// Nattmarkören: nivån för kvartalet som slutar med den senaste natten (högst `today`), kvartalet före och
    /// samma kvartal ett år före.
    static func nattkort(_ d: MarkerDefinition, _ serie: [DayValue], today: Int) -> MarkerCard {
        var kort = MarkerCard(definition: d, value: nil, asOfDay: nil, count: 0, previous: nil, yearAgo: nil,
                              best: nil, norm: nil)
        guard let slut = serie.map(\.day).filter({ (dag: Int) -> Bool in dag <= today }).max(),
              let nu = MarkerLevel.level(serie, endDay: slut, logarithmic: d.logarithmic) else { return kort }
        kort.value = nu.mean
        kort.asOfDay = slut
        kort.count = nu.count
        kort.previous = MarkerLevel.level(serie, endDay: slut - MarkerLevel.windowDays,
                                          logarithmic: d.logarithmic)?.mean
        kort.yearAgo = MarkerLevel.level(serie, endDay: slut - MarkerLevel.yearDays, logarithmic: d.logarithmic)?.mean
        return kort
    }

    /// Pass och inskrivet: den senaste mätningen, den före och den bästa. `serie` ska vara äldst först för samma
    /// dag; sorteringen på dag är stabil här.
    static func mätkort(_ d: MarkerDefinition, _ serie: [DayValue]) -> MarkerCard {
        let ordnad: [DayValue] = serie.enumerated()
            .sorted { (a: (offset: Int, element: DayValue), b: (offset: Int, element: DayValue)) -> Bool in
                a.element.day != b.element.day ? a.element.day < b.element.day : a.offset < b.offset
            }
            .map { (p: (offset: Int, element: DayValue)) -> DayValue in p.element }
            .filter { (p: DayValue) -> Bool in p.value.isFinite }
        var kort = MarkerCard(definition: d, value: nil, asOfDay: nil, count: ordnad.count, previous: nil,
                              yearAgo: nil, best: nil, norm: nil)
        guard let senaste = ordnad.last else { return kort }
        kort.value = senaste.value
        kort.asOfDay = senaste.day
        if ordnad.count > 1 { kort.previous = ordnad[ordnad.count - 2].value }
        let värden: [Double] = ordnad.map(\.value)
        switch d.better {
        case .higher: kort.best = värden.max()
        case .lower: kort.best = värden.min()
        case .neutral: kort.best = nil
        }
        return kort
    }

    /// METOD M59. Platsen bland jämnåriga: percentilen, andelen med ett sämre värde (vänd för en markör där lägre
    /// är bättre) och motsvarande ålder. `nil` när tabellen inte täcker åldern eller könet.
    public static func standing(value: Double, age: Double, sex: Sex, table: NormTable,
                                better: MarkerDefinition.Direction) -> NormStanding? {
        guard let plats = table.position(value: value, age: age, sex: sex) else { return nil }
        var andel: Double?
        var kant: NormStanding.Edge = .inside
        switch better {
        case .higher:
            andel = plats.percentile
            if plats.bound == .above { kant = .atLeast }
            if plats.bound == .below { kant = .atMost }
        case .lower:
            andel = 100 - plats.percentile
            if plats.bound == .below { kant = .atLeast }
            if plats.bound == .above { kant = .atMost }
        case .neutral:
            andel = nil
        }
        return NormStanding(source: table.source, age: age, position: plats, betterThan: andel, edge: kant,
                            equivalentAge: table.equivalentAge(value: value, sex: sex))
    }
}
