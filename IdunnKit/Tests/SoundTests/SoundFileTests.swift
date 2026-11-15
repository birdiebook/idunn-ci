import Foundation
import XCTest
import DemoData
@testable import Sound

// METOD M38. `.ljud`-filen: skrivs och läses tillbaka bit för bit lika.

final class SoundFileTests: XCTestCase {

    /// Sekunder med varierade (men påhittade) värden, inklusive negativa nivåer och 255.
    func sampleSeconds(_ n: Int) -> [SoundSecond] {
        var r = Seeded(42)
        var out: [SoundSecond] = []
        for i in 0..<n {
            var bands: [Int16] = []
            for _ in 0..<8 { bands.append(Int16(-1_200 + Int(r.uniform() * 1_300))) }
            var classes: [UInt8] = []
            for _ in 0..<12 { classes.append(UInt8(r.uniform() * 101)) }
            out.append(SoundSecond(second: i * 3 + (i % 2), level: Int16(-1_200 + Int(r.uniform() * 1_300)),
                                   levelA: Int16(-1_200 + Int(r.uniform() * 1_300)),
                                   peak: Int16(-1_200 + Int(r.uniform() * 1_300)), bands: bands,
                                   onset: i % 3 == 0 ? 255 : UInt8(i % 16), classes: classes))
        }
        return out
    }

    let start = 1_791_662_400

    func testFilenLäsTillbakaBitFörBitLika() throws {
        let secs = sampleSeconds(500)
        let data = SoundFile.encode(start: start, seconds: secs)
        XCTAssertEqual(data.count, SoundFile.headerBytes + 500 * SoundFile.recordBytes)
        let c = try SoundFile.decode(data)
        XCTAssertEqual(c.start, start)
        XCTAssertEqual(c.classListVersion, SoundClasses.version)
        XCTAssertEqual(c.seconds, secs, "varje fält i varje sekund är lika")
        XCTAssertEqual(c.truncatedBytes, 0)
        XCTAssertEqual(SoundFile.encode(start: c.start, seconds: c.seconds), data, "och skrivs om till samma byte")
    }

    func testHuvudetOchPostenHarSinaStorlekar() {
        XCTAssertEqual(SoundFile.headerBytes, 14)
        XCTAssertEqual(SoundFile.recordBytes, 39, "4 + 11 · 2 + 1 + 12")
        let h = SoundFile.header(start: start)
        XCTAssertEqual(h.count, 14)
        XCTAssertEqual([UInt8](h.prefix(4)), Array("IDLJ".utf8))
        XCTAssertEqual(SoundFile.record(sampleSeconds(1)[0]).count, 39)
        // 8 timmar: 28 800 sekunder, cirka 1,1 MB.
        XCTAssertEqual(SoundFile.headerBytes + 28_800 * SoundFile.recordBytes, 1_123_214)
    }

    func testPosterLäggsTillEnITaget() throws {
        let secs = sampleSeconds(20)
        var d = SoundFile.header(start: start)
        for s in secs { d.append(SoundFile.record(s)) }
        XCTAssertEqual(d, SoundFile.encode(start: start, seconds: secs))
        XCTAssertEqual(try SoundFile.decode(d).seconds, secs)
    }

    func testEnHalvPostSistHoppasÖverMenRäknas() throws {
        let secs = sampleSeconds(10)
        var data = SoundFile.encode(start: start, seconds: secs)
        data.removeLast(10)
        let c = try SoundFile.decode(data)
        XCTAssertEqual(c.seconds, Array(secs.prefix(9)))
        XCTAssertEqual(c.truncatedBytes, 29)
    }

    func testEnTomFilHarBaraHuvud() throws {
        let c = try SoundFile.decode(SoundFile.header(start: start))
        XCTAssertEqual(c.seconds, [])
        XCTAssertEqual(c.start, start)
    }

    func testFelFilerGerFelUtanVärden() {
        XCTAssertThrowsError(try SoundFile.decode(Data())) { (e: Error) in
            XCTAssertEqual(e as? SoundFileError, .tooShort)
        }
        var bad = SoundFile.encode(start: start, seconds: sampleSeconds(2))
        bad[0] = 0x58
        XCTAssertThrowsError(try SoundFile.decode(bad)) { (e: Error) in
            XCTAssertEqual(e as? SoundFileError, .badMagic)
        }
        var ny = SoundFile.encode(start: start, seconds: sampleSeconds(2))
        ny[4] = 9
        XCTAssertThrowsError(try SoundFile.decode(ny)) { (e: Error) in
            XCTAssertEqual(e as? SoundFileError, .unsupportedVersion)
        }
    }

    func testBandenOchKlasserFyllsUtTillÅttaOchTolv() throws {
        let kort = SoundSecond(second: 1, level: -300, levelA: -310, peak: -250, bands: [-300, -310], onset: 3,
                               classes: [90])
        let c = try SoundFile.decode(SoundFile.encode(start: start, seconds: [kort]))
        XCTAssertEqual(c.seconds[0].bands, [-300, -310, -1200, -1200, -1200, -1200, -1200, -1200])
        XCTAssertEqual(c.seconds[0].classes, [90, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    // MARK: Namnet

    func testFilstammenÄrUTCUtanDatumformaterare() {
        XCTAssertEqual(SoundFile.stem(start: 1_791_662_400), "ljud-2026-10-10T20-00-00Z")
        XCTAssertEqual(SoundFile.stem(start: 951_782_400 + 3_723), "ljud-2000-02-29T01-02-03Z")
        XCTAssertEqual(SoundFile.stem(start: 0), "ljud-1970-01-01T00-00-00Z")
    }

    // MARK: Märkena

    func testMärkenaLäsTillbakaIOrdning() {
        let marks: [SoundMark] = [SoundMark(time: 100, kind: .started), SoundMark(time: 5_000, kind: .interruptedCall),
                                  SoundMark(time: 5_090, kind: .resumed), SoundMark(time: 9_000, kind: .stopped)]
        var d = Data()
        for m in marks { d.append(m.line()) }
        d.append(contentsOf: Array("skräp utan JSON\n".utf8))
        d.append(SoundMark(time: 9_500, kind: .failed).line())
        let back = SoundMark.decode(d)
        XCTAssertEqual(back, marks + [SoundMark(time: 9_500, kind: .failed)])
    }
}
