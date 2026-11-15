import Foundation
import XCTest
@testable import Night

// PÅHITTADE minuter och nätter, bara tal. METOD M22: nattlandskapet på
// väggklockan, över midnatt och mellan zoner.

final class NightLandscapeTests: XCTestCase {
    /// En påhittad lokal midnatt (dag 20 000 efter 1970), i väggklockans tal.
    let midnatt: TimeInterval = 20_000 * 86_400

    /// `antal` minuter från väggklockans `lokalStart` i zonen `zon`.
    func minuter(lokalStart: TimeInterval, zon: Int, antal: Int,
                 puls: (Int) -> Double?) -> [NightCurve.Minute] {
        (0..<antal).map { (k: Int) -> NightCurve.Minute in
            NightCurve.Minute(start: lokalStart - TimeInterval(zon) + Double(k) * 60,
                              heartRate: puls(k), beats: 60, kept: 60, omitted: 0)
        }
    }

    // MARK: Profilen

    func testSammaKlockslagISammaStegOavsettZon() throws {
        // 23:00–07:00 väggklocka, i UTC+2 och i UTC−5.
        let fall = { (k: Int) -> Double? in 60 - Double(k) / 60 }
        let hemma = try XCTUnwrap(NightLandscape.profile(
            minutes: minuter(lokalStart: midnatt - 3600, zon: 7200, antal: 480, puls: fall), utcOffsetSeconds: 7200))
        let borta = try XCTUnwrap(NightLandscape.profile(
            minutes: minuter(lokalStart: midnatt - 3600, zon: -18_000, antal: 480, puls: fall), utcOffsetSeconds: -18_000))
        XCTAssertEqual(hemma, borta)
        XCTAssertEqual(hemma.firstBin, 132, "kl. 23 är 11 timmar efter kl. 12")
        XCTAssertEqual(hemma.heartRate.count, 96, "8 timmar i steg om 5 min")
        XCTAssertEqual(try XCTUnwrap(hemma.heartRate[0]), 60 - 2.0 / 60, accuracy: 1e-9, "medel av minut 0–4")
        XCTAssertEqual(NightLandscape.Scene.clockMinutes(bin: hemma.firstBin), 23 * 60)
        XCTAssertEqual(NightLandscape.Scene.clockMinutes(bin: hemma.endBin), 7 * 60)
    }

    func testÖverMidnatt() throws {
        let jämn = { (_: Int) -> Double? in 55 }
        func första(_ lokal: TimeInterval) throws -> Int {
            try XCTUnwrap(NightLandscape.profile(minutes: minuter(lokalStart: lokal, zon: 3600, antal: 60, puls: jämn),
                                                 utcOffsetSeconds: 3600)).firstBin
        }
        // 23:55 och 00:05 hamnar på var sin sida om midnatt, i följd på samma axel.
        XCTAssertEqual(try första(midnatt - 300), 143)
        XCTAssertEqual(try första(midnatt + 300), 145)
        XCTAssertEqual(try första(midnatt + 1800), 150)
        XCTAssertEqual(NightLandscape.Scene.clockMinutes(bin: 144), 0)
        XCTAssertEqual(NightLandscape.Scene.clockMinutes(bin: 150), 30)
    }

    func testStegMedFärreÄnTreMinuterÄrTomt() throws {
        // Första steget har bara två minuter med puls, nästa fem.
        let p = try XCTUnwrap(NightLandscape.profile(
            minutes: minuter(lokalStart: midnatt, zon: 0, antal: 10) { (k: Int) -> Double? in
                if k >= 5 { return 52 }
                return k < 2 ? 50 : nil
            }, utcOffsetSeconds: 0))
        XCTAssertEqual(p.firstBin, 144)
        XCTAssertNil(p.heartRate[0])
        XCTAssertEqual(p.heartRate[1], 52)
        XCTAssertEqual(p.heartRate(atBin: 145), 52)
        XCTAssertNil(p.heartRate(atBin: 146), "utanför profilen")
        XCTAssertNil(NightLandscape.profile(minutes: minuter(lokalStart: midnatt, zon: 0, antal: 10) { (_: Int) -> Double? in nil },
                                            utcOffsetSeconds: 0))
    }

    // MARK: Scenen

    func natt(_ i: Int, giltiga: Int = 40, profil: NightLandscape.Profile?) -> NightLandscape.Night {
        NightLandscape.Night(end: Date(timeIntervalSince1970: midnatt + Double(i) * 86_400), utcOffsetSeconds: 0,
                             validWindows: giltiga, restingHeartRate: 50, rmssd: 40, profile: profil)
    }

    func testScenenTarDeSenasteOchLäggerDenNyasteSist() throws {
        var nätter: [NightLandscape.Night] = []
        for i in 0..<35 {
            let p = NightLandscape.Profile(firstBin: 132 + i % 3, heartRate: [50 + Double(i % 5), 60, nil, 55])
            nätter.append(natt(i, giltiga: i == 34 ? 10 : 40, profil: p))
        }
        nätter.append(natt(40, profil: nil))
        let s = try XCTUnwrap(NightLandscape.scene(nätter.shuffled()))
        XCTAssertEqual(s.ridges.count, 30)
        XCTAssertEqual(s.ridges.first?.end, nätter[4].end, "äldst först")
        XCTAssertEqual(s.ridges.last?.end, nätter[33].end, "en för kort natt och en utan profil räknas inte")
        XCTAssertEqual(s.bins, 132...144, "hela timmar kring 132–138")
        XCTAssertEqual(s.heartRate, 50...60)
        XCTAssertNil(NightLandscape.scene([natt(1, giltiga: 10, profil: nätter[0].profile)]))
    }

    // MARK: Bilden och trycket

    func testLägetOchTräffen() throws {
        let platt = NightLandscape.Profile(firstBin: 132, heartRate: [Double?](repeating: 60, count: 12))
        let s = try XCTUnwrap(NightLandscape.scene([natt(0, profil: platt), natt(1, profil: platt), natt(2, profil: platt)]))
        XCTAssertEqual(s.heartRate, 59...61, "lika puls överallt ger ±1")
        let l = NightLandscape.Layout(width: 120, height: 100, scene: s, overlap: 3)
        XCTAssertEqual(l.rowSpacing, 20, accuracy: 1e-9)
        XCTAssertEqual(l.baseline(0), 60, accuracy: 1e-9)
        XCTAssertEqual(l.baseline(2), 100, accuracy: 1e-9)
        XCTAssertEqual(l.y(2, heartRate: 61), 40, accuracy: 1e-9, "högsta pulsen når tre rader upp")
        XCTAssertEqual(l.y(2, heartRate: 60), 70, accuracy: 1e-9)
        XCTAssertEqual(l.x(bin: 132), 5, accuracy: 1e-9)
        XCTAssertEqual(l.bin(x: 5), 132)

        // Den främsta åsen täcker 70–100, den mittersta 50–80, den bakersta 30–60.
        XCTAssertEqual(l.hit(x: 60, y: 75, scene: s), 2)
        XCTAssertEqual(l.hit(x: 60, y: 65, scene: s), 1)
        XCTAssertEqual(l.hit(x: 60, y: 45, scene: s), 0)
        XCTAssertEqual(l.hit(x: 60, y: 5, scene: s), 0, "ovanför allt: närmaste baslinje")
        XCTAssertEqual(l.hit(x: 500, y: 79, scene: s), 1, "utanför klockan: närmaste baslinje")
    }
}
