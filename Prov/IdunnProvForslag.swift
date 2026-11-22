// RITAR FÖRSLAGEN I PASSLISTAN TILL PNG (BESLUT B121, METOD M69): listan Förslag överst på fliken Pass
// (`forslag-lista`) och bladet där typen väljs, med en gissad typ (`forslag-blad`) och utan (`forslag-blad-utan-typ`).
// Märkningen (BESLUT B147, METOD M84): förslagsbladet med Annat och flyttade tider (`forslag-blad-annat`), ett sparat
// pass med egna ord och anteckning (`pass-egen-typ`), bladet Ändra (`pass-andra`) och bladet efter Stopp
// (`pass-efter-markning`).
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

    // MARK: Märkningen (BESLUT B147, METOD M84)

    /// Påhittade sekunder som bandets poster för ett förslag: puls 130 från en timme före till en timme efter.
    private func poster(_ f: PassDetection.Candidate) -> [PassHistory.Reading] {
        let från: Int = f.startMinute * 60 - 3_600
        return (0..<(f.minutes * 60 + 7_200)).map { (s: Int) -> PassHistory.Reading in
            PassHistory.Reading(time: från + s, bpm: 120 + Int((15 * sin(Double(s) / 90)).rounded()))
        }
    }

    func testRitaMärkningen() throws {
        let utanTyp: PassDetection.Candidate = förslag(kind: nil, minuter: 41, timmarFöre: 26)
        let prov: [PassHistory.Reading] = poster(utanTyp)
        let förhand = { (v: PassForslagsval) -> Pass? in
            PassSuggestions.pass(from: utanTyp, kind: v.label.kind, readings: prov, label: v.label,
                                 start: v.start, stop: v.stopp)
        }
        // Förslagsbladet med Annat, egna ord, en anteckning, och starten flyttad 12 minuter bakåt.
        let tider = (start: utanTyp.start.addingTimeInterval(-720), stopp: utanTyp.end.addingTimeInterval(-180))
        let val = PassMarkningsval(typ: .annat, egna: "Padel", anteckning: "Dubbel, tre set")
        XCTAssertTrue(val.harTyp)
        XCTAssertEqual(val.label, PassLabel(customKind: "Padel", note: "Dubbel, tre set"))
        let blivande: Pass = try XCTUnwrap(förhand(PassForslagsval(label: val.label, start: tider.start, stopp: tider.stopp)))
        XCTAssertEqual(blivande.kindName, "Padel")
        XCTAssertEqual(blivande.suggested?.start, utanTyp.start)
        try fånga(FörslagBlad(förslag: utanTyp, nu: nu, läggTill: { _ in }, taBort: {}, förhand: förhand,
                              förval: val, tider: tider)
                    .background(Tema.bg), namn: "forslag-blad-annat", höjd: 1_150)

        // Det sparade passet med egna ord och anteckning, och bladet Ändra på det.
        let sparat: Pass = PassSuggestions.pass(from: utanTyp, kind: nil, readings: prov, label: val.label,
                                                start: tider.start, stop: tider.stopp)
        try fånga(NavigationStack { PassDetail(pass: sparat, zonMaxpuls: 190) }, namn: "pass-egen-typ", höjd: 1_100)
        try fånga(PassAndraBlad(pass: sparat, nu: nu, spara: { _, _, _ in }), namn: "pass-andra", höjd: 1_150)

        // Bladet efter Stopp: typerna med Annat… och anteckningen.
        var pågår: Pass = sparat
        pågår.kind = nil
        pågår.customKind = nil
        pågår.note = nil
        pågår.afterEnd = nil
        let efterNu: Date = (pågår.stop ?? nu).addingTimeInterval(200)
        try fånga(PassScreen(phase: .after, pass: pågår, now: efterNu, saved: []), namn: "pass-efter-markning",
                  höjd: 1_500)
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
