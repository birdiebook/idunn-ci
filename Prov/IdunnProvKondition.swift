// RITAR "KONDITION" PÅ DATA TILL PNG (BESLUT B106, METOD M60, M61, M64): Data med sektionen Kondition överst, en gång
// med VO2 max (profilen fylld, tolv nätter med vilopuls) och en gång där midjemåttet saknas och nätterna är för få,
// formuläret Kropp och träningsvanor (ifyllt och tomt, `kropp-formular`, BESLUT B111) och bladet för Whoops avskrivna tal.
//
// DATAN ÄR PÅHITTAD: profilen och vilopulserna skrivs här i provet, och räknas av samma `PassiveFitness` som appen
// använder (`KonditionModell.vilonätter` tar Idunns nätter; provet matar `PassiveFitness.estimate` direkt med
// påhittade nätter). Riktig hälsodata får aldrig in här — CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg,
// som IdunnProvAndra.

import XCTest
import SwiftUI
import UIKit
import Fitness
import Markers
import WhoopFrames
@testable import Idunn

@MainActor
final class IdunnProvKondition: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// En påhittad profil: man född 1985, midjemått 88 cm, tränar 2–3 gånger i veckan, svettig, 30–60 min.
    private func profil(midja: Double? = 88) -> FitnessProfile {
        FitnessProfile(birthYear: 1985, sex: .man, heightCm: 181, weightKg: 79.5, waistCm: midja, ownMaxPulse: nil,
                       habits: TrainingHabits(frequency: .twoToThree, intensity: .sweat, duration: .to60))
    }

    /// Påhittade vilopulser, en natt per dag bakåt från idag: 52–57 slag/min.
    private func nätter(antal: Int, idag: Int) -> [RestingNight] {
        let pulser: [Double] = [54, 53, 55, 52, 56, 54, 53, 57, 54, 55, 52, 54]
        return (0..<antal).map { (i: Int) -> RestingNight in
            RestingNight(day: idag - i, pulse: pulser[i % pulser.count])
        }
    }

    private var nu: Date {
        let zon: Int = TimeZone.current.secondsFromGMT()
        return DayLog.date(of: DayLog.Day(year: 2026, month: 11, day: 14), hour: 7, minute: 30, utcOffsetSeconds: zon)
    }

    private func data(_ lager: FitnessStore, skattning: PassiveFitness.Outcome) -> some View {
        NavigationStack {
            DataScreen(link: .connected, battery: 72, status: ListenerStatus.read([]), summaries: [], cycles: [],
                       days: [], activeDay: nil, tally: FrameTally(), now: nu,
                       kondition: lager, skattning: skattning)
        }
    }

    // MARK: Data

    func test1DataMedTal() throws {
        let idag: Int = KonditionModell.idag(nu: nu)
        let lager = FitnessStore(profile: profil(),
                                 whoopNotes: [WhoopFitnessNote(day: idag - 14, value: 51),
                                              WhoopFitnessNote(day: idag - 7, value: 52),
                                              WhoopFitnessNote(day: idag, value: 52.5)])
        let ut = PassiveFitness.estimate(profile: lager.profile, nights: nätter(antal: 12, idag: idag), day: idag)
        guard case .estimate(let e) = ut else { return XCTFail("tolv nätter och en hel profil ger ett tal: \(ut)") }
        XCTAssertEqual(e.nights, 12)
        XCTAssertTrue((30.0...70.0).contains(e.value), "ett rimligt tal: \(e.value)")
        try fånga(data(lager, skattning: ut), namn: "kondition-data", höjd: 1_400)
    }

    func test2DataDarNagotSaknas() throws {
        let idag: Int = KonditionModell.idag(nu: nu)
        let lager = FitnessStore(profile: profil(midja: nil))
        // Midjemåttet saknas och bara fyra nätter har vilopuls: inget tal visas.
        let ut = PassiveFitness.estimate(profile: lager.profile, nights: nätter(antal: 4, idag: idag), day: idag)
        guard case .missing(let saknas) = ut else { return XCTFail("inget tal utan midjemått: \(ut)") }
        XCTAssertEqual(saknas, [.waist, .nights])
        try fånga(data(lager, skattning: ut), namn: "kondition-data-saknas", höjd: 1_400)
    }

    // MARK: Formulären

    func test3KroppFormularet() throws {
        try fånga(NavigationStack { KroppFormulär(profil: profil()) }, namn: "kropp-formular", höjd: 1_500)
        try fånga(NavigationStack { KroppFormulär(profil: FitnessProfile()) }, namn: "kropp-formular-tom", höjd: 1_500)
    }

    func test4WhoopTalen() throws {
        let idag: Int = KonditionModell.idag(nu: nu)
        let noter: [WhoopFitnessNote] = [WhoopFitnessNote(day: idag - 14, value: 51),
                                         WhoopFitnessNote(day: idag - 7, value: 52),
                                         WhoopFitnessNote(day: idag, value: 52.5)]
        try fånga(NavigationStack { WhoopTalVy(noter: noter, idag: nu) }, namn: "kondition-whoop", höjd: 900)
    }

    // MARK: Lagret

    /// Lagret läser en fil som saknas eller är trasig som tomt, och sparar profilen med tomma fält som saknade.
    func test5Lagret() throws {
        let mapp = FileManager.default.temporaryDirectory.appendingPathComponent("idun-kondition-prov", isDirectory: true)
        try? FileManager.default.removeItem(at: mapp)
        try FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mapp) }
        let fil = mapp.appendingPathComponent(FitnessFile.fileName)

        XCTAssertEqual(KonditionModell.läsFil(fil), FitnessStore(), "ingen fil är ett tomt lager")
        try Data("inte json".utf8).write(to: fil)
        XCTAssertEqual(KonditionModell.läsFil(fil), FitnessStore(), "en trasig fil är ett tomt lager")

        let modell = KonditionModell(fil: fil, läs: false)
        modell.sätt(profil: FitnessProfile(birthYear: 1985, sex: .man))
        modell.skrivAv(dag: 20_000, värde: 52)
        let läst: FitnessStore = KonditionModell.läsFil(fil)
        XCTAssertEqual(läst.profile.birthYear, 1985)
        XCTAssertNil(läst.profile.waistCm, "ett tomt fält är nil, aldrig 0")
        XCTAssertNil(läst.profile.habits)
        XCTAssertEqual(läst.whoopNotes, [WhoopFitnessNote(day: 20_000, value: 52)])
        if case .estimate = modell.skattning { XCTFail("ingen skattning utan nätter och midjemått") }

        // BESLUT B111. Födelseår och kön kommer från personen på fliken Profil, inte ur den sparade profilen.
        XCTAssertNil(modell.maxpuls, "utan person finns ingen maxpuls ur åldern")
        XCTAssertNil(modell.referens)
        XCTAssertTrue(modell.konditionsserie.isEmpty, "inget visat tal, ingen serie")
        modell.sätt(person: Person(birthYear: 1985, sex: .male))
        XCTAssertNotNil(modell.maxpuls)
        XCTAssertEqual(modell.referens?.kön, FitnessProfile.Sex.man)
        modell.sätt(person: Person(birthYear: 1985, sex: .female))
        XCTAssertEqual(modell.referens?.kön, FitnessProfile.Sex.kvinna)
        modell.sätt(person: nil)
        XCTAssertNil(modell.maxpuls)
        XCTAssertNil(KonditionModell.räknad(profil(), person: nil).birthYear)
        XCTAssertEqual(KonditionModell.räknad(profil(), person: Person(birthYear: 1990, sex: .female)).sex,
                       FitnessProfile.Sex.kvinna)
    }

    // MARK: Ritverktyget

    /// Ett riktigt fönster: listor och formulär är UIKit och ritas inte av `ImageRenderer`.
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
