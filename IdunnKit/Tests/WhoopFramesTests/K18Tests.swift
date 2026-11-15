import Foundation
import XCTest
@testable import WhoopFrames

// METOD M24. Påhittade ramar: fixturen K18Fixtur.swift genereras av
// tools/tests/k18_fixtur.py, som också räknar facit-talen med
// tools/k18_analys.py. De övriga proven bygger sina ramar här. Inga byte
// kommer från ett riktigt band.

private enum K18Bygge {
    static let t0 = 1_760_000_040 // en minutgräns

    /// Ett K18-inre med fälten i PROTOKOLL_W5 §6.
    static func inner(time: Int, pulse: Int = 55, rr: [Int] = [], g: (Float, Float, Float) = (0, 0, 1),
                      skin: Int = 3250, band: Int = 312, count: Int? = nil, length: Int = 112) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: length)
        b[0] = 47
        b[1] = 18
        put32(&b, 7, UInt32(time))
        b[14] = UInt8(pulse)
        b[15] = UInt8(count ?? rr.count)
        for (j, v) in rr.enumerated() { put16(&b, 16 + 2 * j, v) }
        put32(&b, 37, g.0.bitPattern)
        put32(&b, 41, g.1.bitPattern)
        put32(&b, 45, g.2.bitPattern)
        put16(&b, 61, band)
        put16(&b, 65, skin)
        return b
    }

    static func put16(_ b: inout [UInt8], _ o: Int, _ v: Int) {
        b[o] = UInt8(v & 0xFF)
        b[o + 1] = UInt8((v >> 8) & 0xFF)
    }

    static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for k in 0..<4 { b[o + k] = UInt8((v >> UInt32(8 * k)) & 0xFF) }
    }

    /// Ramen i en notis, som den kommer på `…0005`.
    static func note(_ inner: [UInt8], at s: Int = 0, split: Int? = nil) -> [RawFrame] {
        let t = Date(timeIntervalSince1970: Double(t0 + s))
        let b = Ramar.ram(inner)
        guard let split else { return [RawFrame(time: t, characteristic: "fd4b0005", bytes: b)] }
        return [RawFrame(time: t, characteristic: "fd4b0005", bytes: Array(b[..<split])),
                RawFrame(time: t, characteristic: "fd4b0005", bytes: Array(b[split...]))]
    }

    static func series(_ seconds: [Int], g: (Int) -> (Float, Float, Float) = { _ in (0, 0, 1) }) -> K18Series {
        K18Series(notifications: seconds.flatMap { s in note(inner(time: t0 + s, g: g(s)), at: s) })
    }
}

final class K18Tests: XCTestCase {
    // MARK: Facit

    /// Samma tal som tools/k18_analys.py på samma påhittade ramar.
    func testFixturenGerSammaTalSomPythonFacit() throws {
        let data = Data((K18Fixtur.jsonl.joined(separator: "\n") + "\n").utf8)
        let (notes, skipped) = RawFrameLog.decode(data)
        XCTAssertEqual(skipped, 0)
        XCTAssertEqual(notes.count, K18Fixtur.jsonl.count)
        let s = K18Series(notifications: notes)

        XCTAssertEqual(s.records.count, K18Fixtur.poster.count)
        for (r, f) in zip(s.records, K18Fixtur.poster) {
            XCTAssertEqual(r.time, f.t)
            XCTAssertEqual(r.pulse, f.pulse, "puls \(f.t)")
            XCTAssertEqual(r.rr, f.rr, "RR \(f.t)")
            XCTAssertEqual(r.gravity.x, f.x, "x \(f.t)")
            XCTAssertEqual(r.gravity.y, f.y, "y \(f.t)")
            XCTAssertEqual(r.gravity.z, f.z, "z \(f.t)")
            XCTAssertEqual(r.skinTemperature, f.skin, "hud \(f.t)")
            XCTAssertEqual(r.bandTemperature, f.band, "band \(f.t)")
        }

        let movement = Dictionary(uniqueKeysWithValues: s.movementPerSecond.map { ($0.time, $0.value) })
        for f in K18Fixtur.poster {
            if let m = f.movement {
                XCTAssertEqual(try XCTUnwrap(movement[f.t], "rörelse saknas \(f.t)"), m, accuracy: 1e-9)
            } else {
                XCTAssertNil(movement[f.t], "rörelse där facit saknar \(f.t)")
            }
        }

        let minutes = s.minutes
        XCTAssertEqual(minutes.count, K18Fixtur.minuter.count)
        for (m, f) in zip(minutes, K18Fixtur.minuter) {
            XCTAssertEqual(m.minute, f.minute)
            XCTAssertEqual(m.seconds, f.seconds)
            XCTAssertEqual(m.skinTemperature, f.skin, accuracy: 1e-9)
            XCTAssertEqual(m.bandTemperature, f.band, accuracy: 1e-9)
            if let mv = f.movement {
                XCTAssertEqual(try XCTUnwrap(m.movement), mv, accuracy: 1e-9)
            } else {
                XCTAssertNil(m.movement)
            }
        }

        for c in K18Fixtur.täckning {
            let from = Date(timeIntervalSince1970: Double(K18Fixtur.t0 + c.from))
            let to = Date(timeIntervalSince1970: Double(K18Fixtur.t0 + c.to))
            let cov = s.coverage(from: from, to: to)
            if c.total == 0 {
                XCTAssertNil(cov, c.name)
            } else {
                XCTAssertEqual(cov?.coveredMinutes, c.covered, c.name)
                XCTAssertEqual(cov?.totalMinutes, c.total, c.name)
            }
        }
    }

    func testFixturenBärDeTreSakerProvetVillHa() {
        let (notes, _) = RawFrameLog.decode(Data((K18Fixtur.jsonl.joined(separator: "\n") + "\n").utf8))
        let s = K18Series(notifications: notes)
        XCTAssertEqual(s.duplicates, 2) // sekund 70 och sekund 256
        XCTAssertEqual(s.badChecksums, 0)
        XCTAssertEqual(s.records.first { $0.time == K18Fixtur.t0 + 70 }?.pulse, 99, "den senare ramen gäller")
        XCTAssertEqual(s.records.first { $0.time == K18Fixtur.t0 + 256 }?.rr.count, 4, "högst fyra RR, som facit")
        XCTAssertNil(s.records.first { $0.time == K18Fixtur.t0 + 140 }, "K26 är ingen K18")
        XCTAssertNil(s.records.first { $0.time == K18Fixtur.t0 + 160 }, "för kort för K18")
        XCTAssertEqual(s.records.map(\.time), s.records.map(\.time).sorted())
    }

    // MARK: Avkodning

    func testFältenLiggerPåSinaOffset() throws {
        let inner = K18Bygge.inner(time: K18Bygge.t0 + 5, pulse: 61, rr: [812, 1034, 790],
                                   g: (0.25, -0.5, 0.75), skin: 3321, band: 305)
        let r = try XCTUnwrap(K18Record.decode(inner: inner))
        XCTAssertEqual(r.time, K18Bygge.t0 + 5)
        XCTAssertEqual(r.pulse, 61)
        XCTAssertEqual(r.rr, [812, 1034, 790])
        XCTAssertEqual(r.gravity, K18Record.Gravity(x: 0.25, y: -0.5, z: 0.75))
        XCTAssertEqual(r.skinTemperature, 33.21, accuracy: 1e-12)
        XCTAssertEqual(r.bandTemperature, 30.5, accuracy: 1e-12)
        XCTAssertEqual(r.gravity.length, (0.0625 + 0.25 + 0.5625).squareRoot(), accuracy: 1e-12)
    }

    func testBaraTyp47Familj18MedFullLängdAvkodas() {
        var annan = K18Bygge.inner(time: 1)
        annan[1] = 26
        XCTAssertNil(K18Record.decode(inner: annan))
        annan[1] = 18
        annan[0] = 43
        XCTAssertNil(K18Record.decode(inner: annan))
        XCTAssertNil(K18Record.decode(inner: K18Bygge.inner(time: 1, length: 111)))
        XCTAssertNotNil(K18Record.decode(inner: K18Bygge.inner(time: 1, length: 112)))
        XCTAssertNotNil(K18Record.decode(inner: K18Bygge.inner(time: 1, length: 130)))
    }

    func testFemRRGerFyraSomFacit() throws {
        let r = try XCTUnwrap(K18Record.decode(inner: K18Bygge.inner(time: 1, rr: [1, 2, 3, 4, 5], count: 5)))
        XCTAssertEqual(r.rr, [1, 2, 3, 4])
        let ingen = try XCTUnwrap(K18Record.decode(inner: K18Bygge.inner(time: 1, rr: [], count: 0)))
        XCTAssertEqual(ingen.rr, [])
    }

    func testEnRamSomDelasIFlerNotiserBlirEnPost() {
        let s = K18Series(notifications: K18Bygge.note(K18Bygge.inner(time: K18Bygge.t0 + 3), split: 60))
        XCTAssertEqual(s.records.map(\.time), [K18Bygge.t0 + 3])
    }

    func testEnRamMedFelCRC32RäknasInte() {
        var b = Ramar.ram(K18Bygge.inner(time: K18Bygge.t0))
        b[b.count - 1] ^= 0xFF
        let ok = K18Bygge.note(K18Bygge.inner(time: K18Bygge.t0 + 1), at: 1)
        let s = K18Series(notifications: [RawFrame(time: Date(), characteristic: "fd4b0005", bytes: b)] + ok)
        XCTAssertEqual(s.records.map(\.time), [K18Bygge.t0 + 1])
        XCTAssertEqual(s.badChecksums, 1)
    }

    // MARK: Serien

    func testSammaSekundTvåGångerRäknasEnGång() {
        let a = K18Bygge.note(K18Bygge.inner(time: K18Bygge.t0 + 1), at: 1)
        let s = K18Series(notifications: K18Bygge.note(K18Bygge.inner(time: K18Bygge.t0), at: 0) + a + a
            + K18Bygge.note(K18Bygge.inner(time: K18Bygge.t0 + 2), at: 2))
        XCTAssertEqual(s.records.count, 3)
        XCTAssertEqual(s.duplicates, 1)
        XCTAssertEqual(s.movementPerSecond.count, 2)
        XCTAssertEqual(s.minutes.first?.seconds, 3)
    }

    func testOrdningenIIndataSpelarIngenRoll() {
        let ordnad = K18Bygge.series([0, 1, 2, 3, 4], g: { (Float($0) * 0.1, 0, 1) })
        let blandad = K18Bygge.series([3, 0, 4, 2, 1], g: { (Float($0) * 0.1, 0, 1) })
        XCTAssertEqual(ordnad.records, blandad.records)
        XCTAssertEqual(ordnad.minutes, blandad.minutes)
    }

    func testRörelsenÄrAvståndetMellanSekunderna() throws {
        // x ökar 0,3 g per sekund, y 0,4 g: avståndet är 0,5 g.
        let s = K18Bygge.series([0, 1, 2], g: { (0.3 * Float($0), 0.4 * Float($0), 1) })
        let m = s.movementPerSecond
        XCTAssertEqual(m.map(\.time), [K18Bygge.t0 + 1, K18Bygge.t0 + 2])
        for v in m { XCTAssertEqual(v.value, 0.5, accuracy: 1e-6) }
        XCTAssertEqual(try XCTUnwrap(s.minutes.first?.movement), 0.5, accuracy: 1e-6)
    }

    func testIngenDeltaÖverEttGlapp() {
        // 0,1,2 — glapp — 10,11: Δ finns för 1, 2 och 11, inte för 10.
        let s = K18Bygge.series([0, 1, 2, 10, 11], g: { (Float($0) * 0.1, 0, 1) })
        XCTAssertEqual(s.movementPerSecond.map(\.time), [K18Bygge.t0 + 1, K18Bygge.t0 + 2, K18Bygge.t0 + 11])
        // Ett hopp på bara två sekunder är också ett glapp (en post saknas).
        let t = K18Bygge.series([0, 2], g: { (Float($0), 0, 1) })
        XCTAssertTrue(t.movementPerSecond.isEmpty)
        XCTAssertNil(t.minutes.first?.movement, "ingen Δ alls: tom, inte noll")
    }

    func testTemperaturenÄrMedianenPerMinut() {
        // Tre poster i minuten: hud 31,00 / 32,00 / 40,00 → medianen 32,00.
        var all: [RawFrame] = []
        for (s, hud) in [(0, 3100), (1, 4000), (2, 3200)] {
            all += K18Bygge.note(K18Bygge.inner(time: K18Bygge.t0 + s, skin: hud, band: 300 + s), at: s)
        }
        // Två poster nästa minut: medianen är medelvärdet av de två.
        for (s, hud) in [(60, 3000), (61, 3100)] {
            all += K18Bygge.note(K18Bygge.inner(time: K18Bygge.t0 + s, skin: hud), at: s)
        }
        let m = K18Series(notifications: all).minutes
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].skinTemperature, 32.0, accuracy: 1e-12)
        XCTAssertEqual(m[0].bandTemperature, 30.1, accuracy: 1e-12)
        XCTAssertEqual(m[1].skinTemperature, 30.5, accuracy: 1e-12)
        XCTAssertEqual(m[1].minute, K18Bygge.t0 / 60 + 1)
        XCTAssertEqual(m[1].start, Date(timeIntervalSince1970: Double(K18Bygge.t0 + 60)))
    }

    func testMinuterUtanPosterÄrInteMed() {
        let s = K18Bygge.series([0, 1, 200, 201])
        XCTAssertEqual(s.minutes.map(\.minute), [K18Bygge.t0 / 60, K18Bygge.t0 / 60 + 3])
    }

    // MARK: Täckningen

    private func date(_ s: Int) -> Date { Date(timeIntervalSince1970: Double(K18Bygge.t0 + s)) }

    func testTäckningenÖverEttGlapp() throws {
        // Minut 0 och minut 3 har poster; minut 1 och 2 (bandet av) saknar.
        let s = K18Bygge.series(Array(0..<60) + Array(180..<200))
        var c = try XCTUnwrap(s.coverage(from: date(0), to: date(240)))
        XCTAssertEqual(c.coveredMinutes, 2)
        XCTAssertEqual(c.totalMinutes, 4)
        XCTAssertEqual(c.fraction, 0.5, accuracy: 1e-12)
        // Bara glappet: ingen täckning, men intervallet finns.
        c = try XCTUnwrap(s.coverage(from: date(60), to: date(180)))
        XCTAssertEqual(c.coveredMinutes, 0)
        XCTAssertEqual(c.totalMinutes, 2)
        XCTAssertEqual(c.fraction, 0)
    }

    func testTäckningensGränserOchOjämnaIntervall() throws {
        let s = K18Bygge.series(Array(0..<60))
        // Slutet exakt på en minutgräns tar inte med minuten efter.
        XCTAssertEqual(s.coverage(from: date(0), to: date(60))?.totalMinutes, 1)
        // En sekund in i nästa minut tar med den.
        XCTAssertEqual(s.coverage(from: date(0), to: date(61))?.totalMinutes, 2)
        // Mitt i en minut räknas hela minuten som berörd.
        let mitt = try XCTUnwrap(s.coverage(from: date(30), to: date(90)))
        XCTAssertEqual(mitt.coveredMinutes, 1)
        XCTAssertEqual(mitt.totalMinutes, 2)
        // Poster utanför intervallet räknas inte.
        XCTAssertEqual(s.coverage(from: date(60), to: date(120))?.coveredMinutes, 0)
        // Tomt och vänt intervall.
        XCTAssertNil(s.coverage(from: date(10), to: date(10)))
        XCTAssertNil(s.coverage(from: date(20), to: date(10)))
        // Utan poster alls: noll av N.
        XCTAssertEqual(K18Series(notifications: []).coverage(from: date(0), to: date(300))?.coveredMinutes, 0)
    }

    func testTomSerieGerTommaSvar() {
        let s = K18Series(notifications: [])
        XCTAssertTrue(s.records.isEmpty)
        XCTAssertTrue(s.movementPerSecond.isEmpty)
        XCTAssertTrue(s.minutes.isEmpty)
    }
}
