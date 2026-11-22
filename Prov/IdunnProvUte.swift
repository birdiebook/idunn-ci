// RITAR "PASS UTE" TILL PNG (BESLUT B107, B108, B110, METOD M65): fliken Pass i vila med knappen Ute (`ute-vila`), ett
// pågående pass ute med sträcka och tempo (`ute-pagar`) och ett sparat pass ute med kartdelen: rutten färgad efter pulszon,
// sträcka, tid, tempo och kilometertider (`ute-pass`).
//
// DATAN ÄR PÅHITTAD: spåret är en slinga på cirka 3 km kring en påhittad punkt, en position per sekund, och pulsen en
// våg som går genom flera zoner. Riktiga positioner och riktig hälsodata får aldrig in här — CLAUDE.md §Dataregeln.
// BESLUT B111: pågående pass ute visar tid, puls, sträcka och tempo (inte lägst, snitt och högst), och kartans färger
// förklaras som ett tonat streck från lugnt till hårt. Kartbilden hämtas från Apple och kanske inte laddas i simulatorn; rutten och talen ska synas ändå. Egen klass och
// egna ritverktyg, som IdunnProvKondition.

import XCTest
import SwiftUI
import UIKit
import Pass
import SleepNeed
@testable import Idunn

@MainActor
final class IdunnProvUte: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// Ett påhittat klockslag: starten på passet.
    private let start = Date(timeIntervalSinceReferenceDate: 784_000_000)
    /// Maxpulsen som provet ger kartan (påhittad).
    private let maxPuls: Double = 190

    /// En slinga på cirka 3 km (radie 477 m) kring en påhittad punkt: 900 sekunder, en position per sekund.
    private func spår(sekunder: Int) -> [TrackPoint] {
        let lat0 = 57.5
        let lon0 = 14.0
        let radie = 3_000.0 / (2 * Double.pi)
        let graderPerMeter = 1 / 111_195.0
        return (0...sekunder).map { (s: Int) -> TrackPoint in
            // BESLUT B138. Farten varierar mjukt (±30 %) och slingan är ändå full efter 900 sekunder.
            let v: Double = 2 * Double.pi * (Double(s) + 15 * sin(2 * Double.pi * Double(s) / 300)) / 900
            return TrackPoint(t: start.addingTimeInterval(Double(s)),
                              lat: lat0 + radie * (1 - cos(v)) * graderPerMeter,
                              lon: lon0 + radie * sin(v) * graderPerMeter / cos(lat0 * Double.pi / 180),
                              speed: 3.3, altitude: 40 + 6 * sin(v), accuracy: 5)
        }
    }

    /// Pulsen en gång per sekund: en våg på 5 minuter mellan 105 och 185 slag/min, så att flera zoner syns.
    private func puls(sekunder: Int, från: Int = 0) -> [PassSample] {
        (från...sekunder).map { (s: Int) -> PassSample in
            let bpm: Double = 145 + 40 * sin(2 * Double.pi * Double(s) / 300)
            return PassSample(t: start.addingTimeInterval(Double(s)), bpm: Int(bpm.rounded()))
        }
    }

    /// Passet ute, färdigt: 15 minuter ute och 10 minuter med sjunkande puls efteråt.
    private func sparat() -> Pass {
        var prov: [PassSample] = puls(sekunder: 900)
        for s in 901...1_500 {
            let bpm: Double = 180 - 60 * Double(s - 900) / 600
            prov.append(PassSample(t: start.addingTimeInterval(Double(s)), bpm: Int(bpm.rounded())))
        }
        return Pass(start: start, stop: start.addingTimeInterval(900), afterEnd: start.addingTimeInterval(1_500),
                    kind: .kondition, samples: prov, track: spår(sekunder: 900))
    }

    // MARK: Bilderna

    func test1Vila() throws {
        let nu: Date = start.addingTimeInterval(86_400)
        try fånga(PassScreen(phase: .idle, pass: nil, now: nu, saved: [sparat()]), namn: "ute-vila", höjd: 800)
    }

    func test2Pagar() throws {
        // Tio minuter in: 600 positioner och prov, och klockan en sekund efter det sista.
        let p = Pass(start: start, samples: puls(sekunder: 600), track: spår(sekunder: 600))
        let meter: Double = PassRoute.distance(p.track ?? [])
        XCTAssertTrue((1_900.0...2_100.0).contains(meter), "två tredjedelar av slingan: \(meter) m")
        try fånga(PassScreen(phase: .running, pass: p, now: start.addingTimeInterval(601), saved: []),
                  namn: "ute-pagar", höjd: 900)
    }

    func test3SparatPass() throws {
        let p: Pass = sparat()
        let spårPunkter: [TrackPoint] = p.track ?? []
        let meter: Double = PassRoute.distance(spårPunkter)
        XCTAssertTrue((2_900.0...3_100.0).contains(meter), "slingan är cirka 3 km: \(meter) m")
        XCTAssertEqual(PassRoute.splits(spårPunkter).count, 2, "tre kilometer ger två hela kilometertider")
        XCTAssertTrue(PassKarta.harRutt(p))
        XCTAssertFalse(PassKarta.harRutt(p.withoutTrack()), "ett pass utan spår har ingen karta")
        let delar = PassRoute.runs(spårPunkter, samples: p.samples) { (bpm: Int) -> Int in
            PassLoad.zone(bpm: bpm, maxPulse: 190)
        }
        XCTAssertGreaterThan(Set(delar.map { $0.klass }).count, 2, "flera zoner syns på rutten")
        try fånga(NavigationStack { PassDetail(pass: p, maxPulse: maxPuls, zonMaxpuls: maxPuls) },
                  namn: "ute-pass", höjd: 1_250)
    }

    // MARK: Efteråt (BESLUT B138)

    /// Samma pass ute med tempokurvan och höjdkurvan.
    func test4SparatTempoOchHojd() throws {
        let p: Pass = sparat()
        XCTAssertGreaterThanOrEqual(PassSeries.pace(p.track ?? [], start: p.start).count, 2)
        XCTAssertGreaterThanOrEqual(PassSeries.altitude(p.track ?? [], start: p.start).count, 2)
        try fånga(NavigationStack { PassDetail(pass: p, maxPulse: maxPuls, zonMaxpuls: maxPuls, kurva: .tempo) },
                  namn: "pass-sparat-tempo", höjd: 1_300)
        try fånga(NavigationStack { PassDetail(pass: p, maxPulse: maxPuls, zonMaxpuls: maxPuls, kurva: .höjd) },
                  namn: "pass-sparat-hojd", höjd: 1_300)
    }

    /// Ett pass inne med prov också efter stopp, så att återhämtningen har värden.
    func test5SparatInne() throws {
        var p: Pass = sparat().withoutTrack()
        p.kind = .styrka
        XCTAssertFalse(p.isOutdoor)
        XCTAssertNotNil(p.pulseAtStop)
        try fånga(NavigationStack { PassDetail(pass: p, zonMaxpuls: maxPuls) }, namn: "pass-sparat-inne", höjd: 1_200)
    }

    // MARK: Ritverktyget

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
