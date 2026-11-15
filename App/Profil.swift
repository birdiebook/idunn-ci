import Foundation
import Combine
import Night
import Pass
import SleepNeed
import Markers

/// BESLUT B104 · BESLUT B105 · METOD M59
/// Profilen i appen (PLAN.md Å3): Idunns nätter och pass och det användaren skriver in blir en rad per markör
/// (`MarkerProfile.cards`). Räkningen är IdunnKits; här kopplas den ihop och det inskrivna sparas. Födelseår och kön
/// är en inställning (UserDefaults). Mätningarna och de egna markörerna är hälsodata som nätterna: en fil i appens
/// mapp (`markorer.json`), som bara lämnar telefonen med Exportera alla dygn (dataregeln).
final class ProfilModell: ObservableObject {
    static let shared = ProfilModell()

    @Published private(set) var kort: [MarkerCard] = []
    @Published private(set) var person: Person? = ProfilModell.sparadPerson()
    @Published private(set) var logg: MeasurementLog = MeasurementLog()
    /// Filen finns men gick inte att läsa (skriven av ett nyare bygge, eller trasig). Då skrivs den aldrig över:
    /// hellre en profil som inte går att ändra än mätningar som försvinner.
    @Published private(set) var låst: Bool = false

    private var nätter: [Trends.IdunNight] = []
    private var pass: [Pass] = []
    /// BESLUT B111. Det Idunn räknat för kondition (steptest, pass ute eller det passiva talet), ur `KonditionModell`.
    private var kondition: [DayValue] = []
    private var prenumeration: AnyCancellable?

    /// Filen med det inskrivna, bredvid nätterna.
    static var fil: URL { NightFiles.folder.appendingPathComponent("markorer.json") }

    private static let årNyckel: String = "profil.fodelsear"
    private static let könNyckel: String = "profil.kon"

    private init() {
        // Inte i provet (IdunnProv körs inuti appen): där räknas korten ur påhittad data med `kort(person:…)`.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let läst: (logg: MeasurementLog, låst: Bool) = ProfilModell.läs(från: ProfilModell.fil)
        logg = läst.logg
        låst = läst.låst
        prenumeration = PassController.shared.$saved.sink { [weak self] (p: [Pass]) in
            self?.pass = p
            self?.räkna()
        }
    }

    // MARK: Filen och inställningen

    /// Loggen ur filen. En fil som saknas är en tom logg; en som inte går att läsa ger en tom logg som är låst.
    static func läs(från url: URL) -> (logg: MeasurementLog, låst: Bool) {
        guard let data = try? Data(contentsOf: url) else { return (MeasurementLog(), false) }
        guard let logg = try? MeasurementLog.decode(data) else { return (MeasurementLog(), true) }
        return (logg, false)
    }

    /// Skriver loggen, med samma skydd som nätternas filer. `false` när det inte gick.
    @discardableResult
    static func skriv(_ logg: MeasurementLog, till url: URL) -> Bool {
        guard let data = try? logg.encoded() else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    private static func sparadPerson() -> Person? {
        let d = UserDefaults.standard
        guard d.object(forKey: årNyckel) != nil, let kön = d.string(forKey: könNyckel).flatMap(Sex.init(rawValue:))
        else { return nil }
        return Person(birthYear: d.integer(forKey: årNyckel), sex: kön)
    }

    private func spara() {
        guard !låst else { return }
        try? NightFiles.prepareFolder()
        ProfilModell.skriv(logg, till: ProfilModell.fil)
    }

    // MARK: Det som ändrar profilen

    /// Nätterna har ändrats (en ny natt, ett nytt bygge).
    func sätt(nätter: [Trends.IdunNight]) {
        self.nätter = nätter
        räkna()
    }

    /// Födelseår och kön är satta, eller borttagna (`nil`).
    func sätt(person ny: Person?) {
        let d = UserDefaults.standard
        if let p = ny {
            d.set(p.birthYear, forKey: ProfilModell.årNyckel)
            d.set(p.sex.rawValue, forKey: ProfilModell.könNyckel)
        } else {
            d.removeObject(forKey: ProfilModell.årNyckel)
            d.removeObject(forKey: ProfilModell.könNyckel)
        }
        person = ny
        räkna()
    }

    /// BESLUT B111. Konditionen Idunn räknat har ändrats: räkna om korten.
    func sätt(kondition ny: [DayValue]) {
        kondition = ny
        räkna()
    }

    /// En ny mätning. `false` när den inte gick att spara (okänd markör, ogiltigt värde, låst fil).
    @discardableResult
    func läggTill(markör: MarkerID, dag: Int, värde: Double, not: String?) -> Bool {
        guard !låst else { return false }
        var ny: MeasurementLog = logg
        let rensad: String? = not.map { (s: String) -> String in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        do {
            try ny.add(MarkerReading(marker: markör, day: dag, value: värde,
                                   note: (rensad ?? "").isEmpty ? nil : rensad))
        } catch {
            return false
        }
        logg = ny
        spara()
        räkna()
        return true
    }

    func taBort(mätning id: String) {
        guard !låst else { return }
        logg.remove(id: id)
        spara()
        räkna()
    }

    /// En egen markör (ett lyft, ett test). `false` utan namn eller med låst fil.
    @discardableResult
    func nyMarkör(namn: String, enhet: String, bättre: MarkerDefinition.Direction) -> Bool {
        guard !låst else { return false }
        var ny: MeasurementLog = logg
        guard (try? ny.addCustom(name: namn, unit: enhet, better: bättre)) != nil else { return false }
        logg = ny
        spara()
        räkna()
        return true
    }

    /// Tar bort en egen markör och dess mätningar.
    func taBort(markör id: MarkerID) {
        guard !låst else { return }
        logg.removeCustom(id)
        spara()
        räkna()
    }

    private func räkna() {
        kort = ProfilModell.kort(person: person, nätter: nätter, pass: pass, logg: logg, idag: Väcktidsval.idag(),
                          kondition: kondition)
    }

    // MARK: Räkningen

    /// METOD M59 · BESLUT B105. Korten ur Idunns nätter, passen och det inskrivna. Värden in och ut, så att provet
    /// räknar samma sak ur påhittad data. HRV, vilopuls och regelbundenhet tas per dag som i trendvyn
    /// (`Trends.idunValues`). Pulsens återhämtning är fallet en minut efter stopp i konditionspass: bara de slutar på
    /// ett sätt som går att jämföra (METOD M47). Maxpulsen är den ur passen (METOD M53), på det senaste passets dag.
    /// BESLUT B111 · METOD M64. `kondition` är det Idunn räknat för VO2 max (en punkt per mätning); det räknas i samma
    /// rad som det inskrivna.
    static func kort(person: Person?, nätter: [Trends.IdunNight], pass: [Pass], logg: MeasurementLog, idag: Int,
                     kondition: [DayValue] = [], zon: TimeZone = .current) -> [MarkerCard] {
        let värden: Trends.Values = Trends.idunValues(nätter)
        func serie(_ mått: Trends.Measure) -> [DayValue] {
            (värden[mått] ?? [:]).map { (p: (key: WakeDay, value: Double)) -> DayValue in
                DayValue(day: p.key.daysSince1970, value: p.value)
            }
        }
        var serier: [MarkerID: [DayValue]] = [
            .hrv: serie(.hrv),
            .restingHeartRate: serie(.restingHeartRate),
            .regularity: serie(.regularity),
        ]
        serier[.heartRateRecovery] = pass.compactMap { (p: Pass) -> DayValue? in
            guard p.kind == .kondition, let fall: Int = p.drop(after: 60) else { return nil }
            return DayValue(day: Väcktidsval.idag(p.start, zon: zon), value: Double(fall))
        }
        if let högst: Double = PassLoad.maxPulse(from: pass),
           let senaste: Date = pass.map({ (p: Pass) -> Date in p.start }).max() {
            serier[.maxPulse] = [DayValue(day: Väcktidsval.idag(senaste, zon: zon), value: högst)]
        }
        if !kondition.isEmpty { serier[.vo2max] = kondition }
        return MarkerProfile.cards(person: person, series: serier, log: logg, today: idag)
    }
}
