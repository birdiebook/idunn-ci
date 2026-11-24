import Foundation
import XCTest
@testable import HeartRate
@testable import WhoopFrames

// METOD M27. Dygnsfilens namn och växling, lyssnarens status och exporten av
// ett intervall över midnatt. Påhittade ramar med riktiga kontrollsummor
// (Ramar.ram, HistorySessionTests); inga byte kommer från ett riktigt band.

/// Epoksekunder för lokala tider i testerna (2026-10-13 är en tisdag, +02:00).
private enum Tid {
    static let cest = 7200
    /// 2026-10-13 00:00 UTC.
    static let dag13 = 1_791_849_600
    /// 2026-10-14 00:00 lokal tid i +02:00 = 2026-10-13 22:00 UTC.
    static let midnatt14 = 1_791_928_800

    /// Lokal tid i +02:00 på 2026-10-13 plus `dagar` dygn.
    static func lokal(dag: Int = 13, _ h: Int, _ m: Int = 0) -> Double {
        Double(dag13 + (dag - 13) * 86_400 + h * 3600 + m * 60 - cest)
    }
}

final class DayLogTests: XCTestCase {
    func testStamenÄrDetLokalaDatumet() {
        XCTAssertEqual(DayLog.stem(for: Date(timeIntervalSince1970: 1_760_300_000), utcOffsetSeconds: 0),
                       "dygn-2025-10-12")
        // En sekund före och på lokal midnatt.
        XCTAssertEqual(DayLog.stem(for: Date(timeIntervalSince1970: Double(Tid.midnatt14 - 1)),
                                   utcOffsetSeconds: Tid.cest), "dygn-2026-10-13")
        XCTAssertEqual(DayLog.stem(for: Date(timeIntervalSince1970: Double(Tid.midnatt14)),
                                   utcOffsetSeconds: Tid.cest), "dygn-2026-10-14")
        // Samma ögonblick i en annan zon är ett annat datum.
        XCTAssertEqual(DayLog.stem(for: Date(timeIntervalSince1970: Double(Tid.midnatt14)),
                                   utcOffsetSeconds: -5 * 3600), "dygn-2026-10-13")
    }

    func testDatumFöreEpokenOchSkottdag() {
        XCTAssertEqual(DayLog.stem(for: Date(timeIntervalSince1970: -1), utcOffsetSeconds: 0), "dygn-1969-12-31")
        XCTAssertEqual(DayLog.stem(for: Date(timeIntervalSince1970: 0), utcOffsetSeconds: -3600), "dygn-1969-12-31")
        XCTAssertEqual(DayLog.stem(for: Date(timeIntervalSince1970: 1_709_208_000), utcOffsetSeconds: 0),
                       "dygn-2024-02-29")
        // 2100 är inte skottår.
        XCTAssertEqual(DayLog.shifted(DayLog.Day(year: 2100, month: 2, day: 28), by: 1),
                       DayLog.Day(year: 2100, month: 3, day: 1))
    }

    func testVarjeDagGårFramOchTillbaka() {
        for z in stride(from: -800, through: 30_000, by: 7) {
            let d = DayLog.day(fromDays: z)
            XCTAssertEqual(DayLog.days(d), z, d.text)
        }
        XCTAssertEqual(DayLog.days(DayLog.Day(year: 1970, month: 1, day: 1)), 0)
    }

    func testStamUrTextOchTillbaka() {
        XCTAssertEqual(DayLog.day(ofStem: "dygn-2026-10-13"), DayLog.Day(year: 2026, month: 10, day: 13))
        XCTAssertTrue(DayLog.isDayStem("dygn-2026-10-13"))
        // Natter, intervall och allt annat är inga dygnsfiler.
        XCTAssertFalse(DayLog.isDayStem("2026-10-13T20-13-20Z"))
        XCTAssertFalse(DayLog.isDayStem("dygn-2026-10-12-1800-2026-10-13-1200"))
        XCTAssertFalse(DayLog.isDayStem("dygn-2026-13-01"))
        XCTAssertFalse(DayLog.isDayStem("dygn-26-1-1"))
        XCTAssertFalse(DayLog.isDayStem("dygn-"))
    }

    func testLokalTidPåEttDatum() {
        let d = DayLog.Day(year: 2026, month: 10, day: 13)
        XCTAssertEqual(DayLog.date(of: d, hour: 18, utcOffsetSeconds: Tid.cest).timeIntervalSince1970,
                       Tid.lokal(18))
        XCTAssertEqual(DayLog.date(of: d, utcOffsetSeconds: 0).timeIntervalSince1970, Double(Tid.dag13))
    }

    func testDygnsfilerSomKanInnehållaEttIntervall() {
        let från = Date(timeIntervalSince1970: Tid.lokal(dag: 12, 18))
        let till = Date(timeIntervalSince1970: Tid.lokal(dag: 13, 12))
        XCTAssertEqual(DayLog.stems(touching: från, to: till, utcOffsetSeconds: Tid.cest),
                       ["dygn-2026-10-11", "dygn-2026-10-12", "dygn-2026-10-13", "dygn-2026-10-14"])
        XCTAssertEqual(DayLog.stems(touching: till, to: från, utcOffsetSeconds: Tid.cest), [])
    }

    // MARK: Växlingen

    func testKursornVäxlarVidMidnattOchBytetÄrEnGång() {
        var c = DayLog.Cursor()
        let före = Date(timeIntervalSince1970: Double(Tid.midnatt14 - 5))
        XCTAssertEqual(c.advance(to: före, utcOffsetSeconds: Tid.cest),
                       .file(stem: "dygn-2026-10-13", utcOffsetSeconds: Tid.cest), "första notisen öppnar filen")
        XCTAssertEqual(c.advance(to: Date(timeIntervalSince1970: Double(Tid.midnatt14 - 1)),
                                 utcOffsetSeconds: Tid.cest), .none)
        XCTAssertEqual(c.advance(to: Date(timeIntervalSince1970: Double(Tid.midnatt14)),
                                 utcOffsetSeconds: Tid.cest),
                       .file(stem: "dygn-2026-10-14", utcOffsetSeconds: Tid.cest))
        XCTAssertEqual(c.advance(to: Date(timeIntervalSince1970: Double(Tid.midnatt14 + 60)),
                                 utcOffsetSeconds: Tid.cest), .none)
        XCTAssertEqual(c.stem, "dygn-2026-10-14")
    }

    func testNyZonSammaDatumGerEnZonradInteEnNyFil() {
        var c = DayLog.Cursor()
        let middag = Date(timeIntervalSince1970: Tid.lokal(12))
        _ = c.advance(to: middag, utcOffsetSeconds: Tid.cest)
        // Sommartiden slutar: klockan går tillbaka en timme, samma datum.
        XCTAssertEqual(c.advance(to: middag.addingTimeInterval(60), utcOffsetSeconds: 3600),
                       .zone(utcOffsetSeconds: 3600))
        XCTAssertEqual(c.advance(to: middag.addingTimeInterval(120), utcOffsetSeconds: 3600), .none)
    }

    func testResaOverDatumgränsenÖppnarRättFil() {
        var c = DayLog.Cursor()
        let t = Date(timeIntervalSince1970: Double(Tid.midnatt14 + 600))   // 00:10 den 14:e i +02:00
        _ = c.advance(to: t, utcOffsetSeconds: Tid.cest)
        // Västerut: samma ögonblick är kvällen den 13:e. Den filen öppnas igen.
        XCTAssertEqual(c.advance(to: t.addingTimeInterval(1), utcOffsetSeconds: -5 * 3600),
                       .file(stem: "dygn-2026-10-13", utcOffsetSeconds: -5 * 3600))
        // Österut igen: den 14:e.
        XCTAssertEqual(c.advance(to: t.addingTimeInterval(2), utcOffsetSeconds: Tid.cest),
                       .file(stem: "dygn-2026-10-14", utcOffsetSeconds: Tid.cest))
    }

    // MARK: Zonraden i sidofilen

    func testZonradenBärTidOchHuvudetGörDetInte() {
        var fil = RecordingLog.header(utcOffsetSeconds: 7200)
        fil.append(RecordingLog.zoneChange(utcOffsetSeconds: 3600, at: Date(timeIntervalSince1970: 1_760_300_100)))
        fil.append(RecordingLog.marker("skak", at: Date(timeIntervalSince1970: 1_760_300_200)))
        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.utcOffsetSeconds, 7200, "huvudet är den första zonen")
        XCTAssertEqual(ut.zoneChanges, [RecordingLog.ZoneChange(time: Date(timeIntervalSince1970: 1_760_300_100),
                                                                 utcOffsetSeconds: 3600)])
        XCTAssertEqual(ut.markers.count, 1)
        XCTAssertEqual(ut.recording.samples.count, 0)
        XCTAssertEqual(ut.skippedLines, 0)
    }
}

// MARK: - Lyssnarens status

private enum Notiser {
    static let k = "fd4b0005"

    /// En K18-post med bandets tid `time` (Unix-sekunder i i7), 112 byte.
    static func k18(_ time: Int) -> [UInt8] {
        Ramar.pad([47, 18, 0] + Ramar.u32(0) + Ramar.u32(UInt32(time)), 112)
    }

    static func note(_ heard: Double, _ ram: [UInt8], _ ch: String = k) -> RawFrame {
        RawFrame(time: Date(timeIntervalSince1970: heard), characteristic: ch, bytes: ram)
    }

    /// En hel K18-ram för bandets tid `time`, hörd samma sekund.
    static func record(_ time: Int) -> RawFrame {
        note(Double(time), Ramar.ram(k18(time)))
    }

    /// K18 för varje sekund i `[from, to)`, hörda när de mäts.
    static func k18Run(from: Int, to: Int) -> [RawFrame] {
        (from..<to).map { record($0) }
    }
}

final class ListenerStatusTests: XCTestCase {
    private let t0 = 1_791_849_600 // en minutgräns

    func testSenasteK18OchMinuternaDeTäcker() {
        var s = ListenerStatus()
        XCTAssertNil(s.lastK18Heard)
        for n in Notiser.k18Run(from: t0, to: t0 + 130) { s.add(n) }
        XCTAssertEqual(s.lastK18Heard, Date(timeIntervalSince1970: Double(t0 + 129)))
        XCTAssertEqual(s.lastK18Record, Date(timeIntervalSince1970: Double(t0 + 129)))
        XCTAssertEqual(s.k18Minutes, [t0 / 60, t0 / 60 + 1, t0 / 60 + 2])
        XCTAssertNil(s.lastSync)
    }

    func testEnSynkÄrSenasteCompleteIngetAnnat() {
        var s = ListenerStatus()
        let start = Notiser.note(10, Ramar.ram(Ramar.start()))
        let end = Notiser.note(11, Ramar.ram(Ramar.end(records: 3, trim: 5)))
        let klar = Notiser.note(12, Ramar.ram(Ramar.complete()))
        let senare = Notiser.note(900, Ramar.ram(Ramar.complete()))
        for n in [start, end] { s.add(n) }
        XCTAssertNil(s.lastSync, "START och END är ingen färdig synk")
        s.add(klar)
        XCTAssertEqual(s.lastSync, Date(timeIntervalSince1970: 12))
        s.add(senare)
        XCTAssertEqual(s.lastSync, Date(timeIntervalSince1970: 900))
        // En äldre notis (efter en inläsning ur filerna) flyttar inte tiden bakåt.
        s.add(klar)
        XCTAssertEqual(s.lastSync, Date(timeIntervalSince1970: 900))
    }

    func testBaraKaraktäristik0005RäknasOchEnTrasigRamInte() {
        var s = ListenerStatus()
        s.add(Notiser.note(5, Ramar.ram(Ramar.complete()), "fd4b0003"))
        s.add(Notiser.note(6, Ramar.ram(Ramar.k18(0)), "fd4b0004"))
        XCTAssertNil(s.lastSync)
        XCTAssertNil(s.lastK18Heard)

        var dålig = Ramar.ram(Notiser.k18(t0))
        dålig[dålig.count - 1] ^= 1
        s.add(Notiser.note(7, dålig))
        XCTAssertEqual(s.badChecksums, 1)
        XCTAssertNil(s.lastK18Heard, "en ram med fel summa räknas inte")
        var dåligSynk = Ramar.ram(Ramar.complete())
        dåligSynk[dåligSynk.count - 1] ^= 1
        s.add(Notiser.note(8, dåligSynk))
        XCTAssertNil(s.lastSync)
    }

    func testEnRamDeladPåTvåNotiserHörsNärDenBlevHel() {
        var s = ListenerStatus()
        let b = Ramar.ram(Notiser.k18(t0))
        s.add(Notiser.note(Double(t0), Array(b.prefix(60))))
        XCTAssertNil(s.lastK18Heard)
        s.add(Notiser.note(Double(t0) + 0.5, Array(b.dropFirst(60))))
        XCTAssertEqual(s.lastK18Heard, Date(timeIntervalSince1970: Double(t0) + 0.5))
        XCTAssertEqual(s.k18Minutes, [t0 / 60])
    }

    func testEnPostFrånFramtidenRäknasInteSomTäckning() {
        var s = ListenerStatus()
        // Bandets klocka sa tre dygn fram; telefonen hörde den nu.
        s.add(Notiser.note(Double(t0), Ramar.ram(Notiser.k18(t0 + 3 * 86_400))))
        XCTAssertEqual(s.lastK18Heard, Date(timeIntervalSince1970: Double(t0)))
        XCTAssertNil(s.lastK18Record)
        XCTAssertTrue(s.k18Minutes.isEmpty)
    }

    // BESLUT B158 · METOD M87. Natten 23→24 nov 2026 (formen, inga värden): bandet var inte anslutet över natten,
    // Whoop-appen synkade 8,5 timmar på två minuter på morgonen, och natten räknades mitt i. En synk som kommer
    // ikapp märks när den är klar, så att natten räknas om.
    func testEnSynkSomKomIkappMärksNärDenÄrKlar() {
        var s = ListenerStatus()
        let hörd = Double(t0 + 8 * 3600)
        for sek in 0..<600 { s.add(Notiser.note(hörd + Double(sek) / 100, Ramar.ram(Notiser.k18(t0 + sek)))) }
        XCTAssertNil(s.lastCatchUp, "inte förrän synken är klar")
        s.add(Notiser.note(hörd + 10, Ramar.ram(Ramar.complete())))
        XCTAssertEqual(s.lastCatchUp, Date(timeIntervalSince1970: hörd + 10))
        XCTAssertEqual(s.lastCatchUpRecords, 600)
        XCTAssertEqual(s.lastCatchUpLag, 8 * 3600, accuracy: 1e-6)
    }

    func testEnVanligSynkVar10eMinutÄrInteIkapp() {
        var s = ListenerStatus()
        // Posterna från de senaste tio minuterna, hörda i en synk.
        let hörd = Double(t0 + 600)
        for sek in 0..<600 { s.add(Notiser.note(hörd + Double(sek) / 100, Ramar.ram(Notiser.k18(t0 + sek)))) }
        s.add(Notiser.note(hörd + 10, Ramar.ram(Ramar.complete())))
        XCTAssertEqual(s.lastSync, Date(timeIntervalSince1970: hörd + 10))
        XCTAssertNil(s.lastCatchUp)
    }

    func testEftersläpningenBörjarOmEfterVarjeSynk() {
        var s = ListenerStatus()
        let hörd = Double(t0 + 3 * 3600)
        s.add(Notiser.note(hörd, Ramar.ram(Notiser.k18(t0))))
        s.add(Notiser.note(hörd + 1, Ramar.ram(Ramar.complete())))
        XCTAssertEqual(s.lastCatchUp, Date(timeIntervalSince1970: hörd + 1))
        // Nästa synk bär bara färska poster: den är inte ikapp, och tiden står kvar.
        s.add(Notiser.note(hörd + 600, Ramar.ram(Notiser.k18(t0 + 3 * 3600 + 300))))
        s.add(Notiser.note(hörd + 601, Ramar.ram(Ramar.complete())))
        XCTAssertEqual(s.lastSync, Date(timeIntervalSince1970: hörd + 601))
        XCTAssertEqual(s.lastCatchUp, Date(timeIntervalSince1970: hörd + 1))
        XCTAssertEqual(s.lastCatchUpRecords, 1)
    }

    func testSynkIkappRäknarOmNättersomEnHämtning() {
        // K18Nights.fetchEnds läser orden i fetchEnds ur sidofilen; NightLedger räknar om efter dem.
        XCTAssertTrue(RecordingLog.fetchEnds.contains(RecordingLog.Link.syncCaughtUp.rawValue))
        let t = Date(timeIntervalSince1970: 1_795_500_000)
        var fil = RecordingLog.header(utcOffsetSeconds: 3600)
        fil.append(RecordingLog.link(.syncCaughtUp, text: "600 K18-sekunder, äldsta 480 min sent", at: t))
        let ut = RecordingLog.decode(fil).links
        XCTAssertEqual(ut.map(\.word), ["synk ikapp"])
        XCTAssertEqual(ut.first?.time, t)
    }

    func testHistorikSomHördesSenareTäckerDenMinutenDenMätts() {
        // Whoop synkar klockan 07: posterna är från natten, hörda på morgonen.
        var s = ListenerStatus()
        let hörd = Double(t0 + 8 * 3600)
        for sek in 0..<120 { s.add(Notiser.note(hörd + Double(sek) / 100, Ramar.ram(Notiser.k18(t0 + sek)))) }
        XCTAssertEqual(s.k18Minutes, [t0 / 60, t0 / 60 + 1])
        XCTAssertEqual(s.lastK18Record, Date(timeIntervalSince1970: Double(t0 + 119)))
        XCTAssertEqual(s.lastK18Heard!.timeIntervalSince1970, hörd + 1.19, accuracy: 1e-6)
    }

    func testInläsningUrFilenOchLivePåhoppetGerSammaSomEnKörning() {
        let alla = Notiser.k18Run(from: t0, to: t0 + 400)
            + [Notiser.note(Double(t0 + 401), Ramar.ram(Ramar.complete()))]
        let hel = ListenerStatus.read(alla)
        // Filen lästes till 250, appen hörde 150 och uppåt under tiden: överlapp.
        var live = ListenerStatus()
        for n in alla[150...] { live.add(n) }
        var läst = ListenerStatus.read(Array(alla[..<250]))
        läst.merge(live)
        XCTAssertEqual(läst, hel)
        // Att slå ihop samma sak en gång till ändrar inget.
        läst.merge(live)
        XCTAssertEqual(läst, hel)
    }

    func testInläsningUrDygnsfilenGerSammaSomNotiserEnEfterEn() {
        let alla = Notiser.k18Run(from: t0, to: t0 + 300)
            + [Notiser.note(Double(t0 + 301), Ramar.ram(Ramar.complete()))]
        var fil = Data()
        for n in alla { fil.append(RawFrameLog.line(n)) }
        fil.append(contentsOf: Array("{\"t\":1,\"k\"".utf8))   // en halvskriven sista rad
        var s = ListenerStatus()
        s.read(log: fil)
        XCTAssertEqual(s, ListenerStatus.read(alla))
        XCTAssertEqual(s.lastSync, Date(timeIntervalSince1970: Double(t0 + 301)))
    }

    func testMängdenAvMinuterVäxerInteOändligt() {
        var s = ListenerStatus()
        // Tio dygn av en post per minut.
        for m in 0..<(10 * 1440) {
            s.add(Notiser.record(t0 + m * 60))
        }
        XCTAssertLessThanOrEqual(s.k18Minutes.count, 8000)
        XCTAssertTrue(s.k18Minutes.contains(t0 / 60 + 10 * 1440 - 1), "det nyaste finns kvar")
    }

    // MARK: Fönstret och täckningen

    func testSenasteNattenFöreOchEfterTolv() {
        let morgon = Date(timeIntervalSince1970: Tid.lokal(9))
        let w = NightWindow.latest(now: morgon, utcOffsetSeconds: Tid.cest)
        XCTAssertEqual(w.start.timeIntervalSince1970, Tid.lokal(dag: 12, 18))
        XCTAssertEqual(w.end.timeIntervalSince1970, Tid.lokal(12))
        XCTAssertEqual(w.until, morgon, "natten pågår: räknas fram till nu")
        XCTAssertTrue(w.inProgress)

        // BESLUT B50. På eftermiddagen står den färdiga natten kvar; kl 18 byter fönstret
        // till natten som börjar (NightWindowTests prövar gränsen och zonbytet).
        let eftermiddag = Date(timeIntervalSince1970: Tid.lokal(15))
        let e = NightWindow.latest(now: eftermiddag, utcOffsetSeconds: Tid.cest)
        XCTAssertEqual(e.start.timeIntervalSince1970, Tid.lokal(dag: 12, 18), "eftermiddagen visar natten som var")
        XCTAssertFalse(e.inProgress)

        let kväll = Date(timeIntervalSince1970: Tid.lokal(20))
        let k = NightWindow.latest(now: kväll, utcOffsetSeconds: Tid.cest)
        XCTAssertEqual(k.start.timeIntervalSince1970, Tid.lokal(18), "kvällen visar natten som börjat")
        XCTAssertEqual(k.end.timeIntervalSince1970, Tid.lokal(dag: 14, 12))
        XCTAssertEqual(k.until, kväll)
        XCTAssertTrue(k.inProgress)

        // Efter midnatt är det samma natt som på kvällen.
        let efterMidnatt = Date(timeIntervalSince1970: Tid.lokal(dag: 14, 0, 30))
        let n = NightWindow.latest(now: efterMidnatt, utcOffsetSeconds: Tid.cest)
        XCTAssertEqual(n.start.timeIntervalSince1970, Tid.lokal(dag: 13, 18))
        XCTAssertEqual(n.end.timeIntervalSince1970, Tid.lokal(dag: 14, 12))
        XCTAssertEqual(n.until, efterMidnatt)
    }

    func testTäckningenRäknasÖverMidnattOchSlutarVidNu() {
        // Natten 12→13 okt, 18:00–12:00 = 1080 minuter. K18 från 22:00 till 06:00.
        // Klockan 13:00: natten är slut och `latest` visar den (kl 18 byter den, BESLUT B50).
        let now = Date(timeIntervalSince1970: Tid.lokal(13))
        let w = NightWindow.latest(now: now, utcOffsetSeconds: Tid.cest)
        var s = ListenerStatus()
        let från = Int(Tid.lokal(dag: 12, 22))
        let till = Int(Tid.lokal(dag: 13, 6))
        for m in stride(from: från, to: till, by: 60) { s.add(Notiser.record(m)) }
        let c = s.coverage(w)
        XCTAssertEqual(c?.totalMinutes, 1080)
        XCTAssertEqual(c?.coveredMinutes, 8 * 60)
        XCTAssertEqual(c?.fraction ?? 0, 480.0 / 1080.0, accuracy: 1e-12)

        // Poster utanför fönstret (kvällen före, eftermiddagen efter) tillför inget.
        var t = s
        t.add(Notiser.record(Int(Tid.lokal(dag: 12, 17, 59))))
        t.add(Notiser.record(Int(Tid.lokal(dag: 13, 12))))
        XCTAssertEqual(t.coverage(w)?.coveredMinutes, 480)
    }

    func testPågåendeNattTäckerBaraFramTillNu() {
        let nu = Date(timeIntervalSince1970: Tid.lokal(dag: 13, 2))
        let w = NightWindow.latest(now: nu, utcOffsetSeconds: Tid.cest)   // 18:00 → 02:00 = 480 min
        var s = ListenerStatus()
        for m in stride(from: Int(w.start.timeIntervalSince1970), to: Int(nu.timeIntervalSince1970), by: 60) {
            s.add(Notiser.record(m))
        }
        XCTAssertEqual(s.coverage(w)?.totalMinutes, 480)
        XCTAssertEqual(s.coverage(w)?.fraction ?? 0, 1, accuracy: 1e-12)
        XCTAssertTrue(w.inProgress)
    }

    func testTomtFönsterHarIngenTäckning() {
        let s = ListenerStatus()
        let t = Date(timeIntervalSince1970: Double(t0))
        let w = NightWindow.Window(start: t, end: t.addingTimeInterval(3600), until: t)
        XCTAssertNil(s.coverage(w))
    }
}

// MARK: - Export av ett intervall

final class DayExportTests: XCTestCase {
    private func läs(_ zip: Data) -> [String: Data] {
        let b = [UInt8](zip)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var ut: [String: Data] = [:]
        var o = 0
        while o + 30 <= b.count, u32(o) == 0x0403_4B50 {
            XCTAssertEqual(u16(o + 8), 0)
            let storlek = u32(o + 18)
            let namnLängd = u16(o + 26)
            let extra = u16(o + 28)
            let namn = String(decoding: b[(o + 30)..<(o + 30 + namnLängd)], as: UTF8.self)
            let start = o + 30 + namnLängd + extra
            ut[namn] = Data(b[start..<(start + storlek)])
            o = start + storlek
        }
        return ut
    }

    /// Två dygnsfiler: den 12:e (zon +2) och den 13:e, med en notis per tio
    /// minuter och ett märke i vardera.
    private func dygn() -> [ExportPackage.DayPart] {
        func fil(_ dag: Int) -> ExportPackage.DayPart {
            var puls = RecordingLog.header(utcOffsetSeconds: Tid.cest)
            var t2 = Data()
            for h in 0..<24 {
                for m in stride(from: 0, to: 60, by: 10) {
                    let t = Tid.lokal(dag: dag, h, m)
                    t2.append(RawFrameLog.line(Notiser.note(t, [UInt8](repeating: UInt8(h), count: 4))))
                }
            }
            puls.append(RecordingLog.marker("skak", at: Date(timeIntervalSince1970: Tid.lokal(dag: dag, 23, 5))))
            return ExportPackage.DayPart(stem: "dygn-2026-10-\(dag)", pulse: puls, frames: t2)
        }
        return [fil(13), fil(12)] // i oordning med flit
    }

    func testEnNattÖverMidnattPlockasUrBådaDygnenISammaOrdning() throws {
        let från = Date(timeIntervalSince1970: Tid.lokal(dag: 12, 18))
        let till = Date(timeIntervalSince1970: Tid.lokal(dag: 13, 12))
        let r = ExportPackage.interval(parts: dygn(), from: från, to: till, utcOffsetSeconds: Tid.cest,
                                       compress: false)
        XCTAssertEqual(r.name, "idunn-dygn-2026-10-12-1800-2026-10-13-1200.zip")
        XCTAssertEqual(r.summary.notifications, 6 * 6 + 12 * 6, "18–24 den 12:e och 00–12 den 13:e")
        XCTAssertEqual(r.summary.markers, 1, "märket 23:05 den 12:e; det den 13:e ligger efter 12")

        let filer = läs(try XCTUnwrap(r.zip))
        let stem = "dygn-2026-10-12-1800-2026-10-13-1200"
        XCTAssertEqual(Set(filer.keys), [stem + ".jsonl", stem + ".t2.jsonl"])
        let noter = RawFrameLog.decode(try XCTUnwrap(filer[stem + ".t2.jsonl"])).frames
        XCTAssertEqual(noter.count, 108)
        XCTAssertEqual(noter.first?.time.timeIntervalSince1970, Tid.lokal(dag: 12, 18))
        XCTAssertEqual(noter.last?.time.timeIntervalSince1970, Tid.lokal(dag: 13, 11, 50), "slutet är exklusivt")
        XCTAssertEqual(noter.map(\.time), noter.map(\.time).sorted())
        let log = RecordingLog.decode(try XCTUnwrap(filer[stem + ".jsonl"]))
        XCTAssertEqual(log.utcOffsetSeconds, Tid.cest)
        XCTAssertEqual(log.markers.map(\.label), ["skak"])
    }

    /// METOD M43. Länkens rader följer med intervallet, i tidsordning bland märkena.
    func testIntervalletTarMedLänkradernaIOrdning() throws {
        let t = Tid.lokal(10)
        var puls = RecordingLog.header(utcOffsetSeconds: Tid.cest)
        puls.append(RecordingLog.marker("rotera x", at: Date(timeIntervalSince1970: t)))
        puls.append(RecordingLog.marker("rotera y", at: Date(timeIntervalSince1970: t + 20)))
        puls.append(RecordingLog.link(.disconnected, code: 6, text: "påhittad", at: Date(timeIntervalSince1970: t + 10)))
        puls.append(RecordingLog.link(.connected, at: Date(timeIntervalSince1970: t + 30)))
        puls.append(RecordingLog.link(.connected, at: Date(timeIntervalSince1970: t + 600)))
        var t2 = Data()
        t2.append(RawFrameLog.line(Notiser.note(t + 1, [1, 2, 3, 4])))
        let del = ExportPackage.DayPart(stem: "dygn-2026-10-13", pulse: puls, frames: t2)
        let r = ExportPackage.interval(parts: [del], from: Date(timeIntervalSince1970: t - 60),
                                       to: Date(timeIntervalSince1970: t + 60), utcOffsetSeconds: Tid.cest,
                                       compress: false)
        XCTAssertEqual(r.summary.markers, 2)
        let filer = läs(try XCTUnwrap(r.zip))
        let sida = try XCTUnwrap(filer["dygn-2026-10-13-0959-2026-10-13-1001.jsonl"])
        let log = RecordingLog.decode(sida)
        XCTAssertEqual(log.markers.map(\.label), ["rotera x", "rotera y"])
        XCTAssertEqual(log.links.map(\.word), ["frånkopplad", "ansluten"])
        XCTAssertEqual(log.links.first?.code, 6)
        let rader = String(decoding: sida, as: UTF8.self).split(separator: "\n")
        XCTAssertEqual(rader.count, 5, "zonen, två märken och två länkrader")
        XCTAssertTrue(rader[2].contains("frånkopplad"), "tidsordning: märket, länken, märket, länken")
    }

    func testEttIntervallUtanNotiserGerIngenZip() {
        let r = ExportPackage.interval(parts: dygn(),
                                       from: Date(timeIntervalSince1970: Tid.lokal(dag: 20, 0)),
                                       to: Date(timeIntervalSince1970: Tid.lokal(dag: 20, 6)),
                                       utcOffsetSeconds: Tid.cest)
        XCTAssertNil(r.zip)
        XCTAssertEqual(r.summary.notifications, 0)
        let vänt = ExportPackage.interval(parts: dygn(), from: Date(timeIntervalSince1970: 10),
                                          to: Date(timeIntervalSince1970: 5), utcOffsetSeconds: 0)
        XCTAssertNil(vänt.zip)
    }

    func testNotisernaMedSammaTidBehållerSinOrdning() throws {
        let t = Tid.lokal(10)
        var t2 = Data()
        for i in 0..<5 { t2.append(RawFrameLog.line(Notiser.note(t, [UInt8(i)]))) }
        let del = ExportPackage.DayPart(stem: "dygn-2026-10-13", pulse: RecordingLog.header(utcOffsetSeconds: 0),
                                        frames: t2)
        let r = ExportPackage.interval(parts: [del], from: Date(timeIntervalSince1970: t - 60),
                                       to: Date(timeIntervalSince1970: t + 60), utcOffsetSeconds: Tid.cest,
                                       compress: false)
        let filer = läs(try XCTUnwrap(r.zip))
        let n = RawFrameLog.decode(try XCTUnwrap(filer["dygn-2026-10-13-0959-2026-10-13-1001.t2.jsonl"])).frames
        XCTAssertEqual(n.map { $0.bytes[0] }, [0, 1, 2, 3, 4])
    }

    func testHelaDygnetÄrFilernaSomDeÄrOchHarDygnsnamn() {
        XCTAssertEqual(ExportPackage.fileName(stem: "dygn-2026-10-13", offWristOnly: false),
                       "idunn-dygn-2026-10-13.zip")
    }
}
