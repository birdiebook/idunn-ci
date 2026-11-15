// PROVET GÅR APPENS VÄG (BESLUT B52, PLAN.md E1 och K1) — i simulatorn, utan telefon och utan TestFlight.
//
// Förut ritade IdunnProv vyerna ur objekt provet själv byggt (`NightReport.make`, `K18Night.analyze`): grönt
// även när appen, som läser filer, gjorde fel. Natten 12→13 oktober visade i bygge 9 en natt utan lager fast
// provet var grönt, just därför. Här skrivs de påhittade nätterna (`DemoData`) som FILER i appens mapp i
// simulatorn (`NightFiles.folder`), appens egen laddning räknar dem (`K18Nights.computeDue`, `NightSummary.load`,
// `Recorder.chosen`, `NightLoader.bundle`), och vyerna ritas ur det laddningen gav. Riktig hälsodata får aldrig
// in här — CLAUDE.md §Dataregeln. Filerna städas bort efteråt.
//
// BILDERNA (prefixet `vag-`; IdunnProvs egna bilder är kvar som de var, för jämförelsen):
// · `vag-morgon` — Morgon för natten som räknades ur dygnsfiler (nätter från och med 13→14 skrivs så).
// · `vag-natten` — samma natts kurva med lagren, ur filerna.
// · `vag-trend` — trendvyn (BESLUT B82) ur laddningens nätter.
// · `vag-overgang` — ÖVERGÅNGSNATTEN (K1): en gammal inspelning vars `.t2.jsonl` bär K18 för natten, utan
//   dygnsfiler. Kurvan har lagren; i bygge 9 hade den inga. `vag-overgang-morgon` är dess Morgon.
// · `morgon-utan-lager` (E3) — en natt ur K18 vars filer saknas: kurvan går inte att räkna fram, och Morgon säger det.
//
// VAD SOM GÅR GENOM FILERNA OCH VAD SOM INTE GÖR (kostnaden, BESLUT B52): en natt ur K18 kostar ungefär 15 s att
// räkna i ett Debug-bygge i simulatorn, så bara två gör det: den senaste (dygnsfiler) och natten före (övergången).
// De äldre dagarna är gamla inspelningar (bara pulsfilen, som före A2) och deras K18-bara tal (medelpuls, sömn,
// minuter i rörelse, hudtemperatur) läggs på ur `DemoHistory` som i IdunnProv (METOD M42), så att normalområdena
// finns. Allt det laddningen ger för de två nätterna, och för alla gamla inspelningar, kommer ur filer.

import XCTest
import SwiftUI
import UIKit
import AVFoundation
import DemoData
import HeartRate
import Night
import Sound
import WhoopFrames
@testable import Idunn

@MainActor
final class IdunnProvVag: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393
    /// Lika många dagar som i IdunnProv, så att bilderna går att jämföra.
    static let antalNätter = 40

    /// Det laddningen gav, och det vyerna ritas ur.
    struct Vag {
        /// Nätterna som appen ser dem, senaste först (`Recorder.chosen`): K18-nätterna ur `natt-*.k18.json` och
        /// de gamla inspelningarna ur sina filer.
        var summaries: [NightSummary]
        /// Idunns nätter för vyerna: de laddade, och de äldre dagarnas K18-bara tal ur `DemoHistory`.
        var idun: [Trends.IdunNight]
        /// Natten ur dygnsfilerna, och övergångsnatten dagen före.
        var senasteDag: WakeDay
        var övergångsDag: WakeDay
        /// Kurvan och lagren ur filerna för de två K18-nätterna (`NightLoader.bundle`, det Nattens kurva öppnar med).
        var bundles: [WakeDay: NightLoader.CurveBundle]
        /// Inspelningens egen sammanfattning för övergångsdagen: den gamla natten som K18 gick före.
        var gammalÖvergång: NightSummary?
        /// BESLUT B52. Senaste nattens filer raderades och kurvan gick då inte längre att räkna fram: sant om
        /// `NightChoice.lacksLayers` säger det, som Morgon frågar.
        var senasteUtanLager: Bool
        /// METOD M44 · BESLUT B54. Ljudfilens stam för senaste natten (ligger i appens ljudmapp under provet).
        var ljudStam: String
    }

    static var vag: Vag?
    /// Gick laddningen sönder (eller hoppades över) görs den inte om för varje bild: det tar minuter.
    static var vagFel: Error?

    // MARK: Filerna

    /// En natt som lyssnaren skriver den: notiserna fördelade på dygnsfiler efter datumet de hördes.
    private func skrivDygn(_ n: DemoK18Nights.Night) {
        var perDag: [String: [RawFrame]] = [:]
        for x in DemoK18Frames.notifications(n.records) {
            perDag[DayLog.stem(for: x.time, utcOffsetSeconds: n.utcOffsetSeconds), default: []].append(x)
        }
        for (stem, notiser) in perDag {
            NightFiles.write(RecordingLog.header(utcOffsetSeconds: n.utcOffsetSeconds), to: NightFiles.pulse(stem))
            NightFiles.write(DemoK18Frames.log(notiser), to: NightFiles.frames(stem))
        }
    }

    /// En natt som spelades in före dygnsfilerna (K1): pulsen i `<start>.jsonl` (så att inspelningen är en natt
    /// som kan tävla med K18) och bandets K18 i `<start>.t2.jsonl`, inga dygnsfiler. Namnet är starten i UTC,
    /// som appen skriver det. Ger namnet.
    private func skrivÖvergång(_ n: DemoK18Nights.Night) -> String {
        let stam: String = RecordingStem.stem(for: Date(timeIntervalSince1970: Double(n.records[0].time) - 90))
        var puls: Data = RecordingLog.header(utcOffsetSeconds: n.utcOffsetSeconds)
        puls.append(RecordingLog.batteryAtStart(95))
        var sist: Date = Date(timeIntervalSince1970: Double(n.records[0].time))
        for m in n.measurements(.units1024, jitter: 0.6, seed: 7) {
            puls.append(RecordingLog.line(HeartRateSample(m.measurement, at: m.time)))
            sist = m.time
        }
        puls.append(RecordingLog.batteryAtEnd(88))
        puls.append(RecordingLog.stopped(at: sist))
        NightFiles.write(puls, to: NightFiles.pulse(stam))
        NightFiles.write(DemoK18Frames.log(DemoK18Frames.notifications(n.records)), to: NightFiles.frames(stam))
        return stam
    }

    /// BESLUT B54. Ett klipp som lyssnaren skriver det (AAC, 16 kHz, mono): tre sekunder lågt brus.
    private func skrivKlipp(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let inställningar: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let fil = try AVAudioFile(forWriting: url, settings: inställningar, commonFormat: .pcmFormatFloat32,
                                  interleaved: false)
        let buffert = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: fil.processingFormat, frameCapacity: 48_000))
        let kanal = try XCTUnwrap(buffert.floatChannelData)
        var slump = Seeded(3)
        for i in 0..<48_000 { kanal[0][i] = Float(0.01 * slump.gauss()) }
        buffert.frameLength = 48_000
        try fil.write(from: buffert)
    }

    /// Ljudfilerna provet skrev tas bort igen.
    private func städaLjud(stam: String) {
        let fm = FileManager.default
        try? fm.removeItem(at: SoundFiles.folder.appendingPathComponent(stam + ".ljud"))
        try? fm.removeItem(at: SoundFiles.folder.appendingPathComponent(SoundSummary.fileName(stem: stam)))
        try? fm.removeItem(at: SoundClips.url(NightSound.Clip(stem: stam, second: 0)).deletingLastPathComponent())
    }

    /// Mappen var tom när provet började (annars hade det hoppats över), så allt som ligger där är provets.
    private func städa() {
        let fm = FileManager.default
        let namn: [String] = (try? fm.contentsOfDirectory(atPath: NightFiles.folder.path)) ?? []
        for n in namn {
            try? fm.removeItem(at: NightFiles.folder.appendingPathComponent(n))
        }
    }

    // MARK: Appens laddning

    /// Räknas en gång för alla bilder.
    func vagen() throws -> Vag {
        if let v = Self.vag { return v }
        if let f = Self.vagFel { throw f }
        do {
            let v = try byggVagen()
            Self.vag = v
            return v
        } catch {
            Self.vagFel = error
            throw error
        }
    }

    /// Skriver filerna, laddar som appen gör och sparar det vyerna behöver.
    private func byggVagen() throws -> Vag {
        let t = Date()
        let fm = FileManager.default
        try NightFiles.prepareFolder()
        let finns: [String] = (try? fm.contentsOfDirectory(atPath: NightFiles.folder.path)) ?? []
        guard finns.isEmpty else {
            // Appens mapp delas med appens egna nätter i simulatorn: provet rör inte nätter som inte är dess egna.
            throw XCTSkip("appens mapp har redan \(finns.count) filer: provet går inte appens väg över någon annans nätter")
        }
        defer { städa() }

        let zon: Int = DemoNights.utcOffsetSeconds
        let senaste: DemoK18Nights.Night = DemoK18Nights.night(daysBeforeLast: 0, movementBout: true, stages: true)
        let övergång: DemoK18Nights.Night = DemoK18Nights.night(
            daysBeforeLast: 1, movementBout: true, boutMinutes: DemoK18Nights.boutMinutes(daysBeforeLast: 1),
            stages: true)
        let dag0 = WakeDay(Date(timeIntervalSince1970: Double(senaste.wake)), utcOffsetSeconds: zon)
        let dag1 = WakeDay(Date(timeIntervalSince1970: Double(övergång.wake)), utcOffsetSeconds: zon)
        XCTAssertEqual(dag1, dag0 - 1, "övergångsnatten är natten före")

        // Filerna i appens mapp, som de ligger på telefonen.
        skrivDygn(senaste)

        // METOD M44 · BESLUT B54. Ljudet till senaste natten, som lyssnaren skriver det: `ljud/<stam>.ljud` och ett
        // klipp per planterad händelse i `ljudklipp/<stam>/`. Natten före (övergången) har inget ljud.
        let ljudMapp = SoundFiles.folder
        let ljudFiler: [String] = (try? fm.contentsOfDirectory(atPath: ljudMapp.path)) ?? []
        guard ljudFiler.isEmpty else {
            throw XCTSkip("appens ljudmapp har redan \(ljudFiler.count) filer: provet rör inte någon annans ljud")
        }
        let serie = K18Series(notifications: DemoK18Frames.notifications(senaste.records))
        let natt0 = try XCTUnwrap(K18Night.analyze(serie, wakeDay: dag0, startOffsetSeconds: zon, endOffsetSeconds: zon))
        let plan = DemoSound.plan(layers: try XCTUnwrap(natt0.layers), series: serie)
        let ljudStam = SoundFile.stem(start: plan.start)
        try fm.createDirectory(at: ljudMapp, withIntermediateDirectories: true)
        try SoundFile.encode(start: plan.start, seconds: DemoSound.seconds(count: plan.count, plants: plan.plants))
            .write(to: ljudMapp.appendingPathComponent(ljudStam + ".ljud"))
        for p in plan.plants {
            try skrivKlipp(SoundClips.url(NightSound.Clip(stem: ljudStam, second: p.from)))
        }
        let övergångsStam: String = skrivÖvergång(övergång)
        XCTAssertTrue(NightFiles.dayStems().count >= 2, "dygnsfilerna för senaste natten (kvällen och morgonen)")
        // De äldre dagarna: gamla inspelningar med bara pulsfilen, som före A2. Dag 1 är övergångsnatten.
        var hud: [Int: Double] = [:]
        for k in 0..<Self.antalNätter where k != 1 {
            let n: DemoNights.Night = DemoNights.night(daysBeforeLast: k)
            NightFiles.write(n.log, to: NightFiles.pulse(NightFiles.stem(for: n.start)))
            if k >= 2 {
                // METOD M25. Hudtemperaturen som den gamla nattens K18 gav, för de äldre dagarnas tal.
                let natt: SkinTemperature.Night = SkinTemperature.night(K18Series(records: n.k18), from: n.start,
                                                                        to: n.end)
                if let c = natt.celsius { hud[k] = c }
            }
        }
        XCTAssertTrue(NightFiles.stems().contains(övergångsStam), "övergången är en inspelning i appens mapp")
        XCTAssertEqual(NightFiles.stems().count, Self.antalNätter, "en inspelning per dag, dag 1 är övergången")

        // Appens laddning: nätterna räknas ur filerna (`Recorder.computeNights`), sammanfattningarna läses
        // (`Recorder.reloadSummaries`) och valet görs (`Recorder.chosen`). Klockan står efter kl 12 på
        // uppvakningsdagen, så att natten inte är preliminär.
        let nu: Date = NightLedger.windowEnd(dag0, utcOffsetSeconds: TimeZone.current.secondsFromGMT())
            .addingTimeInterval(3 * 3600)
        XCTAssertTrue(K18Nights.computeDue(now: nu), "något räknades och sparades")
        let gamla: [NightSummary] = NightFiles.stems().compactMap(NightSummary.load)
        let k18: [NightSummary] = K18Nights.summaries()
        XCTAssertEqual(k18.count, 2, "två nätter ur K18: ur dygnsfilerna, och ur övergångens inspelning")
        let valda: [NightSummary] = Recorder.chosen(k18: k18, old: gamla)
        let nätter: [WakeDay: NightSummary] = MorningCardView.nights(valda)

        // Natten ur dygnsfilerna.
        let senasteN: NightSummary = try XCTUnwrap(nätter[dag0], "Morgon har en natt för senaste dagen")
        XCTAssertEqual(senasteN.origin, .k18)
        XCTAssertEqual(senasteN.stem, K18Nights.stem(dag0))
        XCTAssertNotEqual(senasteN.preliminary, true, "räknad efter kl 12")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(senasteN.coverage), ListenerCheck.minCoverage, "bandet hördes")

        // K1. Övergångsnatten: K18 ur inspelningens `.t2.jsonl` går före inspelningen själv.
        let gammalÖvergång: NightSummary? = gamla.first { (s: NightSummary) -> Bool in s.stem == övergångsStam }
        let gammal: NightSummary = try XCTUnwrap(gammalÖvergång, "inspelningen är också en gammal natt")
        XCTAssertEqual(gammal.origin, .notification)
        print("PROV: övergångens inspelning har \(gammal.validWindows) giltiga fönster (minst \(Trends.minValidWindows) tävlar)")
        let övergångN: NightSummary = try XCTUnwrap(nätter[dag1], "Morgon har en natt för övergångsdagen")
        XCTAssertEqual(övergångN.origin, .k18, "K18 ur inspelningen går före inspelningen själv")
        XCTAssertEqual(övergångN.stem, K18Nights.stem(dag1))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(övergångN.coverage), ListenerCheck.minCoverage, "bandet hördes")

        // Nattens kurva ur filerna, det Nattens kurva öppnar med: lagren finns för båda.
        var bundles: [WakeDay: NightLoader.CurveBundle] = [:]
        for (dag, s) in [(dag0, senasteN), (dag1, övergångN)] {
            let b: NightLoader.CurveBundle = try XCTUnwrap(NightLoader.bundle(for: s),
                                                          "kurvan går att räkna om ur filerna (\(dag))")
            let lager: NightLayers.Layers = try XCTUnwrap(b.layers, "en natt ur K18 har lager (\(dag))")
            XCTAssertTrue(lager.minutes.contains { $0.movement != nil && $0.skinTemperature != nil },
                          "rörelse och temperatur (\(dag))")
            XCTAssertFalse(lager.asleep.isEmpty, "sömnbitarna (\(dag))")
            XCTAssertFalse(NightChoice.lacksLayers(source: s.origin, layers: b.layers))
            bundles[dag] = b
        }

        // METOD M44 · BESLUT B54. Ljudet kom med genom appens väg: sammanfattningen bär det som väckte, kurvan har
        // händelserna, och natten utan ljud (övergången) har inget.
        let ljudSumma = try XCTUnwrap(senasteN.sound, "sammanfattningen för senaste natten bär ljudet")
        XCTAssertFalse(ljudSumma.wakers.isEmpty, "något väckte dig")
        XCTAssertNil(övergångN.sound, "övergångsnatten har ingen ljudfil")
        // METOD M45 · BESLUT B55. Appen skrev nattens tal för datorn bredvid .ljud-filen, och exporten tar med den.
        let sammanfattningsFil = SoundFiles.folder.appendingPathComponent(SoundSummary.fileName(stem: ljudStam))
        let sammanfattning = try XCTUnwrap(try? Data(contentsOf: sammanfattningsFil), "ljud/<stam>.sammanfattning.json")
        let tal = try XCTUnwrap(SoundSummary.decode(sammanfattning), "sammanfattningen går att läsa")
        XCTAssertGreaterThan(tal.secondsMeasured, 3_600, "sekunder med mått")
        XCTAssertEqual(tal.eventsPerClass.reduce(0, +) > 0, true, "händelser")
        XCTAssertGreaterThanOrEqual(tal.overall.awakenings, ljudSumma.wakers.count, "uppvaknandena mot kontrollerna")
        let ljudet = try XCTUnwrap(bundles[dag0]?.sound, "kurvan ur filerna har ljudet")
        XCTAssertEqual(ljudet.digest.wakers.count, ljudSumma.wakers.count, "kurvan och sammanfattningen delar uträkningen")
        XCTAssertNil(bundles[dag1]?.sound, "övergångens kurva har inget ljud")
        XCTAssertTrue(ljudet.events.contains { $0.woke && SoundClips.exists($0.clip) }, "klippet till det som väckte finns")
        print("PROV: ljud ur filer: \(ljudet.events.count) händelser, \(ljudSumma.wakers.count) väckte, "
              + "snarkning \(ljudet.snoringPerHour.map { String($0) } ?? "–") min/h")

        // De äldre dagarnas K18-bara tal (METOD M42), som i IdunnProv: samma gamla nätter ur filerna, med talen påsatta.
        let gamlaNätter: [Trends.IdunNight] = gamla.compactMap { (s: NightSummary) -> Trends.IdunNight? in s.idunNight }
        var historik: [Trends.IdunNight] = []
        for h in DemoHistory.nights(daysBeforeLast: 2..<Self.antalNätter) {
            let dag: WakeDay = dag0 - h.daysBeforeLast
            guard var natt = gamlaNätter.first(where: { (n: Trends.IdunNight) -> Bool in n.day == dag }) else { continue }
            natt.meanHeartRate = h.meanHeartRate
            natt.sleepHours = h.sleepMinutes / 60
            natt.sleepEpisode = Trends.sleepEpisode(source: .k18, start: Date(timeIntervalSince1970: Double(h.onset)),
                                                    end: Date(timeIntervalSince1970: Double(h.wake)),
                                                    utcOffsetSeconds: zon, sleepMinutes: h.sleepMinutes, coverage: 0.95)
            natt.movementMinutes = h.movementMinutes
            natt.snoringPerHour = DemoSound.snoringPerHour(daysBeforeLast: h.daysBeforeLast)
            natt.skinTemperature = hud[h.daysBeforeLast]
            natt.source = .k18
            historik.append(natt)
        }
        XCTAssertEqual(historik.count, Self.antalNätter - 2, "en äldre K18-natt per gammal natt före de två")
        let idun: [Trends.IdunNight] = valda.compactMap { (s: NightSummary) -> Trends.IdunNight? in s.idunNight } + historik

        // E3. Natten ur dygnsfilerna förlorar sina filer (rådygnet raderat utan arkiv): sammanfattningen ligger kvar,
        // men kurvan går inte att räkna om, och Morgon frågar `NightChoice.lacksLayers` som i appen.
        for stem in K18Days.stems(wakeDay: dag0, includeNext: true) {
            try? fm.removeItem(at: NightFiles.pulse(stem))
            try? fm.removeItem(at: NightFiles.frames(stem))
        }
        let efter: NightLoader.CurveBundle? = NightLoader.bundle(for: senasteN)
        XCTAssertNil(efter, "utan filer går natten inte att räkna om")
        let utanLager: Bool = NightChoice.lacksLayers(source: senasteN.origin, layers: efter?.layers)
        XCTAssertTrue(utanLager, "en natt ur K18 utan kurva saknar lager")

        let v = Vag(summaries: valda, idun: idun, senasteDag: dag0, övergångsDag: dag1, bundles: bundles,
                    gammalÖvergång: gammal, senasteUtanLager: utanLager, ljudStam: ljudStam)
        print("PROV: appens väg: \(gamla.count) gamla och \(k18.count) K18-nätter ur filer på \(Int(Date().timeIntervalSince(t))) s")
        return v
    }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    // MARK: Morgon

    func test1VagMorgon() throws {
        let v = try vagen()
        let dagar = MorningCard.days(idun: Trends.idunValues(v.idun))
        let nätter = MorningCardView.nights(v.summaries)
        let kort = try XCTUnwrap(dagar.last)
        XCTAssertEqual(kort.day, v.senasteDag, "Morgon visar natten som räknades ur dygnsfilerna")
        XCTAssertEqual(dagar.count, Self.antalNätter, "en morgon per natt")
        let natt = try XCTUnwrap(nätter[kort.day])
        XCTAssertEqual(natt.origin, .k18)
        XCTAssertTrue(kort.rows.allSatisfy { $0.source == .idun && !$0.usesWhoopHistory }, "bara Idunn")
        let rörelse = try XCTUnwrap(kort.rows.first { $0.measure == .movement }, "rörelsens rad")
        XCTAssertGreaterThan(rörelse.value, 0, "natten har minuter i rörelse")
        XCTAssertNotNil(rörelse.range, "rörelsens normalområde")
        XCTAssertTrue(kort.rows.contains { $0.measure == .sleep }, "sömnens rad ur nattens sömnperiod")
        XCTAssertNotNil(natt.deepMinutes, "djupminuterna")
        XCTAssertNotNil(natt.remMinutes, "REM-minuterna")
        try rendera(MorningCardStack(card: kort, summary: natt, bundle: v.bundles[kort.day]), namn: "vag-morgon")
    }

    // MARK: Nattens kurva

    func test2VagNatten() throws {
        let v = try vagen()
        let nätter = MorningCardView.nights(v.summaries)
        let natt = try XCTUnwrap(nätter[v.senasteDag])
        let b = try XCTUnwrap(v.bundles[v.senasteDag], "kurvan ur filerna")
        let lager = try XCTUnwrap(b.layers, "lagren ur filerna")
        XCTAssertFalse(lager.stages.isEmpty, "stadiebandet")
        let typisk = NightCurveView.typical(b.curve, stem: natt.stem, summaries: v.summaries)
        print("PROV: typisk natt \(typisk == nil ? "saknas" : "finns")")
        // METOD M44 · BESLUT B54. Ljudet ur filerna (klippen finns i appens mapp, så knapparna syns).
        let ljud = try XCTUnwrap(b.sound, "ljudet ur filerna")
        XCTAssertTrue(ljud.events.contains { $0.woke }, "något väckte")
        try rendera(CurveStack(curve: b.curve, typical: typisk, layers: lager, sound: ljud, markerad: .constant(nil)),
                    namn: "vag-natten")
    }

    // MARK: Trendvyn

    func test3VagTrend() throws {
        let v = try vagen()
        let serier = Trends.series(idun: Trends.idunValues(v.idun), whoop: [:]).filter { !$0.points.isEmpty }
        XCTAssertFalse(serier.isEmpty)
        XCTAssertTrue(serier.allSatisfy { $0.sources == [.idun] }, "bara Idunns nätter")
        let rörelse = try XCTUnwrap(serier.first { $0.measure == .movement }, "rörelsens diagram")
        XCTAssertGreaterThanOrEqual(rörelse.points.count, Self.antalNätter - 4, "en punkt per natt")
        XCTAssertFalse(rörelse.bands.isEmpty, "rörelsens normalområde")
        // Appens egen väg (`TrendsView.series`) ger de nätter laddningen räknade: de två ur K18 och de gamla.
        let appens = TrendsView.series(summaries: v.summaries)
        let appensRörelse = try XCTUnwrap(appens.first { $0.measure == .movement }, "rörelsen ur de laddade nätterna")
        XCTAssertGreaterThanOrEqual(appensRörelse.points.count, 1, "minuter i rörelse ur K18-nätterna i filerna")
        XCTAssertLessThanOrEqual(appensRörelse.points.count, 2, "bara de två K18-nätterna har minuter i rörelse ur filerna")
        try rendera(TrendStack(serier: serier, mått: .constant(.hrv), period: .constant(.month), markerad: .constant(nil)),
                    namn: "vag-trend")
    }

    // MARK: Övergångsnatten (K1)

    func test4VagOvergang() throws {
        let v = try vagen()
        let dag = v.övergångsDag
        let nätter = MorningCardView.nights(v.summaries)
        let natt = try XCTUnwrap(nätter[dag])
        XCTAssertEqual(natt.origin, .k18, "K18 ur inspelningen gäller, inte inspelningen")
        let gammal = try XCTUnwrap(v.gammalÖvergång)
        XCTAssertEqual(gammal.wakeDay, dag, "inspelningen är en gammal natt samma dag")
        let b = try XCTUnwrap(v.bundles[dag], "kurvan ur inspelningens filer")
        let lager = try XCTUnwrap(b.layers, "övergångsnatten har lager, som i bygge 9 saknades")
        XCTAssertTrue(lager.minutes.contains { $0.movement != nil && $0.skinTemperature != nil }, "rörelse och temperatur")
        let typisk = NightCurveView.typical(b.curve, stem: natt.stem, summaries: v.summaries)
        try rendera(CurveStack(curve: b.curve, typical: typisk, layers: lager, markerad: .constant(nil)),
                    namn: "vag-overgang")
        // Och Morgon för samma natt: raderna som bara en natt ur K18 har.
        let dagar = MorningCard.days(idun: Trends.idunValues(v.idun))
        let kort = try XCTUnwrap(dagar.first { $0.day == dag }, "Morgon har en morgon för övergångsdagen")
        XCTAssertTrue(kort.rows.contains { $0.measure == .sleep }, "sömn ur K18")
        XCTAssertTrue(kort.rows.contains { $0.measure == .meanHeartRate }, "medelpuls ur K18")
        try rendera(MorningCardStack(card: kort, summary: natt, bundle: b), namn: "vag-overgang-morgon")
    }

    // MARK: Morgon när natten saknar lager (E3)

    func test5MorgonUtanLager() throws {
        let v = try vagen()
        XCTAssertTrue(v.senasteUtanLager, "natten ur K18 utan filer saknar lager")
        let dagar = MorningCard.days(idun: Trends.idunValues(v.idun))
        let nätter = MorningCardView.nights(v.summaries)
        let kort = try XCTUnwrap(dagar.last)
        let natt = try XCTUnwrap(nätter[kort.day])
        XCTAssertEqual(natt.origin, .k18)

        // En fast klocka och en lyssnare som mår bra, som i IdunnProv: bara natten utan lager säger till.
        let zon = TimeZone.current.secondsFromGMT()
        let nu = DayLog.date(of: DayLog.Day(year: 2026, month: 10, day: 14), hour: 7, minute: 30,
                             utcOffsetSeconds: zon)
        let fönster = NightWindow.latest(now: nu, utcOffsetSeconds: zon)
        let bra = ListenerStatus.read(DemoListener.notifications(
            start: fönster.start, end: nu, gap: 0.55...0.65, syncAt: nu.addingTimeInterval(-20 * 60)))
        let utan: ListenerAlert? = ListenerCheck.alert(status: bra, nightCoverage: natt.coverage, bluetooth: .ok,
                                                       nightLacksLayers: v.senasteUtanLager, now: nu,
                                                       utcOffsetSeconds: zon)
        XCTAssertEqual(utan, .missingLayers)
        XCTAssertNil(ListenerCheck.alert(status: bra, nightCoverage: natt.coverage, bluetooth: .ok,
                                         nightLacksLayers: false, now: nu, utcOffsetSeconds: zon),
                     "natten med sina lager ger ingen rad")
        let text = ListenerAlertRow.text(.missingLayers, now: nu)
        XCTAssertTrue(text.contains("–"), text)
        for tekniskt in ["K18", "T2", "RR", "iagnos", "2A37", "lager"] {
            XCTAssertFalse(text.contains(tekniskt), "inget tekniskt ord utanför Data: \(text)")
        }

        try rendera(MorningCardStack(card: kort, summary: natt, alert: utan), namn: "morgon-utan-lager")
        try fånga(NavigationStack { MorningCardScreen(days: dagar, summaries: nätter, alert: utan, loadsCurves: false) },
                  namn: "skarm-morgon-utan-lager", höjd: 1_500)
        // Sista provet: ljudfilerna och klippen som provet skrev tas bort igen.
        städaLjud(stam: v.ljudStam)
    }

    // MARK: Ritningen

    /// `ImageRenderer`: innehållet i full längd, mörkt läge, @3x.
    private func rendera(_ vy: some View, namn: String) throws {
        let innehåll = vy
            .frame(width: Self.bredd)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tema.bg)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "sv_SE"))
        let r = ImageRenderer(content: innehåll)
        r.scale = 3
        r.proposedSize = ProposedViewSize(width: Self.bredd, height: nil)
        guard let bild = r.uiImage, let png = bild.pngData() else {
            XCTFail("kunde inte rita \(namn)")
            return
        }
        try skriv(png, namn: namn, storlek: bild.size, skala: bild.scale)
    }

    /// Ett riktigt fönster: navigationsrubrik och sidor som på telefonen.
    private func fånga(_ vy: some View, namn: String, höjd: CGFloat) throws {
        let vc = UIHostingController(rootView: vy
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "sv_SE")))
        let scen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let fönster: UIWindow = scen.map { UIWindow(windowScene: $0) } ?? UIWindow()
        fönster.frame = CGRect(x: 0, y: 0, width: Self.bredd, height: höjd)
        fönster.overrideUserInterfaceStyle = .dark
        fönster.rootViewController = vc
        fönster.isHidden = false
        vc.view.frame = fönster.bounds
        vc.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        vc.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let bild = UIGraphicsImageRenderer(bounds: fönster.bounds, format: format).image { _ in
            _ = fönster.drawHierarchy(in: fönster.bounds, afterScreenUpdates: true)
        }
        fönster.isHidden = true
        fönster.rootViewController = nil
        guard let png = bild.pngData() else {
            XCTFail("kunde inte fånga \(namn)")
            return
        }
        try skriv(png, namn: namn, storlek: bild.size, skala: bild.scale)
    }

    private func skriv(_ png: Data, namn: String, storlek: CGSize, skala: CGFloat) throws {
        let väg = "\(Self.ut)/\(namn).png"
        try png.write(to: URL(fileURLWithPath: väg))
        print("PROV: skrev \(väg) (\(Int(storlek.width * skala))×\(Int(storlek.height * skala)) px)")
    }
}
