// RITAR DAGBOKEN TILL PNG (BESLUT B130, METOD M75): morgonens fråga (`dagbok-morgon`, och med ett givet svar
// `dagbok-morgon-vald`), kvällens blad utan val (`dagbok-kvall`) och med två taggar valda, en med detalj
// (`dagbok-kvall-vald`). Prövar också appens väg för filen: fram och tillbaka, och en fil som inte går att läsa.
//
// DATAN ÄR PÅHITTAD: kvällarna och skattningarna nedan är inte någons. Riktig hälsodata får aldrig in här —
// CLAUDE.md §Dataregeln. Egen klass och egna ritverktyg, som IdunnProvProfil.

import XCTest
import SwiftUI
import UIKit
import Journal
@testable import Idunn

@MainActor
final class IdunnProvDagbok: XCTestCase {

    static let ut = "/tmp/idun_prov"
    static let bredd: CGFloat = 393
    /// 2025-11-15, som dagar sedan 1970-01-01.
    static let idag: Int = 20_407

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(atPath: Self.ut, withIntermediateDirectories: true)
    }

    func test1MorgonensFråga() throws {
        try rendera(MorgonfrågaVy().padding(.vertical, 60), namn: "dagbok-morgon")
        try rendera(MorgonfrågaVy(vald: 4).padding(.vertical, 60), namn: "dagbok-morgon-vald")
    }

    func test2KvällensBlad() throws {
        try rendera(KvällVy(), namn: "dagbok-kvall")
        let valda: [EveningTag] = [EveningTag(id: "sen-maltid", detail: "stor"), EveningTag(id: "alkohol")]
        try rendera(KvällVy(valda: valda), namn: "dagbok-kvall-vald")
    }

    func test3FilenFramOchTillbaka() throws {
        let mapp: URL = FileManager.default.temporaryDirectory.appendingPathComponent("prov-dagbok", isDirectory: true)
        try? FileManager.default.removeItem(at: mapp)
        try FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
        let fil: URL = mapp.appendingPathComponent(Journal.fileName)
        // Ingen fil: en tom dagbok som går att skriva.
        let ingen = DagbokModell.läs(från: fil)
        XCTAssertEqual(ingen.dagbok, Journal())
        XCTAssertFalse(ingen.låst)
        // Skriven och läst tillbaka: samma dagbok.
        var skriven = Journal()
        skriven = skriven.setting(JournalEvening(wakeDayNumber: Self.idag,
                                                 tags: [EveningTag(id: "bastu"), EveningTag(id: "sen-maltid", detail: "liten")],
                                                 recordedAt: 1_763_000_000))
        skriven = skriven.setting(JournalMorning(wakeDayNumber: Self.idag, rested: 4, recordedAt: 1_763_030_000))
        skriven = skriven.skippingMorning(Self.idag + 1)
        XCTAssertTrue(DagbokModell.skriv(skriven, till: fil))
        let läst = DagbokModell.läs(från: fil)
        XCTAssertEqual(läst.dagbok, skriven)
        XCTAssertFalse(läst.låst)
        // En fil som inte går att läsa (trasig, eller från ett nyare bygge) låser dagboken i stället för att skrivas över.
        try Data("inte json".utf8).write(to: fil)
        XCTAssertTrue(DagbokModell.läs(från: fil).låst)
        try Data(#"{"evenings":[],"mornings":[],"skippedMornings":[],"version":99}"#.utf8).write(to: fil)
        XCTAssertTrue(DagbokModell.läs(från: fil).låst)
        print("PROV: dagbokens fil gick fram och tillbaka (\(skriven.evenings.count) kväll, \(skriven.mornings.count) morgon)")
    }

    // MARK: Ritverktygen (som IdunnProvProfil)

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
