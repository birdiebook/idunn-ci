import Foundation
import XCTest
import HeartRate
import WhoopFrames
import DemoData
@testable import Night

// METOD M28. Påhittade nätter (DemoK18Nights): samma slag som K18-poster och
// som 2A37-mätningar, räknade båda vägarna. Inga värden kommer från ett
// riktigt band.

final class K18NightTests: XCTestCase {

    // MARK: Hjälpare

    func sleep(_ n: DemoK18Nights.Night, _ series: K18Series) throws -> SleepPeriod {
        let day = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let w = SleepDetection.dayWindow(wakeDay: day, startOffsetSeconds: n.utcOffsetSeconds,
                                         endOffsetSeconds: n.utcOffsetSeconds)
        return try XCTUnwrap(SleepDetection.detect(series, from: w.from, to: w.to))
    }

    /// Den gamla vägen: samma sekunder som 2A37-mätningar i en inspelning.
    func old(_ n: DemoK18Nights.Night, _ p: SleepPeriod, form: DemoK18Nights.RRForm = .wholeMilliseconds,
             jitter: Double = 0) -> NightRecording {
        var rec = NightRecording()
        for m in n.measurements(form, jitter: jitter) {
            let s = Int(m.time.timeIntervalSince1970.rounded(.down))
            if s >= p.onset && s < p.wake { rec.append(m.measurement, at: m.time) }
        }
        return rec
    }

    func diff(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return abs(a - b)
    }

    func rec(_ t: Int, rr: [Int]) -> K18Record {
        K18Record(time: t, pulse: 60, rr: rr, gravity: .init(x: 0, y: 0, z: 1),
                  skinTemperature: 33, bandTemperature: 30)
    }

    // MARK: Klart när: samma resultat via K18 som via den gamla vägen

    func testSammaResultatViaK18OchGamlaVägen() throws {
        for k in [0, 1, 2] {
            let n = DemoK18Nights.night(daysBeforeLast: k, shortGaps: false)
            let series = K18Series(records: n.records)
            let p = try sleep(n, series)
            XCTAssertEqual(Double(p.onset), Double(n.onset), accuracy: 400, "natt \(k)")
            XCTAssertEqual(Double(p.wake), Double(n.wake), accuracy: 400, "natt \(k)")

            let viaK18 = K18Night.analyze(series, sleep: p, utcOffsetSeconds: n.utcOffsetSeconds)
            let gamla = NightResult.fromNotifications(old(n, p), k18: series, utcOffsetSeconds: n.utcOffsetSeconds)
            XCTAssertEqual(viaK18.source, .k18)
            XCTAssertEqual(gamla.source, .notification)

            // Natten är en riktig natt, inte två tomma resultat som råkar vara lika.
            XCTAssertGreaterThan(viaK18.analysis.validWindows, 40, "natt \(k)")
            XCTAssertNotNil(viaK18.analysis.rmssd.mean)
            XCTAssertNotNil(viaK18.analysis.restingHeartRate)
            XCTAssertNotNil(viaK18.analysis.breathsPerMinute)
            XCTAssertNotNil(viaK18.curve)
            XCTAssertNotNil(viaK18.landscape)
            XCTAssertNotNil(viaK18.poincare)
            XCTAssertFalse(viaK18.pulse.isEmpty)

            // Slagen, ett för ett.
            XCTAssertEqual(viaK18.beats.count, gamla.beats.count, "natt \(k)")
            XCTAssertTrue(viaK18.beats == gamla.beats, "slagen skiljer, natt \(k)")
            // Siffrorna.
            XCTAssertEqual(viaK18.analysis.rmssd, gamla.analysis.rmssd, "HRV, natt \(k)")
            XCTAssertEqual(viaK18.analysis.restingHeartRate, gamla.analysis.restingHeartRate)
            XCTAssertEqual(viaK18.analysis.breathsPerMinute, gamla.analysis.breathsPerMinute)
            XCTAssertEqual(viaK18.analysis.cleaning, gamla.analysis.cleaning)
            XCTAssertTrue(viaK18.analysis == gamla.analysis, "analysen skiljer, natt \(k)")
            // METOD M49 · BESLUT B99. Hudformen (D2) och pulsen utanför sömnen finns bara på en natt ur K18, där lagren
            // finns; i övrigt är kurvan densamma.
            var kurvaK18: NightCurve.Curve? = viaK18.curve
            XCTAssertNotNil(kurvaK18?.profile?.skin, "natt \(k): hudformen följer med K18-natten")
            XCTAssertFalse(kurvaK18?.outside.isEmpty ?? true, "natt \(k): pulsen utanför sömnen följer med K18-natten")
            kurvaK18?.profile?.skin = nil
            kurvaK18?.outside = []
            XCTAssertTrue(kurvaK18 == gamla.curve, "kurvan skiljer, natt \(k)")
            XCTAssertEqual(viaK18.landscape, gamla.landscape)
            XCTAssertEqual(viaK18.poincare, gamla.poincare)
            XCTAssertTrue(viaK18.poincarePairs == gamla.poincarePairs)
            XCTAssertEqual(viaK18.pulse, gamla.pulse)
            XCTAssertEqual(viaK18.wakeDay, gamla.wakeDay)
        }
    }

    func testHudtemperaturenÄrOverSömnperiodenViaK18ochStillaMinuterViaGamla() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let series = K18Series(records: n.records)
        let p = try sleep(n, series)
        let viaK18 = K18Night.analyze(series, sleep: p, utcOffsetSeconds: n.utcOffsetSeconds)
        let gamla = NightResult.fromNotifications(old(n, p), k18: series, utcOffsetSeconds: n.utcOffsetSeconds)
        XCTAssertEqual(viaK18.skin?.basis, .sleepPeriod)
        XCTAssertEqual(gamla.skin?.basis, .recording)
        XCTAssertNotNil(viaK18.skin?.celsius)
        XCTAssertNotNil(viaK18.coverage)
        XCTAssertNil(gamla.coverage)
        // Utan K18 bredvid en gammal inspelning finns ingen temperatur.
        XCTAssertNil(NightResult.fromNotifications(old(n, p), utcOffsetSeconds: 0).skin)
    }

    // MARK: Avvikelser som beror på K18:s form

    func testFormenSkiljerSigLiteMenInteMer() throws {
        // 2A37 i 1/1024 s och med radions ankomsttid (0–0,3 s) mot K18 i hela
        // millisekunder och hela sekunder. Storleken skrivs i METOD M28.
        var fel: [String] = []
        for k in [0, 1, 2] {
            let n = DemoK18Nights.night(daysBeforeLast: k, shortGaps: false)
            let series = K18Series(records: n.records)
            let p = try sleep(n, series)
            let viaK18 = K18Night.analyze(series, sleep: p, utcOffsetSeconds: n.utcOffsetSeconds)
            let gamla = NightResult.fromNotifications(old(n, p, form: .units1024, jitter: 0.3), k18: series,
                                                      utcOffsetSeconds: n.utcOffsetSeconds)
            let hrv = diff(viaK18.analysis.rmssd.mean, gamla.analysis.rmssd.mean)
            let whoopLike = diff(viaK18.analysis.rmssd.whoopLike, gamla.analysis.rmssd.whoopLike)
            let vilo = diff(viaK18.analysis.restingHeartRate, gamla.analysis.restingHeartRate)
            let andning = diff(viaK18.analysis.breathsPerMinute, gamla.analysis.breathsPerMinute)
            let kasserade = abs(viaK18.analysis.cleaning.fractionDropped - gamla.analysis.cleaning.fractionDropped)
            let luckor = abs(viaK18.analysis.cleaning.omitted - gamla.analysis.cleaning.omitted)
            let rad = "M28 natt \(k): RMSSD \(hrv ?? -1) ms, whoop-lik \(whoopLike ?? -1) ms, vilopuls \(vilo ?? -1), "
                + "andning \(andning ?? -1), kastade \(kasserade), utelämnade \(luckor) av "
                + "\(viaK18.analysis.cleaning.omitted); RMSSD \(viaK18.analysis.rmssd.mean ?? -1)"
            print(rad)
            if (hrv ?? 99) > 1.5 { fel.append("HRV " + rad) }
            if (whoopLike ?? 99) > 1.5 { fel.append("whoop-lik " + rad) }
            if (vilo ?? 99) > 1 { fel.append("vilopuls " + rad) }
            if (andning ?? 99) > 1.5 { fel.append("andning " + rad) }
        }
        XCTAssertEqual(fel, [])
    }

    func testHögstFyraRRPerSekundOchInteFlerIDemoNätterna() {
        for k in [0, 1, 2, 3] {
            let n = DemoK18Nights.night(daysBeforeLast: k)
            XCTAssertLessThanOrEqual(n.records.map { $0.rr.count }.max() ?? 0, 4)
            XCTAssertLessThanOrEqual(n.beats.map { $0.count }.max() ?? 0, 4, "inga slag förloras av gränsen")
        }
    }

    // MARK: Glapp

    func testEnSaknadSekundÄrEnSekundUtanRR() {
        let base = 1_760_000_040
        let recs: [K18Record] = (1...10).map { rec(base + $0, rr: [1000]) }
            + (15...20).map { rec(base + $0, rr: [1000]) }
        let series = K18Series(records: recs)
        let r = K18Beats.recording(series, onset: base, wake: base + 100)
        XCTAssertEqual(r.samples.count, 20, "16 poster och fyra saknade sekunder")
        XCTAssertEqual(r.samples.filter { $0.bpm == 0 && $0.rrMilliseconds.isEmpty }.count, 4)

        let beats = RRCleaning.clean(r)
        XCTAssertEqual(beats.count, 16)
        let gap = beats.enumerated().filter { $0.element.gapBefore }.map { $0.offset }
        XCTAssertTrue(gap.contains(10), "första slaget efter hålet har ett glapp före sig: \(gap)")
        XCTAssertTrue(gap.allSatisfy { $0 >= 10 }, "inget glapp i den obrutna delen: \(gap)")
        XCTAssertGreaterThanOrEqual(beats[10].omittedBefore, 3)
        XCTAssertLessThanOrEqual(beats[10].omittedBefore, 4)
        // Ingen skillnad över hålet, och paren i Poincarémolnet saknar det också.
        let diffs = RRCleaning.differences(beats)
        XCTAssertFalse(diffs.contains { $0.time == beats[10].time })
        XCTAssertFalse(Poincare.pairs(beats).contains { $0.time == beats[10].time })
        XCTAssertEqual(beats.filter { $0.omittedBefore > 0 }.map { $0.omittedBefore }.reduce(0, +),
                       beats[10].omittedBefore, "luckan räknas en gång")
    }

    func testOUnbrutenFöljdGerInga() {
        let base = 1_760_000_040
        let recs: [K18Record] = (1...120).map { rec(base + $0, rr: [1000]) }
        let r = K18Beats.recording(K18Series(records: recs), onset: base, wake: base + 1000)
        XCTAssertEqual(r.samples.count, 120)
        let beats = RRCleaning.clean(r)
        XCTAssertEqual(beats.count, 120)
        XCTAssertFalse(beats.contains { $0.gapBefore })
        XCTAssertEqual(beats.reduce(0) { $0 + $1.omittedBefore }, 0)
    }

    func testGlappÖverEnMinutDelarNattenSomFörut() {
        let base = 1_760_000_040
        let recs: [K18Record] = (1...30).map { rec(base + $0, rr: [1000]) }
            + (100...130).map { rec(base + $0, rr: [1000]) }
        let r = K18Beats.recording(K18Series(records: recs), onset: base, wake: base + 1000)
        XCTAssertEqual(r.samples.count, 61, "70 sekunder är över gränsen: inga platshållare")
        let beats = RRCleaning.clean(r)
        XCTAssertEqual(Set(beats.map { $0.segment }).count, 2)
        XCTAssertFalse(RRCleaning.differences(beats).contains { $0.time == beats[30].time })
    }

    func testKortaGlappIEnNattGerGlappFöreFörstaSlagetEfter() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: true)
        let series = K18Series(records: n.records)
        let p = try sleep(n, series)
        let viaK18 = K18Night.analyze(series, sleep: p, utcOffsetSeconds: n.utcOffsetSeconds)
        let recording = K18Beats.recording(series, onset: p.onset, wake: p.wake)

        // Hålen i posterna inom perioden: mellan 2 och 60 sekunder.
        var efter: [Int] = []
        for (a, b) in zip(n.records, n.records.dropFirst()) {
            if b.time - a.time > 1, b.time - a.time <= 60, b.time > p.onset, b.time < p.wake { efter.append(b.time) }
        }
        XCTAssertEqual(efter.count, 2, "6 och 25 sekunder")
        for t in efter {
            let idx = try XCTUnwrap(recording.samples.firstIndex { Int($0.time.timeIntervalSince1970) == t })
            let first = try XCTUnwrap(viaK18.beats.first { $0.notification >= idx })
            XCTAssertTrue(first.gapBefore, "glapp före första slaget efter hålet vid \(t)")
            XCTAssertFalse(RRCleaning.differences(viaK18.beats).contains { $0.time == first.time })
        }
        // Det långa hålet (3–7 minuter) är ett eget avsnitt.
        XCTAssertGreaterThanOrEqual(viaK18.analysis.cleaning.segments, 2)

        // Samma natt utan platshållarna: hålen syns inte lika väl.
        let naiv = NightRecording(samples: recording.samples.filter { $0.bpm > 0 })
        let utanPlatshållare = RRCleaning.clean(naiv)
        let medGlapp = viaK18.beats.filter { $0.gapBefore }.count
        let utanGlapp = utanPlatshållare.filter { $0.gapBefore }.count
        let utanAnalys = NightAnalysis.analyze(beats: utanPlatshållare)
        print("M28 korta glapp: glapp före slag \(medGlapp) med platshållare, \(utanGlapp) utan; "
              + "utelämnade \(viaK18.analysis.cleaning.omitted) mot \(utanAnalys.cleaning.omitted); "
              + "RMSSD \(viaK18.analysis.rmssd.mean ?? -1) mot \(utanAnalys.rmssd.mean ?? -1)")
        // Platshållarna ändrar var glappet märks (rätt slag, inte ett senare), inte hur mycket.
        XCTAssertLessThanOrEqual(abs(medGlapp - utanGlapp), 4)
        XCTAssertEqual(try XCTUnwrap(viaK18.analysis.rmssd.mean), try XCTUnwrap(utanAnalys.rmssd.mean), accuracy: 0.5)
    }

    // MARK: Natten är sömnperioden

    func testUtanSömnperiodFinnsIngenNatt() {
        let base = 1_760_000_040
        // Tolv timmar i rörelse med RR: ingen period, alltså ingen natt.
        let recs: [K18Record] = DemoSleep.records(start: base, phases: [.active(seconds: 12 * 3600)], seed: 3)
            .map { (r: K18Record) -> K18Record in
                var x = r
                x.rr = [1000]
                return x
            }
        let day = WakeDay(Date(timeIntervalSince1970: Double(base + 6 * 3600)), utcOffsetSeconds: 0)
        XCTAssertNil(K18Night.analyze(K18Series(records: recs), wakeDay: day,
                                      startOffsetSeconds: 0, endOffsetSeconds: 0))
        XCTAssertNil(K18Night.analyze(K18Series(records: []), wakeDay: day,
                                      startOffsetSeconds: 0, endOffsetSeconds: 0))
    }

    func testNattenUrEnUppvakningsdag() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 3)
        let series = K18Series(records: n.records)
        let day = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let r = try XCTUnwrap(K18Night.analyze(series, wakeDay: day, startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        XCTAssertEqual(r.source, .k18)
        XCTAssertEqual(r.wakeDay, day)
        XCTAssertNotNil(r.sleep)
        XCTAssertGreaterThan(r.analysis.validWindows, 40)
        // Dagen före har ingen K18 i fönstret: ingen natt.
        XCTAssertNil(K18Night.analyze(series, wakeDay: day - 1, startOffsetSeconds: n.utcOffsetSeconds,
                                      endOffsetSeconds: n.utcOffsetSeconds))
        // Slagen ligger inom perioden.
        let first = try XCTUnwrap(r.analysis.start)
        let last = try XCTUnwrap(r.analysis.end)
        let p = try XCTUnwrap(r.sleep)
        XCTAssertGreaterThanOrEqual(first.timeIntervalSince1970, Double(p.onset) - 3)
        XCTAssertLessThanOrEqual(last.timeIntervalSince1970, Double(p.wake) + 3)
    }

    // MARK: Källan och pulsen

    func testKällanBärsOchGårAttSpara() throws {
        struct Rad: Codable, Equatable { var source: NightSource }
        XCTAssertEqual(NightSource.k18.rawValue, "K18")
        XCTAssertEqual(NightSource.notification.rawValue, "2A37")
        for s in [NightSource.k18, .notification] {
            let data = try JSONEncoder().encode(Rad(source: s))
            XCTAssertEqual(try JSONDecoder().decode(Rad.self, from: data), Rad(source: s))
        }
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(Rad(source: .k18)), as: UTF8.self).contains("K18"))
    }

    func testPulsenPerMinutÄrMedianenAvI14OchKräverEnHalvMinut() {
        let base = 1_760_000_040 // en minutgräns
        func r(_ t: Int, _ pulse: Int) -> K18Record {
            K18Record(time: t, pulse: pulse, rr: [], gravity: .init(x: 0, y: 0, z: 1),
                      skinTemperature: 33, bandTemperature: 30)
        }
        var recs: [K18Record] = []
        for s in 0..<60 { recs.append(r(base + s, s < 20 ? 70 : 52)) } // minut 0: median 52
        for s in 0..<29 { recs.append(r(base + 60 + s, 50) ) }         // minut 1: för få
        for s in 0..<60 { recs.append(r(base + 120 + s, s == 5 ? 0 : 48)) } // minut 2: nollor räknas inte
        let rec = K18Beats.recording(K18Series(records: recs), onset: base, wake: base + 1000)
        let m = K18Beats.pulsePerMinute(rec)
        XCTAssertEqual(m.map { $0.minute }, [base / 60, base / 60 + 2])
        XCTAssertEqual(m[0].bpm, 52)
        XCTAssertEqual(m[0].seconds, 60)
        XCTAssertEqual(m[1].bpm, 48)
        XCTAssertEqual(m[1].seconds, 59)
    }
}
