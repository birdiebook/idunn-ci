import Foundation
import XCTest
import DemoData
import WhoopFrames
@testable import Night

// METOD M49 till M52 (D2, BESLUT B63). Påhittade tal och nätter (DemoData); inget kommer från ett riktigt band.

final class FormTests: XCTestCase {
    let idag = WakeDay(daysSince1970: 20_000)

    // MARK: Hudtemperaturens form (METOD M49)

    func minuter(_ antal: Int, hud: (Int) -> Double?) -> [NightLayers.Minute] {
        (0..<antal).map { (k: Int) -> NightLayers.Minute in
            NightLayers.Minute(start: Double(k) * 60, movement: 0.001, skinTemperature: hud(k))
        }
    }

    func testHudformenDelasIAttioFyraDelarSomPulsenOchEnTomDelBlirNil() throws {
        // 80 minuter = 4 800 s: varje del är 100 s. Minut 17 (mitt 1 050 s) är ensam i del 10.
        let m = minuter(80) { (k: Int) -> Double? in k == 17 ? nil : 33 + Double(k) * 0.01 }
        let form = NightCurve.skinProfile(m, start: 0, end: 4_800)
        XCTAssertEqual(form.count, NightCurve.profileBins)
        XCTAssertNil(form[10], "delen utan minut med värde är tom, inte noll")
        let första = try XCTUnwrap(form[0])
        let sista = try XCTUnwrap(form[47])
        XCTAssertLessThan(första, sista, "hudtemperaturen stiger genom den påhittade natten")
        XCTAssertTrue((33...34).contains(första))
    }

    func testHudformenUtanSpannHarBaraTommaDelar() {
        let m = minuter(10) { (_: Int) -> Double? in 33 }
        XCTAssertTrue(NightCurve.skinProfile(m, start: 100, end: 100).allSatisfy { $0 == nil })
        XCTAssertTrue(NightCurve.skinProfile([], start: 0, end: 600).allSatisfy { $0 == nil })
    }

    func testEnSparadFormUtanHudAvkodasAndraMedHudGörRundturen() throws {
        let gammal = Data(#"{"heartRate":[60,null],"rmssd":[40,null]}"#.utf8)
        let p = try JSONDecoder().decode(NightCurve.Profile.self, from: gammal)
        XCTAssertNil(p.skin, "en sammanfattning från före D2 saknar hudformen och avkodas ändå")
        XCTAssertEqual(p.heartRate.count, 2)
        let ny = NightCurve.Profile(heartRate: [60, nil], rmssd: [40, nil], skin: [33.1, nil])
        let tillbaka = try JSONDecoder().decode(NightCurve.Profile.self, from: JSONEncoder().encode(ny))
        XCTAssertEqual(tillbaka, ny)
    }

    func formMedHud(_ nivå: Double) -> NightCurve.Profile {
        NightCurve.Profile(heartRate: [Double?](repeating: 55, count: 48), rmssd: [Double?](repeating: 50, count: 48),
                           skin: [Double?](repeating: nivå, count: 48))
    }

    func testDenTypiskaNattenFårEttHudbandFrånTreNätterOchInteFrånFärre() throws {
        let tre = NightCurve.typical([formMedHud(33.0), formMedHud(33.2), formMedHud(33.4)])
        XCTAssertEqual(tre.skin.count, 48)
        let b = try XCTUnwrap(tre.skin.first)
        XCTAssertEqual(b.median, 33.2, accuracy: 1e-9)
        XCTAssertEqual(b.lower, 33.1, accuracy: 1e-9)
        XCTAssertEqual(b.upper, 33.3, accuracy: 1e-9)
        let två = NightCurve.typical([formMedHud(33.0), formMedHud(33.2)])
        XCTAssertTrue(två.skin.isEmpty, "färre än tre nätter ger inget band")
        // Nätter utan hudform ger inget hudband, men pulsen och HRV får sina som förut.
        let gamla = NightCurve.Profile(heartRate: [Double?](repeating: 55, count: 48),
                                       rmssd: [Double?](repeating: 50, count: 48))
        let utan = NightCurve.typical([gamla, gamla, gamla])
        XCTAssertTrue(utan.skin.isEmpty)
        XCTAssertEqual(utan.heartRate.count, 48)
    }

    // MARK: Natten ur K18: hudform, effektivitet, vakna stunder, klockslag (METOD M49, M50, M52)

    func sömn(_ n: DemoK18Nights.Night, _ series: K18Series) throws -> SleepPeriod {
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let f = SleepDetection.dayWindow(wakeDay: dag, startOffsetSeconds: n.utcOffsetSeconds,
                                         endOffsetSeconds: n.utcOffsetSeconds)
        return try XCTUnwrap(SleepDetection.detect(series, from: f.from, to: f.to))
    }

    func testEnNattUrK18BärHudformEffektivitetVakraStunderOchKlockslag() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, stages: true)
        let series = K18Series(records: n.records)
        let r = K18Night.analyze(series, sleep: try sömn(n, series), utcOffsetSeconds: n.utcOffsetSeconds)
        let form = try XCTUnwrap(r.curve?.profile?.skin, "hudformen följer med nattens form")
        XCTAssertEqual(form.count, NightCurve.profileBins)
        XCTAssertTrue(form.contains { $0 != nil }, "minuter med hudtemperatur")
        for v in form.compactMap({ $0 }) { XCTAssertTrue((30...36).contains(v), "hud \(v)") }

        let d = NightDigest(r)
        let e = try XCTUnwrap(d.efficiency, "effektiviteten")
        XCTAssertTrue((50...100).contains(e), "effektivitet \(e)")
        XCTAssertNotNil(d.wakeBouts)
        XCTAssertNotNil(d.awakeMinutes, "natten har stadier")
        let insomning = try XCTUnwrap(d.onsetMinutes)
        let uppvaknande = try XCTUnwrap(d.wakeMinutes)
        XCTAssertLessThan(insomning, uppvaknande)
        XCTAssertTrue((-360...180).contains(insomning), "insomning \(insomning)")
        XCTAssertTrue((120...900).contains(uppvaknande), "uppvaknande \(uppvaknande)")
        // Sammanfattningen bär dem till trenderna.
        let natt = d.idunNight
        XCTAssertEqual(natt.efficiency, d.efficiency)
        XCTAssertEqual(natt.deepMinutes, d.deepMinutes)
        XCTAssertEqual(natt.onsetMinutes, d.onsetMinutes)
        // En sparad sammanfattning från före D2 saknar fälten och avkodas ändå.
        let data: Data = try JSONEncoder().encode(d)
        var json: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for nyckel in ["efficiency", "wakeBouts", "awakeMinutes", "onsetMinutes", "wakeMinutes"] {
            json.removeValue(forKey: nyckel)
        }
        let utanFält: Data = try JSONSerialization.data(withJSONObject: json)
        let gammal = try JSONDecoder().decode(NightDigest.self, from: utanFält)
        XCTAssertNil(gammal.efficiency)
        XCTAssertNil(gammal.onsetMinutes)
    }

    func period(sömn: Int, vaken: Int, glapp: Int) -> SleepPeriod {
        SleepPeriod(onset: 1_000, wake: 1_000 + sömn + vaken + glapp, windowStart: 0, windowEnd: 100_000,
                    wakeBouts: [], gaps: [], asleepSeconds: sömn, awakeSeconds: vaken, gapSeconds: glapp,
                    threshold: 0.2, asleepMinutes: [])
    }

    func testEffektivitetenÄrSömnenDeladMedHelaPeriodenOchGlappRäknasInteSomSömn() throws {
        let p = period(sömn: 27_000, vaken: 1_000, glapp: 800)
        XCTAssertEqual(try XCTUnwrap(p.periodEfficiency), 100 * 27_000.0 / 28_800.0, accuracy: 1e-9)
        // Den äldre kvoten (sömn delad med tiden med K18) är en annan och står kvar.
        XCTAssertGreaterThan(try XCTUnwrap(p.efficiency), try XCTUnwrap(p.periodEfficiency) / 100)
        XCTAssertNil(period(sömn: 0, vaken: 0, glapp: 0).periodEfficiency, "perioden saknar längd")
    }

    func testKlockslagetÄrMinuterEfterMidnattPåUppvakningsdagenÖverMidnatt() {
        let midnatt = Double(idag.daysSince1970) * 86_400 - 7_200       // lokal midnatt i UTC+2
        let kväll = Date(timeIntervalSince1970: midnatt - 63 * 60)      // 22:57 kvällen före
        let morgon = Date(timeIntervalSince1970: midnatt + (6 * 60 + 58) * 60)
        XCTAssertEqual(Trends.clockMinutes(kväll, day: idag, utcOffsetSeconds: 7_200), -63, accuracy: 1e-9)
        XCTAssertEqual(Trends.clockMinutes(morgon, day: idag, utcOffsetSeconds: 7_200), 418, accuracy: 1e-9)
        // Efter midnatt är insomning positiv, samma axel.
        let sent = Date(timeIntervalSince1970: midnatt + 25 * 60)
        XCTAssertEqual(Trends.clockMinutes(sent, day: idag, utcOffsetSeconds: 7_200), 25, accuracy: 1e-9)
    }

    // MARK: De nya måtten (METOD M50, M52)

    func testDeNyaMåttenLiggerEfterDeGamlaOchHarNormalområde() {
        XCTAssertEqual(Trends.Measure.allCases,
                       [.hrv, .restingHeartRate, .meanHeartRate, .sleep, .movement, .snoring, .regularity, .breathing,
                        .skinTemperature, .efficiency, .awakeTime, .lightSleep, .deepSleep, .remSleep, .sleepOnset,
                        .sleepWake])
        for m in [Trends.Measure.efficiency, .awakeTime, .lightSleep, .deepSleep, .remSleep, .sleepOnset, .sleepWake] {
            XCTAssertTrue(m.hasRange, "\(m)")
            XCTAssertFalse(m.rangeFollowsResearch, "formen är ett antagande (METOD M52)")
            XCTAssertFalse(m.hasStatus)
            XCTAssertFalse(m.isLogarithmic)
        }
        XCTAssertFalse(Trends.Measure.sleep.hasRange, "sömntiden har fortfarande inget område")
        XCTAssertTrue(Trends.Measure.sleepOnset.accepts(-63), "insomning före midnatt är ett tal")
    }

    func nätter(antal: Int = 40, _ gör: (Int) -> Trends.IdunNight) -> [Trends.IdunNight] {
        (0..<antal).map(gör)
    }

    func testDeNyaMåttenFårEnPunktPerNattMedTalOchNattenSaknasUtanTal() {
        let n = nätter { (k: Int) -> Trends.IdunNight in
            Trends.IdunNight(day: idag - k, validWindows: 60, rmssd: 50, restingHeartRate: 50, breathsPerMinute: 14,
                             source: .k18, id: "n\(k)",
                             efficiency: k == 3 ? nil : 92, wakeBouts: 9, awakeMinutes: 20, lightMinutes: 250,
                             deepMinutes: 70 + Double(k % 3), remMinutes: 80, onsetMinutes: -60, wakeMinutes: 420)
        }
        let v = Trends.idunValues(n)
        XCTAssertEqual(v[.efficiency]?.count, 39, "natt 3 saknar effektivitet: ingen punkt")
        XCTAssertEqual(v[.deepSleep]?[idag], 70)
        XCTAssertEqual(v[.sleepOnset]?[idag], -60)
        XCTAssertEqual(v[.sleepWake]?.count, 40)
        // Gamla inspelningar har inga av dem.
        let gammal = Trends.IdunNight(day: idag, validWindows: 60, rmssd: 50, restingHeartRate: 50, breathsPerMinute: 14)
        let g = Trends.idunValues([gammal])
        XCTAssertEqual(g[.efficiency], [:])
        XCTAssertEqual(g[.deepSleep], [:])
        XCTAssertEqual(g[.sleepOnset], [:])
    }

    func testNattensRadFinnsBaraFörNattenSjälvOchHarSittNormalområde() throws {
        let n = nätter { (k: Int) -> Trends.IdunNight in
            Trends.IdunNight(day: idag - k, validWindows: 60, rmssd: 50, restingHeartRate: 50, breathsPerMinute: 14,
                             source: .k18, id: "n\(k)", deepMinutes: k == 0 ? nil : 60 + Double(k % 5),
                             onsetMinutes: -50 + Double(k % 4))
        }
        let v = Trends.idunValues(n)
        let rad = try XCTUnwrap(MorningCard.nightRow(.sleepOnset, day: idag, idun: v))
        XCTAssertEqual(rad.day, idag)
        XCTAssertEqual(rad.value, -50)
        XCTAssertNotNil(rad.range, "fem veckors nätter före veckan")
        XCTAssertTrue(rad.rangeIsAssumption)
        // Djupsömnen saknas just i natten: en äldre natts rad räknas inte som nattens.
        XCTAssertNil(MorningCard.nightRow(.deepSleep, day: idag, idun: v))
        XCTAssertNotNil(MorningCard.nightRow(.deepSleep, day: idag - 1, idun: v))
        // Baslinjen byggs: bara sex nätter före natten ger ingen rad med område (METOD M7, BESLUT B69).
        let kort = Trends.idunValues(Array(n.prefix(7)))
        XCTAssertNil(try XCTUnwrap(MorningCard.nightRow(.sleepOnset, day: idag, idun: kort)).range)
    }

    // MARK: Perioderna V, M och 6M (METOD M51)

    func värden(dagar: Int, _ f: (Int) -> Double?) -> [WakeDay: Double] {
        var ut: [WakeDay: Double] = [:]
        for k in 0..<dagar {
            if let v = f(k) { ut[idag - k] = v }
        }
        return ut
    }

    func testPerioderna7_30Och182DagarMedEnPunktPerDag() {
        XCTAssertEqual(Trends.Span.allCases.map(\.days), [7, 30, 182])
        XCTAssertEqual(Trends.Span.allCases.map(\.buckets), [7, 30, 182], "BESLUT B82: också 6M har en punkt per dag")
    }

    func testVeckansMedelÄndringenMotVeckanFöreOchEnTomDag() throws {
        // Sju nätter på 8 h, sju före på 6 h; natt 2 saknas i veckan.
        let s = Trends.series(.sleep, idun: värden(dagar: 14) { (k: Int) -> Double? in
            k == 2 ? nil : (k < 7 ? 8 : 6)
        }, whoop: [:])
        let o = Trends.overview(s, span: .week, end: idag)
        XCTAssertEqual(o.buckets.count, 7)
        XCTAssertEqual(o.first, idag - 6)
        XCTAssertEqual(o.end, idag)
        XCTAssertEqual(o.buckets.last?.day, idag)
        XCTAssertEqual(o.buckets.last?.value, 8)
        XCTAssertNil(o.buckets[4].value, "natt 2 saknas: punkten är tom, inte noll")
        XCTAssertEqual(o.nights, 6)
        XCTAssertEqual(try XCTUnwrap(o.mean), 8, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(o.previousMean), 6, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(o.change), 2.0 / 6.0, accuracy: 1e-12)
    }

    func testMedelSaknasMedFärreÄnTreNätterOchÄndringenMedDen() {
        let s = Trends.series(.sleep, idun: värden(dagar: 14) { (k: Int) -> Double? in k < 2 ? 7 : (k >= 7 ? 6 : nil) },
                              whoop: [:])
        let o = Trends.overview(s, span: .week, end: idag)
        XCTAssertNil(o.mean, "två nätter räcker inte till ett medel")
        XCTAssertNil(o.change)
        XCTAssertEqual(o.previousMean, 6)
        XCTAssertEqual(o.nights, 2)
    }

    func testMånadenHar30PunkterOchHalvåret182DagarMedEnNattPerPunkt() throws {
        // 100 nätter bakåt; bortom dag 100 finns inga nätter.
        let s = Trends.series(.efficiency, idun: värden(dagar: 100) { (k: Int) -> Double? in 90 + Double(k % 5) },
                              whoop: [:])
        let m = Trends.overview(s, span: .month, end: idag)
        XCTAssertEqual(m.buckets.count, 30)
        XCTAssertTrue(m.buckets.allSatisfy { $0.value != nil })
        XCTAssertTrue(m.months.isEmpty, "månaderna bara i 6M")
        let h = Trends.overview(s, span: .halfYear, end: idag)
        XCTAssertEqual(h.buckets.count, 182)
        XCTAssertEqual(h.buckets.last?.day, idag)
        XCTAssertEqual(h.buckets.last?.nights, 1)
        XCTAssertEqual(h.buckets.last?.value, 90)
        XCTAssertEqual(h.buckets[h.buckets.count - 2].value, 91, "gårdagen")
        // Före dag 100 finns inga nätter: de äldsta dagarna är tomma.
        XCTAssertNil(h.buckets.first?.value)
        XCTAssertEqual(h.buckets.first?.nights, 0)
        XCTAssertEqual(h.first, idag - 181)
        XCTAssertEqual(h.buckets.first?.day, idag - 181)
        XCTAssertEqual(h.nights, 100)
    }

    func testEnDagUtanNattÄrTomIMånadenOchIHalvåret() {
        // Dag 0–6 har två nätter (dag 2 och 3); resten av månaden har alla.
        let s = Trends.series(.efficiency, idun: värden(dagar: 40) { (k: Int) -> Double? in
            k < 7 ? ((k == 2 || k == 3) ? 90 : nil) : 91
        }, whoop: [:])
        let m = Trends.overview(s, span: .month, end: idag)
        XCTAssertEqual(m.buckets.last?.value, nil, "idag saknas")
        XCTAssertEqual(m.buckets[m.buckets.count - 3].value, 90)
        let h = Trends.overview(s, span: .halfYear, end: idag)
        XCTAssertNil(h.buckets.last?.value, "idag saknas också i halvåret")
        XCTAssertEqual(h.buckets.last?.nights, 0)
        XCTAssertEqual(h.buckets[h.buckets.count - 3].value, 90)
    }

    func testBandetFöljerMedPunkternaNärNormalområdetFinns() throws {
        let s = Trends.series(.efficiency, idun: värden(dagar: 80) { (k: Int) -> Double? in 90 + Double(k % 3) },
                              whoop: [:])
        let o = Trends.overview(s, span: .week, end: idag)
        let sista = try XCTUnwrap(o.buckets.last)
        let lägre = try XCTUnwrap(sista.lower)
        let högre = try XCTUnwrap(sista.upper)
        XCTAssertLessThan(lägre, högre)
        // Halvåret: dagens band.
        let h = Trends.overview(s, span: .halfYear, end: idag)
        XCTAssertNotNil(h.buckets.last?.lower)
        XCTAssertNil(h.buckets.first?.lower, "före de fyra veckorna finns inget område")
        XCTAssertEqual(Trends.lastDay([s]), idag)
        XCTAssertNil(Trends.lastDay([]))
    }

    // MARK: Påhittade nätter för halvåret (METOD M51)

    func testDeSammanfattadeDemonätternaHarAllaTalOchÄrLikaVarjeGång() throws {
        let a = DemoHistory.summaryNights(daysBeforeLast: 40..<182)
        XCTAssertEqual(a.count, 142)
        XCTAssertEqual(a, DemoHistory.summaryNights(daysBeforeLast: 40..<182), "samma seed ger samma nätter")
        XCTAssertEqual(a.map(\.day), a.map(\.day).sorted(), "äldst först")
        for n in a {
            XCTAssertEqual(n.source, .k18)
            XCTAssertNotNil(n.sleepEpisode)
            let e = try XCTUnwrap(n.efficiency)
            XCTAssertTrue((85...99.9).contains(e), "effektivitet \(e)")
            let l = try XCTUnwrap(n.lightMinutes)
            let d = try XCTUnwrap(n.deepMinutes)
            let r = try XCTUnwrap(n.remMinutes)
            let sömn = try XCTUnwrap(n.sleepHours) * 60
            XCTAssertEqual(l + d + r, sömn, accuracy: 1e-6, "lätt + djup + REM är sömntiden")
            XCTAssertTrue((-240...0).contains(try XCTUnwrap(n.onsetMinutes)))
            XCTAssertTrue((200...500).contains(try XCTUnwrap(n.wakeMinutes)))
        }
        XCTAssertTrue(a.contains { $0.snoringPerHour == nil }, "en natt av tio saknar ljud")
        // Det räcker till ett normalområde för alla de nya måtten och till ett halvår.
        let v = Trends.idunValues(a)
        for m in [Trends.Measure.efficiency, .deepSleep, .sleepOnset, .sleepWake, .meanHeartRate, .regularity] {
            XCTAssertFalse((v[m] ?? [:]).isEmpty, "\(m)")
        }
        let serie = Trends.series(.deepSleep, idun: v[.deepSleep] ?? [:], whoop: [:])
        let o = Trends.overview(serie, span: .halfYear, end: try XCTUnwrap(a.last).day)
        XCTAssertGreaterThanOrEqual(o.buckets.filter { $0.value != nil }.count, 120)
        XCTAssertGreaterThanOrEqual(o.months.filter { $0.mean != nil }.count, 5, "ett medel per hel månad")
    }

    // MARK: Kalendermånaderna i 6M och bläddringen (METOD M51, BESLUT B82)

    func testKalenderdagenRäknasFörHandUrDagnumret() {
        func c(_ n: Int) -> [Int] {
            let x = WakeDay(daysSince1970: n).civil
            return [x.year, x.month, x.day]
        }
        XCTAssertEqual(c(0), [1970, 1, 1])
        XCTAssertEqual(c(19_723), [2024, 1, 1])
        XCTAssertEqual(c(19_782), [2024, 2, 29], "skottdagen")
        XCTAssertEqual(c(19_783), [2024, 3, 1])
        XCTAssertEqual(c(20_000), [2024, 10, 4])
        XCTAssertEqual(c(20_089), [2025, 1, 1])
        XCTAssertEqual(idag.monthStart, WakeDay(daysSince1970: 19_997), "1 okt")
        XCTAssertEqual(idag.nextMonthStart, WakeDay(daysSince1970: 20_028), "1 nov")
        XCTAssertEqual(WakeDay(daysSince1970: 20_070).nextMonthStart, WakeDay(daysSince1970: 20_089), "december till januari")
        XCTAssertEqual(WakeDay(daysSince1970: 19_782).nextMonthStart, WakeDay(daysSince1970: 19_783), "februari med skottdag")
    }

    func testHalvåretHarEnRadPerKalendermånadMedMedelOchÄndringMotMånadenFöre() throws {
        // idag är 4 okt 2024, så 6M börjar 6 apr. Påhittade timmar sömn:
        // 25–31 mar 6 h · 1–10 apr 7,5 h · inget i maj · 2 nätter i juni · hela september 8 h · 1–4 okt 9 h,
        // och 5 okt (efter periodens slut) 100 h, som inte får räknas.
        var x: [WakeDay: Double] = [:]
        for n in 19_807...19_813 { x[WakeDay(daysSince1970: n)] = 6 }
        for n in 19_814...19_823 { x[WakeDay(daysSince1970: n)] = 7.5 }
        for n in [19_875, 19_876] { x[WakeDay(daysSince1970: n)] = 7 }
        for n in 19_967...19_996 { x[WakeDay(daysSince1970: n)] = 8 }
        for n in 19_997...20_000 { x[WakeDay(daysSince1970: n)] = 9 }
        x[idag + 1] = 100
        let s = Trends.series(.sleep, idun: x, whoop: [:])
        let o = Trends.overview(s, span: .halfYear, end: idag)
        let m = o.months
        XCTAssertEqual(m, Trends.months(s, first: idag - 181, end: idag))
        XCTAssertEqual(m.map(\.monthStart.daysSince1970), [19_814, 19_844, 19_875, 19_905, 19_936, 19_967, 19_997],
                       "april till oktober")
        XCTAssertEqual(m.first?.first, idag - 181, "april syns från 6 apr")
        XCTAssertEqual(m.first?.last, WakeDay(daysSince1970: 19_843), "30 apr")
        XCTAssertEqual(m.last?.last, idag, "oktober fram till periodens slut")
        // April: medlet av hela månadens nätter (också 1–5 apr före perioden), mot mars.
        XCTAssertEqual(try XCTUnwrap(m[0].mean), 7.5, accuracy: 1e-12)
        XCTAssertEqual(m[0].nights, 10)
        XCTAssertEqual(try XCTUnwrap(m[0].change), 0.25, accuracy: 1e-12)
        XCTAssertNil(m[1].mean, "maj utan nätter")
        XCTAssertNil(m[1].change)
        XCTAssertNil(m[2].mean, "två nätter räcker inte till ett medel")
        XCTAssertEqual(m[2].nights, 2)
        XCTAssertNil(m[5].change, "augusti saknar medel, så september har ingen ändring")
        XCTAssertEqual(try XCTUnwrap(m[5].mean), 8, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(m[6].mean), 9, accuracy: 1e-12, "5 okt ligger efter slutet")
        XCTAssertEqual(m[6].nights, 4)
        XCTAssertEqual(try XCTUnwrap(m[6].change), 0.125, accuracy: 1e-12)
        XCTAssertTrue(Trends.overview(s, span: .week, end: idag).months.isEmpty)
    }

    func testBläddringenFlyttarEnHelPeriodOchStannarVidFörstaOchSistaNatten() {
        let första: WakeDay = idag - 100
        func steg(_ slut: WakeDay, _ span: Trends.Span, _ k: Int) -> WakeDay? {
            Trends.stepped(end: slut, span: span, by: k, first: första, last: idag)
        }
        XCTAssertEqual(steg(idag, .week, -1), idag - 7)
        XCTAssertEqual(steg(idag, .month, -1), idag - 30)
        XCTAssertEqual(steg(idag, .halfYear, -1), nil, "halvåret före slutar före första natten")
        XCTAssertNil(steg(idag, .week, 1), "redan vid senaste natten")
        XCTAssertEqual(steg(idag - 10, .week, 1), idag - 3)
        XCTAssertEqual(steg(idag - 3, .week, 1), idag, "framåt stannar vid senaste natten")
        XCTAssertEqual(steg(idag - 93, .week, -1), första, "en period som slutar på första natten")
        XCTAssertNil(steg(idag - 94, .week, -1))
        let s = Trends.series(.sleep, idun: värden(dagar: 101) { (_: Int) -> Double? in 7 }, whoop: [:])
        XCTAssertEqual(Trends.firstDay([s]), första)
        XCTAssertNil(Trends.firstDay([]))
    }

    func testPilarnaPåMorgonGårEnMorgonMedNattÅtGången() {
        let d: [WakeDay] = [idag - 5, idag - 2, idag]
        XCTAssertEqual(MorningCard.step(d, from: idag - 2, by: -1), idag - 5)
        XCTAssertEqual(MorningCard.step(d, from: idag - 2, by: 1), idag)
        XCTAssertNil(MorningCard.step(d, from: idag, by: 1), "senaste morgonen")
        XCTAssertNil(MorningCard.step(d, from: idag - 5, by: -1), "första morgonen")
        XCTAssertNil(MorningCard.step(d, from: idag - 3, by: -1), "en dag utan morgon")
    }
}
