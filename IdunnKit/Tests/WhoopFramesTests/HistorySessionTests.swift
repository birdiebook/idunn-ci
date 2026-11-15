import Foundation
import XCTest
@testable import WhoopFrames

// METOD M23 · BESLUT B25. Påhittade ramar med samma form som bandets
// (PROTOKOLL_W5 §6.1): kommandosvar typ 36, metadata typ 49 (START 40 byte,
// END 24 byte, COMPLETE 12 byte), K18-poster typ 47 med 112 byte, loggtext
// typ 50 och händelser typ 48. Inga byte kommer från ett riktigt band.

final class WhoopCommandTests: XCTestCase {
    func testHälsningenÄrDenDokumenteradeRamen() {
        let väntad: [UInt8] = [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71,
                               0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D]
        XCTAssertEqual(WhoopCommand.clientHello(sequence: 1).frame, väntad)
        XCTAssertEqual(WhoopCommand.clientHello().frame, väntad)
        XCTAssertEqual(try WhoopCommand.checked(command: 145, sequence: 1, payload: [0x01]).frame, väntad)
    }

    func testBaraSjuKommandonGårAttBygga() {
        // BESLUT B25 (145, 22, 23), BESLUT B53 (81, 82, 106) och BESLUT B61 (3).
        XCTAssertEqual(Set(WhoopCommand.Number.allCases.map(\.rawValue)), [145, 22, 23, 81, 82, 106, 3])
        XCTAssertTrue(WhoopCommand.denied.isDisjoint(with: WhoopCommand.Number.allCases.map(\.rawValue)))
        XCTAssertEqual(WhoopCommand.denied, [25, 29, 32, 36, 37, 38, 45, 63, 99, 153, 154])
        var byggda: Set<UInt8> = []
        for n in UInt8.min...UInt8.max {
            // Varje nummer får den nyttolast som skulle passa ett tillåtet kommando.
            for payload in [[], [0x01], [0x01] + [UInt8](repeating: 7, count: 8), [0x00],
                            [0x01, 0x01], [0x01, 0x00]] as [[UInt8]] {
                do {
                    let c = try WhoopCommand.checked(command: n, sequence: 9, payload: payload)
                    byggda.insert(c.number.rawValue)
                    XCTAssertEqual(c.frame[10], n)
                } catch WhoopCommand.BuildError.denied(let d) {
                    XCTAssertEqual(d, n)
                    XCTAssertTrue(WhoopCommand.denied.contains(n))
                } catch WhoopCommand.BuildError.notAllowed(let d) {
                    XCTAssertEqual(d, n)
                    XCTAssertFalse(WhoopCommand.denied.contains(n))
                    XCTAssertNil(WhoopCommand.Number(rawValue: n))
                } catch WhoopCommand.BuildError.badPayload(let d) {
                    XCTAssertNotNil(WhoopCommand.Number(rawValue: d))
                } catch {
                    XCTFail("oväntat fel \(error)")
                }
            }
        }
        XCTAssertEqual(byggda, [145, 22, 23, 81, 82, 106, 3])
    }

    /// METOD M43. Ramarna för IMU-provet, byte för byte. Facit räknat
    /// oberoende i Python (zlib.crc32 och CRC16-Modbus, samma ram som den
    /// dokumenterade hälsningen) och samma bygge som NOOP:s och goose:s
    /// rambyggare för Whoop 5: inre delen utfylld till en multipel av 4.
    func testImuKommandonasRamar() throws {
        XCTAssertEqual(WhoopCommand.startRawData(sequence: 1).frame,
                       [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71,
                        0x23, 0x01, 0x51, 0x01, 0x78, 0xE9, 0xA6, 0x46])
        XCTAssertEqual(WhoopCommand.imuMode(on: true, sequence: 2).frame,
                       [0xAA, 0x01, 0x0C, 0x00, 0x00, 0x01, 0xE7, 0x41,
                        0x23, 0x02, 0x6A, 0x01, 0x01, 0x00, 0x00, 0x00, 0x1C, 0xC9, 0xF7, 0xA9])
        XCTAssertEqual(WhoopCommand.stopRawData(sequence: 3).frame,
                       [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71,
                        0x23, 0x03, 0x52, 0x01, 0xD5, 0x6E, 0x0F, 0x6E])
        XCTAssertEqual(WhoopCommand.imuMode(on: false, sequence: 4).frame,
                       [0xAA, 0x01, 0x0C, 0x00, 0x00, 0x01, 0xE7, 0x41,
                        0x23, 0x04, 0x6A, 0x01, 0x00, 0x00, 0x00, 0x00, 0x43, 0x9B, 0x9B, 0x72])
        // Samma ramar genom den kontrollerade ingången, och andra nyttolaster avvisas.
        XCTAssertEqual(try WhoopCommand.checked(command: 106, sequence: 2, payload: [0x01, 0x01]).frame,
                       WhoopCommand.imuMode(on: true, sequence: 2).frame)
        XCTAssertEqual(try WhoopCommand.checked(command: 81, sequence: 1, payload: [0x01]).frame,
                       WhoopCommand.startRawData(sequence: 1).frame)
        for (n, p) in [(81, [0x00]), (82, []), (106, [0x01]), (106, [0x01, 0x02]), (106, [0x00, 0x01])]
            as [(UInt8, [UInt8])] {
            XCTAssertThrowsError(try WhoopCommand.checked(command: n, sequence: 1, payload: p)) { e in
                XCTAssertEqual(e as? WhoopCommand.BuildError, .badPayload(n))
            }
        }
        // 63, 153 och 154 är spärrade, inte bara okända.
        for n in [63, 153, 154] as [UInt8] {
            XCTAssertThrowsError(try WhoopCommand.checked(command: n, sequence: 1, payload: [0x01, 0x01])) { e in
                XCTAssertEqual(e as? WhoopCommand.BuildError, .denied(n))
            }
        }
        // Ramarna går ihop med Idunns egen ihopfogning och båda summorna.
        for c in [WhoopCommand.startRawData(sequence: 5), .stopRawData(sequence: 6),
                  .imuMode(on: true, sequence: 7), .imuMode(on: false, sequence: 8)] {
            let (frames, _) = FrameAssembly.assemble([RawFrame(time: Date(), characteristic: "fd4b0002", bytes: c.frame)])
            XCTAssertEqual(frames.count, 1)
            XCTAssertTrue(frames[0].crc32OK)
            XCTAssertEqual(Array(frames[0].inner.prefix(3)), [35, c.sequence, c.number.rawValue])
        }
    }

    func testDeFarligaAvvisasMedEgetFel() {
        for n in WhoopCommand.denied {
            XCTAssertThrowsError(try WhoopCommand.checked(command: n, sequence: 1, payload: [])) { e in
                XCTAssertEqual(e as? WhoopCommand.BuildError, .denied(n))
            }
        }
    }

    func testNyttolastenPrövas() {
        XCTAssertThrowsError(try WhoopCommand.checked(command: 145, sequence: 1, payload: [0x00]))
        XCTAssertThrowsError(try WhoopCommand.checked(command: 22, sequence: 1, payload: [0x00]))
        XCTAssertThrowsError(try WhoopCommand.checked(command: 23, sequence: 1, payload: [0x02] + [UInt8](repeating: 0, count: 8)))
        XCTAssertThrowsError(try WhoopCommand.checked(command: 23, sequence: 1, payload: [0x01, 0x02]))
        XCTAssertNoThrow(try WhoopCommand.checked(command: 22, sequence: 1, payload: []))
    }

    func testRamarnaKlararBådaSummornaOchFylls() {
        let end = HistoryEnd(inner: Ramar.end(records: 3, trim: 0x0001_2345))!
        for c in [WhoopCommand.sendHistoricalData(sequence: 2),
                  WhoopCommand.historicalDataResult(sequence: 3, end: end),
                  WhoopCommand.clientHello(sequence: 4)] {
            let (frames, stats) = FrameAssembly.assemble([RawFrame(time: Date(), characteristic: "fd4b0002", bytes: c.frame)])
            XCTAssertEqual(frames.count, 1)
            XCTAssertEqual(stats["fd4b0002"]?.crc32Failures, 0)
            XCTAssertTrue(frames[0].crc32OK)
            XCTAssertEqual(frames[0].inner.count % 4, 0)
            XCTAssertEqual(Array(frames[0].inner.prefix(3)), [35, c.sequence, c.number.rawValue])
        }
        // 22 utan nyttolast fylls till [35, sekvens, 22, 00] (= NOOP:s [0x00]).
        XCTAssertEqual(Array(WhoopCommand.sendHistoricalData(sequence: 2).frame[8..<12]), [35, 2, 22, 0])
        // Kvittensen: en etta och END:s åtta byte, ingen utfyllnad.
        let k = WhoopCommand.historicalDataResult(sequence: 3, end: end)
        XCTAssertEqual(k.payload, [0x01, 0x45, 0x23, 0x01, 0x00, 0x0C, 0x00, 0x00, 0x00])
        XCTAssertEqual(k.frame.count, 8 + 12 + 4)
    }

    func testEndLäsesPåRättaPlatser() {
        let e = HistoryEnd(inner: Ramar.end(records: 52, trim: 0x0001_6E90))!
        XCTAssertEqual(e.records, 52)
        XCTAssertEqual(e.trimCursor, 0x0001_6E90)
        XCTAssertEqual(e.endData, [0x90, 0x6E, 0x01, 0x00, 0x0C, 0x00, 0x00, 0x00])
        XCTAssertFalse(e.isEmpty)
        XCTAssertTrue(HistoryEnd(inner: Ramar.emptyEnd())!.isEmpty)
        XCTAssertNil(HistoryEnd(inner: Array(Ramar.end(records: 1, trim: 1).prefix(20))))
        XCTAssertEqual(HistoryMeta(inner: Ramar.start()), .start)
        XCTAssertEqual(HistoryMeta(inner: Ramar.complete()), .complete)
        XCTAssertEqual(CommandResponse(inner: Ramar.response(23, seq: 7, result: 1)),
                       CommandResponse(inner: [36, 0, 23, 7, 1]))
    }
}

/// Påhittade inre delar i bandets form.
enum Ramar {
    static let t0: UInt32 = 1_760_000_000
    static func u32(_ v: UInt32) -> [UInt8] { [0, 8, 16, 24].map { UInt8((v >> UInt32($0)) & 0xFF) } }

    static func pad(_ b: [UInt8], _ n: Int) -> [UInt8] { b + [UInt8](repeating: 0, count: max(0, n - b.count)) }

    static func response(_ cmd: UInt8, seq: UInt8, result: UInt8) -> [UInt8] { [36, 0x40, cmd, seq, result, 0, 0, 0] }
    static func start() -> [UInt8] { pad([49, 0x10, 1] + u32(t0), 40) }
    static func end(records: UInt32, trim: UInt32) -> [UInt8] {
        pad([49, 0x11, 2] + u32(t0) + [0, 0] + u32(records) + u32(trim) + u32(12), 24)
    }
    static func emptyEnd() -> [UInt8] { pad([49, 0x12, 2] + u32(t0) + [0, 0] + u32(0) + [UInt8](repeating: 0xFF, count: 8), 24) }
    static func complete() -> [UInt8] { pad([49, 0x13, 3] + u32(t0), 12) }
    static func k18(_ sekund: UInt32) -> [UInt8] { pad([47, 18, 0] + u32(0x0F00 + sekund) + u32(t0 - 3600 + sekund), 112) }
    static func logg() -> [UInt8] { pad([50, 0x20, 0, 0x41, 0x42], 20) }
    static func händelse() -> [UInt8] { pad([48, 0x21, 110, 0] + u32(t0), 20) }

    /// En hel ram med båda summorna, som bandet skickar den.
    static func ram(_ inner: [UInt8]) -> [UInt8] {
        let length = inner.count + 4
        var b: [UInt8] = [0xAA, 0x01, UInt8(length & 0xFF), UInt8(length >> 8), 0x00, 0x01]
        let h = FrameAssembly.crc16Modbus(b)
        b += [UInt8(h & 0xFF), UInt8(h >> 8)] + inner + u32(FrameAssembly.crc32(inner))
        return b
    }
}

/// Kör sessionen som appen gör: notiser genom ihopfogningen, åtgärderna
/// utförda, och en logg över vad som hände i vilken ordning.
private struct Körning {
    var session: HistorySession
    var stream = FrameAssembly.Stream()
    var now: Date
    var sparaOK = true
    var logg: [String] = []
    var skrivna: [WhoopCommand] = []
    var utfall: HistorySession.Outcome?

    init(config: HistorySession.Config = HistorySession.Config()) {
        let t = Date(timeIntervalSince1970: 1_760_000_000)
        now = t
        session = HistorySession(now: t, config: config)
    }

    mutating func gör(_ actions: [HistorySession.Action]) {
        for a in actions {
            switch a {
            case .write(let c):
                skrivna.append(c)
                logg.append("skriv \(c.number.rawValue)")
            case .saveThenAck:
                logg.append("spara")
                let svar = session.saved(ok: sparaOK, now: now)
                gör(svar)
            case .finish(let o):
                utfall = o
                logg.append("slut")
            }
        }
    }

    mutating func starta() { gör(session.start(now: now)) }

    /// En notis i taget; långa ramar delas som bandet gör (högst 244 byte).
    mutating func ta(_ k: String, _ inner: [UInt8], trasig: Bool = false) {
        now += 0.01
        var b = Ramar.ram(inner)
        if trasig { b[b.count - 1] ^= 0xFF }
        var i = 0
        while i < b.count {
            let del = Array(b[i..<min(b.count, i + 244)])
            i += 244
            if let f = stream.add(RawFrame(time: now, characteristic: k, bytes: del)) {
                gör(session.receive(f, now: now))
            }
        }
    }

    mutating func svar(_ cmd: UInt8, result: UInt8 = 1) {
        let seq = skrivna.last(where: { $0.number.rawValue == cmd })?.sequence ?? 0
        self.ta("fd4b0003", Ramar.response(cmd, seq: seq, result: result))
    }

    /// Hälsning och begäran, med 145:s två svar som på bandet (2, sedan 1).
    mutating func handskakning() {
        starta()
        svar(145, result: 2)
        svar(145)
        svar(22)
    }

    mutating func bit(k18 antal: Int, från: UInt32 = 0, extra: Int = 0, angivet: Int? = nil, trim: UInt32) {
        self.ta("fd4b0005", Ramar.start())
        for _ in 0..<extra { self.ta("fd4b0005", Ramar.logg()) }
        for s in 0..<antal { self.ta("fd4b0005", Ramar.k18(från + UInt32(s))) }
        self.ta("fd4b0005", Ramar.end(records: UInt32(angivet ?? (antal + extra)), trim: trim))
    }

    mutating func tick(_ sekunder: TimeInterval) {
        now += sekunder
        gör(session.tick(now: now))
    }

    var kvittenser: [WhoopCommand] { skrivna.filter { $0.number == .historicalDataResult } }
}

final class HistorySessionTests: XCTestCase {
    func testHelaFlödetSomPåBandet() {
        var k = Körning()
        k.starta()
        XCTAssertEqual(k.skrivna.map(\.frame), [WhoopCommand.clientHello(sequence: 1).frame])
        k.svar(145, result: 2)
        XCTAssertEqual(k.skrivna.count, 1, "145 svarar först 2; det är inget fel och ingen signal att gå vidare")
        k.svar(145)
        XCTAssertEqual(k.skrivna.last, WhoopCommand.sendHistoricalData(sequence: 2))
        k.svar(22)
        XCTAssertEqual(k.session.state, .receiving)

        // Första biten: en händelse, loggtext och K18, som i användaren synk.
        k.ta("fd4b0005", Ramar.start())
        k.ta("fd4b0005", Ramar.händelse())
        for _ in 0..<21 { k.ta("fd4b0005", Ramar.logg()) }
        for s in 0..<30 { k.ta("fd4b0005", Ramar.k18(UInt32(s))) }
        // En händelse på …0004 räknas inte till biten (mätt).
        k.ta("fd4b0004", Ramar.händelse())
        k.ta("fd4b0005", Ramar.end(records: 52, trim: 0x0001_6E90))
        let e1 = HistoryEnd(inner: Ramar.end(records: 52, trim: 0x0001_6E90))!
        XCTAssertEqual(k.kvittenser, [WhoopCommand.historicalDataResult(sequence: 3, end: e1)])
        XCTAssertEqual(k.kvittenser[0].payload, [0x01] + e1.endData)
        k.svar(23)
        XCTAssertEqual(k.session.progress.chunks, 1)

        k.bit(k18: 60, från: 30, trim: 0x0001_6E94)
        k.svar(23)
        k.ta("fd4b0005", Ramar.complete())

        XCTAssertEqual(k.utfall, .complete)
        XCTAssertEqual(k.logg, ["skriv 145", "skriv 22", "spara", "skriv 23", "spara", "skriv 23", "slut"])
        let p = k.session.progress
        XCTAssertEqual(p.chunks, 2)
        XCTAssertEqual(p.k18Seconds, 90)
        XCTAssertEqual(p.records, 52 + 60)
        XCTAssertEqual(p.first, Date(timeIntervalSince1970: TimeInterval(Ramar.t0 - 3600)))
        XCTAssertEqual(p.last, Date(timeIntervalSince1970: TimeInterval(Ramar.t0 - 3600 + 89)))
        XCTAssertEqual(k.skrivna.map(\.sequence), [1, 2, 3, 4])
    }

    func testKvittensenGårFörstNärBitenÄrSparad() {
        var k = Körning()
        k.handskakning()
        k.bit(k18: 15, trim: 0x10)
        XCTAssertEqual(Array(k.logg.suffix(2)), ["spara", "skriv 23"])
    }

    func testMisslyckatSparandeKvitterarInget() {
        var k = Körning()
        k.sparaOK = false
        k.handskakning()
        k.bit(k18: 15, trim: 0x10)
        XCTAssertEqual(k.utfall, .stopped(.saveFailed))
        XCTAssertTrue(k.kvittenser.isEmpty)
        // Efter stoppet skickas ingenting, vad bandet än gör.
        k.bit(k18: 5, trim: 0x11)
        k.ta("fd4b0005", Ramar.complete())
        XCTAssertTrue(k.kvittenser.isEmpty)
        XCTAssertEqual(k.utfall, .stopped(.saveFailed))
    }

    func testFelAntalKvitterasInte() {
        var k = Körning()
        k.handskakning()
        k.bit(k18: 60, angivet: 61, trim: 0x10)
        XCTAssertEqual(k.utfall, .stopped(.countMismatch(expected: 61, received: 60)))
        XCTAssertTrue(k.kvittenser.isEmpty)
    }

    func testFelSummaStopparFöreKvittensen() {
        var k = Körning()
        k.handskakning()
        k.ta("fd4b0005", Ramar.start())
        k.ta("fd4b0005", Ramar.k18(0))
        k.ta("fd4b0005", Ramar.k18(1), trasig: true)
        XCTAssertEqual(k.utfall, .stopped(.corruptFrame))
        k.ta("fd4b0005", Ramar.end(records: 2, trim: 0x10))
        XCTAssertTrue(k.kvittenser.isEmpty)
    }

    func testTomtSlutKvitterasInte() {
        var k = Körning()
        k.handskakning()
        k.ta("fd4b0005", Ramar.start())
        for _ in 0..<5 { k.ta("fd4b0005", Ramar.emptyEnd()) }
        k.ta("fd4b0005", Ramar.complete())
        XCTAssertEqual(k.utfall, .complete)
        XCTAssertTrue(k.kvittenser.isEmpty)
        XCTAssertEqual(k.session.progress.emptyEnds, 5)
    }

    func testSammaSlutTvåGångerKvitterasEnGång() {
        var k = Körning()
        k.handskakning()
        k.bit(k18: 10, extra: 13, trim: 0x0001_6EC0)
        // Bandet skickar samma END igen innan svaret på kvittensen kommit (mätt).
        k.ta("fd4b0005", Ramar.end(records: 23, trim: 0x0001_6EC0))
        k.svar(23)
        k.ta("fd4b0005", Ramar.end(records: 23, trim: 0x0001_6EC0))
        k.ta("fd4b0005", Ramar.complete())
        XCTAssertEqual(k.kvittenser.count, 1)
        XCTAssertEqual(k.utfall, .complete)
    }

    func testKlartUnderKvittensenVäntarPåSvaret() {
        var k = Körning()
        k.handskakning()
        k.bit(k18: 8, trim: 0x20)
        k.ta("fd4b0005", Ramar.complete())
        XCTAssertNil(k.utfall)
        k.svar(23)
        XCTAssertEqual(k.utfall, .complete)
        XCTAssertEqual(k.session.progress.chunks, 1)
    }

    func testAnnatResultatStoppar() {
        var a = Körning()
        a.starta()
        a.svar(145, result: 0)
        XCTAssertEqual(a.utfall, .stopped(.unexpectedResponse(command: 145, result: 0)))
        XCTAssertEqual(a.skrivna.count, 1)

        var b = Körning()
        b.starta()
        b.svar(145)
        b.svar(22, result: 2)
        XCTAssertEqual(b.utfall, .stopped(.unexpectedResponse(command: 22, result: 2)))

        var c = Körning()
        c.handskakning()
        c.bit(k18: 4, trim: 0x30)
        c.svar(23, result: 0)
        XCTAssertEqual(c.utfall, .stopped(.unexpectedResponse(command: 23, result: 0)))
        XCTAssertEqual(c.session.progress.chunks, 0)
    }

    func testWhoopAppenSamtidigtStoppar() {
        // Whoop-appens GET_DATA_RANGE (34) med dess egen sekvens.
        var a = Körning()
        a.handskakning()
        a.ta("fd4b0003", Ramar.response(34, seq: 0x7B, result: 2))
        XCTAssertEqual(a.utfall, .stopped(.otherApp(command: 34)))

        // Whoop-appens kvittens: rätt kommando, fel sekvens.
        var b = Körning()
        b.handskakning()
        b.bit(k18: 4, trim: 0x30)
        b.ta("fd4b0003", Ramar.response(23, seq: 0xA6, result: 1))
        XCTAssertEqual(b.utfall, .stopped(.otherApp(command: 23)))

        // En synk som börjar innan Idunn bett om den.
        var c = Körning()
        c.starta()
        c.ta("fd4b0005", Ramar.start())
        XCTAssertEqual(c.utfall, .stopped(.otherApp(command: 22)))
        XCTAssertFalse(c.skrivna.contains { $0.number == .sendHistoricalData })
    }

    func testSentSvarPåEgetKommandoÄrOfarligt() {
        var k = Körning()
        k.handskakning()
        k.ta("fd4b0003", Ramar.response(145, seq: 1, result: 1))
        XCTAssertNil(k.utfall)
    }

    func testVakthundarna() {
        var a = Körning()
        a.tick(29)
        XCTAssertNil(a.utfall)
        a.tick(2)
        XCTAssertEqual(a.utfall, .stopped(.notConnected))

        var b = Körning()
        b.starta()
        b.tick(16)
        XCTAssertEqual(b.utfall, .stopped(.noResponse(command: 145)))

        var c = Körning()
        c.handskakning()
        c.tick(59)
        XCTAssertNil(c.utfall)
        c.ta("fd4b0005", Ramar.start())
        c.tick(59)
        XCTAssertNil(c.utfall, "varje ram på historiken flyttar vakthunden")
        c.tick(2)
        XCTAssertEqual(c.utfall, .stopped(.idle))
        XCTAssertTrue(c.kvittenser.isEmpty)
    }

    func testTappatBandOchSkrivfel() {
        var a = Körning()
        a.handskakning()
        let tappat = a.session.disconnected()
        a.gör(tappat)
        XCTAssertEqual(a.utfall, .stopped(.disconnected))
        var b = Körning()
        b.starta()
        let fel = b.session.writeFailed()
        b.gör(fel)
        XCTAssertEqual(b.utfall, .stopped(.writeFailed))
        let igen = b.session.writeFailed()
        XCTAssertEqual(igen, [])
    }

    func testStrömmenGerSammaRamarSomHelaFilen() {
        var notiser: [RawFrame] = []
        let t = Date(timeIntervalSince1970: 1_760_000_000)
        for inner in [Ramar.start(), Ramar.k18(1), Ramar.logg(), Ramar.end(records: 2, trim: 5)] {
            let b = Ramar.ram(inner)
            notiser.append(RawFrame(time: t, characteristic: "fd4b0005", bytes: Array(b.prefix(60))))
            if b.count > 60 { notiser.append(RawFrame(time: t, characteristic: "fd4b0005", bytes: Array(b.dropFirst(60)))) }
        }
        notiser.append(RawFrame(time: t, characteristic: "fd4b0007", bytes: Array("f12.0.4".utf8)))
        var s = FrameAssembly.Stream()
        let enStröm = notiser.compactMap { s.add($0) }
        s.close()
        let hela = FrameAssembly.assemble(notiser)
        XCTAssertEqual(enStröm, hela.frames)
        XCTAssertEqual(s.stats, hela.stats)
        XCTAssertEqual(enStröm.count, 4)
        XCTAssertTrue(enStröm.allSatisfy(\.crc32OK))
    }
}
