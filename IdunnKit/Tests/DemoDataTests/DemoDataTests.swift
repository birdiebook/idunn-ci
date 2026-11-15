import Foundation
import XCTest
@testable import DemoData
import HeartRate
import Night
import WhoopFrames
import WhoopImport

// Förhandsvisningens påhittade data (BESLUT B20) ska se ut som en vanlig natt
// och en vanlig export för appens egen räkning — annars visar bilderna inget.
// Här provas formen, inga exakta värden.

final class DemoDataTests: XCTestCase {

    func testVäggklockanOchZonen() {
        XCTAssertEqual(DemoWhoop.wall(DemoNights.lastWakeDayUTC - 7200), "2026-10-11 00:00:00")
        XCTAssertEqual(DemoWhoop.wall(951_782_400 - 7200 + 3_723), "2000-02-29 01:02:03")
        XCTAssertEqual(DemoWhoop.zoneText(7200), "UTC+02:00")
        XCTAssertEqual(DemoWhoop.zoneText(-16_200), "UTC-04:30")
        XCTAssertEqual(DemoWhoop.f1(14.649), "14.6")
        XCTAssertEqual(DemoWhoop.f1(-0.25), "-0.3")
    }

    func testSammaSeedGerSammaNatt() {
        // Innehållet, inte byten: JSONEncoder lägger fälten i olika ordning på Linux.
        let a = RecordingLog.decode(DemoNights.night(daysBeforeLast: 2).log)
        XCTAssertEqual(a, RecordingLog.decode(DemoNights.night(daysBeforeLast: 2).log))
        XCTAssertNotEqual(a, RecordingLog.decode(DemoNights.night(daysBeforeLast: 3).log))
        XCTAssertEqual(DemoWhoop.files().cycles, DemoWhoop.files().cycles)
    }

    func testExportenGårGenomTolkningen() {
        let e = DemoWhoop.export()
        XCTAssertEqual(e.cycles.count, 151, "150 dygn och det pågående")
        XCTAssertNil(e.cycles.last?.end, "det pågående dygnet saknar sluttid")
        let medHRV = e.cycles.compactMap(\.hrv)
        XCTAssertEqual(medHRV.count, 146, "fyra nätter utan band")
        XCTAssertGreaterThan(medHRV.min() ?? 0, 20)
        XCTAssertLessThan(medHRV.max() ?? 999, 120)
        XCTAssertTrue(e.sleeps.contains { $0.isNap })
        // Varje dygn slutar där nästa börjar (exportens form).
        for (a, b) in zip(e.cycles, e.cycles.dropFirst()) {
            XCTAssertEqual(a.end, b.start)
        }
        // Trenderna och morgonkortet får värden för alla Whoop-mått.
        let v = Trends.whoopValues(cycles: e.cycles, sleeps: e.sleeps)
        XCTAssertGreaterThanOrEqual(v[.hrv]?.count ?? 0, 90)
        XCTAssertGreaterThanOrEqual(v[.sleep]?.count ?? 0, 90)
        XCTAssertGreaterThanOrEqual(v[.regularity]?.count ?? 0, 60)
        XCTAssertEqual(v[.hrv]?.keys.max(), WakeDay(Date(timeIntervalSince1970: DemoNights.lastWakeDayUTC + 43_200),
                                                    utcOffsetSeconds: 0))
    }

    func testNattenSerUtSomEnNatt() throws {
        let start = Date()
        let n = DemoNights.night(daysBeforeLast: 0)
        let contents = RecordingLog.decode(n.log)
        let natt = contents.recording
        XCTAssertEqual(contents.utcOffsetSeconds, 7200)
        XCTAssertEqual(contents.skippedLines, 0)
        XCTAssertNotNil(natt.batteryAtStart)
        XCTAssertNotNil(natt.batteryAtEnd)
        let genererad = Date().timeIntervalSince(start)

        let q = RecordingQuality.report(natt)
        XCTAssertTrue(q.passes, "en vanlig natt duger")
        XCTAssertEqual(q.gaps?.count, 1, "ett glapp")

        let t1 = Date()
        let slag = RRCleaning.clean(natt)
        let a = NightAnalysis.analyze(beats: slag)
        let curve = NightCurve.make(night: natt, beats: slag, analysis: a)
        let räknad = Date().timeIntervalSince(t1)
        print("DemoData: natten genererad på \(genererad) s, räknad på \(räknad) s")

        XCTAssertGreaterThan(a.cleaning.fractionOmitted, 0, "bandet hoppar över slag")
        XCTAssertGreaterThanOrEqual(a.validWindows, Trends.minValidWindows)
        let rmssd = try XCTUnwrap(a.rmssd.mean)
        XCTAssertTrue((20...80).contains(rmssd), "RMSSD \(rmssd)")
        let puls = try XCTUnwrap(a.restingHeartRate)
        XCTAssertTrue((40...60).contains(puls), "vilopuls \(puls)")
        let andning = try XCTUnwrap(a.breathsPerMinute)
        XCTAssertTrue((11...18).contains(andning), "andning \(andning)")
        let c = try XCTUnwrap(curve)
        XCTAssertNotNil(c.nadir)
        XCTAssertNotNil(c.fall)
        XCTAssertEqual(c.gaps.count, 1)
        XCTAssertNotNil(c.profile)
    }

    func testNätternaSlutarPåSinaMorgnar() {
        let nätter = DemoNights.nights(count: 3)
        XCTAssertEqual(nätter.count, 3)
        for (k, n) in nätter.reversed().enumerated() {
            let dag = WakeDay(n.end, utcOffsetSeconds: DemoNights.utcOffsetSeconds)
            let väntad = WakeDay(Date(timeIntervalSince1970: DemoNights.lastWakeDayUTC - Double(k) * 86_400 + 43_200),
                                 utcOffsetSeconds: 0)
            XCTAssertEqual(dag, väntad)
            XCTAssertLessThan(n.start, n.end)
        }
    }

    // MARK: Hudtemperaturen (METOD M25)

    func testDemonattenHarHudtemperaturOchEnNattUnderMinstaTäckningHarInte() throws {
        let bra = DemoNights.night(daysBeforeLast: 0)
        let a = SkinTemperature.night(K18Series(records: bra.k18), from: bra.start, to: bra.end)
        let hud = try XCTUnwrap(a.celsius)
        XCTAssertTrue((32.8...34.2).contains(hud), "hud \(hud)")
        let täckning = try XCTUnwrap(a.coverage)
        XCTAssertTrue((0.85...0.92).contains(täckning), "täckning \(täckning)")
        XCTAssertGreaterThan(a.stillMinutes, 200)

        // Var sjunde natt täcks bara första tredjedelen: ingen temperatur.
        let kort = DemoNights.night(daysBeforeLast: 3)
        let b = SkinTemperature.night(K18Series(records: kort.k18), from: kort.start, to: kort.end)
        XCTAssertNil(b.celsius)
        let kortTäckning = try XCTUnwrap(b.coverage)
        XCTAssertTrue((0.25...0.32).contains(kortTäckning), "täckning \(kortTäckning)")
    }

    func testIdunnsHudtempLiggerUnderWhoopsOchSaknasPåNätterUnderMinstaTäckning() throws {
        let nätter = DemoNights.nights(count: 40)
        let idun: [Trends.IdunNight] = nätter.map { (n: DemoNights.Night) -> Trends.IdunNight in
            let hud = SkinTemperature.night(K18Series(records: n.k18), from: n.start, to: n.end)
            return Trends.IdunNight(day: WakeDay(n.end, utcOffsetSeconds: DemoNights.utcOffsetSeconds),
                                    validWindows: 90, rmssd: 55, restingHeartRate: 50, breathsPerMinute: 14,
                                    skinTemperature: hud.celsius)
        }
        let värden = Trends.idunValues(idun)
        // Sex av de 40 nätterna (k = 3, 10, …, 38) täcks för lite.
        XCTAssertEqual(värden[.skinTemperature]?.count, 34)
        XCTAssertEqual(värden[.hrv]?.count, 40)

        let e = DemoWhoop.export()
        let whoop = Trends.whoopValues(cycles: e.cycles, sleeps: e.sleeps)
        let nivå = try XCTUnwrap(Baseline.levelOffset(idun: värden[.skinTemperature] ?? [:],
                                                      whoop: whoop[.skinTemperature] ?? [:]))
        XCTAssertTrue((-1.0 ... -0.3).contains(nivå), "nivåskillnad \(nivå) °C")

        // Kortet får sin rad ur Idunns senaste natt, med avvikelsen mot området.
        let rader = MorningCard.rows(idun: värden, whoop: whoop)
        let rad = try XCTUnwrap(rader.first { $0.measure == .skinTemperature })
        XCTAssertEqual(rad.source, .idun)
        XCTAssertNotNil(rad.range)
        XCTAssertNotNil(rad.deviation)
    }

    func testDemoSleepGerEnRimligNattSomSömnmetodenHittar() throws {
        // METOD M26. Nätterna är påhittade med känd insomning och uppvaknande.
        let start = 1_760_000_040
        for seed in [1, 2, 3, 4, 5] as [UInt64] {
            let natt = DemoSleep.plausibleNight(start: start, seed: seed)
            let series = K18Series(records: natt.records)
            // En post per sekund, utan dubbletter.
            XCTAssertEqual(series.records.count, natt.records.count)
            XCTAssertEqual(series.duplicates, 0)
            let from = Date(timeIntervalSince1970: Double(start - 600))
            let to = Date(timeIntervalSince1970: Double((natt.records.last?.time ?? start) + 600))
            let p = try XCTUnwrap(SleepDetection.detect(series, from: from, to: to), "seed \(seed)")
            XCTAssertEqual(Double(p.onset), Double(natt.onset), accuracy: 180, "seed \(seed)")
            XCTAssertEqual(Double(p.wake), Double(natt.wake), accuracy: 180, "seed \(seed)")
            XCTAssertEqual(p.wakeBouts.count, 1, "en orolig stund, seed \(seed)")
            XCTAssertEqual(p.gapSeconds, 0)
        }
    }

    func testDemoSleepÄrDeterministiskOchTillåterGlapp() {
        let faser: [DemoSleep.Phase] = [.still(seconds: 20), .gap(seconds: 10), .still(seconds: 5)]
        let a = DemoSleep.records(start: 1_760_000_040, phases: faser, seed: 4)
        let b = DemoSleep.records(start: 1_760_000_040, phases: faser, seed: 4)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 25)
        XCTAssertEqual(a[19].time, 1_760_000_059)
        XCTAssertEqual(a[20].time, 1_760_000_070, "glappet hoppar över tio sekunder")
        // Gravitationen är en enhetsvektor.
        XCTAssertTrue(a.allSatisfy { abs($0.gravity.length - 1) < 1e-9 })
    }

    func testDemoK18NätterHarSamtligaSlagBådaVägarna() throws {
        // METOD M28. Samma slag som K18-poster och som 2A37-mätningar.
        let n = DemoK18Nights.night(daysBeforeLast: 1)
        XCTAssertEqual(n, DemoK18Nights.night(daysBeforeLast: 1), "samma seed ger samma natt")
        XCTAssertNotEqual(n, DemoK18Nights.night(daysBeforeLast: 2))
        XCTAssertEqual(n.records.count, n.beats.count)
        let m = n.measurements(.wholeMilliseconds)
        XCTAssertEqual(m.count, n.records.count)
        for (r, x) in zip(n.records, m) {
            XCTAssertEqual(x.measurement.rrMilliseconds, r.rr.map { Double($0) })
            XCTAssertEqual(x.measurement.bpm, r.pulse)
            XCTAssertEqual(x.time.timeIntervalSince1970, Double(r.time))
        }
        // RR finns bara under sömnen, och minst ett RR i de flesta sekunder.
        let medRR = n.records.filter { !$0.rr.isEmpty }
        XCTAssertTrue(medRR.allSatisfy { $0.time > n.onset - 2 && $0.time <= n.wake + 1 })
        XCTAssertGreaterThan(Double(medRR.count) / Double(n.wake - n.onset), 0.6)
        // I 1/1024 s avviker varje slag högst en millisekund från K18:s.
        for (r, x) in zip(n.records, n.measurements(.units1024)) {
            for (a, b) in zip(r.rr, x.measurement.rrMilliseconds) { XCTAssertEqual(Double(a), b, accuracy: 1.0) }
        }
        // Gravitationen är sömnmetodens: perioden hittas nära facit.
        let series = K18Series(records: n.records)
        let day = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let w = SleepDetection.dayWindow(wakeDay: day, startOffsetSeconds: n.utcOffsetSeconds,
                                         endOffsetSeconds: n.utcOffsetSeconds)
        let p = try XCTUnwrap(SleepDetection.detect(series, from: w.from, to: w.to))
        XCTAssertEqual(Double(p.onset), Double(n.onset), accuracy: 400)
        XCTAssertEqual(Double(p.wake), Double(n.wake), accuracy: 400)
        // Utan korta glapp är posterna ett glapp kortare per natt.
        let utan = DemoK18Nights.night(daysBeforeLast: 1, shortGaps: false)
        XCTAssertGreaterThan(utan.records.count, 0)
        XCTAssertEqual(DemoK18Nights.nights(count: 3).count, 3)
    }

    /// METOD M37 · BESLUT B46. Provets senaste natt (`stages: true`) ger vaken, lätt, djup och REM, och
    /// ett djupt spann minst 20 min efter insomningen, där provets markör står (kanten vid insomningen, M37).
    func testDemonattenMedStadierHarAllaFyraOchDjupEfterInsomningen() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, movementBout: true, stages: true)
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let r = try XCTUnwrap(K18Night.analyze(K18Series(records: n.records), wakeDay: dag,
                                               startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        let lager = try XCTUnwrap(r.layers)
        let stadier: Set<SleepStage> = Set(lager.stages.map { (s: NightLayers.StageSpan) -> SleepStage in s.stage })
        XCTAssertEqual(stadier, Set(SleepStage.allCases), "vaken, lätt, djup och REM")
        let start: Double = try XCTUnwrap(lager.stages.map { (s: NightLayers.StageSpan) -> Double in s.start }.min())
        XCTAssertTrue(lager.stages.contains { (s: NightLayers.StageSpan) -> Bool in
            s.stage == .deep && s.start - start >= 1_200
        }, "ett djupt spann minst 20 min efter insomningen")
    }

    /// BESLUT B99. Pulsen utanför sömnen: bandets puls per minut före axelns början och efter dess slut, ur
    /// demonattens vakna stunder före insomningen och efter uppvaknandet; ingen efter slutet när bandet togs av vid
    /// uppvaknandet.
    func testPulsenUtanförSömnenKommerUrBandetsPulsOchSaknasNärBandetÄrAv() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0)
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        func natt(_ poster: [K18Record]) throws -> (kurva: NightCurve.Curve, lager: NightLayers.Layers) {
            let r = try XCTUnwrap(K18Night.analyze(K18Series(records: poster), wakeDay: dag,
                                                   startOffsetSeconds: n.utcOffsetSeconds,
                                                   endOffsetSeconds: n.utcOffsetSeconds))
            return (try XCTUnwrap(r.curve), try XCTUnwrap(r.layers))
        }
        let hel = try natt(n.records)
        let före = hel.kurva.outside.filter { (m: NightCurve.Minute) -> Bool in m.mid < hel.lager.start }
        let efter = hel.kurva.outside.filter { (m: NightCurve.Minute) -> Bool in m.mid > hel.lager.end }
        XCTAssertGreaterThan(före.count, 5, "demonattens vakna stund före insomningen")
        XCTAssertGreaterThan(efter.count, 5, "demonattens vakna stund efter uppvaknandet")
        // Pulsen utanför är bandets puls minut för minut, inte ett fast tal: demonattens vakna puls rör sig.
        let tal: Set<Int> = Set(före.compactMap { (m: NightCurve.Minute) -> Int? in m.heartRate.map { Int($0.rounded()) } })
        XCTAssertGreaterThan(tal.count, 3, "pulsen före insomningen följer bandets puls")
        XCTAssertTrue(hel.kurva.outside.allSatisfy { (m: NightCurve.Minute) -> Bool in
            (m.heartRate ?? 0) > 0 && m.start >= hel.lager.start - K18Night.outsideSeconds - 60
                && m.start < hel.lager.end + K18Night.outsideSeconds
        })
        // Bandet av vid axelns slut: inga poster efter, ingen puls efter.
        let slut: TimeInterval = hel.lager.end
        let av = try natt(n.records.filter { (r: K18Record) -> Bool in Double(r.time) < slut })
        XCTAssertTrue(av.kurva.outside.allSatisfy { (m: NightCurve.Minute) -> Bool in m.start < slut })
        XCTAssertFalse(av.kurva.outside.isEmpty, "före insomningen finns pulsen kvar")
    }
}

// BESLUT B30 · METOD M27. Lyssnarens påhittade notiser ska läsas av
// ListenerStatus som riktiga: K18 per minut, ett glapp och en synk.
final class DemoListenerTests: XCTestCase {
    func testNotisernaGerStatusMedGlappOchSynk() {
        // En natt 18–06 (720 min) i +02:00 med glapp 25–50 %.
        let start = Date(timeIntervalSince1970: 1_791_907_200)   // 2026-10-13 18:00 +02:00
        let slut = start.addingTimeInterval(12 * 3600)
        let synk = slut.addingTimeInterval(120)
        let noter = DemoListener.notifications(start: start, end: slut, gap: 0.25...0.5, syncAt: synk)
        let s = ListenerStatus.read(noter)
        XCTAssertEqual(s.lastSync, synk)
        XCTAssertEqual(s.badChecksums, 0)
        let w = NightWindow.Window(start: start, end: slut, until: slut)
        let c = s.coverage(w)
        XCTAssertEqual(c?.totalMinutes, 720)
        // 180 minuter (25–50 %) saknas; gränsminuterna 0,25 och 0,5 ingår i luckan.
        XCTAssertEqual(c?.coveredMinutes, 720 - 181)
    }
}

// METOD M28 · BESLUT B30. Påhittade K18-poster som hela ramar: samma byteordning
// som K18Record.decode läser, så att proven av appens väg (dygnsfiler → natt)
// går genom riktig ihopfogning och avkodning.
final class DemoK18FramesTests: XCTestCase {
    func testPostenKommerTillbakaUrRamen() throws {
        let r = K18Record(time: 1_791_900_000, pulse: 57, rr: [1040, 1062, 980],
                          gravity: .init(x: 0.25, y: -0.5, z: 0.75),
                          skinTemperature: 32.64, bandTemperature: 29.7)
        let inre = DemoK18Frames.inner(r)
        XCTAssertEqual(inre.count, 112)
        let tillbaka = try XCTUnwrap(K18Record.decode(inner: inre))
        XCTAssertEqual(tillbaka, r, "värden som ryms exakt i f32 och i hundradelar kommer tillbaka lika")

        let s = K18Series(notifications: [DemoK18Frames.notification(r, heard: 1_791_900_001)])
        XCTAssertEqual(s.records, [r])
        XCTAssertEqual(s.badChecksums, 0)
    }

    func testHögstFyraRRMedOchEnRamHörsEfteråt() throws {
        let r = K18Record(time: 1_791_900_000, pulse: 60, rr: [800, 810, 820, 830, 840],
                          gravity: .init(x: 0, y: 0, z: 1), skinTemperature: 33, bandTemperature: 30)
        let s = K18Series(notifications: DemoK18Frames.notifications([r], delay: 7200))
        XCTAssertEqual(s.records.first?.rr, [800, 810, 820, 830])
        XCTAssertEqual(s.records.first?.time, 1_791_900_000, "bandets tid, inte den tid ramen hördes")
    }

    func testDygnsfilenLäsesSomNotiserna() {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let noter = DemoK18Frames.notifications(Array(n.records.prefix(300)))
        let fil = DemoK18Frames.log(noter)
        let (tillbaka, hoppade) = RawFrameLog.decode(fil)
        XCTAssertEqual(hoppade, 0)
        XCTAssertEqual(tillbaka, noter)
        XCTAssertEqual(K18Series(notifications: tillbaka).records.count, 300)
    }
}

// METOD M42 · BESLUT B51. Minuter i rörelse i förhandsvisningens påhittade nätter, och de äldre nätterna som ger
// de K18-bara måtten sitt normalområde. Formen provas, inga exakta värden.
final class DemoRorelseTests: XCTestCase {

    func testNätterUtanRörelseavsnittÄrOförändradeOchFörvaltFyraMinuter() {
        let räknade: [DemoK18Nights.Night] = DemoK18Nights.nights(count: 3)
        let enskilda: [DemoK18Nights.Night] = [2, 1, 0].map { (k: Int) -> DemoK18Nights.Night in
            DemoK18Nights.night(daysBeforeLast: k)
        }
        XCTAssertEqual(räknade, enskilda, "movementBouts är av som förut")
        XCTAssertEqual(DemoK18Nights.night(daysBeforeLast: 0, movementBout: true),
                       DemoK18Nights.night(daysBeforeLast: 0, movementBout: true, boutMinutes: 4),
                       "förvalt fyra minuter, som provets senaste natt")
    }

    func testRörelseavsnittetsLängdÄrFrånEttTillTolvOchVarierar() {
        var längder: Set<Int> = []
        var summa: Int = 0
        for k in 0..<40 {
            let m: Int = DemoK18Nights.boutMinutes(daysBeforeLast: k)
            XCTAssertTrue((1...12).contains(m), "natt \(k): \(m)")
            XCTAssertEqual(m, DemoK18Nights.boutMinutes(daysBeforeLast: k), "samma seed ger samma längd")
            längder.insert(m)
            summa += m
        }
        XCTAssertGreaterThanOrEqual(längder.count, 5, "längderna varierar: \(längder.sorted())")
        let medel: Double = Double(summa) / 40
        XCTAssertTrue(medel > 4.5 && medel < 7.5, "kring sex: \(medel)")
    }

    func testEttLängreRörelseavsnittGerEnLängreNattMedSammaStart() {
        let a = DemoK18Nights.night(daysBeforeLast: 4, movementBout: true, boutMinutes: 4)
        let b = DemoK18Nights.night(daysBeforeLast: 4, movementBout: true, boutMinutes: 9)
        XCTAssertEqual(a.onset, b.onset)
        XCTAssertEqual(b.wake - b.onset, a.wake - a.onset + 5 * 60, "fem minuter till")
    }

    func testNätterMedRörelseavsnittHarMinutIRörelseSomAvsnittetLängd() throws {
        let nätter: [DemoK18Nights.Night] = DemoK18Nights.nights(count: 6, movementBouts: true)
        for k in [1, 3] {
            let n: DemoK18Nights.Night = nätter[nätter.count - 1 - k]
            let längd: Int = DemoK18Nights.boutMinutes(daysBeforeLast: k)
            let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
            let r = try XCTUnwrap(K18Night.analyze(K18Series(records: n.records), wakeDay: dag,
                                                   startOffsetSeconds: n.utcOffsetSeconds,
                                                   endOffsetSeconds: n.utcOffsetSeconds))
            let tal: Int = try XCTUnwrap(r.movementMinutes, "natt \(k)")
            // Avsnittet på N minuter har N − 1 eller N hela minuter, och en eller två delar av minuter som
            // också ligger över gränsen; vändningar och orolig sömn ger minutmedel under gränsen (M32). Perioden
            // hittas på några minuter när (rullande median över fem minuter, M26), så uppe-minuter vid kanten
            // kan ge några till; det som skiljer en natt från en uppe-period är att talet inte blir tiotals.
            XCTAssertGreaterThanOrEqual(tal, längd - 1, "natt \(k): avsnitt på \(längd) min gav \(tal)")
            XCTAssertLessThanOrEqual(tal, längd + 10, "natt \(k): avsnitt på \(längd) min gav \(tal)")
        }
    }

    func testDeÄldreNätternaGerEttBandPerMåttOchÄrDeterministiska() {
        let a: [DemoHistory.Night] = DemoHistory.nights(daysBeforeLast: 14..<40)
        XCTAssertEqual(a.count, 26)
        XCTAssertEqual(a, DemoHistory.nights(daysBeforeLast: 14..<40), "samma seed ger samma nätter")
        XCTAssertEqual(a.first?.daysBeforeLast, 39, "äldst först")
        XCTAssertEqual(a.last?.daysBeforeLast, 14)
        XCTAssertNotEqual(DemoHistory.night(daysBeforeLast: 20), DemoHistory.night(daysBeforeLast: 21))
        let längder: Set<Int> = Set(a.map { (n: DemoHistory.Night) -> Int in n.movementMinutes })
        XCTAssertGreaterThan(längder.count, 4, "rörelsen varierar")
        for n in a {
            XCTAssertTrue((1...14).contains(n.movementMinutes), "rörelse \(n.movementMinutes)")
            XCTAssertTrue(n.meanHeartRate > 45 && n.meanHeartRate < 65, "medelpuls \(n.meanHeartRate)")
            XCTAssertTrue(n.sleepMinutes > 250 && n.sleepMinutes < 480, "sömn \(n.sleepMinutes)")
            XCTAssertGreaterThan(Double(n.wake - n.onset), n.sleepMinutes * 60, "vakna stunder ligger i perioden")
            // Natten slutar på sin morgon i telefonens zon.
            let midnatt: Int = Int(DemoNights.lastWakeDayUTC) - n.daysBeforeLast * 86_400 - DemoNights.utcOffsetSeconds
            XCTAssertLessThan(n.onset, midnatt, "insomning på kvällen")
            XCTAssertGreaterThan(n.wake, midnatt, "uppvaknande efter midnatt")
        }
    }
}
