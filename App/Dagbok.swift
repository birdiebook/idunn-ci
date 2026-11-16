import Foundation
import Combine
import Journal

/// BESLUT B130. Det dagboken frågar om just nu: morgonens skattning eller kvällens taggar, för en uppvakningsdag.
enum Dagboksfråga: Equatable {
    case morgon(dag: Int)
    case kväll(dag: Int)
}

/// BESLUT B130. Kvällens blad som ett värde med identitet, för `.sheet(item:)`.
struct Kvällsfråga: Identifiable, Equatable {
    let dag: Int
    var id: Int { dag }
}

/// BESLUT B130 · METOD M75
/// Dagboken i appen (PLAN.md U2): kvällens taggar och morgonens skattning, och när appen frågar efter dem.
/// Räkningen är IdunnKits (`Journal`, `JournalClock`); här sparas filen och hålls frågan som visas. Det som skrivs in
/// är hälsodata som nätterna: en fil i appens mapp (`dagbok.json`), som bara lämnar telefonen med Exportera alla dygn
/// (dataregeln).
final class DagbokModell: ObservableObject {
    static let shared = DagbokModell()

    @Published private(set) var dagbok: Journal = Journal()
    /// Filen finns men gick inte att läsa (skriven av ett nyare bygge, eller trasig). Då skrivs den aldrig över och
    /// appen frågar ingenting: hellre en dagbok som står stilla än kvällar som försvinner.
    @Published private(set) var låst: Bool = false
    /// Frågan som visas, eller `nil`.
    @Published private(set) var fråga: Dagboksfråga?

    /// Kvällen där "Inte nu" valdes sedan appen startade: den frågas inte igen förrän appen startas om eller bladet
    /// öppnas från Data.
    private var uppskjuten: Int?

    /// Filen, bredvid nätterna.
    static var fil: URL { NightFiles.folder.appendingPathComponent(Journal.fileName) }

    private init() {
        // Inte i provet (IdunnProv körs inuti appen): där ritas bladen med påhittade värden.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let läst: (dagbok: Journal, låst: Bool) = DagbokModell.läs(från: DagbokModell.fil)
        dagbok = läst.dagbok
        låst = läst.låst
        // Frågan sätts redan här, så att morgonens fråga ligger över Morgon från första bilden.
        fråga = attFråga(nu: Date())
    }

    // MARK: Filen

    /// Dagboken ur filen. En fil som saknas är en tom dagbok; en som inte går att läsa ger en tom som är låst.
    static func läs(från url: URL) -> (dagbok: Journal, låst: Bool) {
        guard let data = try? Data(contentsOf: url) else { return (Journal(), false) }
        guard let dagbok = try? Journal.decode(data) else { return (Journal(), true) }
        return (dagbok, false)
    }

    /// Skriver dagboken, med samma skydd som nätternas filer. `false` när det inte gick.
    @discardableResult
    static func skriv(_ dagbok: Journal, till url: URL) -> Bool {
        guard let data = try? dagbok.encoded() else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    private func sätt(_ ny: Journal) {
        guard !låst else { return }
        dagbok = ny
        try? NightFiles.prepareFolder()
        DagbokModell.skriv(ny, till: DagbokModell.fil)
    }

    // MARK: Frågan

    private static func zon(_ nu: Date) -> Int { TimeZone.current.secondsFromGMT(for: nu) }

    /// Vad appen ska fråga nu (METOD M75), eller `nil`.
    private func attFråga(nu: Date) -> Dagboksfråga? {
        guard !låst else { return nil }
        guard let p = JournalClock.prompt(at: nu, utcOffsetSeconds: DagbokModell.zon(nu), journal: dagbok) else {
            return nil
        }
        switch p {
        case .morning(let dag):
            return .morgon(dag: dag)
        case .evening(let dag):
            return uppskjuten == dag ? nil : .kväll(dag: dag)
        }
    }

    /// Appen öppnades eller kom fram: ställ frågan som är aktuell, om ingen redan visas.
    func appenÖppnades(nu: Date = Date()) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if fråga == nil { fråga = attFråga(nu: nu) }
    }

    /// Morgonens skattning, 1–5.
    func svara(morgon dag: Int, utvilad: Int, nu: Date = Date()) {
        sätt(dagbok.setting(JournalMorning(wakeDayNumber: dag, rested: utvilad,
                                           recordedAt: Int(nu.timeIntervalSince1970))))
        fråga = nil
    }

    /// Morgonens fråga hoppades över: den ställs inte igen den dagen.
    func hoppaÖver(morgon dag: Int) {
        sätt(dagbok.skippingMorning(dag))
        fråga = nil
    }

    /// Kvällens taggar; en tom lista är svaret "inget av det".
    func svara(kväll dag: Int, taggar: [EveningTag], nu: Date = Date()) {
        sätt(dagbok.setting(JournalEvening(wakeDayNumber: dag, tags: taggar,
                                           recordedAt: Int(nu.timeIntervalSince1970))))
        fråga = nil
    }

    /// "Inte nu", eller bladet drogs ner: kvällen är obesvarad men frågas inte igen i den här körningen.
    func inteNu(kväll dag: Int) {
        uppskjuten = dag
        if fråga == .kväll(dag: dag) { fråga = nil }
    }

    /// BESLUT B131. Kvällens taggar för natten som slutar på dagen, som ord med små bokstäver ("sen måltid"), i
    /// listans ordning. Tom utan dag, utan besvarad kväll och i provet.
    func taggar(dag: Int?) -> [String] {
        guard let dag, let kväll = dagbok.evening(dag) else { return [] }
        return kväll.tags.map { (t: EveningTag) -> String in (JournalTags.tag(t.id)?.title ?? t.id).lowercased() }
    }

    /// Från Data: öppna kvällens blad för natten som kommer (eller som pågår), också när den redan är besvarad.
    func öppnaKväll(nu: Date = Date()) {
        guard !låst else { return }
        fråga = .kväll(dag: JournalClock.eveningDay(nu, utcOffsetSeconds: DagbokModell.zon(nu)))
    }

    /// Från Data: öppna morgonens fråga för idag, också när den redan är besvarad.
    func öppnaMorgon(nu: Date = Date()) {
        guard !låst else { return }
        fråga = .morgon(dag: JournalClock.morningDay(nu, utcOffsetSeconds: DagbokModell.zon(nu)))
    }
}
