// RITAR SÖMNPOÄNGEN OCH ÅTERHÄMTNINGEN TILL PNG (BESLUT B65, B71, B72, METOD M56, M57): ringarna på Morgon,
// Sömnpoängen med tre delar på Natten, Återhämtning med ringen, Vad som drog och veckan, och knapparna Sömnpoäng och
// Återhämtning i trendvyn, räknade av appens egen väg (`SömnbehovModell.huvudtal`) ur påhittade nätter. En gång till
// med bara en natt: sömnpoängen utan regelbundenhet och ingen återhämtning (talen fylls i direkt, B65).
//
// DATAN ÄR PÅHITTAD (`DemoData` via `IdunnProv.laddaDemo()`). Riktig hälsodata får aldrig in här — CLAUDE.md
// §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvH1.

import XCTest
import SwiftUI
import UIKit
import DemoData
import Night
import SleepNeed
@testable import Idunn

@MainActor
final class IdunnProvH23: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393
    static let zon: TimeZone = TimeZone(secondsFromGMT: 3600) ?? .current

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    private func idunNätter(_ d: IdunnProv.Demo) -> [Trends.IdunNight] {
        d.summaries.compactMap(\.idunNight) + d.history
    }

    // MARK: Sömnpoängen och återhämtningen ur alla påhittade nätter

    func test1PoangenOchAterhamtningen() throws {
        let d = try IdunnProv.laddaDemo()
        let nätter: [Trends.IdunNight] = idunNätter(d)
        let värden: Trends.Values = Trends.idunValues(nätter)
        let dagar: [MorningCard.Day] = MorningCard.days(idun: värden)
        let kort: MorningCard.Day = try XCTUnwrap(dagar.last)
        let dag: WakeDay = kort.day
        let sammanfattningar: [WakeDay: NightSummary] = MorningCardView.nights(d.summaries)
        let senaste: NightSummary = try XCTUnwrap(sammanfattningar[dag])
        let paket: NightLoader.CurveBundle? = d.bundles[dag]

        let h: Huvudtal = SömnbehovModell.huvudtal(nätter: nätter, pass: [], zon: Self.zon)
        let v: Huvudtal = h.för(dag)
        let poäng: Int = try XCTUnwrap(v.sleepScore, "sömnpoängen för morgonen")
        let åter: Int = try XCTUnwrap(v.recovery, "återhämtningen för morgonen")
        XCTAssertTrue((0...100).contains(poäng))
        XCTAssertTrue((0...100).contains(åter))
        let delar: [Double?] = try XCTUnwrap(v.scoreParts)
        XCTAssertEqual(delar.count, 3, "mängd, kontinuitet och regelbundenhet")
        let finns: [Double] = delar.compactMap { $0 }
        XCTAssertEqual(finns.count, 3, "efter flera nätter finns alla tre delarna")
        XCTAssertEqual(Double(poäng), finns.reduce(0, +) / Double(finns.count), accuracy: 0.5, "lika vikter")
        let drag: [Double?] = try XCTUnwrap(v.drags)
        XCTAssertEqual(drag.count, 3, "HRV, Vilopuls och Sömn")
        let summa: Double = RecoveryRules.middle + drag.compactMap { $0 }.reduce(0, +)
        XCTAssertEqual(Double(åter), min(100, max(0, summa)), accuracy: 0.5, "bidragen summerar med mitten")
        XCTAssertEqual(h.series["sleepScore"]?[dag].map { Int($0.rounded()) }, poäng)
        XCTAssertEqual(h.series["recovery"]?[dag].map { Int($0.rounded()) }, åter)
        // Natt 1 har ingen återhämtning (ingen baslinje), och den första natten med sömnpoäng ingen regelbundenhet.
        let förstaNatt: WakeDay = try XCTUnwrap(Trends.idunPerDay(nätter).keys.min())
        XCTAssertNil(h.perDayScore[förstaNatt]?.recovery, "återhämtningen från natt 2")
        let förstaSömn: WakeDay = try XCTUnwrap(h.series["sleepScore"]?.keys.min())
        let p1: Huvudtal.Poängdag = try XCTUnwrap(h.perDayScore[förstaSömn])
        XCTAssertEqual(p1.scoreParts?.count, 3)
        XCTAssertNil(p1.scoreParts?[2] ?? nil, "regelbundenheten från andra natten")
        let delText: String = finns.map { (x: Double) -> String in "\(Int(x.rounded()))" }.joined(separator: "/")
        let dragText: String = drag.map { (x: Double?) -> String in
            x.map { (y: Double) -> String in "\(Int(y.rounded()))" } ?? "–"
        }.joined(separator: "/")
        let andning: String = v.breathingHigh ? ", andningen hög" : ""
        let antalSömn: Int = h.series["sleepScore"]?.count ?? 0
        let antalÅter: Int = h.series["recovery"]?.count ?? 0
        print("PROV: sömnpoäng \(poäng) (\(delText)), återhämtning \(åter) (\(dragText)\(andning)), "
              + "\(antalSömn) nätter med sömnpoäng och \(antalÅter) med återhämtning, ur påhittade nätter")

        try rendera(MorningCardStack(card: kort, summary: senaste, bundle: paket, huvudtal: h), namn: "morgon-poang")
        try rendera(NightStack(summary: senaste, bundle: paket, values: värden, huvudtal: h), namn: "natten-poang")
        try rendera(RecoveryStack(day: dag, values: värden, summary: senaste, huvudtal: v), namn: "aterhamtning-poang")
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: sammanfattningar, bundles: d.bundles, huvudtal: h,
                              loadsCurves: false)
        }, namn: "skarm-morgon-poang", höjd: 1_700)
        try fånga(NavigationStack {
            ScrollView { RecoveryStack(day: dag, values: värden, summary: senaste, huvudtal: v) }
                .background(Tema.bg)
                .navigationTitle("Återhämtning")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-aterhamtning-poang", höjd: 2_400)
        let serier: [Trends.Series] = Trends.series(idun: värden, whoop: [:])
        try rendera(TrendStack(serier: serier, huvudtal: h, mått: .constant(.sleepScore), period: .constant(.month),
                               markerad: .constant(nil)),
                    namn: "trend-somnpoang")
        try rendera(TrendStack(serier: serier, huvudtal: h, mått: .constant(.recovery), period: .constant(.month),
                               markerad: .constant(nil)),
                    namn: "trend-aterhamtning-poang")
    }

    // MARK: Bara en natt: sömnpoängen fylls i direkt, återhämtningen väntar på natt 2

    func test2ForstaNatten() throws {
        let d = try IdunnProv.laddaDemo()
        let nätter: [Trends.IdunNight] = idunNätter(d)
        let dagar: [MorningCard.Day] = MorningCard.days(idun: Trends.idunValues(nätter))
        let kort: MorningCard.Day = try XCTUnwrap(dagar.last)
        let dag: WakeDay = kort.day
        let senaste: NightSummary = try XCTUnwrap(MorningCardView.nights(d.summaries)[dag])
        let natten: Trends.IdunNight = try XCTUnwrap(senaste.idunNight)
        let h: Huvudtal = SömnbehovModell.huvudtal(nätter: [natten], pass: [], zon: Self.zon)
        let v: Huvudtal = h.för(dag)
        XCTAssertNotNil(v.sleepScore, "sömnpoängen från första natten")
        XCTAssertNil(v.recovery, "ingen återhämtning utan en natt före")
        XCTAssertNil(v.drags)
        XCTAssertEqual(v.scoreParts?.compactMap { $0 }.count, 2, "mängd och kontinuitet, ingen regelbundenhet")
        let förstaPoäng: Int = try XCTUnwrap(v.sleepScore)
        print("PROV: första natten sömnpoäng \(förstaPoäng), ingen återhämtning")
        try rendera(MorningCardStack(card: kort, summary: senaste, bundle: d.bundles[dag], huvudtal: h),
                    namn: "morgon-natt1")
        try rendera(NightStack(summary: senaste, bundle: d.bundles[dag], values: Trends.idunValues([natten]),
                               huvudtal: h),
                    namn: "natten-natt1")
    }

    // MARK: Ritverktygen (som IdunnProvH1)

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
