import Foundation
import XCTest
import WhoopFrames
import DemoData
@testable import Night

// METOD M26 · BESLUT B73. Påhittade nätter (DemoSleep) och påhittade vinkelserier, bara tal.
// Stegen provas för sig med små serier där svaret går att räkna för hand, och
// metoden som helhet på nätter vars insomning och uppvaknande är kända.

final class SleepDetectionTests: XCTestCase {
    static let t0 = 1_760_000_040 // delbart med 5 och 60
    static let minute = 60

    func rec(_ t: Int, angle: Double) -> K18Record {
        let theta: Double = angle * Double.pi / 180
        return K18Record(time: t, pulse: 55, rr: [],
                         gravity: .init(x: cos(theta), y: 0, z: sin(theta)),
                         skinTemperature: 33, bandTemperature: 30)
    }

    // MARK: Z-vinkeln

    func testZVinkelnUrGravitationen() throws {
        func a(_ x: Double, _ y: Double, _ z: Double) throws -> Double {
            try XCTUnwrap(SleepDetection.zAngle(.init(x: x, y: y, z: z)))
        }
        XCTAssertEqual(try a(0, 0, 1), 90, accuracy: 1e-9)
        XCTAssertEqual(try a(1, 0, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(try a(0, 0, -1), -90, accuracy: 1e-9)
        XCTAssertEqual(try a(1, 0, 1), 45, accuracy: 1e-9)
        // Vridning kring z ändrar inte vinkeln mot horisontalplanet.
        XCTAssertEqual(try a(0.6, 0.8, 1), 45, accuracy: 1e-9)
        XCTAssertEqual(try a(-0.6, 0.8, 1), 45, accuracy: 1e-9)
        // Längden spelar ingen roll, bara riktningen.
        XCTAssertEqual(try a(0, 0, 0.98), 90, accuracy: 1e-9)
        XCTAssertNil(SleepDetection.zAngle(.init(x: .nan, y: 0, z: 1)))
    }

    // MARK: Epoker och steg

    func testEnEpokKräverTreSekunder() throws {
        let first = Self.t0 / SleepDetection.epochSeconds
        // Epok 0: fem sekunder 10…50 grader (medel 30). Epok 1: tre sekunder
        // (medel 20). Epok 2: två sekunder, saknas. Epok 3: ingen alls.
        var recs: [K18Record] = []
        for (j, ang) in [10.0, 20, 30, 40, 50].enumerated() { recs.append(rec(Self.t0 + j, angle: ang)) }
        for (j, ang) in [10.0, 20, 30].enumerated() { recs.append(rec(Self.t0 + 5 + j, angle: ang)) }
        for (j, ang) in [10.0, 20].enumerated() { recs.append(rec(Self.t0 + 10 + j, angle: ang)) }
        let a = SleepDetection.epochAngles(K18Series(records: recs).records, first: first, count: 4)
        XCTAssertEqual(try XCTUnwrap(a[0]), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a[1]), 20, accuracy: 1e-9)
        XCTAssertNil(a[2], "två sekunder är för lite")
        XCTAssertNil(a[3])
    }

    func testStegenSaknasÖverEttGlapp() {
        let s = SleepDetection.angleSteps([10, 12, nil, 20, 21.5, nil, nil, 30])
        XCTAssertNil(s[0])
        XCTAssertEqual(s[1], 2)
        XCTAssertNil(s[2])
        XCTAssertNil(s[3], "ingen ändring över ett glapp")
        XCTAssertEqual(s[4], 1.5)
        XCTAssertNil(s[5])
        XCTAssertNil(s[7])
    }

    // MARK: Rullande median, percentil och tröskel

    func testRullandeMedianenTarBortEnstakaRörelse() throws {
        // 100 steg på 1,0 med tre stora (10) i mitten: medianen över 60 ändras inte.
        var steps = [Double?](repeating: 1.0, count: 100)
        steps[50] = 10
        steps[51] = 10
        steps[52] = 10
        let m = SleepDetection.rollingMedian(steps)
        XCTAssertEqual(try XCTUnwrap(m[50]), 1.0)
        XCTAssertEqual(try XCTUnwrap(m[0]), 1.0, "halvt fönster räcker precis")
    }

    func testRullandeMedianenKräverMinstTrettioSteg() {
        // Steg bara från epok 40: epok 35 har 25 steg i sitt fönster, epok 45 har 35.
        var steps = [Double?](repeating: nil, count: 100)
        for i in 40..<100 { steps[i] = 1.0 }
        let m = SleepDetection.rollingMedian(steps)
        XCTAssertNil(m[35])
        XCTAssertNotNil(m[45])
        XCTAssertNil(m[0])
    }

    func testPercentilenInterpolerarMellanRangerna() {
        XCTAssertEqual(SleepDetection.percentile([1, 2, 3, 4, 5], 0.10), 1.4, accuracy: 1e-12)
        XCTAssertEqual(SleepDetection.percentile([5, 1, 4, 2, 3], 0.10), 1.4, accuracy: 1e-12)
        XCTAssertEqual(SleepDetection.percentile([1, 2, 3, 4], 0.5), 2.5, accuracy: 1e-12)
        XCTAssertEqual(SleepDetection.percentile([7], 0.10), 7)
    }

    func testTröskelnÄrTioProcentGånger15InomIntervallet() {
        XCTAssertEqual(SleepDetection.threshold(percentile10: 0.001), 0.13, accuracy: 1e-12, "golv")
        XCTAssertEqual(SleepDetection.threshold(percentile10: 0.02), 0.30, accuracy: 1e-12)
        XCTAssertEqual(SleepDetection.threshold(percentile10: 1.0), 0.50, accuracy: 1e-12, "tak")
    }

    // MARK: Block

    func testBlockMåsteVaraLängreÄnTrettioMinuter() {
        let n = 2000
        // 361 epoker = 1805 s: längre än 30 minuter. 360 epoker = 1800 s: inte längre.
        var lång = [Double?](repeating: 9, count: n)
        for i in 100..<461 { lång[i] = 0.1 }
        XCTAssertEqual(SleepDetection.blocks(lång, threshold: 0.5), [100..<461])
        var exakt = [Double?](repeating: 9, count: n)
        for i in 100..<460 { exakt[i] = 0.1 }
        XCTAssertEqual(SleepDetection.blocks(exakt, threshold: 0.5), [])
        // En saknad epok avbryter blocket.
        var avbruten = lång
        avbruten[300] = nil
        XCTAssertEqual(SleepDetection.blocks(avbruten, threshold: 0.5), [])
        // Tröskeln är en gräns: lika med tröskeln är inte under.
        var lika = [Double?](repeating: 9, count: n)
        for i in 100..<461 { lika[i] = 0.5 }
        XCTAssertEqual(SleepDetection.blocks(lika, threshold: 0.5), [])
    }

    func testGlappUnderEnTimmeSlåsIhop() {
        let a = 0..<361
        // 719 epoker = 3595 s: slås ihop. 720 epoker = 3600 s: "less than 60
        // minutes" gäller inte.
        XCTAssertEqual(SleepDetection.merged([a, 1080..<1441]), [0..<1441])
        XCTAssertEqual(SleepDetection.merged([a, 1081..<1442]), [a, 1081..<1442])
        // Slås ihop i kedja: det sammanslagna blockets slut gäller.
        XCTAssertEqual(SleepDetection.merged([0..<400, 1000..<1400, 2000..<2400]), [0..<2400])
    }

    func testGrannblockLäggsTillUnderTvåTimmarOchMinstEnTimmeLånga() {
        // BESLUT B73. 720 epoker = 1 h. Det valda blocket är 4 h; grannen före är 1 h med 1439 epoker (119,9 min)
        // emellan: läggs till. 1440 epoker (120 min) är inte "kortare än 120".
        let valt = 3000..<5880
        XCTAssertEqual(SleepDetection.withNeighbours([841..<1561, valt], chosen: valt), 841..<5880)
        XCTAssertEqual(SleepDetection.withNeighbours([840..<1560, valt], chosen: valt), valt)
        // Grannen 719 epoker (59,9 min) är för kort: en kvällsslummer blir inte insomning.
        XCTAssertEqual(SleepDetection.withNeighbours([842..<1561, valt], chosen: valt), valt)
        // Åt båda håll och i kedja; en kort granne stoppar kedjan på sin sida.
        let fyra: [Range<Int>] = [0..<720, 1500..<2250, valt, 6600..<7400, 8800..<9000]
        XCTAssertEqual(SleepDetection.withNeighbours(fyra, chosen: valt), 0..<7400)
        XCTAssertEqual(SleepDetection.withNeighbours([valt], chosen: valt), valt)
        XCTAssertEqual(SleepDetection.withNeighbours([], chosen: valt), valt, "ett block utanför listan står kvar")
    }

    func testDetLängstaBlocketVinnerOchVidLikaDetTidigaste() {
        XCTAssertEqual(SleepDetection.longest([0..<400, 5000..<5600, 9000..<9300]), 5000..<5600)
        XCTAssertEqual(SleepDetection.longest([0..<400, 5000..<5400]), 0..<400)
        XCTAssertNil(SleepDetection.longest([]))
    }

    // MARK: Ihållande inaktivitet

    func testEttPassKräverFemMinuter() {
        let sextio = [Double?](repeating: 10, count: 60) // 300 s
        let femtionio = [Double?](repeating: 10, count: 59)
        XCTAssertEqual(SleepDetection.inactivity(sextio, SleepDetection.angleSteps(sextio)),
                       [Bool](repeating: true, count: 60))
        XCTAssertEqual(SleepDetection.inactivity(femtionio, SleepDetection.angleSteps(femtionio)),
                       [Bool](repeating: false, count: 59))
    }

    func testEnÄndringPåExaktFemGraderBryterInteMenFemKommaEnGör() {
        // 30 epoker på 10 och 30 på 15: steget är exakt 5, inte "larger than 5".
        let exakt = [Double?](repeating: 10, count: 30) + [Double?](repeating: 15, count: 30)
        XCTAssertEqual(SleepDetection.inactivity(exakt, SleepDetection.angleSteps(exakt)),
                       [Bool](repeating: true, count: 60))
        // 59 på 10 och 60 på 15,1: steget 5,1 bryter. Det första passet är för
        // kort; det andra börjar på epoken där ändringen skedde.
        let bryter = [Double?](repeating: 10, count: 59) + [Double?](repeating: 15.1, count: 60)
        let r = SleepDetection.inactivity(bryter, SleepDetection.angleSteps(bryter))
        XCTAssertEqual(Array(r[0..<59]), [Bool](repeating: false, count: 59))
        XCTAssertEqual(Array(r[59...]), [Bool](repeating: true, count: 60))
    }

    func testEnSaknadEpokAvbryterPasset() {
        var a = [Double?](repeating: 10, count: 59)
        a.append(nil)
        a += [Double?](repeating: 10, count: 60)
        let r = SleepDetection.inactivity(a, SleepDetection.angleSteps(a))
        XCTAssertEqual(Array(r[0..<59]), [Bool](repeating: false, count: 59))
        XCTAssertFalse(r[59])
        XCTAssertEqual(Array(r[60...]), [Bool](repeating: true, count: 60))
    }

    // MARK: Nätter

    func natt(_ phases: [DemoSleep.Phase], seed: UInt64 = 7)
        -> (period: SleepPeriod?, series: K18Series, start: Int, end: Int) {
        let recs: [K18Record] = DemoSleep.records(start: Self.t0, phases: phases, seed: seed)
        var seconds = 0
        for p in phases {
            switch p {
            case .still(let s), .active(let s), .gap(let s): seconds += s
            case .restless(let s, _): seconds += s
            case .turn: break
            }
        }
        let series = K18Series(records: recs)
        let from = Date(timeIntervalSince1970: Double(Self.t0 - 600))
        let to = Date(timeIntervalSince1970: Double(Self.t0 + seconds + 600))
        return (SleepDetection.detect(series, from: from, to: to), series, Self.t0, Self.t0 + seconds)
    }

    func assertSumman(_ p: SleepPeriod, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.asleepSeconds + p.awakeSeconds + p.gapSeconds, p.periodSeconds,
                       "perioden är sömn + vaken + glapp", file: file, line: line)
        XCTAssertEqual(p.wakeBouts.map(\.seconds).reduce(0, +), p.awakeSeconds, file: file, line: line)
        XCTAssertEqual(p.gaps.map(\.seconds).reduce(0, +), p.gapSeconds, file: file, line: line)
    }

    func testStillaNatt() throws {
        let m = Self.minute
        let n = natt([.active(seconds: 30 * m), .still(seconds: 180 * m), .turn, .still(seconds: 120 * m),
                      .turn, .still(seconds: 120 * m), .active(seconds: 30 * m)])
        let p = try XCTUnwrap(n.period)
        XCTAssertEqual(Double(p.onset), Double(Self.t0 + 30 * m), accuracy: 120)
        XCTAssertEqual(Double(p.wake), Double(Self.t0 + 450 * m), accuracy: 120)
        // Två vändningar i en stilla natt gör ingen stund vaken: varje del
        // mellan dem är längre än fem minuter.
        XCTAssertLessThanOrEqual(p.awakeSeconds, 60)
        XCTAssertEqual(p.gapSeconds, 0)
        XCTAssertEqual(try XCTUnwrap(p.coverage), 1.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(p.efficiency), 1.0, accuracy: 0.01)
        assertSumman(p)
        // Minuterna ligger inom perioden och är nästan alla.
        XCTAssertTrue(p.asleepMinutes.allSatisfy { $0 >= p.onset / 60 - 1 && $0 <= p.wake / 60 })
        XCTAssertEqual(Double(p.asleepMinutes.count), Double(p.asleepSeconds) / 60, accuracy: 2)
        // Blocket är perioden eller något större.
        XCTAssertLessThanOrEqual(p.windowStart, p.onset)
        XCTAssertGreaterThanOrEqual(p.windowEnd, p.wake)
        XCTAssertGreaterThanOrEqual(p.threshold, SleepDetection.thresholdRange.lowerBound)
        XCTAssertLessThanOrEqual(p.threshold, SleepDetection.thresholdRange.upperBound)
    }

    func testOroligNattHarVaknaStunderPåRättStälle() throws {
        let m = Self.minute
        // Orolig 20 min efter 2 h, och 15 min efter ytterligare 2 h 20 min.
        let n = natt([.active(seconds: 30 * m), .still(seconds: 120 * m), .restless(seconds: 20 * m, every: 100),
                      .still(seconds: 120 * m), .restless(seconds: 15 * m, every: 100),
                      .still(seconds: 120 * m), .active(seconds: 30 * m)])
        let p = try XCTUnwrap(n.period)
        XCTAssertEqual(Double(p.onset), Double(Self.t0 + 30 * m), accuracy: 120)
        XCTAssertEqual(Double(p.wake), Double(Self.t0 + 425 * m), accuracy: 120)
        XCTAssertEqual(p.wakeBouts.count, 2)
        // 35 minuter oroliga, minus ett steg på 100 s i varje: ungefär 32 min.
        XCTAssertEqual(Double(p.awakeSeconds) / 60, 31.7, accuracy: 3)
        let a = try XCTUnwrap(p.wakeBouts.first)
        let b = try XCTUnwrap(p.wakeBouts.last)
        XCTAssertGreaterThanOrEqual(a.start, Self.t0 + 150 * m - 60)
        XCTAssertLessThanOrEqual(a.end, Self.t0 + 170 * m + 60)
        XCTAssertGreaterThanOrEqual(b.start, Self.t0 + 290 * m - 60)
        XCTAssertLessThanOrEqual(b.end, Self.t0 + 305 * m + 60)
        // Sömntiden är perioden minus de vakna stunderna.
        XCTAssertEqual(Double(p.asleepSeconds), Double(p.periodSeconds - p.awakeSeconds), accuracy: 1)
        XCTAssertLessThan(try XCTUnwrap(p.efficiency), 0.95)
        assertSumman(p)
        // Inga sömnminuter mitt i en orolig stund.
        let mitt = (Self.t0 + 160 * m) / 60
        XCTAssertFalse(p.asleepMinutes.contains(mitt))
    }

    // MARK: Uppvaknandet ur pulsen (BESLUT B100)

    /// Vaken i sängen i 20 min efter fyra timmars sömn, sedan sex minuter stilla (ett inaktivitetspass) och uppe.
    /// Pulsen är 55 i sömnen och `efter` från den vakna stundens början. Samma natt som spegelns `PulsUppvaknande`.
    func pulsnatt(efter: Int) -> SleepPeriod? {
        let m = Self.minute
        let phases: [DemoSleep.Phase] = [.active(seconds: 30 * m), .still(seconds: 240 * m),
                                         .restless(seconds: 20 * m, every: 100), .still(seconds: 6 * m),
                                         .active(seconds: 25 * m)]
        let vaken: Int = Self.t0 + 270 * m
        let recs: [K18Record] = DemoSleep.records(start: Self.t0, phases: phases, seed: 7).map { (r: K18Record) in
            var c: K18Record = r
            c.pulse = r.time >= vaken ? efter : 55
            return c
        }
        return SleepDetection.detect(K18Series(records: recs),
                                     from: Date(timeIntervalSince1970: Double(Self.t0 - 600)),
                                     to: Date(timeIntervalSince1970: Double(Self.t0 + 321 * m + 600)))
    }

    func testPulsenKvarUppeFlyttarUppvaknandetTillDenVaknaStundensBörjan() throws {
        let m = Self.minute
        let utan = try XCTUnwrap(pulsnatt(efter: 55))
        // Utan pulsens höjning är det stilla passet efter den vakna stunden sömn, och uppvaknandet efter det.
        XCTAssertEqual(Double(utan.wake), Double(Self.t0 + 296 * m), accuracy: 120)
        let p = try XCTUnwrap(pulsnatt(efter: 66))
        XCTAssertEqual(Double(p.wake), Double(Self.t0 + 270 * m), accuracy: 10)
        XCTAssertEqual(p.onset, utan.onset)
        XCTAssertEqual(p.windowStart, utan.windowStart)
        XCTAssertEqual(p.windowEnd, utan.windowEnd)
        XCTAssertTrue(p.wakeBouts.allSatisfy { $0.end <= p.wake })
        XCTAssertTrue(p.asleepMinutes.allSatisfy { $0 < p.wake / 60 })
        assertSumman(p)
    }

    func testPulsensGränsÄrSjuSlag() throws {
        let m = Self.minute
        // Medianen före 55: efter 62 är precis sju över och flyttar, 61 gör det inte.
        XCTAssertEqual(Double(try XCTUnwrap(pulsnatt(efter: 62)).wake), Double(Self.t0 + 270 * m), accuracy: 10)
        XCTAssertEqual(Double(try XCTUnwrap(pulsnatt(efter: 61)).wake), Double(Self.t0 + 296 * m), accuracy: 120)
    }

    func testPulsenMittINattenFlyttarInteUppvaknandet() throws {
        let m = Self.minute
        // Den oroliga stunden 150–170 min ligger långt före periodens sista timme.
        let phases: [DemoSleep.Phase] = [.active(seconds: 30 * m), .still(seconds: 120 * m),
                                         .restless(seconds: 20 * m, every: 100), .still(seconds: 120 * m),
                                         .active(seconds: 30 * m)]
        let recs: [K18Record] = DemoSleep.records(start: Self.t0, phases: phases, seed: 7)
        let hög: [K18Record] = recs.map { (r: K18Record) in
            var c: K18Record = r
            c.pulse = r.time >= Self.t0 + 150 * m && r.time < Self.t0 + 170 * m ? 75 : 55
            return c
        }
        let from = Date(timeIntervalSince1970: Double(Self.t0 - 600))
        let to = Date(timeIntervalSince1970: Double(Self.t0 + 320 * m + 600))
        let a = try XCTUnwrap(SleepDetection.detect(K18Series(records: recs), from: from, to: to))
        let b = try XCTUnwrap(SleepDetection.detect(K18Series(records: hög), from: from, to: to))
        XCTAssertEqual(a, b)
    }

    func testNattMedGlappÄrVarkenSömnEllerVaken() throws {
        let m = Self.minute
        // Ett glapp på 40 minuter mitt i natten: kortare än 60, så perioden går över det.
        let n = natt([.active(seconds: 30 * m), .still(seconds: 180 * m), .gap(seconds: 40 * m),
                      .still(seconds: 180 * m), .active(seconds: 30 * m)])
        let p = try XCTUnwrap(n.period)
        XCTAssertEqual(Double(p.onset), Double(Self.t0 + 30 * m), accuracy: 120)
        XCTAssertEqual(Double(p.wake), Double(Self.t0 + 430 * m), accuracy: 120)
        XCTAssertEqual(p.gaps.count, 1)
        XCTAssertEqual(Double(p.gapSeconds), Double(40 * m), accuracy: 10)
        XCTAssertEqual(p.awakeSeconds, 0, "ett glapp är inte vaken tid")
        // Sömntiden räknar inte glappet: 360 minuter, inte 400.
        XCTAssertEqual(Double(p.asleepSeconds) / 60, 360, accuracy: 3)
        XCTAssertEqual(try XCTUnwrap(p.coverage), 360.0 / 400, accuracy: 0.01)
        assertSumman(p)
        // Inga sömnminuter inne i glappet.
        let g = try XCTUnwrap(p.gaps.first)
        XCTAssertFalse(p.asleepMinutes.contains { $0 * 60 >= g.start + 60 && $0 * 60 + 60 <= g.end - 60 })
        XCTAssertFalse(p.asleepMinutes.isEmpty)
    }

    func testEttGlappPåNittioMinuterLiggerInomNatten() throws {
        let m = Self.minute
        // BESLUT B73. 90 minuter utan K18 är mer än 60, så M26 ger två block, men den första halvan (2 h) är en
        // granne mindre än 120 minuter bort och läggs till: perioden går över glappet, som varken är sömn eller vaken.
        let n = natt([.active(seconds: 30 * m), .still(seconds: 120 * m), .gap(seconds: 90 * m),
                      .still(seconds: 240 * m), .active(seconds: 30 * m)])
        let p = try XCTUnwrap(n.period)
        XCTAssertEqual(Double(p.onset), Double(Self.t0 + 30 * m), accuracy: 180)
        XCTAssertEqual(Double(p.wake), Double(Self.t0 + 480 * m), accuracy: 180)
        XCTAssertEqual(Double(p.gapSeconds), Double(90 * m), accuracy: 10, "glappet ligger inom perioden")
        XCTAssertEqual(Double(p.asleepSeconds) / 60, 360, accuracy: 5)
        XCTAssertFalse(p.incompleteStart)
        XCTAssertFalse(p.incompleteEnd)
        assertSumman(p)
    }

    func testEttGlappPåHundrafemtioMinuterDelarNattenOchBörjanSaknas() throws {
        let m = Self.minute
        // 150 minuter utan K18: grannen läggs inte till, det längsta blocket blir natten, och den börjar där datan
        // kom tillbaka (BESLUT B73: början saknas).
        let n = natt([.active(seconds: 30 * m), .still(seconds: 120 * m), .gap(seconds: 150 * m),
                      .still(seconds: 240 * m), .active(seconds: 30 * m)])
        let p = try XCTUnwrap(n.period)
        XCTAssertEqual(Double(p.onset), Double(Self.t0 + 300 * m), accuracy: 180)
        XCTAssertEqual(Double(p.wake), Double(Self.t0 + 540 * m), accuracy: 180)
        XCTAssertEqual(p.gapSeconds, 0, "glappet ligger utanför perioden")
        XCTAssertEqual(Double(p.asleepSeconds) / 60, 240, accuracy: 5)
        XCTAssertTrue(p.incompleteStart)
        XCTAssertFalse(p.incompleteEnd)
        assertSumman(p)
    }

    func testEnVakenStundMittINattenDelarInteNatten() throws {
        let m = Self.minute
        // BESLUT B73: 99 minuter uppe mitt i natten. M26 ger två block (3 h 45 min och 4 h 50 min) och valde det
        // senare; grannblocket läggs nu till, och den vakna stunden blir vaken tid i natten.
        let n = natt([.active(seconds: 30 * m), .still(seconds: 225 * m), .active(seconds: 99 * m),
                      .still(seconds: 290 * m), .active(seconds: 30 * m)])
        let p = try XCTUnwrap(n.period)
        XCTAssertEqual(Double(p.onset), Double(Self.t0 + 30 * m), accuracy: 180, "insomningen är den första")
        XCTAssertEqual(Double(p.wake), Double(Self.t0 + 644 * m), accuracy: 180)
        XCTAssertEqual(Double(p.awakeSeconds) / 60, 99, accuracy: 3)
        XCTAssertEqual(Double(p.asleepSeconds) / 60, 515, accuracy: 5)
        assertSumman(p)
    }

    func testEnKvällsslummerUnderEnTimmeBlirInteInsomning() throws {
        let m = Self.minute
        // BESLUT B73: 40 minuter stilla på kvällen, 100 minuter uppe och sedan natten. Slummern är ett block (över
        // 30 min) men under 60 min: insomningen är nattens.
        let kort = try XCTUnwrap(natt([.active(seconds: 60 * m), .still(seconds: 40 * m), .active(seconds: 100 * m),
                                       .still(seconds: 420 * m), .active(seconds: 30 * m)]).period)
        XCTAssertEqual(Double(kort.onset), Double(Self.t0 + 200 * m), accuracy: 180)
        XCTAssertEqual(kort.awakeSeconds, 0)
        // 70 minuter är en granne: då räknas kvällen in, med de 100 minuterna som vaken tid.
        let lång = try XCTUnwrap(natt([.active(seconds: 60 * m), .still(seconds: 70 * m), .active(seconds: 100 * m),
                                       .still(seconds: 420 * m), .active(seconds: 30 * m)]).period)
        XCTAssertEqual(Double(lång.onset), Double(Self.t0 + 60 * m), accuracy: 180)
        XCTAssertEqual(Double(lång.awakeSeconds) / 60, 100, accuracy: 3)
    }

    // MARK: Ofullständiga nätter (BESLUT B73)

    func testOfullständigNattMärksVidBlocketsKant() throws {
        let m = Self.minute
        // 90 minuter utan K18 som slutar där sömnen börjar: början saknas.
        let början = try XCTUnwrap(natt([.active(seconds: 30 * m), .gap(seconds: 90 * m), .still(seconds: 400 * m),
                                         .active(seconds: 30 * m)]).period)
        XCTAssertTrue(början.incompleteStart)
        XCTAssertFalse(början.incompleteEnd)
        // Datan tar slut i sömnen och kommer tillbaka en timme senare: slutet saknas.
        let slutet = try XCTUnwrap(natt([.active(seconds: 30 * m), .still(seconds: 400 * m), .gap(seconds: 60 * m),
                                         .active(seconds: 20 * m)]).period)
        XCTAssertFalse(slutet.incompleteStart)
        XCTAssertTrue(slutet.incompleteEnd)
        // Tio minuter utan K18 före sömnen är för kort för att märka natten.
        let kort = try XCTUnwrap(natt([.active(seconds: 30 * m), .gap(seconds: 10 * m), .still(seconds: 400 * m),
                                       .active(seconds: 30 * m)]).period)
        XCTAssertFalse(kort.incompleteStart)
        XCTAssertFalse(kort.incompleteEnd)
        // En hel natt märks inte.
        let hel = try XCTUnwrap(natt([.active(seconds: 30 * m), .still(seconds: 400 * m),
                                      .active(seconds: 30 * m)]).period)
        XCTAssertFalse(hel.incompleteStart)
        XCTAssertFalse(hel.incompleteEnd)
    }

    func testOfullständigRäknarPåPosterIDygnsfönstret() {
        let t: Int = Self.t0
        func poster(_ spann: [Range<Int>]) -> [K18Record] {
            spann.flatMap { (r: Range<Int>) -> [K18Record] in r.map { (s: Int) -> K18Record in rec(t + s, angle: 0) } }
        }
        let från: Int = t - 600
        let till: Int = t + 11 * 3600
        // Posterna saknas 1–3 h; blocket börjar 2,5 min efter att de kom tillbaka: början saknas.
        let glapp: [K18Record] = poster([0..<3600, 3 * 3600..<10 * 3600])
        XCTAssertTrue(SleepDetection.incomplete(glapp, from: från, to: till, windowStart: t + 3 * 3600 + 150,
                                                windowEnd: t + 9 * 3600).start)
        // Blocket börjar 20 min efter glappet: inte märkt.
        XCTAssertFalse(SleepDetection.incomplete(glapp, from: från, to: till, windowStart: t + 3 * 3600 + 1200,
                                                 windowEnd: t + 9 * 3600).start)
        // Gränsen: avståndet mellan posterna på var sida av glappet är minst 30 min (1800 s märker, 1799 s inte).
        let exakt: [K18Record] = poster([0..<3600, 5399..<10 * 3600])
        XCTAssertTrue(SleepDetection.incomplete(exakt, from: från, to: till, windowStart: t + 5399 + 60,
                                                windowEnd: t + 9 * 3600).start)
        let under: [K18Record] = poster([0..<3600, 5398..<10 * 3600])
        XCTAssertFalse(SleepDetection.incomplete(under, from: från, to: till, windowStart: t + 5398 + 60,
                                                 windowEnd: t + 9 * 3600).start)
        // Datan tar slut vid blocket och inget kommer före fönstrets slut: slutet saknas.
        let slut = SleepDetection.incomplete(poster([0..<8 * 3600]), from: t, to: till, windowStart: t + 150,
                                             windowEnd: t + 8 * 3600 - 1)
        XCTAssertFalse(slut.start, "posterna börjar vid fönstrets början: inget glapp")
        XCTAssertTrue(slut.end)
        // Fönstrets början räknas som glappets början när inga poster finns före blocket.
        let sent = SleepDetection.incomplete(poster([3600..<8 * 3600]), from: från, to: t + 8 * 3600 + 600,
                                             windowStart: t + 3600 + 150, windowEnd: t + 8 * 3600 - 1)
        XCTAssertTrue(sent.start, "70 min utan poster från fönstrets början")
        XCTAssertFalse(sent.end, "10 min till fönstrets slut är för kort")
        // Poster före fönstret räknas inte: glappet räknas från fönstrets början (15 min, för kort).
        let före: [K18Record] = poster([-3600..<(-1000), 900..<8 * 3600])
        XCTAssertFalse(SleepDetection.incomplete(före, from: t, to: till, windowStart: t + 900 + 150,
                                                 windowEnd: t + 7 * 3600).start)
    }

    /// BESLUT B125. Slutglappet mäts till det tidigaste av fönstrets slut och nu (påhittade poster).
    func testOfullständigtSlutMätsTillNu() {
        let t: Int = Self.t0
        let poster: [K18Record] = (0..<(8 * 3600)).map { (s: Int) -> K18Record in rec(t + s, angle: 0) }
        let från: Int = t
        let till: Int = t + 11 * 3600
        let slutPost: Int = t + 8 * 3600 - 1
        // Räknad strax efter sista posten: datan har inte hunnit längre, inget glapp.
        let strax = SleepDetection.incomplete(poster, from: från, to: till, windowStart: t + 150,
                                              windowEnd: slutPost, now: slutPost + 120)
        XCTAssertFalse(strax.end, "två minuter efter sista posten")
        // Räknad långt efter sista posten (två timmar): slutet saknas.
        let långt = SleepDetection.incomplete(poster, from: från, to: till, windowStart: t + 150,
                                              windowEnd: slutPost, now: slutPost + 2 * 3600)
        XCTAssertTrue(långt.end, "datan slutar två timmar före nu")
        // Utan nu, som förut: till fönstrets slut.
        let utan = SleepDetection.incomplete(poster, from: från, to: till, windowStart: t + 150,
                                             windowEnd: slutPost)
        XCTAssertTrue(utan.end)
        // Nu efter fönstrets slut ändrar inget.
        let efter = SleepDetection.incomplete(poster, from: från, to: till, windowStart: t + 150,
                                              windowEnd: slutPost, now: till + 3600)
        XCTAssertTrue(efter.end)
    }

    func testSammanfattningenBärMärkningen() throws {
        let n: DemoK18Nights.Night = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let zon: Int = n.utcOffsetSeconds
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: zon)
        let hel: NightResult = try XCTUnwrap(K18Night.analyze(K18Series(records: n.records), wakeDay: dag,
                                                              startOffsetSeconds: zon, endOffsetSeconds: zon))
        XCTAssertEqual(NightDigest(hel).incompleteStart, false)
        XCTAssertEqual(NightDigest(hel).incompleteEnd, false)
        // Datan börjar en timme in i sömnen: början saknas, slutet finns.
        let senare = K18Series(records: n.records.filter { (r: K18Record) -> Bool in r.time >= n.onset + 3600 })
        let r: NightResult = try XCTUnwrap(K18Night.analyze(senare, wakeDay: dag, startOffsetSeconds: zon,
                                                            endOffsetSeconds: zon))
        let d = NightDigest(r)
        XCTAssertEqual(d.incompleteStart, true)
        XCTAssertEqual(d.incompleteEnd, false)
        // En sparad sammanfattning utan fälten avkodas ändå.
        let data: Data = try JSONEncoder().encode(d)
        XCTAssertEqual(try JSONDecoder().decode(NightDigest.self, from: data), d)
        var obj: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "incompleteStart")
        obj.removeValue(forKey: "incompleteEnd")
        let gammal = try JSONDecoder().decode(NightDigest.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(gammal.incompleteStart)
        XCTAssertNil(gammal.incompleteEnd)
    }

    func testNattÖverMidnattOchZonbyte() throws {
        // Natten mot söndag 25 oktober 2026: sommartiden slutar kl 03 (till 02).
        // Insomning 23:00 CEST (21:00Z), uppvaknande 07:00 CET (06:00Z): åtta
        // timmar på klockan men nio i verkligheten. Uppe en halvtimme före och efter.
        let m = Self.minute
        let start = 1_792_875_600 - 30 * m // 20:30Z = 22:30 CEST
        let recs: [K18Record] = DemoSleep.records(
            start: start,
            phases: [.active(seconds: 30 * m), .still(seconds: 9 * 60 * m), .active(seconds: 30 * m)],
            seed: 11)
        let series = K18Series(records: recs)
        let day = WakeDay(Date(timeIntervalSince1970: 1_792_875_600 + 9 * 3600), utcOffsetSeconds: 3600)
        XCTAssertEqual(day.daysSince1970, 20_751, "söndag 25 oktober 2026")
        let w = SleepDetection.dayWindow(wakeDay: day, startOffsetSeconds: 7200, endOffsetSeconds: 3600)
        XCTAssertEqual(w.from.timeIntervalSince1970, 1_792_836_000) // 24 okt 12:00 CEST = 10:00Z
        XCTAssertEqual(w.to.timeIntervalSince1970, 1_792_926_000) // 25 okt 12:00 CET = 11:00Z
        XCTAssertEqual(w.to.timeIntervalSince(w.from), 25 * 3600, "fönstret är 25 timmar")

        let p = try XCTUnwrap(SleepDetection.detect(series, from: w.from, to: w.to))
        XCTAssertEqual(Double(p.onset), 1_792_875_600, accuracy: 120)
        XCTAssertEqual(Double(p.wake), 1_792_875_600 + 9 * 3600, accuracy: 120)
        XCTAssertEqual(Double(p.asleepSeconds) / 3600, 9, accuracy: 0.1, "nio timmar i verkligheten, inte åtta")
        assertSumman(p)
        // Fönstret utan K18 före och efter räknas som saknat, inte som sömn eller vaket.
        XCTAssertEqual(p.gapSeconds, 0)
    }

    func testDagenFörFönstretGerInteNatten() throws {
        // Samma natt, men fönstret ligger en dag tidigare: ingen K18 alls.
        let m = Self.minute
        let recs: [K18Record] = DemoSleep.records(
            start: Self.t0, phases: [.still(seconds: 300 * m)], seed: 3)
        let series = K18Series(records: recs)
        let före = Date(timeIntervalSince1970: Double(Self.t0 - 86_400 - 3600))
        let efter = Date(timeIntervalSince1970: Double(Self.t0 - 3600))
        XCTAssertNil(SleepDetection.detect(series, from: före, to: efter))
        XCTAssertNil(SleepDetection.detect(K18Series(records: []), from: före, to: efter))
        XCTAssertNil(SleepDetection.detect(series, from: efter, to: före), "vänt fönster")
    }

    func testEnDagUtanSömnGerIngenPeriod() {
        let m = Self.minute
        // Fjorton timmar i rörelse: rullande medianen är aldrig under tröskeln.
        XCTAssertNil(natt([.active(seconds: 14 * 60 * m)]).period)
        // Tjugo stilla minuter mitt i en rörlig dag: kortare än 30 minuter.
        XCTAssertNil(natt([.active(seconds: 120 * m), .still(seconds: 20 * m), .active(seconds: 120 * m)]).period)
    }

    func testSammaFröGerSammaNatt() throws {
        let m = Self.minute
        let faser: [DemoSleep.Phase] = [.active(seconds: 20 * m), .still(seconds: 90 * m), .restless(seconds: 10 * m, every: 90),
                                        .still(seconds: 90 * m), .active(seconds: 20 * m)]
        let a = try XCTUnwrap(natt(faser, seed: 5).period)
        let b = try XCTUnwrap(natt(faser, seed: 5).period)
        XCTAssertEqual(a, b)
    }
}
