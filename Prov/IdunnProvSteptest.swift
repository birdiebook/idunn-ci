// RITAR STEPTESTET OCH KONDITIONEN TILL PNG (BESLUT B106, B110, METOD M62, M64): bladet före start (`steptest-start`, och
// utan maxpuls `steptest-start-utan`), testet medan det pågår på nivå 3 (`steptest-pagar`), ett sparat steptest med
// resultat (`steptest-pass`), fliken Pass i vila med konditionskortet och knapparna Ute och Steptest (`kondition-kort`)
// och konditionsskärmen med referens, mätningar och pulsen per nivå (`kondition-skarm`).
//
// DATAN ÄR PÅHITTAD: stegtesten är tre syntetiska pass med en rak puls per nivå (100, 114, 128, 142 och 156 slag/min plus
// en förskjutning) på ett påhittat steg på 30 cm, och profilen en påhittad man. Mätningarna och talet går appens väg:
// `KonditionModell.sätt(pass:)` räknar med `FitnessSummary` ur samma pass. Riktig hälsodata får aldrig in här —
// CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvUte.

import XCTest
import SwiftUI
import UIKit
import Fitness
import Markers
import Pass
@testable import Idunn

@MainActor
final class IdunnProvSteptest: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// Stegets höjd i cm (påhittad).
    private let höjd: Double = 30

    /// Ett steptest med ett prov per sekund: pulsen 100, 114, 128, 142 och 156 på nivåerna, plus `förskjutning`
    /// (högre puls betyder sämre kondition). Stopp efter `sekunder`, och 10 minuters mätning efteråt med sjunkande puls.
    private func steptest(start: Date, sekunder: Int, förskjutning: Int = 0, efteråt: Bool = true) -> Pass {
        let pulser: [Int] = [100, 114, 128, 142, 156]
        var prov: [PassSample] = (0..<sekunder).map { (s: Int) -> PassSample in
            PassSample(t: start.addingTimeInterval(Double(s)), bpm: pulser[min(s / 120, 4)] + förskjutning)
        }
        guard efteråt else {
            return Pass(start: start, kind: .kondition, samples: prov, stepHeightCm: höjd)
        }
        let sista: Int = (pulser[min((sekunder - 1) / 120, 4)]) + förskjutning
        for s in sekunder..<(sekunder + 600) {
            let bpm: Double = Double(sista) - 50 * Double(s - sekunder) / 600
            prov.append(PassSample(t: start.addingTimeInterval(Double(s)), bpm: Int(bpm.rounded())))
        }
        return Pass(start: start, stop: start.addingTimeInterval(Double(sekunder)),
                    afterEnd: start.addingTimeInterval(Double(sekunder + 600)), kind: .kondition, samples: prov,
                    stepHeightCm: höjd)
    }

    /// En påhittad man, född så att han är 41 år idag (åldersgruppen 40–49): 211 − 0,64 × 41 = 184,8. Födelseår och kön
    /// hör till personen på fliken Profil (BESLUT B111) och går in med `KonditionModell.sätt(person:)`.
    private func person() -> Person {
        let år: Int = FitnessRules.year(ofDay: KonditionModell.idag())
        return Person(birthYear: år - 41, sex: .male)
    }

    /// Kroppen och träningsvanorna, utan egen maxpuls.
    private func profil() -> FitnessProfile {
        FitnessProfile(heightCm: 181, weightKg: 79.5, waistCm: 88, ownMaxPulse: nil, habits: nil)
    }

    private let maxpuls = MaxPulse(bpm: 184.8, source: .age)

    // MARK: Bladet före start

    func test1Start() throws {
        let vy = SteptestStart(höjdCm: 30, maxpuls: maxpuls)
        try fånga(vy, namn: "steptest-start", höjd: 760)
    }

    func test2StartUtanMaxpuls() throws {
        try fånga(SteptestStart(höjdCm: nil, maxpuls: nil), namn: "steptest-start-utan", höjd: 760)
    }

    // MARK: Testet pågår

    func test3Pagar() throws {
        // Fyra och en halv minut in: nivå 3 (240–360 s), 20 sekunder in på den.
        let start: Date = Date().addingTimeInterval(-300)
        let sek: Int = 270
        let p: Pass = steptest(start: start, sekunder: sek, efteråt: false)
        XCTAssertEqual(StepTest.level(at: Double(sek)), 2, "nivå 3 av 5")
        XCTAssertEqual(StepTest.metronome(level: 2), 100, "20 steg i minuten är 100 slag")
        XCTAssertEqual(SteptestText.gräns(184.8), 148, "80 % av maxpulsen, avrundat")
        let nu: Date = start.addingTimeInterval(Double(sek))
        // BESLUT B111. Slag 6 i metronomen: 6 % 4 = 2, så att tredje ordet ("ner") är markerat; två klara nivåer, den
        // tredje pågår.
        try fånga(PassScreen(phase: .running, pass: p, now: nu, saved: [],
                             kondition: PassKondition(maxpuls: maxpuls, steghöjd: höjd, slag: 6)),
                  namn: "steptest-pagar", höjd: 900)
    }

    // MARK: Efter testet

    func test4SparatSteptest() throws {
        let start: Date = Date().addingTimeInterval(-3_600)
        let p: Pass = steptest(start: start, sekunder: 480)
        // Fyra klara nivåer med puls 100, 114, 128 och 142 på en rak linje; linjen dras till maxpulsen 184,8:
        // 17,273 + (184,8 − 100) / 14 × 4,591 = 45,1.
        let r = try XCTUnwrap(StepTest.estimate(p, maxPulse: maxpuls.bpm))
        XCTAssertEqual(r.levels.count, 4)
        XCTAssertEqual(r.value, 45.1, accuracy: 0.1, "ett rimligt tal ur det påhittade testet")
        XCTAssertEqual(r.uncertainty, 3.9)
        try fånga(NavigationStack { PassDetail(pass: p, konditionMaxpuls: maxpuls.bpm, zonMaxpuls: maxpuls.bpm) },
                  namn: "steptest-pass", höjd: 1_400)
    }

    // MARK: Konditionen i vardagen

    /// Tre påhittade steptest, för 21, 10 och 3 dagar sedan, med sjunkande puls (bättre kondition), räknade av
    /// modellen som appen använder. Filen är tillfällig.
    private func modellMedTest() throws -> (KonditionModell, [Pass]) {
        let nu: Date = Date()
        let pass: [Pass] = [
            steptest(start: nu.addingTimeInterval(-21 * 86_400), sekunder: 480, förskjutning: 8),
            steptest(start: nu.addingTimeInterval(-10 * 86_400), sekunder: 480, förskjutning: 4),
            steptest(start: nu.addingTimeInterval(-3 * 86_400), sekunder: 480),
        ]
        let fil = FileManager.default.temporaryDirectory
            .appendingPathComponent("idun-steptest-prov-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(FitnessFile.fileName)
        let modell = KonditionModell(fil: fil, läs: false)
        modell.sätt(person: person())
        modell.sätt(profil: profil())
        modell.sätt(pass: pass)
        addTeardownBlock { try? FileManager.default.removeItem(at: fil.deletingLastPathComponent()) }
        return (modell, pass)
    }

    func test5KortOchSkarm() throws {
        let (modell, pass) = try modellMedTest()
        // Profilen ger en maxpuls ur åldern, och varje test blir en mätning.
        XCTAssertEqual(try XCTUnwrap(modell.maxpuls), 184.8, accuracy: 0.1)
        XCTAssertEqual(modell.mätningar.count, 3)
        XCTAssertEqual(modell.mätningar.map { $0.kind }, [.stepTest, .stepTest, .stepTest])
        // Lägre puls på samma nivå ger ett högre tal: det sista testet är det bästa.
        XCTAssertLessThan(modell.mätningar[0].value, modell.mätningar[2].value)
        for m in modell.mätningar {
            XCTAssertTrue((30.0...60.0).contains(m.value), "ett rimligt tal: \(m.value)")
        }
        // Underlaget är de tre testen, med dagen för det senaste.
        let senast: Int = KonditionModell.dag(för: pass[2])
        let visat = try XCTUnwrap(modell.visat)
        XCTAssertEqual(visat.basis, .measurements(stepTests: 3, passes: 0, latestDay: senast))
        XCTAssertEqual(visat.uncertainty, 3.9, accuracy: 1e-9)
        // Pulsen på nivå 1–3 i tre test.
        XCTAssertEqual(modell.nivåpuls.count, 9)
        let referens = try XCTUnwrap(modell.referens, "en man på 41 år har en referens")
        XCTAssertEqual(referens.band.fromAge, 40)
        // BESLUT B111. Spannet och texten mot medel, under, över och på medel (medlet 47 för en man på 40–49 år).
        XCTAssertEqual(KonditionText.spann(45.1, 3.9), "troligen 41–49")
        XCTAssertEqual(KonditionText.spann(visat.value, visat.uncertainty).hasPrefix("troligen "), true)
        XCTAssertEqual(KonditionText.motMedel(referens.band.mean - 2, referens), "2 under medel för män 40–49 år")
        XCTAssertEqual(KonditionText.motMedel(referens.band.mean + 3, referens), "3 över medel för män 40–49 år")
        XCTAssertEqual(KonditionText.motMedel(referens.band.mean, referens), "På medel för män 40–49 år")
        let kvinnor = KonditionReferens(band: referens.band, kön: .kvinna)
        XCTAssertEqual(KonditionText.motMedel(referens.band.mean + 3, kvinnor), "3 över medel för kvinnor 40–49 år")
        XCTAssertEqual(KonditionText.underlag(visat.basis).hasPrefix("3 steptest · senast "), true)

        // BESLUT B111. Serien till raden Kondition på Profil: en punkt per mätning, i dagordning.
        XCTAssertEqual(modell.konditionsserie.map { (d: DayValue) -> Int in d.day }, modell.mätningar.map { $0.day })
        XCTAssertEqual(modell.konditionsserie.count, 3)

        // BESLUT B114. Påhittad serie för delen "Puls vid samma tempo": fem pass med en veckas mellanrum, 5:30 per km.
        let idagsdag: Int = KonditionModell.idag()
        let temposerie = SteadyPulse.Series(running: true, paceSeconds: 330, points: [
            SteadyPulse.Point(day: idagsdag - 28, pulse: 158, segments: 3),
            SteadyPulse.Point(day: idagsdag - 21, pulse: 156, segments: 3),
            SteadyPulse.Point(day: idagsdag - 14, pulse: 157, segments: 3),
            SteadyPulse.Point(day: idagsdag - 7, pulse: 153, segments: 3),
            SteadyPulse.Point(day: idagsdag, pulse: 151, segments: 3),
        ])
        let kond = PassKondition(modell: modell)
        try fånga(PassScreen(phase: .idle, pass: nil, now: Date(), saved: Array(pass.reversed()), kondition: kond),
                  namn: "kondition-kort", höjd: 900)
        // BESLUT B138. Dagen för den senaste mätningen som "idag", så att bilden blir densamma varje gång.
        let senasteDag: Int = modell.mätningar.map { (m: FitnessMeasurement) -> Int in m.day }.max() ?? idagsdag
        try fånga(NavigationStack {
            KonditionSkärm(visat: visat, mätningar: modell.mätningar, nivåpuls: modell.nivåpuls, referens: referens,
                           tempopuls: temposerie, idag: senasteDag)
        }, namn: "kondition-skarm", höjd: 1_700)
        try fånga(NavigationStack {
            KonditionSkärm(visat: visat, mätningar: modell.mätningar, nivåpuls: modell.nivåpuls, referens: referens,
                           tempopuls: temposerie, period: .month, idag: senasteDag)
        }, namn: "kondition-skarm-m", höjd: 1_700)
        // En enda mätning: ingen ändring och ingen kurva, bara listan.
        try fånga(NavigationStack {
            KonditionSkärm(visat: visat, mätningar: [modell.mätningar[2]], referens: referens, idag: senasteDag)
        }, namn: "kondition-skarm-en", höjd: 1_000)
    }

    // MARK: Ritverktyget

    /// Ett riktigt fönster: listor, diagram och bladet är UIKit och ritas inte av `ImageRenderer`.
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
