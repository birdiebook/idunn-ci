// RITAR VECKAKORTET PÅ FLIKEN PASS TILL PNG (BESLUT B126, METOD M72): kortet "Den här veckan" med och utan maxpuls
// (`vecka-kort`, `vecka-kort-utan-maxpuls`) och fliken Pass i vila med kortet ovanför listan (`vecka-lista`).
//
// DATAN ÄR PÅHITTAD: stoppade pass med en puls per sekund kring ett fast värde, och spår som slingor kring en påhittad
// punkt. Riktiga pass och positioner får aldrig in här — CLAUDE.md §Dataregeln. Egna kopior av ritverktygen, som
// IdunnProvSidor.

import XCTest
import SwiftUI
import UIKit
import Pass
import SleepNeed
@testable import Idunn

@MainActor
final class IdunnProvVecka: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// Provets fasta klockslag.
    private let nu = Date(timeIntervalSinceReferenceDate: 784_000_000)
    private let maxPuls: Double = 185

    /// Kl 12 lokal tid på dagnumret `dag` (dagar sedan 1970-01-01), så att `KonditionModell.dag(för:)` ger samma dag.
    private func middag(dag: Int) -> Date {
        let ungefär: Date = Date(timeIntervalSince1970: Double(dag) * 86_400 + 43_200)
        let förskjutning: Int = TimeZone.current.secondsFromGMT(for: ungefär)
        return Date(timeIntervalSince1970: Double(dag) * 86_400 + 43_200 - Double(förskjutning))
    }

    /// En slinga på `meter` meter över `sekunder` sekunder, en position per sekund, kring en påhittad punkt.
    private func spår(start: Date, sekunder: Int, meter: Double) -> [TrackPoint] {
        let lat0 = 57.5
        let lon0 = 14.0
        let radie = meter / (2 * Double.pi)
        let graderPerMeter = 1 / 111_195.0
        return (0...sekunder).map { (s: Int) -> TrackPoint in
            let v: Double = 2 * Double.pi * Double(s) / Double(sekunder)
            return TrackPoint(t: start.addingTimeInterval(Double(s)),
                              lat: lat0 + radie * (1 - cos(v)) * graderPerMeter,
                              lon: lon0 + radie * sin(v) * graderPerMeter / cos(lat0 * Double.pi / 180),
                              speed: 3.0, altitude: 40, accuracy: 5)
        }
    }

    /// Ett stoppat pass på dagen `dag`: `minuter` långt, pulsen `bpm` varje sekund, med spår om `meter` är satt.
    private func pass(dag: Int, minuter: Int, bpm: Int, typ: PassKind, meter: Double? = nil) -> Pass {
        let start: Date = middag(dag: dag)
        let sekunder: Int = minuter * 60
        let prov: [PassSample] = (0...sekunder).map { (s: Int) -> PassSample in
            PassSample(t: start.addingTimeInterval(Double(s)), bpm: bpm)
        }
        let rutt: [TrackPoint]? = meter.map { (m: Double) -> [TrackPoint] in
            spår(start: start, sekunder: sekunder, meter: m)
        }
        return Pass(start: start, stop: start.addingTimeInterval(Double(sekunder)),
                    kind: typ, samples: prov, track: rutt)
    }

    private func passen(idag: Int) -> [Pass] {
        let måndag: Int = PassWeek.weekStart(day: idag)
        return [
            // Den här veckan, och ett bastupass som inte räknas.
            pass(dag: måndag, minuter: 40, bpm: 150, typ: .kondition, meter: 6_000),
            pass(dag: måndag + 2, minuter: 35, bpm: 120, typ: .styrka),
            pass(dag: måndag + 1, minuter: 20, bpm: 100, typ: .bastu),
            // Veckan före.
            pass(dag: måndag - 7, minuter: 50, bpm: 145, typ: .kondition, meter: 7_500),
            pass(dag: måndag - 5, minuter: 30, bpm: 115, typ: .styrka),
            pass(dag: måndag - 3, minuter: 45, bpm: 105, typ: .promenad, meter: 3_500),
            // Två veckor före.
            pass(dag: måndag - 14, minuter: 60, bpm: 150, typ: .kondition),
            // Fyra veckor före.
            pass(dag: måndag - 28, minuter: 40, bpm: 140, typ: .kondition),
            pass(dag: måndag - 26, minuter: 25, bpm: 120, typ: .styrka)
        ]
    }

    func testRitaVeckan() throws {
        let idag: Int = KonditionModell.idag(nu: nu)
        let alla: [Pass] = passen(idag: idag)
        let med: PassWeek.Overview = PassVecka.oversikt(alla, maxpuls: maxPuls, idag: idag)
        let utan: PassWeek.Overview = PassVecka.oversikt(alla, maxpuls: nil, idag: idag)
        XCTAssertEqual(med.current.passes, 2, "bastun räknas inte")
        XCTAssertTrue(med.hasTraining)

        try fånga(sida(VeckaKort(oversikt: med, harMaxpuls: true)), namn: "vecka-kort", höjd: 900)
        try fånga(sida(VeckaKort(oversikt: utan, harMaxpuls: false)), namn: "vecka-kort-utan-maxpuls", höjd: 900)
        try fånga(PassScreen(phase: .idle, pass: nil, now: nu, saved: alla, vecka: med, veckaMedMaxpuls: true),
                  namn: "vecka-lista", höjd: 1_700)
    }

    // MARK: Ritverktyget

    private func sida<V: View>(_ vy: V) -> some View {
        ScrollView {
            vy.padding(16)
        }
        .background(Tema.bg)
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
