import CoreBluetooth
import Foundation
import HeartRate
import Night
import UIKit
import WhoopFrames

/// En dygnsfil i listan: stammen (`dygn-yyyy-MM-dd`) och filernas storlek.
/// `bytes` är allt dygnet tar på telefonen: rådygnet och arkivet (BESLUT B41).
struct DayFile: Identifiable, Equatable {
    var stem: String
    var bytes: Int
    var rawBytes = 0
    var archiveBytes = 0
    var id: String { stem }
}

/// METOD M12 · METOD M27 · BESLUT B14 · BESLUT B15 · BESLUT B28 · BESLUT B30 · BESLUT B58 · BESLUT B61
/// Lyssnaren (PLAN.md A1): ingen knapp. När ett band är känt håller appen en
/// stående anslutning till det och sparar allt som kommer på Whoops
/// karakteristiker (`…0003`, `…0004`, `…0005`, `…0007`) rått i en dygnsfil per
/// lokalt datum (`DayLog`). Pulsen används bara under ett pass (BESLUT B58,
/// B61): `startPulse` slår på bandets realtidspuls (kommando 3, `PulseControl`)
/// och prenumererar på 2A37 som reserv, `stopPulse` slår av båda, och pulsen går
/// till passet (`onPulse`). Realtidspulsens råa ramar (typ 40) sparas i
/// dygnsfilen som allt annat från Whoops karakteristiker; 2A37 gör det aldrig.
/// Appen skriver aldrig till bandet av sig själv (BESLUT B14).
///
/// Överlever att iOS stänger appen: centralen skapas med ett återställnings-id
/// (state restoration), och bakgrundsläget `bluetooth-central` står i
/// project.yml. Det kopplade bandet har alltid en väntande `connect` hos iOS,
/// utan tidsgräns; när bandet hörs av igen väcker iOS appen, `willRestoreState`
/// lämnar tillbaka bandet, och prenumerationen läggs på igen. Varje notis
/// skrivs till filen direkt (en `write` per rad), så att en notis inte går
/// förlorad om appen avslutas.
///
/// BESLUT B25 · METOD M23. På användaren knapptryck (Bandkontroll) hämtar den
/// också bandets historik och kvitterar den: hälsning, begäran och kvittens
/// skrivs bara genom `BandSender`, och en bit kvitteras först när den är
/// sparad i dygnsfilen. Den passiva lyssningen skriver aldrig.
///
/// BESLUT B53 · METOD M43. IMU-provet (Bandkontroll): på användaren knapptryck
/// slås bandets rörelse i 100 Hz på en begränsad stund (`ImuControl`). Ramarna
/// sparas råa i dygnsfilen som allt annat. Skyddet skickar stoppet (82, 106 av)
/// även utan knapptryck när rörelse i realtid kommer utan prov — det enda
/// Idunn skriver av sig själv, utöver stoppet av passets puls när appen dog
/// under ett pass (BESLUT B61).
///
/// Allt körs på huvudkön (`queue: nil`), så delegaterna och vyerna delar tråd.
final class Recorder: NSObject, ObservableObject {
    static let shared = Recorder()

    enum Link: Equatable {
        case idle, bluetoothOff, unauthorized, searching, connecting, connected

        /// METOD M29. Bluetooths läge som Morgon bedömer det.
        var bluetooth: ListenerCheck.Bluetooth {
            switch self {
            case .bluetoothOff: return .off
            case .unauthorized: return .notAllowed
            default: return .ok
            }
        }
    }

    @Published private(set) var link: Link = .idle
    /// Senast lästa batterinivån, procent.
    @Published private(set) var battery: Int?
    /// METOD M12 · BESLUT B14. T2: antal ramar sedan appen startade, och vilka
    /// karakteristiker som prenumereras.
    @Published private(set) var tally = FrameTally()
    @Published private(set) var listening: Set<String> = []
    /// METOD M27. Senaste K18, senaste Whoop-synk och K18-minuterna.
    @Published private(set) var status = ListenerStatus()
    /// METOD M29. Statusen är läst ur dygnsfilerna (de är krypterade tills
    /// första upplåsningen efter en omstart); före det vet den ingenting och
    /// Morgon säger inget om tystnad.
    @Published private(set) var statusRead = false
    /// Rader som väntar på att dygnsfilen ska gå att skriva (telefonen låst
    /// sedan omstart, skyddsklassen). Normalt 0.
    @Published private(set) var unsaved = 0
    @Published private(set) var summaries: [NightSummary] = []
    /// METOD M55 · BESLUT B70. användaren ändringar av sömnperioden, och om en ändrad natt räknas om just nu.
    @Published private(set) var sleepEdits = SleepEdits()
    @Published private(set) var recomputingEdit = false
    @Published private(set) var days: [DayFile] = []
    /// METOD M34 · BESLUT B41. Vad råa dygn, arkiv och resultat väger.
    @Published private(set) var storage = StorageUsage()
    /// METOD M20. Senaste märket, och antalet (för känseln).
    @Published private(set) var lastMarker: RecordingLog.Marker?
    @Published private(set) var markerCount = 0
    @Published var problem: String?
    /// BESLUT B25 · METOD M23. Hämtningen: pågår, hur långt, hur den slutade.
    @Published private(set) var fetching = false
    @Published private(set) var fetchState: HistorySession.State?
    @Published private(set) var fetchProgress = HistorySession.Progress()
    @Published private(set) var fetchOutcome: HistorySession.Outcome?
    /// BESLUT B53 · METOD M43. IMU-provet: läget, antalen och skyddets stopp.
    @Published private(set) var imuPhase: ImuControl.Phase = .off
    @Published private(set) var imuProgress = ImuControl.Progress()
    @Published private(set) var imuFailsafeStops = 0

    // METOD M1. Bluetooths batteritjänst.
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    // METOD M12. Whoops egen tjänst och de fyra notify-karakteristikerna.
    // Skrivkarakteristiken …0002 söks bara under en hämtning (BESLUT B25).
    static let whoopService = CBUUID(string: RawFrame.service)
    static let whoopListened = RawFrame.listened.map { CBUUID(string: $0) }
    // Pulstjänsten 180D används för att hitta ett band som Whoop-appen redan är
    // ansluten till, och prenumereras bara under ett pass (BESLUT B58): lyssnaren
    // använder den aldrig (BESLUT B28).
    private static let heartRateService = CBUUID(string: "180D")
    // METOD M1 · BESLUT B58. Heart Rate Measurement, pulsnotisen under ett pass.
    private static let heartRateMeasurement = CBUUID(string: "2A37")

    // Strängarna ändras aldrig (BESLUT B9): de är nycklarna till redan sparade värden.
    static let restoreIdentifier = "se.birdiebook.idun.natt"
    private enum Key {
        static let band = "idun.band"
        /// Före A1 en pågående inspelning. Inspelningsknappen finns inte längre;
        /// nyckeln rensas vid start.
        static let activeNight = "idun.aktivNatt"
        /// BESLUT B53. Ett IMU-prov pågick: stoppet skickas vid nästa start.
        static let imuArmed = "idun.imuProv"
        /// BESLUT B61. Passets realtidspuls var på: stoppet skickas vid nästa start.
        static let pulseArmed = "idun.passPuls"
        /// PLAN.md A3. Förra hämtningens början och slut (`AutoFetch.State`, JSON).
        static let autoFetch = "idun.autoHamtning"
    }

    /// PLAN.md A3. Reglaget "Whoop-appen är borta" på Data. Av som förval: då skriver Idunn aldrig till bandet av sig
    /// självt. Nyckeln ändras aldrig (BESLUT B9).
    static let utanWhoopKey = "idun.utanWhoop"

    private var central: CBCentralManager?
    private var band: CBPeripheral?
    private var batteryCharacteristic: CBCharacteristic?
    private let defaults = UserDefaults.standard

    // METOD M27. Dygnsfilen.
    private var cursor = DayLog.Cursor()
    private var frameFile: AppendFile?
    private var sideFile: AppendFile?
    private var closedFailures = 0
    private var pending: [Data] = []
    private static let pendingLimit = 5000
    private var liveStatus = ListenerStatus()
    private var liveTally = FrameTally()
    private var publishedAt = Date.distantPast
    private var publishScheduled = false
    private var syncedAt = Date.distantPast
    private var seeded = false
    private var computingNights = false
    /// METOD M55. En ändring kom medan nätterna räknades: räkna en gång till när den räkningen är klar.
    private var computeAgain = false

    // BESLUT B25 · METOD M23. Hämtningens delar.
    static let fetchMarker = "hämtning"
    private var session: HistorySession?
    private var stream = FrameAssembly.Stream()
    private var commandCharacteristic: CBCharacteristic?
    private var fetchFailuresAtStart = 0
    private var fetchTimer: Timer?
    // PLAN.md A3. Den automatiska hämtningen: tillståndet mellan starter, när regeln senast prövades och en klocka
    // medan appen är vaken.
    private var autoState = AutoFetch.State()
    private var autoConsideredAt = Date.distantPast
    private var autoTimer: Timer?
    /// Varför hämtningen som pågår startade; `nil` = knappen.
    private var fetchReason: AutoFetch.Reason?

    // BESLUT B53 · METOD M43. IMU-provets delar. Ramarna fogas ihop hela tiden
    // (`liveStream`), så att svaren och skyddet ser varje ram.
    private var imu = ImuControl(now: Date())
    private var liveStream = FrameAssembly.Stream()
    private var imuTimer: Timer?
    private var imuArmedSaved = false
    private var channelRequestedAt = Date.distantPast
    // METOD M43. Karakteristikerna vars notiser begärts i den här anslutningen,
    // och om "tjänster klara" redan skrivits för den.
    private var notifyRequested = Set<String>()
    private var servicesLogged = false

    // BESLUT B58 · METOD M47. Pulsen på begäran under ett pass.
    /// Tar emot varje pulsnotis medan pulsen önskas (`startPulse`): notisen och tiden den kom.
    /// Sätts av passet (`PassController`); anropas på huvudkön.
    var onPulse: ((HeartRateMeasurement, Date) -> Void)?
    private var pulseWanted = false
    private var pulseCharacteristic: CBCharacteristic?
    // BESLUT B61 · METOD M48. Bandets realtidspuls (kommando 3). 2A37 är reserven: en
    // 2A37-puls går till passet bara när ingen realtidspuls kommit på `realtimeHoldoff`.
    private var pulse = PulseControl(now: Date())
    private var pulseTimer: Timer?
    private var pulseArmedSaved = false
    private var lastRealtimePulseAt = Date.distantPast
    // BESLUT B116 · METOD M67. Reserven 2A37 i antal (notiser, och de som gick till passet), och märkena
    // om passets puls som skrivs en gång per pass. Bara under ett pass; inga mätvärden.
    private var reservePulses = 0
    private var reservePulsesUsed = 0
    private var pulseNotes: Set<String> = []
    private static let realtimeHoldoff: TimeInterval = 5
    /// Vem som skrev senast, så att ett skrivfel går till rätt maskin.
    private enum Writer { case fetch, imu, pulse }
    private var lastWriter: Writer = .fetch

    override init() {
        super.init()
        defaults.removeObject(forKey: Key.activeNight)
        // BESLUT B53. Appen dog under ett IMU-prov: stoppet går när bandet hörs.
        if defaults.bool(forKey: Key.imuArmed) {
            imu = ImuControl(now: Date(), stopAtStart: true)
            imuArmedSaved = true
            publishImu()
        }
        // BESLUT B61. Appen dog under ett pass: realtidspulsens stopp går när bandet hörs.
        if defaults.bool(forKey: Key.pulseArmed) {
            pulse = PulseControl(now: Date(), stopAtStart: true)
            pulseArmedSaved = true
            publishPulse()
        }
        // Centralen skapas direkt, före första vyn: när iOS väcker appen i
        // bakgrunden för bandet (state restoration) måste den finnas. Inte i
        // provet (IdunnProv körs inuti appen): där finns inget band, och frågan
        // om Bluetooth ska inte ligga över skärmbilderna.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { makeCentral() }
        NotificationCenter.default.addObserver(self, selector: #selector(syncFiles),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate),
                                               name: UIApplication.willTerminateNotification, object: nil)
        reloadSummaries()
        seedStatus()
        // PLAN.md A3. Den automatiska hämtningen: förra hämtningens tider, och regeln en gång i minuten medan appen
        // är vaken (i bakgrunden bara när iOS väckt den).
        loadAutoState()
        autoTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.considerAutoFetch()
        }
        // PLAN.md A3. Startad i bakgrunden = väckt för bandet; i förgrunden = användaren öppnade appen.
        logEvent(.appStarted, text: UIApplication.shared.applicationState == .background ? "i bakgrunden" : nil)
    }

    // MARK: Dygnsfilen

    /// Skrivfel hittills i dygnsfilerna (de som stängts och den som är öppen).
    private var framesFailures: Int { closedFailures + (frameFile?.failures ?? 0) }

    /// METOD M27. Följer klockan och zonen: öppnar dygnets filer, byter vid
    /// midnatt, och skriver en zonrad när zonen ändras inom dygnet.
    private func ensureDay(at now: Date) {
        let zone = TimeZone.current.secondsFromGMT(for: now)
        switch cursor.advance(to: now, utcOffsetSeconds: zone) {
        case .file(let stem, let offset):
            closeDay()
            openDay(stem: stem, zone: offset, at: now)
        case .zone(let offset):
            sideFile?.append(RecordingLog.zoneChange(utcOffsetSeconds: offset, at: now))
        case .none:
            // Förra försöket att öppna misslyckades (filen krypterad tills första upplåsningen).
            if frameFile == nil, let stem = cursor.stem { openDay(stem: stem, zone: zone, at: now) }
        }
    }

    private func openDay(stem: String, zone: Int, at now: Date) {
        do {
            try NightFiles.prepareFolder()
            let nySida = !FileManager.default.fileExists(atPath: NightFiles.pulse(stem).path)
            let side = try AppendFile(url: NightFiles.pulse(stem))
            let frames = try AppendFile(url: NightFiles.frames(stem))
            // En ny dygnsfil får zonen i huvudet; en som öppnas igen (omstart,
            // en resa tillbaka till ett datum) får en zonrad med tid.
            side.append(nySida ? RecordingLog.header(utcOffsetSeconds: zone)
                               : RecordingLog.zoneChange(utcOffsetSeconds: zone, at: now))
            sideFile = side
            frameFile = frames
        } catch {
            sideFile = nil
            frameFile = nil
        }
    }

    private func closeDay() {
        guard frameFile != nil || sideFile != nil else { return }
        if let f = frameFile { closedFailures += f.failures }
        frameFile?.close()
        sideFile?.close()
        frameFile = nil
        sideFile = nil
        // BESLUT B41. Dygnet som just blev färdigt arkiveras (efter marginalen).
        reloadSummaries()
    }

    /// Skriver notisen till dygnets fil. Går filen inte att öppna väntar raden
    /// i minnet (högst `pendingLimit`) och skrivs när den går.
    private func save(_ f: RawFrame) {
        ensureDay(at: f.time)
        let rad = RawFrameLog.line(f)
        guard let file = frameFile else {
            pending.append(rad)
            if pending.count > Self.pendingLimit { pending.removeFirst(pending.count - Self.pendingLimit) }
            return
        }
        if !pending.isEmpty {
            for p in pending { file.append(p) }
            pending.removeAll()
        }
        file.append(rad)
        // Skrivs ned till disken (fsync) högst var 30:e sekund; själva raden
        // är redan hos operativsystemet efter `write`.
        if f.time.timeIntervalSince(syncedAt) >= 30 {
            _ = file.sync()
            syncedAt = f.time
        }
    }

    @objc private func syncFiles() {
        _ = frameFile?.sync()
        _ = sideFile?.sync()
    }

    /// METOD M20. Ett märke i dygnets sidofil, med telefonens tid. Inget
    /// skickas till bandet.
    func mark(_ label: String) {
        let now = Date()
        ensureDay(at: now)
        guard let file = sideFile else {
            problem = "Kunde inte skriva märket."
            return
        }
        let m = RecordingLog.Marker(time: now, label: label)
        file.append(RecordingLog.marker(m.label, at: m.time))
        lastMarker = m
        markerCount += 1
    }

    /// PLAN.md A3. En händelse i appen (start, väckt av iOS, förgrund, bakgrund, nätter räknade) i dygnets sidofil,
    /// som länkens händelser: så att en natt utan Whoop-appen går att följa i efterhand. På huvudkön. Inte i provet
    /// (IdunnProv körs inuti appen): en dygnsfil i appens mapp får provet av appens väg att hoppa över sig självt.
    func logEvent(_ l: RecordingLog.Link, text: String? = nil) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        logLink(l, text: text)
    }

    /// METOD M43. En händelse på länken i dygnets sidofil, bredvid märkena:
    /// ordet, och för ett fel dess kod och systemets text. Inga mätvärden.
    private func logLink(_ l: RecordingLog.Link, error: Error? = nil, text: String? = nil) {
        let now = Date()
        ensureDay(at: now)
        let fel = error.map { $0 as NSError }
        sideFile?.append(RecordingLog.link(l, code: fel?.code, text: fel?.localizedDescription ?? text, at: now))
    }

    // MARK: Status

    /// Läser de tre senaste dygnsfilerna för statusen (senaste K18, synk och
    /// täckning) och slår ihop dem med det som hörts sedan appen startade.
    /// Filerna är krypterade tills första upplåsningen: går de inte att läsa
    /// försöker `refresh` igen.
    private func seedStatus() {
        DispatchQueue.global(qos: .utility).async {
            var inläst = ListenerStatus()
            var läst = true
            for stem in NightFiles.dayStems().prefix(3).reversed() {
                // BESLUT B41. Ett dygn vars rådygn är raderat läses ur arkivet.
                guard let data = NightFiles.dayData(stem)?.frames else {
                    läst = false
                    continue
                }
                inläst.read(log: data)
            }
            DispatchQueue.main.async {
                self.seeded = läst
                self.statusRead = läst
                self.liveStatus.merge(inläst)
                self.status = self.liveStatus
            }
        }
    }

    /// Vyn blev synlig: läs listorna igen, och statusen om den inte kunde läsas.
    func refresh() {
        reloadSummaries()
        if !seeded { seedStatus() }
        considerAutoFetch(force: true)
    }

    // MARK: Den automatiska hämtningen (PLAN.md A3)

    var utanWhoop: Bool { defaults.bool(forKey: Self.utanWhoopKey) }

    private func loadAutoState() {
        if let data = defaults.data(forKey: Key.autoFetch),
           let s = try? JSONDecoder().decode(AutoFetch.State.self, from: data) { autoState = s }
    }

    private func saveAutoState() {
        if let data = try? JSONEncoder().encode(autoState) { defaults.set(data, forKey: Key.autoFetch) }
    }

    /// Prövar regeln (`AutoFetch.decide`) och startar en hämtning när den säger till. Anropas när tjänsterna blivit
    /// klara efter en anslutning, vid varje notis från bandet (batteriets procent väcker appen under natten), när
    /// appen öppnas och varje minut medan den är vaken; högst var 20:e sekund utom vid anslutning och öppning.
    func considerAutoFetch(justConnected: Bool = false, force: Bool = false) {
        let nu = Date()
        guard force || justConnected || nu.timeIntervalSince(autoConsideredAt) >= 20 else { return }
        autoConsideredAt = nu
        let redo: Bool = band?.state == .connected && listening.contains("fd4b0003") && listening.contains("fd4b0005")
        guard let skäl = AutoFetch.decide(enabled: utanWhoop, bandReady: redo, busy: fetching || imu.isArmed,
                                          justConnected: justConnected, now: nu, state: autoState) else { return }
        startFetch(automatic: skäl)
    }

    private func publishSoon(_ now: Date) {
        if now.timeIntervalSince(publishedAt) >= 2 {
            publishNow(now)
        } else if !publishScheduled {
            publishScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.publishScheduled = false
                self?.publishNow(Date())
            }
        }
    }

    private func publishNow(_ now: Date) {
        tally = liveTally
        status = liveStatus
        unsaved = pending.count
        publishedAt = now
    }

    // MARK: Nätterna och dygnen

    /// Läser listorna igen: gamla inspelningar, dygnen och de redan räknade
    /// nätterna ur K18 (snabbt), och räknar sedan de nätter som är dags att
    /// räkna (`computeNights`, långsamt).
    func reloadSummaries() {
        // Dygnen som skrivs just nu arkiveras inte: dagens datum och filen som är öppen.
        let pågår: Set<String> = Set([activeDay] + (cursor.stem.map { [$0] } ?? []))
        DispatchQueue.global(qos: .utility).async {
            // BESLUT B41. Färdiga dygn arkiveras, och rådygn äldre än 14 dagar
            // raderas när arkivet är kontrollerat. Dygn kopieras inte längre
            // till Documents (BESLUT B22); gamla inspelningar gör det fortfarande.
            DayArchiver.run(skip: pågår)
            NightExport.mirror()
            let gamla: [NightSummary] = NightFiles.stems().compactMap(NightSummary.load)
            let k18: [NightSummary] = K18Nights.summaries()
            let d = NightFiles.dayStems().map { (stem: String) -> DayFile in
                DayFile(stem: stem, bytes: NightFiles.size(stem), rawBytes: NightFiles.rawSize(stem),
                        archiveBytes: NightFiles.archiveSize(stem))
            }
            let lagring = StorageUsage.measure()
            let ändringar: SleepEdits = SleepEditFile.load()
            DispatchQueue.main.async {
                self.sleepEdits = ändringar
                self.summaries = Recorder.chosen(k18: k18, old: gamla)
                self.days = d
                self.storage = lagring
                self.computeNights()
            }
        }
    }

    /// METOD M28. Räknar nätterna ur K18 som är dags att räkna (`NightLedger`)
    /// på en bakgrundskö, en i taget, och publicerar listan när något ändrats.
    /// Bara en räkning åt gången; en öppning under tiden startar ingen till.
    private func computeNights() {
        guard !computingNights else {
            // METOD M55. En ändring som sparades under räkningen kanske inte hann läsas: en gång till efteråt.
            if recomputingEdit { computeAgain = true }
            return
        }
        computingNights = true
        DispatchQueue.global(qos: .utility).async {
            let ändrat = K18Nights.computeDue()
            let gamla = NightFiles.stems().compactMap(NightSummary.load)
            let k18 = ändrat ? K18Nights.summaries() : []
            DispatchQueue.main.async {
                self.computingNights = false
                if ändrat {
                    self.summaries = Recorder.chosen(k18: k18, old: gamla)
                    self.logEvent(.nightsComputed)
                }
                if self.computeAgain {
                    self.computeAgain = false
                    self.computeNights()
                } else {
                    self.recomputingEdit = false
                }
            }
        }
    }

    /// METOD M55 · BESLUT B70. Sparar användaren ändring av sömnperioden för dagen (`nil` = Återställ) och räknar om
    /// natten: `NightLedger` ser att posten räknades med en annan ändring, och Morgon, Natten, Över tid och
    /// sömnbehovet får den nya natten när listan publiceras. Bandets data rörs inte.
    func setSleepEdit(_ edit: SleepEdit?, day: WakeDay) {
        recomputingEdit = true
        DispatchQueue.global(qos: .userInitiated).async {
            let alla: SleepEdits = SleepEditFile.load()
            let nya: SleepEdits = edit.map { (e: SleepEdit) -> SleepEdits in alla.setting(e) } ?? alla.removing(day)
            SleepEditFile.save(nya)
            DispatchQueue.main.async {
                self.sleepEdits = nya
                self.recomputingEdit = true
                self.computeNights()
            }
        }
    }

    /// METOD M28 · BESLUT B48. Nätterna som vyerna ser: alla, nyaste först,
    /// utom en natt ur K18 som bandet hörde för lite av när en gammal
    /// inspelning finns samma dag. Då gäller inspelningen (`NightChoice`, provat
    /// i IdunnKit); vyerna väljer sedan en natt per dag som förut
    /// (`NightSummary.preferred`, `Trends.idunPerDay`). Inte privat: provet
    /// (IdunnProv) går appens väg genom den.
    static func chosen(k18: [NightSummary], old: [NightSummary]) -> [NightSummary] {
        let alla: [NightSummary] = k18 + old
        let kandidater: [NightChoice.Candidate] = alla.compactMap { (s: NightSummary) -> NightChoice.Candidate? in
            guard let dag = s.wakeDay else { return nil }
            return NightChoice.Candidate(id: s.id, day: dag, source: s.origin, coverage: s.coverage,
                                         validWindows: s.validWindows)
        }
        let viker: Set<String> = NightChoice.outvoted(kandidater)
        return newestFirst(alla.filter { (s: NightSummary) -> Bool in !viker.contains(s.id) })
    }

    private static func newestFirst(_ alla: [NightSummary]) -> [NightSummary] {
        alla.sorted { (a: NightSummary, b: NightSummary) -> Bool in
            (a.titleDate ?? .distantPast) > (b.titleDate ?? .distantPast)
        }
    }

    /// Tar bort en gammal inspelning. En natt ur K18 har ingen fil att ta bort:
    /// den räknas ur dygnsfilerna (BESLUT B30).
    func delete(_ s: NightSummary) {
        guard s.origin != .k18 else { return }
        NightFiles.delete(s.stem)
        summaries.removeAll { $0.stem == s.stem }
    }

    /// Dygnet som skrivs just nu går inte att ta bort.
    func delete(_ d: DayFile) {
        guard d.stem != activeDay, d.stem != cursor.stem else { return }
        NightFiles.delete(d.stem)
        days.removeAll { $0.stem == d.stem }
    }

    /// Dygnet som växer just nu: dagens lokala datum efter klockan, också före
    /// dagens första notis. Det kopieras inte till Documents och tas inte bort.
    var activeDay: String {
        DayLog.stem(for: Date(), utcOffsetSeconds: TimeZone.current.secondsFromGMT())
    }

    // MARK: Hitta bandet

    private func makeCentral() {
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier])
    }

    private var rememberedBand: UUID? {
        defaults.string(forKey: Key.band).flatMap(UUID.init(uuidString:))
    }

    /// Ansluter till bandet, eller börjar leta om inget band är känt. Bandet vi
    /// kände förra gången ansluts direkt på sitt id: `connect` ligger kvar hos
    /// iOS tills bandet hörs, även med appen i bakgrunden. Första gången:
    /// (1) en Whoop som redan är ansluten till telefonen (Whoop-appen), (2) sök.
    private func find() {
        guard let c = central, c.state == .poweredOn else { return }
        if let id = rememberedBand, let p = c.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
            return
        }
        let anslutna = c.retrieveConnectedPeripherals(withServices: [Self.whoopService])
        let pulsband = c.retrieveConnectedPeripherals(withServices: [Self.heartRateService])
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains("whoop") }
        if let p = anslutna.first ?? pulsband.first {
            connect(p)
            return
        }
        link = .searching
        c.scanForPeripherals(withServices: [Self.whoopService, Self.heartRateService], options: nil)
    }

    /// Lägger en väntande anslutning (utan tidsgräns) på bandet.
    private func connect(_ p: CBPeripheral) {
        central?.stopScan()
        band = p
        p.delegate = self
        if p.state == .connected {
            didConnect(p)
        } else {
            link = .connecting
            central?.connect(p, options: nil)
        }
    }

    /// Tar upp lyssnandet igen från vad tillståndet än är: efter start,
    /// återställning, Bluetooth på igen och när en hämtning behöver bandet.
    private func resumeListening() {
        guard let c = central, c.state == .poweredOn else { return }
        guard let b = band else {
            find()
            return
        }
        switch b.state {
        case .connected: didConnect(b)
        case .connecting: link = .connecting
        default: connect(b)
        }
    }

    private func didConnect(_ p: CBPeripheral) {
        link = .connected
        defaults.set(p.identifier.uuidString, forKey: Key.band)
        p.discoverServices(servicesToDiscover)
    }

    /// Tjänsterna som söks: batteriet och Whoops egen alltid, pulstjänsten bara när ett pass vill ha pulsen
    /// (BESLUT B58). Vid en återanslutning medan pulsen önskas läggs prenumerationen alltså på igen.
    private var servicesToDiscover: [CBUUID] {
        pulseWanted ? [Self.batteryService, Self.whoopService, Self.heartRateService]
                    : [Self.batteryService, Self.whoopService]
    }

    // MARK: Notiserna

    private func received(battery data: Data) {
        guard let level = data.first.map({ Int($0) }) else { return }
        battery = level
        // PLAN.md A3. Batteriets procent kommer som notis ungefär var 20:e–30:e minut under natten och väcker appen.
        considerAutoFetch()
    }

    /// METOD M12 · BESLUT B14. Rå kopia av det bandet skickar. Sparas först,
    /// och först därefter går notisen till hämtningens session, så att allt som
    /// en kvittens gäller redan står i filen (METOD M23).
    private func received(frame data: Data, from uuid: CBUUID) {
        let f = RawFrame(time: Date(), characteristic: uuid.uuidString, bytes: [UInt8](data))
        save(f)
        liveTally.add(f)
        liveStatus.add(f)
        publishSoon(f.time)
        // PLAN.md A3. En notis väcker appen: dags att hämta?
        considerAutoFetch()
        // BESLUT B53. IMU-provets svar och skyddet. Varje ram driver också
        // klockan, så att tidsgränsen håller även när iOS pausar timern.
        if let hel = liveStream.add(f) {
            runImu(imu.receive(hel, now: f.time))
            // BESLUT B61. Passets realtidspuls (typ 40) och svaren på kommando 3.
            runPulse(pulse.receive(hel, now: f.time))
        }
        if imu.isArmed || imu.wantsWrite { tickImu() }
        if pulse.isArmed { tickPulse() }
        guard fetching else { return }
        if let frame = stream.add(f), let actions = session?.receive(frame, now: f.time) { run(actions) }
    }

    // MARK: Hämtningen

    /// BESLUT B25 · METOD M23. Hämtar bandets historik och kvitterar den, på
    /// användaren knapptryck eller (PLAN.md A3, reglaget på) när `AutoFetch` säger
    /// till. Allt som kommer sparas i dygnsfilen som annars; ett märke "hämtning"
    /// i sidofilen visar var det började.
    func startFetch(automatic skäl: AutoFetch.Reason? = nil) {
        // BESLUT B53. Inte medan ett IMU-prov går: svaren och rörelsen skulle blandas in.
        guard !fetching, !imu.isArmed else { return }
        let now = Date()
        ensureDay(at: now)
        guard frameFile != nil, let side = sideFile else {
            problem = "Kunde inte skapa dygnets fil."
            return
        }
        side.append(RecordingLog.marker(Self.fetchMarker, at: now))
        fetchReason = skäl
        autoState.started(at: now)
        saveAutoState()
        fetchFailuresAtStart = framesFailures
        session = HistorySession(now: now)
        stream = FrameAssembly.Stream()
        fetchOutcome = nil
        fetchProgress = HistorySession.Progress()
        fetchState = .waitingForBand
        fetching = true
        fetchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickFetch()
        }
        // Är bandet redan anslutet läses tjänsterna om, och skrivkarakteristiken med dem.
        if central == nil { makeCentral() } else { resumeListening() }
    }

    /// Hälsningen går först när skrivkarakteristiken är funnen och `…0003`
    /// (svaren) och `…0005` (historiken) prenumereras, så att inget svar missas.
    private func maybeBeginSession() {
        guard fetching, session?.state == .waitingForBand, let b = band, b.state == .connected,
              commandCharacteristic != nil,
              listening.contains("fd4b0003"), listening.contains("fd4b0005"),
              let actions = session?.start(now: Date()) else { return }
        run(actions)
    }

    private func tickFetch() {
        guard fetching, let actions = session?.tick(now: Date()) else { return }
        run(actions)
    }

    /// Utför sessionens åtgärder. Skrivningar bara genom `BandSender`.
    private func run(_ actions: [HistorySession.Action]) {
        for a in actions {
            switch a {
            case .write(let c):
                lastWriter = .fetch
                guard let b = band, let ch = commandCharacteristic, BandSender.send(c, to: b, on: ch) else {
                    if let mer = session?.writeFailed() { run(mer) }
                    return
                }
            case .saveThenAck:
                let ok = saveFetched()
                if let mer = session?.saved(ok: ok, now: Date()) { run(mer) }
            case .finish(let o):
                endFetch(o)
                return
            }
        }
        if let s = session {
            fetchProgress = s.progress
            fetchState = s.state
        }
    }

    /// METOD M23. Allt som kommit är skrivet till disken (fsync), ingen rad
    /// väntar i minnet och ingen har fallerat sedan hämtningen började. Först
    /// då kvitteras biten.
    private func saveFetched() -> Bool {
        guard pending.isEmpty, let f = frameFile else { return false }
        return f.sync() && framesFailures == fetchFailuresAtStart
    }

    // MARK: IMU-provet

    /// Skrivkarakteristiken behövs: en hämtning, IMU-provet (BESLUT B53) eller passets puls (BESLUT B61).
    private var needsCommandChannel: Bool {
        fetching || imu.isArmed || imu.wantsWrite || pulse.isArmed || pulse.wantsWrite
    }

    private var imuCanWrite: Bool {
        guard let b = band, b.state == .connected, commandCharacteristic != nil else { return false }
        return !fetching
    }

    private func tickImu() {
        let now = Date()
        // METOD M43. Tystnaden först: en misslyckad skrivning avbryter `runImu`.
        runImu(imu.watch(now: now, linkUp: band?.state == .connected))
        runImu(imu.tick(now: now, canWrite: imuCanWrite))
    }

    /// METOD M43. Utför IMU-provets åtgärder. Skrivningar bara genom `BandSender`.
    private func runImu(_ actions: [ImuControl.Action]) {
        for a in actions {
            switch a {
            case .write(let c):
                lastWriter = .imu
                guard let b = band, let ch = commandCharacteristic, BandSender.send(c, to: b, on: ch) else {
                    let mer = imu.writeFailed(now: Date())
                    runImu(mer)
                    return
                }
            case .mark(let label):
                let now = Date()
                ensureDay(at: now)
                sideFile?.append(RecordingLog.marker(label, at: now))
            case .link(let l):
                logLink(l)
            }
        }
        publishImu()
    }

    /// Visar läget, sparar om ett prov pågår (för en omstart), håller klockan
    /// igång medan något återstår och ber om skrivkarakteristiken när den behövs.
    private func publishImu() {
        if imuPhase != imu.phase { imuPhase = imu.phase }
        if imuProgress != imu.progress { imuProgress = imu.progress }
        if imuFailsafeStops != imu.failsafeStops { imuFailsafeStops = imu.failsafeStops }
        if imuArmedSaved != imu.isArmed {
            imuArmedSaved = imu.isArmed
            defaults.set(imu.isArmed, forKey: Key.imuArmed)
        }
        if imu.isArmed || imu.wantsWrite {
            if imuTimer == nil {
                imuTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    self?.tickImu()
                }
            }
            if imu.wantsWrite, commandCharacteristic == nil { requestCommandChannel() }
        } else {
            imuTimer?.invalidate()
            imuTimer = nil
        }
    }

    /// Läser om tjänsterna, och skrivkarakteristiken med dem (högst var 5:e sekund).
    private func requestCommandChannel() {
        guard let b = band, b.state == .connected, Date().timeIntervalSince(channelRequestedAt) > 5 else { return }
        channelRequestedAt = Date()
        b.discoverServices(servicesToDiscover)
    }

    /// Appen avslutas: stoppet går direkt om ett prov (BESLUT B53) eller passets puls (BESLUT B61) pågår.
    @objc private func appWillTerminate() {
        runImu(imu.flushStop(now: Date()))
        runPulse(pulse.flushStop(now: Date()))
        syncFiles()
    }

    private func endFetch(_ o: HistorySession.Outcome) {
        fetchTimer?.invalidate()
        fetchTimer = nil
        if let s = session { fetchProgress = s.progress }
        session = nil
        fetchOutcome = o
        // PLAN.md A3. Slutet i sidofilen: `NightLedger` räknar om nätterna som hämtningen kan ha fyllt i.
        let vem: String = fetchReason.map { (r: AutoFetch.Reason) -> String in "automatisk (\(r.rawValue)): " } ?? ""
        switch o {
        case .complete:
            logEvent(.fetchComplete,
                     text: vem + "\(fetchProgress.chunks) bitar, \(fetchProgress.k18Seconds) K18-sekunder")
        case .stopped(let orsak):
            logEvent(.fetchStopped, text: vem + "\(orsak)")
        }
        fetchReason = nil
        autoState.ended(at: Date(), o)
        saveAutoState()
        fetchState = nil
        fetching = false
        if !needsCommandChannel { commandCharacteristic = nil }
        // Bandet släpps inte: lyssnaren ligger kvar (BESLUT B28).
        _ = frameFile?.sync()
        publishNow(Date())
        // PLAN.md A3. Nätterna som hämtningen fyllde i räknas om direkt (`NightLedger.jobs(fetches:)`).
        reloadSummaries()
    }
}

// MARK: - IMU-provet

extension Recorder {
    /// BESLUT B53 · METOD M43. Startar IMU-provet på användaren knapptryck.
    /// Inte under en hämtning.
    func startImu() {
        guard !fetching, !imu.isArmed else { return }
        runImu(imu.start(now: Date()))
    }

    /// användaren stoppar provet.
    func stopImu() {
        runImu(imu.stop(now: Date(), reason: .user))
    }
}

// MARK: - Pulsen under ett pass

extension Recorder {
    /// BESLUT B58 · METOD M47. Ett pass vill ha pulsen: prenumerera på 2A37 över den stående anslutningen. Är bandet
    /// anslutet läses tjänsterna om och prenumerationen läggs på när tjänsten hittats; annars läggs den på vid
    /// nästa anslutning (`didConnect`). Den passiva lyssningen, hämtningen och IMU-provet rörs inte.
    func startPulse() {
        pulseWanted = true
        reservePulses = 0
        reservePulsesUsed = 0
        pulseNotes = []
        // BESLUT B61 · METOD M48. Bandets realtidspuls (kommando 3); 2A37 nedan är reserven.
        runPulse(pulse.start(now: Date()))
        // BESLUT B116. Läget vid Start: bandet anslutet (a), skrivkarakteristiken känd (k), en hämtning pågår (h).
        let ansluten: Int = band?.state == .connected ? 1 : 0
        let kanal: Int = commandCharacteristic == nil ? 0 : 1
        pulseNote("puls-läge a\(ansluten) k\(kanal) h\(fetching ? 1 : 0)")
        if let b = band, b.state == .connected, let c = central, c.state == .poweredOn {
            if let ch = pulseCharacteristic, ch.properties.contains(.notify) {
                b.setNotifyValue(true, for: ch)
            } else {
                b.discoverServices(servicesToDiscover)
            }
        } else {
            resumeListening()
        }
    }

    /// BESLUT B58. Passet är slut: slå av notisen. Bandet och lyssnaren ligger kvar.
    func stopPulse() {
        runPulse(pulse.stop(now: Date(), reason: .done))
        // BESLUT B116. Reserven i antal: 2A37-notiser under passet (n), och de som gick till passet (k).
        pulseNote("puls-2a37 n\(reservePulses) k\(reservePulsesUsed)")
        pulseWanted = false
        if let b = band, b.state == .connected, let ch = pulseCharacteristic, ch.isNotifying {
            b.setNotifyValue(false, for: ch)
        }
    }
}

// MARK: - Passets realtidspuls

extension Recorder {
    /// BESLUT B116 · METOD M67. Ett märke om passets puls i dygnets sidofil, högst en gång per pass och bara medan
    /// ett pass vill ha pulsen. Ordet säger var på vägen något hände; aldrig ett mätvärde.
    private func pulseNote(_ label: String) {
        guard pulseWanted, pulseNotes.insert(label).inserted else { return }
        let now = Date()
        ensureDay(at: now)
        sideFile?.append(RecordingLog.marker(label, at: now))
    }

    /// BESLUT B61 · METOD M48. Klockan för realtidspulsen: start, nya försök och stoppet.
    private func tickPulse() {
        let kanSkriva = band?.state == .connected && commandCharacteristic != nil && !fetching
        runPulse(pulse.tick(now: Date(), canWrite: kanSkriva))
    }

    /// Utför realtidspulsens åtgärder. Skrivningar bara genom `BandSender`.
    private func runPulse(_ actions: [PulseControl.Action]) {
        for a in actions {
            switch a {
            case .write(let c):
                lastWriter = .pulse
                guard let b = band, let ch = commandCharacteristic, BandSender.send(c, to: b, on: ch) else {
                    runPulse(pulse.writeFailed(now: Date()))
                    return
                }
            case .mark(let label):
                let now = Date()
                ensureDay(at: now)
                sideFile?.append(RecordingLog.marker(label, at: now))
            case .pulse(let m):
                let now = Date()
                lastRealtimePulseAt = now
                onPulse?(m, now)
            }
        }
        publishPulse()
    }

    /// Sparar om pulsen är på (för en omstart), håller klockan igång medan den är det och ber om
    /// skrivkarakteristiken när något väntar på att skrivas.
    private func publishPulse() {
        if pulseArmedSaved != pulse.isArmed {
            pulseArmedSaved = pulse.isArmed
            defaults.set(pulse.isArmed, forKey: Key.pulseArmed)
        }
        if pulse.isArmed {
            if pulseTimer == nil {
                let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tickPulse() }
                RunLoop.main.add(t, forMode: .common)
                pulseTimer = t
            }
            if pulse.wantsWrite, commandCharacteristic == nil {
                if band?.state == .connected { requestCommandChannel() } else { resumeListening() }
            }
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension Recorder: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            resumeListening()
        case .poweredOff:
            link = .bluetoothOff
            listening.removeAll()
            notifyRequested.removeAll()
            servicesLogged = false
            if fetching, let mer = session?.disconnected() { run(mer) }
        case .unauthorized:
            link = .unauthorized
        default:
            link = .idle
        }
    }

    /// iOS startade om appen i bakgrunden och lämnar tillbaka bandet som var
    /// anslutet eller på väg att anslutas. Kommer före `centralManagerDidUpdateState`,
    /// som tar upp lyssnandet (`resumeListening`).
    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        let återställda = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let p = återställda.first(where: { $0.identifier == rememberedBand }) ?? återställda.first else { return }
        band = p
        p.delegate = self
        // PLAN.md A3. iOS väckte appen för bandet.
        logEvent(.restored)
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Ett annat pulsband i rummet ska inte tas: ett namn som inte är Whoops hoppas över.
        let namn = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name
        if let n = namn, !n.localizedCaseInsensitiveContains("whoop"), p.identifier != rememberedBand { return }
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        logLink(.connected)
        didConnect(p)
    }

    /// Misslyckades anslutningen läggs en ny väntande anslutning efter två
    /// sekunder, så att ett fel som upprepar sig inte snurrar.
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        logLink(.failedToConnect, error: error)
        link = .connecting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let central = self?.central, central.state == .poweredOn else { return }
            central.connect(p, options: nil)
        }
    }

    /// Bandet tappades (utom räckhåll, slut på batteri, Bluetooth av). Ny
    /// väntande anslutning direkt: iOS håller den öppen tills bandet hörs
    /// igen, även med appen i bakgrunden.
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        // METOD M43. Felet säger varför (t.ex. CBError 6 = tidsgränsen, 7 =
        // bandet kopplade ner); `nil` = Idunn kopplade ner, vilket den aldrig gör.
        logLink(.disconnected, error: error)
        notifyRequested.removeAll()
        servicesLogged = false
        listening.removeAll()
        batteryCharacteristic = nil
        // Karakteristiken gäller bara anslutningen; den söks igen vid nästa.
        commandCharacteristic = nil
        pulseCharacteristic = nil
        liveStream = FrameAssembly.Stream()
        // METOD M23. Det som inte kvitterats ligger kvar i bandet.
        if fetching, let mer = session?.disconnected() { run(mer) }
        guard c.state == .poweredOn else { return }
        link = .connecting
        c.connect(p, options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension Recorder: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            switch s.uuid {
            case Self.batteryService: p.discoverCharacteristics([Self.batteryLevel], for: s)
            case Self.whoopService:
                // BESLUT B25 · BESLUT B53. Skrivkarakteristiken söks bara när en
                // hämtning eller IMU-provet behöver den.
                p.discoverCharacteristics(needsCommandChannel ? Self.whoopListened + [BandSender.commandCharacteristic]
                                                              : Self.whoopListened, for: s)
            case Self.heartRateService:
                // BESLUT B58. Bara medan ett pass vill ha pulsen.
                if pulseWanted { p.discoverCharacteristics([Self.heartRateMeasurement], for: s) }
            default: break
            }
        }
        // BESLUT B116. Reserven: bandet visar ingen pulstjänst (bara under ett pass).
        if pulseWanted, !(p.services ?? []).contains(where: { $0.uuid == Self.heartRateService }) {
            pulseNote("puls-2a37 tjänst saknas")
        }
    }

    /// BESLUT B14: här prenumereras och läses det. `setNotifyValue` slår bara
    /// på notiserna för Idunn; iOS delar dem med Whoop-appen. BESLUT B25: under
    /// en hämtning sparas även skrivkarakteristiken, som bara `BandSender`
    /// skriver till.
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.batteryLevel {
                batteryCharacteristic = ch
                p.readValue(for: ch)
                // PLAN.md A3 · BESLUT B14. Notiser på batteriets procent: bara lyssnande, och de väcker appen under
                // natten så att den automatiska hämtningen får chansen.
                if ch.properties.contains(.notify) { p.setNotifyValue(true, for: ch) }
            } else if ch.uuid == BandSender.commandCharacteristic {
                if needsCommandChannel { commandCharacteristic = ch }
            } else if ch.uuid == Self.heartRateMeasurement {
                // BESLUT B58 · METOD M47. Pulsen under ett pass.
                pulseCharacteristic = ch
                if pulseWanted, ch.properties.contains(.notify) { p.setNotifyValue(true, for: ch) }
                // BESLUT B116. Reserven: karakteristiken finns men ger inga notiser.
                if !ch.properties.contains(.notify) { pulseNote("puls-2a37 utan notis") }
            } else if Self.whoopListened.contains(ch.uuid),
                      ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                notifyRequested.insert(RawFrame.shortName(ch.uuid.uuidString))
                p.setNotifyValue(true, for: ch)
            }
        }
        maybeBeginSession()
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == Self.heartRateMeasurement {
            // BESLUT B116. Reserven under ett pass: prenumerationen gick på, eller felets kod. Inget annat ändras.
            if let e = error {
                pulseNote("puls-2a37 fel \((e as NSError).code)")
            } else if ch.isNotifying {
                pulseNote("puls-2a37 på")
            }
            return
        }
        guard Self.whoopListened.contains(ch.uuid) else { return }
        let namn = RawFrame.shortName(ch.uuid.uuidString)
        if error == nil && ch.isNotifying { listening.insert(namn) } else { listening.remove(namn) }
        // METOD M43. En gång per anslutning, när alla begärda notiser är på.
        if !servicesLogged, !notifyRequested.isEmpty, notifyRequested.isSubset(of: listening) {
            servicesLogged = true
            logLink(.servicesReady, text: listening.sorted().joined(separator: " "))
            // PLAN.md A3. Bandet anslöt och lyssnar: hämta det som samlats medan det var borta.
            considerAutoFetch(justConnected: true)
        }
        maybeBeginSession()
    }

    /// BESLUT B25. Bandet tog inte emot kommandot: hämtningen stoppas.
    /// BESLUT B53: utan hämtning gällde det IMU-provet, som stoppar eller gör om stoppet.
    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == BandSender.commandCharacteristic, error != nil else { return }
        switch lastWriter {
        case .fetch:
            if fetching, let mer = session?.writeFailed() { run(mer) }
        case .imu:
            runImu(imu.writeFailed(now: Date()))
        case .pulse:
            runPulse(pulse.writeFailed(now: Date()))
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, let data = ch.value else { return }
        if ch.uuid == Self.batteryLevel {
            received(battery: data)
        } else if Self.whoopListened.contains(ch.uuid) {
            received(frame: data, from: ch.uuid)
        } else if ch.uuid == Self.heartRateMeasurement, pulseWanted, let m = HeartRateMeasurement(data: data) {
            // BESLUT B58. Pulsen går till passet, inte till dygnsfilen. BESLUT B61: bara som reserv,
            // när bandets realtidspuls inte kommit på en stund (annars blir varje sekund två prov).
            let nu = Date()
            reservePulses += 1
            pulseNote("puls-2a37 första")
            if nu.timeIntervalSince(lastRealtimePulseAt) >= Self.realtimeHoldoff {
                reservePulsesUsed += 1
                onPulse?(m, nu)
            }
        }
    }
}
