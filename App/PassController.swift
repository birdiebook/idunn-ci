import Foundation
import Fitness
import HeartRate
import Pass
import UIKit
import WhoopFrames

/// BESLUT B58 · METOD M47
/// Passet (PLAN.md spåret P): ett pass med puls för bastu, dusch, styrka, kondition,
/// promenad eller golf (B142). Äger `PassRecorder` (IdunnKits tillståndsmaskin), slår på pulsen
/// från bandet medan passet pågår och 10 minuter efter stopp (`Recorder.startPulse`)
/// och av när det är färdigt, och håller klockan igång med en timer per sekund.
///
/// **Passet sparas så att en dödad app inte tappar det:** det pågående passet skrivs
/// till Application Support/pass var 10:e sekund, vid varje fasbyte, när typen
/// ändras och när appen går till bakgrunden; vid start läses ett osparat pågående pass
/// in igen (`PassRecorder.restore`) och mäter vidare. Filerna har samma skyddsklass
/// som appens andra hälsofiler (`NightFiles.protection`). Skärmen hålls vaken bara
/// medan passet mäter (running och after). Inget skickas av sig själv; ett pass lämnar
/// telefonen bara med Exportera (BESLUT B22, B23).
///
/// Allt körs på huvudkön (pulsen kommer från `Recorder.onPulse` som Bluetooth levererar
/// på `queue: nil`); filerna skrivs på en egen kö, i ordning.
final class PassController: ObservableObject {
    static let shared = PassController()

    /// Tillståndsmaskinen: fasen och passet som pågår.
    @Published private(set) var state = PassRecorder()
    /// Klockan som vyn ritar efter, uppdaterad varje sekund medan passet mäter.
    @Published private(set) var now = Date()
    /// Färdiga pass, senast först.
    @Published private(set) var saved: [Pass] = []
    @Published var problem: String?
    /// BESLUT B110 · METOD M62. Varför det senaste steptestet tog slut av sig självt; `nil` när det stoppades för hand
    /// eller inget steptest gjorts. Vyn säger det efter testet.
    @Published private(set) var steptestSlut: StepTest.Reason?
    /// BESLUT B111 · METOD M62. Numret på metronomens senaste klick (0 vid nivåns första), för bilden av takten.
    @Published private(set) var steptestSlag: Int = 0

    /// Applikationens pass-mapp.
    static let folder: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("pass", isDirectory: true)

    private static let saveInterval: TimeInterval = 10

    private var timer: Timer?
    private var pulseOn = false
    /// BESLUT B110 · METOD M62. Klicket i steptestet: går bara i fasen running i ett steptest.
    private let metronom = Metronom()
    /// BESLUT B107 · BESLUT B110. Platsen är på bara i fasen running i ett pass ute.
    private var platsOn = false
    /// BESLUT B147 · METOD M84. Bandets rörelse i 100 Hz är på bara i fasen running.
    private var imuOn = false
    private lazy var plats: PassPlats = {
        let p = PassPlats()
        p.onPoint = { [weak self] (punkt: TrackPoint) -> Void in self?.receivedPoint(punkt) }
        p.onDenied = { [weak self] () -> Void in
            self?.problem = "Idunn får inte läsa platsen. Slå på det i Inställningar för att få sträcka och karta."
        }
        return p
    }()
    private var lastSaveAt = Date.distantPast
    /// Filnamnet varje pass fick första gången det sparades, så att ett byte av tidszon
    /// aldrig ger en andra fil för samma pass.
    private var fileNames: [UUID: String] = [:]
    private let ioQueue = DispatchQueue(label: "se.birdiebook.idun.pass", qos: .utility)
    /// BESLUT B117 · METOD M68. Fyllningen ur bandets historik: en i taget, och per pass de dygn som redan lästs
    /// (med storleken de hade), så att ett dygn som inte vuxit inte läses om.
    private var historikPågår = false
    private var historikSedd: [UUID: [String: Int]] = [:]

    /// BESLUT B121 · METOD M69. Förslagen ur bandets historik för de två senaste dygnen, senaste först. Inget läggs
    /// till tyst: ett förslag blir ett pass först med `läggTill`.
    @Published private(set) var förslag: [PassDetection.Candidate] = []
    private var förslagPågår = false
    /// Bandets poster från senaste läsningen, för att fylla pulsen i ett tillagt förslag.
    private var förslagsposter: [PassHistory.Reading] = []
    /// De borttagna förslagen (läses i `init`, inte i provet).
    private var förslagslager: PassSuggestions.Store = PassSuggestions.Store()

    private init() {
        metronom.påSlag = { [weak self] (n: Int) -> Void in self?.steptestSlag = n }
        // Kontrollen med block, inte `#selector`: klassen ärver inte från NSObject.
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.appToBackground() }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.appBecameActive() }
        // Inte i provet (IdunnProv körs inuti appen): där finns inga pass att läsa in och inget band.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            förslagslager = PassForslag.läsLager()
            load()
        }
    }

    // MARK: Knapparna

    /// Start.
    func start() {
        guard state.phase == .idle else { return }
        steptestSlut = nil
        let före = state.phase
        state.start(now: Date())
        now = Date()
        changed(from: före)
    }

    /// BESLUT B107 · BESLUT B110. Start ute: som Start, men passet läser också telefonens plats (sträcka, tempo
    /// och karta efteråt). Nekas platsen går passet ändå, med bara puls, och `problem` säger hur det slås på.
    func startUte() {
        guard state.phase == .idle else { return }
        steptestSlut = nil
        let före = state.phase
        state.start(now: Date(), outdoor: true)
        now = Date()
        changed(from: före)
    }

    /// BESLUT B110 · METOD M62. Start av ett steptest: stegets höjd sparas till nästa gång, passet får typen kondition,
    /// och metronomen går i fasen running. Testet stannar av sig självt (`kollaSteptest`); pulsen mäts sedan vidare i
    /// 10 minuter som vid varje stopp.
    func startSteptest(höjdCm: Double) {
        guard state.phase == .idle else { return }
        KonditionModell.shared.sätt(steghöjd: höjdCm)
        steptestSlut = nil
        let före = state.phase
        state.start(now: Date(), stepHeightCm: höjdCm)
        now = Date()
        changed(from: före)
    }

    /// Stopp: pulsen mäts vidare i 10 minuter.
    func stop() {
        let före = state.phase
        state.stop(now: Date())
        changed(from: före)
    }

    /// Passets typ (sätts efter stopp, men tas emot i varje fas med ett pass).
    func setKind(_ kind: PassKind) {
        state.setKind(kind)
        persistCurrent()
    }

    /// BESLUT B150. Passets märkning: typ eller egna ord, och anteckningen. Sparas direkt, som typen.
    func setLabel(_ label: PassLabel) {
        state.setLabel(label)
        persistCurrent()
    }

    /// BESLUT B150 · METOD M85. Ändrar ett sparat pass: märkningen, och start och slut. Proven utanför det nya fönstret
    /// tas bort och de minuter som saknas fylls ur bandets historik (på filkön); talen räknas om ur proven. Ett
    /// förslags ursprung (`suggested`) står kvar som det var.
    func ändra(_ pass: Pass, label: PassLabel, start: Date, stopp: Date) {
        guard let i = saved.firstIndex(where: { $0.id == pass.id }) else { return }
        var p: Pass = saved[i]
        PassEdit.apply(label, to: &p)
        if p.stop != nil { p = PassEdit.retimed(p, start: start, stop: stopp) }
        guard p != saved[i] else { return }
        var lista: [Pass] = saved
        lista[i] = p
        saved = Self.newestFirst(lista)
        persist(p)
        historikSedd[p.id] = nil
        let ändrat: Pass = p
        ioQueue.async { [weak self] in
            let läst = PassHistorik.läs(ändrat, now: Date(), sedda: [:])
            let fyllt: Pass = PassHistory.fill(ändrat, readings: läst.poster, through: läst.nått)
            DispatchQueue.main.async {
                guard let self = self, let j = self.saved.firstIndex(where: { $0.id == ändrat.id }),
                      self.saved[j] == ändrat, fyllt != ändrat else { return }
                // Bara om passet inte ändrats igen medan historiken lästes.
                self.saved[j] = fyllt
                self.historikSedd[fyllt.id] = läst.sedda
                self.persist(fyllt)
            }
        }
    }

    /// "Klar": avslutar efterperioden och sparar direkt.
    func finish() {
        let före = state.phase
        state.finishNow(now: Date())
        changed(from: före)
    }

    /// Tar bort ett sparat pass (filen och raden).
    func delete(_ pass: Pass) {
        saved.removeAll { $0.id == pass.id }
        let namn = fileNames[pass.id] ?? PassFile.fileName(start: pass.start)
        fileNames[pass.id] = nil
        ioQueue.async {
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(namn))
        }
    }

    /// Passets zip (`idunn-pass-<start>.zip` med passets JSON) i en tillfällig mapp, för delningsbladet.
    /// BESLUT B107 · BESLUT B110. Utan spår som förval: positionerna visar var användaren bor och rör sig och
    /// lämnar telefonen bara med `medSpår` (Exportera med spår). `nil` när filen inte gick att skriva.
    func exportFile(_ pass: Pass, medSpår: Bool = false) -> URL? {
        let ut: Pass = medSpår ? pass : pass.withoutTrack()
        guard let json = try? PassFile.encode(ut) else { return nil }
        let zip = ZipArchive.make([ZipArchive.Entry(name: PassFile.fileName(start: pass.start), data: json)],
                                  date: pass.start)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let url = dir.appendingPathComponent(PassFile.exportName(start: pass.start))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try zip.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return nil
        }
        return url
    }

    // MARK: Klockan och pulsen

    /// En gång per sekund medan passet mäter. Avslutar efterperioden (600 s) och ett gammalt pass,
    /// och sparar var 10:e sekund.
    func tick() {
        let nu = Date()
        now = nu
        let före = state.phase
        state.tick(now: nu)
        changed(from: före)
        kollaSteptest(nu)
        if state.wantsPulse, nu.timeIntervalSince(lastSaveAt) >= Self.saveInterval { persistCurrent() }
    }

    /// BESLUT B110 · METOD M62. Ska steptestet stanna nu? Ja vid ett skäl (`StepTest.stopReason`): skälet sparas för
    /// vyn och passet stoppas. Utan känd maxpuls (ett test som tagits upp igen efter en profil som tömts) går testet
    /// bara till sista nivån. Här byts också metronomens takt när nivån byts.
    private func kollaSteptest(_ nu: Date) {
        guard state.phase == .running, let p = state.pass, p.isStepTest else { return }
        let skäl: StepTest.Reason?
        if let max = KonditionModell.shared.maxpuls {
            skäl = StepTest.stopReason(p, now: nu, maxPulse: max)
        } else {
            skäl = nu.timeIntervalSince(p.start) >= StepTest.totalSeconds ? .completed : nil
        }
        if let s = skäl {
            steptestSlut = s
            stop()
        } else {
            metronom.sätt(nivå: StepTest.level(at: nu.timeIntervalSince(p.start)))
        }
    }

    /// BESLUT B110. Metronomen på i fasen running i ett steptest, annars av (stopp, klar och ett pass som tas upp igen).
    private func syncMetronom() {
        guard state.phase == .running, let p = state.pass, p.isStepTest else {
            metronom.sätt(nivå: nil)
            return
        }
        metronom.sätt(nivå: StepTest.level(at: Date().timeIntervalSince(p.start)))
    }

    /// Pulsen från bandet (`Recorder.onPulse`). Varje prov driver också klockan, så att tiderna
    /// håller även när iOS pausar timern med appen i bakgrunden.
    private func received(_ m: HeartRateMeasurement, at tid: Date) {
        let före = state.phase
        state.add(m, now: tid)
        changed(from: före)
    }

    /// BESLUT B107 · METOD M65. En position från telefonen, in i passet (bara i fasen running i ett pass ute;
    /// `PassRecorder.add` släpper annat). En position från före Start (platsen som telefonen sparat) hoppas över.
    private func receivedPoint(_ punkt: TrackPoint) {
        guard let start = state.pass?.start, punkt.t >= start else { return }
        state.add(punkt)
    }

    private func appToBackground() {
        if state.wantsPulse { persistCurrent() }
    }

    private func appBecameActive() {
        if state.wantsPulse { tick() }
        fillFromHistory()
    }

    // MARK: Pulsen ur bandets historik (BESLUT B117, METOD M68)

    /// Fyller sparade pass som har luckor med pulsen ur bandets historik, när den finns i dygnens filer. Anropas när
    /// appen öppnas, när passen lästs in, när ett pass blivit färdigt och när nätterna lästs om (då har dygnens filer
    /// ändrats). Läsningen görs på filkön; ett pass som inte ändras skrivs inte om. Idempotent (`PassHistory.fill`).
    func fillFromHistory() {
        guard !historikPågår else { return }
        let nu = Date()
        let väntar: [Pass] = saved.filter { PassHistory.awaitsHistory($0, now: nu) }
        guard !väntar.isEmpty else { return }
        historikPågår = true
        let sedd = historikSedd
        ioQueue.async { [weak self] in
            var fyllda: [(pass: Pass, sedda: [String: Int])] = []
            for p in väntar {
                let läst = PassHistorik.läs(p, now: nu, sedda: sedd[p.id] ?? [:])
                fyllda.append((PassHistory.fill(p, readings: läst.poster, through: läst.nått), läst.sedda))
            }
            DispatchQueue.main.async { self?.adoptHistory(fyllda) }
        }
    }

    /// Tar emot de fyllda passen: ett pass som ändrats byts i listan och sparas. Ett pass som tagits bort under
    /// läsningen finns inte kvar i listan och hoppas över.
    private func adoptHistory(_ fyllda: [(pass: Pass, sedda: [String: Int])]) {
        historikPågår = false
        var lista = saved
        var ändrad = false
        for f in fyllda {
            historikSedd[f.pass.id] = f.sedda
            guard let i = lista.firstIndex(where: { $0.id == f.pass.id }), lista[i] != f.pass else { continue }
            lista[i] = f.pass
            persist(f.pass)
            ändrad = true
        }
        if ändrad { saved = lista }
    }

    // MARK: Förslag (BESLUT B121, METOD M69)

    /// Letar pass i bandets historik för de två senaste dygnen och visar dem som förslag, med knuten K3 (BESLUT B151):
    /// pulsen mot dygnets egen nivå och ihållande rörelse, så varken vilopuls eller maxpuls behövs (B121 krävde dem).
    /// Läsningen görs på filkön; ett förslag som tagits bort kommer inte tillbaka.
    func hittaFörslag() {
        // BESLUT B152. Inte medan ett pass går: förslagen läser två dygns rådygn, och passet behöver telefonen.
        guard !förslagPågår, state.phase != .running else { return }
        förslagPågår = true
        var passen: [Pass] = saved
        if let p = state.pass { passen.append(p) }
        let lager: PassSuggestions.Store = förslagslager
        ioQueue.async { [weak self] in
            let läst = PassForslag.sekunder(now: Date())
            let hittade: [PassDetection.Candidate] = PassSuggestions.knotSuggestions(
                seconds: läst.sekunder, passes: passen, store: lager)
            let nyast: [PassDetection.Candidate] = hittade.sorted {
                (a: PassDetection.Candidate, b: PassDetection.Candidate) -> Bool in a.startMinute > b.startMinute
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.förslag = nyast
                self.förslagsposter = läst.poster
                self.förslagPågår = false
            }
        }
    }

    /// BESLUT B150. Bandets poster för ett förslag med valda tider: fönstret och efterperioden, med en minut på var sida.
    private func posterFör(start: Date, stopp: Date) -> [PassHistory.Reading] {
        let från: Int = Int(start.timeIntervalSince1970) - 60
        let till: Int = Int(stopp.timeIntervalSince1970 + PassRules.afterSeconds) + 60
        guard från <= till else { return [] }
        return förslagsposter.filter { (r: PassHistory.Reading) -> Bool in (från...till).contains(r.time) }
    }

    /// BESLUT B150. Förslaget som pass med valda tider och märkning, för talen i bladet; `nil` utan bandets poster.
    func förhandsvisa(_ f: PassDetection.Candidate, val: PassForslagsval) -> Pass? {
        guard !förslagsposter.isEmpty else { return nil }
        return PassSuggestions.pass(from: f, kind: val.label.kind, readings: posterFör(start: val.start, stopp: val.stopp),
                                    label: val.label, start: val.start, stop: val.stopp)
    }

    /// Lägger ett förslag till som ett pass med vald märkning och valda tider, sparat som ett färdigt pass med förslaget
    /// som det var (`suggested`, BESLUT B150), och tar bort förslaget ur listan.
    func läggTill(_ f: PassDetection.Candidate, val: PassForslagsval) {
        let p: Pass = PassSuggestions.pass(from: f, kind: val.label.kind,
                                           readings: posterFör(start: val.start, stopp: val.stopp),
                                           label: val.label, start: val.start, stop: val.stopp)
        persist(p)
        saved = Self.newestFirst(saved.filter { $0.id != p.id } + [p])
        förslag.removeAll { $0 == f }
    }

    /// Tar bort ett förslag för gott.
    func taBortFörslag(_ f: PassDetection.Candidate) {
        förslagslager.dismiss(f)
        let lager: PassSuggestions.Store = förslagslager
        ioQueue.async { PassForslag.skriv(lager) }
        förslag.removeAll { $0 == f }
    }

    /// Fasen byttes: slå på eller av pulsen och timern, spara, och lägg ett färdigt pass i listan.
    private func changed(from före: PassRecorder.Phase) {
        let efter = state.phase
        guard före != efter else { return }
        switch efter {
        case .running, .after:
            beginMeasuring()
            persistCurrent()
        case .done:
            endMeasuring()
            if let p = state.finished {
                persist(p)
                saved = Self.newestFirst(saved.filter { $0.id != p.id } + [p])
                // BESLUT B117. Historiken för passet kan redan finnas (bandet synkade under efterperioden).
                fillFromHistory()
            }
            // Passet är sparat och visas i listan: tillbaka till vila.
            state.clear()
        case .idle:
            endMeasuring()
        }
        syncPlats()
        syncImu()
        syncMetronom()
        UIApplication.shared.isIdleTimerDisabled = state.wantsPulse
    }

    /// BESLUT B107 · BESLUT B110. Platsen på i fasen running i ett pass ute, annars av: stopp, klar och ett
    /// pass som tas upp igen efter en omstart (`adopt` → `changed`) går alla genom här.
    private func syncPlats() {
        let ska: Bool = state.phase == .running && (state.pass?.isOutdoor ?? false)
        if ska, !platsOn {
            platsOn = true
            plats.start()
        } else if !ska, platsOn {
            platsOn = false
            plats.stop()
        }
    }

    /// BESLUT B147 · METOD M84. Rörelsen i 100 Hz på från Start till Stopp, för alla slag av pass; av i efterperioden,
    /// vid klar och när ett pass som tas upp igen redan är i efterperioden (`adopt` → `changed`).
    private func syncImu() {
        let ska: Bool = state.phase == .running
        if ska, !imuOn {
            imuOn = true
            Recorder.shared.startPassImu()
        } else if !ska, imuOn {
            imuOn = false
            Recorder.shared.stopPassImu()
        }
    }

    private func beginMeasuring() {
        if !pulseOn {
            pulseOn = true
            Recorder.shared.onPulse = { [weak self] m, tid in self?.received(m, at: tid) }
            Recorder.shared.startPulse()
        }
        if timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            // Går också medan en lista rullas.
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func endMeasuring() {
        timer?.invalidate()
        timer = nil
        if pulseOn {
            pulseOn = false
            Recorder.shared.onPulse = nil
            Recorder.shared.stopPulse()
        }
    }

    // MARK: Filerna

    private static func newestFirst(_ pass: [Pass]) -> [Pass] {
        pass.sorted { (a: Pass, b: Pass) -> Bool in a.start > b.start }
    }

    private func persistCurrent() {
        guard let p = state.pass else { return }
        persist(p)
    }

    /// Skriver passet (atomiskt, med skyddsklassen) på filkön. Namnet väljs en gång per pass.
    private func persist(_ pass: Pass) {
        lastSaveAt = Date()
        let namn: String
        if let n = fileNames[pass.id] {
            namn = n
        } else {
            namn = PassFile.fileName(start: pass.start)
            fileNames[pass.id] = namn
        }
        ioQueue.async { [weak self] in
            do {
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true,
                                                        attributes: [.protectionKey: NightFiles.protection])
                let data = try PassFile.encode(pass)
                try data.write(to: Self.folder.appendingPathComponent(namn),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                DispatchQueue.main.async { self?.problem = "Kunde inte spara passet." }
            }
        }
    }

    /// Läser passen ur mappen (på filkön) och tar upp ett osparat pågående pass igen.
    private func load() {
        ioQueue.async { [weak self] in
            let filer = PassFile.entries(in: Self.folder)
            DispatchQueue.main.async { self?.adopt(filer) }
        }
    }

    /// Färdiga pass blir listan. Ett osparat pass (inget slut) tas upp igen och mäter vidare om det
    /// fortfarande pågår (`PassRecorder.restore`); ett som hunnit bli gammalt avslutas och sparas, och fler
    /// än ett osparat pass (bara det nyaste kan pågå) stängs vid stopp eller sista provet.
    private func adopt(_ filer: [(url: URL, pass: Pass)]) {
        for f in filer { fileNames[f.pass.id] = f.url.lastPathComponent }
        var lista: [Pass] = filer.map { $0.pass }.filter { $0.isFinished }
        var osparade: [Pass] = filer.map { $0.pass }.filter { !$0.isFinished }
        if state.phase == .idle, !osparade.isEmpty {
            let nyast = osparade.removeFirst()
            var r = PassRecorder()
            r.restore(nyast, now: Date())
            if let klart = r.finished {
                persist(klart)
                lista.append(klart)
            } else {
                state = r
                now = Date()
                changed(from: .idle)
            }
        }
        for p in osparade {
            let stängt = p.closed()
            persist(stängt)
            lista.append(stängt)
        }
        // Pass som blev färdiga medan listan lästes ligger redan i `saved`.
        let nya: [Pass] = lista.filter { (p: Pass) -> Bool in !saved.contains { $0.id == p.id } }
        saved = Self.newestFirst(saved + nya)
        // BESLUT B117. Pass med luckor fylls ur bandets historik när den finns.
        fillFromHistory()
    }
}
