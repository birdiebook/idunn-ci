// RITAR SEKTIONEN "COACHEN" PÅ DATA TILL PNG (BESLUT B127, METOD M73): innan telefonen är kopplad, kopplad med en
// sändning gjord, medan den skickar, och med ett fel.
//
// INGENTING SKICKAS I PROVET: `CoachModell.starta` gör ingenting under XCTest, och sektionen tar läget som värde.
// Läget här är påhittat. Riktig hälsodata får aldrig in här — CLAUDE.md §Dataregeln. Egen klass och egna
// ritverktyg, som IdunnProvKondition.

import XCTest
import SwiftUI
import UIKit
import Night
@testable import Idunn

@MainActor
final class IdunnProvCoach: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    private func sektion(_ läge: CoachModell.Läge) -> some View {
        NavigationStack {
            List {
                CoachSektion(läge: läge)
            }
            .navigationTitle("Data")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func test1InteKopplad() throws {
        try fånga(sektion(CoachModell.Läge()), namn: "coach-okopplad", höjd: 420)
    }

    func test2Kopplad() throws {
        var läge = CoachModell.Läge()
        läge.kopplad = true
        läge.senast = Date(timeIntervalSince1970: 1_800_000_000)
        läge.skickade = 61
        try fånga(sektion(läge), namn: "coach-kopplad", höjd: 520)
    }

    func test3Skickar() throws {
        var läge = CoachModell.Läge()
        läge.kopplad = true
        läge.arbetar = true
        try fånga(sektion(läge), namn: "coach-skickar", höjd: 520)
    }

    func test4Fel() throws {
        var läge = CoachModell.Läge()
        läge.fel = "Koden gäller inte längre. Be Claude om en ny koppling."
        try fånga(sektion(läge), namn: "coach-fel", höjd: 460)
    }

    func test5UtanHuvudtalBlirDetIngaPoäng() {
        // Appens mappning från huvudtalen: en dag utan tal ger inga poäng alls (natten skickas då utan dem).
        XCTAssertNil(CoachModell.poäng(Huvudtal.tom, dag: WakeDay(daysSince1970: 20_833)))
    }

    // MARK: Ritverktyget

    /// Ett riktigt fönster: listor är UIKit och ritas inte av `ImageRenderer`.
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
        let väg = "\(Self.ut)/\(namn).png"
        try png.write(to: URL(fileURLWithPath: väg))
        print("PROV: skrev \(väg) (\(Int(bild.size.width * bild.scale))×\(Int(bild.size.height * bild.scale)) px)")
    }
}
