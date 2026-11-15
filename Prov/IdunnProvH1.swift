// RITAR SÖMNBEHOVET TILL PNG (BESLUT B64, B65, B67, METOD M53): Behov, Ikväll med grundbehov och sömnbrist, Sömnbehov
// och Sömnbrist i trendvyn, räknade av appens egen väg (`SömnbehovModell.huvudtal`) ur påhittade nätter (sedan H2 och
// H3 med ringarna, som prövas i IdunnProvH23). Ett påhittat grundbehov ur exporten prövar uppdateringen.
//
// DATAN ÄR PÅHITTAD (`DemoData` via `IdunnProv.laddaDemo()`, och exportens grundbehov 510 min nedan). Riktig hälsodata får
// aldrig in här — CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvD2.

import XCTest
import SwiftUI
import UIKit
import DemoData
import Night
import SleepNeed
@testable import Idunn

@MainActor
final class IdunnProvH1: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393
    static let zon: TimeZone = TimeZone(secondsFromGMT: 3600) ?? .current

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    private func idunNätter(_ d: IdunnProv.Demo) -> [Trends.IdunNight] {
        d.summaries.compactMap(\.idunNight) + d.history
    }

    // MARK: Behov, Ikväll och Sömnbehov

    func test1BehovPaMorgonOchNatten() throws {
        let d = try IdunnProv.laddaDemo()
        let nätter: [Trends.IdunNight] = idunNätter(d)
        let dagar: [MorningCard.Day] = MorningCard.days(idun: Trends.idunValues(nätter))
        let kort: MorningCard.Day = try XCTUnwrap(dagar.last)
        let dag: WakeDay = kort.day
        let sammanfattningar: [WakeDay: NightSummary] = MorningCardView.nights(d.summaries)
        let senaste: NightSummary = try XCTUnwrap(sammanfattningar[dag])
        let paket: NightLoader.CurveBundle? = d.bundles[dag]

        let h: Huvudtal = SömnbehovModell.huvudtal(nätter: nätter, pass: [], zon: Self.zon)
        let räknade: [SleepNight] = SleepNeed.nights(nätter)
        XCTAssertGreaterThan(räknade.count, 30, "nätterna ur K18 med sovtid och period")
        let b: Huvudtal.Behovsdag = try XCTUnwrap(h.perDay[dag], "morgonens sömnbehov")
        XCTAssertEqual(b.need, b.base + b.pass + b.debtPart, accuracy: 1e-9, "raderna går jämnt upp")
        XCTAssertLessThanOrEqual(b.debtPart, SleepNeedRules.debtInTonightCapMinutes / 60 + 1e-9)
        XCTAssertNotNil(b.bedtime, "läggdags ikväll")
        XCTAssertNotNil(b.bedtimeFull, "läggdags för full sömn")
        XCTAssertLessThanOrEqual(b.tonightBaseSD, SleepNeedRules.priorBaseSDMinutes / 60 + 1e-9, "SD krymper eller står")
        XCTAssertEqual(h.series["debt"]?.count, h.perDay.count)
        let v: Huvudtal = h.för(dag)
        XCTAssertEqual(v.needHours, b.need)
        XCTAssertEqual(v.debtHours, b.debt)
        // Sömnpoängen (H2) och återhämtningen (H3) räknas också nu; de prövas i IdunnProvH23.
        print("PROV: sömnbehov \(Fmt.hm(hours: b.need)), grundbehov \(Fmt.hm(hours: b.tonightBase))"
              + Fmt.plusMinus(hours: b.tonightBaseSD) + ", skuld \(Fmt.hm(hours: b.debt)), läggdags "
              + (b.bedtime.map { Fmt.clock(minutes: $0) } ?? "–") + " ur \(räknade.count) påhittade nätter")

        try rendera(MorningCardStack(card: kort, summary: senaste, bundle: paket, huvudtal: h), namn: "morgon-behov")
        try rendera(NightStack(summary: senaste, bundle: paket, values: Trends.idunValues(nätter), huvudtal: h),
                    namn: "natten-behov")
        try fånga(NavigationStack {
            MorningCardScreen(days: dagar, summaries: sammanfattningar, bundles: d.bundles, huvudtal: h,
                              loadsCurves: false)
        }, namn: "skarm-morgon-behov", höjd: 1_500)
        try fånga(NavigationStack {
            ScrollView { NightStack(summary: senaste, bundle: paket, values: Trends.idunValues(nätter), huvudtal: h) }
                .background(Tema.bg)
                .navigationTitle("Natten")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-natten-behov", höjd: 3_600)
        // Sömnbrist i trendvyn: hela skulden per natt.
        let serier: [Trends.Series] = Trends.series(idun: Trends.idunValues(nätter), whoop: [:])
        try rendera(TrendStack(serier: serier, huvudtal: h, mått: .constant(.debt), period: .constant(.month),
                               markerad: .constant(nil)),
                    namn: "trend-somnbrist")
    }

    // MARK: Grundbehovet med exportens tal

    func test2GrundbehovetMedExportensTal() throws {
        let d = try IdunnProv.laddaDemo()
        let nätter: [Trends.IdunNight] = idunNätter(d)
        let dag: WakeDay = try XCTUnwrap(MorningCard.days(idun: Trends.idunValues(nätter)).last).day
        let utan: Huvudtal.Behovsdag = try XCTUnwrap(SömnbehovModell.huvudtal(nätter: nätter, pass: [], zon: Self.zon)
            .perDay[dag])
        XCTAssertEqual(utan.base * 60, SleepNeedRules.priorBaseMinutes, accuracy: 1e-9, "priorn 8 h")
        XCTAssertEqual(utan.baseSD * 60, SleepNeedRules.priorBaseSDMinutes, accuracy: 1e-9)
        // Ett påhittat grundbehov ur exporten, 510 min: 0,2 × 480 + 0,8 × 510 = 504 ± 13 min.
        let med: Huvudtal.Behovsdag = try XCTUnwrap(SömnbehovModell.huvudtal(nätter: nätter, pass: [], grundUtifrån: 510,
                                                                           zon: Self.zon).perDay[dag])
        XCTAssertEqual(med.base * 60, 504, accuracy: 1e-6)
        XCTAssertLessThan(med.baseSD * 60, 14)
        print("PROV: grundbehov med exportens tal \(Fmt.hm(hours: med.base))" + Fmt.plusMinus(hours: med.baseSD))
    }

    // MARK: Upp i morgon (BESLUT B74)

    func test3SattVäcktid() throws {
        let d = try IdunnProv.laddaDemo()
        let nätter: [Trends.IdunNight] = idunNätter(d)
        let dagar: [MorningCard.Day] = MorningCard.days(idun: Trends.idunValues(nätter))
        let kort: MorningCard.Day = try XCTUnwrap(dagar.last)
        let senaste: NightSummary = try XCTUnwrap(MorningCardView.nights(d.summaries)[kort.day])
        let vanlig: Huvudtal = SömnbehovModell.huvudtal(nätter: nätter, pass: [], zon: Self.zon)
        let satt: Huvudtal = SömnbehovModell.huvudtal(nätter: nätter, pass: [], väcktid: 390, zon: Self.zon)
        let a: Huvudtal.Behovsdag = try XCTUnwrap(vanlig.perDay[kort.day])
        let b: Huvudtal.Behovsdag = try XCTUnwrap(satt.perDay[kort.day])
        XCTAssertNil(vanlig.wakeSet)
        XCTAssertEqual(satt.wakeSet, 390)
        XCTAssertEqual(b.wake, 390)
        XCTAssertEqual(b.need, a.need, accuracy: 1e-9, "behovet rörs inte av väcktiden")
        XCTAssertEqual(b.debt, a.debt, accuracy: 1e-9, "skulden rörs inte av väcktiden")
        let före: Double = try XCTUnwrap(a.bedtime)
        let efter: Double = try XCTUnwrap(b.bedtime)
        // Läggdags för full sömn följer väcktiden minut för minut; läggdags för bästa poäng (BESLUT B75, i `bedtime`)
        // väger också in regelbundenheten och ligger i fönstret 12–4 h före väcktiden.
        let föreFull: Double = try XCTUnwrap(a.bedtimeFull)
        let efterFull: Double = try XCTUnwrap(b.bedtimeFull)
        XCTAssertEqual(efterFull - föreFull, 390 - (a.wake ?? 390), accuracy: 1e-9,
                       "läggdags för full sömn följer väcktiden minut för minut")
        XCTAssertGreaterThanOrEqual(efter, 390 - 60 * SleepNeedRules.bestBedtimeEarliestHoursBeforeWake - 1e-9)
        XCTAssertLessThanOrEqual(efter, 390 - 60 * SleepNeedRules.bestBedtimeLatestHoursBeforeWake + 1e-9)
        XCTAssertNotNil(b.tonightAsleep, "sovtiden som läggdags ger")
        print("PROV: läggdags \(Fmt.clock(minutes: före)) vanlig, \(Fmt.clock(minutes: efter)) med upp 06:30 "
              + "(full sömn \(Fmt.clock(minutes: föreFull)) och \(Fmt.clock(minutes: efterFull)))")

        try rendera(MorningCardStack(card: kort, summary: senaste, bundle: d.bundles[kort.day], huvudtal: satt),
                    namn: "morgon-vaknatid")
        // BESLUT B102. Bladet med dagknapparna. Dag 20 409 är en måndag: vardagarna 06:30 och helgen 08:30.
        let vecka: WakeSchedule = WakeSchedule(every: 390).setting(510, weekdays: [5, 6])
        try fånga(VäcktidBlad(val: Väcktidsval(start: 390, schema: vecka, uppdag: 20_409, engångGår: true)),
                  namn: "blad-vaknatid", höjd: 800)
        // Bara i morgon: en engångstid för måndagen, och påminnelsen före läggdags påslagen (BESLUT B103).
        try fånga(VäcktidBlad(val: Väcktidsval(start: 300, schema: vecka.settingOnce(300, wakeDay: 20_409),
                                               uppdag: 20_409, engångGår: true), påminnelse: true),
                  namn: "blad-vaknatid-bara-i-morgon", höjd: 800)
        XCTAssertEqual(VäcktidBlad.dagtext([0, 1, 2, 3, 4]), "mån–fre")
        XCTAssertEqual(VäcktidBlad.dagtext([0, 2, 5, 6]), "mån, ons, lör–sön")
        XCTAssertEqual(VäcktidBlad.dagtext([0, 1, 2, 3, 4, 5, 6]), "alla dagar")
        // BESLUT B81. Bladen fångas ur ett riktigt fönster: systemets tidshjul ritas inte av `ImageRenderer`.
        // BESLUT B80. Bladet med uträkningen: behovet ur sina delar, effektiviteten, tiden att somna och läggdags.
        let uträkning: Huvudtal.Kvällsuträkning = try XCTUnwrap(b.kväll, "kvällens uträkning")
        XCTAssertEqual(uträkning.tider(upp: 390).full, efterFull, accuracy: 1e-6, "uträkningen ger läggdags för full sömn")
        XCTAssertEqual(uträkning.tider(upp: 390).bästa, efter, accuracy: 1e-6, "och läggdags för bästa poäng")
        try fånga(VäcktidBlad(val: Väcktidsval(start: 390, schema: WakeSchedule(every: 390), uppdag: 20_409,
                                               engångGår: true, uträkning: uträkning)),
                  namn: "blad-vaknatid-utrakning", höjd: 1_300)
        try fånga(VäcktidBlad(val: Väcktidsval(start: Int((a.wake ?? 420).rounded()), uppdag: 20_409)),
                  namn: "blad-vaknatid-vanlig", höjd: 700)
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
