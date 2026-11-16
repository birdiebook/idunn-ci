// RITAR NATTENS FÄRGER TILL PNG (BESLUT B83, METOD M58): kurvan med ett valt stadium (djup, REM, vaken), sömnbristens
// staplar i lägets färg med dagar per läge, Sömn mot behov med dagar per läge, och en natt där början eller slutet
// saknas. Lägenas gränser och räkningen prövas med tal.
//
// DATAN ÄR PÅHITTAD (`DemoData` via `IdunnProv.laddaDemo()`, och `IdunnProv.påhittadeHuvudtal`). Riktig hälsodata får
// aldrig in här — CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvD2.

import XCTest
import SwiftUI
import UIKit
import DemoData
import Night
@testable import Idunn

@MainActor
final class IdunnProvNatten: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    private struct Natt {
        var summary: NightSummary
        var bundle: NightLoader.CurveBundle
        var values: Trends.Values
        var dag: WakeDay
    }

    private func senaste() throws -> Natt {
        let d = try IdunnProv.laddaDemo()
        let dag: WakeDay = try XCTUnwrap(d.latestK18.wakeDay)
        let natt: NightSummary = try XCTUnwrap(MorningCardView.nights(d.summaries)[dag])
        let paket: NightLoader.CurveBundle = try XCTUnwrap(d.bundles[dag])
        return Natt(summary: natt, bundle: paket,
                    values: Trends.idunValues(d.summaries.compactMap(\.idunNight) + d.history), dag: dag)
    }

    // MARK: Lägena och räkningen

    func test1LägenasGränser() throws {
        // Sömnbristen på hela minuter, som talet står utskrivet: 0:44 låg, 0:45 och 1:30 måttlig, 1:31 hög (B91).
        XCTAssertEqual(Skuldläge(44.4 / 60), .låg)
        XCTAssertEqual(Skuldläge(44.6 / 60), .måttlig)
        XCTAssertEqual(Skuldläge(0.75), .måttlig)
        XCTAssertEqual(Skuldläge(1.5), .måttlig)
        XCTAssertEqual(Skuldläge(90.6 / 60), .hög)
        XCTAssertEqual(Skuldläge(0), .låg)
        // Sömn mot behov på hela procent: 85 optimal, 84 och 70 tillräcklig, 69 dålig.
        XCTAssertEqual(Behovsläge(84.6), .optimal)
        XCTAssertEqual(Behovsläge(84.4), .tillräcklig)
        XCTAssertEqual(Behovsläge(70), .tillräcklig)
        XCTAssertEqual(Behovsläge(69.4), .dålig)
        XCTAssertEqual(Behovsläge(120), .optimal)
        // Dagar per läge, i lägenas ordning; en dag utan värde räknas inte.
        XCTAssertEqual(Lägesräkning.antal([0.2, nil, 1.0, 2.0, 1.8]) { (v: Double) -> Skuldläge in Skuldläge(v) },
                       [1, 1, 2])
        XCTAssertEqual(Lägesräkning.antal([nil, nil]) { (v: Double) -> Skuldläge in Skuldläge(v) }, [0, 0, 0])
        XCTAssertEqual(NightStack.andelar([7, nil, 6, 8], [8, 8, nil, 0]), [87.5, nil, nil, nil])
        XCTAssertEqual(Lägesräkning.antal([90, 75, 50, nil]) { (p: Double) -> Behovsläge in Behovsläge(p) }, [1, 1, 1])
    }

    // MARK: Kurvan med ett valt stadium

    func test2KurvanMedValtStadium() throws {
        let n = try senaste()
        let stadier: [NightLayers.StageSpan] = try XCTUnwrap(n.bundle.layers).stages
        for s in [SleepStage.deep, .rem] {
            XCTAssertTrue(stadier.contains { $0.stage == s }, "natten har \(s)")
        }
        try rendera(NightStack(summary: n.summary, bundle: n.bundle, values: n.values, stadium: .deep),
                    namn: "natten-stadium-djup")
        try rendera(NightStack(summary: n.summary, bundle: n.bundle, values: n.values, stadium: .rem),
                    namn: "natten-stadium-rem")
        try rendera(NightStack(summary: n.summary, bundle: n.bundle, values: n.values, stadium: .wake),
                    namn: "natten-stadium-vaken")
        // Ett valt stadium som natten saknar: kurvan som vanligt.
        var utanStadier: NightLoader.CurveBundle = n.bundle
        utanStadier.layers?.stages = []
        try rendera(NattKurva(curve: n.bundle.curve, layers: utanStadier.layers, höjd: 220, axel: true, valt: .deep),
                    namn: "nattkurva-valt-utan-stadier")
        try fånga(NavigationStack {
            ScrollView { NightStack(summary: n.summary, bundle: n.bundle, values: n.values, stadium: .deep) }
                .background(Tema.bg)
                .navigationTitle("Natten")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-natten-stadium", höjd: 900)
    }

    // MARK: Sömnbristen i färg och dagar per läge

    func test3SömnbristOchSömnMotBehov() throws {
        let n = try senaste()
        let huvud: Huvudtal = IdunnProv.påhittadeHuvudtal(slut: n.dag)
        let brist: [Double?] = huvud.last("debt", days: 7, ending: n.dag)
        let lägen: [Int] = Lägesräkning.antal(brist) { (v: Double) -> Skuldläge in Skuldläge(v) }
        XCTAssertEqual(lägen.reduce(0, +), brist.compactMap { $0 }.count, "varje dag med skuld i ett läge")
        let sömn: [Double?] = (0..<7).map { (k: Int) -> Double? in (n.values[.sleep] ?? [:])[n.dag - (6 - k)] }
        let andel: [Double?] = NightStack.andelar(sömn, huvud.last("need", days: 7, ending: n.dag))
        let behovslägen: [Int] = Lägesräkning.antal(andel) { (p: Double) -> Behovsläge in Behovsläge(p) }
        XCTAssertEqual(behovslägen.reduce(0, +), andel.compactMap { $0 }.count)
        print("PROV: sömnbrist per läge (låg, måttlig, hög) \(lägen), sömn mot behov (optimal, tillräcklig, dålig) "
              + "\(behovslägen) med påhittade tal")
        try rendera(NightStack(summary: n.summary, bundle: n.bundle, values: n.values, huvudtal: huvud),
                    namn: "natten-lagen")
        try fånga(NavigationStack {
            ScrollView { NightStack(summary: n.summary, bundle: n.bundle, values: n.values, huvudtal: huvud) }
                .background(Tema.bg)
                .navigationTitle("Natten")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-natten-lagen", höjd: 4_600)
    }

    // MARK: En natt där början eller slutet saknas

    func test4OfullständigNatt() throws {
        let n = try senaste()
        var början: NightSummary = n.summary
        början.incompleteStart = true
        början.incompleteEnd = false
        var slutet: NightSummary = n.summary
        slutet.incompleteStart = false
        slutet.incompleteEnd = true
        try rendera(NightStack(summary: början, bundle: n.bundle, values: n.values), namn: "natten-borjan-saknas")
        try rendera(NightStack(summary: slutet, bundle: n.bundle, values: n.values), namn: "natten-slutet-saknas")
        // BESLUT B125. Samma natt som preliminär: i stället för "slutet saknas" står hur långt datan når.
        var preliminär: NightSummary = slutet
        preliminär.preliminary = true
        try rendera(NightStack(summary: preliminär, bundle: n.bundle, values: n.values), namn: "natten-preliminar")
        try fånga(NavigationStack {
            ScrollView { NightStack(summary: början, bundle: n.bundle, values: n.values) }
                .background(Tema.bg)
                .navigationTitle("Natten")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-natten-borjan-saknas", höjd: 900)
    }

    // MARK: Ritverktygen (som IdunnProvD2)

    private func rendera(_ vy: some View, namn: String) throws {
        let innehåll = vy
            .frame(width: Self.bredd)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tema.bg)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "sv_SE"))
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
