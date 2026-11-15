import Foundation
import XCTest
import HeartRate
@testable import Night

// PÅHITTADE nätter (NightGenerator.swift, OmissionTests.swift) och handgjorda
// par, bara tal. METOD M21: Poincarédiagrammet, SD1 och SD2 enligt Brennan,
// Palaniswami & Kamen (2001), och rutnätet.

final class PoincareTests: XCTestCase {
    let roten2: Double = 2.0.squareRoot()

    // MARK: Paren

    func testParenFöljerSkillnadernasRegel() throws {
        // En timme där bandet utelämnar var tionde slag (METOD M3, BESLUT B17).
        let n = OmittingGenerator.night(seconds: 3600, seed: 1, meanRR: 985, omit: 0.10)
        let beats = RRCleaning.clean(n.night)
        let par = Poincare.pairs(beats)
        let skillnader = RRCleaning.differences(beats)
        XCTAssertEqual(par.count, skillnader.count)
        for (p, d) in zip(par, skillnader) {
            XCTAssertEqual(p.y - p.x, d.milliseconds, accuracy: 1e-9)
            XCTAssertEqual(p.time, d.time)
        }
        // Luckorna tar bort par: färre par än grannar i serien.
        let luckor: Int = beats.filter(\.gapBefore).count
        XCTAssertGreaterThan(luckor, 0)
        XCTAssertLessThanOrEqual(par.count, beats.count - 1 - luckor)
        // Paren ligger i tidsordning (uppspelningen söker binärt).
        XCTAssertTrue(zip(par, par.dropFirst()).allSatisfy { (a: Poincare.Pair, b: Poincare.Pair) -> Bool in a.time <= b.time })
    }

    func testIngetParÖverLuckaKastatSlagEllerGlapp() {
        let b: [Beat] = [
            Beat(time: 1, rrMilliseconds: 1000, segment: 0),
            Beat(time: 2, rrMilliseconds: 1010, segment: 0),                       // par (1000, 1010)
            Beat(time: 4, rrMilliseconds: 990, segment: 0, gapBefore: true),       // utelämnat före: inget par
            Beat(time: 5, rrMilliseconds: 1500, segment: 0, verdict: .deviatesFromMedian), // kastat: två par bort
            Beat(time: 6, rrMilliseconds: 1005, segment: 0),
            Beat(time: 7, rrMilliseconds: 995, segment: 0),                        // par (1005, 995)
            Beat(time: 90, rrMilliseconds: 1000, segment: 1),                      // nytt avsnitt: inget par
            Beat(time: 91, rrMilliseconds: 980, segment: 1),                       // par (1000, 980)
        ]
        let par = Poincare.pairs(b)
        XCTAssertEqual(par, [Poincare.Pair(time: 2, x: 1000, y: 1010),
                             Poincare.Pair(time: 7, x: 1005, y: 995),
                             Poincare.Pair(time: 91, x: 1000, y: 980)])
    }

    // MARK: SD1 och SD2

    func testSD1ÄrRMSSDGenomRotenUrTvå() throws {
        let n = OmittingGenerator.night(seconds: 3600, seed: 1, meanRR: 985, omit: 0.10)
        let beats = RRCleaning.clean(n.night)
        let d = try XCTUnwrap(Poincare.descriptors(Poincare.pairs(beats)))
        let rmssd: Double = OmittingGenerator.rmssd(RRCleaning.differences(beats).map(\.milliseconds))
        XCTAssertEqual(d.rmssd, rmssd, accuracy: 1e-9)
        // Brennan ekv. 6: SD1² = ½ SDSD², exakt.
        XCTAssertEqual(d.sd1, d.sdsd / roten2, accuracy: 1e-9)
        // Och SDSD = RMSSD när skillnadernas medel är noll (stationärt): på en
        // natt med andning och brus nästan exakt.
        XCTAssertEqual(d.sd1 / (rmssd / roten2), 1, accuracy: 1e-3)
        XCTAssertGreaterThan(d.sd1, 20)
    }

    func testSD2UrSDRRochSDSD() throws {
        let n = OmittingGenerator.night(seconds: 3600, seed: 7, meanRR: 1100, omit: 0.05)
        let beats = RRCleaning.clean(n.night)
        let d = try XCTUnwrap(Poincare.descriptors(Poincare.pairs(beats)))
        // Ekv. 9: SD1² + SD2² = 2 SDRR², exakt med parens SDRR.
        XCTAssertEqual(d.sd1 * d.sd1 + d.sd2 * d.sd2, 2 * d.sdrr * d.sdrr, accuracy: 1e-6 * d.sdrr * d.sdrr)
        // Ekv. 10: SD2² = 2 SDRR² − ½ SDSD², med SDRR ur nattens alla behållna
        // slag, räknad för sig: stämmer på någon promille.
        let rr: [Double] = beats.filter(\.isKept).map(\.rrMilliseconds)
        let medel: Double = rr.reduce(0, +) / Double(rr.count)
        let varians: Double = rr.reduce(0.0) { (a: Double, x: Double) -> Double in a + (x - medel) * (x - medel) } / Double(rr.count)
        let sd2: Double = (2 * varians - 0.5 * d.sdsd * d.sdsd).squareRoot()
        XCTAssertEqual(d.sd2 / sd2, 1, accuracy: 0.01)
        XCTAssertGreaterThan(d.sd2, d.sd1, "andningen gör molnet längre än brett")
    }

    func testVäxlandeSerieHarIngenLängd() throws {
        // Brennan m.fl. Fig. 2a: a, b, a, b ... ger två punkter, (a, b) och
        // (b, a). Längden (SD2) är noll, bredden |a − b|/√2.
        var par: [Poincare.Pair] = []
        for i in 0..<100 {
            par.append(i % 2 == 0 ? Poincare.Pair(time: Double(i), x: 975, y: 1025)
                                  : Poincare.Pair(time: Double(i), x: 1025, y: 975))
        }
        let d = try XCTUnwrap(Poincare.descriptors(par))
        XCTAssertEqual(d.sd2, 0, accuracy: 1e-9)
        XCTAssertEqual(d.sd1, 50 / roten2, accuracy: 1e-9)
        XCTAssertEqual(d.sdrr, 25, accuracy: 1e-9)
        XCTAssertEqual(d.meanX, 1000, accuracy: 1e-9)
        XCTAssertNil(d.ratio, "SD2 = 0 ger ingen kvot")
        XCTAssertNil(Poincare.descriptors([par[0]]), "ett par räcker inte")
    }

    func testEllipsenOchAxlarna() throws {
        let d = Poincare.Descriptors(count: 10, meanX: 1000, meanY: 1010, sd1: 10, sd2: 40,
                                     sdsd: 10 * roten2, rmssd: 10 * roten2, sdrr: 29.15)
        let e = Poincare.ellipse(d, points: 48)
        XCTAssertEqual(e.count, 49)
        XCTAssertEqual(e.first, e.last)
        for p in e {
            // Tillbaka till de vridna axlarna: tvärs och längs identitetslinjen.
            let dx: Double = p.x - d.meanX
            let dy: Double = p.y - d.meanY
            let längs: Double = (dx + dy) / roten2
            let tvärs: Double = (dy - dx) / roten2
            XCTAssertEqual(pow(längs / d.sd2, 2) + pow(tvärs / d.sd1, 2), 1, accuracy: 1e-9)
        }
        let a = Poincare.axes(d)
        XCTAssertEqual(hypot(a.sd1.x - d.meanX, a.sd1.y - d.meanY), 10, accuracy: 1e-9)
        XCTAssertEqual(hypot(a.sd2.x - d.meanX, a.sd2.y - d.meanY), 40, accuracy: 1e-9)
        XCTAssertEqual(a.sd2.x - d.meanX, a.sd2.y - d.meanY, accuracy: 1e-9, "SD2 längs identitetslinjen")
    }

    // MARK: Axeln och rutorna

    func testAxelnAvrundasOchHarEnMinstaLängd() throws {
        let jämn: [Poincare.Pair] = (0..<50).map { (i: Int) -> Poincare.Pair in Poincare.Pair(time: Double(i), x: 1000, y: 1000) }
        XCTAssertEqual(Poincare.axis(jämn), 900...1100)
        let bred: [Poincare.Pair] = (0..<1000).map { (i: Int) -> Poincare.Pair in
            Poincare.Pair(time: Double(i), x: 812 + Double(i % 376), y: 1187 - Double(i % 376))
        }
        XCTAssertEqual(Poincare.axis(bred), 800...1200)
        XCTAssertNil(Poincare.axis([]))
    }

    func testRutornasAntal() {
        let par: [Poincare.Pair] = [
            Poincare.Pair(time: 0, x: 1000, y: 1000),
            Poincare.Pair(time: 1, x: 1000, y: 1000),
            Poincare.Pair(time: 2, x: 995, y: 1000),    // samma ruta (993,75–1001,6)
            Poincare.Pair(time: 3, x: 1100, y: 900),    // övre och nedre änden
            Poincare.Pair(time: 4, x: 1200, y: 1000),   // utanför
            Poincare.Pair(time: 5, x: 899.9, y: 1000),  // utanför
        ]
        let h = Poincare.histogram(par, axis: 900...1100)
        XCTAssertEqual(h.binWidth, 7.8125)
        XCTAssertEqual(h.bins, 26, "200 ms / 7,8125 ms = 25,6, uppåt")
        // 1000 ms ligger 100 ms in: ruta 12 (12,8).
        XCTAssertEqual(h.count(x: 12, y: 12), 3)
        XCTAssertEqual(h.count(x: 25, y: 0), 1, "övre änden i sista rutan")
        XCTAssertEqual(h.outside, 2)
        XCTAssertEqual(h.total + h.outside, par.count)
        XCTAssertEqual(h.maxCount, 3)
        XCTAssertEqual(h.count(x: 26, y: 0), 0, "utanför rutnätet är tomt")
    }

    func testTäthetensKlasser() {
        XCTAssertEqual(Poincare.densityClass(0, max: 100, classes: 6), 0)
        XCTAssertEqual(Poincare.densityClass(1, max: 100, classes: 6), 1)
        XCTAssertEqual(Poincare.densityClass(10, max: 100, classes: 6), 4, "halvvägs i logaritmen")
        XCTAssertEqual(Poincare.densityClass(100, max: 100, classes: 6), 6)
        XCTAssertEqual(Poincare.densityClass(1, max: 1, classes: 6), 6)
    }

    // MARK: Pulsaxeln (BESLUT B32)

    func testPulsenUrIntervallet() {
        XCTAssertEqual(Poincare.pulse(1000), 60, accuracy: 1e-12)
        XCTAssertEqual(Poincare.pulse(750), 80, accuracy: 1e-12)
        XCTAssertEqual(Poincare.pulse(Poincare.pulse(857)), 857, accuracy: 1e-9)
    }

    func testPulsaxelnsStreck() {
        // 750–1350 ms är 44,4–80 slag/min: steg 5 ger åtta streck, steg 10 fyra.
        XCTAssertEqual(Poincare.pulseTicks(750...1350), [50, 60, 70, 80])
        // Minsta axeln (200 ms) kring 60 slag/min: 54,5–66,7.
        XCTAssertEqual(Poincare.pulseTicks(900...1100), [55, 60, 65])
        // Långsam puls: 37,5–42,9 slag/min, steg 1.
        XCTAssertEqual(Poincare.pulseTicks(1400...1600), [38, 39, 40, 41, 42])
        XCTAssertEqual(Poincare.pulseTicks(0...1000), [])
    }

    func testPulsaxelnHarAlltidStreckInomAxeln() {
        // Varje axel `axis(_:)` kan ge: minst 200 ms, ändar på hela 50 ms.
        // Ett steg är högst 2,5 gånger det förra, så fler än fem streck med
        // ett steg ger minst två med nästa.
        for lo in stride(from: 300.0, through: 2000.0, by: 50) {
            for span in stride(from: 200.0, through: 1200.0, by: 50) {
                let axel: ClosedRange<Double> = lo...(lo + span)
                let streck = Poincare.pulseTicks(axel)
                XCTAssertGreaterThanOrEqual(streck.count, 2, "\(axel)")
                XCTAssertLessThanOrEqual(streck.count, Poincare.maxPulseTicks, "\(axel)")
                for s in streck {
                    XCTAssertTrue(axel.contains(Poincare.pulse(s)), "\(s) utanför \(axel)")
                    XCTAssertEqual(s, s.rounded(), "hela slag/min")
                }
                XCTAssertEqual(streck, streck.sorted())
            }
        }
    }

    // MARK: Uppspelningen

    func testFönstretGenomNatten() {
        let par: [Poincare.Pair] = (0..<100).map { (i: Int) -> Poincare.Pair in Poincare.Pair(time: Double(i), x: 1000, y: 1000) }
        XCTAssertEqual(Poincare.window(par, endingAt: 50, seconds: 10), 41..<51)
        XCTAssertEqual(Poincare.window(par, endingAt: -5, seconds: 10), 0..<0)
        XCTAssertEqual(Poincare.window(par, endingAt: 500, seconds: 10), 100..<100)
        XCTAssertEqual(Poincare.window(par, endingAt: 3.5, seconds: 300), 0..<4)
    }
}
