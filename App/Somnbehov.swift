import Foundation
import Combine
import Night
import Pass
import SleepNeed

/// BESLUT B64 · BESLUT B65 · BESLUT B71 · BESLUT B72 · METOD M53 · METOD M56 · METOD M57
/// Huvudtalen i appen (PLAN.md H1–H3): Idunns nätter (sovtiden och sömnperioden, M26, M37, HRV, medelpulsen och
/// andningen) och de sparade passen in, huvudtalen ut (`Huvudtal`: Behov, Ikväll med grundbehov och sömnbrist,
/// Sömnbehov och serierna för Sömn mot behov och Sömnbrist; sömnpoängen med sina tre delar; återhämtningen med Vad som
/// drog och andningen; serierna "sleepScore" och "recovery"). Sömnbehovet och sömnpoängen finns från första natten,
/// återhämtningen från andra. Grundbehovet är 8 h ± 30 min, uppdaterat med grundbehovet ur den importerade exporten på
/// Data när den finns (BESLUT B67). Nätterna är alla som appen har sparat (nätternas resultat, som räknas ur
/// dygnsarkivet, BESLUT B41), så talen finns direkt. Räkningen är IdunnKits (`SleepNeed`, `SleepScoring`, `Recovery`);
/// här kopplas den bara ihop. Schemat för när användaren går upp (BESLUT B74, B102) är den enda inställningen här: en
/// tid per veckodag och en tid för bara en morgon, som läggdags räknas från. Läggdags i Ikväll är den med bäst
/// förväntad sömnpoäng (BESLUT B75), och påminnelsen före läggdags räknas ur samma plan (BESLUT B103).
final class SömnbehovModell: ObservableObject {
    static let shared = SömnbehovModell()

    @Published private(set) var huvudtal: Huvudtal = .tom

    private var nätter: [Trends.IdunNight] = []
    private var pass: [Pass] = []
    /// BESLUT B67. Grundbehovet ur den importerade exporten på Data (sätts av `Store`), eller `nil`.
    private var grundUtifrån: Double?
    /// BESLUT B74 · BESLUT B102. Schemat användaren har satt: en tid per veckodag (minuter efter midnatt, `nil` för det
    /// vanliga uppvaknandet) och en tid för bara en morgon. En inställning, inte hälsodata: UserDefaults.
    private(set) var schema: WakeSchedule = SömnbehovModell.sparatSchema()
    private var prenumeration: AnyCancellable?

    private static let väcktidNyckel = "väcktid"
    private static let schemaNyckel = "väckschema"

    /// Schemat ur UserDefaults. Finns bara den enda väcktiden från B74 gäller den alla dagar, som förut.
    private static func sparatSchema() -> WakeSchedule {
        let d = UserDefaults.standard
        if let data = d.data(forKey: schemaNyckel),
           let s = try? JSONDecoder().decode(WakeSchedule.self, from: data), s.weekdays.count == 7 {
            return s
        }
        guard d.object(forKey: väcktidNyckel) != nil else { return WakeSchedule() }
        let m: Int = d.integer(forKey: väcktidNyckel)
        return (0...719).contains(m) ? WakeSchedule(every: Double(m)) : WakeSchedule()
    }

    private init() {
        // Inte i provet (IdunnProv körs inuti appen): där räknas talen ur påhittad data med `huvudtal(nätter:…)`.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        prenumeration = PassController.shared.$saved.sink { [weak self] (p: [Pass]) in
            self?.pass = p
            self?.räkna()
        }
    }

    /// Nätterna har ändrats (en ny natt, ett nytt bygge).
    func sätt(nätter: [Trends.IdunNight]) {
        self.nätter = nätter
        räkna()
    }

    /// BESLUT B67. Exporten på Data har importerats eller bytts.
    func sätt(grundUtifrån: Double?) {
        self.grundUtifrån = grundUtifrån
        räkna()
    }

    /// BESLUT B102. Schemat är ändrat i bladet Upp i morgon (dagar, en engångstid eller återställt).
    func sätt(schema nytt: WakeSchedule) {
        schema = nytt
        if let data = try? JSONEncoder().encode(nytt) {
            UserDefaults.standard.set(data, forKey: Self.schemaNyckel)
        }
        räkna()
    }

    private func räkna() {
        huvudtal = Self.huvudtal(nätter: nätter, pass: pass, grundUtifrån: grundUtifrån, schema: schema)
        // BESLUT B103. Påminnelsen före läggdags följer planen: en ny natt eller ett ändrat schema flyttar den.
        Läggdagspåminnelse.shared.sätt(påminnelser: Self.påminnelser(nätter: nätter, pass: pass,
                                                                     grundUtifrån: grundUtifrån, schema: schema,
                                                                     nu: Date()))
    }

    /// Passen som sömnbehovet räknar med: bara när maxpulsen går att ta ur dem.
    private static func passdagar(_ pass: [Pass], zon: TimeZone) -> [PassDay] {
        PassLoad.maxPulse(from: pass).map { (m: Double) -> [PassDay] in
            pass.map { (p: Pass) -> PassDay in PassDay(p, maxPulse: m, timeZone: zon) }
        } ?? []
    }

    /// BESLUT B103 · METOD M53. Påminnelserna före läggdags som ligger framför `nu`, ur samma nätter, pass och schema
    /// som huvudtalen (`SleepNeed.reminders`).
    static func påminnelser(nätter idun: [Trends.IdunNight], pass: [Pass], grundUtifrån: Double? = nil,
                            schema: WakeSchedule, nu: Date, zon: TimeZone = .current) -> [BedtimeReminder] {
        SleepNeed.reminders(nights: SleepNeed.nights(idun), passes: passdagar(pass, zon: zon),
                            whoopBase: grundUtifrån, schedule: schema, now: nu, timeZone: zon)
    }

    /// METOD M53 · METOD M56 · METOD M57 · BESLUT B65. Huvudtalen ur Idunns nätter och passen. Värden in och ut, så att
    /// provet räknar samma sak ur påhittad data. Passen ger tillägg när maxpulsen går att ta ur dem (appen frågar inte
    /// efter ålder, så Tanakas reserv används inte). Sömnpoängen och återhämtningen räknas mot nattens behov.
    /// Läggdags räknas från `schema` (BESLUT B102); `väcktid` är en tid för alla dagar (B74) när inget schema ges.
    static func huvudtal(nätter idun: [Trends.IdunNight], pass: [Pass], grundUtifrån: Double? = nil,
                         väcktid: Double? = nil, schema: WakeSchedule? = nil, zon: TimeZone = .current) -> Huvudtal {
        let nätter: [SleepNight] = SleepNeed.nights(idun)
        let passdagar: [PassDay] = Self.passdagar(pass, zon: zon)
        let gällande: WakeSchedule = schema ?? WakeSchedule(every: väcktid)
        var h = Huvudtal()
        h.schema = gällande
        var behov: [WakeDay: Double] = [:]
        var skuld: [WakeDay: Double] = [:]
        let behovsdagar: [NeedDay] = SleepNeed.days(nights: nätter, passes: passdagar, whoopBase: grundUtifrån,
                                                    schedule: gällande)
        // Den satta tiden för morgonen efter den senaste natten; `för(_:)` lägger varje morgons egen.
        h.wakeSet = behovsdagar.last.flatMap { (d: NeedDay) -> Double? in gällande.minute(wakeDay: d.day + 1) }
        for d in behovsdagar {
            let dag = WakeDay(daysSince1970: d.day)
            h.perDay[dag] = Huvudtal.Behovsdag(
                need: d.needMinutes / 60, base: d.base.minutes / 60, baseSD: d.base.sdMinutes / 60,
                pass: d.passMinutes / 60, debtPart: d.debtPartMinutes / 60, debt: d.debtMinutes / 60,
                tonight: d.tonight.map { (t: TonightPlan) -> Double in t.needMinutes / 60 },
                tonightBase: d.base.minutes / 60, tonightBaseSD: d.base.sdMinutes / 60,
                bedtime: d.tonight?.bestBedtimeMinute, wake: d.tonight?.wakeMinute,
                wakeSet: gällande.minute(wakeDay: d.day + 1),
                tonightAsleep: d.tonight.map { (t: TonightPlan) -> Double in t.bestAsleepMinutes / 60 },
                bedtimeFull: d.tonight?.bedtimeMinute,
                kväll: d.tonight.map { (t: TonightPlan) -> Huvudtal.Kvällsuträkning in
                    Huvudtal.Kvällsuträkning(grund: t.baseMinutes / 60, grundSD: d.base.sdMinutes / 60,
                                             skuld: t.debtPartMinutes / 60, pass: t.passMinutes / 60,
                                             behov: t.needMinutes / 60, effektivitet: t.efficiency,
                                             somna: SleepNeedRules.sleepLatencyMinutes, upp: t.wakeMinute,
                                             läggdagsFull: t.bedtimeMinute, läggdags: t.bestBedtimeMinute,
                                             poängFull: t.fullScore, poäng: t.bestScore)
                })
            behov[dag] = d.needMinutes / 60
            skuld[dag] = d.debtMinutes / 60
        }
        if !behov.isEmpty {
            h.series["need"] = behov
            h.series["debt"] = skuld
        }
        poäng(idun: idun, behov: behovsdagar, in: &h)
        return h
    }

    /// METOD M56 · METOD M57 · BESLUT B71 · BESLUT B72. Sömnpoängen (tre delar) och återhämtningen (Vad som drog: HRV,
    /// Vilopuls och Sömn, och andningen över ditt normala) per morgon, och deras serier.
    private static func poäng(idun: [Trends.IdunNight], behov: [NeedDay], in h: inout Huvudtal) {
        let sömn: [Int: SleepScore] = SleepScoring.days(idun, need: behov)
        let åter: [Int: RecoveryScore] = Recovery.days(idun, need: behov)
        var sömnserie: [WakeDay: Double] = [:]
        var återserie: [WakeDay: Double] = [:]
        for d in Set(sömn.keys).union(åter.keys) {
            let dag = WakeDay(daysSince1970: d)
            let s: SleepScore? = sömn[d]
            let r: RecoveryScore? = åter[d]
            if let s = s { sömnserie[dag] = s.score }
            if let r = r { återserie[dag] = r.score }
            h.perDayScore[dag] = Huvudtal.Poängdag(
                sleepScore: s.map { (x: SleepScore) -> Int in Int(x.score.rounded()) },
                scoreParts: s.map { (x: SleepScore) -> [Double?] in [x.amount, x.continuity, x.regularity] },
                recovery: r.map { (x: RecoveryScore) -> Int in Int(x.score.rounded()) },
                drags: r.map { (x: RecoveryScore) -> [Double?] in [x.hrv, x.heartRate, x.sleep] },
                breathingHigh: r?.breathingHigh ?? false)
        }
        if !sömnserie.isEmpty { h.series["sleepScore"] = sömnserie }
        if !återserie.isEmpty { h.series["recovery"] = återserie }
    }
}
