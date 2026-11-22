import Foundation
import HeartRate

/// METOD M43 · BESLUT B53 · BESLUT B3
/// IMU-provet: bandets rörelse i 100 Hz under en begränsad stund, på
/// användaren knapptryck. En tillståndsmaskin utan Bluetooth och utan klocka,
/// som `HistorySession`: appen matar in tider, hela ramar och misslyckade
/// skrivningar, och utför det maskinen svarar (`Action`).
///
/// - **Start:** START_RAW_DATA (81) `01`, sedan TOGGLE_IMU_MODE (106) `01 01`,
///   med `commandSpacing` emellan (NOOP:s ordning, prövad på en Whoop 5/MG med
///   Android; goose skickar med 0,25 s mellanrum).
/// - **Stopp:** STOP_RAW_DATA (82) `01`, sedan 106 `01 00` (NOOP:s ordning).
///   Samma två kommandon oavsett varför provet stoppas.
/// - **Skydden:** (a) provet stoppas efter `hardTimeout`; (b) kommer
///   realtidsrörelse (typ 43 med layout 21, eller typ 51) när inget prov pågår
///   skickas stoppet, högst en gång per `failsafeRepeat` och tidigast
///   `failsafeGrace` efter ett eget stopp (NOOP:s skydd); (c) appen stoppar när
///   användaren trycker, när den avslutas (`flushStop`) och, om den dog under
///   ett prov, vid nästa start (`stopAtStart`).
/// - **Tystnaden** (`watch`, METOD M43): är länken uppe men ingen rörelseram
///   kommit på `silenceLimit` medan provet är på skrivs `imu tyst` i sidofilen,
///   och `imu igen` vid nästa ram. Ingen ny start skickas: bandet tog upp
///   strömmen själv efter en återanslutning 2026-10-14.
///
/// Maskinen räknar bara ramar, byte och svar — aldrig ett värde ur rörelsen
/// (BESLUT B3). Ramarna sparas råa i dygnsfilen som alla andra notiser.
public struct ImuControl: Sendable {
    public struct Config: Equatable, Sendable {
        /// **antagande**, användaren första prov: 30 min. Provet stoppas då.
        public var hardTimeout: TimeInterval = 30 * 60
        /// goose: 0,25 s mellan kommandona. **antagande** att det räcker.
        public var commandSpacing: TimeInterval = 0.25
        /// **antagande**. Ett svar som inte kommit så här länge räknas som uteblivet.
        public var commandTimeout: TimeInterval = 10
        /// NOOP: 3 s. Rörelse så här länge efter ett eget stopp är väntad
        /// (bandet hinner skicka det som redan var på väg). **antagande**: 5 s.
        public var failsafeGrace: TimeInterval = 5
        /// NOOP: 30 s mellan två stopp ur skyddet.
        public var failsafeRepeat: TimeInterval = 30
        /// **antagande**. Ny skrivning av stoppet efter en misslyckad.
        public var retryDelay: TimeInterval = 2
        /// **antagande**. Så många gånger skrivs ett stopp innan maskinen ger upp
        /// (skyddet tar det igen om rörelsen fortsätter).
        public var maxStopAttempts = 5
        /// Provets första sekvens; skild från hämtningens (som börjar på 1).
        public var firstSequence: UInt8 = 101
        /// METOD M43. **antagande**: tre buffertar (en i sekunden, mätt
        /// 2026-10-14) utan rörelse med länken uppe räknas som tystnad.
        public var silenceLimit: TimeInterval = 3
        public init() {}
    }

    /// BESLUT B53. Märkena för provets delar (sittningskortet i PLAN.md). Ett
    /// märke gäller till nästa märke; `tools/imu_analys.py` läser samma ord.
    public static let markerLabels = ["still", "rotera x", "rotera y", "rotera z", "sving", "chip", "putt", "paus"]

    public enum StopReason: String, Equatable, Sendable {
        /// användaren stoppade.
        case user = "knapp"
        /// `hardTimeout` nådd.
        case timeout = "tid"
        /// Bandet svarade något annat än 1 eller 2 på ett startkommando.
        case refused = "nej"
        /// Ett startkommando gick inte att skriva.
        case writeFailed = "skrivfel"
        /// Skyddet: realtidsrörelse utan prov.
        case unexpected = "skydd"
        /// Appen dog under ett prov; stoppet skickas vid nästa start.
        case restart = "omstart"
        /// Appen avslutas.
        case terminate = "avslut"
    }

    public enum Phase: Equatable, Sendable {
        case off, starting, on
        case stopping(StopReason)
    }

    public enum Action: Equatable, Sendable {
        /// Skriv kommandot till `…0002` (med svar), genom `BandSender`.
        case write(WhoopCommand)
        /// Ett märke i dygnets sidofil (`imu-start`, `imu-stopp <orsak>`).
        case mark(String)
        /// METOD M43. En länkrad i sidofilen (`imu tyst`, `imu igen`); inget märke.
        case link(RecordingLog.Link)
    }

    /// METOD M43. Vilken sorts rörelseram, ur inre byte 0 och 1.
    public enum Kind: Equatable, Sendable {
        /// Typ 43 med layout 21: sex axlar, 100 prov per axel och sekund (R21).
        case r21
        /// Typ 43 med annan layout (NOOP: R16/R17, EKG och optik).
        case other43
        /// Typ 51, realtidsströmmen med antal och spann. Layouten är dokumenterad
        /// men inte sedd från ett band.
        case stream51
        /// Typ 52, den lagrade varianten av 51.
        case stream52

        public init?(inner: [UInt8]) {
            guard let t = inner.first else { return nil }
            switch t {
            case 43: self = inner.count > 1 && inner[1] == 21 ? .r21 : .other43
            case 51: self = .stream51
            case 52: self = .stream52
            default: return nil
            }
        }

        /// Det skyddet reagerar på: realtidsrörelse som provet själv slår på.
        public var isRealtimeImu: Bool { self == .r21 || self == .stream51 }
    }

    /// Ett svar på ett av provets kommandon. `result` är `nil` om inget svar
    /// kom inom `commandTimeout`.
    public struct Response: Equatable, Sendable {
        public var command: UInt8
        /// För 106: på (`true`) eller av (`false`); `nil` för 81 och 82.
        public var on: Bool?
        public var result: UInt8?
    }

    /// Bara antal och tider (BESLUT B3).
    public struct Progress: Equatable, Sendable {
        public var startedAt: Date?
        public var stoppedAt: Date?
        public var stopReason: StopReason?
        public var r21Frames = 0
        public var other43Frames = 0
        public var stream51Frames = 0
        public var stream52Frames = 0
        /// Rörelseramar med fel CRC32.
        public var corruptFrames = 0
        /// Rörelseramarnas byte (inre del).
        public var imuBytes = 0
        public var lastImuAt: Date?
        public var responses: [Response] = []
        /// METOD M43. Gånger rörelsen tystnat med länken uppe (`watch`).
        public var silences = 0
        public init() {}

        public var imuFrames: Int { r21Frames + stream51Frames + stream52Frames }
    }

    private enum Step: Equatable, Sendable {
        case startRaw, imuOn, stopRaw, imuOff
    }

    public private(set) var phase: Phase = .off
    public private(set) var progress = Progress()
    /// Gånger skyddet skickat stoppet sedan appen startade.
    public private(set) var failsafeStops = 0
    public let config: Config

    private var queue: [Step] = []
    private var nextWriteAt: Date
    private var lastStep: Step?
    private var awaiting: [(command: WhoopCommand, sentAt: Date)] = []
    private var nextSequence: UInt8
    private var stopAttempts = 0
    private var lastOwnStop = Date.distantPast
    private var lastFailsafe = Date.distantPast
    /// METOD M43. Från när tystnaden räknas (provet på och länken uppe), och
    /// om `imu tyst` redan skrivits för den här tystnaden.
    private var watchFrom: Date?
    private var silent = false

    /// `stopAtStart`: appen dog under ett prov (sparat i appen). Stoppet läggs
    /// i kön direkt och skrivs när bandet går att skriva till.
    public init(now: Date, config: Config = Config(), stopAtStart: Bool = false) {
        self.config = config
        nextWriteAt = now
        nextSequence = config.firstSequence
        if stopAtStart {
            phase = .stopping(.restart)
            queue = [.stopRaw, .imuOff]
        }
    }

    /// Ett prov pågår eller håller på att stoppas. Appen sparar det, så att en
    /// omstart vet att stoppet ska skickas (`stopAtStart`).
    public var isArmed: Bool { phase != .off }

    /// Något väntar på att skrivas: appen ser till att skrivkarakteristiken finns.
    public var wantsWrite: Bool { !queue.isEmpty }

    /// Sekunder kvar till `hardTimeout`, medan provet är på.
    public func remaining(now: Date) -> TimeInterval? {
        guard phase == .starting || phase == .on, let s = progress.startedAt else { return nil }
        return max(0, config.hardTimeout - now.timeIntervalSince(s))
    }

    // MARK: Indata

    /// användaren knapptryck. Bara från av.
    public mutating func start(now: Date) -> [Action] {
        guard phase == .off, queue.isEmpty else { return [] }
        progress = Progress()
        progress.startedAt = now
        phase = .starting
        watchFrom = nil
        silent = false
        stopAttempts = 0
        queue = [.startRaw, .imuOn]
        nextWriteAt = max(nextWriteAt, now)
        return [.mark("imu-start")]
    }

    /// Stoppar provet (eller en oväntad ström). Ett stopp som redan pågår
    /// görs inte om.
    public mutating func stop(now: Date, reason: StopReason) -> [Action] {
        if case .stopping = phase { return [] }
        if phase == .off && reason != .unexpected && reason != .restart { return [] }
        phase = .stopping(reason)
        progress.stopReason = reason
        stopAttempts = 0
        watchFrom = nil
        silent = false
        queue = [.stopRaw, .imuOff]
        nextWriteAt = max(nextWriteAt, now)
        return [.mark("imu-stopp " + reason.rawValue)]
    }

    /// Klockan, helst fyra gånger i sekunden medan `isArmed` eller `wantsWrite`.
    /// `canWrite`: bandet är anslutet, skrivkarakteristiken funnen och ingen
    /// hämtning pågår.
    public mutating func tick(now: Date, canWrite: Bool) -> [Action] {
        var ut: [Action] = []
        expireResponses(now: now)
        if phase == .starting || phase == .on, let s = progress.startedAt,
           now.timeIntervalSince(s) >= config.hardTimeout {
            ut += stop(now: now, reason: .timeout)
        }
        guard canWrite, !queue.isEmpty, now >= nextWriteAt else { return ut }
        let step = queue.removeFirst()
        let c = command(for: step)
        awaiting.append((c, now))
        lastStep = step
        nextWriteAt = now.addingTimeInterval(config.commandSpacing)
        if step == .stopRaw { stopAttempts += 1 }
        ut.append(.write(c))
        if queue.isEmpty {
            switch phase {
            case .starting: phase = .on
            case .stopping: finishStop(now: now)
            default: break
            }
        }
        return ut
    }

    /// En hel ram från någon av Whoops karakteristiker.
    public mutating func receive(_ f: FrameAssembly.Frame, now: Date) -> [Action] {
        if f.crc32OK, let r = CommandResponse(inner: f.inner) { return response(r, now: now) }
        guard let kind = Kind(inner: f.inner) else { return [] }
        guard f.crc32OK else {
            if phase != .off { progress.corruptFrames += 1 }
            return []
        }
        if phase != .off {
            switch kind {
            case .r21: progress.r21Frames += 1
            case .other43: progress.other43Frames += 1
            case .stream51: progress.stream51Frames += 1
            case .stream52: progress.stream52Frames += 1
            }
            if kind != .other43 {
                progress.imuBytes += f.inner.count
                progress.lastImuAt = now
                if silent {
                    silent = false
                    return [.link(.imuResumed)]
                }
            }
            return []
        }
        // Skyddet (b): realtidsrörelse utan prov.
        guard kind.isRealtimeImu,
              now.timeIntervalSince(lastOwnStop) >= config.failsafeGrace,
              now.timeIntervalSince(lastFailsafe) >= config.failsafeRepeat else { return [] }
        lastFailsafe = now
        failsafeStops += 1
        return stop(now: now, reason: .unexpected)
    }

    /// METOD M43. Tystnaden: anropas med klockan (som `tick`). `linkUp`: bandet
    /// är anslutet. Medan provet är på och länken uppe räknas tiden från det
    /// senaste av provet på, länken uppe och senaste rörelseramen; över
    /// `silenceLimit` blir det ett `imu tyst`, en gång per tystnad. Går
    /// länken ner börjar räkningen om (frånkopplingen har en egen rad).
    public mutating func watch(now: Date, linkUp: Bool) -> [Action] {
        guard phase == .on, linkUp else {
            watchFrom = nil
            silent = false
            return []
        }
        let från = watchFrom ?? now
        watchFrom = från
        guard !silent else { return [] }
        let senast = max(från, progress.lastImuAt ?? .distantPast)
        guard now.timeIntervalSince(senast) > config.silenceLimit else { return [] }
        silent = true
        progress.silences += 1
        return [.link(.imuSilent)]
    }

    /// Den senaste skrivningen gick inte fram (`BandSender` sade nej, eller
    /// bandet svarade med fel på skrivningen). Ett start blir ett stopp; ett
    /// stopp görs om, högst `maxStopAttempts` gånger.
    public mutating func writeFailed(now: Date) -> [Action] {
        switch phase {
        case .starting, .on:
            if lastStep == .startRaw || lastStep == .imuOn {
                return stop(now: now, reason: .writeFailed)
            }
            return []
        case .stopping(let reason):
            return retryStop(now: now, reason: reason)
        case .off:
            // Felet kom efter att stoppets sista kommando skrivits.
            guard let reason = progress.stopReason, lastStep == .stopRaw || lastStep == .imuOff else { return [] }
            return retryStop(now: now, reason: reason)
        }
    }

    /// Appen avslutas: stoppets kommandon på en gång, utan mellanrum. Bara om
    /// ett prov pågår.
    public mutating func flushStop(now: Date) -> [Action] {
        guard isArmed else { return [] }
        var ut: [Action] = []
        if case .stopping = phase {} else {
            ut += stop(now: now, reason: .terminate)
        }
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

    private mutating func retryStop(now: Date, reason: StopReason) -> [Action] {
        guard stopAttempts < config.maxStopAttempts else {
            queue = []
            finishStop(now: now)
            return []
        }
        phase = .stopping(reason)
        queue = [.stopRaw, .imuOff]
        nextWriteAt = now.addingTimeInterval(config.retryDelay)
        return []
    }

    private mutating func finishStop(now: Date) {
        phase = .off
        progress.stoppedAt = now
        lastOwnStop = now
    }

    private mutating func command(for step: Step) -> WhoopCommand {
        let s = nextSequence
        nextSequence = nextSequence &+ 1
        switch step {
        case .startRaw: return .startRawData(sequence: s)
        case .imuOn: return .imuMode(on: true, sequence: s)
        case .stopRaw: return .stopRawData(sequence: s)
        case .imuOff: return .imuMode(on: false, sequence: s)
        }
    }

    private static func label(_ c: WhoopCommand) -> Response {
        let on: Bool? = c.number == .toggleImuMode ? c.payload == [0x01, 0x01] : nil
        return Response(command: c.number.rawValue, on: on, result: nil)
    }

    private mutating func response(_ r: CommandResponse, now: Date) -> [Action] {
        guard let i = awaiting.firstIndex(where: {
            $0.command.number.rawValue == r.command && $0.command.sequence == r.sequence
        }) else { return [] }
        let c = awaiting[i].command
        var svar = Self.label(c)
        svar.result = r.result
        progress.responses.append(svar)
        // Mätt på 145: först 2, sedan 1. Vänta på nästa svar efter en 2:a.
        if r.result != 2 { awaiting.remove(at: i) }
        let start = c.number == .startRawData || (c.number == .toggleImuMode && c.payload == [0x01, 0x01])
        if start, r.result != 1, r.result != 2, phase == .starting || phase == .on {
            return stop(now: now, reason: .refused)
        }
        return []
    }

    private mutating func expireResponses(now: Date) {
        while let first = awaiting.first, now.timeIntervalSince(first.sentAt) > config.commandTimeout {
            awaiting.removeFirst()
            progress.responses.append(Self.label(first.command))
        }
    }
}
