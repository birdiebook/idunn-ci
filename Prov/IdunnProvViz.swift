// RITAR NATTLANDSKAPET OCH POINCARÉMOLNET TILL PNG — i simulatorn, med samma
// väg som IdunnProv.swift (BESLUT B20, METOD M21, METOD M22).
//
// DATAN ÄR PÅHITTAD (`DemoData`): seedade nätter slag för slag. Riktig
// hälsodata får aldrig in här — CLAUDE.md §Dataregeln. Nätterna räknas samma
// väg som i appen (`NightReport.make`, `NightSummary`, `PoincareModel.make`).
//
// Egen klass och egna ritverktyg, så att IdunnProv.swift kan ändras utan att
// den här filen rörs.

import XCTest
import SwiftUI
import UIKit
import DemoData
import HeartRate
import Night
import WhoopFrames
@testable import Idunn

@MainActor
final class IdunnProvViz: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393
    /// Landskapets nätter: lika många som det visar.
    static let antalNätter = NightLandscape.maxNights

    /// Nätter ur K18 (A2) för landskapet och Poincarémolnet.
    static let antalK18 = 10

    struct Demo {
        var summaries: [NightSummary]
        var senaste: DemoNights.Night
        /// METOD M28. Nätter ur K18, senaste först.
        var k18Summaries: [NightSummary]
        var senasteK18: NightResult
    }

    static var demo: Demo?

    func data() throws -> Demo {
        if let d = Self.demo { return d }
        let t = Date()
        let nätter = DemoNights.nights(count: Self.antalNätter)
        let summaries: [NightSummary] = nätter.map { (n: DemoNights.Night) -> NightSummary in
            NightSummary(NightReport.make(stem: NightFiles.stem(for: n.start), contents: RecordingLog.decode(n.log),
                                          frames: []))
        }.reversed()
        var k18: [NightSummary] = []
        var senasteK18: NightResult?
        for n in DemoK18Nights.nights(count: Self.antalK18) {
            let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
            let r = try XCTUnwrap(K18Night.analyze(K18Series(records: n.records), wakeDay: dag,
                                                   startOffsetSeconds: n.utcOffsetSeconds,
                                                   endOffsetSeconds: n.utcOffsetSeconds))
            k18.append(NightSummary(digest: NightDigest(r), stem: K18Nights.stem(dag), build: "prov"))
            senasteK18 = r
        }
        k18.reverse()
        let d = Demo(summaries: summaries, senaste: try XCTUnwrap(nätter.last), k18Summaries: k18,
                     senasteK18: try XCTUnwrap(senasteK18))
        print("PROV: \(nätter.count) gamla och \(k18.count) K18-nätter för landskapet på \(Int(Date().timeIntervalSince(t))) s")
        Self.demo = d
        return d
    }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    // MARK: Nattlandskapet

    func test7Landskap() throws {
        let d = try data()
        let s = try XCTUnwrap(NightLandscape.scene(d.summaries.compactMap(\.landscapeNight)))
        XCTAssertEqual(s.ridges.count, Self.antalNätter, "varje påhittad natt är en ås")
        try rendera(LandscapeStack(scene: s, vald: .constant(nil)), namn: "landskap")
        try rendera(LandscapeStack(scene: s, vald: .constant(s.ridges.count / 2)), namn: "landskap-vald")
        try fånga(NavigationStack {
            ScrollView { LandscapeStack(scene: s, vald: .constant(nil)) }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Landskap")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-landskap", höjd: 900)
    }

    /// METOD M28 · METOD M22. Landskapet av nätter ur K18: pulsen på väggklockan
    /// ur samma `NightResult` som sammanfattningen.
    func test7bLandskapK18() throws {
        let d = try data()
        let s = try XCTUnwrap(NightLandscape.scene(d.k18Summaries.compactMap(\.landscapeNight)))
        XCTAssertEqual(s.ridges.count, Self.antalK18, "varje K18-natt är en ås")
        try rendera(LandscapeStack(scene: s, vald: .constant(nil)), namn: "landskap-k18")
    }

    // MARK: Poincarémolnet

    func test8Poincare() throws {
        let d = try data()
        let m = try XCTUnwrap(PoincareModel.make(RecordingLog.decode(d.senaste.log).recording))
        XCTAssertGreaterThan(m.pairs.count, 10_000, "en hel natts par")
        XCTAssertGreaterThan(m.descriptors.sd2, m.descriptors.sd1)
        try rendera(PoincareStack(model: m, läge: .constant(nil)), namn: "poincare")
        let mitt: TimeInterval = (m.start + m.end) / 2
        try rendera(PoincareStack(model: m, läge: .constant(mitt)), namn: "poincare-spelar")
        try fånga(NavigationStack {
            ScrollView { PoincareStack(model: m, läge: .constant(nil)) }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Slag för slag")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-poincare", höjd: 900)
    }

    /// METOD M28 · METOD M21. Poincarémolnet för en natt ur K18, ur samma
    /// slag som sammanfattningen (`NightResult.poincarePairs`).
    func test9PoincareK18() throws {
        let d = try data()
        let m = try XCTUnwrap(PoincareModel.make(result: d.senasteK18))
        XCTAssertGreaterThan(m.pairs.count, 10_000, "en hel natts par")
        XCTAssertGreaterThan(m.descriptors.sd2, m.descriptors.sd1)
        try rendera(PoincareStack(model: m, läge: .constant(nil)), namn: "poincare-k18")
        try fånga(NavigationStack {
            ScrollView { PoincareStack(model: m, läge: .constant(nil)) }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Poincaré")
                .navigationBarTitleDisplayMode(.inline)
        }, namn: "skarm-poincare-k18", höjd: 900)
    }

    // MARK: Ritningen (som i IdunnProv.swift)

    private func rendera(_ vy: some View, namn: String) throws {
        let innehåll = vy
            .frame(width: Self.bredd)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(.systemGroupedBackground))
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
