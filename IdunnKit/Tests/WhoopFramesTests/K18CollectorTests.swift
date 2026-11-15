import Foundation
import XCTest
@testable import WhoopFrames

// METOD M24 · METOD M28. Strömmande insamling av K18-poster (A2, appens
// koppling): samma poster som K18Series(notifications:) över samma påhittade
// ramar (K18Fixtur), men bara de i ett tidsintervall.

final class K18CollectorTests: XCTestCase {

    private func notiser() -> (data: Data, notes: [RawFrame]) {
        let data = Data((K18Fixtur.jsonl.joined(separator: "\n") + "\n").utf8)
        return (data, RawFrameLog.decode(data).frames)
    }

    func testSammaPosterSomSerienOverAllaNotiser() {
        let (data, notes) = notiser()
        var c = K18Collector()
        let hoppade = c.read(log: data)
        XCTAssertEqual(hoppade, 0)
        let viaSamlaren = c.series()
        let viaSerien = K18Series(notifications: notes)
        XCTAssertGreaterThan(viaSerien.records.count, 50)
        XCTAssertEqual(viaSamlaren.records, viaSerien.records)
        XCTAssertEqual(c.badChecksums, viaSerien.badChecksums)
    }

    func testNotisForNotisGerSammaSomHelaFilen() {
        let (data, notes) = notiser()
        var a = K18Collector()
        a.read(log: data)
        var b = K18Collector()
        for n in notes { b.add(n) }
        XCTAssertEqual(a.series().records, b.series().records)
    }

    func testBaraPosterMedBandetsTidIIntervalletBehålls() {
        let (data, notes) = notiser()
        let alla = K18Series(notifications: notes).records
        let från = K18Fixtur.t0 + 20
        let till = K18Fixtur.t0 + 60
        var c = K18Collector(from: från, to: till)
        c.read(log: data)
        let väntat = alla.filter { $0.time >= från && $0.time < till }
        XCTAssertFalse(väntat.isEmpty)
        XCTAssertLessThan(väntat.count, alla.count)
        XCTAssertEqual(c.series().records, väntat)
        XCTAssertEqual(c.count, väntat.count, "utanför intervallet sparas inget i minnet")
    }

    func testIntervalletMedDatumGerSammaGränserSomSekunder() {
        let (data, _) = notiser()
        let a = Date(timeIntervalSince1970: Double(K18Fixtur.t0 + 20))
        let b = Date(timeIntervalSince1970: Double(K18Fixtur.t0 + 60))
        var viaDatum = K18Collector(from: a, to: b)
        viaDatum.read(log: data)
        var viaSekunder = K18Collector(from: K18Fixtur.t0 + 20, to: K18Fixtur.t0 + 60)
        viaSekunder.read(log: data)
        XCTAssertEqual(viaDatum.series().records, viaSekunder.series().records)
    }

    func testEnPostSomHörsSentFinnsIIntervalletEfterPostensEgenTid() {
        // Tiden som filtreras på är bandets, inte notisens: samma ram hörd ett
        // dygn senare ger samma post.
        let (_, notes) = notiser()
        let sent: [RawFrame] = notes.map {
            RawFrame(time: $0.time.addingTimeInterval(86_400), characteristic: $0.characteristic, bytes: $0.bytes)
        }
        var c = K18Collector(from: K18Fixtur.t0, to: K18Fixtur.t0 + 100)
        for n in sent { c.add(n) }
        XCTAssertEqual(c.series().records, K18Series(notifications: notes).records.filter { $0.time < K18Fixtur.t0 + 100 })
    }

    func testEnRamMedFelKontrollsummaRäknasInteOchRäknasSomFel() {
        let (_, notes) = notiser()
        var trasig = notes
        // Vänd en byte i innehållet i en ram (en hel notis per ram i fixturen).
        var bytes = trasig[5].bytes
        bytes[40] ^= 0xFF
        trasig[5] = RawFrame(time: trasig[5].time, characteristic: trasig[5].characteristic, bytes: bytes)
        var c = K18Collector()
        for n in trasig { c.add(n) }
        XCTAssertEqual(c.badChecksums, 1)
        XCTAssertNil(c.series().records.first { $0.time == K18Fixtur.t0 + 5 }, "ramen med fel räknas inte")
        XCTAssertNotNil(c.series().records.first { $0.time == K18Fixtur.t0 + 6 })
    }

    func testTomtInnehållGerEnTomSerie() {
        var c = K18Collector()
        let hoppade = c.read(log: Data())
        XCTAssertEqual(hoppade, 0)
        XCTAssertTrue(c.series().records.isEmpty)
        XCTAssertEqual(c.count, 0)
    }
}
