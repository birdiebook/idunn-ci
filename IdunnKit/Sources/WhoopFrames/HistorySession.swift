import Foundation

/// METOD M23 · BESLUT B25
/// Bandets HISTORY_END (metadata, typ 49, i2 = 2). Uppmätt på användaren band
/// 2026-10-12 (PROTOKOLL_W5 §6.1): 24 byte inre del, i9 u32 = antal poster i
/// biten, i13–i20 = de åtta byte som kvittensen bär (end_data, första u32 =
/// bandets trimmarkör). En bit utan poster har end_data `FF ×8`.
public struct HistoryEnd: Equatable, Sendable {
    public static let endDataOffset = 13
    public static let endDataLength = 8
    public static let recordsOffset = 9

    /// Poster i biten enligt bandet: allt på `…0005` mellan START och END.
    public var records: UInt32
    /// i13–i20, ordagrant.
    public var endData: [UInt8]

    public init?(inner: [UInt8]) {
        guard inner.count >= Self.endDataOffset + Self.endDataLength,
              inner[0] == HistoryMeta.packetType, inner[2] == 2,
              let n = FrameAssembly.u32(inner, at: Self.recordsOffset) else { return nil }
        records = n
        endData = Array(inner[Self.endDataOffset..<(Self.endDataOffset + Self.endDataLength)])
    }

    /// Trimmarkören: end_datas första u32.
    public var trimCursor: UInt32 { FrameAssembly.u32(endData, at: 0) ?? 0 }

    /// Ett slut utan poster (`FF ×8`). Whoop-appen kvitterade aldrig ett sådant
    /// (mätt), och Idunn gör det inte heller.
    public var isEmpty: Bool { endData.allSatisfy { $0 == 0xFF } }
}

/// METOD M23. Synkens markeringar, metadata typ 49 med i2 = 1, 2, 3.
public enum HistoryMeta: Equatable, Sendable {
    public static let packetType: UInt8 = 49

    case start
    case end(HistoryEnd)
    case complete

    public init?(inner: [UInt8]) {
        guard inner.count >= 3, inner[0] == Self.packetType else { return nil }
        switch inner[2] {
        case 1: self = .start
        case 2:
            guard let e = HistoryEnd(inner: inner) else { return nil }
            self = .end(e)
        case 3: self = .complete
        default: return nil
        }
    }
}

/// METOD M23. Bandets svar på ett kommando (typ 36): i2 kommandot, i3 dess
/// sekvens, i4 resultatet (1 = lyckat). Mätt 2026-10-12.
public struct CommandResponse: Equatable, Sendable {
    public static let packetType: UInt8 = 36

    public var command: UInt8
    public var sequence: UInt8
    public var result: UInt8

    public init?(inner: [UInt8]) {
        guard inner.count >= 5, inner[0] == Self.packetType else { return nil }
        command = inner[2]
        sequence = inner[3]
        result = inner[4]
    }
}

/// METOD M23 · BESLUT B25
/// En hämtning av bandets historik, som tillståndsmaskin utan Bluetooth och
/// utan klocka: appen matar in ramar, tider och utfallet av sparandet, och
/// utför det maskinen svarar (`Action`).
///
/// Ordningen: CLIENT_HELLO (145) → svar → SEND_HISTORICAL_DATA (22) → svar →
/// för varje bit HISTORY_START, poster, HISTORY_END → **spara** → kvittens
/// (23) → svar … → HISTORY_COMPLETE. Kvittensen skickas bara när
///
/// - biten är sparad varaktigt (`saved(ok: true)` efter `.saveThenAck`),
/// - antalet hela ramar på `…0005` sedan START (eller förra END) är exakt
///   det bandet anger i END (i9), och ingen av dem hade fel CRC32,
/// - END inte är tomt (`FF ×8`) och inte samma som redan kvitterats.
///
/// Allt oväntat stoppar hämtningen utan kvittens: ett svar med annat resultat
/// än 1 (145 får först svara 2, mätt), ett svar på ett kommando Idunn inte
/// skickat (Whoop-appen synkar samtidigt), tystnad, fel antal, fel summa,
/// misslyckat sparande eller skrivning, tappat band. Det som inte kvitterats
/// ligger kvar i bandet.
public struct HistorySession: Sendable {
    public struct Config: Equatable, Sendable {
        /// Karakteristiken som bär historiken och synkens markeringar (mätt).
        public var historyCharacteristic = "fd4b0005"
        /// **antagande** (NOOP:s 60 s). Utan en enda ram på historiken så här
        /// länge under hämtningen stoppas den.
        public var idleTimeout: TimeInterval = 60
        /// **antagande**. Så länge ett kommando får vänta på sitt svar.
        public var commandTimeout: TimeInterval = 15
        /// **antagande**. Så länge bandet får ta på sig att bli anslutet och
        /// prenumererat innan hälsningen går.
        public var connectTimeout: TimeInterval = 30
        /// Hälsningens sekvens; 1 ger den dokumenterade ramen.
        public var firstSequence: UInt8 = 1
        public init() {}
    }

    public enum StopReason: Equatable, Sendable {
        /// Bandet svarade med ett annat resultat än väntat.
        case unexpectedResponse(command: UInt8, result: UInt8)
        /// Inget svar på kommandot inom `commandTimeout`.
        case noResponse(command: UInt8)
        /// Ett svar på ett kommando Idunn inte skickat, eller en synk Idunn
        /// inte begärt: en annan app (Whoop) pratar med bandet samtidigt.
        case otherApp(command: UInt8)
        /// Inga ramar på historiken inom `idleTimeout`.
        case idle
        /// Bandet kom aldrig så långt att hälsningen kunde skickas.
        case notConnected
        /// END angav ett annat antal poster än som kom fram hela.
        case countMismatch(expected: Int, received: Int)
        /// En ram på historiken hade fel CRC32.
        case corruptFrame
        /// Ett nytt END kom medan förra biten sparades eller kvitterades.
        case unexpectedEnd
        /// Biten gick inte att spara varaktigt.
        case saveFailed
        /// Skrivningen till bandet misslyckades.
        case writeFailed
        case disconnected
        /// Avbruten i appen.
        case cancelled
    }

    public enum Outcome: Equatable, Sendable {
        case complete
        case stopped(StopReason)
    }

    public enum Action: Equatable, Sendable {
        /// Skriv kommandot till `…0002` (med svar).
        case write(WhoopCommand)
        /// Spara allt som kommit varaktigt, och svara med `saved(ok:now:)`.
        case saveThenAck
        /// Hämtningen är slut.
        case finish(Outcome)
    }

    public enum State: Equatable, Sendable {
        case waitingForBand, hello, requesting, receiving, saving, acking
        case finished(Outcome)
    }

    /// Bara antal och tider — inga värden ur posterna (BESLUT B3).
    public struct Progress: Equatable, Sendable {
        /// Kvitterade bitar.
        public var chunks = 0
        /// Poster i kvitterade bitar (allt på `…0005` utom markeringarna).
        public var records = 0
        /// K18-poster (typ 47, i1 = 18), en per sekund, i kvitterade bitar.
        public var k18Seconds = 0
        /// Första och sista K18-postens egen tid (posthuvudets i7).
        public var first: Date?
        public var last: Date?
        /// Tomma slut (`FF ×8`), som inte kvitteras.
        public var emptyEnds = 0
        public init() {}
    }

    public private(set) var state: State = .waitingForBand
    public private(set) var progress = Progress()
    public let config: Config

    private let createdAt: Date
    private var nextSequence: UInt8
    private var pending: (command: WhoopCommand.Number, sequence: UInt8, sentAt: Date)?
    private var sent: [(command: UInt8, sequence: UInt8)] = []
    private var lastActivity: Date
    private var chunkOpen = false
    private var chunk = Progress()
    /// Biten som sparas och kvitteras just nu; räknas in när bandet svarat.
    private var ackChunk = Progress()
    private var chunkCount = 0
    private var currentEnd: HistoryEnd?
    private var lastAcked: [UInt8]?
    private var completeSeen = false

    public init(now: Date, config: Config = Config()) {
        self.config = config
        createdAt = now
        lastActivity = now
        nextSequence = config.firstSequence
    }

    public var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    // MARK: Indata

    /// Bandet är anslutet och `…0003` och `…0005` prenumereras: hälsningen går.
    public mutating func start(now: Date) -> [Action] {
        guard state == .waitingForBand else { return [] }
        state = .hello
        return [record(.clientHello(sequence: takeSequence()), now: now)]
    }

    /// En hel ram från någon av Whoops karakteristiker.
    public mutating func receive(_ f: FrameAssembly.Frame, now: Date) -> [Action] {
        if isFinished { return [] }
        let history = f.characteristic == config.historyCharacteristic
        if !f.crc32OK {
            return history && chunkOpen ? stop(.corruptFrame) : []
        }
        if let r = CommandResponse(inner: f.inner) { return response(r, now: now) }
        guard history else { return [] }
        if let m = HistoryMeta(inner: f.inner) { return meta(m, now: now) }
        guard f.type != Int(HistoryMeta.packetType), chunkOpen else { return [] }
        lastActivity = now
        chunkCount += 1
        chunk.records += 1
        // METOD M23 · PROTOKOLL_W5 §6: K18 = typ 47, i1 = 18, tid i i7.
        if f.inner.count > 10, f.inner[0] == 47, f.inner[1] == 18 {
            chunk.k18Seconds += 1
            if let t = FrameAssembly.u32(f.inner, at: 7) {
                let d = Date(timeIntervalSince1970: TimeInterval(t))
                chunk.first = min(chunk.first ?? d, d)
                chunk.last = max(chunk.last ?? d, d)
            }
        }
        return []
    }

    /// Svaret på `.saveThenAck`: `ok` bara om allt som kommit är varaktigt sparat.
    public mutating func saved(ok: Bool, now: Date) -> [Action] {
        guard state == .saving, let e = currentEnd else { return [] }
        guard ok else { return stop(.saveFailed) }
        state = .acking
        lastAcked = e.endData
        let seq = takeSequence()
        let c = WhoopCommand.historicalDataResult(sequence: seq, end: e)
        return [record(c, now: now)]
    }

    /// Klockan, gärna en gång i sekunden.
    public mutating func tick(now: Date) -> [Action] {
        if isFinished { return [] }
        if state == .waitingForBand {
            return now.timeIntervalSince(createdAt) > config.connectTimeout ? stop(.notConnected) : []
        }
        if let p = pending, now.timeIntervalSince(p.sentAt) > config.commandTimeout {
            return stop(.noResponse(command: p.command.rawValue))
        }
        if state == .receiving, now.timeIntervalSince(lastActivity) > config.idleTimeout {
            return stop(.idle)
        }
        return []
    }

    public mutating func writeFailed() -> [Action] { isFinished ? [] : stop(.writeFailed) }
    public mutating func disconnected() -> [Action] { isFinished ? [] : stop(.disconnected) }
    public mutating func cancel() -> [Action] { isFinished ? [] : stop(.cancelled) }

    // MARK: Inuti

    private mutating func response(_ r: CommandResponse, now: Date) -> [Action] {
        guard let p = pending, r.command == p.command.rawValue, r.sequence == p.sequence else {
            // Ett sent svar på något Idunn redan skickat är ofarligt.
            if sent.contains(where: { $0.command == r.command && $0.sequence == r.sequence }) { return [] }
            return stop(.otherApp(command: r.command))
        }
        // Mätt: första svaret på 145 har resultat 2, sedan kommer 1 med data.
        if p.command == .clientHello && r.result == 2 { return [] }
        guard r.result == 1 else { return stop(.unexpectedResponse(command: r.command, result: r.result)) }
        pending = nil
        lastActivity = now
        switch p.command {
        case .clientHello:
            state = .requesting
            return [record(.sendHistoricalData(sequence: takeSequence()), now: now)]
        case .sendHistoricalData:
            if state == .requesting { state = .receiving }
            return []
        case .historicalDataResult:
            progress.chunks += 1
            progress.records += ackChunk.records
            progress.k18Seconds += ackChunk.k18Seconds
            if let a = ackChunk.first { progress.first = min(progress.first ?? a, a) }
            if let b = ackChunk.last { progress.last = max(progress.last ?? b, b) }
            ackChunk = Progress()
            currentEnd = nil
            state = .receiving
            return completeSeen ? finish(.complete) : []
        case .startRawData, .stopRawData, .toggleImuMode, .toggleRealtimeHr:
            // BESLUT B53. Hämtningen skickar aldrig IMU-provets kommandon.
            return stop(.otherApp(command: r.command))
        }
    }

    private mutating func meta(_ m: HistoryMeta, now: Date) -> [Action] {
        switch state {
        case .waitingForBand, .hello:
            // Idunn har inte bett om historiken: någon annan synkar.
            return stop(.otherApp(command: WhoopCommand.Number.sendHistoricalData.rawValue))
        default: break
        }
        lastActivity = now
        switch m {
        case .start:
            if state == .requesting { state = .receiving }
            chunkOpen = true
            chunkCount = 0
            chunk = Progress()
            return []
        case .end(let e):
            if lastAcked == e.endData { return [] }  // samma END en gång till (mätt)
            if state == .saving || state == .acking {
                return currentEnd?.endData == e.endData ? [] : stop(.unexpectedEnd)
            }
            if e.isEmpty {
                progress.emptyEnds += 1
                chunkCount = 0
                chunk = Progress()
                return []
            }
            guard chunkOpen, Int(e.records) == chunkCount else {
                return stop(.countMismatch(expected: Int(e.records), received: chunkOpen ? chunkCount : 0))
            }
            chunkCount = 0
            ackChunk = chunk
            chunk = Progress()
            currentEnd = e
            state = .saving
            return [.saveThenAck]
        case .complete:
            if state == .saving || state == .acking {
                completeSeen = true
                return []
            }
            return finish(.complete)
        }
    }

    private mutating func record(_ c: WhoopCommand, now: Date) -> Action {
        pending = (c.number, c.sequence, now)
        sent.append((c.number.rawValue, c.sequence))
        return .write(c)
    }

    private mutating func takeSequence() -> UInt8 {
        let s = nextSequence
        nextSequence = nextSequence == UInt8.max ? 1 : nextSequence + 1
        return s
    }

    private mutating func finish(_ o: Outcome) -> [Action] {
        state = .finished(o)
        pending = nil
        return [.finish(o)]
    }

    private mutating func stop(_ r: StopReason) -> [Action] { finish(.stopped(r)) }
}
