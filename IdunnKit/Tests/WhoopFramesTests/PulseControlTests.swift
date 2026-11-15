import Foundation
import XCTest
import HeartRate
@testable import WhoopFrames

// METOD M48 · BESLUT B61. Passets puls ur bandets protokoll, med påhittade
// paket i bandets form (PROTOKOLL_W5 §2.2 och §3.3). Inga byte kommer från ett
// riktigt band.

final class PulseControlTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    /// Ett påhittat REALTIME_DATA-paket (typ 40): posthuvud, puls i i17, RR-antal i i18, RR från i19.
    static func typ40(bpm: UInt8, rr: [UInt16] = [], längd: Int = 48) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: längd)
        b[0] = 40
        b[1] = 24
        for (i, v) in Ramar.u32(Ramar.t0).enumerated() { b[7 + i] = v }
        b[17] = bpm
        b[18] = UInt8(rr.count)
        for (k, v) in rr.enumerated() {
            b[19 + 2 * k] = UInt8(v & 0xFF)
            b[20 + 2 * k] = UInt8(v >> 8)
        }
        return b
    }

    static func svar(_ kommando: UInt8, sekvens: UInt8, resultat: UInt8) -> [UInt8] {
        [36, 7, kommando, sekvens, resultat, 0, 0, 0]
    }

    private func frame(_ inner: [UInt8], ok: Bool = true, t: Date) -> FrameAssembly.Frame {
        ImuControlTests.frame(inner, ok: ok, t: t)
    }

    private func skrivna(_ a: [PulseControl.Action]) -> [[UInt8]] {
        a.compactMap { if case .write(let c) = $0 { return [c.number.rawValue] + c.payload } else { return nil } }
    }

    private func märken(_ a: [PulseControl.Action]) -> [String] {
        a.compactMap { if case .mark(let m) = $0 { return m } else { return nil } }
    }

    private func pulser(_ a: [PulseControl.Action]) -> [HeartRateMeasurement] {
        a.compactMap { if case .pulse(let m) = $0 { return m } else { return nil } }
    }

    // MARK: Kommandot

    func testKommando3sRamarByteFörByte() throws {
        // Räknade med samma rambyggare som 81 och 106 (CRC16-Modbus, CRC32 zlib).
        XCTAssertEqual(WhoopCommand.realtimeHeartRate(on: true, sequence: 201).frame,
                       [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0xC9, 0x03, 0x01, 0x56, 0x11, 0x97, 0x51])
        XCTAssertEqual(WhoopCommand.realtimeHeartRate(on: false, sequence: 202).frame,
                       [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0xCA, 0x03, 0x00, 0x99, 0x9F, 0xD6, 0x24])
        XCTAssertEqual(try WhoopCommand.checked(command: 3, sequence: 201, payload: [0x01]),
                       .realtimeHeartRate(on: true, sequence: 201))
        XCTAssertThrowsError(try WhoopCommand.checked(command: 3, sequence: 1, payload: [0x02])) {
            XCTAssertEqual($0 as? WhoopCommand.BuildError, .badPayload(3))
        }
        XCTAssertThrowsError(try WhoopCommand.checked(command: 3, sequence: 1, payload: [0x01, 0x01]))
        XCTAssertFalse(WhoopCommand.denied.contains(3))
    }

    // MARK: Paketet

    func testPulsenLäsesUrI17OchRRUrI18() {
        let m = RealtimePulse.measurement(inner: Self.typ40(bpm: 72, rr: [833, 845]))
        XCTAssertEqual(m?.bpm, 72)
        XCTAssertEqual(m?.rrMilliseconds, [833, 845])
        XCTAssertNil(m?.sensorContact)
    }

    func testOrimligPulsEllerFelTypGerIngenPuls() {
        XCTAssertNil(RealtimePulse.measurement(inner: Self.typ40(bpm: 0)))
        XCTAssertNil(RealtimePulse.measurement(inner: Self.typ40(bpm: 24)))
        XCTAssertNil(RealtimePulse.measurement(inner: Self.typ40(bpm: 231)))
        XCTAssertNotNil(RealtimePulse.measurement(inner: Self.typ40(bpm: 25)))
        XCTAssertNotNil(RealtimePulse.measurement(inner: Self.typ40(bpm: 230)))
        var fel = Self.typ40(bpm: 70)
        fel[0] = 47
        XCTAssertNil(RealtimePulse.measurement(inner: fel))
        XCTAssertNil(RealtimePulse.measurement(inner: Array(Self.typ40(bpm: 70).prefix(17))))
    }

    func testOrimligaRRSläppsMenPulsenBehålls() {
        XCTAssertEqual(RealtimePulse.measurement(inner: Self.typ40(bpm: 70, rr: [900, 100]))?.rrMilliseconds, [])
        var fem = Self.typ40(bpm: 70)
        fem[18] = 5
        XCTAssertEqual(RealtimePulse.measurement(inner: fem)?.rrMilliseconds, [])
        // Antalet pekar förbi paketets slut.
        var kort = Array(Self.typ40(bpm: 70, rr: [900, 900]).prefix(21))
        kort[18] = 2
        XCTAssertEqual(RealtimePulse.measurement(inner: kort)?.bpm, 70)
        XCTAssertEqual(RealtimePulse.measurement(inner: kort)?.rrMilliseconds, [])
    }

    // MARK: Maskinen

    func testStartSkickar3PåOchPulsenGårTillPasset() {
        var c = PulseControl(now: t0)
        XCTAssertEqual(c.start(now: t0), [.mark("puls-start")])
        XCTAssertTrue(c.isArmed)
        XCTAssertTrue(c.wantsWrite)
        XCTAssertEqual(c.tick(now: t0, canWrite: false), [])
        XCTAssertEqual(skrivna(c.tick(now: t0, canWrite: true)), [[3, 1]])
        XCTAssertFalse(c.wantsWrite)
        XCTAssertEqual(c.receive(frame(Self.svar(3, sekvens: 201, resultat: 1), t: t0 + 0.3), now: t0 + 0.3),
                       [.mark("puls-svar 1")])
        let a = c.receive(frame(Self.typ40(bpm: 88), t: t0 + 1), now: t0 + 1)
        XCTAssertEqual(pulser(a).map(\.bpm), [88])
        XCTAssertEqual(c.progress.frames, 1)
        XCTAssertEqual(c.progress.pulses, 1)
        XCTAssertEqual(c.progress.startResults, [1])
        // En andra start medan passet går gör ingenting.
        XCTAssertEqual(c.start(now: t0 + 2), [])
    }

    func testSvaret2VäntarPåNästaSvar() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(c.receive(frame(Self.svar(3, sekvens: 201, resultat: 2), t: t0 + 0.1), now: t0 + 0.1), [])
        XCTAssertEqual(c.receive(frame(Self.svar(3, sekvens: 201, resultat: 1), t: t0 + 0.4), now: t0 + 0.4),
                       [.mark("puls-svar 1")])
    }

    func testTyp40UtanPassBlirIngenPulsOchIngetStopp() {
        // Whoop-appens eget pass lämnas i fred.
        var c = PulseControl(now: t0)
        XCTAssertEqual(c.receive(frame(Self.typ40(bpm: 120), t: t0), now: t0), [])
        XCTAssertEqual(c.tick(now: t0 + 60, canWrite: true), [])
        XCTAssertFalse(c.isArmed)
    }

    func testTrasigRamRäknasMenGerIngenPuls() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(c.receive(frame(Self.typ40(bpm: 70), ok: false, t: t0 + 1), now: t0 + 1),
                       [.mark("puls-ram trasig")])
        // Märket skrivs en gång per pass.
        XCTAssertEqual(c.receive(frame(Self.typ40(bpm: 70), ok: false, t: t0 + 2), now: t0 + 2), [])
        XCTAssertEqual(c.progress.corruptFrames, 2)
        XCTAssertEqual(c.progress.pulses, 0)
    }

    func testIngenPulsSkickarStartetIgenTreGångerSedanMärke() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        XCTAssertEqual(skrivna(c.tick(now: t0, canWrite: true)), [[3, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 9.9, canWrite: true)), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 10, canWrite: true)), [[3, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 20, canWrite: true)), [[3, 1]])
        XCTAssertEqual(c.tick(now: t0 + 30, canWrite: true), [.mark("puls-svar saknas"), .mark("puls-ingen")])
        XCTAssertEqual(c.tick(now: t0 + 40, canWrite: true), [.mark("puls-svar saknas")])
        XCTAssertEqual(c.progress.starts, 3)
        // En puls senare nollställer: tystnar den igen försöker maskinen på nytt.
        XCTAssertEqual(pulser(c.receive(frame(Self.typ40(bpm: 70), t: t0 + 50), now: t0 + 50)).count, 1)
        XCTAssertEqual(skrivna(c.tick(now: t0 + 59, canWrite: true)), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 60, canWrite: true)), [[3, 1]])
    }

    func testPulsenHållerStartetBorta() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        for s in 1...30 {
            _ = c.receive(frame(Self.typ40(bpm: 70), t: t0 + Double(s)), now: t0 + Double(s))
            XCTAssertEqual(skrivna(c.tick(now: t0 + Double(s) + 0.5, canWrite: true)), [])
        }
        XCTAssertEqual(c.progress.starts, 1)
    }

    func testNejFrånBandetStopparFörsökenMenInteSjälvaPasset() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(c.receive(frame(Self.svar(3, sekvens: 201, resultat: 3), t: t0 + 0.3), now: t0 + 0.3),
                       [.mark("puls-svar 3")])
        XCTAssertEqual(c.tick(now: t0 + 10, canWrite: true), [.mark("puls-ingen")])
        XCTAssertEqual(c.phase, .on)
    }

    func testUteblivetSvarRäknasSomNil() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 10.5, canWrite: false)
        XCTAssertEqual(c.progress.startResults, [nil])
    }

    func testStoppetSkickar3AvOchMärker() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(c.stop(now: t0 + 5, reason: .done), [.mark("puls-stopp klar"), .mark("puls-slut r0 p0 t0")])
        XCTAssertEqual(c.stop(now: t0 + 5, reason: .done), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 5, canWrite: true)), [[3, 0]])
        XCTAssertEqual(c.phase, .off)
        XCTAssertFalse(c.isArmed)
        // Efter stoppet blir typ 40 ingen puls.
        XCTAssertEqual(c.receive(frame(Self.typ40(bpm: 70), t: t0 + 6), now: t0 + 6), [])
        // Stopp utan pass gör ingenting.
        XCTAssertEqual(c.stop(now: t0 + 7, reason: .done), [])
    }

    func testMisslyckatStoppGörsOm() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.stop(now: t0 + 1, reason: .done)
        XCTAssertEqual(skrivna(c.tick(now: t0 + 1, canWrite: true)), [[3, 0]])
        XCTAssertEqual(c.writeFailed(now: t0 + 1.1), [.mark("puls-skrivfel av")])
        XCTAssertTrue(c.isArmed)
        XCTAssertEqual(skrivna(c.tick(now: t0 + 2, canWrite: true)), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 3.1, canWrite: true)), [[3, 0]])
        XCTAssertFalse(c.isArmed)
    }

    func testStoppetGerUppEfterFemFörsök() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.stop(now: t0 + 1, reason: .done)
        var t = t0 + 1
        for _ in 0..<5 {
            XCTAssertEqual(skrivna(c.tick(now: t, canWrite: true)), [[3, 0]])
            _ = c.writeFailed(now: t)
            t += 3
        }
        XCTAssertFalse(c.isArmed)
        XCTAssertEqual(c.tick(now: t, canWrite: true), [])
    }

    func testMisslyckatStartGörsOmVidNästaFörsök() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(c.writeFailed(now: t0 + 0.1), [.mark("puls-skrivfel på")])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 10, canWrite: true)), [[3, 1]])
    }

    func testOmstartEfterDödAppSkickarStoppet() {
        var c = PulseControl(now: t0, stopAtStart: true)
        XCTAssertTrue(c.isArmed)
        XCTAssertTrue(c.wantsWrite)
        XCTAssertEqual(c.phase, .stopping(.restart))
        XCTAssertEqual(skrivna(c.tick(now: t0, canWrite: true)), [[3, 0]])
        XCTAssertFalse(c.isArmed)
    }

    func testPassSomTasUppIgenEfterOmstartStartarIStälletFörAttStoppa() {
        var c = PulseControl(now: t0, stopAtStart: true)
        XCTAssertEqual(c.start(now: t0), [.mark("puls-start")])
        XCTAssertEqual(c.phase, .on)
        XCTAssertEqual(skrivna(c.tick(now: t0, canWrite: true)), [[3, 1]])
        XCTAssertTrue(c.isArmed)
    }

    func testAvslutSkickarStoppetDirekt() {
        var c = PulseControl(now: t0)
        XCTAssertEqual(c.flushStop(now: t0), [])
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        let a = c.flushStop(now: t0 + 1)
        XCTAssertEqual(a.first, .mark("puls-stopp avslut"))
        XCTAssertEqual(skrivna(a), [[3, 0]])
        XCTAssertFalse(c.isArmed)
    }

    func testSekvensernaÄrSkildaFrånHämtningenOchImu() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        let a = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(a.first, .mark("puls-skrev på 201"))
        guard a.count == 2, case .write(let w) = a[1] else { return XCTFail("inget skrivet") }
        XCTAssertEqual(w.sequence, 201)
    }

    // MARK: Märkena och de glesa försöken (BESLUT B116, METOD M67)

    func testVarjeStegLämnarEttMärke() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        XCTAssertEqual(märken(c.tick(now: t0, canWrite: true)), ["puls-skrev på 201"])
        // Första paketet: längden. Första paketet utan rimlig puls: ett märke till. Båda bara en gång.
        XCTAssertEqual(märken(c.receive(frame(Self.typ40(bpm: 0), t: t0 + 1), now: t0 + 1)),
                       ["puls-ram 48", "puls-orimlig"])
        XCTAssertEqual(märken(c.receive(frame(Self.typ40(bpm: 0, längd: 60), t: t0 + 2), now: t0 + 2)), [])
        XCTAssertEqual(märken(c.receive(frame(Self.typ40(bpm: 70), t: t0 + 3), now: t0 + 3)), ["puls-första"])
        XCTAssertEqual(märken(c.receive(frame(Self.typ40(bpm: 71), t: t0 + 4), now: t0 + 4)), [])
        _ = c.receive(frame(Self.typ40(bpm: 70), ok: false, t: t0 + 5), now: t0 + 5)
        // Stoppet bär antalen: fyra hela ramar, två med puls, en trasig. Inga värden.
        XCTAssertEqual(märken(c.stop(now: t0 + 6, reason: .done)), ["puls-stopp klar", "puls-slut r4 p2 t1"])
        XCTAssertEqual(märken(c.tick(now: t0 + 6, canWrite: true)), ["puls-skrev av 202"])
        // Ett nytt pass märker på nytt.
        _ = c.start(now: t0 + 100)
        _ = c.tick(now: t0 + 100, canWrite: true)
        XCTAssertEqual(märken(c.receive(frame(Self.typ40(bpm: 70), t: t0 + 101), now: t0 + 101)),
                       ["puls-ram 48", "puls-första"])
    }

    func testIngetMärkeBärEttMätvärde() {
        // Pulsen 173 och RR 1234 får aldrig stå i ett märke: bara antal, längder, koder och sekvenser.
        var c = PulseControl(now: t0)
        var alla: [String] = märken(c.start(now: t0)) + märken(c.tick(now: t0, canWrite: true))
        alla += märken(c.receive(frame(Self.svar(3, sekvens: 201, resultat: 1), t: t0), now: t0))
        for s in 1...20 {
            alla += märken(c.receive(frame(Self.typ40(bpm: 173, rr: [1234]), t: t0 + Double(s)), now: t0 + Double(s)))
        }
        alla += märken(c.stop(now: t0 + 21, reason: .done)) + märken(c.tick(now: t0 + 21, canWrite: true))
        XCTAssertEqual(alla, ["puls-start", "puls-skrev på 201", "puls-svar 1", "puls-ram 48", "puls-första",
                              "puls-stopp klar", "puls-slut r20 p20 t0", "puls-skrev av 202"])
        for m in alla {
            XCTAssertFalse(m.contains("173") || m.contains("1234"), m)
            XCTAssertLessThanOrEqual(m.count, 32, m)   // RecordingLog.marker kortar vid 32 tecken
        }
    }

    func testEfterTreFörsökKommerGlesaFörsökSåLängePassetGår() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        for s in [0.0, 10, 20] { XCTAssertEqual(skrivna(c.tick(now: t0 + s, canWrite: true)), [[3, 1]]) }
        XCTAssertEqual(märken(c.tick(now: t0 + 30, canWrite: true)), ["puls-svar saknas", "puls-ingen"])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 79, canWrite: true)), [])
        // 60 s efter det senaste startet: ett till, och sedan ett per minut. `puls-ingen` skrivs inte om.
        XCTAssertEqual(skrivna(c.tick(now: t0 + 80, canWrite: true)), [[3, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 139, canWrite: true)), [])
        let a = c.tick(now: t0 + 140, canWrite: true)
        XCTAssertEqual(skrivna(a), [[3, 1]])
        XCTAssertFalse(märken(a).contains("puls-ingen"))
        XCTAssertEqual(c.progress.starts, 5)
        // Utan anslutning skrivs inget, och efter stoppet inga fler start.
        XCTAssertEqual(skrivna(c.tick(now: t0 + 300, canWrite: false)), [])
        _ = c.stop(now: t0 + 301, reason: .done)
        XCTAssertEqual(skrivna(c.tick(now: t0 + 301, canWrite: true)), [[3, 0]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 400, canWrite: true)), [])
    }

    func testEfterBandetsNejKommerIngaGlesaFörsök() {
        var c = PulseControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.receive(frame(Self.svar(3, sekvens: 201, resultat: 3), t: t0 + 0.3), now: t0 + 0.3)
        for s in stride(from: 10.0, through: 600, by: 10) {
            XCTAssertEqual(skrivna(c.tick(now: t0 + s, canWrite: true)), [])
        }
        XCTAssertEqual(c.progress.starts, 1)
    }
}
