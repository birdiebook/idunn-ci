// RITAR APPENS VYER TILL PNG — i simulatorn, utan telefon och utan TestFlight
// (BESLUT B20). Körs av Codemagics arbetsflöde `ios-prov` (codemagic.yaml),
// startat med `python tools/prov.py`, som hämtar bilderna till en mapp utanför repot.
//
// DATAN ÄR PÅHITTAD (`DemoData` i IdunnKit): seedade nätter slag för slag (både
// gamla inspelningar och nätter ur K18, `DemoK18Nights`), en seedad lyssnare
// (`DemoListener`) och en seedad Whoop-historik. Riktig hälsodata får aldrig
// in här — CLAUDE.md §Dataregeln. Nätterna räknas samma väg som i appen (`NightReport.make`,
// `NightSummary`, `MorningCardView.days`, `TrendsView.series`), så bilderna
// visar appens egen räkning av den påhittade datan.
//
// DE ÄLDRE DAGARNA (METOD M42): bara de senaste `antalK18` nätterna räknas ur K18, för det tar tid. Normalområdet
// kräver fyra veckors nätter, så måtten som bara en natt ur K18 har (medelpuls, minuter i rörelse) får sina
// äldre dagar ur `DemoHistory`: samma gamla nätter som förut, med de K18-bara talen påsatta (`Demo.history`).
//
// TVÅ SLAGS BILDER:
// · `ImageRenderer` (SwiftUI) ritar vyernas innehåll i full längd: Morgon (med
//   och utan felrad, utan baslinje, föregående morgon), Nattens kurva, trendvyn och delarna av nattrapporten och Nätter. Den
//   ritar inte UIKit-delar — List, ScrollView, NavigationStack, den
//   segmenterade periodväljaren — så listorna ritas här i sina delar, och
//   `*-imagerenderer.png` visar vad som blir kvar av en hel lista.
// · `skarm-*.png` fångas ur ett riktigt fönster (`drawHierarchy`), med
//   navigationsrubriken och listorna som på telefonen. Höga fönster visar
//   hela innehållet utan att rulla.
//
// VARFÖR /tmp: simulatorn delar filsystem med Mac-värden, så Codemagic hämtar
// bilderna därifrån som artefakter (samma väg som Birdiebooks ios-preview).

import XCTest
import SwiftUI
import UIKit
import DemoData
import HeartRate
import Night
import Sound
import WhoopFrames
import WhoopImport
@testable import Idunn

@MainActor
final class IdunnProv: XCTestCase {

    static let ut = "/tmp/idun_prov"
    /// iPhone 15/16/17 Pro: 393 × 852 punkter.
    static let bredd: CGFloat = 393
    static let skärmhöjd: CGFloat = 852
    /// Idunns nätter: fler än baslinjens fem veckor, så att normalområdet syns.
    static let antalNätter = 40

    /// Nätter ur K18 (A2): fler än en vecka, så att kortet och trenderna blandar
    /// dem med de gamla inspelningarna. De sista dagarna har båda; K18 går före.
    static let antalK18 = 14

    struct Demo {
        var reports: [NightReport]
        /// Alla Idunns nätter, K18 och gamla, senaste först (som `Recorder.summaries`).
        var summaries: [NightSummary]
        /// Bara de gamla inspelningarna (2A37), senaste först.
        var oldSummaries: [NightSummary]
        /// Bara nätterna ur K18, senaste först.
        var k18Summaries: [NightSummary]
        /// Hela resultatet för den senaste K18-natten (kurvan, Poincarémolnet).
        var latestK18: NightResult
        var export: WhoopExport
        var latest: NightReport
        /// METOD M42. De gamla nätterna äldre än K18-nätterna, som K18-nätter med medelpuls, sömn och minuter i
        /// rörelse ur `DemoHistory`: det som ger de K18-bara måtten normalområde.
        var history: [Trends.IdunNight]
        /// BESLUT B63 (D2). Kurvan och lagren för varje K18-natt, som appen laddar dem (`NightLoader.CurveBundle`), för
        /// Morgons och Nattens kurva. Ljudet bara på den senaste natten.
        var bundles: [WakeDay: NightLoader.CurveBundle]
        /// METOD M51 (D2). Påhittade sammanfattade nätter för dagarna före de räknade, så att trendvyn har ett halvår.
        var halvår: [Trends.IdunNight]
    }

    /// Hela halvåret för trendvyn: de räknade nätterna, de äldre K18-bara talen och de sammanfattade nätterna.
    static let halvårDagar = 182

    func idunHalvår(_ d: Demo) -> [Trends.IdunNight] {
        idunNätter(d) + d.halvår
    }

    /// Kurvan och lagren som appen laddar dem, ur ett resultat.
    static func paket(_ r: NightResult) -> NightLoader.CurveBundle? {
        r.curve.map { (c: NightCurve.Curve) -> NightLoader.CurveBundle in
            NightLoader.CurveBundle(curve: c, layers: r.layers, sound: r.sound)
        }
    }

    /// Idunns nätter som Morgon och trendvyn ser dem: de räknade (K18 och gamla) och de äldre dagarnas K18-bara tal.
    func idunNätter(_ d: Demo) -> [Trends.IdunNight] {
        d.summaries.compactMap(\.idunNight) + d.history
    }

    /// Räknas en gång för alla bilder.
    static var demo: Demo?

    func data() throws -> Demo { try Self.laddaDemo() }

    static func laddaDemo() throws -> Demo {
        if let d = Self.demo { return d }
        let t = Date()
        let nätter = DemoNights.nights(count: Self.antalNätter)
        let reports: [NightReport] = nätter.map { (n: DemoNights.Night) -> NightReport in
            // METOD M25. K18 kommer påhittad ur DemoData, utan ramar.
            NightReport.make(stem: NightFiles.stem(for: n.start), contents: RecordingLog.decode(n.log), frames: [],
                             k18: K18Series(records: n.k18))
        }
        // Senaste först, som `Recorder.summaries`.
        let gamla: [NightSummary] = reports.map { (r: NightReport) -> NightSummary in NightSummary(r) }.reversed()

        // METOD M28. Nätter ur K18, räknade som appen räknar dem: sömnperioden
        // ur rörelsen och slagen ur posterna (`K18Night.analyze`).
        var resultat: [NightResult] = []
        // METOD M32. Den senaste natten har fyra minuter med armen i rörelse och
        // inga slag: kurvan visar då ett glapp med rörelse som orsak, bredvid
        // glappet utan bandets data.
        // METOD M37. Slagen följer ett påhittat hypnogram (`stages: true`), så att
        // stadiemodellen ger vaken, lätt, djup och REM.
        // METOD M42. Varje natt har ett avsnitt med armen i rörelse av olika längd (minuter i rörelse).
        var påhittade: [DemoK18Nights.Night] = DemoK18Nights.nights(count: Self.antalK18, stages: true,
                                                                    movementBouts: true)
        påhittade[påhittade.count - 1] = DemoK18Nights.night(daysBeforeLast: 0, movementBout: true, stages: true)
        for n in påhittade {
            let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
            let r = K18Night.analyze(K18Series(records: n.records), wakeDay: dag,
                                     startOffsetSeconds: n.utcOffsetSeconds, endOffsetSeconds: n.utcOffsetSeconds)
            resultat.append(try XCTUnwrap(r, "varje påhittad K18-natt har en sömnperiod"))
        }
        // METOD M44 · BESLUT B54. Ljud till den senaste natten: en påhittad ljudfil (snarkning, trafik före en vaken
        // stund, dörr, hosta, djur och tal) går genom samma analys som på telefonen (`NightSoundMaker`). De påhittade
        // K18-nätterna saknar andningsvåg i slagen, så analysen kan inte skilja din snarkning från någon annans:
        // ägarna och snarkminuterna per timme sätts för hand (`DemoSound.withDemoOwners`), allt annat är analysens.
        let sistaNatt = påhittade[påhittade.count - 1]
        let sistaSerie = K18Series(records: sistaNatt.records)
        let sistaLager = try XCTUnwrap(resultat[resultat.count - 1].layers)
        let ljudPlan = DemoSound.plan(layers: sistaLager, series: sistaSerie)
        let ljudKälla = NightSoundMaker.Source(
            stem: SoundFile.stem(start: ljudPlan.start), start: ljudPlan.start,
            seconds: DemoSound.seconds(count: ljudPlan.count, plants: ljudPlan.plants))
        let analyserat = try XCTUnwrap(
            NightSoundMaker.make(sources: [ljudKälla], series: sistaSerie, layers: sistaLager), "ljudet gav en natt")
        resultat[resultat.count - 1].sound = DemoSound.withDemoOwners(analyserat, snoringPerHour: 14)

        var k18: [NightSummary] = []
        for (i, r) in resultat.enumerated() {
            let dag = try XCTUnwrap(r.wakeDay)
            var digest = NightDigest(r)
            // De äldre nätterna har ett påhittat ljud i tal (en natt av nio saknar det).
            if digest.sound == nil { digest.sound = DemoSound.digest(daysBeforeLast: resultat.count - 1 - i) }
            k18.append(NightSummary(digest: digest, stem: K18Nights.stem(dag), build: "prov"))
        }
        k18.reverse()
        // METOD M42. De gamla nätterna före K18-nätterna får K18-nätternas tal ur DemoHistory.
        let sistaDag: WakeDay = try XCTUnwrap(resultat.last?.wakeDay)
        let gamlaNätter: [Trends.IdunNight] = gamla.compactMap { (s: NightSummary) -> Trends.IdunNight? in s.idunNight }
        var historik: [Trends.IdunNight] = []
        for h in DemoHistory.nights(daysBeforeLast: Self.antalK18..<Self.antalNätter) {
            let dag: WakeDay = sistaDag - h.daysBeforeLast
            guard var natt = gamlaNätter.first(where: { (n: Trends.IdunNight) -> Bool in n.day == dag }) else { continue }
            DemoHistory.apply(h, to: &natt)
            natt.snoringPerHour = DemoSound.snoringPerHour(daysBeforeLast: h.daysBeforeLast)
            historik.append(natt)
        }
        XCTAssertEqual(historik.count, Self.antalNätter - Self.antalK18, "en äldre K18-natt per gammal natt")
        let alla: [NightSummary] = (k18 + gamla).sorted { (a: NightSummary, b: NightSummary) -> Bool in
            (a.titleDate ?? .distantPast) > (b.titleDate ?? .distantPast)
        }
        // BESLUT B63. Kurvan och lagren för varje K18-natt; ljudet ligger bara på den senaste.
        var paket: [WakeDay: NightLoader.CurveBundle] = [:]
        for r in resultat {
            if let dag = r.wakeDay, let b = Self.paket(r) { paket[dag] = b }
        }
        let halvår: [Trends.IdunNight] = DemoHistory.summaryNights(daysBeforeLast: Self.antalNätter..<Self.halvårDagar)
        let d = Demo(reports: reports, summaries: alla, oldSummaries: gamla, k18Summaries: k18,
                     latestK18: try XCTUnwrap(resultat.last), export: DemoWhoop.export(),
                     latest: try XCTUnwrap(reports.last), history: historik, bundles: paket, halvår: halvår)
        print("PROV: \(reports.count) gamla och \(resultat.count) K18-nätter räknade på \(Int(Date().timeIntervalSince(t))) s")
        Self.demo = d
        return d
    }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    // MARK: Morgon

    func test1Morgon() throws {
        let d = try data()
        // BESLUT B40. Morgnarna ur Idunns nätter, utan Whoop. METOD M42: de äldre dagarna har K18-bara tal ur
        // DemoHistory, så att medelpuls och minuter i rörelse har sitt normalområde som de andra måtten.
        let dagar = MorningCard.days(idun: Trends.idunValues(idunNätter(d)))
        let kort = try XCTUnwrap(dagar.last)
        let natt = kort.day
        let rader = kort.rows
        let nätter = MorningCardView.nights(d.summaries)
        XCTAssertEqual(dagar.count, Self.antalNätter, "en morgon per natt")
        XCTAssertEqual(rader.count, MorningCard.measures.count, "en rad per mått")
        XCTAssertTrue(rader.allSatisfy { $0.source == .idun && !$0.usesWhoopHistory }, "bara Idunn")
        XCTAssertTrue(rader.contains { $0.range != nil }, "normalområdet syns")
        XCTAssertNil(kort.baselineBuilding, "40 nätter: området finns, ingen byggrad")
        // METOD M25. Hudtemperaturen: Idunns natt och avvikelsen mot området, som
        // bara Idunns egna nätter bygger.
        let hud = try XCTUnwrap(rader.first { $0.measure == .skinTemperature }, "hudtemperaturens rad")
        XCTAssertNotNil(hud.deviation, "avvikelsen mot normalområdet")
        XCTAssertEqual(d.oldSummaries.filter { $0.skinTemperature == nil }.count, 6,
                       "sex gamla nätter är under minsta K18-täckning och har ingen temperatur")
        // METOD M26 · METOD M28. Idunns sömntid är ett mått på kortet, ur K18-natten.
        XCTAssertTrue(rader.contains { $0.measure == .sleep }, "sömnens rad")
        // BESLUT B34 · BESLUT B46. Medelpulsen är ett eget mått på kortet, med ett normalområde som de andra.
        let medelpuls = try XCTUnwrap(rader.first { $0.measure == .meanHeartRate }, "medelpulsens rad")
        XCTAssertNotNil(medelpuls.range, "medelpulsens normalområde (DemoHistory ger de äldre dagarna)")
        // METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden: en rad med eget normalområde.
        let rörelse = try XCTUnwrap(rader.first { $0.measure == .movement }, "rörelsens rad")
        XCTAssertNotNil(rörelse.range, "rörelsens normalområde")
        XCTAssertGreaterThan(rörelse.value, 0, "senaste natten har minuter i rörelse")
        XCTAssertNotNil(nätter[natt]?.movementMinutes, "sammanfattningen bär minuterna")
        XCTAssertTrue(d.oldSummaries.allSatisfy { $0.movementMinutes == nil }, "en gammal inspelning har inga")
        // METOD M33. Regelbundenheten ur Idunns sömnperioder (K18-nätterna i rad).
        let sri = try XCTUnwrap(rader.first { $0.measure == .regularity }, "regelbundenhetens rad")
        print("PROV: regelbundenhet \(sri.value) ur \(Self.antalK18) K18-nätter")
        // K18 går före en gammal inspelning samma dag.
        let senaste = try XCTUnwrap(nätter[natt])
        XCTAssertEqual(senaste.origin, .k18)
        // METOD M44 · BESLUT B54. Ljudet på Morgon: det som väckte dig, och en snarkrad bara när natten ligger
        // utanför ditt normalområde. Senaste natten har båda; raden ligger utanför kortets ordinarie mått.
        let ljudSumma = try XCTUnwrap(senaste.sound, "senaste natten har ljud")
        XCTAssertFalse(ljudSumma.wakers.isEmpty, "något väckte dig")
        let snarkrad = try XCTUnwrap(kort.snoring, "14 min/h ligger över området")
        XCTAssertEqual(snarkrad.value, 14, accuracy: 1e-9)
        XCTAssertNotNil(snarkrad.range, "ditt normalområde")
        XCTAssertFalse(rader.contains { $0.measure == .snoring }, "snarkraden hör inte till de ordinarie raderna")
        // BESLUT B46. Senaste natten har djup- och REM-minuter till sömnraden.
        XCTAssertNotNil(senaste.deepMinutes, "djupminuterna")
        XCTAssertNotNil(senaste.remMinutes, "REM-minuterna")

        // METOD M33. Baslinjen byggs: bara de 5 senaste nätterna (färre än 7, BESLUT B69), så området saknas
        // och kortet säger hur långt baslinjen kommit.
        let nyaste = d.summaries.filter { (s: NightSummary) -> Bool in
            (s.wakeDay ?? WakeDay(daysSince1970: 0)) > natt - 5
        }
        let ung = MorningCardView.days(summaries: nyaste)
        let ungKort = try XCTUnwrap(ung.last)
        let byggs = try XCTUnwrap(ungKort.baselineBuilding, "området saknas: byggraden syns")
        print("PROV: baslinjen byggs \(byggs) av \(Baseline.minNightsForRange)")
        XCTAssertTrue(ungKort.rows.allSatisfy { $0.range == nil }, "värdena utan band")
        XCTAssertTrue(ungKort.rows.allSatisfy { $0.status == nil }, "inget läge innan området finns")

        // Svepet: föregående morgon är nattens kort dagen före.
        let föregående = try XCTUnwrap(dagar.dropLast().last)
        XCTAssertEqual(föregående.day, natt - 1)
        XCTAssertNotNil(nätter[föregående.day], "den natten har sin kurva")

        // METOD M29. Morgon utan fel och med: felraden syns bara när något är fel.
        let nu = Date()
        let tyst = ListenerAlert.silent(since: nu.addingTimeInterval(-9 * 3600))
        let paket: NightLoader.CurveBundle? = d.bundles[natt]
        XCTAssertNotNil(paket, "senaste natten har kurva och lager")
        try rendera(MorningCardStack(card: kort, summary: senaste, bundle: paket), namn: "morgon")
        try rendera(MorningCardStack(card: kort, summary: senaste, bundle: paket, alert: tyst), namn: "morgon-fel")
        // En natt utan ljud visar ingen ljudrad, och nattens kort är i övrigt som förut.
        let utanLjudDag = natt - 4
        let utanLjudKort = try XCTUnwrap(dagar.first { $0.day == utanLjudDag }, "morgonen en natt utan ljud")
        let utanLjudNatt = try XCTUnwrap(nätter[utanLjudDag])
        XCTAssertNil(utanLjudNatt.sound, "natten har inget ljud")
        XCTAssertNil(utanLjudKort.snoring)
        try rendera(MorningCardStack(card: utanLjudKort, summary: utanLjudNatt, bundle: d.bundles[utanLjudDag]),
                    namn: "morgon-utan-ljud")
        try rendera(MorningCardStack(card: ungKort, summary: nätter[ungKort.day], bundle: d.bundles[ungKort.day]),
                    namn: "morgon-utan-baslinje")
        try rendera(MorningCardStack(card: föregående, summary: nätter[föregående.day],
                                     bundle: d.bundles[föregående.day]), namn: "morgon-foregaende")
        // BESLUT B63. Skärmbilderna: kurvorna är redan räknade (`bundles`), så sidorna räknar inget själva.
        // BESLUT B82. Överst "‹ Idag ›" och uppe till höger bandet: anslutet med 72 %, utan känt batteri och inte
        // anslutet (felraden), och inte anslutet med 15 %.
        XCTAssertEqual(MorningCard.step(dagar.map(\.day), from: kort.day, by: -1), föregående.day, "‹ går till föregående morgon")
        XCTAssertNil(MorningCard.step(dagar.map(\.day), from: kort.day, by: 1), "› finns inte på senaste morgonen")
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: nätter, bundles: d.bundles, loadsCurves: false,
                              band: Bandstatus(batteri: 72, ansluten: true), idag: natt)
        }, namn: "skarm-morgon", höjd: 1_500)
        // BESLUT B125. Dagens dag är dagen efter den senaste natten: Idag är en tom sida med stegen och hur långt de
        // kommit, och gårdagen ligger ett steg bakåt. Klockslaget är påhittat.
        let dataTill: Date = Calendar.current.date(bySettingHour: 6, minute: 40, second: 0, of: nu) ?? nu
        let väntar = Morgonläge.nu(ansluten: true, hämtar: true, räknar: false, dataTill: dataTill, hämtatTill: nil)
        let räknar = Morgonläge.nu(ansluten: true, hämtar: false, räknar: true, dataTill: dataTill, hämtatTill: nil)
        let ingen = Morgonläge.nu(ansluten: true, hämtar: false, räknar: false, dataTill: dataTill, hämtatTill: nil)
        XCTAssertEqual([väntar.band, väntar.hämtar, väntar.räknar], [.klart, .pågår, .väntar])
        XCTAssertEqual([räknar.band, räknar.hämtar, räknar.räknar], [.klart, .klart, .pågår])
        XCTAssertEqual([ingen.band, ingen.hämtar, ingen.räknar], [.klart, .klart, .väntar])
        XCTAssertEqual(Morgonläge.nu(ansluten: false, hämtar: false, räknar: false, dataTill: nil,
                                     hämtatTill: nil).band, .pågår)
        XCTAssertEqual(väntar.hämtarText, "Hämtar natten från bandet · data till 06:40")
        XCTAssertFalse(väntar.ingenNatt)
        XCTAssertFalse(räknar.ingenNatt)
        XCTAssertTrue(ingen.ingenNatt)
        XCTAssertEqual(ingen.ingenNattText, "Ingen natt för idag än")
        XCTAssertEqual(ingen.hämtarText, "Hämtat från bandet · data till 06:40")
        XCTAssertEqual(Morgonläge.nu(ansluten: true, hämtar: false, räknar: false, dataTill: nil,
                                     hämtatTill: nil).ingenNattText, "Ingen natt för idag än")
        // BESLUT B149. Inget pågår och ingen natt: varför. Påhittade minuter: data 18–00:28 och från 08:55, och ett kort
        // glapp på 10 minuter som inte räknas.
        let kväll: Date = Calendar.current.date(byAdding: .day, value: -1,
                                                to: Calendar.current.startOfDay(for: nu)) ?? nu
        let fönster: Date = kväll.addingTimeInterval(12 * 3600)
        let m0: Int = Int(kväll.timeIntervalSince1970 / 60)
        var minuter: Set<Int> = Set((m0 + 18 * 60)..<(m0 + 24 * 60 + 29))
        minuter.subtract((m0 + 20 * 60)..<(m0 + 20 * 60 + 10))
        minuter.formUnion((m0 + 32 * 60 + 55)...(m0 + 32 * 60 + 56))
        let slutet: Date = kväll.addingTimeInterval(32 * 3600 + 57 * 60)
        let hål: ClosedRange<Date>? = Morgonläge.lucka(minuter: minuter, från: fönster, nu: slutet)
        XCTAssertEqual(hål.map { Fmt.clock(date: $0.lowerBound) + "–" + Fmt.clock(date: $0.upperBound) }, "00:29–08:55",
                       "den längsta luckan i natten, inte det korta glappet")
        let hel: Set<Int> = minuter.union((m0 + 24 * 60)...(m0 + 32 * 60 + 56))
        XCTAssertNil(Morgonläge.lucka(minuter: hel, från: fönster, nu: slutet), "en hel natt har ingen lucka")
        let saknas = Morgonläge.nu(ansluten: true, hämtar: false, räknar: false, dataTill: dataTill, hämtatTill: nil,
                                   lucka: hål)
        XCTAssertEqual(saknas.rubrik, "Natten saknas")
        XCTAssertEqual(saknas.brödtext, "Bandet var inte anslutet 00:29–08:55, så natten går inte att räkna.")
        XCTAssertEqual(ingen.rubrik, "Ingen sömn hittad")
        XCTAssertEqual(Morgonläge.nu(ansluten: true, hämtar: false, räknar: false, dataTill: nil, hämtatTill: nil).rubrik,
                       "Ingen data från bandet")
        for (läge, namn) in [(väntar, "skarm-morgon-vantar"), (räknar, "skarm-morgon-raknar"),
                             (ingen, "skarm-morgon-ingen-natt"), (saknas, "skarm-morgon-lucka")] {
            try fånga(NavigationStack {
                MorningCardScreen(days: dagar, summaries: nätter, bundles: d.bundles, loadsCurves: false,
                                  band: Bandstatus(batteri: 72, ansluten: true), idag: natt + 1, läge: läge)
            }, namn: namn, höjd: 1_500)
        }
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: nätter, alert: tyst, bundles: d.bundles, loadsCurves: false,
                              band: .okänd)
        }, namn: "skarm-morgon-fel", höjd: 1_500)
        // BESLUT B123. Lågt batteri: ansluten med 14 %, och brickan med batteriet i rött.
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: nätter, bundles: d.bundles, loadsCurves: false,
                              band: Bandstatus(batteri: 14, ansluten: true))
        }, namn: "skarm-morgon-batteri-lagt", höjd: 1_500)
        try fånga(NavigationStack {
            MorningCardScreen(days: ung, summaries: nätter, bundles: d.bundles, loadsCurves: false,
                              band: Bandstatus(batteri: 15, ansluten: false))
        }, namn: "skarm-morgon-utan-baslinje", höjd: 1_500)
        // Föregående morgon, som efter ‹ eller ett svep åt höger (och som en natt öppnad ur trendvyn): datumet i mitten.
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: nätter, start: föregående.day, showsData: false,
                              bundles: d.bundles, loadsCurves: false)
        }, namn: "skarm-morgon-foregaende", höjd: 1_500)
        // Ingen natt än, och bandet har aldrig hörts: felraden över tomt läge.
        try fånga(NavigationStack { MorningCardScreen(days: [], alert: .neverHeard) },
                  namn: "skarm-morgon-tom-fel")
        // BESLUT B63. Platserna för spåret H med påhittade huvudtal (bara här): samma layout ifylld.
        let huvud: Huvudtal = Self.påhittadeHuvudtal(slut: natt)
        try rendera(MorningCardStack(card: kort, summary: senaste, bundle: paket, huvudtal: huvud),
                    namn: "morgon-huvudtal")
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: nätter, bundles: d.bundles, huvudtal: huvud, loadsCurves: false)
        }, namn: "skarm-morgon-huvudtal", höjd: 1_500)

        // BESLUT B46. En natt utan stadier (en gammal inspelning, eller en natt vars stadier inte gick att räkna):
        // sömnraden står utan raden med djup och REM. Samma natt, bara sammanfattningen utan stadierna.
        var utanStadier = senaste
        utanStadier.lightMinutes = nil
        utanStadier.deepMinutes = nil
        utanStadier.remMinutes = nil
        XCTAssertNotNil(utanStadier.sleepMinutes, "sömntiden står kvar")
        XCTAssertNotNil(utanStadier.movementMinutes, "rörelsen står kvar")
        var nätterUtanStadier = nätter
        nätterUtanStadier[natt] = utanStadier
        // Utan stadier saknar nattens lager stadiebandet: kurvan står ensam.
        var paketUtanStadier: NightLoader.CurveBundle? = paket
        paketUtanStadier?.layers?.stages = []
        var paketen: [WakeDay: NightLoader.CurveBundle] = d.bundles
        paketen[natt] = paketUtanStadier
        try rendera(MorningCardStack(card: kort, summary: utanStadier, bundle: paketUtanStadier),
                    namn: "morgon-utan-stadier")
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: nätterUtanStadier, bundles: paketen, loadsCurves: false)
        }, namn: "skarm-morgon-utan-stadier", höjd: 1_500)

        // METOD M42 · BESLUT B51. En natt utan K18, bara de gamla inspelningarna: raderna som bara en natt ur
        // K18 har (medelpuls, sömn, minuter i rörelse, regelbundenhet) saknas, och de andra står med sina band.
        let gamla: [Trends.IdunNight] = d.oldSummaries.compactMap { (s: NightSummary) -> Trends.IdunNight? in s.idunNight }
        let utanK18 = MorningCard.day(natt, idun: Trends.idunValues(gamla))
        let måttUtanK18: [Trends.Measure] = utanK18.rows.map { (r: MorningCard.Row) -> Trends.Measure in r.measure }
        XCTAssertFalse(måttUtanK18.contains(.movement), "ingen rörelserad utan K18")
        XCTAssertFalse(måttUtanK18.contains(.meanHeartRate), "ingen medelpuls utan K18")
        XCTAssertFalse(måttUtanK18.contains(.sleep), "ingen sömnrad utan K18")
        XCTAssertTrue(måttUtanK18.contains(.hrv), "HRV står kvar")
        XCTAssertTrue(utanK18.rows.contains { $0.range != nil }, "med sitt normalområde")
        let gammalNatt = try XCTUnwrap(d.oldSummaries.first)
        // En gammal inspelning har en kurva men inga lager (inga stadier, ingen rörelse).
        let gammalKurva: NightLoader.CurveBundle? = d.latest.curve.map { (c: NightCurve.Curve) -> NightLoader.CurveBundle in
            NightLoader.CurveBundle(curve: c, layers: nil)
        }
        try rendera(MorningCardStack(card: utanK18, summary: gammalNatt, bundle: gammalKurva), namn: "morgon-utan-k18")
        var gammalaPaket: [WakeDay: NightLoader.CurveBundle] = [:]
        if let g = gammalKurva { gammalaPaket[natt] = g }
        try fånga(NavigationStack {
            MorningCardScreen(days: [utanK18], summaries: [natt: gammalNatt], bundles: gammalaPaket, loadsCurves: false)
        }, namn: "skarm-morgon-utan-k18", höjd: 1_500)
    }

    func test1bFelradensTexter() {
        let nu = DayLog.date(of: DayLog.Day(year: 2026, month: 10, day: 14), hour: 7, minute: 30,
                             utcOffsetSeconds: TimeZone.current.secondsFromGMT())
        let sedan = nu.addingTimeInterval(-(9 * 3600 + 16 * 60))
        let alla: [ListenerAlert] = [.bluetoothNotAllowed, .bluetoothOff, .neverHeard, .silent(since: sedan),
                                     .lowCoverage(fraction: 0.41), .missingLayers]
        for a in alla {
            let t = ListenerAlertRow.text(a, now: nu)
            XCTAssertTrue(t.contains("–"), t)
            for tekniskt in ["K18", "T2", "RR", "iagnos", "2A37"] {
                XCTAssertFalse(t.contains(tekniskt), "inget tekniskt ord utanför Data: \(t)")
            }
        }
        XCTAssertTrue(ListenerAlertRow.text(.silent(since: sedan), now: nu).contains(":"), "klockslaget")
        XCTAssertTrue(ListenerAlertRow.text(.lowCoverage(fraction: 0.41), now: nu).contains("41 %"))
        // BESLUT B52. Natten saknar lager: raden säger vad som saknas med vardagsord.
        XCTAssertTrue(ListenerAlertRow.text(.missingLayers, now: nu).contains("natten"))
    }

    // MARK: Nattens kurva

    func test2NattensKurva() throws {
        let d = try data()
        let c = try XCTUnwrap(d.latest.curve)
        let typisk = NightCurveView.typical(c, stem: d.latest.stem, summaries: d.summaries)
        XCTAssertNotNil(typisk, "den typiska natten finns")
        XCTAssertFalse(c.gaps.isEmpty, "glappet syns")
        // BESLUT B46. En gammal inspelning har ingen stadiedata, ingen medelpuls och inga minuter.
        let gammal = try XCTUnwrap(d.oldSummaries.first)
        XCTAssertNil(gammal.deepMinutes)
        XCTAssertNil(gammal.remMinutes)
        XCTAssertNil(gammal.lightMinutes)
        XCTAssertNil(gammal.meanHeartRate)

        try rendera(CurveStack(curve: c, typical: typisk, markerad: .constant(nil)), namn: "nattens-kurva")
        let botten = c.nadir.map { Date(timeIntervalSince1970: $0.time) }
        try rendera(CurveStack(curve: c, typical: typisk, markerad: .constant(botten)), namn: "nattens-kurva-markerad")
        try fånga(NavigationStack {
            CurveCharts(curve: c, typical: typisk)
                .navigationTitle(titel(d.latest))
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-nattens-kurva", höjd: 1_000)
    }

    /// METOD M28. En natt ur K18: kurvan ur samma `NightResult` som sammanfattningen.
    func test2bK18Kurva() throws {
        let d = try data()
        let r = d.latestK18
        let c = try XCTUnwrap(r.curve)
        XCTAssertEqual(r.source, .k18)
        XCTAssertNotNil(r.sleep, "natten är sömnperioden")
        // METOD M32. Lagren på tidsaxeln: rörelse, hudtemperatur, glapp med orsak och sömn.
        let lager = try XCTUnwrap(r.layers, "en natt ur K18 har lager")
        XCTAssertTrue(lager.minutes.contains { $0.movement != nil && $0.skinTemperature != nil }, "rörelse och temperatur")
        XCTAssertTrue(lager.minutes.contains { $0.skinTemperature == nil }, "tomma minuter vid glappet")
        XCTAssertTrue(lager.gaps.contains { $0.cause == .movement }, "glapp med rörelse som orsak")
        XCTAssertTrue(lager.gaps.contains { $0.cause == .unknown }, "glapp utan känd orsak")
        XCTAssertFalse(lager.asleep.isEmpty, "sömnbitarna")
        XCTAssertFalse(lager.awake.isEmpty, "den vakna stunden är ett avbrott")
        let dag = try XCTUnwrap(r.wakeDay)
        let stem = K18Nights.stem(dag)
        let typisk = NightCurveView.typical(c, stem: stem, summaries: d.summaries)
        XCTAssertNotNil(typisk, "den typiska natten ur de tidigare nätterna, en per dag")
        try rendera(CurveStack(curve: c, typical: typisk, layers: lager, markerad: .constant(nil)), namn: "k18-kurva")
        // METOD M37 · BESLUT B45 · BESLUT B46. Stadierna: alla fyra finns, minuterna går ihop med
        // sömntiden, och sammanfattningen bär samma minuter.
        let stadier = try XCTUnwrap(r.stages, "en natt ur K18 med nya mätningar har stadier")
        XCTAssertFalse(lager.stages.isEmpty, "stadiebandet")
        XCTAssertEqual(Set(lager.stages.map { $0.stage }), Set(SleepStage.allCases), "vaken, lätt, djup och REM")
        XCTAssertGreaterThanOrEqual(stadier.minutes(.deep), 10, "djupsömn")
        XCTAssertGreaterThanOrEqual(stadier.minutes(.rem), 10, "REM")
        let digest = NightDigest(r)
        let lättMin: Double = try XCTUnwrap(digest.lightMinutes)
        let djupMin: Double = try XCTUnwrap(digest.deepMinutes)
        let remMin: Double = try XCTUnwrap(digest.remMinutes)
        XCTAssertEqual(lättMin, stadier.minutes(.light), accuracy: 1e-9)
        XCTAssertEqual(djupMin, stadier.minutes(.deep), accuracy: 1e-9)
        XCTAssertEqual(remMin, stadier.minutes(.rem), accuracy: 1e-9)
        let sömnPeriod: SleepPeriod = try XCTUnwrap(r.sleep)
        let sömnMinuter: Double = sömnPeriod.asleepMinutesTotal
        XCTAssertEqual(sömnMinuter, stadier.minutes(.light) + stadier.minutes(.deep) + stadier.minutes(.rem),
                       accuracy: 1e-9, "sömntiden är lätt + djup + REM")
        XCTAssertNotNil(r.analysis.meanHeartRate, "medelpulsen")
        // METOD M42. Natten med fyra minuters rörelse mitt i sömnen har minuter i rörelse, och sammanfattningen bär dem.
        let rörelseMin: Int = try XCTUnwrap(r.movementMinutes, "en natt ur K18 har minuter i rörelse")
        XCTAssertGreaterThanOrEqual(rörelseMin, 3, "fyra minuter med armen i rörelse")
        XCTAssertEqual(NightDigest(r).movementMinutes, rörelseMin)
        // Markören mitt i ett typiskt djupt spann: avläsningen säger "Djup". Spannet får inte ligga vid
        // insomningen (METOD M37, Känd svaghet): där har bandet mest fel men ser säkrast ut.
        let natStart = lager.stages.map { $0.start }.min() ?? 0
        let djup = try XCTUnwrap(lager.stages.first { $0.stage == .deep && $0.start - natStart >= 1_200 },
                                 "ett djupt spann minst 20 min efter insomningen")
        let mitt = (djup.start + djup.end) / 2
        XCTAssertEqual(lager.stage(at: mitt)?.stage, .deep)
        try rendera(CurveStack(curve: c, typical: typisk, layers: lager,
                               markerad: .constant(Date(timeIntervalSince1970: mitt))), namn: "k18-kurva-stadium")
        let titelDag = r.sleep?.wakeDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? ""
        try fånga(NavigationStack {
            CurveCharts(curve: c, typical: typisk, layers: lager)
                .navigationTitle(titelDag)
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-k18-kurva", höjd: 1_400)

        // METOD M44 · METOD M46 · BESLUT B54 · BESLUT B56. Lagret "Ljud": nivån, snarkningens band, symbolerna och
        // det som följdes av något, med klippen (förhandsvisningen säger att alla klipp finns) och facit.
        let ljud = try XCTUnwrap(r.sound, "den senaste natten har ljud")
        XCTAssertTrue(ljud.events.contains { $0.woke }, "något väckte")
        XCTAssertTrue(ljud.events.contains { $0.owner == .yours }, "din snarkning")
        XCTAssertTrue(ljud.events.contains { $0.owner == .someoneElse }, "någon annans snarkning")
        XCTAssertTrue(ljud.events.contains { $0.soundClass == SoundClass.door.rawValue }, "en dörr")
        XCTAssertFalse(ljud.levels.isEmpty, "nivån")
        let finnsKlipp: (NightSound.Clip) -> Bool = { (_: NightSound.Clip) -> Bool in true }
        try rendera(CurveStack(curve: c, typical: typisk, layers: lager, sound: ljud, markerad: .constant(nil))
            .environment(\.clipExists, finnsKlipp), namn: "k18-kurva-ljud")
        let ljudTid = ljud.followed.first.map { Date(timeIntervalSince1970: $0.time) }
        try rendera(CurveStack(curve: c, typical: typisk, layers: lager, sound: ljud, markerad: .constant(ljudTid))
            .environment(\.clipExists, finnsKlipp), namn: "k18-kurva-ljud-markerad")
        try fånga(NavigationStack {
            CurveCharts(curve: c, typical: typisk, layers: lager, sound: ljud)
                .navigationTitle(titelDag)
                .navigationBarTitleDisplayMode(.inline)
                .environment(\.clipExists, finnsKlipp)
        }, namn: "skarm-k18-kurva-ljud", höjd: 2_300)

        // Rapporten över ljudet med klippen öppna, och några omdömen (facit) satta: rätt på trafiken, fel på
        // dörren, och din snarkning rätt både som klass och som ägare. Omdömena tas bort efteråt.
        let butik = SoundFacitStore.shared
        let trafik = try XCTUnwrap(ljud.events.first { $0.soundClass == SoundClass.traffic.rawValue })
        let dörr = try XCTUnwrap(ljud.events.first { $0.soundClass == SoundClass.door.rawValue })
        let din = try XCTUnwrap(ljud.events.first { $0.owner == .yours })
        let annans = try XCTUnwrap(ljud.events.first { $0.owner == .someoneElse })
        butik.rateClass(trafik, right: true)
        butik.rateClass(dörr, right: false)
        butik.rateClass(din, right: true)
        butik.rateOwner(din, right: true)
        butik.rateOwner(annans, right: false)
        XCTAssertEqual(butik.facit.heard, 3)
        XCTAssertEqual(butik.facit.ownerTally().heard, 2)
        try rendera(SoundReport(sound: ljud, clipsOpen: true).padding().environment(\.clipExists, finnsKlipp),
                    namn: "ljud-rapport")
        butik.rateClass(trafik, right: true)
        butik.rateClass(dörr, right: false)
        butik.rateClass(din, right: true)
        butik.rateOwner(din, right: true)
        butik.rateOwner(annans, right: false)
        XCTAssertEqual(butik.facit.entries.count, 0, "samma knapp en gång till tar bort omdömet")
    }

    // MARK: Trendvyn (BESLUT B82)

    func test3OverTid() throws {
        let d = try data()
        // METOD M42. Bilderna ritar de äldre dagarna med K18-bara tal ur DemoHistory (Demo.history); appens egen
        // väg (`TrendsView.series`, ur sammanfattningarna) prövas bredvid, för de räknade nätterna.
        let serier = Trends.series(idun: Trends.idunValues(idunNätter(d)), whoop: [:]).filter { !$0.points.isEmpty }
        XCTAssertFalse(serier.isEmpty)
        let appens = TrendsView.series(summaries: d.summaries).filter { !$0.points.isEmpty }
        let appensRörelse = try XCTUnwrap(appens.first { $0.measure == .movement }, "rörelsens serie ur sammanfattningarna")
        XCTAssertGreaterThanOrEqual(appensRörelse.points.count, Self.antalK18 - 2, "en punkt per K18-natt")
        // BESLUT B40. Bara Idunn: ingen serie har en andra källa.
        XCTAssertTrue(serier.allSatisfy { $0.sources == [.idun] }, "bara Idunns nätter")
        // METOD M25. Hudtemperaturen har en lucka på varje natt under minsta täckning.
        let hud = try XCTUnwrap(serier.first { $0.measure == .skinTemperature })
        XCTAssertGreaterThanOrEqual(hud.points.count, Self.antalNätter - 6)
        XCTAssertLessThanOrEqual(hud.points.count, Self.antalNätter)
        // METOD M26. Idunns sömntid ur K18.
        let sömn = try XCTUnwrap(serier.first { $0.measure == .sleep })
        XCTAssertGreaterThanOrEqual(sömn.points.count, Self.antalK18 - 2)
        // BESLUT B34 · BESLUT B46. Medelpulsen ur K18-nätterna.
        let medelpuls = try XCTUnwrap(serier.first { $0.measure == .meanHeartRate }, "medelpulsens diagram")
        XCTAssertGreaterThanOrEqual(medelpuls.points.count, Self.antalK18 - 2)
        XCTAssertFalse(medelpuls.bands.isEmpty, "medelpulsens normalområde")
        // METOD M42 · BESLUT B51. Minuter i rörelse: en punkt per natt ur K18, med medel och normalområde.
        let rörelse = try XCTUnwrap(serier.first { $0.measure == .movement }, "rörelsens diagram")
        XCTAssertGreaterThanOrEqual(rörelse.points.count, Self.antalNätter - 4)
        XCTAssertFalse(rörelse.rolling.isEmpty, "7-dagarsmedlet")
        XCTAssertFalse(rörelse.bands.isEmpty, "rörelsens normalområde")
        XCTAssertTrue(rörelse.points.allSatisfy { $0.value >= 0 }, "minuter")
        // METOD M33. Regelbundenheten ur Idunns sömnperioder.
        let sri = try XCTUnwrap(serier.first { $0.measure == .regularity }, "regelbundenhetens diagram")
        XCTAssertFalse(sri.rolling.isEmpty)
        // METOD M44 · BESLUT B54. Dina snarkminuter per timme sömn: en punkt per natt med ljud (en natt av nio
        // saknar det), med medel och normalområde som de andra måtten.
        let snarkning = try XCTUnwrap(serier.first { $0.measure == .snoring }, "snarkningens diagram")
        XCTAssertGreaterThanOrEqual(snarkning.points.count, 30)
        XCTAssertLessThan(snarkning.points.count, Self.antalNätter, "nätter utan ljud har ingen punkt")
        XCTAssertFalse(snarkning.rolling.isEmpty, "7-dagarsmedlet")
        XCTAssertFalse(snarkning.bands.isEmpty, "snarkningens normalområde")
        XCTAssertNil(snarkning.latest?.status, "bara HRV får ett läge")
        let appensSnarkning = try XCTUnwrap(appens.first { $0.measure == .snoring }, "snarkningen ur sammanfattningarna")
        XCTAssertGreaterThanOrEqual(appensSnarkning.points.count, Self.antalK18 - 4, "en punkt per K18-natt med ljud")

        // BESLUT B63 · BESLUT B82 · METOD M51 (D2). Trendvyn med ett halvår: de räknade nätterna, de äldre K18-bara talen
        // och de sammanfattade nätterna (`DemoHistory.summaryNights`).
        let alla: [Trends.Series] = Trends.series(idun: Trends.idunValues(idunHalvår(d)), whoop: [:])
        let slut: WakeDay = try XCTUnwrap(Trends.lastDay(alla))
        let hrv = try XCTUnwrap(alla.first { $0.measure == .hrv })
        let månad = Trends.overview(hrv, span: .month, end: slut)
        XCTAssertEqual(månad.buckets.count, 30)
        XCTAssertNotNil(månad.mean, "medlet över 30 dagar")
        XCTAssertNotNil(månad.change, "ändringen mot månaden före")
        let halvår = Trends.overview(hrv, span: .halfYear, end: slut)
        XCTAssertEqual(halvår.buckets.count, 182, "en punkt per dag")
        XCTAssertGreaterThanOrEqual(halvår.buckets.filter { $0.value != nil }.count, 150, "nästan en natt per dag")
        XCTAssertGreaterThanOrEqual(halvår.months.filter { $0.mean != nil }.count, 6, "ett medel per månad")
        XCTAssertGreaterThanOrEqual(halvår.months.filter { $0.change != nil }.count, 5, "och ändringen mot månaden före")
        let förra = try XCTUnwrap(Trends.stepped(end: slut, span: .month, by: -1, first: try XCTUnwrap(Trends.firstDay(alla)),
                                                 last: slut))
        XCTAssertEqual(förra, slut - 30, "‹ går en månad bakåt")
        for m in [Trends.Measure.efficiency, .deepSleep, .sleepOnset] {
            let s = try XCTUnwrap(alla.first { $0.measure == m }, "\(m)")
            XCTAssertGreaterThan(s.points.count, 150, "\(m): nästan en punkt per natt")
        }
        let huvud: Huvudtal = Self.påhittadeHuvudtal(slut: slut)
        func stapel(_ m: TidMått, _ p: Trends.Span, h: Huvudtal = .tom, serier: [Trends.Series]? = nil,
                    markerad: Date? = nil, slutdag: WakeDay? = nil, val: Bool = false) -> TrendStack {
            TrendStack(serier: serier ?? alla, huvudtal: h, mått: .constant(m), period: .constant(p),
                       slut: .constant(slutdag), markerad: .constant(markerad), valÖppet: .constant(val))
        }
        // BESLUT B82. V med varje dags tal och bandet, M med linjen, bandet och senaste värdet, 6M med dagarna svagt och
        // månadernas medel med ändringen mot månaden före.
        try rendera(stapel(.hrv, .week), namn: "trend-v")
        try rendera(stapel(.hrv, .month), namn: "trend-m")
        try rendera(stapel(.hrv, .halfYear), namn: "trend-6m")
        try rendera(stapel(.resting, .halfYear), namn: "trend-6m-vilopuls")
        try rendera(stapel(.sleep, .week), namn: "trend-v-somn")
        try rendera(stapel(.hrv, .month, slutdag: slut - 30), namn: "trend-m-bakat")
        try rendera(stapel(.hrv, .week, val: true), namn: "trend-val")
        try rendera(stapel(.hrv, .month, markerad: slut.noonUTC.addingTimeInterval(-5 * 86_400)), namn: "trend-markerad")
        try rendera(stapel(.sleep, .month), namn: "trend-somn")
        try rendera(stapel(.efficiency, .month), namn: "trend-effektivitet")
        try rendera(stapel(.deep, .halfYear), namn: "trend-djupsomn")
        try rendera(stapel(.skin, .week), namn: "trend-hudtemp")
        try rendera(stapel(.snoring, .month), namn: "trend-snarkning")
        // Spåret H: platsen står tom i appen, och ifylld med påhittade tal bara här.
        try rendera(stapel(.recovery, .month), namn: "trend-aterhamtning")
        try rendera(stapel(.recovery, .week, h: huvud), namn: "trend-aterhamtning-huvudtal")
        try rendera(stapel(.debt, .week, h: huvud), namn: "trend-sombrist-huvudtal")
        // Utan baslinje: bara de fem senaste nätterna (färre än 7, BESLUT B69), så normalbanden saknas.
        let ung: [Trends.IdunNight] = Array(idunNätter(d).sorted { (a: Trends.IdunNight, b: Trends.IdunNight) -> Bool in
            a.day > b.day
        }.prefix(5))
        let ungaSerier: [Trends.Series] = Trends.series(idun: Trends.idunValues(ung), whoop: [:])
        try rendera(stapel(.hrv, .week, serier: ungaSerier), namn: "trend-utan-baslinje")
        // Skärmen som på telefonen, pushad från Morgon: rubriken och rullningen är riktiga.
        try fånga(NavigationStack {
            ScrollView { stapelMedRullning(.hrv, .week, alla) }
                .background(Tema.bg)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-trend", höjd: 1_400)
        try fånga(NavigationStack {
            ScrollView { stapelMedRullning(.hrv, .halfYear, alla) }
                .background(Tema.bg)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-trend-6m", höjd: 1_400)
    }

    func stapelMedRullning(_ m: TidMått, _ p: Trends.Span, _ serier: [Trends.Series]) -> TrendStack {
        TrendStack(serier: serier, mått: .constant(m), period: .constant(p), markerad: .constant(nil))
    }

    // MARK: Nattrapporten

    func test4Nattrapport() throws {
        let d = try data()
        let r = d.latest
        let q = r.quality
        let a = r.analysis

        // Listan i sina delar: ImageRenderer ritar inte List.
        let delar = VStack(alignment: .leading, spacing: 12) {
            kort {
                NightBar(gaps: r.gaps).frame(height: 22)
            }
            kort {
                VStack(spacing: 10) {
                    CheckRow(symbol: "pause.circle", title: "Glapp",
                             value: q.gaps.map { "\($0.count) · \(pct($0.fraction))" }, passes: q.gaps?.passes)
                    CheckRow(symbol: "1.circle", title: "Varje slag",
                             value: q.coverage.map { pct($0.fractionComplete) }, passes: q.coverage?.passes)
                    CheckRow(symbol: "2.circle", title: "Uträknade",
                             value: q.computed.map { "\(pct($0.fractionEqualToBpm)) · \(pct($0.fractionIdentical))" },
                             passes: q.computed?.passes)
                    CheckRow(symbol: "3.circle", title: "Utjämnade",
                             value: q.smoothing.map { String(format: "%.2f", $0.ratio) }, passes: q.smoothing?.passes)
                }
            }
            kort {
                DiagnosisGrid(d: r.diagnostics, cleaning: a.cleaning,
                              unreadable: r.contents.unreadableNotifications)
            }
        }
        .padding()
        try rendera(delar, namn: "nattrapport-delar")
        try rendera(ReportList(report: r), namn: "nattrapport-imagerenderer", krav: false)
        try fånga(NavigationStack {
            ReportList(report: r)
                .navigationTitle(titel(r))
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-nattrapport", höjd: 1_900)
    }

    // MARK: Nätter, på Data (BESLUT B40)

    /// Listan över nätter på Data: Idunns egna nätter, en per uppvakningsdag, K18 före en
    /// gammal inspelning. Den senaste är preliminär (räknad före klockan 12).
    func test5Natter() throws {
        let d = try data()
        var lista = d.summaries
        if let i = lista.firstIndex(where: { $0.origin == .k18 }) { lista[i].preliminary = true }
        let nätter = NightSummary.preferred(lista)
        XCTAssertEqual(nätter.count, Self.antalNätter, "en natt per uppvakningsdag")
        XCTAssertGreaterThanOrEqual(nätter.filter { $0.origin == .k18 }.count, Self.antalK18 - 2,
                                    "K18 går före samma dag")
        XCTAssertEqual(nätter.first?.origin, .k18)

        let rader = VStack(alignment: .leading, spacing: 10) {
            ForEach(nätter.prefix(10)) { s in
                IdunNightRow(summary: s)
                Divider()
            }
        }
        .padding()
        try rendera(rader, namn: "natter-rader")
        // Listan ligger på Data (BESLUT B40), för kontroll.
        try fånga(NavigationStack { NightsList(summaries: lista) }, namn: "skarm-natter")
        try fånga(NavigationStack { NightsList(summaries: []) }, namn: "skarm-natter-tom", höjd: 400)
    }

    /// Whoops nätter ur exporten (sidan Data → Whoops nätter).
    func test5bWhoopsNatter() throws {
        let d = try data()
        let cycles = d.export.cycles
        let rader = VStack(alignment: .leading, spacing: 10) {
            ForEach(cycles.suffix(12).reversed(), id: \.start) { c in
                NightRow(cycle: c)
                Divider()
            }
        }
        .padding()
        try rendera(rader, namn: "whoop-natter-rader")
        try rendera(NightList(cycles: cycles), namn: "whoop-natter-imagerenderer", krav: false)
        try fånga(NavigationStack {
            NightList(cycles: cycles).navigationTitle("Whoops nätter")
        }, namn: "skarm-whoop-natter")
    }

    // MARK: Idunn mot Whoop

    func test6IdunnMotWhoop() throws {
        let d = try data()
        // METOD M26. Sömnjämförelsen: K18-nätternas sömnperiod mot Whoops pass.
        let perioder = NightSummary.preferred(d.summaries).compactMap { $0.sleepPeriod }
        XCTAssertGreaterThanOrEqual(perioder.count, Self.antalK18 - 2)
        let sömn = SleepComparison.summary(nights: perioder, whoop: d.export.sleeps)
        XCTAssertTrue(sömn.isEnough, "minst tre nätter möter ett pass: \(sömn)")
        try fånga(NavigationStack {
            MorningView(summaries: d.summaries, cycles: d.export.cycles, sleeps: d.export.sleeps)
        }, namn: "skarm-idunn-mot-whoop", höjd: 1_100)
    }

    // MARK: Data (BESLUT B38)

    func test7Data() throws {
        let d = try data()
        // En fast klocka: onsdag 14 oktober 07:30 i telefonens zon, så att
        // fönstret (kväll 18 till morgon 12) och "min sedan" blir desamma varje gång.
        let zon = TimeZone.current.secondsFromGMT()
        let nu = DayLog.date(of: DayLog.Day(year: 2026, month: 10, day: 14), hour: 7, minute: 30,
                             utcOffsetSeconds: zon)
        let fönster = NightWindow.latest(now: nu, utcOffsetSeconds: zon)
        XCTAssertTrue(fönster.inProgress, "klockan 07:30 pågår natten")

        // Ansluten, K18 med ett glapp, Whoop synkade för 20 minuter sedan.
        let bra = ListenerStatus.read(DemoListener.notifications(
            start: fönster.start, end: nu, gap: 0.55...0.65, syncAt: nu.addingTimeInterval(-20 * 60)))
        let braTäckning = try XCTUnwrap(bra.coverage(fönster))
        XCTAssertGreaterThan(braTäckning.fraction, 0.8)
        XCTAssertEqual(bra.lastSync, nu.addingTimeInterval(-20 * 60))
        // Letar efter bandet, K18 bara första kvällen, ingen synk.
        let glest = ListenerStatus.read(DemoListener.notifications(
            start: fönster.start, end: fönster.start.addingTimeInterval(3 * 3600)))
        let glestTäckning = try XCTUnwrap(glest.coverage(fönster))
        XCTAssertLessThan(glestTäckning.fraction, 0.5, "under hälften är orange")
        // Nystartad: inget hört alls.
        let tom = ListenerStatus()
        XCTAssertNil(tom.lastK18Heard)

        // METOD M29. Samma statusar mot Morgons regler: bara den glesa säger till.
        XCTAssertNil(ListenerCheck.alert(status: bra, nightCoverage: 0.93, bluetooth: .ok, now: nu,
                                         utcOffsetSeconds: zon), "en bra natt ger ingen rad")
        let larm = ListenerCheck.alert(status: glest, nightCoverage: nil, bluetooth: .ok, now: nu,
                                       utcOffsetSeconds: zon)
        let sist = try XCTUnwrap(glest.lastK18Heard)
        XCTAssertEqual(larm, .silent(since: sist))
        XCTAssertEqual(ListenerCheck.alert(status: tom, nightCoverage: nil, bluetooth: .ok, now: nu,
                                           utcOffsetSeconds: zon), .neverHeard)

        let rader = VStack(alignment: .leading, spacing: 12) {
            kort { ListenerView(link: .connected, battery: 72, status: bra, now: nu) }
            kort { ListenerView(link: .searching, battery: 31, status: glest, unsaved: 12, now: nu) }
            kort { ListenerView(link: .bluetoothOff, battery: nil, status: tom, now: nu) }
        }
        .padding()
        try rendera(rader, namn: "lyssnaren")

        let dagar: [DayFile] = [
            DayFile(stem: "dygn-2026-10-14", bytes: 9_400_000),
            DayFile(stem: "dygn-2026-10-13", bytes: 23_800_000),
            DayFile(stem: "dygn-2026-10-12", bytes: 21_100_000),
        ]
        // METOD M46 · BESLUT B56. Facit för klassningen, påhittat: 8 trafikklipp (ett fel), 5 tal (två fel: över en
        // femtedel), 4 snarkningar (ett fel) och ägaren rätt på tre av fyra.
        var facit = SoundFacit()
        let facitStam = "ljud-2026-10-13T21-03-00Z"
        for i in 0..<8 {
            facit.rateClass(NightSound.Clip(stem: facitStam, second: 100 + i), soundClass: SoundClass.traffic.rawValue,
                            owner: nil, right: i != 2, at: 1)
        }
        for i in 0..<5 {
            facit.rateClass(NightSound.Clip(stem: facitStam, second: 200 + i), soundClass: SoundClass.speech.rawValue,
                            owner: nil, right: i > 1, at: 1)
        }
        for i in 0..<4 {
            let klipp = NightSound.Clip(stem: facitStam, second: 300 + i)
            facit.rateClass(klipp, soundClass: SoundClass.snoring.rawValue, owner: .yours, right: i != 1, at: 1)
            facit.rateOwner(klipp, soundClass: SoundClass.snoring.rawValue, owner: .yours, right: i != 3, at: 1)
        }
        XCTAssertTrue(facit.classTally().contains { $0.overThreshold }, "tal ligger över en femtedel")
        // Några K18-nätter (med kontrollen av stämpeln) och några gamla inspelningar.
        let urval: [NightSummary] = Array(d.k18Summaries.prefix(4)) + Array(d.oldSummaries.suffix(3))
        try fånga(NavigationStack {
            DataScreen(link: .connected, battery: 72, status: bra, summaries: urval, cycles: d.export.cycles,
                       sleeps: d.export.sleeps, days: dagar, activeDay: "dygn-2026-10-14", tally: FrameTally(),
                       listening: ["fd4b0003", "fd4b0004", "fd4b0005", "fd4b0007"], storage: .demo, lastMarker: nil,
                       markerCount: 0,
                       // BESLUT B47. Ljudet under natten, påhittat: sex och en halv timme, ett glapp.
                       sound: SoundListener.Status(listening: true, since: nu.addingTimeInterval(-23_400),
                                                   seconds: 23_400, gaps: 1, clips: 37, bytes: 1_900_000),
                       facit: facit, now: nu)
        }, namn: "skarm-data", höjd: 2_700)
    }

    // MARK: Påhittade huvudtal (spåret H)

    /// BESLUT B63. Påhittade tal för platserna i spåret H, bara för att pröva formen: ingen formel, inget som räknas.
    static func påhittadeHuvudtal(slut: WakeDay) -> Huvudtal {
        var h = Huvudtal()
        h.recovery = 54
        h.sleepScore = 87
        h.needHours = 8.42
        h.bedtime = -111
        h.scoreParts = [93, 92, 81]
        h.needBase = 7.6
        h.needStrain = 0.27
        h.needDebt = 0.55
        h.stressHigh = 0.0
        h.stressMid = 1.6
        h.stressLow = 6.27
        h.drags = [-14, -5, 6]
        h.breathingHigh = true
        h.sleepVsNeed = 88
        h.sleepVsNeedRange = 82...94
        var r = Seeded(2026)
        var kurva: [Double] = []
        var glatt: Double = 0.6
        for _ in 0..<240 {
            glatt = glatt * 0.85 + min(3, max(0, r.uniform() * 3)) * 0.15
            kurva.append(glatt)
        }
        h.stressCurve = kurva
        var rec: [WakeDay: Double] = [:]
        var poäng: [WakeDay: Double] = [:]
        var brist: [WakeDay: Double] = [:]
        var behov: [WakeDay: Double] = [:]
        var stress: [WakeDay: Double] = [:]
        for k in 0..<Self.halvårDagar {
            let dag: WakeDay = slut - k
            rec[dag] = max(8, min(99, 58 + 18 * sin(Double(k) / 6) + 10 * r.gauss()))
            poäng[dag] = max(45, min(100, 84 + 7 * sin(Double(k) / 9) + 5 * r.gauss()))
            brist[dag] = max(0, 0.6 + 0.4 * r.gauss())
            behov[dag] = 8.1 + 0.6 * r.uniform()
            stress[dag] = max(0, 1.5 + 0.8 * r.gauss())
        }
        h.series = ["recovery": rec, "sleepScore": poäng, "debt": brist, "need": behov, "stress": stress]
        return h
    }

    // MARK: Ritningen

    private func titel(_ r: NightReport) -> String {
        r.contents.recording.end?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? ""
    }

    private func kort<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        inner()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    /// `ImageRenderer`: innehållet i full längd, mörkt läge, @3x.
    private func rendera(_ vy: some View, namn: String, krav: Bool = true) throws {
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
            if krav { XCTFail("kunde inte rita \(namn)") }
            print("PROV: \(namn) gick inte att rita med ImageRenderer")
            return
        }
        try skriv(png, namn: namn, storlek: bild.size, skala: bild.scale)
    }

    /// Ett riktigt fönster: listor och navigationsrubrik som på telefonen.
    private func fånga(_ vy: some View, namn: String, höjd: CGFloat = IdunnProv.skärmhöjd) throws {
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
        // Listornas celler och diagrammen ritas på nästa varv.
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
