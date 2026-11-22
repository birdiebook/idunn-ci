import Foundation
import UIKit
import Coach

/// BESLUT B143 · METOD M82
/// Utvecklingskopian: när telefonen är kopplad till coachen (B127) laddar appen av sig själv upp varje färdigt dygns
/// arkiv (`dygn-<datum>.arkiv`, METOD M34) till användaren egen databas, nyast först, ett dygn per anrop, och ett dygn
/// på nytt bara när dess arkiv ändrats. Kopplingen och sändaren är coachens: nätet nås bara genom `CoachSändare`.
///
/// - **När:** när coachen skickar (`CoachModell` anropar `synka()` efter en ändring och när appen öppnas), bara
///   när telefonen är kopplad och reglaget Utvecklingskopia är på.
/// - **Vad:** bara arkiven, som byte exakt som de ligger på telefonen. Aldrig ljud, spår eller dagbok.
/// - **Fel:** ett misslyckat anrop stoppar körningen; nästa försök tidigast efter `CoachRules.retrySeconds`.
///   `for-gammal` (hinken full, dygnet äldst) räknas som klart. `okand` kopplar från, som hos coachen.
@MainActor
final class DygnskopiaModell: ObservableObject {
    static let shared = DygnskopiaModell()

    /// Det sektionen på Data ritar.
    struct Läge: Equatable {
        var kopplad: Bool = false
        var på: Bool = true
        var arbetar: Bool = false
        /// Dygn i hinken, megabyte i den och taket enligt det senaste svaret.
        var dygn: Int? = nil
        var megabyte: Double? = nil
        var tak: Double? = nil
        /// När ett dygn senast kom fram.
        var senast: Date? = nil
        var fel: String? = nil
    }

    @Published private(set) var läge = Läge()

    /// Det som sparas i `dygnskopia.json`: loggen över uppladdat, det senaste läget och när det senast lyckades.
    private struct Fil: Codable {
        var logg = DayCopyLedger()
        var dygn: Int?
        var megabyte: Double?
        var tak: Double?
        var senast: Date?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            logg = try c.decodeIfPresent(DayCopyLedger.self, forKey: .logg) ?? DayCopyLedger()
            dygn = try c.decodeIfPresent(Int.self, forKey: .dygn)
            megabyte = try c.decodeIfPresent(Double.self, forKey: .megabyte)
            tak = try c.decodeIfPresent(Double.self, forKey: .tak)
            senast = try c.decodeIfPresent(Date.self, forKey: .senast)
        }
    }

    /// Arkivets storlek och ändringstid vid senaste läsningen, med fingeravtrycket: ett arkiv som inte ändrats läses
    /// inte om vid nästa körning.
    struct Spår: Sendable {
        var storlek: Int
        var ändrad: Date
        var avtryck: String
    }

    private var fil = Fil()
    private var spår: [String: Spår] = [:]
    private var startad = false
    private var senasteFörsök: Date?
    private var bakgrund: UIBackgroundTaskIdentifier = .invalid

    private static let påNyckel: String = "dygnskopia.pa"

    private static let filen: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("dygnskopia.json")

    private init() {}

    /// Körs en gång, när vyerna matat modellerna (`CoachModell.vyernaMatade`): inte före, för filerna kan vara låsta.
    func starta() {
        guard !startad, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        startad = true
        if let data = try? Data(contentsOf: Self.filen), let f = try? JSONDecoder().decode(Fil.self, from: data) {
            fil = f
        }
        läge.på = (UserDefaults.standard.object(forKey: Self.påNyckel) as? Bool) ?? true
        läge.dygn = fil.dygn
        läge.megabyte = fil.megabyte
        läge.tak = fil.tak
        läge.senast = fil.senast
        läge.kopplad = CoachNyckelring.läs() != nil
    }

    /// Reglaget på Data.
    func sätt(på ny: Bool) {
        läge.på = ny
        UserDefaults.standard.set(ny, forKey: Self.påNyckel)
        if ny { synka() }
    }

    /// Kopplingen har ändrats (ny eller borttagen): läget följer, och en ny koppling får börja ladda upp.
    func kopplingenÄndrad() {
        guard startad else { return }
        läge.kopplad = CoachNyckelring.läs() != nil
        if läge.kopplad { synka() }
    }

    // MARK: Uppladdningen

    /// Laddar upp de dygn som är nya eller ändrade, nyast först. En körning i taget.
    func synka() {
        guard startad, läge.på, !läge.arbetar, CoachModell.shared.redo else { return }
        guard let c = CoachNyckelring.läs(), c.isValid else {
            läge.kopplad = false
            return
        }
        läge.kopplad = true
        if läge.fel != nil, let f = senasteFörsök, Date().timeIntervalSince(f) < CoachRules.retrySeconds { return }
        // Filerna är låsta tills telefonen låsts upp en gång efter en omstart.
        guard UIApplication.shared.isProtectedDataAvailable else { return }

        läge.arbetar = true
        senasteFörsök = Date()
        börjaBakgrund()
        let känt: [String: Spår] = spår
        Task { @MainActor in
            let lista = await Task.detached(priority: .utility) { () -> (dagar: [(day: String, fingerprint: String)],
                                                                          spår: [String: Spår]) in
                Self.lista(känt: känt)
            }.value
            self.spår = lista.spår
            var fel: String? = nil
            for dag in self.fil.logg.pending(lista.dagar) {
                guard self.läge.på else { break }
                let läst: (data: Data, avtryck: String)? = await Task.detached(priority: .utility) {
                    () -> (data: Data, avtryck: String)? in
                    guard let d = try? Data(contentsOf: NightFiles.archive("dygn-" + dag), options: .mappedIfSafe)
                    else { return nil }
                    return (d, DayCopyLedger.fingerprint(d))
                }.value
                // Ett arkiv som försvunnit eller är för stort eller tomt hoppas över: det finns inget att skicka.
                guard let läst, let anrop = CoachCall.dayCopy(config: c, day: dag, archive: läst.data) else { continue }
                let svar: CoachReply = await CoachSändare.skicka(anrop)
                switch svar {
                case .copied(let dygn, let mb, let tak):
                    self.fil.logg.mark(day: dag, fingerprint: läst.avtryck)
                    self.fil.dygn = dygn
                    self.fil.megabyte = mb
                    self.fil.tak = tak
                    self.fil.senast = Date()
                    self.spara()
                    self.läge.dygn = dygn
                    self.läge.megabyte = mb
                    self.läge.tak = tak
                    self.läge.senast = self.fil.senast
                case .refused("for-gammal"):
                    // Hinken är full och dygnet äldre än allt i den: klart, inget nytt försök.
                    self.fil.logg.mark(day: dag, fingerprint: läst.avtryck)
                    self.spara()
                default:
                    fel = Self.text(svar)
                    if svar.isUnknownDevice { CoachModell.shared.kopplaFrån() }
                }
                if fel != nil { break }
            }
            self.läge.kopplad = CoachNyckelring.läs() != nil
            self.läge.fel = fel
            self.läge.arbetar = false
            self.slutaBakgrund()
        }
    }

    /// Dygnens arkiv och deras fingeravtryck, nyast först. Körs utanför huvudkön: ett arkiv är ett par MB.
    nonisolated private static func lista(känt: [String: Spår])
        -> (dagar: [(day: String, fingerprint: String)], spår: [String: Spår]) {
        var dagar: [(day: String, fingerprint: String)] = []
        var nytt: [String: Spår] = [:]
        for stam in NightFiles.dayStems() {
            let dag: String = String(stam.dropFirst("dygn-".count))
            guard stam.hasPrefix("dygn-"), DayCopyRules.isValidDay(dag), stam.count == "dygn-yyyy-MM-dd".count else {
                continue
            }
            let storlek: Int = NightFiles.archiveSize(stam)
            guard storlek > 0 else { continue }
            let url: URL = NightFiles.archive(stam)
            let ändrad: Date = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate]
                as? Date) ?? .distantPast
            if let s = känt[dag], s.storlek == storlek, s.ändrad == ändrad {
                nytt[dag] = s
                dagar.append((dag, s.avtryck))
                continue
            }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            let avtryck: String = DayCopyLedger.fingerprint(data)
            nytt[dag] = Spår(storlek: storlek, ändrad: ändrad, avtryck: avtryck)
            dagar.append((dag, avtryck))
        }
        return (dagar, nytt)
    }

    private func spara() {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        guard let data = try? e.encode(fil) else { return }
        NightFiles.write(data, to: Self.filen)
    }

    /// Uppladdningen får gå klart även om appen läggs i bakgrunden under tiden.
    private func börjaBakgrund() {
        guard bakgrund == .invalid else { return }
        bakgrund = UIApplication.shared.beginBackgroundTask(withName: "dygnskopia") { [weak self] in
            Task { @MainActor in self?.slutaBakgrund() }
        }
    }

    private func slutaBakgrund() {
        guard bakgrund != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bakgrund)
        bakgrund = .invalid
    }

    /// Vad ett svar som inte gick fram betyder, i ord.
    private static func text(_ svar: CoachReply) -> String {
        switch svar {
        case .ok, .copied:
            return ""
        case .refused(let skäl):
            switch skäl {
            case "okand": return "Kopplingen gäller inte längre. Be Claude om en ny och klistra in den."
            case "fullt": return "Det är fullt hos coachen. Säg till Claude."
            default: return "Kopian tog inte emot dygnet som skickades."
            }
        case .http(let kod):
            return "Kopian svarade inte som väntat (\(kod)). Idunn försöker igen."
        case .unreachable:
            return "Inget nät just nu. Idunn försöker igen."
        }
    }
}
