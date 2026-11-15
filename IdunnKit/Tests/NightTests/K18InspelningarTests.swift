import Foundation
import XCTest
import DemoData
import HeartRate
import WhoopFrames
@testable import Night

// METOD M28 · METOD M41 · BESLUT B48 (K1). Nätter som spelades in före dygnsfilerna har sin
// K18 i inspelningens `<start>.t2.jsonl`. Bygge 9 sökte K18-nätter bara i `dygn-*`, så
// natten 12→13 okt blev en gammal inspelning utan lager. Nu läser en K18-natt också
// de inspelningar som överlappar fönstret kl 12–12. Påhittade nätter (DemoK18Nights)
// skrivna som filer, och inga värden ur något band.

final class K18InspelningarTests: XCTestCase {
    let zon = 7200

    func dag(_ d: Int) -> DayLog.Day { DayLog.Day(year: 2026, month: 10, day: d) }
    func natt(_ d: Int) -> WakeDay { WakeDay(daysSince1970: dag(d).daysSince1970) }

    /// Klockan `h:m` den lokala dagen `d` (oktober 2026).
    func tid(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        DayLog.date(of: dag(d), hour: h, minute: m, utcOffsetSeconds: zon)
    }

    // MARK: Hjälpare

    func uppvakningsdag(_ n: DemoK18Nights.Night) -> WakeDay {
        WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
    }

    /// Namnet inspelningen av natten skulle ha: starten 90 sekunder före första posten, i UTC.
    func inspelningsstam(_ n: DemoK18Nights.Night) -> String {
        RecordingStem.stem(for: Date(timeIntervalSince1970: Double(n.records[0].time) - 90))
    }

    /// Inspelningen som den ligger på telefonen: sidofilen (zonen i huvudet) och
    /// `.t2.jsonl` med K18-notiserna. Inga dygnsfiler.
    func inspelning(_ n: DemoK18Nights.Night) -> K18Days.File {
        K18Days.File(stem: inspelningsstam(n), sidecar: RecordingLog.header(utcOffsetSeconds: n.utcOffsetSeconds),
                     frames: DemoK18Frames.log(DemoK18Frames.notifications(n.records)))
    }

    /// Samma notiser som dygnsfiler, som lyssnaren skriver dem.
    func dygnsfiler(_ n: DemoK18Nights.Night) -> [K18Days.File] {
        var perDag: [String: [RawFrame]] = [:]
        for x in DemoK18Frames.notifications(n.records) {
            perDag[DayLog.stem(for: x.time, utcOffsetSeconds: n.utcOffsetSeconds), default: []].append(x)
        }
        return perDag.keys.sorted().map { (stem: String) -> K18Days.File in
            K18Days.File(stem: stem, sidecar: RecordingLog.header(utcOffsetSeconds: n.utcOffsetSeconds),
                         frames: DemoK18Frames.log(perDag[stem] ?? []))
        }
    }

    /// Facit: samma notiser i ett svep, utan filer.
    func facit(_ n: DemoK18Nights.Night, dag: WakeDay) -> NightResult? {
        K18Night.analyze(K18Series(notifications: DemoK18Frames.notifications(n.records)), wakeDay: dag,
                         startOffsetSeconds: n.utcOffsetSeconds, endOffsetSeconds: n.utcOffsetSeconds)
    }

    // MARK: Namnet

    func testStammenÄrStartenIUTCOchSammaSträngSomAppenSkriver() {
        XCTAssertEqual(RecordingStem.start(ofStem: "2026-10-12T19-47-05Z"), Date(timeIntervalSince1970: 1_791_834_425))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        for t in [1_791_834_425.0, 0.0, 1_760_300_000.0, 1_798_761_599.0] {
            let d = Date(timeIntervalSince1970: t)
            // Så skriver `NightFiles.stem(for:)` namnet.
            let appens = f.string(from: d).replacingOccurrences(of: ":", with: "-")
            XCTAssertEqual(RecordingStem.stem(for: d), appens)
            XCTAssertEqual(RecordingStem.start(ofStem: appens), d)
        }
    }

    func testAllaAndraNamnÄrInteInspelningar() {
        let inte: [String] = ["dygn-2026-10-12", "natt-2026-10-12", "", "2026-10-12T19:47:05Z", "2026-10-12T19-47-05",
                              "2026-13-12T19-47-05Z", "2026-10-12T25-47-05Z", "2026-10-12T19-47-05Z.jsonl",
                              "abcd-10-12T19-47-05Z"]
        for s in inte { XCTAssertNil(RecordingStem.start(ofStem: s), s) }
    }

    // MARK: Vilka nätter en inspelning berör

    func testEnInspelningHörTillFönstretDenBörjadeI() {
        // 21:47 den 12:e är natten som slutar den 13:e.
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: tid(12, 21, 47), utcOffsetSeconds: zon), [natt(13)])
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: tid(12, 12), utcOffsetSeconds: zon), [natt(13)],
                       "kl 12 börjar nästa fönster")
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: tid(12, 23, 59), utcOffsetSeconds: zon), [natt(13)])
    }

    func testEnInspelningSomBörjatFöreMiddagenKanLöpaInINästaFönster() {
        // Före kl 12 kan en inspelning på upp till `recordingReachHours` löpa över middagen.
        XCTAssertEqual(K18Days.recordingReachHours, 12)
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: tid(12, 11, 59), utcOffsetSeconds: zon), [natt(12), natt(13)])
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: tid(13, 3), utcOffsetSeconds: zon), [natt(13), natt(14)])
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: tid(13, 0), utcOffsetSeconds: zon), [natt(13), natt(14)])
    }

    func testDagenRäknasPåVäggklockanIZonen() {
        let start = tid(12, 21, 47)   // 19:47 UTC
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: start, utcOffsetSeconds: 0), [natt(13)], "19:47")
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: start, utcOffsetSeconds: -5 * 3600), [natt(13)], "14:47")
        XCTAssertEqual(K18Days.wakeDays(ofRecordingStart: start, utcOffsetSeconds: 12 * 3600),
                       [natt(13), natt(14)], "07:47 den 13:e, före middagen")
    }

    func testEnInspelningGerEnKandidatUtanDygnsfiler() {
        let stam = "2026-10-12T19-47-05Z"
        XCTAssertEqual(NightLedger.candidates(dayStems: [], recordingStems: [stam], utcOffsetSeconds: zon,
                                              today: natt(20)), [natt(13)])
        XCTAssertEqual(NightLedger.candidates(dayStems: [], recordingStems: [stam], utcOffsetSeconds: zon,
                                              today: natt(12)), [], "ingen natt i framtiden")
        // Dygn och inspelning ger sina dagar, ingen dubbleras, och ett namn som inte är en inspelning räknas inte.
        let blandat = NightLedger.candidates(dayStems: [DayLog.stem(for: dag(13))],
                                             recordingStems: [stam, "natt-2026-10-12", "skräp"],
                                             utcOffsetSeconds: zon, today: natt(20))
        XCTAssertEqual(blandat, [natt(14), natt(13)])
    }

    func testFilernaEnNattLäserÄrDygnenOchInspelningarnaSomÖverlappar() {
        let denna = "2026-10-12T19-47-05Z"
        let tidigare = "2026-10-05T19-00-00Z"
        let senare = "2026-10-20T19-00-00Z"
        let alla = [senare, "dygn-2026-10-12", denna, "natt-2026-10-13", tidigare, "skräp"]
        XCTAssertEqual(K18Days.recordingStems(wakeDay: natt(13), among: alla, utcOffsetSeconds: zon), [denna])
        XCTAssertEqual(K18Days.recordingStems(wakeDay: natt(21), among: alla, utcOffsetSeconds: zon), [senare])
        XCTAssertEqual(K18Days.recordingStems(wakeDay: natt(14), among: alla, utcOffsetSeconds: zon), [])
        XCTAssertEqual(K18Days.stems(wakeDay: natt(13), includeNext: true, recordingStems: alla, utcOffsetSeconds: zon),
                       ["dygn-2026-10-12", "dygn-2026-10-13", "dygn-2026-10-14", denna], "dygnen först")
        XCTAssertEqual(K18Days.stems(wakeDay: natt(13), includeNext: false, recordingStems: [],
                                     utcOffsetSeconds: zon), K18Days.stems(wakeDay: natt(13), includeNext: false))
        // I den ordning de började.
        let a = "2026-10-12T22-00-00Z", b = "2026-10-12T19-00-00Z"
        XCTAssertEqual(K18Days.recordingStems(wakeDay: natt(13), among: [a, b], utcOffsetSeconds: zon), [b, a])
    }

    // MARK: Natten ur en inspelning

    func testNattenUrEnInspelningUtanDygnsfilerÄrSammaNattSomIEttSvepMedLager() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dagen = uppvakningsdag(n)
        let stam = inspelningsstam(n)
        let filer: [String: K18Days.File] = [stam: inspelning(n)]

        let ur = try XCTUnwrap(K18Days.night(wakeDay: dagen, includeNext: false, recordingStems: [stam],
                                              fallbackOffsetSeconds: 0, load: { filer[$0] }))
        let svep = try XCTUnwrap(facit(n, dag: dagen))
        XCTAssertEqual(ur.source, .k18)
        XCTAssertEqual(ur.wakeDay, dagen)
        XCTAssertEqual(ur.utcOffsetSeconds, z, "zonen kommer ur inspelningens huvud, inte ur reservzonen")
        XCTAssertNotNil(ur.layers, "en K18-natt har lager")
        XCTAssertGreaterThan(ur.analysis.validWindows, 40)
        XCTAssertTrue(ur == svep, "natten ur inspelningen skiljer sig från natten i ett svep")

        // Utan inspelningen i listan finns ingen natt: det var bygge 9.
        XCTAssertNil(K18Days.night(wakeDay: dagen, includeNext: false, recordingStems: [],
                                   fallbackOffsetSeconds: z, load: { filer[$0] }))
    }

    func testEnSekundIBådeInspelningOchDygnRäknasEnGång() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dagen = uppvakningsdag(n)
        let svep = try XCTUnwrap(facit(n, dag: dagen))
        let dygn = dygnsfiler(n)
        XCTAssertEqual(dygn.count, 2)
        var filer: [String: K18Days.File] = [:]
        for f in dygn + [inspelning(n)] { filer[f.stem] = f }
        let stam = inspelningsstam(n)

        let båda = try XCTUnwrap(K18Days.night(wakeDay: dagen, includeNext: false, recordingStems: [stam],
                                                fallbackOffsetSeconds: z, load: { filer[$0] }))
        XCTAssertTrue(båda == svep, "samma poster i två filer ger samma natt som i en")
        let baraDygn = try XCTUnwrap(K18Days.night(wakeDay: dagen, includeNext: false, recordingStems: [],
                                                    fallbackOffsetSeconds: z, load: { filer[$0] }))
        XCTAssertTrue(baraDygn == båda)
    }

    func testBaraInspelningarSomÖverlapparFönstretÖppnas() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dagen = uppvakningsdag(n)
        let stam = inspelningsstam(n)
        var filer: [String: K18Days.File] = [stam: inspelning(n)]
        let tidigare = "2026-10-01T19-00-00Z", senare = "2026-10-20T19-00-00Z"
        filer[tidigare] = K18Days.File(stem: tidigare, sidecar: nil, frames: Data())
        filer[senare] = K18Days.File(stem: senare, sidecar: nil, frames: Data())
        var begärda: [String] = []
        let ur = K18Days.night(wakeDay: dagen, includeNext: false, recordingStems: [tidigare, stam, senare],
                               fallbackOffsetSeconds: z, load: { (s: String) -> K18Days.File? in
            begärda.append(s)
            return filer[s]
        })
        XCTAssertNotNil(ur)
        XCTAssertEqual(begärda, K18Days.stems(wakeDay: dagen, includeNext: false) + [stam],
                       "bara dygnen och inspelningen som överlappar öppnas")
    }

    // MARK: Bygget räknar om

    func testBygge9SågEnDagUtanNattOchBygge10HittarNattenIInspelningen() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dagen = uppvakningsdag(n)
        let stam = inspelningsstam(n)
        let dygnsstam = DayLog.stem(for: DayLog.Day(daysSince1970: dagen.daysSince1970))
        let filer: [String: K18Days.File] = [stam: inspelning(n)]
        let nu = NightLedger.windowEnd(dagen, utcOffsetSeconds: z).addingTimeInterval(3 * 3600)

        var poster: [WakeDay: NightLedger.Entry] = [:]
        func räkna(_ bygge: String, inspelningar: [String]) -> Int {
            NightLedger.computeDue(dayStems: [dygnsstam], recordingStems: inspelningar, entries: poster,
                                   build: bygge, now: nu, utcOffsetSeconds: z, load: { filer[$0] },
                                   save: { (e: NightLedger.Entry) -> Void in poster[e.wakeDay] = e })
        }

        // Bygge 9: dagen har ett dygn (som sparades efteråt) men inspelningen var okänd för räkningen.
        XCTAssertEqual(räkna("9", inspelningar: []), 1)
        XCTAssertNotNil(poster[dagen], "dagen sparades")
        XCTAssertNil(poster[dagen]?.digest, "…utan natt")
        XCTAssertEqual(räkna("9", inspelningar: []), 0, "och räknas inte om i samma bygge")

        // Bygge 10: nytt bygge räknar om, och nu finns inspelningen bland kandidaterna.
        XCTAssertEqual(räkna("10", inspelningar: [stam]), 1)
        let post = try XCTUnwrap(poster[dagen])
        XCTAssertEqual(post.build, "10")
        let digest = try XCTUnwrap(post.digest, "natten finns nu")
        XCTAssertEqual(digest.source, .k18)
        XCTAssertEqual(digest.wakeDay, dagen)
        XCTAssertGreaterThan(try XCTUnwrap(digest.coverage), ListenerCheck.minCoverage)
        XCTAssertFalse(post.preliminary)
        XCTAssertEqual(räkna("10", inspelningar: [stam]), 0, "färdig, och räknas inte om i samma bygge")
    }

    func testNyttByggeRäknarOmEnDagUtanNattÄvenNärBaraInspelningenFinns() {
        // Utan en enda dygnsfil: dagen kommer ur inspelningen.
        let stam = "2026-10-12T19-47-05Z"
        let tidigare = NightLedger.Entry(build: "9", wakeDay: natt(13), computedAt: tid(14, 9), preliminary: false,
                                         settled: false, digest: nil)
        let nu = tid(14, 10)
        func jobb(_ bygge: String) -> [NightLedger.Job] {
            NightLedger.jobs(dayStems: [], recordingStems: [stam], entries: [natt(13): tidigare], build: bygge,
                             now: nu, utcOffsetSeconds: zon)
        }
        XCTAssertEqual(jobb("9"), [], "samma bygge: dagen är räknad")
        XCTAssertEqual(jobb("10"), [NightLedger.Job(wakeDay: natt(13), preliminary: false, settled: false)],
                       "nytt bygge: räkna om")
        // Och en dag som ännu inte har någon post räknas första gången.
        XCTAssertEqual(NightLedger.jobs(dayStems: [], recordingStems: [stam], entries: [:], build: "9", now: nu,
                                        utcOffsetSeconds: zon).map(\.wakeDay), [natt(13)])
    }
}
