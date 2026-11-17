// RITAR SIDORNA I ETT PÅGÅENDE PASS TILL PNG (BESLUT B124, METOD M71): Nu, Översikt och Karta för ett pass ute
// (`pass-nu`, `pass-oversikt`, `pass-karta`), Nu och Översikt för ett pass inne (`pass-nu-inne`, `pass-oversikt-inne`)
// och hela fliken med statusraden, pillren och Stopp (`pass-sidor`, `pass-sidor-inne`; BESLUT B133, B135).
//
// DATAN ÄR PÅHITTAD: en slinga på cirka 3 km kring en påhittad punkt och en puls som stiger från 110 till 160.
// Riktiga positioner och riktig hälsodata får aldrig in här — CLAUDE.md §Dataregeln.

import XCTest
import SwiftUI
import UIKit
import Fitness
import Pass
import SleepNeed
@testable import Idunn

@MainActor
final class IdunnProvSidor: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// Provets fasta klockslag och passets start, 20 minuter tidigare.
    private let nu = Date(timeIntervalSinceReferenceDate: 784_000_000)
    private var start: Date { nu.addingTimeInterval(-1_200) }
    private let maxPuls: Double = 185

    private func spår(sekunder: Int) -> [TrackPoint] {
        let lat0 = 57.5
        let lon0 = 14.0
        let radie = 3_000.0 / (2 * Double.pi)
        let graderPerMeter = 1 / 111_195.0
        let s0: Date = start
        return (0...sekunder).map { (s: Int) -> TrackPoint in
            let v: Double = 2 * Double.pi * Double(s) / 900
            return TrackPoint(t: s0.addingTimeInterval(Double(s)),
                              lat: lat0 + radie * (1 - cos(v)) * graderPerMeter,
                              lon: lon0 + radie * sin(v) * graderPerMeter / cos(lat0 * Double.pi / 180),
                              speed: 3.3, altitude: 20 + 0.03 * Double(s), accuracy: 5)
        }
    }

    /// Pulsen en gång per sekund, stigande från 110 till 160 över 20 minuter.
    private func puls(sekunder: Int) -> [PassSample] {
        let s0: Date = start
        return (0...sekunder).map { (s: Int) -> PassSample in
            let bpm: Double = 110 + 50 * Double(s) / Double(sekunder)
            return PassSample(t: s0.addingTimeInterval(Double(s)), bpm: Int(bpm.rounded()))
        }
    }

    private func passUte() -> Pass {
        Pass(start: start, samples: puls(sekunder: 1_200), track: spår(sekunder: 1_200))
    }

    private func passInne() -> Pass {
        Pass(start: start, samples: puls(sekunder: 1_200))
    }

    func testRitaSidorna() throws {
        let ute: Pass = passUte()
        let inne: Pass = passInne()
        XCTAssertTrue(ute.isOutdoor)
        XCTAssertFalse(inne.isOutdoor)
        try fånga(sida(PassNuSida(pass: ute, now: nu, maxpuls: maxPuls)), namn: "pass-nu", höjd: 900)
        try fånga(sida(PassOversiktSida(pass: ute, now: nu, maxpuls: maxPuls)), namn: "pass-oversikt", höjd: 900)
        try fånga(sida(PassKartSida(pass: ute, now: nu, maxpuls: maxPuls)), namn: "pass-karta", höjd: 800)
        try fånga(sida(PassNuSida(pass: inne, now: nu, maxpuls: maxPuls)), namn: "pass-nu-inne", höjd: 900)
        try fånga(sida(PassOversiktSida(pass: inne, now: nu, maxpuls: maxPuls)), namn: "pass-oversikt-inne", höjd: 900)
        let medMaxpuls: PassKondition = PassKondition(maxpuls: MaxPulse(bpm: maxPuls, source: .own))
        try fånga(PassScreen(phase: .running, pass: ute, now: nu, saved: [], kondition: medMaxpuls), namn: "pass-sidor", höjd: 900)
        try fånga(PassScreen(phase: .running, pass: inne, now: nu, saved: [], kondition: medMaxpuls), namn: "pass-sidor-inne", höjd: 900)
    }

    // MARK: Ritverktyget

    /// En sida i en ScrollView med marginal och temats bakgrund.
    private func sida<V: View>(_ vy: V) -> some View {
        ScrollView {
            vy.padding(16)
        }
        .background(Tema.bg)
    }

    /// Ett riktigt fönster: listor och kartor är UIKit och ritas inte av `ImageRenderer`.
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
        // Kartan får lite längre tid på sig att hämta sina bilder.
        RunLoop.main.run(until: Date().addingTimeInterval(3))
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
