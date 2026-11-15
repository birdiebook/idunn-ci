import Foundation
import XCTest
import DemoData
import HeartRate
import WhoopFrames
@testable import Night

// METOD M55 · BESLUT B70. användaren ändring av sömnperioden: natten räknas om för den givna perioden, Återställ ger den
// hittade igen, och en period utanför dygnsfönstret eller med vaknade före somnade avvisas. Påhittade nätter
// (DemoK18Nights); inga värden kommer från ett riktigt band.

final class SleepEditTests: XCTestCase {

    // MARK: Hjälpare

    static let natt: DemoK18Nights.Night = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
    static let serie: K18Series = K18Series(records: natt.records)
    var zon: Int { Self.natt.utcOffsetSeconds }
    var dag: WakeDay { WakeDay(Date(timeIntervalSince1970: Double(Self.natt.wake)), utcOffsetSeconds: zon) }
    var fönster: (from: Date, to: Date) {
        SleepDetection.dayWindow(wakeDay: dag, startOffsetSeconds: zon, endOffsetSeconds: zon)
    }

    func analysera(_ e: SleepEdit?) -> NightResult? {
        K18Night.analyze(Self.serie, wakeDay: dag, startOffsetSeconds: zon, endOffsetSeconds: zon, edit: e)
    }

    /// Natten som den hittades, räknad en gång.
    static var hittadNatt: NightResult?
    func hittad() throws -> NightResult {
        if let h = Self.hittadNatt { return h }
        let h = try XCTUnwrap(analysera(nil), "den påhittade natten har en sömnperiod")
        Self.hittadNatt = h
        return h
    }

    /// Somnade 45 minuter senare och vaknade 20 minuter tidigare än den hittade perioden, i hela minuter.
    func senareInsomning() throws -> SleepEdit {
        let p: SleepPeriod = try XCTUnwrap(try hittad().sleep)
        let på: Int = SleepEdit.clockMinutes(p.onset, wakeDay: dag, utcOffsetSeconds: zon) + 45
        let av: Int = SleepEdit.clockMinutes(p.wake, wakeDay: dag, utcOffsetSeconds: zon) - 20
        return try SleepEdit.make(wakeDay: dag, onsetMinutes: på, wakeMinutes: av, utcOffsetSeconds: zon,
                                  foundOnset: p.onset, foundWake: p.wake)
    }

    // MARK: En ändrad period ger natten för den perioden

    func testÄndradPeriodGerNattenFörPerioden() throws {
        let h: NightResult = try hittad()
        let p: SleepPeriod = try XCTUnwrap(h.sleep)
        let e: SleepEdit = try senareInsomning()
        let r: NightResult = try XCTUnwrap(analysera(e))
        let q: SleepPeriod = try XCTUnwrap(r.sleep)

        XCTAssertEqual(q.onset, e.onset, "perioden börjar vid den ändrade insomningen")
        XCTAssertEqual(q.wake, e.wake, "och slutar när han vaknade")
        XCTAssertEqual(r.edit, e)
        XCTAssertEqual(r.found, SleepInterval(start: p.onset, end: p.wake), "den hittade perioden följer med")
        XCTAssertEqual(r.wakeDay, dag)
        XCTAssertEqual(q.asleepSeconds + q.awakeSeconds + q.gapSeconds, q.periodSeconds, "sömn + vaken + glapp")
        XCTAssertLessThan(q.asleepSeconds, p.asleepSeconds, "kortare period, mindre sömn")
        XCTAssertGreaterThan(q.asleepSeconds, 0)
        XCTAssertGreaterThan(r.analysis.validWindows, 20, "HRV och vilopuls räknas i perioden")
        let stadier: NightStages.Night = try XCTUnwrap(r.stages, "stadierna räknas inom perioden")
        XCTAssertEqual(stadier.onset, e.onset)
        XCTAssertEqual(stadier.epochs.count, (e.wake - e.onset) / NightStages.epochSeconds)
        XCTAssertNotNil(r.curve)
        XCTAssertNotNil(r.layers, "lagren räknas för den nya perioden")

        // Precis samma natt som att räkna kedjan över den givna perioden: inget annat ändras.
        let given: SleepPeriod = try XCTUnwrap(SleepDetection.given(Self.serie, from: fönster.from, to: fönster.to,
                                                                    onset: e.onset, wake: e.wake))
        var direkt: NightResult = K18Night.analyze(Self.serie, sleep: given, utcOffsetSeconds: zon)
        direkt.edit = e
        direkt.found = r.found
        XCTAssertTrue(r == direkt, "den ändrade natten är kedjan över den givna perioden")

        // Sammanfattningen bär den nya perioden och märket.
        let d = NightDigest(r)
        XCTAssertEqual(d.edited, true)
        XCTAssertEqual(d.sleepStart, q.onsetDate)
        XCTAssertEqual(d.sleepEnd, q.wakeDate)
        XCTAssertEqual(d.foundStart, p.onsetDate)
        XCTAssertEqual(d.foundEnd, p.wakeDate)
        XCTAssertEqual(d.onsetMinutes, Double(SleepEdit.clockMinutes(e.onset, wakeDay: dag, utcOffsetSeconds: zon)))
    }

    func testGivenMedDenHittadePeriodensGränserGerSammaEpoker() throws {
        let p: SleepPeriod = try XCTUnwrap(SleepDetection.detect(Self.serie, from: fönster.from, to: fönster.to))
        let g: SleepPeriod = try XCTUnwrap(SleepDetection.given(Self.serie, from: fönster.from, to: fönster.to,
                                                                onset: p.onset, wake: p.wake))
        XCTAssertEqual(g.onset, p.onset)
        XCTAssertEqual(g.wake, p.wake)
        XCTAssertEqual(g.wakeBouts, p.wakeBouts)
        XCTAssertEqual(g.gaps, p.gaps)
        XCTAssertEqual(g.asleepSeconds, p.asleepSeconds)
        XCTAssertEqual(g.awakeSeconds, p.awakeSeconds)
        XCTAssertEqual(g.gapSeconds, p.gapSeconds)
        XCTAssertEqual(g.asleepMinutes, p.asleepMinutes)
        XCTAssertEqual(g.threshold, 0, "ingen tröskel valde perioden")
        XCTAssertEqual(g.windowStart, g.onset)
        XCTAssertEqual(g.windowEnd, g.wake)
    }

    func testGränsernaAvrundasInåtTillHelaEpoker() throws {
        let p: SleepPeriod = try XCTUnwrap(SleepDetection.detect(Self.serie, from: fönster.from, to: fönster.to))
        let g: SleepPeriod = try XCTUnwrap(SleepDetection.given(Self.serie, from: fönster.from, to: fönster.to,
                                                                onset: p.onset + 1, wake: p.wake - 1))
        XCTAssertEqual(g.onset, p.onset + SleepDetection.epochSeconds)
        XCTAssertEqual(g.wake, p.wake - SleepDetection.epochSeconds)
    }

    // MARK: Återställ ger den hittade igen

    func testÅterställGerDenHittadeNattenIgen() throws {
        let h: NightResult = try hittad()
        let e: SleepEdit = try senareInsomning()
        let ändrade: SleepEdits = SleepEdits().setting(e)
        XCTAssertEqual(ändrade[dag], e)
        let åter: SleepEdits = ändrade.removing(dag)
        XCTAssertNil(åter[dag])
        XCTAssertTrue(åter.isEmpty)
        let r: NightResult = try XCTUnwrap(analysera(åter[dag]))
        XCTAssertTrue(r == h, "utan ändringen är natten den hittade, oförändrad")
        XCTAssertNil(r.edit)
        XCTAssertNil(r.found)
        XCTAssertNil(NightDigest(r).edited, "ingen märkning")
        XCTAssertNil(NightDigest(r).foundStart)
    }

    // MARK: Det som avvisas

    func testEnPeriodUtanförDygnsfönstretAvvisas() throws {
        XCTAssertThrowsError(try SleepEdit.make(wakeDay: dag, onsetMinutes: -721, wakeMinutes: 400,
                                                utcOffsetSeconds: zon)) { (fel: Error) in
            XCTAssertEqual(fel as? SleepEdit.Problem, .outsideWindow, "före klockan 12 dagen före")
        }
        XCTAssertThrowsError(try SleepEdit.make(wakeDay: dag, onsetMinutes: -60, wakeMinutes: 721,
                                                utcOffsetSeconds: zon)) { (fel: Error) in
            XCTAssertEqual(fel as? SleepEdit.Problem, .outsideWindow, "efter klockan 12 på uppvakningsdagen")
        }
        XCTAssertNoThrow(try SleepEdit.make(wakeDay: dag, onsetMinutes: -720, wakeMinutes: 720, utcOffsetSeconds: zon),
                         "hela fönstret, kl 12–12, går")

        // En ändring utanför fönstret som ändå kommer in (en gammal fil, en annan zon) gäller inte.
        let h: NightResult = try hittad()
        let p: SleepPeriod = try XCTUnwrap(h.sleep)
        let utanför = SleepEdit(wakeDay: dag, onset: Int(fönster.from.timeIntervalSince1970) - 3_600, wake: p.wake)
        XCTAssertThrowsError(try utanför.check(window: fönster.from, to: fönster.to))
        let r: NightResult = try XCTUnwrap(analysera(utanför))
        XCTAssertTrue(r == h, "natten räknas med den hittade perioden")
        XCTAssertNil(r.edit)

        // En ändring för en annan dag gäller inte heller.
        let e: SleepEdit = try senareInsomning()
        let annan = SleepEdit(wakeDay: dag + 1, onset: e.onset, wake: e.wake)
        XCTAssertTrue(try XCTUnwrap(analysera(annan)) == h)
    }

    func testVaknadeFöreSomnadeAvvisas() throws {
        XCTAssertThrowsError(try SleepEdit.make(wakeDay: dag, onsetMinutes: 400, wakeMinutes: -50,
                                                utcOffsetSeconds: zon)) { (fel: Error) in
            XCTAssertEqual(fel as? SleepEdit.Problem, .wakeNotAfterOnset)
        }
        XCTAssertThrowsError(try SleepEdit.make(wakeDay: dag, onsetMinutes: 400, wakeMinutes: 400,
                                                utcOffsetSeconds: zon)) { (fel: Error) in
            XCTAssertEqual(fel as? SleepEdit.Problem, .wakeNotAfterOnset, "samma minut")
        }
        XCTAssertThrowsError(try SleepEdit.make(wakeDay: dag, onsetMinutes: 400, wakeMinutes: 429,
                                                utcOffsetSeconds: zon)) { (fel: Error) in
            XCTAssertEqual(fel as? SleepEdit.Problem, .tooShort, "kortare än en halvtimme")
        }
        XCTAssertNoThrow(try SleepEdit.make(wakeDay: dag, onsetMinutes: 400, wakeMinutes: 430, utcOffsetSeconds: zon))

        let h: NightResult = try hittad()
        let p: SleepPeriod = try XCTUnwrap(h.sleep)
        let bakvänd = SleepEdit(wakeDay: dag, onset: p.wake, wake: p.onset)
        let r: NightResult = try XCTUnwrap(analysera(bakvänd))
        XCTAssertTrue(r == h, "en bakvänd period gäller inte")
        XCTAssertNil(r.edit)
    }

    func testEnPeriodUtanBandetsDataGällerInte() throws {
        // Klockan 13–14 dagen före: inom fönstret, men långt före nattens första post.
        let e: SleepEdit = try SleepEdit.make(wakeDay: dag, onsetMinutes: -660, wakeMinutes: -600, utcOffsetSeconds: zon)
        XCTAssertNil(SleepDetection.given(Self.serie, from: fönster.from, to: fönster.to, onset: e.onset, wake: e.wake))
        let h: NightResult = try hittad()
        let r: NightResult = try XCTUnwrap(analysera(e))
        XCTAssertTrue(r == h, "natten räknas med den hittade perioden")
        XCTAssertNil(r.edit)
    }

    // MARK: Klockslagen och filen

    func testKlockslagenGårFramOchTillbaka() {
        let d = WakeDay(daysSince1970: 20_000)
        for m in [-720, -50, 0, 405, 720] {
            let t: Int = SleepEdit.unix(minutes: m, wakeDay: d, utcOffsetSeconds: 3_600)
            XCTAssertEqual(SleepEdit.clockMinutes(t, wakeDay: d, utcOffsetSeconds: 3_600), m)
            XCTAssertEqual(SleepEdit.clockMinutes(t + 59, wakeDay: d, utcOffsetSeconds: 3_600), m, "nedåt till minuten")
        }
        XCTAssertEqual(SleepEdit.unix(minutes: 0, wakeDay: d, utcOffsetSeconds: 3_600), 20_000 * 86_400 - 3_600)
    }

    func testFilenGårAttSparaOchLäsaIgen() throws {
        let a = SleepEdit(wakeDay: WakeDay(daysSince1970: 20_400), onset: 1_762_550_000, wake: 1_762_576_000,
                          foundOnset: 1_762_548_000, foundWake: 1_762_577_000)
        let b = SleepEdit(wakeDay: WakeDay(daysSince1970: 20_398), onset: 1_762_380_000, wake: 1_762_405_000)
        let alla: SleepEdits = SleepEdits([a]).setting(b)
        XCTAssertEqual(alla.nights.map(\.wakeDayNumber), [20_398, 20_400], "äldst först")
        let läst: SleepEdits = try SleepEdits.decode(try alla.encoded())
        XCTAssertEqual(läst, alla)
        XCTAssertEqual(läst[b.wakeDay]?.foundOnset, nil)
        XCTAssertEqual(läst[a.wakeDay]?.foundWake, 1_762_577_000)

        let a2 = SleepEdit(wakeDay: a.wakeDay, onset: a.onset + 600, wake: a.wake)
        let ny: SleepEdits = alla.setting(a2)
        XCTAssertEqual(ny.nights.count, 2, "samma dag ersätts")
        XCTAssertEqual(ny[a.wakeDay], a2)
        XCTAssertEqual(SleepEdits([a, a2]).nights, [a2], "den sista för en dag gäller")

        XCTAssertThrowsError(try SleepEdits.decode(Data("inte en fil".utf8)))
        XCTAssertEqual(SleepEdits.fileName, "somn-andringar.json")
    }

    // MARK: Ledgern räknar om en ändrad natt

    func testEnNyEllerBorttagenÄndringRäknarOmNatten() {
        let zon = 7_200
        let d = WakeDay(daysSince1970: DayLog.Day(year: 2026, month: 10, day: 14).daysSince1970)
        let nu: Date = NightLedger.windowEnd(d, utcOffsetSeconds: zon).addingTimeInterval(30 * 3_600)
        let stammar: [String] = [DayLog.stem(for: DayLog.Day(year: 2026, month: 10, day: 13)),
                                 DayLog.stem(for: DayLog.Day(year: 2026, month: 10, day: 14))]
        var poster: [WakeDay: NightLedger.Entry] = [:]
        for w in NightLedger.candidates(dayStems: stammar, today: WakeDay(nu, utcOffsetSeconds: zon)) {
            poster[w] = NightLedger.Entry(build: "1", wakeDay: w, computedAt: nu, preliminary: false,
                                          settled: NightLedger.isSettled(w, now: nu, utcOffsetSeconds: zon), digest: nil)
        }
        let e = SleepEdit(wakeDay: d, onset: 1_000_000, wake: 1_030_000)
        func jobb(_ ä: SleepEdits) -> [NightLedger.Job] {
            NightLedger.jobs(dayStems: stammar, entries: poster, build: "1", now: nu, utcOffsetSeconds: zon, edits: ä)
        }
        XCTAssertEqual(jobb(SleepEdits()), [], "inget att räkna")
        XCTAssertEqual(jobb(SleepEdits([e])), [NightLedger.Job(wakeDay: d, preliminary: false, settled: true)],
                       "en ny ändring räknar om natten")
        poster[d]?.edit = e
        XCTAssertEqual(jobb(SleepEdits([e])), [], "räknad med ändringen")
        XCTAssertEqual(jobb(SleepEdits()).map(\.wakeDay), [d], "återställd: räknas om igen")
        var flyttad = e
        flyttad.onset += 600
        XCTAssertEqual(jobb(SleepEdits([flyttad])).map(\.wakeDay), [d], "en flyttad tid räknas om")
    }

    /// Appens väg: dygnsfilerna som lyssnaren skriver dem, `NightLedger.computeDue` som telefonen kör, och ändringen.
    func testComputeDueRäknarDenÄndradeNattenOchÅterställer() throws {
        let n: DemoK18Nights.Night = Self.natt
        var filer: [String: K18Days.File] = [:]
        var perDag: [String: [RawFrame]] = [:]
        for x in DemoK18Frames.notifications(n.records) {
            perDag[DayLog.stem(for: x.time, utcOffsetSeconds: zon), default: []].append(x)
        }
        for (stem, notiser) in perDag {
            filer[stem] = K18Days.File(stem: stem, sidecar: RecordingLog.header(utcOffsetSeconds: zon),
                                       frames: DemoK18Frames.log(notiser))
        }
        let nu: Date = NightLedger.windowEnd(dag, utcOffsetSeconds: zon).addingTimeInterval(30 * 3_600)
        var poster: [WakeDay: NightLedger.Entry] = [:]
        func räkna(_ ä: SleepEdits) -> Int {
            NightLedger.computeDue(dayStems: Array(filer.keys), entries: poster, build: "1", now: nu,
                                   utcOffsetSeconds: zon, load: { (s: String) -> K18Days.File? in filer[s] },
                                   save: { (e: NightLedger.Entry) -> Void in poster[e.wakeDay] = e }, edits: ä)
        }

        XCTAssertGreaterThan(räkna(SleepEdits()), 0)
        let före: NightDigest = try XCTUnwrap(poster[dag]?.digest)
        XCTAssertNil(före.edited)
        XCTAssertEqual(räkna(SleepEdits()), 0)

        let start: Int = Int(try XCTUnwrap(före.sleepStart).timeIntervalSince1970)
        let slut: Int = Int(try XCTUnwrap(före.sleepEnd).timeIntervalSince1970)
        let e: SleepEdit = try SleepEdit.make(
            wakeDay: dag, onsetMinutes: SleepEdit.clockMinutes(start, wakeDay: dag, utcOffsetSeconds: zon) + 30,
            wakeMinutes: SleepEdit.clockMinutes(slut, wakeDay: dag, utcOffsetSeconds: zon), utcOffsetSeconds: zon)
        XCTAssertEqual(räkna(SleepEdits([e])), 1, "bara den ändrade natten räknas om")
        let efter: NightDigest = try XCTUnwrap(poster[dag]?.digest)
        XCTAssertEqual(poster[dag]?.edit, e)
        XCTAssertEqual(efter.edited, true)
        XCTAssertEqual(efter.sleepStart, Date(timeIntervalSince1970: Double(e.onset)))
        XCTAssertEqual(efter.sleepEnd, Date(timeIntervalSince1970: Double(e.wake)))
        XCTAssertEqual(efter.foundStart, före.sleepStart, "den hittade perioden står kvar bredvid")
        XCTAssertLessThan(try XCTUnwrap(efter.sleepMinutes), try XCTUnwrap(före.sleepMinutes))
        XCTAssertEqual(räkna(SleepEdits([e])), 0)

        XCTAssertEqual(räkna(SleepEdits()), 1, "Återställ räknar om natten")
        XCTAssertNil(poster[dag]?.edit)
        XCTAssertEqual(poster[dag]?.digest, före, "och den är den hittade igen")
    }
}
