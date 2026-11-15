import Foundation
import HeartRate

/// METOD M48 · BESLUT B61
/// Pulsen i realtid ur bandets eget protokoll: paket av typ 40 (REALTIME_DATA)
/// som bandet skickar på Whoops karakteristiker medan TOGGLE_REALTIME_HR (3)
/// är på. Det är Whoop-appens väg under ett träningspass, och den kräver varken
/// Whoop-appen eller "Broadcast Heart Rate" (2A37).
///
/// Paketet har samma posthuvud som historiken (PROTOKOLL_W5 §2.2): typ i i0,
/// tid i i7. Pulsen läses i **i17** (u8, bpm) och RR-antalet i i18 med upp till
/// fyra RR (u16, ms) från i19 — Whoop 4:s platser (NOOP), som också är pulsens
/// plats i Whoop 5:s K24. **antagande** för typ 40 på Whoop 5 tills ett pass
/// är jämfört; ramarna sparas råa i dygnsfilen som allt annat, så platsen går
/// att rätta i efterhand.
public enum RealtimePulse {
    public static let packetType: UInt8 = 40
    /// METOD M48. Pulsens plats (inre offset).
    public static let bpmOffset = 17
    /// METOD M48. RR-antalet och RR-värdenas början (Whoop 4).
    public static let rrCountOffset = 18
    public static let rrOffset = 19
    public static let maxRR = 4
    /// METOD M48. **antagande**: en puls utanför är inte en puls (fel plats eller ingen kontakt).
    public static let bpmRange = 25...230
    /// METOD M48. **antagande**: 250–2 500 ms motsvarar 24–240 slag per minut.
    public static let rrRange = 250...2500

    /// Pulsen ur ett helt paket av typ 40, eller `nil` om paketet inte är det
    /// eller pulsen inte är rimlig. RR tas bara med när antalet är 1–4 och
    /// varje värde är rimligt; annars tom.
    public static func measurement(inner: [UInt8]) -> HeartRateMeasurement? {
        guard inner.count > bpmOffset, inner[0] == packetType else { return nil }
        let bpm = Int(inner[bpmOffset])
        guard bpmRange.contains(bpm) else { return nil }
        var rr: [Double] = []
        if inner.count > rrCountOffset {
            let n = Int(inner[rrCountOffset])
            if (1...maxRR).contains(n), inner.count >= rrOffset + 2 * n {
                let värden = (0..<n).map { k in
                    Int(inner[rrOffset + 2 * k]) | (Int(inner[rrOffset + 2 * k + 1]) << 8)
                }
                if värden.allSatisfy({ rrRange.contains($0) }) { rr = värden.map(Double.init) }
            }
        }
        return HeartRateMeasurement(bpm: bpm, rrMilliseconds: rr)
    }
}

/// METOD M48 · BESLUT B61
/// Passets puls ur bandet: en tillståndsmaskin utan Bluetooth och utan klocka,
/// som `ImuControl`. Appen matar in tider, hela ramar och misslyckade
/// skrivningar och utför det maskinen svarar (`Action`).
///
/// - **Start:** TOGGLE_REALTIME_HR (3) `01`. Kommer ingen puls inom
///   `resendAfter` skickas startet igen, högst `maxStartsWithoutPulse` gånger i
///   rad; en puls nollställer räkningen. Samma regel tar upp strömmen när den
///   tystnat mitt i passet (till exempel efter en återanslutning).
/// - **Stopp:** 3 `00`, gjort om högst `maxStopAttempts` gånger om skrivningen
///   misslyckas. Appen stoppar vid passets slut, när den avslutas
///   (`flushStop`) och, om den dog under ett pass, vid nästa start
///   (`stopAtStart`): då har iOS väckt appen för bandets notiser, så strömmen
///   står inte på länge.
/// - **Inget skydd mot andras ström:** startar Whoop-appen sin egen
///   realtidspuls (ett pass där) lämnas den i fred. Typ 40 utan pass blir
///   ingen puls.
///
/// Maskinen räknar ramar och svar; pulsen går bara till passet (`.pulse`).
public struct PulseControl: Sendable {
    public struct Config: Equatable, Sendable {
        /// goose: 0,25 s mellan kommandona. **antagande** att det räcker.
        public var commandSpacing: TimeInterval = 0.25
        /// **antagande**. Ingen puls så här länge efter ett start (eller efter
        /// förra pulsen) medan passet vill ha puls: startet skickas igen.
        public var resendAfter: TimeInterval = 10
        /// **antagande**. Så många start i rad utan puls innan maskinen slutar
        /// försöka (passet kan ändå få puls från 2A37, BESLUT B58).
        public var maxStartsWithoutPulse = 3
        /// **antagande**. Ett svar som inte kommit så här länge räknas som uteblivet.
        public var commandTimeout: TimeInterval = 10
        /// **antagande**. Ny skrivning efter en misslyckad.
        public var retryDelay: TimeInterval = 2
        /// **antagande**. Så många gånger skrivs stoppet innan maskinen ger upp.
        public var maxStopAttempts = 5
        /// Första sekvensen; skild från hämtningens (1) och IMU-provets (101).
        public var firstSequence: UInt8 = 201
        public init() {}
    }

    public enum StopReason: String, Equatable, Sendable {
        /// Passet är färdigt.
        case done = "klar"
        /// Appen dog under ett pass; stoppet skickas vid nästa start.
        case restart = "omstart"
        /// Appen avslutas.
        case terminate = "avslut"
    }

    public enum Phase: Equatable, Sendable {
        case off, on
        case stopping(StopReason)
    }

    public enum Action: Equatable, Sendable {
        /// Skriv kommandot till `…0002` (med svar), genom `BandSender`.
        case write(WhoopCommand)
        /// Ett märke i dygnets sidofil (`puls-start`, `puls-stopp <orsak>`, `puls-svar <r>` …).
        case mark(String)
        /// En puls till passet.
        case pulse(HeartRateMeasurement)
    }

    /// Bara antal och tider.
    public struct Progress: Equatable, Sendable {
        public var startedAt: Date?
        public var stoppedAt: Date?
        /// Startkommandon som skrivits.
        public var starts = 0
        /// Paket av typ 40 med rätt CRC32 medan passet ville ha puls.
        public var frames = 0
        /// Av dem: med en rimlig puls.
        public var pulses = 0
        /// Typ 40 med fel CRC32.
        public var corruptFrames = 0
        public var lastPulseAt: Date?
        /// Bandets svar på startet (1 = lyckat), i ordning; `nil` = inget svar i tid.
        public var startResults: [UInt8?] = []
        public init() {}
    }

    private enum Step: Equatable, Sendable { case on, off }

    public private(set) var phase: Phase = .off
    public private(set) var progress = Progress()
    public let config: Config

    private var queue: [Step] = []
    private var nextWriteAt: Date
    private var lastStep: Step?
    private var lastStartAt: Date?
    private var startsWithoutPulse = 0
    private var stopAttempts = 0
    private var awaiting: [(command: WhoopCommand, sentAt: Date)] = []
    private var nextSequence: UInt8
    private var gaveUpMarked = false

    /// `stopAtStart`: appen dog under ett pass (sparat i appen). Stoppet läggs
    /// i kön direkt och skrivs när bandet går att skriva till.
    public init(now: Date, config: Config = Config(), stopAtStart: Bool = false) {
        self.config = config
        nextWriteAt = now
        nextSequence = config.firstSequence
        if stopAtStart {
            phase = .stopping(.restart)
            queue = [.off]
        }
    }

    /// Passet vill ha puls, eller stoppet väntar. Appen sparar det, så att en
    /// omstart vet att stoppet ska skickas (`stopAtStart`).
    public var isArmed: Bool { phase != .off }

    /// Något väntar på att skrivas: appen ser till att skrivkarakteristiken finns.
    public var wantsWrite: Bool { !queue.isEmpty }

    // MARK: Indata

    /// Passet vill ha puls. Från av, eller mitt i ett stopp (ett pass som tas upp igen efter
    /// en omstart): stoppet släpps och startet skickas i stället.
    public mutating func start(now: Date) -> [Action] {
        guard phase != .on else { return [] }
        progress = Progress()
        progress.startedAt = now
        phase = .on
        startsWithoutPulse = 0
        gaveUpMarked = false
        lastStartAt = nil
        queue = [.on]
        nextWriteAt = max(nextWriteAt, now)
        return [.mark("puls-start")]
    }

    /// Passet behöver inte längre puls. Ett stopp som redan pågår görs inte om.
    public mutating func stop(now: Date, reason: StopReason) -> [Action] {
        if case .stopping = phase { return [] }
        if phase == .off && reason != .restart { return [] }
        phase = .stopping(reason)
        stopAttempts = 0
        queue = [.off]
        nextWriteAt = max(nextWriteAt, now)
        return [.mark("puls-stopp " + reason.rawValue)]
    }

    /// Klockan, gärna fyra gånger i sekunden medan `isArmed`. `canWrite`: bandet
    /// är anslutet, skrivkarakteristiken funnen och ingen hämtning pågår.
    public mutating func tick(now: Date, canWrite: Bool) -> [Action] {
        var ut: [Action] = []
        expireResponses(now: now)
        if phase == .on, queue.isEmpty, canWrite, let s = lastStartAt {
            let senast = max(s, progress.lastPulseAt ?? .distantPast)
            if now.timeIntervalSince(senast) >= config.resendAfter {
                if startsWithoutPulse < config.maxStartsWithoutPulse {
                    queue = [.on]
                } else if !gaveUpMarked {
                    gaveUpMarked = true
                    ut.append(.mark("puls-ingen"))
                }
            }
        }
        guard canWrite, !queue.isEmpty, now >= nextWriteAt else { return ut }
        let step = queue.removeFirst()
        let c = command(for: step)
        awaiting.append((c, now))
        lastStep = step
        nextWriteAt = now.addingTimeInterval(config.commandSpacing)
        switch step {
        case .on:
            progress.starts += 1
            startsWithoutPulse += 1
            lastStartAt = now
        case .off:
            stopAttempts += 1
        }
        ut.append(.write(c))
        if queue.isEmpty, case .stopping = phase { finishStop(now: now) }
        return ut
    }

    /// En hel ram från någon av Whoops karakteristiker.
    public mutating func receive(_ f: FrameAssembly.Frame, now: Date) -> [Action] {
        if f.crc32OK, let r = CommandResponse(inner: f.inner) { return response(r) }
        guard f.inner.first == RealtimePulse.packetType, phase == .on else { return [] }
        guard f.crc32OK else {
            progress.corruptFrames += 1
            return []
        }
        progress.frames += 1
        guard let m = RealtimePulse.measurement(inner: f.inner) else { return [] }
        progress.pulses += 1
        progress.lastPulseAt = now
        startsWithoutPulse = 0
        gaveUpMarked = false
        return [.pulse(m)]
    }

    /// Den senaste skrivningen gick inte fram. Ett start görs om vid nästa
    /// `resendAfter` (räknas som ett start); ett stopp görs om, högst
    /// `maxStopAttempts` gånger.
    public mutating func writeFailed(now: Date) -> [Action] {
        guard lastStep == .off else { return [] }
        let reason: StopReason
        switch phase {
        case .stopping(let r): reason = r
        case .off: reason = .done
        case .on: return []
        }
        guard stopAttempts < config.maxStopAttempts else {
            queue = []
            finishStop(now: now)
            return []
        }
        phase = .stopping(reason)
        queue = [.off]
        nextWriteAt = now.addingTimeInterval(config.retryDelay)
        return []
    }

    /// Appen avslutas: stoppet på en gång, utan mellanrum. Bara om passet vill ha puls.
    public mutating func flushStop(now: Date) -> [Action] {
        guard isArmed else { return [] }
        var ut: [Action] = []
        if case .stopping = phase {} else { ut += stop(now: now, reason: .terminate) }
        for step in queue {
            let c = command(for: step)
            awaiting.append((c, now))
            lastStep = step
            ut.append(.write(c))
        }
        queue = []
        finishStop(now: now)
        return ut
    }

    // MARK: Inuti

    private mutating func finishStop(now: Date) {
        phase = .off
        progress.stoppedAt = now
    }

    private mutating func command(for step: Step) -> WhoopCommand {
        let s = nextSequence
        nextSequence = nextSequence &+ 1
        return .realtimeHeartRate(on: step == .on, sequence: s)
    }

    private mutating func response(_ r: CommandResponse) -> [Action] {
        guard let i = awaiting.firstIndex(where: {
            $0.command.number.rawValue == r.command && $0.command.sequence == r.sequence
        }) else { return [] }
        let c = awaiting[i].command
        // Mätt på 145: först 2, sedan 1. Vänta på nästa svar efter en 2:a.
        guard r.result != 2 else { return [] }
        awaiting.remove(at: i)
        guard c.payload == [0x01] else { return [] }
        progress.startResults.append(r.result)
        // Bandet sade nej: inga fler försök (passet kan ändå få 2A37).
        if r.result != 1 { startsWithoutPulse = config.maxStartsWithoutPulse }
        return [.mark("puls-svar \(r.result)")]
    }

    private mutating func expireResponses(now: Date) {
        while let first = awaiting.first, now.timeIntervalSince(first.sentAt) > config.commandTimeout {
            awaiting.removeFirst()
            if first.command.payload == [0x01] { progress.startResults.append(nil) }
        }
    }
}
