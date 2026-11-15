import Foundation
import Combine
import Fitness
import Markers
import Night
import Pass

/// BESLUT B106 · METOD M60 · METOD M61 · METOD M64
/// Konditionen i appen (PLAN.md spåret O, etapp O1 och O2): profilen, Whoops avskrivna VO2 max-tal och skattningen av
/// VO2 max ur Idunns egna nätter. Profilen och talen sparas som `kondition.json` (`FitnessStore`) i Application Support,
/// med samma skyddsklass som appens andra hälsofiler (`NightFiles.write`), och följer med i "Exportera alla dygn"
/// (`NightExport.packageAll`). Filen som saknas eller inte går att läsa är ett tomt lager. Skattningen räknas av
/// IdunnKits `PassiveFitness` ur nattens vilopuls (samma värde som Morgon visar, METOD M5) och profilen; bara Idunns
/// nätter räknas, aldrig Whoops export. Inget skickas av sig själv (BESLUT B23).
final class KonditionModell: ObservableObject {
    /// Inte i provet (IdunnProv körs inuti appen): där finns ingen fil att läsa, och provet bygger egna lager.
    static let shared = KonditionModell(
        läs: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)

    /// Det som sparas: profilen och de avskrivna talen.
    @Published private(set) var lager: FitnessStore
    /// Skattningen för idag, eller det som saknas för att räkna den.
    @Published private(set) var skattning: PassiveFitness.Outcome
    /// BESLUT B110 · METOD M62 · METOD M64. Aktiva mätningar ur de sparade passen (steptest och pass ute), i dagordning.
    @Published private(set) var mätningar: [FitnessMeasurement] = []
    /// BESLUT B110 · METOD M62. Pulsen på nivå 1–3 i varje steptest, för "pulsen på samma nivå" över tid.
    @Published private(set) var nivåpuls: [KonditionNivåpuls] = []
    /// BESLUT B114 · METOD M66. Pulsen vid samma tempo över passen ute; nil utan ett pass med jämna bitar.
    @Published private(set) var tempopuls: SteadyPulse.Series? = nil
    /// BESLUT B110 · METOD M64. Talet som visas i vardagen: aktiva mätningar, annars den passiva skattningen.
    @Published private(set) var visat: FitnessSummary.Shown? = nil

    /// BESLUT B111. Födelseår och kön finns på fliken Profil (`ProfilModell.person`) och matas hit; allt som räknas här
    /// använder dem i stället för fälten i `lager.profile`.
    @Published private(set) var person: Person? = nil

    private var nätter: [RestingNight] = []
    private var sparade: [Pass] = []
    private let fil: URL

    /// Filens plats: Application Support, bredvid passens mapp.
    static let standardfil: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(FitnessFile.fileName)

    init(fil: URL = KonditionModell.standardfil, läs: Bool = true) {
        self.fil = fil
        let läst: FitnessStore = läs ? Self.läsFil(fil) : FitnessStore()
        lager = läst
        skattning = PassiveFitness.estimate(profile: Self.räknad(läst.profile, person: nil), nights: [], day: Self.idag())
    }

    /// En fil som saknas eller är trasig blir ett tomt lager.
    static func läsFil(_ url: URL) -> FitnessStore {
        guard let data = try? Data(contentsOf: url), let s = try? FitnessFile.decode(data) else {
            return FitnessStore()
        }
        return s
    }

    /// Dagnumret för `nu`: dagar sedan 1970-01-01 i telefonens zon, som `SleepNight.day`.
    static func idag(nu: Date = Date(), zon: TimeZone = .current) -> Int {
        WakeDay(nu, utcOffsetSeconds: zon.secondsFromGMT(for: nu)).daysSince1970
    }

    /// METOD M61. Vilopulsen per uppvakningsdag ur Idunns nätter (samma värde som Morgon visar). Finns två nätter
    /// samma dag gäller den ur K18; en natt utan vilopuls räknas inte.
    static func vilonätter(_ idun: [Trends.IdunNight]) -> [RestingNight] {
        var perDag: [Int: Trends.IdunNight] = [:]
        for n in idun {
            guard let puls = n.restingHeartRate, puls > 0 else { continue }
            let dag: Int = n.day.daysSince1970
            if let finns = perDag[dag], finns.source == .k18 || n.source != .k18 { continue }
            perDag[dag] = n
        }
        return perDag.keys.sorted().compactMap { (dag: Int) -> RestingNight? in
            perDag[dag]?.restingHeartRate.map { (puls: Double) -> RestingNight in
                RestingNight(day: dag, pulse: puls)
            }
        }
    }

    /// BESLUT B111. Profilen som räknas: den sparade med födelseår och kön från personen (utan person båda `nil`).
    /// Fälten `birthYear` och `sex` i den sparade profilen används inte längre.
    static func räknad(_ profil: FitnessProfile, person: Person?) -> FitnessProfile {
        var ut: FitnessProfile = profil
        ut.birthYear = person?.birthYear
        if let p = person {
            ut.sex = p.sex == .male ? FitnessProfile.Sex.man : FitnessProfile.Sex.kvinna
        } else {
            ut.sex = nil
        }
        return ut
    }

    /// BESLUT B111. Profilen som räknas, ur lagret och personen.
    var räknadProfil: FitnessProfile { Self.räknad(lager.profile, person: person) }

    /// BESLUT B111. Födelseår och kön har ändrats på fliken Profil: räkna om allt som beror på dem.
    func sätt(person ny: Person?) {
        guard ny != person else { return }
        person = ny
        räkna()
    }

    /// Nätterna har ändrats (en ny natt, ett nytt bygge): räkna om skattningen.
    func sätt(nätter idun: [Trends.IdunNight]) {
        nätter = Self.vilonätter(idun)
        räkna()
    }

    /// Profilen har ändrats: spara och räkna om.
    func sätt(profil: FitnessProfile) {
        guard profil != lager.profile else { return }
        var ny: FitnessStore = lager
        ny.profile = profil
        spara(ny)
        räkna()
    }

    /// BESLUT B110 · METOD M62. Passen har ändrats (ett nytt pass, ett borttaget): räkna om mätningarna och talet.
    func sätt(pass: [Pass]) {
        sparade = pass
        räkna()
    }

    /// BESLUT B110 · METOD M62. Höjden på steget som skrevs in senast, för nästa steptest.
    func sätt(steghöjd: Double?) {
        guard steghöjd != lager.stepHeightCm else { return }
        var ny: FitnessStore = lager
        ny.stepHeightCm = steghöjd
        spara(ny)
    }

    /// METOD M60. Maxpulsen och var den kommer ifrån (egen eller ur åldern); `nil` utan båda.
    var maxpulsUnderlag: MaxPulse? {
        räknadProfil.maxPulse(year: FitnessRules.year(ofDay: Self.idag()))
    }

    /// METOD M60. Maxpulsen i slag/min, eller `nil`.
    var maxpuls: Double? { maxpulsUnderlag?.bpm }

    /// METOD M64. Referensen för profilens kön och ålder, eller `nil` utan båda (eller utanför 20–59 år).
    var referens: KonditionReferens? {
        let profil: FitnessProfile = räknadProfil
        guard let kön = profil.sex,
              let ålder = profil.age(year: FitnessRules.year(ofDay: Self.idag())),
              let band = FitnessReference.band(sex: kön, age: ålder) else { return nil }
        return KonditionReferens(band: band, kön: kön)
    }

    /// Dagen ett pass räknas på: dagar sedan 1970-01-01 i telefonens zon vid passets start.
    static func dag(för pass: Pass) -> Int {
        WakeDay(pass.start, utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: pass.start)).daysSince1970
    }

    /// METOD M62. Pulsen på nivå 1–3 i varje steptest med puls på nivån, i dagordning.
    static func nivåpuls(_ pass: [Pass]) -> [KonditionNivåpuls] {
        var ut: [KonditionNivåpuls] = []
        for p in pass where p.isStepTest {
            let dag: Int = Self.dag(för: p)
            for n in StepTest.levels(p) where n.index < 3 {
                guard let puls = n.pulse else { continue }
                ut.append(KonditionNivåpuls(test: p.id, dag: dag, nivå: n.index + 1, puls: puls))
            }
        }
        return ut.sorted { (a: KonditionNivåpuls, b: KonditionNivåpuls) -> Bool in
            a.dag != b.dag ? a.dag < b.dag : a.nivå < b.nivå
        }
    }

    /// METOD M64. Ett avskrivet Whoop-tal för en dag (ersätter talet som redan står för dagen).
    func skrivAv(dag: Int, värde: Double) {
        var ny: FitnessStore = lager
        ny.setWhoopNote(day: dag, value: värde)
        spara(ny)
    }

    /// BESLUT B111 · METOD M64. Det Idunn räknat, som en serie för raden Kondition på Profil: varje aktiv mätning som en
    /// punkt, och utan mätning men med ett visat tal en enda punkt för idag.
    var konditionsserie: [DayValue] {
        if !mätningar.isEmpty {
            return mätningar.map { (m: FitnessMeasurement) -> DayValue in DayValue(day: m.day, value: m.value) }
        }
        if let v = visat { return [DayValue(day: Self.idag(), value: v.value)] }
        return []
    }

    private func räkna() {
        let idag: Int = Self.idag()
        skattning = PassiveFitness.estimate(profile: räknadProfil, nights: nätter, day: idag)
        // BESLUT B110. Utan maxpuls ingen mätning: båda metoderna räknar mot den.
        var ny: [FitnessMeasurement] = []
        var tempolista: [SteadyPulse.PassSegments] = []
        if let max = räknadProfil.maxPulse(year: FitnessRules.year(ofDay: idag))?.bpm {
            let vila: Double? = PassiveFitness.restingPulse(nätter, day: idag)?.pulse
            for p in sparade {
                if let m = FitnessSummary.measurement(p, day: Self.dag(för: p), maxPulse: max, restingPulse: vila) {
                    ny.append(m)
                }
                // BESLUT B114 · METOD M66. Passen ute: bitarna räknas mot vilopulsen den dagen, annars dagens.
                if p.isOutdoor {
                    let dagen: Int = Self.dag(för: p)
                    guard let vilopuls = PassiveFitness.restingPulse(nätter, day: dagen)?.pulse ?? vila else { continue }
                    let bitar: [SpeedFitness.Segment] = SpeedFitness.segments(p, maxPulse: max, restingPulse: vilopuls)
                    if !bitar.isEmpty {
                        tempolista.append(SteadyPulse.PassSegments(day: dagen, restingPulse: vilopuls, segments: bitar))
                    }
                }
            }
        }
        tempopuls = SteadyPulse.shown(tempolista)
        mätningar = ny.sorted { (a: FitnessMeasurement, b: FitnessMeasurement) -> Bool in a.day < b.day }
        nivåpuls = Self.nivåpuls(sparade)
        var passiv: FitnessEstimate?
        if case .estimate(let e) = skattning { passiv = e }
        visat = FitnessSummary.shown(passive: passiv, measurements: ny, day: idag)
    }

    private func spara(_ ny: FitnessStore) {
        lager = ny
        guard let data = try? FitnessFile.encode(ny) else { return }
        try? FileManager.default.createDirectory(at: fil.deletingLastPathComponent(), withIntermediateDirectories: true)
        NightFiles.write(data, to: fil)
    }
}
