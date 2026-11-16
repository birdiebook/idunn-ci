import Foundation
import Night

/// BESLUT B131 · METOD M76
/// Nattens HRV i två halvor, per uppvakningsdag, som vyn HRV i natt visar dem: var halva mot sitt eget normalområde,
/// räknat som nattens HRV (METOD M7), och en rad när någon halva ligger under sitt. Räkningen är IdunnKits
/// (`NightHalves`, `MorningCard`); här samlas nätternas värden. Tas in som värden, så att provet kan rita raderna.
struct Natthalvor: Equatable {
    /// Första halvans RMSSD i ms per uppvakningsdag, och andra halvans.
    var första: [WakeDay: Double] = [:]
    var andra: [WakeDay: Double] = [:]

    init(första: [WakeDay: Double] = [:], andra: [WakeDay: Double] = [:]) {
        self.första = första
        self.andra = andra
    }

    /// Ur nätternas sammanfattningar: samma nätter som trenderna räknar (minst `Trends.minValidWindows` fönster), och
    /// av flera samma dag den med flest fönster.
    init(_ summaries: [NightSummary]) {
        var fönster: [WakeDay: Int] = [:]
        for s in summaries where s.validWindows >= Trends.minValidWindows {
            guard let dag = s.wakeDay, let a = s.rmssdEarly, let b = s.rmssdLate else { continue }
            if let finns = fönster[dag], finns >= s.validWindows { continue }
            fönster[dag] = s.validWindows
            första[dag] = a
            andra[dag] = b
        }
    }

    /// Halvans rad för natten `dag`: värdet, normalområdet och axeln, räknade som HRV:s (i ln, METOD M6 och M7).
    func rad(_ halva: [WakeDay: Double], dag: WakeDay) -> MorningCard.Row? {
        MorningCard.nightRow(.hrv, day: dag, idun: [.hrv: halva])
    }

    /// METOD M76. Raden under halvorna, eller `nil` när båda ligger inom eller över sitt normala. Kvällens taggar
    /// (små bokstäver) nämns när natten började lågt.
    func text(dag: WakeDay, taggar: [String] = []) -> String? {
        let a: MorningCard.Row? = rad(första, dag: dag)
        let b: MorningCard.Row? = rad(andra, dag: dag)
        guard let p = NightHalves.pattern(early: a?.value, earlyRange: a?.range, late: b?.value, lateRange: b?.range)
        else { return nil }
        let före: String = taggar.isEmpty ? "" : " Kvällen före: " + taggar.joined(separator: ", ") + "."
        switch p {
        case .lowEarly: return "Låg i början av natten, återhämtad mot morgonen." + före
        case .lowBoth: return "Låg hela natten." + före
        case .lowLate: return "Bra början, lägre mot morgonen."
        }
    }
}
