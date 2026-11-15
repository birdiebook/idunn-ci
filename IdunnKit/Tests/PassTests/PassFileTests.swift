import Foundation
import XCTest
@testable import Pass

// Påhittade pass. Mapparna ligger i en tillfällig mapp som tas bort efteråt.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func exempel(start: Double = 0, kind: PassKind? = .bastu, klart: Bool = true) -> Pass {
    let s = t0.addingTimeInterval(start)
    var p = Pass(id: UUID(), start: s, stop: s.addingTimeInterval(120),
                 afterEnd: klart ? s.addingTimeInterval(720) : nil, kind: kind)
    for i in 0..<5 { p.samples.append(PassSample(t: s.addingTimeInterval(Double(i * 30)), bpm: 90 + i)) }
    return p
}

final class PassFileTests: XCTestCase {
    private var mapp: URL!

    override func setUpWithError() throws {
        mapp = FileManager.default.temporaryDirectory.appendingPathComponent("passprov-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: mapp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: mapp)
    }

    func testKodningenFramOchTillbaka() throws {
        let p = exempel()
        let data = try PassFile.encode(p)
        XCTAssertEqual(try PassFile.decode(data), p)
        // Utan typ och utan slut.
        let q = exempel(kind: nil, klart: false)
        XCTAssertEqual(try PassFile.decode(try PassFile.encode(q)), q)
    }

    func testKodningenÄrStabilMedSorteradeNycklarOchIsoDatum() throws {
        let s = String(decoding: try PassFile.encode(exempel()), as: UTF8.self)
        XCTAssertTrue(s.contains("\"start\":\"2027-01-15T08:00:00Z\""), s)
        let nycklar = ["afterEnd", "id", "kind", "samples", "start", "stop"]
        let platser = nycklar.compactMap { s.range(of: "\"\($0)\":")?.lowerBound }
        XCTAssertEqual(platser, platser.sorted())
        XCTAssertEqual(try PassFile.encode(exempel()).count, try PassFile.encode(exempel()).count)
    }

    func testFilnamnetIAngivenTidszon() {
        // 1 800 000 000 s = 2027-01-15 08:00:00 UTC.
        let utc = TimeZone(identifier: "UTC")!
        let sthlm = TimeZone(secondsFromGMT: 3600)!
        XCTAssertEqual(PassFile.fileName(start: t0, timeZone: utc), "pass-2027-01-15-080000.json")
        XCTAssertEqual(PassFile.fileName(start: t0, timeZone: sthlm), "pass-2027-01-15-090000.json")
        // Över midnatt byter datumet.
        XCTAssertEqual(PassFile.fileName(start: t0.addingTimeInterval(16 * 3600 + 5), timeZone: sthlm),
                       "pass-2027-01-16-010005.json")
        XCTAssertEqual(PassFile.exportName(start: t0, timeZone: sthlm), "idunn-pass-2027-01-15-090000.zip")
    }

    func testMappenLäsesSenastFörstOchTrasigaFilerHoppasÖver() throws {
        let äldst = exempel(start: 0)
        let mitten = exempel(start: 1000, kind: .dusch)
        let nyast = exempel(start: 2000, kind: .promenad, klart: false)
        for p in [mitten, äldst, nyast] {
            try PassFile.encode(p).write(to: mapp.appendingPathComponent(PassFile.fileName(start: p.start,
                                                                                         timeZone: TimeZone(identifier: "UTC")!)))
        }
        // Trasiga och främmande filer.
        try Data("{ inte json".utf8).write(to: mapp.appendingPathComponent("pass-2027-01-01-000000.json"))
        try Data("{\"hej\":1}".utf8).write(to: mapp.appendingPathComponent("pass-2027-01-02-000000.json"))
        try Data().write(to: mapp.appendingPathComponent("pass-2027-01-03-000000.json"))
        try Data("x".utf8).write(to: mapp.appendingPathComponent("annat.json"))
        try Data("x".utf8).write(to: mapp.appendingPathComponent("pass-2027-01-04-000000.txt"))

        let alla = PassFile.loadAll(in: mapp)
        XCTAssertEqual(alla, [nyast, mitten, äldst])
        XCTAssertEqual(PassFile.entries(in: mapp).map { $0.url.lastPathComponent },
                       ["pass-2027-01-15-083320.json", "pass-2027-01-15-081640.json", "pass-2027-01-15-080000.json"])
    }

    func testTomEllerSaknadMappGerTomLista() {
        XCTAssertEqual(PassFile.loadAll(in: mapp), [])
        XCTAssertEqual(PassFile.loadAll(in: mapp.appendingPathComponent("finns-inte")), [])
    }
}
