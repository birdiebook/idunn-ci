import Foundation
import XCTest
@testable import WhoopFrames

// BESLUT B147 · BESLUT B148 · METOD M84. Passets rörelse ur dygnens arkiv, med påhittade ramar
// (`ImuControlTests.r21`) och påhittade sidofiler. Inga byte kommer från ett riktigt band.

final class PassMotionTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_300_000)

    private func ram(_ inner: [UInt8], _ t: Date) -> DayArchive.Entry {
        DayArchive.Entry(heardMilliseconds: Int((t.timeIntervalSince1970 * 1000).rounded()),
                         characteristic: "fd4b0005", headerBytes: [0, 1], inner: inner)
    }

    private func k18(_ t: Date) -> DayArchive.Entry {
        var b = [UInt8](repeating: 0, count: 112)
        b[0] = 47
        b[1] = 18
        return ram(b, t)
    }

    private func dygn(_ d: Int, _ ramar: [DayArchive.Entry], sida: String = "") -> DayArchive {
        var a = DayArchive(day: DayLog.Day(year: 2025, month: 10, day: d), sidecar: Data(sida.utf8))
        for r in ramar { a.add(r) }
        return a
    }

    func testFönstretMedMarginalOchBaraRörelsen() throws {
        let start = t0 + 600
        let stopp = t0 + 1800
        let a = dygn(12, [
            ram(ImuControlTests.r21(sekund: 1), start - 61),           // före marginalen
            ram(ImuControlTests.r21(sekund: 2), start - 59),
            k18(start + 10),                                          // ingen rörelse
            ram([43, 17, 0, 0], start + 20),                          // EKG/optik, inte layout 21
            ram(ImuControlTests.r21(sekund: 3), start + 30),
            ram(ImuControlTests.r21(sekund: 4), stopp + 59),
            ram(ImuControlTests.r21(sekund: 5), stopp + 61),           // efter marginalen
        ], sida: """
        {"t":\(Int(start.timeIntervalSince1970) - 100),"marke":"still"}
        {"t":\(start.timeIntervalSince1970 + 0.5),"marke":"imu-start pass"}
        {"zon":3600}
        {"t":\(Int(stopp.timeIntervalSince1970)),"lank":"frånkopplad","fel":6}
        """)
        let p = try XCTUnwrap(PassMotion.extract([a], start: start, stop: stopp))
        XCTAssertEqual(p.frames.count, 3)
        XCTAssertTrue(p.frames.allSatisfy(PassMotion.isMotion))
        XCTAssertEqual(p.notifications, 3)
        XCTAssertEqual(p.day, a.day)
        let rader = String(decoding: p.sidecar, as: UTF8.self).split(separator: "\n")
        XCTAssertEqual(rader.count, 2)
        XCTAssertTrue(rader[0].contains("imu-start pass"))
        XCTAssertTrue(rader[1].contains("frånkopplad"))
        // Filen går att läsa tillbaka som ett arkiv.
        XCTAssertEqual(try DayArchive.decode(p.encode()), p)
    }

    func testPassetÖverMidnattFogasIhopIOrdning() throws {
        let start = t0
        let stopp = t0 + 3600
        let kväll = dygn(12, [ram(ImuControlTests.r21(sekund: 1), start + 10)])
        let natt = dygn(13, [ram(ImuControlTests.r21(sekund: 2), stopp - 10)])
        let p = try XCTUnwrap(PassMotion.extract([natt, kväll], start: start, stop: stopp))
        XCTAssertEqual(p.day, kväll.day)
        XCTAssertEqual(p.frames.map(\.heardMilliseconds), [kväll.frames[0].heardMilliseconds,
                                                           natt.frames[0].heardMilliseconds])
    }

    func testUtanRörelseIngenFil() {
        let a = dygn(12, [k18(t0 + 10), ram(ImuControlTests.r21(sekund: 1), t0 + 9000)])
        XCTAssertNil(PassMotion.extract([a], start: t0, stop: t0 + 600))
        XCTAssertNil(PassMotion.extract([], start: t0, stop: t0 + 600))
    }

    func testHistorikensRörelseRäknasOcksåMenInteK18() {
        var hist = ImuControlTests.r21(sekund: 1)
        hist[0] = 47
        XCTAssertTrue(PassMotion.isMotion(ram(hist, t0)))
        XCTAssertFalse(PassMotion.isMotion(k18(t0)))
        XCTAssertFalse(PassMotion.isMotion(ram([43, 17], t0)))
    }

    func testDygnetUtanRörelsenBehållerAlltAnnat() throws {
        var a = dygn(12, [k18(t0), ram(ImuControlTests.r21(sekund: 1), t0 + 1), ram([43, 17, 0, 0], t0 + 2),
                          k18(t0 + 3)], sida: "{\"t\":1,\"marke\":\"x\"}\n")
        a.notifications = 40
        a.droppedFrames = 2
        XCTAssertTrue(PassMotion.hasMotion(a))
        let b = PassMotion.withoutMotion(a)
        XCTAssertFalse(PassMotion.hasMotion(b))
        XCTAssertEqual(b.k18Frames, a.k18Frames)
        XCTAssertEqual(b.otherFrames.count, 1)
        XCTAssertEqual(b.sidecar, a.sidecar)
        XCTAssertEqual(b.notifications, 40)
        XCTAssertEqual(b.droppedFrames, 2)
        XCTAssertEqual(try DayArchive.decode(b.encode()), b)
        // Ett dygn utan rörelse är oförändrat.
        XCTAssertEqual(PassMotion.withoutMotion(b), b)
    }
}
