import Foundation

/// BESLUT B25 · BESLUT B53 · BESLUT B61 · METOD M12 · METOD M23 · METOD M43 · METOD M48
/// Det enda Idunn kan skicka till bandet: ett kommando (pakettyp 35) till
/// skrivkarakteristiken `…0002`. Bara sju nummer går att bygga —
/// **145** CLIENT_HELLO, **22** SEND_HISTORICAL_DATA och **23**
/// HISTORICAL_DATA_RESULT för hämtningen (B25), **81** START_RAW_DATA,
/// **82** STOP_RAW_DATA och **106** TOGGLE_IMU_MODE för IMU-provet (B53), och
/// **3** TOGGLE_REALTIME_HR för passets puls (B61) — och bara med den
/// nyttolast respektive väg kräver.
///
/// Spärren sitter i typen: numret är en `Number` med just sju fall, och
/// initieraren är privat. Ett godtyckligt nummer kan bara pröva sig in genom
/// `checked(command:sequence:payload:)`, som avvisar allt utanför listan och
/// säger särskilt till om det är ett av de farliga (`denied`).
///
/// Ramen (METOD M12, PROTOKOLL_W5 §1): `AA 01`, längd (u16 LE = inre del + 4),
/// `00 01`, CRC16-Modbus över byte 0–5 (LE), inre del `[35, sekvens, nummer]
/// + nyttolast` utfylld med nollor till en multipel av 4, CRC32 (zlib) över
/// den inre delen (LE). Den dokumenterade CLIENT_HELLO räknas fram byte för byte.
public struct WhoopCommand: Equatable, Sendable {
    /// BESLUT B25 · BESLUT B53 · BESLUT B61. De sju kommandon Idunn får skicka.
    public enum Number: UInt8, CaseIterable, Sendable {
        case clientHello = 145
        case sendHistoricalData = 22
        case historicalDataResult = 23
        /// METOD M43. START_RAW_DATA, nyttolast `01`.
        case startRawData = 81
        /// METOD M43. STOP_RAW_DATA, nyttolast `01`.
        case stopRawData = 82
        /// METOD M43. TOGGLE_IMU_MODE, nyttolast `01 01` (på) eller `01 00` (av).
        case toggleImuMode = 106
        /// METOD M48 · BESLUT B61. TOGGLE_REALTIME_HR, nyttolast `01` (på) eller `00` (av).
        case toggleRealtimeHr = 3
    }

    /// BESLUT B25. Raderar data, startar om bandet, skriver firmware eller
    /// nollställer batterimätaren (NOOP `docs/PROTOCOL.md` §6). BESLUT B53:
    /// dessutom **63** (realtidsströmmen R10/R11; svarar "stöds inte" på Whoop 5
    /// 50.42.1.0) och **153/154** (beständig R20/R21, en bestående
    /// tillståndsändring i bandet). Får aldrig skickas; `checked` avvisar dem
    /// med `.denied`.
    public static let denied: Set<UInt8> = [25, 29, 32, 36, 37, 38, 45, 63, 99, 153, 154]

    public enum BuildError: Error, Equatable, Sendable {
        /// Ett av de farliga kommandona.
        case denied(UInt8)
        /// Inte ett av de sju tillåtna.
        case notAllowed(UInt8)
        /// Rätt nummer men fel nyttolast.
        case badPayload(UInt8)
    }

    /// METOD M12. Skrivkarakteristiken i Whoops tjänst.
    public static let characteristic = "FD4B0002-CCE1-4033-93CE-002D5875F58A"
    /// METOD M12. Pakettypen COMMAND.
    public static let packetType: UInt8 = 35

    public let number: Number
    public let sequence: UInt8
    public let payload: [UInt8]
    /// Hela ramen, som den skrivs till `…0002`.
    public let frame: [UInt8]

    private init(number: Number, sequence: UInt8, payload: [UInt8]) {
        self.number = number
        self.sequence = sequence
        self.payload = payload
        self.frame = Self.encode(number: number.rawValue, sequence: sequence, payload: payload)
    }

    /// METOD M12. CLIENT_HELLO med nyttolasten `01`. Med sekvens 1 blir ramen
    /// den dokumenterade `AA 01 08 00 00 01 E6 71 23 01 91 01 36 3E 5C 8D`.
    public static func clientHello(sequence: UInt8 = 1) -> WhoopCommand {
        WhoopCommand(number: .clientHello, sequence: sequence, payload: [0x01])
    }

    /// METOD M23. SEND_HISTORICAL_DATA utan nyttolast (goose för Whoop 5).
    /// Utfyllnaden gör den inre delen till `[35, sekvens, 22, 00]`, samma byte
    /// som NOOP:s `[0x00]` för Whoop 4.
    public static func sendHistoricalData(sequence: UInt8) -> WhoopCommand {
        WhoopCommand(number: .sendHistoricalData, sequence: sequence, payload: [])
    }

    /// METOD M23. Kvittensen på en bit: `[0x01]` + de åtta byten ur bitens
    /// HISTORY_END (i13–i20). Först när bandet tagit emot den får det glömma biten.
    public static func historicalDataResult(sequence: UInt8, end: HistoryEnd) -> WhoopCommand {
        WhoopCommand(number: .historicalDataResult, sequence: sequence, payload: [0x01] + end.endData)
    }

    /// METOD M43 · BESLUT B53. START_RAW_DATA (81) med `01`.
    public static func startRawData(sequence: UInt8) -> WhoopCommand {
        WhoopCommand(number: .startRawData, sequence: sequence, payload: [0x01])
    }

    /// METOD M43 · BESLUT B53. STOP_RAW_DATA (82) med `01`.
    public static func stopRawData(sequence: UInt8) -> WhoopCommand {
        WhoopCommand(number: .stopRawData, sequence: sequence, payload: [0x01])
    }

    /// METOD M43 · BESLUT B53. TOGGLE_IMU_MODE (106) med `01 01` (på) eller
    /// `01 00` (av). Den inre delen fylls ut till `[35, sekvens, 106, 01, på, 0, 0, 0]`.
    public static func imuMode(on: Bool, sequence: UInt8) -> WhoopCommand {
        WhoopCommand(number: .toggleImuMode, sequence: sequence, payload: [0x01, on ? 0x01 : 0x00])
    }

    /// METOD M48 · BESLUT B61. TOGGLE_REALTIME_HR (3) med `01` (på) eller `00`
    /// (av): bandet skickar pulsen i realtid (typ 40) medan den är på. Den inre
    /// delen fylls ut till `[35, sekvens, 3, på]`.
    public static func realtimeHeartRate(on: Bool, sequence: UInt8) -> WhoopCommand {
        WhoopCommand(number: .toggleRealtimeHr, sequence: sequence, payload: [on ? 0x01 : 0x00])
    }

    /// Den enda vägen in för ett godtyckligt nummer. Avvisar de farliga
    /// (`.denied`), allt utanför de sju (`.notAllowed`) och en nyttolast som
    /// vägen inte använder (`.badPayload`).
    public static func checked(command: UInt8, sequence: UInt8, payload: [UInt8]) throws -> WhoopCommand {
        if denied.contains(command) { throw BuildError.denied(command) }
        guard let n = Number(rawValue: command) else { throw BuildError.notAllowed(command) }
        let ok: Bool
        switch n {
        case .clientHello: ok = payload == [0x01]
        case .sendHistoricalData: ok = payload.isEmpty
        case .historicalDataResult: ok = payload.count == 1 + HistoryEnd.endDataLength && payload[0] == 0x01
        case .startRawData, .stopRawData: ok = payload == [0x01]
        case .toggleImuMode: ok = payload == [0x01, 0x01] || payload == [0x01, 0x00]
        case .toggleRealtimeHr: ok = payload == [0x01] || payload == [0x00]
        }
        guard ok else { throw BuildError.badPayload(command) }
        return WhoopCommand(number: n, sequence: sequence, payload: payload)
    }

    private static func encode(number: UInt8, sequence: UInt8, payload: [UInt8]) -> [UInt8] {
        var inner: [UInt8] = [packetType, sequence, number] + payload
        while inner.count % 4 != 0 { inner.append(0x00) }
        let length: Int = inner.count + 4
        var b: [UInt8] = [0xAA, 0x01, UInt8(length & 0xFF), UInt8((length >> 8) & 0xFF), 0x00, 0x01]
        let h: UInt16 = FrameAssembly.crc16Modbus(b)
        b.append(UInt8(h & 0xFF))
        b.append(UInt8(h >> 8))
        b.append(contentsOf: inner)
        let c: UInt32 = FrameAssembly.crc32(inner)
        for shift in [0, 8, 16, 24] { b.append(UInt8((c >> UInt32(shift)) & 0xFF)) }
        return b
    }
}
