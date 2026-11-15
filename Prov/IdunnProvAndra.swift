// RITAR "ÄNDRA SÖMNEN" TILL PNG (BESLUT B70, METOD M55): Natten för en natt där användaren ändrat när han somnade, med
// märket vid Sömnperiod och knappen Ändra uppe till höger, och bladet med de två tidshjulen (som det öppnar, med
// Återställ, och med vaknade före somnade).
//
// DATAN ÄR PÅHITTAD (`DemoData`): den senaste påhittade natten ur IdunnProv (`IdunnProv.laddaDemo()`) räknas om med en
// senare insomning genom samma väg som appen (`K18Night.analyze(…, edit:)`, `NightDigest`, `NightSummary`). Riktig
// hälsodata får aldrig in här — CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvD2.

import XCTest
import SwiftUI
import UIKit
import DemoData
import HeartRate
import Night
import WhoopFrames
@testable import Idunn

@MainActor
final class IdunnProvAndra: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    // MARK: Natten, ändrad

    func test1NattenAndrad() throws {
        let d = try IdunnProv.laddaDemo()
        let r0: NightResult = d.latestK18
        let dag: WakeDay = try XCTUnwrap(r0.wakeDay)
        let zon: Int = r0.utcOffsetSeconds
        let p: SleepPeriod = try XCTUnwrap(r0.sleep)
        let gammal: NightSummary = try XCTUnwrap(MorningCardView.nights(d.summaries)[dag])
        XCTAssertFalse(gammal.isEdited, "den hittade natten är inte märkt")
        XCTAssertTrue(gammal.canEditSleep, "en natt ur bandet går att ändra")

        // Samma påhittade natt som IdunnProv räknar som den senaste, nu med insomningen 50 minuter senare.
        let natt = DemoK18Nights.night(daysBeforeLast: 0, movementBout: true, stages: true)
        let serie = K18Series(records: natt.records)
        let på: Int = SleepEdit.clockMinutes(p.onset, wakeDay: dag, utcOffsetSeconds: zon) + 50
        let av: Int = SleepEdit.clockMinutes(p.wake, wakeDay: dag, utcOffsetSeconds: zon)
        let e: SleepEdit = try SleepEdit.make(wakeDay: dag, onsetMinutes: på, wakeMinutes: av, utcOffsetSeconds: zon,
                                              foundOnset: p.onset, foundWake: p.wake)
        let r: NightResult = try XCTUnwrap(K18Night.analyze(serie, wakeDay: dag, startOffsetSeconds: zon,
                                                            endOffsetSeconds: zon, edit: e))
        XCTAssertEqual(r.sleep?.onset, e.onset, "natten börjar vid den ändrade insomningen")
        XCTAssertEqual(r.edit, e)
        XCTAssertNotNil(r.layers, "lagren räknas för den nya perioden")

        var digest = NightDigest(r)
        digest.sound = gammal.sound
        let ändrad = NightSummary(digest: digest, stem: K18Nights.stem(dag), build: "prov")
        XCTAssertTrue(ändrad.isEdited, "märket")
        XCTAssertEqual(ändrad.id, gammal.id, "samma natt, så att Natten visar den nya")
        XCTAssertLessThan(try XCTUnwrap(ändrad.sleepMinutes), try XCTUnwrap(gammal.sleepMinutes))

        // Bladet öppnar med ändringen, och den hittade perioden följer med till nästa ändring.
        let från = try XCTUnwrap(SömnÄndringBlad.startvärden(ändrad, ändring: e))
        XCTAssertEqual(från.somnade, på)
        XCTAssertEqual(från.vaknade, av)
        XCTAssertEqual(SömnÄndringBlad.hittadPeriod(ändrad), SleepInterval(start: p.onset, end: p.wake))

        // Idunns nätter med den ändrade i stället för den hittade, som `Recorder.summaries` efter omräkningen.
        let alla: [NightSummary] = d.summaries.map { (s: NightSummary) -> NightSummary in s.id == ändrad.id ? ändrad : s }
        let v: Trends.Values = Trends.idunValues(alla.compactMap(\.idunNight) + d.history)
        let paket: NightLoader.CurveBundle = try XCTUnwrap(IdunnProv.paket(r))
        try rendera(NightStack(summary: ändrad, bundle: paket, values: v), namn: "natten-andrad")
        try fånga(NavigationStack {
            ScrollView { NightStack(summary: ändrad, bundle: paket, values: v) }
                .background(Tema.bg)
                .navigationTitle("Natten")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { ÄndraKnapp() }
                }
        }, namn: "skarm-natten-andrad", höjd: 1_200)
    }

    // MARK: Bladet

    func test2Bladet() throws {
        let d = try IdunnProv.laddaDemo()
        let dag: WakeDay = try XCTUnwrap(d.latestK18.wakeDay)
        let natt: NightSummary = try XCTUnwrap(MorningCardView.nights(d.summaries)[dag])
        let från = try XCTUnwrap(SömnÄndringBlad.startvärden(natt, ändring: nil), "bladet öppnar med nattens period")
        XCTAssertLessThan(från.somnade, från.vaknade)
        XCTAssertTrue((Tidshjul.lägst...Tidshjul.högst).contains(från.somnade))
        XCTAssertTrue((Tidshjul.lägst...Tidshjul.högst).contains(från.vaknade))
        let hittad: SleepInterval? = SömnÄndringBlad.hittadPeriod(natt)
        XCTAssertNotNil(hittad)

        try fånga(SömnÄndringBlad(dag: dag, zon: natt.utcOffsetSeconds, frånSomnade: från.somnade,
                                    frånVaknade: från.vaknade, ändrad: false, hittad: hittad), namn: "andra-blad", höjd: 900)
        try fånga(SömnÄndringBlad(dag: dag, zon: natt.utcOffsetSeconds, frånSomnade: från.somnade + 50,
                                    frånVaknade: från.vaknade, ändrad: true, hittad: hittad), namn: "andra-blad-aterstall", höjd: 900)
        // Vaknade före somnade: raden säger det och Spara är släckt.
        try fånga(SömnÄndringBlad(dag: dag, zon: natt.utcOffsetSeconds, frånSomnade: från.vaknade,
                                    frånVaknade: från.somnade, ändrad: false, hittad: hittad), namn: "andra-blad-fel", höjd: 900)
    }

    // MARK: Ritverktygen

    private func rendera(_ vy: some View, namn: String) throws {
        let innehåll = vy
            .frame(width: Self.bredd)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tema.bg)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "sv_SE"))
        // Som IdunnProvD2: en lång vy ritas med lägre skala om @3x inte ger någon bild.
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

    /// Ett riktigt fönster: navigationsrubrik och knappen uppe till höger som på telefonen.
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
