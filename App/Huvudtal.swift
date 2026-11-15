import Foundation
import Night
import SleepNeed

/// BESLUT B62 · BESLUT B65 · BESLUT B71 · BESLUT B72 · PLAN.md spåret H
/// Huvudtalen: Återhämtning och Sömn, Behov, Ikväll, Sömnpoängens delar, Sömnbehov, Sömnstress, Sömnbrist, Vad som
/// drog och veckoremsan. Ett tal ritas bara när det finns (BESLUT B65, som ändrar B63:s streck): sömnbehovet (H1,
/// METOD M53), sömnpoängen (H2, METOD M56) och återhämtningen (H3, METOD M57) räknas av `SömnbehovModell`;
/// sömnstressen (H4) är `nil` i appen tills etappen landar. Förhandsvisningen (`Prov/IdunnProv.swift`) fyller i
/// påhittade tal för att pröva formen.
struct Huvudtal: Equatable {
    /// Återhämtning och Sömn, 0–100.
    var recovery: Int? = nil
    var sleepScore: Int? = nil
    /// Sömnbehovet i timmar, och läggdags ikväll som minuter efter midnatt (negativt före, Fmt.clock): läggdags för
    /// bästa förväntade sömnpoäng (BESLUT B75, METOD M53).
    var needHours: Double? = nil
    var bedtime: Double? = nil
    /// BESLUT B71 · METOD M56. Sömnpoängens tre delar, 0–100, i ordningen mängd, kontinuitet, regelbundenhet; en del
    /// som saknas (regelbundenheten första natten) är `nil` och ritas inte.
    var scoreParts: [Double?]? = nil
    /// Sömnbehovets delar i timmar: grundbehov, gårdagens pass, sömnbrist.
    var needBase: Double? = nil
    var needStrain: Double? = nil
    var needDebt: Double? = nil
    /// Sömnstressen i timmar per läge, och nattens kurva (0–3 per del av natten, 240 delar).
    var stressHigh: Double? = nil
    var stressMid: Double? = nil
    var stressLow: Double? = nil
    var stressCurve: [Double]? = nil
    /// BESLUT B72 · METOD M57. Vad som drog Återhämtningen: HRV, Vilopuls (medelpulsen under sömnen) och Sömn, i poäng
    /// (minus drar ner); ett mått som saknas är `nil` och ritas inte.
    var drags: [Double?]? = nil
    /// BESLUT B72. Andningen ligger mer än 2 SD över ditt normala: en rad i Vad som drog, utan vikt i poängen.
    var breathingHigh: Bool = false
    /// Sömn mot behov i procent och dess normalområde.
    var sleepVsNeed: Double? = nil
    var sleepVsNeedRange: ClosedRange<Double>? = nil
    /// Dagliga serier för veckorna och Över tid: "recovery", "sleepScore", "debt", "need" och "stress".
    var series: [String: [WakeDay: Double]] = [:]

    /// BESLUT B65 · METOD M53. Grundbehovets SD i timmar (Sömnbehov), och skulden efter natten (hela, Morgon).
    var needBaseSD: Double? = nil
    var debtHours: Double? = nil
    /// BESLUT B65 · METOD M53. Kvällen efter morgonen: behovet, och grundbehovet med SD som det är lärt efter natten.
    var tonightHours: Double? = nil
    /// BESLUT B75. Den förutsagda sovtiden i timmar med läggdags `bedtime`.
    var tonightAsleep: Double? = nil
    var tonightBase: Double? = nil
    var tonightBaseSD: Double? = nil
    /// BESLUT B74. Väcktiden kvällens läggdags räknas från (minuter efter midnatt): `wake` är den som gäller, och
    /// `wakeSet` är den användaren har satt för morgonen efter (`nil` = det vanliga uppvaknandet).
    var wake: Double? = nil
    var wakeSet: Double? = nil
    /// BESLUT B102. Schemat läggdags räknades från: en tid per veckodag och en tid för bara en morgon.
    var schema: WakeSchedule = WakeSchedule()
    /// BESLUT B65. Sömnbehovet per morgon; `för(_:)` lägger dagens tal i fälten ovan.
    var perDay: [WakeDay: Behovsdag] = [:]
    /// BESLUT B71 · BESLUT B72. Sömnpoängen och återhämtningen per morgon; `för(_:)` lägger dagens tal i fälten ovan.
    var perDayScore: [WakeDay: Poängdag] = [:]

    /// BESLUT B71 · BESLUT B72 · METOD M56 · METOD M57. Huvudtalen för en morgon (`SleepScoring.days`,
    /// `Recovery.days`); `nil` där talet inte finns (sömnpoängen utan sovtid, återhämtningen natt 1).
    struct Poängdag: Equatable {
        var sleepScore: Int?
        var scoreParts: [Double?]?
        var recovery: Int?
        var drags: [Double?]?
        var breathingHigh: Bool
    }

    /// BESLUT B65 · METOD M53. Sömnbehovets tal för en morgon, i timmar (`SleepNeed.days`).
    /// BESLUT B80. Kvällens uträkning för morgonen (`för(_:)`), för bladet Upp i morgon.
    var kväll: Kvällsuträkning? = nil

    struct Behovsdag: Equatable {
        /// Nattens behov och dess delar; grundbehovet lärt ur nätterna före natten.
        var need: Double
        var base: Double
        var baseSD: Double
        var pass: Double
        var debtPart: Double
        /// Skulden efter natten.
        var debt: Double
        /// Kvällen efter morgonen: behovet, grundbehovet lärt även ur natten, och läggdags (minuter från midnatt
        /// dagen efter, negativt före).
        var tonight: Double?
        var tonightBase: Double
        var tonightBaseSD: Double
        var bedtime: Double?
        /// BESLUT B74. Väcktiden läggdags räknades från.
        var wake: Double? = nil
        /// BESLUT B102. Schemats tid för morgonen efter (veckodagens eller engångstiden); `nil` utan satt tid.
        var wakeSet: Double? = nil
        /// BESLUT B75. `bedtime` är läggdags för bästa förväntade sömnpoäng; här sovtiden den ger (timmar) och läggdags
        /// för full sömn.
        var tonightAsleep: Double? = nil
        var bedtimeFull: Double? = nil
        /// BESLUT B80. Hela kvällens uträkning, för bladet Upp i morgon.
        var kväll: Kvällsuträkning? = nil
    }

    /// BESLUT B80 · METOD M53. Hur läggdags räknas fram, steg för steg: behovet ur sina delar (timmar), effektiviteten
    /// (0–1), tiden att somna och väcktiden (minuter), läggdags för full sömn och för bästa förväntade sömnpoäng
    /// (minuter efter midnatt, negativt före) och poängen för båda.
    struct Kvällsuträkning: Equatable {
        var grund: Double
        var grundSD: Double
        var skuld: Double
        var pass: Double
        var behov: Double
        var effektivitet: Double
        var somna: Double
        var upp: Double
        var läggdagsFull: Double
        var läggdags: Double
        var poängFull: Double
        var poäng: Double

        /// Läggdags för full sömn med en annan väcktid (bladets hjul), och flytten för regelbundenheten som den sparade
        /// väcktiden gav.
        func tider(upp ny: Double) -> (full: Double, bästa: Double) {
            let full: Double = ny - behov * 60 / effektivitet - somna
            return (full, full + (läggdags - läggdagsFull))
        }
    }

    /// BESLUT B65 · BESLUT B71 · BESLUT B72. Huvudtalen för morgonen `dag`: dagens sömnbehov i Behov, Ikväll och
    /// Sömnbehov, och dagens sömnpoäng och återhämtning. En dag utan tal lämnar fälten som de är (förhandsvisningens
    /// påhittade tal).
    func för(_ dag: WakeDay) -> Huvudtal {
        var h = self
        if let p = perDayScore[dag] {
            h.sleepScore = p.sleepScore
            h.scoreParts = p.scoreParts
            h.recovery = p.recovery
            h.drags = p.drags
            h.breathingHigh = p.breathingHigh
        }
        guard let b = perDay[dag] else { return h }
        h.needHours = b.need
        h.needBase = b.base
        h.needBaseSD = b.baseSD
        h.needStrain = b.pass
        h.needDebt = b.debtPart
        h.debtHours = b.debt
        h.tonightHours = b.tonight
        h.tonightAsleep = b.tonightAsleep
        h.tonightBase = b.tonightBase
        h.tonightBaseSD = b.tonightBaseSD
        h.bedtime = b.bedtime
        h.wake = b.wake
        h.wakeSet = b.wakeSet
        h.kväll = b.kväll
        return h
    }

    /// Appens värde: allt tomt.
    static let tom = Huvudtal()

    /// Serien `namn` för de `antal` dagarna som slutar `slut`, äldst först; en tom dag är `nil`.
    func last(_ namn: String, days antal: Int, ending slut: WakeDay) -> [Double?] {
        let s: [WakeDay: Double] = series[namn] ?? [:]
        return (0..<antal).map { (k: Int) -> Double? in s[slut - (antal - 1 - k)] }
    }
}
