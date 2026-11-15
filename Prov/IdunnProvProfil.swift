// RITAR PROFILEN TILL PNG (BESLUT B104, B105, METOD M59): fliken Profil med påhittade markörer (`profil`), och utan
// något alls (`profil-tom`). Prövar också appens väg för det inskrivna: filen fram och tillbaka, en fil som inte går
// att läsa, korten ur appens egen räkning och bladets tolkning av ett inskrivet tal.
//
// Raden Kondition och raden Kropp och träningsvanor ritas som `profil-kondition` (BESLUT B111).
//
// DATAN ÄR PÅHITTAD: personen, nätterna och mätningarna nedan är inte någons. Riktig hälsodata får aldrig in här —
// CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvNatten.

import XCTest
import SwiftUI
import UIKit
import Fitness
import Markers
@testable import Idunn

@MainActor
final class IdunnProvProfil: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393
    /// 2025-11-15, som dagar sedan 1970-01-01.
    static let idag: Int = 20_407

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    /// Påhittade nätter: 40 i det senaste kvartalet, 40 i kvartalet före och 40 ett år tidigare.
    private func nätter(nu: Double, före: Double, ifjol: Double) -> [DayValue] {
        var serie: [DayValue] = []
        for i in 0..<40 {
            serie.append(DayValue(day: Self.idag - 2 * i, value: nu))
            serie.append(DayValue(day: Self.idag - 90 - 2 * i, value: före))
            serie.append(DayValue(day: Self.idag - 365 - 2 * i, value: ifjol))
        }
        return serie
    }

    /// Påhittade mätningar: VO2 max två gånger, greppstyrka en gång och en egen markör tre gånger.
    private func logg() throws -> MeasurementLog {
        var l = MeasurementLog()
        try l.add(MarkerReading(marker: .vo2max, day: Self.idag - 200, value: 44.0, note: "klocka", id: "a"))
        try l.add(MarkerReading(marker: .vo2max, day: Self.idag - 20, value: 46.5, note: "klocka", id: "b"))
        try l.add(MarkerReading(marker: .gripStrength, day: Self.idag - 10, value: 52, id: "c"))
        let lyft: MarkerDefinition = try l.addCustom(name: "Marklyft", unit: "kg", better: .higher, decimals: 0, id: "1")
        try l.add(MarkerReading(marker: lyft.id, day: Self.idag - 300, value: 110, id: "d"))
        try l.add(MarkerReading(marker: lyft.id, day: Self.idag - 150, value: 125, id: "e"))
        try l.add(MarkerReading(marker: lyft.id, day: Self.idag - 5, value: 120, id: "f"))
        return l
    }

    func test1ProfilenMedVärden() throws {
        let person = Person(birthYear: 1984, sex: .male)
        let serier: [MarkerID: [DayValue]] = [
            .hrv: nätter(nu: 62, före: 58, ifjol: 55),
            .restingHeartRate: nätter(nu: 51, före: 52, ifjol: 55),
            .regularity: nätter(nu: 84, före: 86, ifjol: 80),
            .heartRateRecovery: [DayValue(day: Self.idag - 40, value: 24), DayValue(day: Self.idag - 3, value: 29)],
            .maxPulse: [DayValue(day: Self.idag - 3, value: 183)],
        ]
        let kort: [MarkerCard] = MarkerProfile.cards(person: person, series: serier, log: try logg(), today: Self.idag)
        // Normtabellerna finns för VO2 max och greppstyrka, och bara för dem.
        let medNorm: [MarkerID] = kort.filter { (k: MarkerCard) -> Bool in k.norm != nil }.map(\.id)
        XCTAssertEqual(medNorm, [.vo2max, .gripStrength])
        XCTAssertEqual(kort.count, MarkerDefinition.builtIn.count + 1)
        try rendera(ProfilStack(kort: kort, person: person).padding(16), namn: "profil")
    }

    func test2ProfilenUtanNågot() throws {
        let kort: [MarkerCard] = MarkerProfile.cards(person: nil, series: [:], log: MeasurementLog(), today: Self.idag)
        XCTAssertTrue(kort.allSatisfy { (k: MarkerCard) -> Bool in k.value == nil })
        try rendera(ProfilStack(kort: kort, person: nil).padding(16), namn: "profil-tom")
        try rendera(ProfilStack(kort: kort, person: nil, låst: true).padding(16), namn: "profil-last")
    }

    func test3FilenFramOchTillbaka() throws {
        let mapp: URL = FileManager.default.temporaryDirectory.appendingPathComponent("prov-profil", isDirectory: true)
        try? FileManager.default.removeItem(at: mapp)
        try FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
        let fil: URL = mapp.appendingPathComponent("markorer.json")
        // Ingen fil: en tom logg som går att skriva.
        let ingen = ProfilModell.läs(från: fil)
        XCTAssertEqual(ingen.logg, MeasurementLog())
        XCTAssertFalse(ingen.låst)
        // Skriven och läst tillbaka: samma logg.
        let skriven: MeasurementLog = try logg()
        XCTAssertTrue(ProfilModell.skriv(skriven, till: fil))
        let läst = ProfilModell.läs(från: fil)
        XCTAssertEqual(läst.logg, skriven)
        XCTAssertFalse(läst.låst)
        // En fil som inte går att läsa (trasig, eller från ett nyare bygge) låser profilen i stället för att skrivas över.
        try Data("inte json".utf8).write(to: fil)
        XCTAssertTrue(ProfilModell.läs(från: fil).låst)
        try Data(#"{"custom":[],"measurements":[],"version":99}"#.utf8).write(to: fil)
        XCTAssertTrue(ProfilModell.läs(från: fil).låst)
        print("PROV: profilens fil gick fram och tillbaka (\(skriven.measurements.count) mätningar)")
    }

    func test4AppensRäkningOchBladetsTal() throws {
        // Utan nätter och pass ger appens räkning ett kort per markör, med det inskrivna ifyllt.
        let kort: [MarkerCard] = ProfilModell.kort(person: nil, nätter: [], pass: [], logg: try logg(),
                                                   idag: Self.idag)
        XCTAssertEqual(kort.count, MarkerDefinition.builtIn.count + 1)
        XCTAssertEqual(kort.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.value, 46.5)
        XCTAssertNil(kort.first { (k: MarkerCard) -> Bool in k.id == .hrv }?.value)
        XCTAssertNil(kort.first { (k: MarkerCard) -> Bool in k.id == .maxPulse }?.value)
        // Bladet tar komma eller punkt, och inget annat än ett tal över noll.
        XCTAssertEqual(MätningBlad.tal("42,5"), 42.5)
        XCTAssertEqual(MätningBlad.tal(" 51.0 "), 51)
        XCTAssertNil(MätningBlad.tal(""))
        XCTAssertNil(MätningBlad.tal("0"))
        XCTAssertNil(MätningBlad.tal("-3"))
        XCTAssertNil(MätningBlad.tal("fyrtio"))
    }

    /// BESLUT B111. Raden Kondition fylls av det Idunn räknat (en påhittad serie: tre steptest), och under raden med
    /// födelseår och kön står raden Kropp och träningsvanor, tom och ifylld. Ett inskrivet tal räknas i samma rad.
    func test5KonditionPåProfilen() throws {
        let person = Person(birthYear: 1984, sex: .male)
        let serie: [DayValue] = [DayValue(day: Self.idag - 21, value: 43.0), DayValue(day: Self.idag - 10, value: 44.5),
                                 DayValue(day: Self.idag - 3, value: 45.1)]
        let utan: [MarkerCard] = ProfilModell.kort(person: person, nätter: [], pass: [], logg: MeasurementLog(),
                                                   idag: Self.idag)
        XCTAssertNil(utan.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.value, "utan serie och mätning inget tal")
        let kort: [MarkerCard] = ProfilModell.kort(person: person, nätter: [], pass: [], logg: MeasurementLog(),
                                                   idag: Self.idag, kondition: serie)
        XCTAssertEqual(kort.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.value, 45.1)
        // Ett inskrivet tal efter serien blir det senaste i samma rad.
        var inskrivet = MeasurementLog()
        try inskrivet.add(MarkerReading(marker: .vo2max, day: Self.idag - 1, value: 47.0, id: "z"))
        let båda: [MarkerCard] = ProfilModell.kort(person: person, nätter: [], pass: [], logg: inskrivet,
                                                   idag: Self.idag, kondition: serie)
        XCTAssertEqual(båda.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.value, 47.0)
        let kropp = FitnessProfile(heightCm: 181, weightKg: 79.5, waistCm: 88, ownMaxPulse: nil, habits: nil)
        try rendera(ProfilStack(kort: kort, person: person, kropp: kropp).padding(16), namn: "profil-kondition")
        try rendera(ProfilStack(kort: kort, person: person).padding(16), namn: "profil-kondition-tom")
    }

    // MARK: Ritverktygen (som IdunnProvNatten)

    private func rendera(_ vy: some View, namn: String) throws {
        let innehåll = vy
            .frame(width: Self.bredd)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tema.bg)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "sv_SE"))
        for skala in [3.0, 2.0, 1.0] as [CGFloat] {
            let r = ImageRenderer(content: innehåll)
            r.scale = skala
            r.proposedSize = ProposedViewSize(width: Self.bredd, height: nil)
            if let bild = r.uiImage, let png = bild.pngData() {
                let väg = "\(Self.ut)/\(namn).png"
                try png.write(to: URL(fileURLWithPath: väg))
                print("PROV: skrev \(väg) (\(Int(bild.size.width * bild.scale))×\(Int(bild.size.height * bild.scale)) px)")
                return
            }
            print("PROV: \(namn) gick inte att rita @\(Int(skala))x")
        }
        XCTFail("kunde inte rita \(namn)")
    }
}
