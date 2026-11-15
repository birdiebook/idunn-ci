import Foundation
import XCTest
import HeartRate
import WhoopFrames
@testable import Night

// METOD M30. Python-spegeln (tools/natt_spegel.py) räknar nätterna i
// NattSpegelFixtur.swift (skrivna av tools/tests/natt_fixtur.py --skriv) och
// skriver facit; här räknar IdunnKit exakt samma rader och måste ge samma tal.
// Räknesättet är detsamma rad för rad, så skillnaden ska vara avrundning:
// talbiblioteken (sin/cos i andningens DFT) och summeringsordningen, runt
// 1e-15 relativt. Provet kräver 1e-9 relativt (plus 1e-12 absolut). Antalen
// (slag, kastade, utelämnade, omlagda, fönster, glapp) kräver exakt lika.
//
// Raderna är påhittade. Inga värden kommer från ett riktigt band eller en
// riktig export (CLAUDE.md §Dataregeln).

final class NattSpegelTests: XCTestCase {

    // MARK: Raderna blir poster

    /// Minutraderna `flagga,hud,band` som heltal.
    func minuter(_ text: String) -> [[Int]] {
        var ut: [[Int]] = []
        for rad in text.split(separator: "\n") {
            ut.append(rad.split(separator: ",").map { (x: Substring) -> Int in Int(String(x)) ?? 0 })
        }
        return ut
    }

    /// En post ur minuttabellen: gravitationen är (x, 0, 1) med x = (t mod 2) · 0,1
    /// (flagga 1, rörlig) eller · 0,015 (flagga 2, nästan stilla); flagga 0 ger x = 0.
    func post(time t: Int, pulse: Int, rr: [Int], minut0: Int, minuter m: [[Int]]) -> K18Record {
        let rad: [Int] = m[t / 60 - minut0]
        let flagga: Int = rad[0]
        var x: Double = 0.0
        if flagga == 1 {
            x = Double(t % 2) * 0.1
        } else if flagga == 2 {
            x = Double(t % 2) * 0.015
        }
        return K18Record(time: t, pulse: pulse, rr: rr,
                         gravity: K18Record.Gravity(x: x, y: 0.0, z: 1.0),
                         skinTemperature: Double(rad[1]) / 100,
                         bandTemperature: Double(rad[2]) / 10)
    }

    /// K18-posterna: `bpm,rr1,rr2` per sekund från `start`, `-N` hoppar N sekunder.
    func k18Poster(_ n: NattSpegelFixtur.K18Natt) -> [K18Record] {
        let tabell: [[Int]] = minuter(n.minuter)
        var t: Int = n.start
        var ut: [K18Record] = []
        for rad in n.rader.split(separator: "\n") {
            if rad.hasPrefix("-") {
                t += Int(String(rad.dropFirst())) ?? 0
                continue
            }
            let delar: [Int] = rad.split(separator: ",").map { (x: Substring) -> Int in Int(String(x)) ?? 0 }
            ut.append(post(time: t, pulse: delar[0], rr: Array(delar.dropFirst()), minut0: n.minut0, minuter: tabell))
            t += 1
        }
        return ut
    }

    /// 2A37-notiserna: `tid,bpm,rr1,rr2`.
    func notiser(_ n: NattSpegelFixtur.NotisNatt) -> NightRecording {
        var samples: [HeartRateSample] = []
        for rad in n.rader.split(separator: "\n") {
            let d: [Substring] = rad.split(separator: ",", omittingEmptySubsequences: false)
            let t: Double = Double(String(d[0])) ?? 0
            let bpm: Int = Int(String(d[1])) ?? 0
            var rr: [Double] = []
            for x in d.dropFirst(2) { rr.append(Double(String(x)) ?? 0) }
            samples.append(HeartRateSample(time: Date(timeIntervalSince1970: t), bpm: bpm, rrMilliseconds: rr))
        }
        return NightRecording(samples: samples)
    }

    /// K18 tre sekunder per minut, för hudtemperaturen i 2A37-natten.
    func k18TreSekunder(_ n: NattSpegelFixtur.NotisNatt) -> [K18Record] {
        let tabell: [[Int]] = minuter(n.minuter)
        var ut: [K18Record] = []
        for i in 0..<tabell.count {
            for j in 0..<3 {
                ut.append(post(time: (n.minut0 + i) * 60 + j, pulse: 55, rr: [], minut0: n.minut0, minuter: tabell))
            }
        }
        return ut
    }

    // MARK: Jämförelsen

    func near(_ a: Double?, _ b: Double?, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        switch (a, b) {
        case (nil, nil):
            return
        case let (x?, y?):
            XCTAssertLessThanOrEqual(abs(x - y), 1e-9 * abs(y) + 1e-12, "\(what): \(x) mot \(y)", file: file, line: line)
        default:
            XCTFail("\(what): \(String(describing: a)) mot \(String(describing: b))", file: file, line: line)
        }
    }

    /// Rensning, utelämnade slag, fönster, kandidaterna, vilopuls, andning och
    /// pulsminuterna för en inspelning, mot facit.
    func kontrolleraKedjan(_ rec: NightRecording, _ f: NattSpegelFixtur.Facit, _ namn: String) {
        let beats: [Beat] = RRCleaning.clean(rec)
        let s: RRCleaning.Summary = RRCleaning.summary(beats)
        XCTAssertEqual(s.beats, f.slag, "\(namn): slag")
        XCTAssertEqual(s.outOfRangeShort, f.utanforKort, "\(namn): utanför, för kort")
        XCTAssertEqual(s.outOfRangeLong, f.utanforLang, "\(namn): utanför, för långt")
        XCTAssertEqual(s.deviatingShort, f.avvikerKort, "\(namn): avviker, för kort")
        XCTAssertEqual(s.deviatingLong, f.avvikerLang, "\(namn): avviker, för långt")
        XCTAssertEqual(s.notifications, f.notiser, "\(namn): notiser med slag")
        XCTAssertEqual(s.reanchorings, f.omlagda, "\(namn): omlagda notiser")
        XCTAssertEqual(s.segments, f.avsnitt, "\(namn): avsnitt")
        XCTAssertEqual(s.omitted, f.utelamnade, "\(namn): utelämnade slag")
        XCTAssertEqual(RRCleaning.differences(beats).count, f.skillnader, "\(namn): skillnader")
        XCTAssertEqual(beats.filter { (b: Beat) -> Bool in b.gapBefore }.count, f.glappSlag, "\(namn): glapp före slag")

        let a: NightAnalysis.Report = NightAnalysis.analyze(beats: beats)
        XCTAssertEqual(a.windows.count, f.fonster, "\(namn): fönster")
        XCTAssertEqual(a.validWindows, f.giltiga, "\(namn): giltiga fönster")
        XCTAssertEqual(a.clearBreathingWindows, f.andningsfonster, "\(namn): fönster med tydlig andning")
        near(a.rmssd.mean, f.rmssdMedel, "\(namn): RMSSD medel (a)")
        near(a.rmssd.median, f.rmssdMedian, "\(namn): RMSSD median (b)")
        near(a.rmssd.lateQuiet, f.rmssdSentLugnt, "\(namn): RMSSD sent och lugnt (c)")
        near(a.rmssd.whoopLike, f.rmssdGlidande, "\(namn): RMSSD glidande (d)")
        near(a.restingHeartRate, f.vilopuls, "\(namn): vilopuls")
        near(a.breathsPerMinute, f.andning, "\(namn): andning")
        near(a.meanHeartRate, f.medelpuls, "\(namn): medelpuls")

        let puls: [PulseMinute] = K18Beats.pulsePerMinute(rec)
        XCTAssertEqual(puls.count, f.pulsMinuter, "\(namn): pulsminuter")
        var summa: Double = 0
        for m in puls { summa += m.bpm }
        near(summa, f.pulsSumma, "\(namn): summa av pulsminuterna")
    }

    func kontrolleraHud(_ hud: SkinTemperature.Night, celsius: Double?, tackning: Double?, minuter: Int,
                        _ namn: String) {
        near(hud.celsius, celsius, "\(namn): celsius")
        near(hud.coverage, tackning, "\(namn): täckning")
        XCTAssertEqual(hud.stillMinutes, minuter, "\(namn): minuter")
    }

    // MARK: Nätterna

    func testK18NätternaGerSammaTalSomSpegeln() {
        XCTAssertEqual(NattSpegelFixtur.k18Natter.count, 4)
        for n in NattSpegelFixtur.k18Natter {
            let poster: [K18Record] = k18Poster(n)
            let serie = K18Series(records: poster)
            XCTAssertEqual(serie.records.count, poster.count, "\(n.namn): en post per sekund")
            let wake: Int = n.start + n.sekunder
            let rec: NightRecording = K18Beats.recording(serie, onset: n.start, wake: wake)
            XCTAssertGreaterThan(rec.samples.count, 1000, "\(n.namn): en riktig natt")
            kontrolleraKedjan(rec, n.facit, n.namn)

            // Hudtemperaturen: sömnminuter (flagga 0) och stilla minuter (flagga 0 och 2).
            var somn: [Int] = []
            let tabell: [[Int]] = minuter(n.minuter)
            for i in 0..<tabell.count where tabell[i][0] == 0 { somn.append(n.minut0 + i) }
            let fran = Date(timeIntervalSince1970: Double(n.start))
            let till = Date(timeIntervalSince1970: Double(wake))
            kontrolleraHud(SkinTemperature.night(serie, asleepMinutes: somn, from: fran, to: till),
                           celsius: n.facit.hudSomnCelsius, tackning: n.facit.hudSomnTackning,
                           minuter: n.facit.hudSomnMinuter, "\(n.namn): hud, sömnminuter")
            kontrolleraHud(SkinTemperature.night(serie, from: fran, to: till),
                           celsius: n.facit.hudStillaCelsius, tackning: n.facit.hudStillaTackning,
                           minuter: n.facit.hudStillaMinuter, "\(n.namn): hud, stilla minuter")

            // METOD M42. Minuter i rörelse under posttiden: lagrens minuter över perioden. Flagga 1 är rörelse
            // (|Δg| 0,1), flagga 2 ligger under gränsen (0,015) och flagga 0 är stilla.
            let lager: [NightLayers.Minute] = NightLayers.grid(serie, start: Double(n.start), end: Double(wake))
            XCTAssertEqual(NightLayers.movementMinutes(lager, period: Double(n.start)...Double(wake)),
                           n.facit.rorelseMinuter, "\(n.namn): minuter i rörelse")
            let rörliga: Int = tabell.filter { (rad: [Int]) -> Bool in rad[0] == 1 }.count
            XCTAssertEqual(n.facit.rorelseMinuter, rörliga, "\(n.namn): facit är minuterna med flagga 1")
        }
    }

    func testNotisNattenGerSammaTalSomSpegeln() {
        XCTAssertEqual(NattSpegelFixtur.notisNatter.count, 1)
        for n in NattSpegelFixtur.notisNatter {
            let rec: NightRecording = notiser(n)
            XCTAssertGreaterThan(rec.samples.count, 1000, "\(n.namn): en riktig natt")
            kontrolleraKedjan(rec, n.facit, n.namn)

            // Den gamla vägen: hudtemperaturen över inspelningens stilla minuter.
            let serie = K18Series(records: k18TreSekunder(n))
            guard let fran = rec.start, let till = rec.end else {
                XCTFail("\(n.namn): tom inspelning")
                return
            }
            kontrolleraHud(SkinTemperature.night(serie, from: fran, to: till),
                           celsius: n.facit.hudStillaCelsius, tackning: n.facit.hudStillaTackning,
                           minuter: n.facit.hudStillaMinuter, "\(n.namn): hud, stilla minuter")
            // METOD M42. Ingen sömnperiod och inga lager i den gamla vägen: inga minuter i rörelse.
            XCTAssertNil(n.facit.rorelseMinuter, "\(n.namn): minuter i rörelse")
        }
    }

    /// Natten med glapp ska ha prövat det spegeln gör: platshållare, ett eget
    /// avsnitt efter glappet på 90 s, och omläggning efter sekunderna utan RR.
    func testGlappNattenPrövarGlappsreglerna() {
        guard let n = NattSpegelFixtur.k18Natter.first(where: { (x: NattSpegelFixtur.K18Natt) -> Bool in x.namn == "glapp" }) else {
            XCTFail("natten glapp saknas")
            return
        }
        XCTAssertEqual(n.facit.avsnitt, 2)
        XCTAssertGreaterThan(n.facit.glappSlag, 0)
        XCTAssertGreaterThan(n.facit.omlagda, 0)
        XCTAssertGreaterThan(n.facit.utelamnade, 0)
    }
}
