import Foundation
import XCTest
import DemoData
import HeartRate
import WhoopFrames
@testable import Night

// METOD M28 · METOD M32 · BESLUT B48 · BESLUT B52 (E2, E3). VAKTEN: en natt med K18 ger lager och väljs före
// inspelningen. Provet kör telefonens väg med filer i minnet i stället för i Application
// Support, och anropar de funktioner appen anropar: `NightLedger.computeDue` (som
// `K18Nights.computeDue`), `K18Days.night` (som `K18Nights.result`, och därmed
// `NightLoader.bundle`), `NightChoice.outvoted` (som `Recorder`) och `Trends.idunPerDay` /
// `Trends.idunValues` (som Morgon, Över tid och Nätter). Ändrar någon av dem valet, eller tappar
// en K18-natt sina lager, fäller det här provet, utan telefon. Påhittade nätter.

final class NattvalVaktTests: XCTestCase {

    // MARK: Hjälpare

    func uppvakningsdag(_ n: DemoK18Nights.Night) -> WakeDay {
        WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
    }

    /// En gammal inspelning av natten: sidofilen med zonen och `.t2.jsonl` med K18-notiserna.
    func inspelning(_ n: DemoK18Nights.Night) -> K18Days.File {
        let stam = RecordingStem.stem(for: Date(timeIntervalSince1970: Double(n.records[0].time) - 90))
        return K18Days.File(stem: stam, sidecar: RecordingLog.header(utcOffsetSeconds: n.utcOffsetSeconds),
                            frames: DemoK18Frames.log(DemoK18Frames.notifications(n.records)))
    }

    /// Inspelningens sammanfattning som Morgon ser den: en gammal natt (2A37) samma dag.
    func gammalNatt(_ dag: WakeDay, fönster: Int = 60) -> Trends.IdunNight {
        Trends.IdunNight(day: dag, validWindows: fönster, rmssd: 41, restingHeartRate: 54, breathsPerMinute: 14,
                         source: .notification, id: "inspelning")
    }

    struct Väg {
        var dag: WakeDay
        var digest: NightDigest
        var result: NightResult
    }

    /// Telefonens väg för en natt som bara finns som inspelning: räkna den som appen gör vid start,
    /// och hämta hela resultatet som kurvan gör (`K18Nights.result`).
    func telefonensVäg(_ n: DemoK18Nights.Night) throws -> Väg {
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let fil = inspelning(n)
        let filer: [String: K18Days.File] = [fil.stem: fil]
        let nu = NightLedger.windowEnd(dag, utcOffsetSeconds: z).addingTimeInterval(3 * 3600)

        var sparade: [NightLedger.Entry] = []
        NightLedger.computeDue(dayStems: [], recordingStems: [fil.stem], entries: [:], build: "10", now: nu,
                               utcOffsetSeconds: z, load: { filer[$0] },
                               save: { (e: NightLedger.Entry) -> Void in sparade.append(e) })
        let post = try XCTUnwrap(sparade.first { (e: NightLedger.Entry) -> Bool in e.wakeDay == dag },
                                 "natten ur inspelningen räknades")
        let digest = try XCTUnwrap(post.digest, "…och blev en natt")
        let satt = NightLedger.isSettled(dag, now: nu, utcOffsetSeconds: z)
        let result = try XCTUnwrap(K18Days.night(wakeDay: dag, includeNext: satt, recordingStems: [fil.stem],
                                                  fallbackOffsetSeconds: z, load: { filer[$0] }))
        return Väg(dag: dag, digest: digest, result: result)
    }

    // MARK: Vakten

    func testEnNattMedK18GerLagerOchVäljsFöreInspelningen() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let v = try telefonensVäg(n)

        // Natten har lager: kurvan, rörelse, temperatur, glapp och sömnperioden på samma tidsaxel.
        XCTAssertEqual(v.result.source, .k18)
        XCTAssertNotNil(v.result.curve, "kurvan")
        XCTAssertNotNil(v.result.layers, "lagren")
        XCTAssertFalse(NightChoice.lacksLayers(source: v.result.source, layers: v.result.layers))
        XCTAssertEqual(v.digest.source, .k18)
        XCTAssertGreaterThan(v.digest.validWindows, Trends.minValidWindows)
        let täckning = try XCTUnwrap(v.digest.coverage)
        XCTAssertGreaterThanOrEqual(täckning, ListenerCheck.minCoverage, "bandet hördes hela natten")

        // Valet: samma dag finns en gammal inspelning, och K18-natten gäller, i vilken ordning de än kommer.
        var k18 = v.digest.idunNight
        k18.id = "natt"
        let gammal = gammalNatt(v.dag)
        for ordning in [[k18, gammal], [gammal, k18]] {
            XCTAssertEqual(Trends.idunPerDay(ordning)[v.dag]?.id, "natt")
            XCTAssertEqual(Trends.idunPerDay(ordning)[v.dag]?.source, .k18)
        }
        // Det som Morgon och Över tid ritar: sömntiden finns bara hos K18-natten.
        XCTAssertNotNil(Trends.idunValues([k18, gammal])[.sleep]?[v.dag], "Morgon visar K18-nattens sömntid")

        // Och vyerna ser båda nätterna men väljer K18: ingen viker sig för en inspelning när bandet hördes.
        let kandidater: [NightChoice.Candidate] = [
            NightChoice.Candidate(id: "natt", day: v.dag, source: .k18, coverage: v.digest.coverage,
                                  validWindows: v.digest.validWindows),
            NightChoice.Candidate(id: "inspelning", day: v.dag, source: .notification, coverage: nil,
                                  validWindows: 60),
        ]
        XCTAssertEqual(NightChoice.outvoted(kandidater), [])
        XCTAssertEqual(NightChoice.eligible(kandidater), kandidater)
    }

    func testEnK18NattSomBandetHördeFörLiteVikerSigFörInspelningenSomLågPåHelaNatten() throws {
        let v = try telefonensVäg(DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false))
        var k18 = v.digest.idunNight
        k18.id = "natt"
        let gammal = gammalNatt(v.dag)
        // Samma natt, men bandet hördes bara 41 % av sömnperioden.
        let kandidater: [NightChoice.Candidate] = [
            NightChoice.Candidate(id: "natt", day: v.dag, source: .k18, coverage: 0.41,
                                  validWindows: v.digest.validWindows),
            NightChoice.Candidate(id: "inspelning", day: v.dag, source: .notification, coverage: nil,
                                  validWindows: 60),
        ]
        XCTAssertEqual(NightChoice.outvoted(kandidater), ["natt"])
        let kvar: Set<String> = Set(NightChoice.eligible(kandidater).map(\.id))
        XCTAssertEqual(kvar, ["inspelning"])
        // Vyerna får bara det som är kvar, och väljer då inspelningen.
        let vyernas: [Trends.IdunNight] = [k18, gammal].filter { (n: Trends.IdunNight) -> Bool in kvar.contains(n.id) }
        XCTAssertEqual(Trends.idunPerDay(vyernas)[v.dag]?.id, "inspelning")
        XCTAssertEqual(Trends.idunPerDay(vyernas)[v.dag]?.source, .notification)
        XCTAssertNil(Trends.idunValues(vyernas)[.sleep]?[v.dag], "en gammal inspelning har ingen sömnperiod")
    }

    // MARK: Valet i detalj

    func kandidat(_ id: String, _ dag: WakeDay, _ källa: NightSource, _ täckning: Double?, fönster: Int = 60)
        -> NightChoice.Candidate {
        NightChoice.Candidate(id: id, day: dag, source: källa, coverage: täckning, validWindows: fönster)
    }

    func testGränsenÄrListenerChecksMinTäckning() {
        let d = WakeDay(daysSince1970: 20_000)
        XCTAssertEqual(ListenerCheck.minCoverage, 0.5)
        XCTAssertTrue(NightChoice.k18Qualifies(coverage: 0.5), "vid gränsen gäller K18")
        XCTAssertFalse(NightChoice.k18Qualifies(coverage: 0.4999))
        XCTAssertFalse(NightChoice.k18Qualifies(coverage: nil), "en natt utan täckning är obevisad")
        let alla = [kandidat("k", d, .k18, 0.5), kandidat("g", d, .notification, nil)]
        XCTAssertEqual(NightChoice.outvoted(alla), [])
        let under = [kandidat("k", d, .k18, 0.4999), kandidat("g", d, .notification, nil)]
        XCTAssertEqual(NightChoice.outvoted(under), ["k"])
        let utan = [kandidat("k", d, .k18, nil), kandidat("g", d, .notification, nil)]
        XCTAssertEqual(NightChoice.outvoted(utan), ["k"])
    }

    func testEnK18NattUtanInspelningBlirKvarHurLiteDenHördes() {
        let d = WakeDay(daysSince1970: 20_000)
        XCTAssertEqual(NightChoice.outvoted([kandidat("k", d, .k18, 0.05)]), [], "inget bättre att visa")
        XCTAssertEqual(NightChoice.outvoted([kandidat("k", d, .k18, nil)]), [])
        // En inspelning en annan dag hjälper inte.
        XCTAssertEqual(NightChoice.outvoted([kandidat("k", d, .k18, 0.05), kandidat("g", d + 1, .notification, nil)]), [])
    }

    func testEnInspelningSomInteÄrEnNattFårInteTaK18NattensPlats() {
        // Under minsta antal giltiga fönster är inspelningen ett prov (METOD M14) och väljs aldrig av
        // `Trends.idunPerDay`; då ska inte K18-natten ha viket för den.
        let d = WakeDay(daysSince1970: 20_000)
        let kort = kandidat("g", d, .notification, nil, fönster: Trends.minValidWindows - 1)
        XCTAssertEqual(NightChoice.outvoted([kandidat("k", d, .k18, 0.1), kort]), [])
        let nog = kandidat("g", d, .notification, nil, fönster: Trends.minValidWindows)
        XCTAssertEqual(NightChoice.outvoted([kandidat("k", d, .k18, 0.1), nog]), ["k"])
    }

    func testVarjeDagValsForSig() {
        let a = WakeDay(daysSince1970: 20_000), b = a + 1, c = a + 2
        let alla = [
            kandidat("k-a", a, .k18, 0.9), kandidat("g-a", a, .notification, nil),
            kandidat("k-b", b, .k18, 0.2), kandidat("g-b", b, .notification, nil),
            kandidat("k-c", c, .k18, 0.2),
        ]
        XCTAssertEqual(NightChoice.outvoted(alla), ["k-b"])
        XCTAssertEqual(NightChoice.eligible(alla).map(\.id), ["k-a", "g-a", "g-b", "k-c"], "ordningen behålls")
        // Två K18-nätter samma dag, en för lite hörd: bara den viker sig.
        let två = [kandidat("bra", a, .k18, 0.8), kandidat("dålig", a, .k18, 0.1), kandidat("g", a, .notification, nil)]
        XCTAssertEqual(NightChoice.outvoted(två), ["dålig"])
    }

    func testLagerSaknasBaraHosEnK18NattSomBordeHaDem() {
        XCTAssertTrue(NightChoice.lacksLayers(source: .k18, layers: nil))
        XCTAssertFalse(NightChoice.lacksLayers(source: .notification, layers: nil), "en gammal inspelning har inga lager")
    }

    // MARK: En natt utan lager (E3, BESLUT B52)

    func testEnK18NattVarsFilerInteGårAttLäsaSaknarLager() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let v = try telefonensVäg(n)
        // Med filerna har natten lager, och Morgon säger inget.
        XCTAssertFalse(NightChoice.lacksLayers(source: v.digest.source, layers: v.result.layers))

        // Utan dem (raderade eller aldrig skrivna) går ingen natt att räkna om: resultatet saknas,
        // och därmed lagren. Sammanfattningen (`v.digest`) ligger kvar och Morgon visar den.
        let utan: NightResult? = K18Days.night(wakeDay: v.dag, includeNext: true, recordingStems: [],
                                               fallbackOffsetSeconds: n.utcOffsetSeconds,
                                               load: { (_: String) -> K18Days.File? in nil })
        XCTAssertNil(utan, "inga filer, ingen natt")
        XCTAssertTrue(NightChoice.lacksLayers(source: v.digest.source, layers: utan?.layers),
                      "en natt ur K18 vars kurva inte går att räkna fram saknar lager")
        XCTAssertEqual(v.digest.source, .k18)
        // Samma sak för en gammal inspelning är inget fel: den ritas som förut, utan lager.
        XCTAssertFalse(NightChoice.lacksLayers(source: .notification, layers: utan?.layers))
    }

    func testEnNattUtanDygnetEfterSaknarInteLager() throws {
        // Dygnet efter uppvakningsdagen är inget krav: en natt som inte satt sig läses utan det.
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let v = try telefonensVäg(n)
        let fil = inspelning(n)
        let ur = K18Days.night(wakeDay: v.dag, includeNext: false, recordingStems: [fil.stem],
                               fallbackOffsetSeconds: n.utcOffsetSeconds,
                               load: { (s: String) -> K18Days.File? in s == fil.stem ? fil : nil })
        XCTAssertFalse(NightChoice.lacksLayers(source: .k18, layers: ur?.layers))
    }
}
