import AVFoundation
import Foundation
import SoundAnalysis
import Sound

/// METOD M38 · BESLUT B47
/// Lyssnaren för ljudet under natten (PLAN.md spåret J, J2). Allt som är ett
/// beslut ligger i IdunnKit-målet `Sound` (måtten, klasserna, filen, händelserna,
/// klippen, `ClipPolicy`), provat på Linux; här sitter bara det som kräver
/// iOS: mikrofonen, ljudsessionen, konverteringen till 16 kHz, SoundAnalysis
/// och AAC-klippen.
///
/// **Start** när appen kommer i förgrunden kl 20–04, om reglaget är på och
/// mikrofonen tillåten (iOS låter ingen app starta mikrofonen från bakgrunden).
/// **Slut** första gången appen kommer i förgrunden efter kl 05, och senast
/// kl 12. Under tiden håller `audio` i UIBackgroundModes appen vid liv.
///
/// **Ljudsessionen** är `.record` med läget `.measurement`, som stänger av
/// systemets nivåreglering och brusdämpning (nivåerna går annars inte att
/// jämföra mellan nätter). Mikrofonens takt konverteras till 16 kHz mono
/// Float32; varje fulla sekund (16 000 prov) mäts av `SoundMeter`.
///
/// **Klasserna** kommer från `SNClassifySoundRequest(.version1)` med fönstret
/// 1,5 s och överlapp 1/3 (ett resultat i sekunden), och sätts på den sekund
/// vars mitt ligger närmast fönstrets mitt. En sekund skrivs därför först när
/// dess klasser kommit, eller fyra sekunder senare utan dem.
///
/// **Filerna** ligger i Application Support: `ljud/ljud-<start>.ljud` (måtten,
/// för alltid) med `.markningar` bredvid (start, stopp, avbrott), och
/// `ljudklipp/ljud-<start>/<händelsens sekund>.m4a` (AAC 16 kHz mono, 32 kbit/s,
/// raderas efter 14 dagar). Båda mapparna är undantagna från iCloud-kopian som
/// rådygnen. Inget lämnar telefonen utom med Exportera (dataregeln, BESLUT B47).
///
/// **Avbrott** (samtal, väckarklocka, Siri): återupptas om iOS tillåter det
/// (`.shouldResume`), annars ligger ett glapp kvar tills appen öppnas igen.
/// iOS säger inte om det var ett samtal eller en väckarklocka, så märket blir
/// "annat" (`SoundMark.Kind.interruptedOther`).
///
/// Allt tillstånd rörs på den egna kön `queue`; det som visas på Data
/// publiceras på huvudkön (`status`).
final class SoundListener: ObservableObject {
    static let shared = SoundListener(root: SoundListener.defaultRoot)

    /// Nyckeln för reglaget på Data (`@AppStorage`). Strängen ändras aldrig (BESLUT B9).
    static let enabledKey = "idun.ljudPaa"
    private static let openNightKey = "idun.ljudNatt"

    /// METOD M38. Start kl 20–04, slut vid första förgrund efter 05 och senast 12.
    static let startFromHour = 20
    static let startBeforeHour = 4
    static let endAfterHour = 5
    static let latestHour = 12
    /// METOD M38. Klippen raderas efter så här många dagar.
    static let clipDays = 14
    /// METOD M38. Ringbufferten, sekunder, och längsta klippet med sekunderna före.
    static let ringSeconds = 35
    static let clipBufferSeconds = 33
    /// Så länge väntar en sekund på sina klasser innan den skrivs utan dem.
    static let classWaitSeconds = 4

    struct Status: Equatable {
        var listening = false
        /// När nattens första sekund mättes.
        var since: Date?
        /// Mätta sekunder i natten.
        var seconds = 0
        /// Avbrott och andra glapp i natten.
        var gaps = 0
        /// Klipp som sparas just nu, och vad ljudet tar på telefonen.
        var clips = 0
        var bytes = 0
        /// Varför lyssnaren inte går (en mening), annars `nil`.
        var note: String?
    }

    /// Resultatet av en körning mot en ljudfil (`process(file:start:)`, provet).
    struct FileResult: Equatable {
        var seconds: Int
        var events: Int
        var clips: Int
        var measureFile: URL
        var clipFolder: URL
        /// Fick SoundAnalysis köras? Annars saknas klasserna.
        var classified: Bool
    }

    enum ListenerError: Error {
        case noInput
        case cannotConvert
        case cannotRead
    }

    @Published private(set) var status = Status()

    private let root: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "se.birdiebook.idun.ljud", qos: .userInitiated)

    // MARK: Tillstånd (rörs bara på `queue`)

    private var running = false
    private var engineRunning = false
    private var fileStart = 0
    private var stem = ""
    private var measureHandle: FileHandle?
    private var markHandle: FileHandle?
    private var meter = SoundMeter()
    private var detector = SoundEvents.Detector()
    private var policy = ClipPolicy()
    private var gaps = 0
    private var measured = 0
    private var eventsSeen = 0
    private var since: Date?
    private var note: String?

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let target: AVAudioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                      channels: 1, interleaved: false)!
    private var pending: [Float] = []
    private var baseSecond = 0
    private var tick = 0
    private var nextToFinalize = 0
    private var awaiting: [SoundSecond] = []
    private var ring: [(idx: Int, samples: [Float])] = []
    private var eventStart: Int?
    private var eventBuffer: [(idx: Int, samples: [Float])] = []

    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: ClassObserver?
    private let classBox = ClassBox()
    private var noonTimer: DispatchSourceTimer?
    private var statusTimer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    init(root: URL, defaults: UserDefaults = .standard) {
        self.root = root
        self.defaults = defaults
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: nil) { [weak self] (n: Notification) in
            self?.queue.async { self?.interruption(n) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil,
                                            queue: nil) { [weak self] (_: Notification) in
            self?.queue.async { self?.configurationChanged() }
        })
    }

    // MARK: Mapparna

    var measureFolder: URL { root.appendingPathComponent("ljud", isDirectory: true) }
    var clipRoot: URL { root.appendingPathComponent("ljudklipp", isDirectory: true) }

    private func measureURL() -> URL { measureFolder.appendingPathComponent(stem + ".ljud") }
    private func marksURL() -> URL { measureFolder.appendingPathComponent(stem + ".markningar") }
    private func clipFolder() -> URL { clipRoot.appendingPathComponent(stem, isDirectory: true) }
    private func clipURL(_ id: Int) -> URL {
        clipFolder().appendingPathComponent(String(format: "%05d.m4a", id))
    }

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true
    }

    // MARK: Förgrund, reglage, slut

    /// Appen kom i förgrunden: starta kl 20–04, avsluta efter 05, eller återuppta efter ett avbrott.
    func appBecameActive(now: Date = Date()) {
        // Provet (IdunnProv) körs inuti appen: där finns ingen mikrofon att fråga om.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        queue.async { self.evaluate(now: now) }
    }

    /// Reglaget på Data ändrades.
    func setEnabled(_ on: Bool) {
        queue.async {
            if on {
                self.evaluate(now: Date())
            } else if self.running {
                self.stopLocked(finalForNight: false)
            } else {
                self.note = nil
                self.publish()
            }
        }
    }

    private func evaluate(now: Date) {
        let hour: Int = Calendar.current.component(.hour, from: now)
        if running {
            if !SoundListener.isEnabled {
                stopLocked(finalForNight: false)
            } else if hour >= SoundListener.endAfterHour && hour < SoundListener.startFromHour {
                stopLocked(finalForNight: true)
            } else if !engineRunning {
                resumeEngine()
            }
            return
        }
        guard SoundListener.isEnabled else {
            note = nil
            publish()
            return
        }
        guard hour >= SoundListener.startFromHour || hour < SoundListener.startBeforeHour else {
            publish()
            return
        }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startLocked(now: now)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] (granted: Bool) in
                self?.queue.async {
                    if granted {
                        self?.startLocked(now: Date())
                    } else {
                        self?.note = "Mikrofonen är inte tillåten."
                        self?.publish()
                    }
                }
            }
        default:
            note = "Mikrofonen är inte tillåten. Slå på den i Inställningar."
            publish()
        }
    }

    // MARK: Start och stopp

    private func startLocked(now: Date) {
        guard !running else { return }
        note = nil
        do {
            try beginNight(start: now)
            try SoundListener.configureSession()
            try startEngine()
        } catch {
            mark(.failed)
            note = "Mikrofonen gick inte att starta."
            endNight(finalForNight: false)
            publish()
            return
        }
        mark(.started)
        scheduleNoon(after: now)
        scheduleStatus()
        publish()
    }

    private func stopLocked(finalForNight: Bool) {
        guard running else { return }
        stopEngine()
        finishAll()
        mark(.stopped)
        endNight(finalForNight: finalForNight)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        noonTimer?.cancel()
        noonTimer = nil
        statusTimer?.cancel()
        statusTimer = nil
        publish()
    }

    /// Senast kl 12 slutar lyssnaren, också om appen aldrig öppnats.
    private func scheduleNoon(after now: Date) {
        noonTimer?.cancel()
        var parts = DateComponents()
        parts.hour = SoundListener.latestHour
        parts.minute = 0
        guard let when = Calendar.current.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(wallDeadline: .now() + max(1, when.timeIntervalSince(Date())))
        timer.setEventHandler { [weak self] in self?.stopLocked(finalForNight: true) }
        timer.resume()
        noonTimer = timer
    }

    private func scheduleStatus() {
        statusTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in self?.publish() }
        timer.resume()
        statusTimer = timer
    }

    // MARK: Natten och filerna

    /// Öppnar nattens filer. En natt som redan har en öppen fil (appen startades om,
    /// eller ett avbrott) fortsätter i samma fil; en halv post sist skärs bort.
    private func beginNight(start: Date) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: measureFolder, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try fm.createDirectory(at: clipRoot, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        for folder in [measureFolder, clipRoot] { exclude(folder) }
        pruneClips(now: start)

        let now: Int = Int(start.timeIntervalSince1970)
        if let open = defaults.object(forKey: SoundListener.openNightKey) as? Int, now - open < 10 * 3_600, open <= now {
            fileStart = open
            stem = SoundFile.stem(start: open)
        } else {
            fileStart = now
            stem = SoundFile.stem(start: now)
            policy = ClipPolicy()
            gaps = 0
            eventsSeen = 0
            defaults.set(now, forKey: SoundListener.openNightKey)
        }
        since = Date(timeIntervalSince1970: Double(fileStart))
        let url = measureURL()
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: SoundFile.header(start: fileStart),
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            else { throw ListenerError.cannotRead }
        }
        let handle = try FileHandle(forWritingTo: url)
        let size: Int = Int(try handle.seekToEnd())
        let whole: Int = SoundFile.headerBytes + max(0, size - SoundFile.headerBytes) / SoundFile.recordBytes
            * SoundFile.recordBytes
        if whole < size { try handle.truncate(atOffset: UInt64(whole)) }
        try handle.seekToEnd()
        measured = (whole - SoundFile.headerBytes) / SoundFile.recordBytes
        measureHandle = handle
        if !fm.fileExists(atPath: marksURL().path) {
            fm.createFile(atPath: marksURL().path, contents: nil,
                          attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        markHandle = try? FileHandle(forWritingTo: marksURL())
        _ = try? markHandle?.seekToEnd()
        try? fm.createDirectory(at: clipFolder(), withIntermediateDirectories: true)

        resetStream(now: now)
        meter = SoundMeter()
        detector = SoundEvents.Detector()
        eventStart = nil
        eventBuffer = []
        ring = []
        running = true
    }

    private func endNight(finalForNight: Bool) {
        try? measureHandle?.close()
        try? markHandle?.close()
        measureHandle = nil
        markHandle = nil
        running = false
        engineRunning = false
        if finalForNight { defaults.removeObject(forKey: SoundListener.openNightKey) }
    }

    /// Nollställer strömmen: nästa sekund som mäts hamnar där klockan är, så att
    /// tiden som saknades mellan två starter blir ett glapp i filen.
    private func resetStream(now: Int) {
        pending = []
        tick = 0
        baseSecond = max(0, now - fileStart)
        nextToFinalize = baseSecond
        awaiting = []
        classBox.reset()
        analyzer = nil
        observer = nil
        makeAnalyzer()
    }

    private func mark(_ kind: SoundMark.Kind) {
        let m = SoundMark(time: Int(Date().timeIntervalSince1970), kind: kind)
        try? markHandle?.write(contentsOf: m.line())
    }

    /// Sätter filen utanför iCloud-kopian.
    private func exclude(_ url: URL) {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }

    /// Klippmappar äldre än 14 dagar raderas.
    private func pruneClips(now: Date) {
        let fm = FileManager.default
        let limit: Date = now.addingTimeInterval(-Double(SoundListener.clipDays) * 86_400)
        let names: [String] = (try? fm.contentsOfDirectory(atPath: clipRoot.path)) ?? []
        for n in names {
            let dir = clipRoot.appendingPathComponent(n)
            let attr = try? fm.attributesOfItem(atPath: dir.path)
            if let changed = attr?[.modificationDate] as? Date, changed < limit { try? fm.removeItem(at: dir) }
        }
    }

    // MARK: Mikrofonen

    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenerError.noInput }
        guard let conv = AVAudioConverter(from: format, to: target) else { throw ListenerError.cannotConvert }
        converter = conv
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self = self else { return }
            let samples: [Float] = SoundListener.convert(buffer, with: conv, to: self.target)
            if !samples.isEmpty { self.queue.async { self.feed(samples) } }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        engineRunning = true
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        engineRunning = false
    }

    /// METOD M38. Mätläget utan systemets signalbehandling. `playAndRecord` med
    /// `mixWithOthers`, inte `record`: `record` tystar allt annat, så en podcast vid
    /// insomningen skulle stanna när Idunn börjar lyssna. Telefonens egen mikrofon
    /// väljs, så att anslutna hörlurar inte blir nattens mikrofon.
    static func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
        try session.setActive(true)
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }),
           session.preferredInput?.uid != builtIn.uid {
            try? session.setPreferredInput(builtIn)
        }
    }

    /// Bygger om ljudkedjan efter ett avbrott eller en ändrad ljudrutt.
    private func resumeEngine() {
        guard running else { return }
        stopEngine()
        finishAll()
        do {
            try SoundListener.configureSession()
            resetStream(now: Int(Date().timeIntervalSince1970))
            try startEngine()
            mark(.resumed)
        } catch {
            mark(.failed)
            note = "Lyssnaren kunde inte återupptas."
        }
        publish()
    }

    private func interruption(_ n: Notification) {
        guard running,
              let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            gaps += 1
            mark(.interruptedOther)
            stopEngine()
            publish()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0)
            if options.contains(.shouldResume) { resumeEngine() }
        @unknown default:
            break
        }
    }

    private func configurationChanged() {
        guard running, engineRunning else { return }
        gaps += 1
        mark(.routeLost)
        resumeEngine()
    }

    /// Konverterar en mikrofonbuffer till 16 kHz mono Float32.
    static func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter, to target: AVAudioFormat) -> [Float] {
        let ratio: Double = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { (_: AVAudioPacketCount, inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, let channel = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
    }

    // MARK: Sekunderna

    /// Tar emot 16 kHz-prov; varje full sekund mäts.
    private func feed(_ samples: [Float]) {
        guard running else { return }
        pending.append(contentsOf: samples)
        while pending.count >= SoundMeter.sampleRate {
            let second = Array(pending.prefix(SoundMeter.sampleRate))
            pending.removeFirst(SoundMeter.sampleRate)
            secondTick(second)
        }
    }

    private func secondTick(_ samples: [Float]) {
        let idx: Int = baseSecond + tick
        tick += 1
        ring.append((idx: idx, samples: samples))
        if ring.count > SoundListener.ringSeconds { ring.removeFirst(ring.count - SoundListener.ringSeconds) }
        if eventStart != nil && eventBuffer.count < SoundListener.clipBufferSeconds {
            eventBuffer.append((idx: idx, samples: samples))
        }
        if let analyzer = analyzer, let buffer = pcmBuffer(samples) {
            analyzer.analyze(buffer, atAudioFramePosition: AVAudioFramePosition((tick - 1) * SoundMeter.sampleRate))
        }
        guard let measuredSecond = meter.measure(samples, second: idx) else { return }
        awaiting.append(measuredSecond)
        finalizeReady(current: idx)
    }

    private func pcmBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else { return nil }
        for i in 0..<samples.count { channel[0][i] = samples[i] }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// Skriver de sekunder som fått sina klasser, eller väntat klart på dem.
    private func finalizeReady(current: Int) {
        while let first = awaiting.first {
            let classes: [UInt8]? = classBox.classes(for: first.second)
            if classes == nil && current - first.second < SoundListener.classWaitSeconds { break }
            awaiting.removeFirst()
            var s = first
            if let c = classes { s.classes = c }
            write(s)
        }
    }

    /// Skriver allt som väntar (vid stopp och avbrott) och avslutar den öppna händelsen.
    /// SoundAnalysis får först avsluta sina fönster, så att de sista sekunderna får sina klasser.
    private func finishAll(waitSeconds: Double = 3) {
        if let a = analyzer {
            a.completeAnalysis()
            _ = classBox.waitUntilDone(seconds: waitSeconds)
        }
        classBox.markDone()
        while !awaiting.isEmpty {
            var s = awaiting.removeFirst()
            if let c = classBox.classes(for: s.second) { s.classes = c }
            write(s)
        }
        for e in detector.finish() { decide(e) }
        detector = SoundEvents.Detector()
        eventStart = nil
        eventBuffer = []
        analyzer = nil
        observer = nil
    }

    /// En färdig sekund: till filen, och till händelsedetektorn.
    private func write(_ s: SoundSecond) {
        try? measureHandle?.write(contentsOf: SoundFile.record(s))
        measured += 1
        let closed: [SoundEvent] = detector.push(s)
        for e in closed { decide(e) }
        if let open = detector.openStart {
            if eventStart != open {
                eventStart = open
                eventBuffer = ring.filter { (r: (idx: Int, samples: [Float])) -> Bool in r.idx >= open - ClipPolicy.beforeSeconds }
            }
        } else {
            eventStart = nil
            eventBuffer = []
        }
    }

    // MARK: Klippen

    private func decide(_ e: SoundEvent) {
        eventsSeen += 1
        switch policy.decide(e) {
        case .save:
            writeClip(e)
        case .replace(let id):
            try? FileManager.default.removeItem(at: clipURL(id))
            writeClip(e)
        case .skip:
            break
        }
    }

    /// Klippet för händelsen ur händelsebufferten: AAC 16 kHz mono, 32 kbit/s.
    private func writeClip(_ e: SoundEvent) {
        let span: Range<Int> = ClipPolicy.span(of: e)
        var samples: [Float] = []
        for r in eventBuffer where r.idx >= span.lowerBound && r.idx < span.upperBound {
            samples.append(contentsOf: r.samples)
        }
        guard !samples.isEmpty, let buffer = pcmBuffer(samples) else { return }
        let url = clipURL(e.id)
        try? FileManager.default.createDirectory(at: clipFolder(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            // METOD M38: fast takt begärs, men simulatorns kodare gav 6,8 kB/s för brus
            // med och utan den; takten mäts på telefonen.
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    }

    // MARK: SoundAnalysis

    private func makeAnalyzer() {
        let a = SNAudioStreamAnalyzer(format: target)
        let obs = ClassObserver(box: classBox)
        obs.baseOffset = baseSecond
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 1_000)
            request.overlapFactor = 1.0 / 3.0
            do {
                try a.add(request, withObserver: obs)
            } catch {
                // Fönstret stöds inte: klassificeraren får sitt eget.
                let plain = try SNClassifySoundRequest(classifierIdentifier: .version1)
                try a.add(plain, withObserver: obs)
            }
            analyzer = a
            observer = obs
        } catch {
            analyzer = nil
            observer = nil
        }
    }

    // MARK: Status

    private func publish() {
        let usage: Int = SoundListener.folderBytes(measureFolder) + SoundListener.folderBytes(clipRoot)
        let s = Status(listening: running && engineRunning, since: since, seconds: measured, gaps: gaps,
                       clips: policy.count, bytes: usage, note: note)
        DispatchQueue.main.async { self.status = s }
    }

    static func folderBytes(_ url: URL) -> Int {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in walker {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return total
    }

    // MARK: Provet: en ljudfil i stället för mikrofonen

    /// Matar lyssnaren med en ljudfil i stället för mikrofonen (IdunnProv: simulatorn har
    /// ingen). Hela vägen är densamma: konvertering till 16 kHz, `SoundMeter`, klasser,
    /// `.ljud`-filen, händelserna och klippen. Filens första sekund är `start`.
    func process(file url: URL, start: Date) throws -> FileResult {
        try queue.sync { try self.processLocked(file: url, start: start) }
    }

    private func processLocked(file url: URL, start: Date) throws -> FileResult {
        let input = try AVAudioFile(forReading: url)
        guard let conv = AVAudioConverter(from: input.processingFormat, to: target) else {
            throw ListenerError.cannotConvert
        }
        try beginNight(start: start)
        let classified = analyzer != nil
        let chunk = AVAudioFrameCount(8_192)
        while input.framePosition < input.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: chunk) else {
                throw ListenerError.cannotRead
            }
            try input.read(into: buffer, frameCount: chunk)
            if buffer.frameLength == 0 { break }
            feed(SoundListener.convert(buffer, with: conv, to: target))
        }
        // Resten av analysen levereras av SoundAnalysis på dess egen kö: `finishAll` väntar in den.
        finishAll(waitSeconds: 10)
        let result = FileResult(seconds: measured, events: eventsSeen, clips: countClips(),
                                measureFile: measureURL(), clipFolder: clipFolder(), classified: classified)
        mark(.stopped)
        endNight(finalForNight: true)
        return result
    }

    private func countClips() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: clipFolder().path)) ?? []).filter {
            $0.hasSuffix(".m4a")
        }.count
    }
}

/// Klasserna per sekund som SoundAnalysis levererat, delade mellan analysens kö
/// och lyssnarens (en lås, inga hopp över köer: en sekund kan skrivas så fort
/// dess klasser finns).
final class ClassBox {
    private let lock = NSLock()
    private var values: [Int: [UInt8]] = [:]
    private var done = false
    private let semaphore = DispatchSemaphore(value: 0)

    func reset() {
        lock.lock()
        values = [:]
        done = false
        lock.unlock()
    }

    /// Ett fönster (start och längd i sekunder) hör till den sekund vars mitt ligger
    /// närmast fönstrets mitt. Flera fönster på samma sekund slås ihop med högsta värdet.
    func add(start: Double, duration: Double, classes: [UInt8], baseOffset: Int) {
        let idx: Int = baseOffset + Int((start + duration / 2 - 0.5).rounded())
        lock.lock()
        if let old = values[idx] {
            values[idx] = zip(old, classes).map { (a: UInt8, b: UInt8) -> UInt8 in max(a, b) }
        } else {
            values[idx] = classes
        }
        lock.unlock()
    }

    func classes(for idx: Int) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        return values[idx]
    }

    func markDone() {
        lock.lock()
        let was = done
        done = true
        lock.unlock()
        if !was { semaphore.signal() }
    }

    func waitUntilDone(seconds: Double) -> Bool {
        lock.lock()
        let already = done
        lock.unlock()
        if already { return true }
        return semaphore.wait(timeout: .now() + seconds) == .success
    }
}

/// Tar emot SoundAnalysis resultat och lägger dem i `ClassBox`. Klassningens
/// tid är sekunder i strömmen, räknade från första bufferten som matades in.
final class ClassObserver: NSObject, SNResultsObserving {
    private let box: ClassBox
    /// Sekunden i filen som strömmens första sekund hör till.
    var baseOffset = 0

    init(box: ClassBox) {
        self.box = box
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        var apple: [String: Double] = [:]
        for c in r.classifications { apple[c.identifier] = c.confidence }
        box.add(start: r.timeRange.start.seconds, duration: r.timeRange.duration.seconds,
                classes: SoundClasses.group(apple), baseOffset: baseOffset)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        box.markDone()
    }

    func requestDidComplete(_ request: SNRequest) {
        box.markDone()
    }
}
