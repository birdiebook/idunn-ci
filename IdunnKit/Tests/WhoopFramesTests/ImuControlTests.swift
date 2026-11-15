import Foundation
import XCTest
import HeartRate
@testable import WhoopFrames

// METOD M43 · BESLUT B53. IMU-provets tillståndsmaskin med påhittade ramar i
// bandets form (NOOP docs/PROTOCOL_SENSORS.md §R21, omräknat till inre offset =
// ramens offset − 8). Inga byte kommer från ett riktigt band.

final class ImuControlTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    /// En påhittad R21-ram (typ 43, layout 21): 1 232 byte inre del = 1 244
    /// byte hel ram, antal 100 i i16 och i622, sex serier om 100 i16.
    static func r21(sekund: UInt32) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 1232)
        b[0] = 43
        b[1] = 21
        b[2] = 0x80
        for (i, v) in Ramar.u32(0x0100 + sekund).enumerated() { b[3 + i] = v }
        for (i, v) in Ramar.u32(Ramar.t0 + sekund).enumerated() { b[7 + i] = v }
        b[16] = 100
        b[622] = 100
        for i in 0..<100 {
            // z ≈ 1 g (4096) vid vila, lite brus på x.
            b[20 + 2 * i] = UInt8(i & 0xFF)
            b[420 + 2 * i] = 0x00
            b[420 + 2 * i + 1] = 0x10
        }
        return b
    }

    static func frame(_ inner: [UInt8], ok: Bool = true, k: String = "fd4b0005", t: Date) -> FrameAssembly.Frame {
        FrameAssembly.Frame(characteristic: k, notifications: [0], time: t, inner: inner, crc32OK: ok,
                            headerBytes: [0, 1])
    }

    private func skrivna(_ a: [ImuControl.Action]) -> [[UInt8]] {
        a.compactMap { if case .write(let c) = $0 { return [c.number.rawValue] + c.payload } else { return nil } }
    }

    func testStartenSkickar81Sedan106MedMellanrum() {
        var c = ImuControl(now: t0)
        XCTAssertFalse(c.isArmed)
        XCTAssertEqual(c.start(now: t0), [.mark("imu-start")])
        XCTAssertTrue(c.isArmed)
        XCTAssertTrue(c.wantsWrite)
        // Inget skrivs utan skrivkarakteristik.
        XCTAssertEqual(c.tick(now: t0, canWrite: false), [])
        XCTAssertEqual(skrivna(c.tick(now: t0, canWrite: true)), [[81, 1]])
        XCTAssertEqual(c.phase, .starting)
        XCTAssertEqual(skrivna(c.tick(now: t0 + 0.1, canWrite: true)), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 0.25, canWrite: true)), [[106, 1, 1]])
        XCTAssertEqual(c.phase, .on)
        XCTAssertFalse(c.wantsWrite)
        // En andra start medan provet går gör ingenting.
        XCTAssertEqual(c.start(now: t0 + 1), [])
    }

    func testStoppetSkickar82Sedan106AvOchMärker() {
        var c = ImuControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 0.3, canWrite: true)
        XCTAssertEqual(c.stop(now: t0 + 60, reason: .user), [.mark("imu-stopp knapp")])
        XCTAssertEqual(c.phase, .stopping(.user))
        XCTAssertEqual(c.stop(now: t0 + 60, reason: .user), [], "ett stopp som pågår görs inte om")
        XCTAssertEqual(skrivna(c.tick(now: t0 + 60, canWrite: true)), [[82, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 60.25, canWrite: true)), [[106, 1, 0]])
        XCTAssertEqual(c.phase, .off)
        XCTAssertFalse(c.isArmed)
        XCTAssertEqual(c.progress.stopReason, .user)
        XCTAssertEqual(c.stop(now: t0 + 61, reason: .user), [], "inget att stoppa")
    }

    func testTidsgränsenStopparProvet() {
        var cfg = ImuControl.Config()
        XCTAssertEqual(cfg.hardTimeout, 30 * 60)
        cfg.hardTimeout = 120
        var c = ImuControl(now: t0, config: cfg)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 0.25, canWrite: true)
        XCTAssertEqual(c.remaining(now: t0 + 20), 100)
        XCTAssertEqual(c.tick(now: t0 + 119, canWrite: true), [])
        let a = c.tick(now: t0 + 120, canWrite: true)
        XCTAssertEqual(a.first, .mark("imu-stopp tid"))
        XCTAssertEqual(skrivna(a), [[82, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 120.25, canWrite: true)), [[106, 1, 0]])
        XCTAssertEqual(c.phase, .off)
    }

    func testRamarnaRäknasBaraMedanProvetGår() {
        var c = ImuControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 0.25, canWrite: true)
        for s in 0..<10 {
            XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: UInt32(s)), t: t0 + Double(s)), now: t0 + Double(s)), [])
        }
        _ = c.receive(Self.frame([51, 0, 0] + [UInt8](repeating: 0, count: 40), t: t0 + 11), now: t0 + 11)
        _ = c.receive(Self.frame([43, 17, 0] + [UInt8](repeating: 0, count: 40), t: t0 + 11), now: t0 + 11)
        _ = c.receive(Self.frame(Self.r21(sekund: 12), ok: false, t: t0 + 12), now: t0 + 12)
        _ = c.receive(Self.frame(Ramar.k18(3), t: t0 + 12), now: t0 + 12)
        XCTAssertEqual(c.progress.r21Frames, 10)
        XCTAssertEqual(c.progress.stream51Frames, 1)
        XCTAssertEqual(c.progress.other43Frames, 1)
        XCTAssertEqual(c.progress.corruptFrames, 1)
        XCTAssertEqual(c.progress.imuFrames, 11)
        XCTAssertEqual(c.progress.imuBytes, 10 * 1232 + 43)
    }

    func testSvarenSparasOchEttNejStopparStarten() {
        var c = ImuControl(now: t0)
        _ = c.start(now: t0)
        guard case .write(let k81) = c.tick(now: t0, canWrite: true).last else { return XCTFail("81 skrevs inte") }
        XCTAssertEqual(k81.sequence, 101)
        _ = c.receive(Self.frame(Ramar.response(81, seq: 101, result: 1), k: "fd4b0003", t: t0 + 0.1), now: t0 + 0.1)
        guard case .write(let k106) = c.tick(now: t0 + 0.25, canWrite: true).last else { return XCTFail("106 skrevs inte") }
        // NOOP: kommando 63 svarar 3 ("stöds inte") på Whoop 5. Ett sådant svar på 106 stoppar.
        let a = c.receive(Self.frame(Ramar.response(106, seq: k106.sequence, result: 3), k: "fd4b0003", t: t0 + 0.4),
                          now: t0 + 0.4)
        XCTAssertEqual(a, [.mark("imu-stopp nej")])
        XCTAssertEqual(c.progress.responses, [ImuControl.Response(command: 81, on: nil, result: 1),
                                              ImuControl.Response(command: 106, on: true, result: 3)])
        // Ett svar på ett kommando provet inte skickat räknas inte.
        _ = c.receive(Self.frame(Ramar.response(22, seq: 5, result: 1), k: "fd4b0003", t: t0 + 0.5), now: t0 + 0.5)
        XCTAssertEqual(c.progress.responses.count, 2)
        // Utan svar inom tidsgränsen: ett svar utan resultat.
        XCTAssertEqual(skrivna(c.tick(now: t0 + 0.5, canWrite: true)), [[82, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 20, canWrite: true)), [[106, 1, 0]])
        XCTAssertEqual(c.progress.responses.last, ImuControl.Response(command: 82, on: nil, result: nil))
        _ = c.tick(now: t0 + 31, canWrite: true)
        XCTAssertEqual(c.progress.responses.last, ImuControl.Response(command: 106, on: false, result: nil))
    }

    func testSkyddetStopparOväntadRörelse() {
        var c = ImuControl(now: t0)
        // Historik, loggtext och annan typ 43 rör inte skyddet.
        XCTAssertEqual(c.receive(Self.frame(Ramar.k18(1), t: t0), now: t0), [])
        XCTAssertEqual(c.receive(Self.frame([43, 17, 0] + [UInt8](repeating: 0, count: 20), t: t0), now: t0), [])
        XCTAssertEqual(c.receive(Self.frame([52, 0, 0] + [UInt8](repeating: 0, count: 20), t: t0), now: t0), [])
        // R21 i realtid utan prov: stoppet.
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 1), t: t0 + 1), now: t0 + 1), [.mark("imu-stopp skydd")])
        XCTAssertEqual(c.failsafeStops, 1)
        XCTAssertEqual(skrivna(c.tick(now: t0 + 1, canWrite: true)), [[82, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 1.25, canWrite: true)), [[106, 1, 0]])
        XCTAssertEqual(c.phase, .off)
        // Inte igen inom 30 s ...
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 20), t: t0 + 20), now: t0 + 20), [])
        // ... men efter, och även för typ 51.
        XCTAssertEqual(c.receive(Self.frame([51, 0, 0] + [UInt8](repeating: 0, count: 20), t: t0 + 32), now: t0 + 32),
                       [.mark("imu-stopp skydd")])
        XCTAssertEqual(c.failsafeStops, 2)
        // En ram med fel summa räknas inte.
        var d = ImuControl(now: t0)
        XCTAssertEqual(d.receive(Self.frame(Self.r21(sekund: 1), ok: false, t: t0), now: t0), [])
    }

    func testSkyddetVäntarEfterEttEgetStopp() {
        var c = ImuControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 0.25, canWrite: true)
        _ = c.stop(now: t0 + 10, reason: .user)
        _ = c.tick(now: t0 + 10, canWrite: true)
        _ = c.tick(now: t0 + 10.25, canWrite: true)
        XCTAssertEqual(c.phase, .off)
        // Bandet skickar det som var på väg: inom fem sekunder är det väntat.
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 11), t: t0 + 12), now: t0 + 12), [])
        XCTAssertEqual(c.failsafeStops, 0)
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 16), t: t0 + 16), now: t0 + 16), [.mark("imu-stopp skydd")])
    }

    func testOmstartEfterEttProvSkickarStoppet() {
        var c = ImuControl(now: t0, stopAtStart: true)
        XCTAssertTrue(c.isArmed)
        XCTAssertEqual(c.phase, .stopping(.restart))
        XCTAssertEqual(c.tick(now: t0 + 5, canWrite: false), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 6, canWrite: true)), [[82, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 6.25, canWrite: true)), [[106, 1, 0]])
        XCTAssertFalse(c.isArmed)
    }

    func testSkrivfelIStartenBlirStoppOchStoppetGörsOm() {
        var cfg = ImuControl.Config()
        cfg.maxStopAttempts = 3
        var c = ImuControl(now: t0, config: cfg)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(c.writeFailed(now: t0 + 0.1), [.mark("imu-stopp skrivfel")])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 0.25, canWrite: true)), [[82, 1]])
        // Stoppets skrivning fallerar: hela stoppet igen efter en paus.
        XCTAssertEqual(c.writeFailed(now: t0 + 0.3), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 1, canWrite: true)), [])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 2.3, canWrite: true)), [[82, 1]])
        XCTAssertEqual(skrivna(c.tick(now: t0 + 2.55, canWrite: true)), [[106, 1, 0]])
        XCTAssertEqual(c.phase, .off)
        // Ett sent fel på stoppets sista skrivning: en gång till, sedan ger maskinen upp.
        _ = c.writeFailed(now: t0 + 3)
        XCTAssertEqual(c.phase, .stopping(.writeFailed))
        _ = c.tick(now: t0 + 5, canWrite: true)
        _ = c.writeFailed(now: t0 + 5.1)
        XCTAssertEqual(c.phase, .off)
        XCTAssertFalse(c.wantsWrite)
    }

    func testAvslutSkickarBådaGenast() {
        var c = ImuControl(now: t0)
        XCTAssertEqual(c.flushStop(now: t0), [], "inget prov, inget att skicka")
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 0.25, canWrite: true)
        let a = c.flushStop(now: t0 + 30)
        XCTAssertEqual(a.first, .mark("imu-stopp avslut"))
        XCTAssertEqual(skrivna(a), [[82, 1], [106, 1, 0]])
        XCTAssertFalse(c.isArmed)
    }

    /// METOD M43. Länken uppe men ingen rörelse: `imu tyst` efter tre
    /// sekunder, en gång, och `imu igen` vid nästa ram.
    func testTystnadenMedLänkenUppeOchNärDenTarSlut() {
        var c = ImuControl(now: t0)
        XCTAssertEqual(c.config.silenceLimit, 3)
        XCTAssertEqual(c.watch(now: t0, linkUp: true), [], "inget prov")
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        XCTAssertEqual(c.watch(now: t0 + 0.1, linkUp: true), [])
        XCTAssertEqual(c.watch(now: t0 + 5, linkUp: true), [], "provet startar fortfarande")
        _ = c.tick(now: t0 + 5, canWrite: true)
        XCTAssertEqual(c.phase, .on)
        XCTAssertEqual(c.watch(now: t0 + 5, linkUp: true), [])
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 5), t: t0 + 6), now: t0 + 6), [])
        XCTAssertEqual(c.watch(now: t0 + 8.9, linkUp: true), [])
        XCTAssertEqual(c.watch(now: t0 + 9.1, linkUp: true), [.link(.imuSilent)])
        XCTAssertEqual(c.watch(now: t0 + 20, linkUp: true), [], "en gång per tystnad")
        // Annan typ 43 (EKG, optik) är ingen rörelse.
        XCTAssertEqual(c.receive(Self.frame([43, 17, 0] + [UInt8](repeating: 0, count: 20), t: t0 + 21), now: t0 + 21), [])
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 21), t: t0 + 22), now: t0 + 22), [.link(.imuResumed)])
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 22), t: t0 + 23), now: t0 + 23), [])
        XCTAssertEqual(c.watch(now: t0 + 25, linkUp: true), [])
        XCTAssertEqual(c.watch(now: t0 + 26.1, linkUp: true), [.link(.imuSilent)])
        XCTAssertEqual(c.progress.silences, 2)
        // Stoppet avslutar tystnaden utan `imu igen`.
        _ = c.stop(now: t0 + 30, reason: .user)
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 30), t: t0 + 31), now: t0 + 31), [])
        XCTAssertEqual(c.watch(now: t0 + 40, linkUp: true), [])
    }

    /// Går länken ner räknas tystnaden om från återanslutningen; tiden utan
    /// länk är ingen tystnad (frånkopplingen har sin egen rad).
    func testTystnadenRäknasFrånÅteranslutningen() {
        var c = ImuControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 0.25, canWrite: true)
        XCTAssertEqual(c.watch(now: t0 + 0.25, linkUp: true), [])
        _ = c.receive(Self.frame(Self.r21(sekund: 1), t: t0 + 1), now: t0 + 1)
        XCTAssertEqual(c.watch(now: t0 + 4.5, linkUp: true), [.link(.imuSilent)])
        XCTAssertEqual(c.watch(now: t0 + 5, linkUp: false), [])
        XCTAssertEqual(c.watch(now: t0 + 60, linkUp: false), [])
        XCTAssertEqual(c.watch(now: t0 + 80, linkUp: true), [])
        XCTAssertEqual(c.watch(now: t0 + 82.9, linkUp: true), [])
        // Ramen inom gränsen efter återanslutningen: ingen rad alls.
        XCTAssertEqual(c.receive(Self.frame(Self.r21(sekund: 80), t: t0 + 82.95), now: t0 + 82.95), [])
        XCTAssertEqual(c.watch(now: t0 + 85.9, linkUp: true), [])
        XCTAssertEqual(c.watch(now: t0 + 86, linkUp: true), [.link(.imuSilent)])
        XCTAssertEqual(c.progress.silences, 2)
    }

    func testSorten() {
        XCTAssertEqual(ImuControl.Kind(inner: Self.r21(sekund: 0)), .r21)
        XCTAssertEqual(ImuControl.Kind(inner: [43, 16]), .other43)
        XCTAssertEqual(ImuControl.Kind(inner: [43]), .other43)
        XCTAssertEqual(ImuControl.Kind(inner: [51]), .stream51)
        XCTAssertEqual(ImuControl.Kind(inner: [52]), .stream52)
        XCTAssertNil(ImuControl.Kind(inner: [47, 21]), "R21 i historiken är inte realtid")
        XCTAssertNil(ImuControl.Kind(inner: []))
    }

    /// En R21-ram är 1 244 byte och delas över många notiser. Ihopfogningen
    /// ska ge hela ramen med rätt summa, ram efter ram, även med andra
    /// karakteristikers notiser emellan, och med bandets inre offsets
    /// (ramens offset − 8): tid i i7, antal i i16 och i622.
    func testR21FogasIhopÖverMångaNotiser() {
        var stream = FrameAssembly.Stream()
        var c = ImuControl(now: t0)
        _ = c.start(now: t0)
        _ = c.tick(now: t0, canWrite: true)
        _ = c.tick(now: t0 + 0.25, canWrite: true)
        var hela = 0
        var notiser = 0
        for s in 0..<120 {
            let ram = Ramar.ram(Self.r21(sekund: UInt32(s)))
            XCTAssertEqual(ram.count, 1244)
            let tid = t0 + 1 + Double(s)
            // 244 byte per notis (en vanlig MTU på iOS), sista biten kortare.
            var i = 0
            while i < ram.count {
                let bit = Array(ram[i..<min(i + 244, ram.count)])
                notiser += 1
                if let f = stream.add(RawFrame(time: tid, characteristic: "fd4b0005", bytes: bit)) {
                    XCTAssertTrue(f.crc32OK)
                    XCTAssertEqual(f.inner.count, 1232)
                    XCTAssertEqual(FrameAssembly.u32(f.inner, at: 7), Ramar.t0 + UInt32(s))
                    XCTAssertEqual(Int(f.inner[16]) | Int(f.inner[17]) << 8, 100)
                    XCTAssertEqual(Int(f.inner[622]) | Int(f.inner[623]) << 8, 100)
                    // Bandets ram-offset 24 (NOOP) = inre 16.
                    XCTAssertEqual(ram[24], f.inner[16])
                    XCTAssertEqual(ram[630], f.inner[622])
                    XCTAssertEqual(Array(ram[15..<19]), Array(f.inner[7..<11]))
                    hela += 1
                    _ = c.receive(f, now: tid)
                }
                i += 244
                // En kommandosvarsnotis på en annan karakteristik mitt i.
                if i == 488 {
                    _ = stream.add(RawFrame(time: tid, characteristic: "fd4b0003",
                                            bytes: Ramar.ram(Ramar.response(50, seq: 1, result: 1))))
                }
            }
        }
        XCTAssertEqual(hela, 120)
        XCTAssertEqual(notiser, 120 * 6)
        XCTAssertEqual(stream.stats["fd4b0005"]?.crc32Failures, 0)
        XCTAssertEqual(stream.stats["fd4b0005"]?.incomplete, 0)
        XCTAssertEqual(c.progress.r21Frames, 120)
    }
}
