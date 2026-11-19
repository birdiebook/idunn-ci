import Foundation
import Combine
import UIKit
import Coach
import Fitness
import Markers
import Night
import Pass
import SleepNeed

/// BESLUT B127 · METOD M73
/// Coachen i appen (PLAN.md spåret C): när telefonen är kopplad skickar Idunn sammanfattningarna av nätterna, passen,
/// det inskrivna och profilen till användaren egen databas, av sig själv, så att Claude kan läsa dem. Det är det enda
/// appen skickar, och det enda undantaget från att data stannar på telefonen (CLAUDE.md, dataregeln).
///
/// - **Vad:** dokumenten i IdunnKits `Coach`, byggda ur samma värden som vyerna visar. Aldrig slag, pulsprov, spår
///   eller ljud: de har inget fält där.
/// - **När:** en stund efter att något ändrats (en natt räknad, ett pass sparat, en mätning inskriven) och när appen
///   öppnas. Bara det som är nytt eller ändrat skickas (`CoachLedger`). Vyerna ska ha matat modellerna först
///   (`vyernaMatade`): en app som iOS väckt i bakgrunden utan skärm har inga huvudtal, och skulle annars skicka
///   nätterna utan dem. Modellen gör därför ingenting förrän skärmen funnits en gång.
/// - **Vart:** värden i kopplingen som användaren klistrat in, över TLS, genom `CoachSändare`.
/// - **Av:** reglaget på Data stänger av sändningen; "Koppla från" tar bort kopplingen ur nyckelringen.
final class CoachModell: ObservableObject {
    static let shared = CoachModell()

    /// Det sektionen på Data ritar.
    struct Läge: Equatable {
        var kopplad: Bool = false
        var på: Bool = true
        var arbetar: Bool = false
        /// Senaste sändningen som kom fram.
        var senast: Date? = nil
        /// Dokument som står som skickade.
        var skickade: Int = 0
        var fel: String? = nil
    }

    @Published private(set) var läge = Läge()

    private var config: CoachConfig?
    private var logg = CoachLedger()
    private var prenumerationer: Set<AnyCancellable> = []
    private var startad: Bool = false
    private var matad: Bool = false
    private var senasteFörsök: Date?
    private var bakgrund: UIBackgroundTaskIdentifier = .invalid

    private static let påNyckel: String = "coach.pa"
    private static let senastNyckel: String = "coach.senast"

    /// Loggen över det skickade, bredvid appens andra filer. Den bär bara fingeravtryck, inga värden.
    private static let loggfil: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("coach-skickat.json")

    private init() {}

    // MARK: Start

    /// Körs en gång, första gången vyerna matat modellerna. Inte vid appens start: iOS kan väcka appen för bandet
    /// innan telefonen låsts upp efter en omstart, och då är filerna låsta. Modellerna den lyssnar på (passen,
    /// profilen, konditionen) ska inte skapas då; de läser sina filer när de skapas. Inte heller i provet
    /// (IdunnProv körs inuti appen): där skickas ingenting.
    private func starta() {
        guard !startad, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        startad = true
        config = CoachNyckelring.läs()
        if let data = try? Data(contentsOf: Self.loggfil), let l = try? JSONDecoder().decode(CoachLedger.self, from: data) {
            logg = l
        }
        let d = UserDefaults.standard
        läge.på = (d.object(forKey: Self.påNyckel) as? Bool) ?? true
        läge.senast = d.object(forKey: Self.senastNyckel) as? Date
        läge.kopplad = config != nil
        läge.skickade = logg.count

        let händelser: [AnyPublisher<Void, Never>] = [
            Recorder.shared.$summaries.map { (_: [NightSummary]) -> Void in () }.eraseToAnyPublisher(),
            PassController.shared.$saved.map { (_: [Pass]) -> Void in () }.eraseToAnyPublisher(),
            SömnbehovModell.shared.$huvudtal.map { (_: Huvudtal) -> Void in () }.eraseToAnyPublisher(),
            ProfilModell.shared.$logg.map { (_: MeasurementLog) -> Void in () }.eraseToAnyPublisher(),
            ProfilModell.shared.$person.map { (_: Person?) -> Void in () }.eraseToAnyPublisher(),
            KonditionModell.shared.$lager.map { (_: FitnessStore) -> Void in () }.eraseToAnyPublisher(),
            KonditionModell.shared.$visat.map { (_: FitnessSummary.Shown?) -> Void in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
                .map { (_: Notification) -> Void in () }.eraseToAnyPublisher(),
        ]
        // METOD M73. En natt räknas om i flera steg; vänta tills det varit lugnt en stund och skicka en gång.
        Publishers.MergeMany(händelser)
            .debounce(for: .seconds(CoachRules.debounceSeconds), scheduler: RunLoop.main)
            .sink { [weak self] (_: Void) -> Void in
                self?.synka(tvinga: false)
                // BESLUT B143. Utvecklingskopian följer med när coachen skickar.
                Task { @MainActor in DygnskopiaModell.shared.synka() }
            }
            .store(in: &prenumerationer)
    }

    /// Vyerna har gett modellerna nätterna (`ContentView`): huvudtalen finns, så nätterna får skickas. Första gången
    /// läses kopplingen och loggen, och modellen börjar lyssna på ändringar.
    func vyernaMatade() {
        starta()
        matad = startad
        // BESLUT B143. Utvecklingskopian startar när vyerna matat modellerna, som coachen.
        Task { @MainActor in
            DygnskopiaModell.shared.starta()
            DygnskopiaModell.shared.synka()
        }
    }

    /// BESLUT B143. Vyerna har matat modellerna: utvecklingskopian får börja.
    var redo: Bool { startad && matad }

    // MARK: Det som skickas

    /// Alla dokument som de ser ut nu, ur samma värden som vyerna visar.
    private func dokument() -> [CoachItem] {
        var ut: [CoachItem] = []
        let nätter: [Trends.IdunNight] = CoachNight.perDay(Recorder.shared.summaries.compactMap(\.idunNight))
        let huvudtal: Huvudtal = SömnbehovModell.shared.huvudtal
        for n in nätter {
            ut.append(CoachItem(CoachNight(n, scores: Self.poäng(huvudtal, dag: n.day))))
        }
        let sparade: [Pass] = PassController.shared.saved
        let maxpuls: Double? = KonditionModell.shared.maxpulsIdag ?? PassLoad.maxPulse(from: sparade)
        for p in sparade where p.isFinished {
            let zon: Int = TimeZone.current.secondsFromGMT(for: p.start)
            ut.append(CoachItem(CoachPass(p, maxPulse: maxpuls, utcOffsetSeconds: zon)))
        }
        for m in CoachMeasurement.all(ProfilModell.shared.logg) {
            ut.append(CoachItem(m))
        }
        let profil = CoachProfile(profile: KonditionModell.shared.lager.profile, person: ProfilModell.shared.person,
                                  maxPulse: KonditionModell.shared.maxpulsIdag,
                                  restingPulse: KonditionModell.shared.vilopuls, shown: KonditionModell.shared.visat)
        if !profil.isEmpty {
            ut.append(CoachItem(profil))
        }
        ut.append(CoachItem(CoachStatus(build: NightSummary.currentBuild)))
        return ut
    }

    /// Huvudtalen för morgonen `dag`, eller `nil` när appen inte har några för den.
    static func poäng(_ h: Huvudtal, dag: WakeDay) -> CoachScores? {
        let p: Huvudtal.Poängdag? = h.perDayScore[dag]
        let b: Huvudtal.Behovsdag? = h.perDay[dag]
        if p == nil && b == nil { return nil }
        let delar: [Double?] = p?.scoreParts ?? []
        let drog: [Double?] = p?.drags ?? []
        func del(_ lista: [Double?], _ i: Int) -> Double? {
            lista.count > i ? lista[i] : nil
        }
        return CoachScores(sleepScore: p?.sleepScore, scoreAmount: del(delar, 0), scoreContinuity: del(delar, 1),
                           scoreRegularity: del(delar, 2), recovery: p?.recovery, dragHrv: del(drog, 0),
                           dragPulse: del(drog, 1), dragSleep: del(drog, 2), breathingHigh: p?.breathingHigh,
                           needHours: b?.need, needBase: b?.base, needPass: b?.pass, needDebt: b?.debtPart,
                           debtHours: b?.debt)
    }

    // MARK: Sändningen

    /// Skickar det som är nytt eller ändrat. `tvinga` är knappen "Skicka nu": den går förbi reglaget och väntetiden
    /// efter ett fel, men inte förbi kopplingen.
    func synka(tvinga: Bool) {
        guard startad, matad, let c = config, !läge.arbetar else { return }
        guard läge.på || tvinga else { return }
        if !tvinga, läge.fel != nil, let f = senasteFörsök, Date().timeIntervalSince(f) < CoachRules.retrySeconds {
            return
        }
        // Filerna är låsta tills telefonen låsts upp en gång efter en omstart: då är listorna tomma och säger inget.
        guard UIApplication.shared.isProtectedDataAvailable else { return }

        // METOD M73. Ett pass eller en mätning som tagits bort i appen tas bort hos coachen, men bara när appen är
        // framme och listan den togs bort ur går att lita på. Nätter tas aldrig bort av sig själva.
        var fårTasBort: Set<CoachKind> = []
        if UIApplication.shared.applicationState == .active {
            if !PassController.shared.saved.isEmpty { fårTasBort.insert(.pass) }
            if !ProfilModell.shared.låst { fårTasBort.insert(.measurement) }
        }
        let saker: [CoachItem] = logg.pending(dokument(), deletable: fårTasBort)
        guard !saker.isEmpty else {
            if tvinga { läge.fel = nil }
            return
        }

        läge.arbetar = true
        senasteFörsök = Date()
        let bitar: [[CoachItem]] = CoachLedger.batches(saker)
        börjaBakgrund()
        Task { @MainActor in
            var fel: String? = nil
            for bit in bitar {
                guard let anrop = CoachCall.ingest(config: c, items: bit) else {
                    fel = "Det gick inte att packa det som skulle skickas."
                    break
                }
                let svar: CoachReply = await CoachSändare.skicka(anrop)
                if case .ok = svar {
                    self.logg.mark(bit)
                    self.sparaLogg()
                } else {
                    fel = Self.text(svar)
                    if svar.isUnknownDevice { self.glömKopplingen() }
                    break
                }
            }
            self.läge.arbetar = false
            self.läge.skickade = self.logg.count
            self.läge.fel = fel
            if fel == nil {
                let nu = Date()
                self.läge.senast = nu
                UserDefaults.standard.set(nu, forKey: Self.senastNyckel)
            }
            self.slutaBakgrund()
        }
    }

    /// Sändningen får gå klart även om appen läggs i bakgrunden under tiden.
    private func börjaBakgrund() {
        guard bakgrund == .invalid else { return }
        bakgrund = UIApplication.shared.beginBackgroundTask(withName: "coach") { [weak self] in
            self?.slutaBakgrund()
        }
    }

    private func slutaBakgrund() {
        guard bakgrund != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bakgrund)
        bakgrund = .invalid
    }

    private func sparaLogg() {
        guard let data = try? JSONEncoder().encode(logg) else { return }
        try? data.write(to: Self.loggfil, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Vad ett svar som inte gick fram betyder, i ord.
    private static func text(_ svar: CoachReply) -> String {
        switch svar {
        case .ok, .copied:
            return ""
        case .refused(let skäl):
            switch skäl {
            case "okand": return "Kopplingen gäller inte längre. Be Claude om en ny och klistra in den."
            case "fel-kod": return "Koden gäller inte längre. Be Claude om en ny koppling."
            case "sparrad": return "För många försök. Vänta en timme och försök igen."
            case "fullt": return "Det är fullt hos coachen. Säg till Claude."
            default: return "Coachen tog inte emot det som skickades."
            }
        case .http(let kod):
            return "Coachen svarade inte som väntat (\(kod)). Idunn försöker igen."
        case .unreachable:
            return "Inget nät just nu. Idunn försöker igen."
        }
    }

    // MARK: Kopplingen

    /// Kopplar telefonen med texten användaren kopierat från Claude. Telefonen skapar sin egen hemlighet, och
    /// engångskoden i texten byts mot rätten att skicka med den.
    func koppla(_ text: String) {
        guard startad, !läge.arbetar else { return }
        guard let länk = CoachLink.parse(text) else {
            läge.fel = "Det där var ingen koppling. Kopiera hela texten från Claude och tryck igen."
            return
        }
        let hemlighet: String = CoachToken.make()
        guard let anrop = CoachCall.pair(link: länk, token: hemlighet, device: UIDevice.current.model) else {
            läge.fel = "Det där var ingen koppling. Kopiera hela texten från Claude och tryck igen."
            return
        }
        läge.arbetar = true
        läge.fel = nil
        Task { @MainActor in
            let svar: CoachReply = await CoachSändare.skicka(anrop)
            self.läge.arbetar = false
            guard case .ok = svar else {
                self.läge.fel = Self.text(svar)
                return
            }
            let ny = CoachConfig(host: länk.host, key: länk.key, token: hemlighet)
            guard CoachNyckelring.spara(ny) else {
                self.läge.fel = "Kopplingen gick inte att spara på telefonen."
                return
            }
            // En ny koppling börjar från början: allt skickas, och det som redan finns där skrivs över med samma.
            self.config = ny
            self.logg = CoachLedger()
            self.sparaLogg()
            self.läge.kopplad = true
            self.läge.skickade = 0
            self.sätt(på: true)
            self.synka(tvinga: true)
            DygnskopiaModell.shared.kopplingenÄndrad()
        }
    }

    /// Reglaget på Data.
    func sätt(på ny: Bool) {
        läge.på = ny
        UserDefaults.standard.set(ny, forKey: Self.påNyckel)
        if ny { synka(tvinga: false) }
    }

    /// "Koppla från": kopplingen tas bort från telefonen. Det som redan skickats ligger kvar hos coachen.
    func kopplaFrån() {
        glömKopplingen()
        läge.fel = nil
        DygnskopiaModell.shared.kopplingenÄndrad()
    }

    private func glömKopplingen() {
        CoachNyckelring.taBort()
        config = nil
        läge.kopplad = false
    }
}
