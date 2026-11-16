// RITAR D2-VYERNA TILL PNG (BESLUT B62, B63): Natten, Återhämtning och måttet över natten, också utan baslinje, utan
// stadier, utan K18 och en gång med påhittade huvudtal i platserna för spåret H (bara här). Morgon och trendvyn ritas i
// IdunnProv.swift, som förut.
//
// DATAN ÄR PÅHITTAD (`DemoData`) och räknas av IdunnProv (`IdunnProv.laddaDemo()`), en gång för alla bilder: nätter slag för
// slag ur K18 med stadier, ljud och lager, och äldre nätter som samlade tal. Riktig hälsodata får aldrig in här —
// CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvViz.

import XCTest
import SwiftUI
import UIKit
import DemoData
import HeartRate
import Night
import Sound
import WhoopFrames
@testable import Idunn

@MainActor
final class IdunnProvD2: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// Idunns nätter som vyerna ser dem: de räknade och de äldre dagarnas K18-bara tal (METOD M42).
    private func värden(_ d: IdunnProv.Demo) -> Trends.Values {
        Trends.idunValues(d.summaries.compactMap(\.idunNight) + d.history)
    }

    /// Bara de fem senaste nätterna: normalområdet kräver sju (BESLUT B69), så banden saknas.
    private func ungaVärden(_ d: IdunnProv.Demo) -> Trends.Values {
        let nätter: [Trends.IdunNight] = d.summaries.compactMap(\.idunNight) + d.history
        let nyaste: [Trends.IdunNight] = Array(nätter.sorted { (a: Trends.IdunNight, b: Trends.IdunNight) -> Bool in
            a.day > b.day
        }.prefix(5))
        return Trends.idunValues(nyaste)
    }

    // MARK: Natten

    func test1Natten() throws {
        let d = try IdunnProv.laddaDemo()
        let r = d.latestK18
        let dag: WakeDay = try XCTUnwrap(r.wakeDay)
        let nätter: [WakeDay: NightSummary] = MorningCardView.nights(d.summaries)
        let natt: NightSummary = try XCTUnwrap(nätter[dag])
        let paket: NightLoader.CurveBundle = try XCTUnwrap(d.bundles[dag])
        let v: Trends.Values = värden(d)

        // Det Natten visar finns i sammanfattningen och har sitt normalområde.
        let e: Double = try XCTUnwrap(natt.efficiency, "effektiviteten")
        XCTAssertTrue((50...100).contains(e), "effektivitet \(e)")
        XCTAssertNotNil(natt.wakeBouts, "antalet vakna stunder")
        XCTAssertNotNil(natt.awakeMinutes, "vaken-minuterna")
        XCTAssertLessThan(try XCTUnwrap(natt.onsetMinutes), try XCTUnwrap(natt.wakeMinutes), "insomning före uppvaknande")
        XCTAssertFalse(try XCTUnwrap(paket.layers).stages.isEmpty, "stadierna")
        for m in [Trends.Measure.deepSleep, .remSleep, .lightSleep, .awakeTime, .sleepOnset, .sleepWake, .meanHeartRate,
                  .movement, .snoring] {
            let rad: MorningCard.Row = try XCTUnwrap(MorningCard.nightRow(m, day: dag, idun: v), "\(m)")
            XCTAssertNotNil(rad.range, "\(m): normalområdet")
        }
        XCTAssertNil(Huvudtal.tom.recovery)
        XCTAssertNil(Huvudtal.tom.sleepScore)

        let huvud: Huvudtal = IdunnProv.påhittadeHuvudtal(slut: dag)
        try rendera(NightStack(summary: natt, bundle: paket, values: v), namn: "natten")
        try rendera(NightStack(summary: natt, bundle: paket, values: v, huvudtal: huvud), namn: "natten-huvudtal")
        // Utan baslinje: bara tolv nätter, så banden saknas och pricken hamnar på axeln.
        try rendera(NightStack(summary: natt, bundle: paket, values: ungaVärden(d)), namn: "natten-utan-baslinje")
        // Utan stadier: lagren saknar bandet, och sammanfattningen saknar stadiernas minuter.
        var utanStadier: NightSummary = natt
        utanStadier.lightMinutes = nil
        utanStadier.deepMinutes = nil
        utanStadier.remMinutes = nil
        utanStadier.awakeMinutes = nil
        var paketUtanStadier: NightLoader.CurveBundle = paket
        paketUtanStadier.layers?.stages = []
        try rendera(NightStack(summary: utanStadier, bundle: paketUtanStadier, values: v), namn: "natten-utan-stadier")
        // Utan K18: en gammal inspelning har en kurva men inga lager, ingen period, inga stadier.
        let gammal: NightSummary = try XCTUnwrap(d.oldSummaries.first)
        let gammalKurva: NightLoader.CurveBundle? = d.latest.curve.map { (c: NightCurve.Curve) -> NightLoader.CurveBundle in
            NightLoader.CurveBundle(curve: c, layers: nil)
        }
        try rendera(NightStack(summary: gammal, bundle: gammalKurva, values: v), namn: "natten-utan-k18")

        try fånga(NavigationStack {
            ScrollView { NightStack(summary: natt, bundle: paket, values: v) }
                .background(Tema.bg)
                .navigationTitle("Natten")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-natten", höjd: 4_200)
        try fånga(NavigationStack {
            ScrollView { NightStack(summary: natt, bundle: paket, values: v, huvudtal: huvud) }
                .background(Tema.bg)
                .navigationTitle("Natten")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-natten-huvudtal", höjd: 4_200)
    }

    // MARK: Återhämtning

    func test2Aterhamtning() throws {
        let d = try IdunnProv.laddaDemo()
        let dag: WakeDay = try XCTUnwrap(d.latestK18.wakeDay)
        let natt: NightSummary? = MorningCardView.nights(d.summaries)[dag]
        let v: Trends.Values = värden(d)
        let huvud: Huvudtal = IdunnProv.påhittadeHuvudtal(slut: dag)
        XCTAssertNotNil(MorningCard.nightRow(.hrv, day: dag, idun: v)?.range, "HRV mot ditt normala")
        try rendera(RecoveryStack(day: dag, values: v, summary: natt), namn: "aterhamtning")
        try rendera(RecoveryStack(day: dag, values: v, summary: natt, huvudtal: huvud), namn: "aterhamtning-huvudtal")
        try rendera(RecoveryStack(day: dag, values: ungaVärden(d), summary: natt), namn: "aterhamtning-utan-baslinje")
        try fånga(NavigationStack {
            ScrollView { RecoveryStack(day: dag, values: v, summary: natt) }
                .background(Tema.bg)
                .navigationTitle("Återhämtning")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-aterhamtning", höjd: 2_500)
        try fånga(NavigationStack {
            ScrollView { RecoveryStack(day: dag, values: v, summary: natt, huvudtal: huvud) }
                .background(Tema.bg)
                .navigationTitle("Återhämtning")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-aterhamtning-huvudtal", höjd: 2_500)
    }

    // MARK: Måttet över natten

    func test3Matt() throws {
        let d = try IdunnProv.laddaDemo()
        let dag: WakeDay = try XCTUnwrap(d.latestK18.wakeDay)
        let natt: NightSummary = try XCTUnwrap(MorningCardView.nights(d.summaries)[dag])
        let paket: NightLoader.CurveBundle = try XCTUnwrap(d.bundles[dag])
        let kurva: NightCurve.Curve = paket.curve
        let v: Trends.Values = värden(d)
        let typisk: NightCurve.Typical? = NightCurveView.typical(kurva, stem: natt.stem, summaries: d.summaries)
        let typiskt: NightCurve.Typical = try XCTUnwrap(typisk, "den typiska natten")
        XCTAssertFalse(typiskt.rmssd.isEmpty, "HRV:s band")
        XCTAssertFalse(typiskt.skin.isEmpty, "hudtemperaturens band (METOD M49)")
        XCTAssertNotNil(paket.sound, "den senaste natten har ljud")
        let finnsKlipp: (NightSound.Clip) -> Bool = { (_: NightSound.Clip) -> Bool in true }

        // BESLUT B131 · METOD M76. Nattens två halvor under Nattens HRV: ur demonätterna som appen räknar dem
        // (`matt-hrv-halvor`), och med påhittade halvor där natten börjar lågt och kvällen har taggar
        // (`matt-hrv-lag-borjan`).
        let halvor = Natthalvor(d.summaries)
        XCTAssertNotNil(halvor.första[dag], "den senaste natten har en första halva")
        XCTAssertNotNil(halvor.andra[dag], "den senaste natten har en andra halva")
        try rendera(NightMetricStack(metric: .hrv, summary: natt, bundle: paket, typical: typisk, values: v, halvor: halvor),
                    namn: "matt-hrv-halvor")
        var första: [WakeDay: Double] = [:]
        var andra: [WakeDay: Double] = [:]
        for i in 1...35 {
            let före = WakeDay(daysSince1970: dag.daysSince1970 - i)
            första[före] = 50 + Double(i % 5)
            andra[före] = 62 + Double(i % 4)
        }
        första[dag] = 33
        andra[dag] = 64
        let lågBörjan = Natthalvor(första: första, andra: andra)
        XCTAssertEqual(lågBörjan.text(dag: dag, taggar: ["styrkepass", "sen måltid"]),
                       "Låg i början av natten, återhämtad mot morgonen. Kvällen före: styrkepass, sen måltid.")
        try rendera(NightMetricStack(metric: .hrv, summary: natt, bundle: paket, typical: typisk, values: v,
                                     halvor: lågBörjan, taggar: ["styrkepass", "sen måltid"]),
                    namn: "matt-hrv-lag-borjan")

        let namn: [NightMetric: String] = [.hrv: "hrv", .temp: "hudtemp", .resp: "andning", .move: "rorelse", .ljud: "ljud"]
        for m in NightMetric.allCases {
            let n: String = namn[m] ?? m.rawValue
            let stack = NightMetricStack(metric: m, summary: natt, bundle: paket, typical: typisk, values: v)
                .environment(\.clipExists, finnsKlipp)
            try rendera(stack, namn: "matt-" + n)
            try fånga(NavigationStack {
                ScrollView {
                    NightMetricStack(metric: m, summary: natt, bundle: paket, typical: typisk, values: v)
                        .environment(\.clipExists, finnsKlipp)
                }
                .background(Tema.bg)
                .navigationTitle(m.title + " i natt")
                .navigationBarTitleDisplayMode(.inline)
            }, namn: "skarm-matt-" + n, höjd: m == .ljud ? 1_900 : 1_500)
        }

        // Utan baslinje: inga normalområden, ingen vanlig natt som band.
        try rendera(NightMetricStack(metric: .temp, summary: natt, bundle: paket, typical: nil, values: ungaVärden(d)),
                    namn: "matt-hudtemp-utan-baslinje")
        try rendera(NightMetricStack(metric: .hrv, summary: natt, bundle: paket, typical: nil, values: ungaVärden(d)),
                    namn: "matt-hrv-utan-baslinje")
        // Utan K18: en gammal inspelning har HRV och andning men varken hudtemperatur, rörelse eller ljud i kurvan.
        let gammal: NightSummary = try XCTUnwrap(d.oldSummaries.first)
        let gammalKurva: NightLoader.CurveBundle? = d.latest.curve.map { (c: NightCurve.Curve) -> NightLoader.CurveBundle in
            NightLoader.CurveBundle(curve: c, layers: nil)
        }
        try rendera(NightMetricStack(metric: .hrv, summary: gammal, bundle: gammalKurva, typical: nil, values: v),
                    namn: "matt-hrv-utan-k18")
        try rendera(NightMetricStack(metric: .temp, summary: gammal, bundle: gammalKurva, typical: nil, values: v),
                    namn: "matt-hudtemp-utan-k18")
        // En natt utan ljud: diagrammet säger det i stället för att tiga.
        let tystDag: WakeDay = dag - 4
        let tystNatt: NightSummary = try XCTUnwrap(MorningCardView.nights(d.summaries)[tystDag])
        try rendera(NightMetricStack(metric: .ljud, summary: tystNatt, bundle: d.bundles[tystDag], typical: nil, values: v),
                    namn: "matt-ljud-utan-ljud")
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
        // Natten är lång: i provet 2026-11-07 gav @3x ingen bild alls (skarm-natten i fönstret gick). En lägre
        // skala får hela längden att rymmas; skalan står i loggen.
        for skala in [3.0, 2.0, 1.0] as [CGFloat] {
            let r = ImageRenderer(content: innehåll)
            r.scale = skala
            r.proposedSize = ProposedViewSize(width: Self.bredd, height: nil)
            if let bild = r.uiImage, let png = bild.pngData() {
                try skriv(png, namn: namn, storlek: bild.size, skala: bild.scale)
                return
            }
            print("PROV: \(namn) gick inte att rita @\(Int(skala))x")
        }
        XCTFail("kunde inte rita \(namn)")
    }

    /// Ett riktigt fönster: navigationsrubrik och rullning som på telefonen.
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
        // Natten i fönstret (4 200 pt) blev helt vit @3x i provet 2026-11-07, medan 2 700 pt (8 100 px) gick:
        // en lång bild får lägre skala så att den håller sig under 8 100 px.
        format.scale = min(3, 8_100 / höjd)
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
