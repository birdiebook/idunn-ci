// RITAR FÖRSLAGEN I PASSLISTAN TILL PNG (BESLUT B121, METOD M69): listan Förslag överst på fliken Pass
// (`forslag-lista`) och bladet där typen väljs, med en gissad typ (`forslag-blad`) och utan (`forslag-blad-utan-typ`).
//
// DATAN ÄR PÅHITTAD: två förslag och ett sparat pass relativt en fast tid. Riktig hälsodata får aldrig in här —
// CLAUDE.md §Dataregeln. Egen klass och eget ritverktyg, som IdunnProvUte.

import XCTest
import SwiftUI
import UIKit
import Pass
import SleepNeed
@testable import Idunn

@MainActor
final class IdunnProvForslag: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// Ett påhittat klockslag: nu.
    private let nu = Date(timeIntervalSince1970: 1_800_000_000)

    /// Ett förslag som slutar `timmarFöre` timmar före `nu`, `minuter` långt.
    private func förslag(kind: PassKind?, minuter: Int, timmarFöre: Int) -> PassDetection.Candidate {
        let slutMinut: Int = Int(nu.timeIntervalSince1970) / 60 - timmarFöre * 60
        return PassDetection.Candidate(startMinute: slutMinut - minuter + 1, endMinute: slutMinut, kind: kind,
                                       elevatedMinutes: minuter, meanReserve: 0.55)
    }

    /// Ett påhittat sparat pass: 18 minuter, kondition, för två dygn sedan.
    private func sparat() -> Pass {
        let start: Date = nu.addingTimeInterval(-2 * 86_400)
        let prov: [PassSample] = (0...1_080).map { (s: Int) -> PassSample in
            let bpm: Double = 140 + 25 * sin(2 * Double.pi * Double(s) / 300)
            return PassSample(t: start.addingTimeInterval(Double(s)), bpm: Int(bpm.rounded()))
        }
        return Pass(start: start, stop: start.addingTimeInterval(1_080), afterEnd: start.addingTimeInterval(1_680),
                    kind: .kondition, samples: prov)
    }

    // MARK: Bilderna

    func testRitaFörslagen() throws {
        let bastu: PassDetection.Candidate = förslag(kind: .bastu, minuter: 22, timmarFöre: 3)
        let utanTyp: PassDetection.Candidate = förslag(kind: nil, minuter: 41, timmarFöre: 26)
        XCTAssertEqual(PassForslagText.rubrik(bastu), "Bastu · 22 min")
        XCTAssertEqual(PassForslagText.rubrik(utanTyp), "Pass · 41 min")
        try fånga(PassScreen(phase: .idle, pass: nil, now: nu, saved: [sparat()], förslag: [bastu, utanTyp]),
                  namn: "forslag-lista", höjd: 1_000)
        try fånga(FörslagBlad(förslag: bastu, nu: nu, läggTill: { _ in }, taBort: {})
                    .background(Tema.bg), namn: "forslag-blad", höjd: 700)
        try fånga(FörslagBlad(förslag: utanTyp, nu: nu, läggTill: { _ in }, taBort: {})
                    .background(Tema.bg), namn: "forslag-blad-utan-typ", höjd: 700)
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
        RunLoop.main.run(until: Date().addingTimeInterval(1))
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
