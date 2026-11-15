import Foundation
import XCTest
import HeartRate
@testable import Night

// Påhittade nätter och fönster (NightGenerator.swift), bara tal. METOD M18.

final class NightCurveTests: XCTestCase {
    let t0 = NightGenerator.t0

    func kurva(_ natt: NightRecording) throws -> (NightCurve.Curve, NightAnalysis.Report) {
        let slag = RRCleaning.clean(natt)
        let r = NightAnalysis.analyze(beats: slag)
        return (try XCTUnwrap(NightCurve.make(night: natt, beats: slag, analysis: r)), r)
    }

    // MARK: Minuterna och glappen

    func testMinutpulsenUrSlagen() throws {
        let natt = NightGenerator.oneBeatPerSecond([Double](repeating: 1000, count: 600))
        let (c, _) = try kurva(natt)
        XCTAssertEqual(t0.truncatingRemainder(dividingBy: 60), 0, "t0 är en hel minut")
        XCTAssertEqual(c.minutes.count, 10)
        for m in c.minutes {
            XCTAssertEqual(try XCTUnwrap(m.heartRate), 60, accuracy: 1e-9)
            XCTAssertEqual(m.beats, 60)
            XCTAssertEqual(m.missingShare, 0)
        }
        XCTAssertTrue(c.gaps.isEmpty)
    }

    func testGlappetSynsOchMinutenUtanSlagFårIngenPuls() throws {
        let a = NightGenerator.oneBeatPerSecond([Double](repeating: 1000, count: 600))
        let b = NightGenerator.oneBeatPerSecond([Double](repeating: 1000, count: 600), from: t0 + 700)
        let (c, _) = try kurva(NightRecording(samples: a.samples + b.samples))
        XCTAssertEqual(c.gaps.count, 1)
        let g = try XCTUnwrap(c.gaps.first)
        XCTAssertEqual(g.lowerBound, t0 + 599, accuracy: 1e-6)
        XCTAssertEqual(g.upperBound, t0 + 700, accuracy: 1e-6)
        let iGlappet = try XCTUnwrap(c.minutes.first { $0.start == t0 + 600 })
        XCTAssertNil(iGlappet.heartRate)
        XCTAssertEqual(iGlappet.beats, 0)
    }

    func testAndelenSomSaknas() {
        // 50 slag kom, 40 behölls, 10 utelämnades: 20 av 60 saknas.
        let m = NightCurve.Minute(start: 0, heartRate: 55, beats: 50, kept: 40, omitted: 10)
        XCTAssertEqual(m.missingShare, 20.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(NightCurve.Minute(start: 0, heartRate: nil, beats: 0, kept: 0, omitted: 0).missingShare, 0)
        // Under 20 behållna slag får minuten ingen puls.
        XCTAssertEqual(NightCurve.minBeatsPerMinute, 20)
    }

    // MARK: Lägsta punkten och fallet

    func fönster(_ puls: [Double?]) -> [NightCurve.WindowPoint] {
        puls.enumerated().map { (k: Int, p: Double?) -> NightCurve.WindowPoint in
            NightCurve.WindowPoint(start: Double(k) * 300, rmssd: p == nil ? nil : 40, heartRate: p, breathsPerMinute: nil)
        }
    }

    func testLägstaPunktenOchFallet() throws {
        let w = fönster([nil, 70, 64, 58, 55, 53, 52, 52.5, 54, 56, 60])
        let n = try XCTUnwrap(NightCurve.nadir(w, start: 0, end: 3300))
        XCTAssertEqual(n.heartRate, 52)
        XCTAssertEqual(n.time, 6 * 300 + 150)
        XCTAssertEqual(n.fraction, 1950.0 / 3300.0, accuracy: 1e-12)
        // Inom 3 slag/min från 52: första fönstret på 55 eller lägre.
        let f = try XCTUnwrap(NightCurve.fall(w, start: 0, nadir: n))
        XCTAssertEqual(f.seconds, 4 * 300 + 150)
        XCTAssertEqual(f.fromHeartRate, 70)
        XCTAssertEqual(f.drop, 18)
    }

    func testVidLikaVinnerDetTidigareFönstret() throws {
        let w = fönster([60, 50, 55, 50])
        let n = try XCTUnwrap(NightCurve.nadir(w, start: 0, end: 1200))
        XCTAssertEqual(n.time, 450)
        // Natten börjar redan nära botten: fallet är första fönstret.
        let f = try XCTUnwrap(NightCurve.fall(fönster([52, 50, 51]), start: 0, nadir: n))
        XCTAssertEqual(f.seconds, 150)
        XCTAssertNil(NightCurve.nadir(fönster([nil, nil]), start: 0, end: 600))
    }

    /// Pulsen `t` sekunder in i den genererade natten.
    static func fallandePuls(_ t: Double) -> Double {
        let minut: Double = t / 60
        if minut < 80 {
            let kvar: Double = exp(-minut / 20)
            return 50 + 16 * kvar
        }
        let botten: Double = 50 + 16 * exp(-4.0)
        let uppåt: Double = (minut - 80) / 10
        return botten + uppåt
    }

    func testGenereradNattMedFallOchBotten() throws {
        // Två timmar: pulsen faller från 66 mot 50 med tidskonstant 20 min,
        // bottnar efter 80 min och stiger sedan 4 slag/min på 40 min.
        // Facit ur Python-spegeln (fönster från första slaget): botten i
        // fönstret 75–80 min (mitt 4650 s), fallet inom 3 slag/min nått i
        // fönstret 30–35 min (mitt 1950 s), första fönstret 64,2 slag/min.
        let slag: [Double] = NightGenerator.beats(seconds: 7200) { (i: Int, t: Double, _: inout Seeded) -> Double in
            let rsa: Double = i % 2 == 0 ? -20 : 20
            let rr: Double = 60_000 / Self.fallandePuls(t)
            return rr + rsa
        }
        let (c, r) = try kurva(NightGenerator.night(slag))
        let n = try XCTUnwrap(c.nadir)
        XCTAssertEqual(n.heartRate, try XCTUnwrap(r.windows.compactMap(\.meanHeartRate).min()),
                       "botten = lägsta fönstret (METOD M18)")
        // BESLUT B76. Vilopulsen är 10:e percentilen av fönstren och ligger på eller över botten.
        XCTAssertLessThanOrEqual(n.heartRate, try XCTUnwrap(r.restingHeartRate))
        XCTAssertEqual(n.time - c.start, 4650, accuracy: 310)
        XCTAssertEqual(n.fraction, 0.646, accuracy: 0.05)
        let f = try XCTUnwrap(c.fall)
        XCTAssertEqual(f.seconds, 1950, accuracy: 310)
        XCTAssertEqual(f.fromHeartRate, 64.2, accuracy: 1)
        XCTAssertGreaterThan(f.drop, 12)
        let p = try XCTUnwrap(c.profile)
        XCTAssertEqual(p.heartRate.count, NightCurve.profileBins)
        XCTAssertEqual(p.rmssd.count, NightCurve.profileBins)
        XCTAssertGreaterThanOrEqual(p.heartRate.compactMap { $0 }.count, 46)
    }

    // MARK: Nattens form och den typiska natten

    func testNattensFormIDelar() throws {
        // 80 minuter: delarna är 100 s. Minut k har puls 40 + k.
        let m: [NightCurve.Minute] = (0..<80).map { (k: Int) -> NightCurve.Minute in
            NightCurve.Minute(start: Double(k) * 60, heartRate: 40 + Double(k), beats: 60, kept: 60, omitted: 0)
        }
        let p = try XCTUnwrap(NightCurve.profile(minutes: m, windows: fönster([50, 52]), start: 0, end: 4800))
        // Del 0 har minuterna med mitt 30 och 90 s, del 1 den med 150 s.
        XCTAssertEqual(try XCTUnwrap(p.heartRate[0]), 40.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(p.heartRate[1]), 42, accuracy: 1e-12)
        // Fönstren har mitt 150 och 450 s: del 1 och 4.
        XCTAssertEqual(p.rmssd[1], 40)
        XCTAssertEqual(p.rmssd[4], 40)
        XCTAssertNil(p.rmssd[0])
        XCTAssertNil(NightCurve.profile(minutes: m, windows: [], start: 10, end: 10))
    }

    func profil(_ puls: Double, rmssd: Double? = nil) -> NightCurve.Profile {
        NightCurve.Profile(heartRate: [Double?](repeating: puls, count: NightCurve.profileBins),
                           rmssd: [Double?](repeating: rmssd, count: NightCurve.profileBins))
    }

    func testTypiskaNattenÄrMedianOchKvartiler() throws {
        let tre = NightCurve.typical([profil(50), profil(52), profil(60)])
        XCTAssertEqual(tre.heartRate.count, NightCurve.profileBins)
        let b = try XCTUnwrap(tre.heartRate.first)
        XCTAssertEqual(b.median, 52)
        XCTAssertEqual(b.lower, 51, accuracy: 1e-12)
        XCTAssertEqual(b.upper, 56, accuracy: 1e-12)
        XCTAssertEqual(b.nights, 3)
        XCTAssertEqual(b.fraction, 0.5 / Double(NightCurve.profileBins), accuracy: 1e-12)
        XCTAssertTrue(tre.rmssd.isEmpty, "ingen natt har RMSSD")

        let fyra = NightCurve.typical([profil(50), profil(52), profil(60), profil(70)])
        let c = try XCTUnwrap(fyra.heartRate.last)
        XCTAssertEqual(c.median, 56)
        XCTAssertEqual(c.lower, 51.5, accuracy: 1e-12)
        XCTAssertEqual(c.upper, 62.5, accuracy: 1e-12)
    }

    func testTypiskaNattenTarBaraTidigareRiktigaNätter() throws {
        let start = Date(timeIntervalSince1970: t0)
        func natt(_ dagarFöre: Double, _ fönster: Int, _ puls: Double) -> NightCurve.Past {
            NightCurve.Past(end: start.addingTimeInterval(-dagarFöre * 86_400), validWindows: fönster,
                            profile: profil(puls))
        }
        // Två riktiga nätter före, ett prov och en natt efter: för få.
        let för = [natt(1, 90, 50), natt(2, 90, 52), natt(3, 10, 99), natt(-1, 90, 99)]
        XCTAssertNil(NightCurve.typical(before: start, nights: för))
        // En till riktig natt före: tre nätter, och provet och natten efter syns inte.
        let t = try XCTUnwrap(NightCurve.typical(before: start, nights: för + [natt(4, 90, 60)]))
        XCTAssertEqual(t.nights, 3)
        XCTAssertEqual(try XCTUnwrap(t.heartRate.first).median, 52)
        // Högst 28 nätter, de senaste.
        let många: [NightCurve.Past] = (1...40).map { (k: Int) -> NightCurve.Past in natt(Double(k), 90, Double(k)) }
        let m = try XCTUnwrap(NightCurve.typical(before: start, nights: många))
        XCTAssertEqual(m.nights, 28)
        XCTAssertEqual(try XCTUnwrap(m.heartRate.first).median, 14.5, accuracy: 1e-12)
    }
}
