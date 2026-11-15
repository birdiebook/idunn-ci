import Foundation

/// BESLUT B105 · METOD M59
/// Profilens texter: talen, platsen bland jämnåriga, motsvarande ålder och ändringarna, som färdiga rader. De står
/// här och inte i vyn, så att orden prövas i Actions och appen bara ritar dem. Decimalkomma och månadsnamn skrivs
/// för hand, så att telefonens språk inte spelar in.
public enum MarkerText {

    /// Ett tal med `decimals` decimaler och decimalkomma; minus som "−", och aldrig "−0".
    public static func number(_ v: Double, decimals: Int) -> String {
        let text: String = String(format: "%.\(max(0, decimals))f", abs(v))
        let noll: Bool = (Double(text) ?? 0) == 0
        return (v < 0 && !noll ? "−" : "") + text.replacingOccurrences(of: ".", with: ",")
    }

    /// En ändring med tecken: "+2", "−1,5", och "±0" när den avrundas till noll.
    public static func signed(_ v: Double, decimals: Int) -> String {
        let text: String = number(abs(v), decimals: decimals)
        if (Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0) == 0 { return "±0" }
        return (v < 0 ? "−" : "+") + text
    }

    /// Kortets värde, eller ett streck.
    public static func value(_ card: MarkerCard) -> String {
        card.value.map { (v: Double) -> String in number(v, decimals: card.definition.decimals) } ?? "–"
    }

    /// "Bättre än 62 % av jämnåriga"; utanför tabellens kanter "minst" eller "högst". `nil` utan riktning.
    public static func standing(_ n: NormStanding) -> String? {
        guard let andel = n.betterThan else { return nil }
        let procent: Int = Int(andel.rounded())
        switch n.edge {
        case .inside: return "Bättre än \(procent) % av jämnåriga"
        case .atLeast: return "Bättre än minst \(procent) % av jämnåriga"
        case .atMost: return "Bättre än högst \(procent) % av jämnåriga"
        }
    }

    /// "Som en 38-åring"; i bästa åldern "Som en 30-åring eller bättre"; under den äldsta medianen "Som äldre än 90 år".
    public static func equivalentAge(_ n: NormStanding) -> String? {
        switch n.equivalentAge {
        case .years(let år)?: return "Som en \(Int(år.rounded()))-åring"
        case .best(let år)?: return "Som en \(Int(år.rounded()))-åring eller bättre"
        case .beyond(let år)?: return "Som äldre än \(Int(år.rounded())) år"
        case nil: return nil
        }
    }

    /// Ändringen mot det närmast före: kvartalet före för en nattmarkör, annars förra mätningen.
    public static func change(_ card: MarkerCard) -> String? {
        guard let d = card.change else { return nil }
        let mot: String = card.definition.source == .night ? "kvartalet före" : "förra mätningen"
        return "\(signed(d, decimals: card.definition.decimals)) mot \(mot)"
    }

    /// Ändringen mot samma kvartal ett år tidigare (bara nattmarkörer).
    public static func overYear(_ card: MarkerCard) -> String? {
        guard let d = card.changeOverYear else { return nil }
        return "\(signed(d, decimals: card.definition.decimals)) mot för ett år sedan"
    }

    /// "Bäst 45,0": bara när det finns fler än en mätning och markören har en riktning.
    public static func best(_ card: MarkerCard) -> String? {
        guard card.count > 1, let b = card.best else { return nil }
        return "Bäst \(number(b, decimals: card.definition.decimals))"
    }

    /// Vad kortets värde är: kvartalets nätter, eller mätningens dag.
    public static func basis(_ card: MarkerCard) -> String? {
        guard card.value != nil, let dag = card.asOfDay else { return nil }
        switch card.definition.source {
        case .night: return "Medel av \(card.count) nätter, senaste 90 dagarna"
        case .pass, .manual: return date(day: dag)
        }
    }

    private static let månader: [String] = ["jan", "feb", "mars", "april", "maj", "juni", "juli", "aug", "sep", "okt",
                                            "nov", "dec"]

    /// Dagen (dagar sedan 1970-01-01) som "2 juli 2020".
    public static func date(day: Int) -> String {
        let d = civil(day: day)
        return "\(d.day) \(månader[d.month - 1]) \(d.year)"
    }

    /// Kalenderdagen för dagar sedan 1970-01-01 i den gregorianska kalendern (heltalsräkning, utan Calendar, så att
    /// telefonens zon och kalender inte spelar in).
    public static func civil(day: Int) -> (year: Int, month: Int, day: Int) {
        let z: Int = day + 719_468
        let era: Int = (z >= 0 ? z : z - 146_096) / 146_097
        let doe: Int = z - era * 146_097
        let yoe: Int = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy: Int = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp: Int = (5 * doy + 2) / 153
        let dag: Int = doy - (153 * mp + 2) / 5 + 1
        let månad: Int = mp < 10 ? mp + 3 : mp - 9
        let år: Int = yoe + era * 400 + (månad <= 2 ? 1 : 0)
        return (år, månad, dag)
    }

    /// Dagar sedan 1970-01-01 för en kalenderdag (omvändningen av `civil`).
    public static func day(year: Int, month: Int, day: Int) -> Int {
        let y: Int = month <= 2 ? year - 1 : year
        let era: Int = (y >= 0 ? y : y - 399) / 400
        let yoe: Int = y - era * 400
        let doy: Int = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe: Int = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
