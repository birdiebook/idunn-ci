import XCTest
@testable import Markers

/// BESLUT B104 · METOD M59. Markörerna mot jämnåriga. **Allt här är påhittat**: normtabellen nedan kommer inte ur
/// någon källa (jämna tal, valda så att räkningen går att följa i huvudet), och mätningarna är inte någons.
final class MarkersTests: XCTestCase {

    /// PÅHITTAD normtabell. Medianen sjunker 40 → 38 → 34 → 30 över bandens mitt 25, 35, 45, 55.
    private func tabell(_ marker: MarkerID = .vo2max, trend: NormTable.AgeTrend = .declines,
                        medianer: [Double] = [40, 38, 34, 30]) -> NormTable {
        let band: [NormTable.Band] = medianer.enumerated().map { (p: (offset: Int, element: Double)) -> NormTable.Band in
            let m: Double = p.element
            return NormTable.Band(20 + 10 * p.offset, 29 + 10 * p.offset, [m - 10, m - 5, m, m + 5, m + 10])
        }
        return NormTable(marker: marker, source: "PÅHITTAD", percentiles: [10, 25, 50, 75, 90], trend: trend,
                         bands: [.male: band])!
    }

    // MARK: Personen

    func testÅldernRäknasFrånMittenAvFödelseåret() {
        let p = Person(birthYear: 1980, sex: .male)
        // 2020-07-02 är dag 18 445: fyrtio år efter mitten av 1980.
        XCTAssertEqual(p.age(onDay: 18_445), 40, accuracy: 0.01)
        // Ett halvår senare (2021-01-01, dag 18 628).
        XCTAssertEqual(p.age(onDay: 18_628), 40.5, accuracy: 0.01)
    }

    // MARK: Normtabellen

    func testEnTabellSomInteHållerIhopBlirIngenTabell() {
        let band = [NormTable.Band(20, 29, [1, 2, 3])]
        XCTAssertNotNil(NormTable(marker: .vo2max, source: "x", percentiles: [25, 50, 75], trend: .declines,
                                  bands: [.male: band]))
        XCTAssertNil(NormTable(marker: .vo2max, source: "x", percentiles: [50, 25, 75], trend: .declines,
                               bands: [.male: band]), "percentilerna stiger inte")
        XCTAssertNil(NormTable(marker: .vo2max, source: "x", percentiles: [25, 50], trend: .declines,
                               bands: [.male: band]), "fel antal värden")
        XCTAssertNil(NormTable(marker: .vo2max, source: "x", percentiles: [25, 50, 75], trend: .declines,
                               bands: [.male: [NormTable.Band(20, 29, [1, 3, 2])]]), "värdena sjunker")
        XCTAssertNil(NormTable(marker: .vo2max, source: "x", percentiles: [25, 50, 75], trend: .declines,
                               bands: [.male: band + [NormTable.Band(31, 39, [1, 2, 3])]]), "en lucka mellan banden")
        XCTAssertNil(NormTable(marker: .vo2max, source: "x", percentiles: [0, 50, 75], trend: .declines,
                               bands: [.male: band]), "percentilen 0 finns inte")
        XCTAssertNil(NormTable(marker: .vo2max, source: "x", percentiles: [25, 50, 75], trend: .declines,
                               bands: [.male: []]), "ett kön utan band")
    }

    func testVärdenaFörEnÅlderLiggerPåLinjenMellanBandensMitt() {
        let t = tabell()
        XCTAssertEqual(t.values(age: 40, sex: .male), [26, 31, 36, 41, 46], "mitt mellan 35 och 45")
        XCTAssertEqual(t.values(age: 35, sex: .male), [28, 33, 38, 43, 48], "bandets mitt")
        XCTAssertEqual(t.values(age: 22, sex: .male), [30, 35, 40, 45, 50], "före första mitten: första bandet")
        XCTAssertEqual(t.values(age: 59.9, sex: .male), [20, 25, 30, 35, 40], "efter sista mitten: sista bandet")
        XCTAssertNil(t.values(age: 19.9, sex: .male), "yngre än tabellen")
        XCTAssertNil(t.values(age: 60.5, sex: .male), "äldre än tabellen")
        XCTAssertEqual(t.ages, 20...60, "banden 20–29 till 50–59 gäller åldrarna 20 till 60")
        XCTAssertNil(t.values(age: 40, sex: .female), "könet saknas i tabellen")
    }

    func testPercentilenBlandJämnåriga() {
        let t = tabell()
        XCTAssertEqual(t.position(value: 36, age: 40, sex: .male), NormPosition(percentile: 50, bound: .inside))
        XCTAssertEqual(t.position(value: 38.5, age: 40, sex: .male), NormPosition(percentile: 62.5, bound: .inside))
        XCTAssertEqual(t.position(value: 26, age: 40, sex: .male), NormPosition(percentile: 10, bound: .inside))
        XCTAssertEqual(t.position(value: 46, age: 40, sex: .male), NormPosition(percentile: 90, bound: .inside))
        XCTAssertEqual(t.position(value: 20, age: 40, sex: .male), NormPosition(percentile: 10, bound: .below))
        XCTAssertEqual(t.position(value: 50, age: 40, sex: .male), NormPosition(percentile: 90, bound: .above))
        XCTAssertNil(t.position(value: 36, age: 70, sex: .male))
        XCTAssertNil(t.position(value: .nan, age: 40, sex: .male))
    }

    func testTvåPercentilerMedSammaVärdeGerMittenAvDem() {
        let t = NormTable(marker: .vo2max, source: "PÅHITTAD", percentiles: [25, 50, 75], trend: .flat,
                          bands: [.male: [NormTable.Band(20, 29, [30, 30, 40])]])!
        XCTAssertEqual(t.position(value: 30, age: 25, sex: .male), NormPosition(percentile: 37.5, bound: .inside))
    }

    func testMotsvarandeÅlderDärMedianenSjunker() {
        let t = tabell()
        XCTAssertEqual(t.equivalentAge(value: 36, sex: .male), .years(40))
        XCTAssertEqual(t.equivalentAge(value: 38, sex: .male), .years(35))
        XCTAssertEqual(t.equivalentAge(value: 30, sex: .male), .years(55), "lika med den äldsta medianen")
        XCTAssertEqual(t.equivalentAge(value: 40, sex: .male), .best(25), "lika med den bästa medianen")
        XCTAssertEqual(t.equivalentAge(value: 47, sex: .male), .best(25))
        XCTAssertEqual(t.equivalentAge(value: 29, sex: .male), .beyond(55))
        XCTAssertNil(t.equivalentAge(value: 36, sex: .female))
    }

    func testMotsvarandeÅlderRäknasBaraEfterMedianensTopp() {
        // Som greppstyrkan: upp till en topp och sedan ned. 37 finns på båda sidor om toppen, och den äldre gäller.
        let t = tabell(medianer: [36, 40, 38, 30])
        guard case .years(let år)? = t.equivalentAge(value: 37, sex: .male) else { return XCTFail("ingen ålder") }
        XCTAssertEqual(år, 46.25, accuracy: 1e-9)
        XCTAssertEqual(t.equivalentAge(value: 40, sex: .male), .best(35))
        // En platå i toppen: bästa åldern är platåns början, och nedgången räknas från dess slut.
        let platå = tabell(medianer: [40, 40, 34, 30])
        XCTAssertEqual(platå.equivalentAge(value: 40, sex: .male), .best(25))
        XCTAssertEqual(platå.equivalentAge(value: 37, sex: .male), .years(40))
    }

    func testMotsvarandeÅlderDärMedianenStiger() {
        // En markör där lägre är bättre och medianen stiger med åldern.
        let t = tabell(trend: .rises, medianer: [60, 62, 66, 70])
        XCTAssertEqual(t.equivalentAge(value: 64, sex: .male), .years(40))
        XCTAssertEqual(t.equivalentAge(value: 59, sex: .male), .best(25))
        XCTAssertEqual(t.equivalentAge(value: 71, sex: .male), .beyond(55))
    }

    func testIngenMotsvarandeÅlderUtanEnMedianSomRörSigÅtEttHåll() {
        XCTAssertNil(tabell(trend: .flat).equivalentAge(value: 36, sex: .male), "trenden är flat")
        XCTAssertNil(tabell(medianer: [40, 34, 36, 30]).equivalentAge(value: 35, sex: .male),
                     "medianen vänder upp efter toppen")
        let utanMedian = NormTable(marker: .vo2max, source: "PÅHITTAD", percentiles: [25, 75], trend: .declines,
                                   bands: [.male: [NormTable.Band(20, 29, [30, 40]), NormTable.Band(30, 39, [28, 38])]])!
        XCTAssertNil(utanMedian.equivalentAge(value: 33, sex: .male), "tabellen saknar medianen")
        XCTAssertNil(tabell(medianer: [40]).equivalentAge(value: 40, sex: .male), "ett enda band")
    }

    func testEnTabellMedExaktaÅldrar() {
        // Värden vid exakta åldrar (som Dodds): linjen går mellan åldrarna, inte mellan bandens mitt.
        let t = NormTable(marker: .gripStrength, source: "PÅHITTAD", percentiles: [25, 50, 75], trend: .declines,
                          ages: 30...50,
                          rows: [.male: [NormTable.Row(age: 30, [40, 50, 60]), NormTable.Row(age: 40, [38, 48, 58]),
                                         NormTable.Row(age: 50, [30, 40, 50])]])!
        XCTAssertEqual(t.values(age: 35, sex: .male), [39, 49, 59])
        XCTAssertEqual(t.values(age: 50, sex: .male), [30, 40, 50], "tabellens sista ålder gäller")
        XCTAssertNil(t.values(age: 50.1, sex: .male))
        XCTAssertEqual(t.equivalentAge(value: 44, sex: .male), .years(45))
        XCTAssertNil(NormTable(marker: .gripStrength, source: "x", percentiles: [50], trend: .declines, ages: 30...50,
                               rows: [.male: [NormTable.Row(age: 40, [48]), NormTable.Row(age: 30, [50])]]),
                     "raderna står inte i åldersordning")
    }

    func testEnRadUrMedelOchStandardavvikelse() {
        let rad = NormTable.normalRow(age: 45, mean: 50, sd: 10)
        XCTAssertEqual(rad.values.count, NormTable.normalPercentiles.count)
        XCTAssertEqual(rad.values[3], 50, "medianen är medlet")
        XCTAssertEqual(rad.values[0], 33.55, accuracy: 0.01, "5 %: medlet − 1,645 standardavvikelser")
        XCTAssertEqual(rad.values[2], 43.26, accuracy: 0.01, "25 %: − 0,674")
        XCTAssertEqual(rad.values[5], 62.82, accuracy: 0.01, "90 %: + 1,282")
        XCTAssertEqual(rad.values[6] - 50, 50 - rad.values[0], accuracy: 1e-9, "symmetrisk")
    }

    // MARK: Tabellerna ur källorna (METOD M59)

    func testTabellernaHållerIhopOchÄrTvå() {
        XCTAssertNotNil(Norms.gripStrength)
        XCTAssertNotNil(Norms.vo2max)
        XCTAssertEqual(Norms.published.map(\.marker), [.gripStrength, .vo2max])
        // HRV och vilopuls har ingen tabell (M59): ingen plats bland jämnåriga räknas för dem.
        XCTAssertFalse(Norms.published.contains { (t: NormTable) -> Bool in
            t.marker == .hrv || t.marker == .restingHeartRate
        })
    }

    func testGreppstyrkanÄrDoddsTabell2() throws {
        // Stickprov mot artikeln (docs/KALLOR.md K57): centilerna 10, 25, 50, 75, 90 i kg.
        let t = try XCTUnwrap(Norms.gripStrength)
        XCTAssertEqual(t.percentiles, [10, 25, 50, 75, 90])
        XCTAssertEqual(t.values(age: 40, sex: .male), [38, 44, 50, 57, 63])
        XCTAssertEqual(t.values(age: 65, sex: .male), [31, 37, 43, 48, 53])
        XCTAssertEqual(t.values(age: 40, sex: .female), [23, 27, 31, 35, 39])
        XCTAssertEqual(t.values(age: 90, sex: .female), [9, 11, 14, 17, 20])
        XCTAssertEqual(t.rows[.male]?.count, 18)
        XCTAssertEqual(t.rows[.female]?.count, 18)
        // Artikelns text: medianen når 51 kg hos män mellan 29 och 39 år och 31 kg hos kvinnor mellan 26 och 42.
        XCTAssertEqual(t.equivalentAge(value: 51, sex: .male), .best(30))
        XCTAssertEqual(t.equivalentAge(value: 31, sex: .female), .best(30))
        // Efter toppen: 50 kg är mannens median vid 40, och 49,5 ligger mitt mellan 40 och 45.
        XCTAssertEqual(t.equivalentAge(value: 50, sex: .male), .years(40))
        XCTAssertEqual(t.equivalentAge(value: 49.5, sex: .male), .years(42.5))
        XCTAssertEqual(t.equivalentAge(value: 24, sex: .male), .beyond(90))
        // En 42-åring med 50 kg: värdena vid 42 är 37,2, 43,2, 49,6, 56,6, 62,2, så percentilen är strax över 50.
        let plats = try XCTUnwrap(t.position(value: 50, age: 42, sex: .male))
        XCTAssertEqual(plats.percentile, 50 + 0.4 / 7.0 * 25, accuracy: 1e-9)
        XCTAssertNil(t.position(value: 50, age: 91, sex: .male), "tabellen slutar vid 90 år")
    }

    func testSyreupptagningenÄrLoesTabell2() throws {
        // Stickprov mot artikeln (docs/KALLOR.md K58): medel ± standardavvikelse per tioårsband, ml/kg/min.
        let t = try XCTUnwrap(Norms.vo2max)
        let medianer: [Sex: [Double]] = [.male: [54.4, 49.1, 47.2, 42.6, 39.2, 35.3],
                                         .female: [43.0, 40.0, 38.4, 34.4, 31.1, 28.3]]
        for (kön, facit) in medianer {
            let rader = try XCTUnwrap(t.rows[kön])
            XCTAssertEqual(rader.map(\.age), [25, 35, 45, 55, 65, 75])
            XCTAssertEqual(rader.map { (r: NormTable.Row) -> Double in r.values[3] }, facit)
        }
        // Män 40–49: 47,2 ± 7,7. Den 5:e percentilen är 47,2 − 1,645 × 7,7 = 34,5 och den 95:e 59,9.
        let fyrtiofem = try XCTUnwrap(t.values(age: 45, sex: .male))
        XCTAssertEqual(fyrtiofem[0], 34.53, accuracy: 0.01)
        XCTAssertEqual(fyrtiofem[6], 59.87, accuracy: 0.01)
        XCTAssertEqual(t.position(value: 47.2, age: 45, sex: .male), NormPosition(percentile: 50, bound: .inside))
        XCTAssertEqual(t.position(value: 70, age: 45, sex: .male), NormPosition(percentile: 95, bound: .above))
        // Motsvarande ålder: 48,15 ligger mitt mellan medlen vid 35 och 45.
        guard case .years(let år)? = t.equivalentAge(value: 48.15, sex: .male) else { return XCTFail("ingen ålder") }
        XCTAssertEqual(år, 40, accuracy: 1e-6)
        XCTAssertEqual(t.equivalentAge(value: 56, sex: .male), .best(25))
        XCTAssertEqual(t.equivalentAge(value: 28, sex: .female), .beyond(75))
        XCTAssertNil(t.values(age: 19, sex: .male), "studien börjar vid 20 år")
    }

    // MARK: Kvartalets nivå

    func testNivånÄrMedletÖverNittioDagar() {
        // 30 nätter i fönstret (värdet 50), och äldre nätter utanför det (värdet 90) som inte ska räknas.
        var serie: [DayValue] = (0..<30).map { (i: Int) -> DayValue in DayValue(day: 1_000 - 3 * i, value: 50) }
        serie += (0..<30).map { (i: Int) -> DayValue in DayValue(day: 910 - i, value: 90) }
        let nivå = MarkerLevel.level(serie, endDay: 1_000)
        XCTAssertEqual(nivå?.mean, 50)
        XCTAssertEqual(nivå?.count, 30)
        // Dag 911 är fönstrets första dag: en natt där räknas, en natt dag 910 gör det inte.
        let kant = MarkerLevel.level(serie + [DayValue(day: 911, value: 81)], endDay: 1_000)
        XCTAssertEqual(kant?.count, 31)
        XCTAssertEqual(kant?.mean ?? 0, 51, accuracy: 1e-9)
    }

    func testNivånKräverTjugoNätter() {
        let nitton: [DayValue] = (0..<19).map { (i: Int) -> DayValue in DayValue(day: 1_000 - i, value: 50) }
        XCTAssertNil(MarkerLevel.level(nitton, endDay: 1_000))
        XCTAssertNotNil(MarkerLevel.level(nitton + [DayValue(day: 950, value: 50)], endDay: 1_000))
    }

    func testEttLogaritmisktMåttFårMedletAvLogaritmerna() {
        // Tio nätter med 25 och tio med 100: det geometriska medlet är 50, det vanliga 62,5.
        let serie: [DayValue] = (0..<20).map { (i: Int) -> DayValue in
            DayValue(day: 1_000 - i, value: i % 2 == 0 ? 25 : 100)
        }
        XCTAssertEqual(MarkerLevel.level(serie, endDay: 1_000, logarithmic: true)?.mean ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(MarkerLevel.level(serie, endDay: 1_000)?.mean ?? 0, 62.5, accuracy: 1e-9)
        // Noll går inte att logaritmera och hoppas över: då är det bara nitton nätter kvar.
        var medNoll = serie
        medNoll[0].value = 0
        XCTAssertNil(MarkerLevel.level(medNoll, endDay: 1_000, logarithmic: true))
    }

    // MARK: Det som skrivs in för hand

    func testMätningarLäggsTillOchTasBort() throws {
        var logg = MeasurementLog()
        try logg.add(MarkerReading(marker: .vo2max, day: 200, value: 44, note: "klocka", id: "b"))
        try logg.add(MarkerReading(marker: .vo2max, day: 100, value: 42, id: "a"))
        try logg.add(MarkerReading(marker: .gripStrength, day: 150, value: 48, id: "c"))
        XCTAssertEqual(logg.series(.vo2max).map(\.id), ["a", "b"], "äldst först")
        XCTAssertEqual(logg.series(.gripStrength).map(\.value), [48])
        logg.remove(id: "a")
        XCTAssertEqual(logg.series(.vo2max).map(\.id), ["b"])
        logg.remove(id: "finns-inte")
        XCTAssertEqual(logg.measurements.count, 2)
    }

    func testEnMätningSomInteGårAttSparaFelar() {
        var logg = MeasurementLog()
        XCTAssertThrowsError(try logg.add(MarkerReading(marker: "okänd", day: 1, value: 1))) { (e: Error) in
            XCTAssertEqual(e as? MarkerError, .unknownMarker)
        }
        XCTAssertThrowsError(try logg.add(MarkerReading(marker: .hrv, day: 1, value: 50))) { (e: Error) in
            XCTAssertEqual(e as? MarkerError, .notManual, "HRV mäts av Idunn")
        }
        for dåligt in [0, -3, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try logg.add(MarkerReading(marker: .vo2max, day: 1, value: dåligt))) { (e: Error) in
                XCTAssertEqual(e as? MarkerError, .invalidValue)
                XCTAssertFalse("\(e)".contains("3"), "felet visar aldrig värdet")
            }
        }
        XCTAssertTrue(logg.measurements.isEmpty)
    }

    func testEgnaMarkörer() throws {
        var logg = MeasurementLog()
        let lyft = try logg.addCustom(name: "  Marklyft ", unit: "kg", better: .higher, decimals: 0, id: "1")
        XCTAssertEqual(lyft.id, "egen-1")
        XCTAssertEqual(lyft.name, "Marklyft")
        XCTAssertEqual(lyft.source, .manual)
        XCTAssertEqual(logg.definitions.count, MarkerDefinition.builtIn.count + 1)
        try logg.add(MarkerReading(marker: lyft.id, day: 10, value: 120, id: "m"))
        XCTAssertThrowsError(try logg.addCustom(name: "   ", unit: "kg", better: .higher)) { (e: Error) in
            XCTAssertEqual(e as? MarkerError, .emptyName)
        }
        // En inbyggd markör går inte att ta bort; en egen tar sina mätningar med sig.
        logg.removeCustom(.vo2max)
        XCTAssertEqual(logg.definitions.count, MarkerDefinition.builtIn.count + 1)
        logg.removeCustom(lyft.id)
        XCTAssertNil(logg.definition(lyft.id))
        XCTAssertTrue(logg.measurements.isEmpty)
    }

    func testDeInbyggdaMarkörernaHarOlikaId() {
        let id: [MarkerID] = MarkerDefinition.builtIn.map(\.id)
        XCTAssertEqual(Set(id).count, id.count)
        XCTAssertEqual(MarkerDefinition.builtIn.filter { (d: MarkerDefinition) -> Bool in d.logarithmic }.map(\.id),
                       [.hrv], "bara HRV räknas i logaritmen")
    }

    func testFilenGårAttLäsaTillbaka() throws {
        var logg = MeasurementLog()
        let lyft = try logg.addCustom(name: "Marklyft", unit: "kg", better: .higher, id: "1")
        try logg.add(MarkerReading(marker: .vo2max, day: 100, value: 42.5, note: "labbtest", id: "a"))
        try logg.add(MarkerReading(marker: lyft.id, day: 120, value: 120, id: "b"))
        let data: Data = try logg.encoded()
        XCTAssertEqual(try MeasurementLog.decode(data), logg)
        XCTAssertEqual(try logg.encoded(), data, "samma logg ger samma fil")
        XCTAssertEqual(try MeasurementLog.decode(Data(#"{"custom":[],"measurements":[],"version":1}"#.utf8)),
                       MeasurementLog())
    }

    func testEnFilFrånEttNyareByggeLäsesInte() {
        let nyare = Data(#"{"custom":[],"measurements":[],"version":2}"#.utf8)
        XCTAssertThrowsError(try MeasurementLog.decode(nyare)) { (e: Error) in
            XCTAssertEqual(e as? MarkerError, .newerVersion)
        }
    }

    // MARK: Profilen

    /// Påhittade nätter: 40 nätter med värdet `nu` i det senaste kvartalet, 40 med `före` kvartalet före, och 40 med
    /// `ifjol` i fönstret ett år före det senaste. Sista natten är dag 20 000.
    private func nätter(nu: Double, före: Double, ifjol: Double) -> [DayValue] {
        var serie: [DayValue] = []
        for i in 0..<40 {
            serie.append(DayValue(day: 20_000 - 2 * i, value: nu))
            serie.append(DayValue(day: 19_910 - 2 * i, value: före))
            serie.append(DayValue(day: 19_635 - 2 * i, value: ifjol))
        }
        return serie
    }

    func testProfilenHarEttKortPerMarkörOckUtanVärden() {
        let kort = MarkerProfile.cards(person: nil, series: [:], log: MeasurementLog(), norms: [], today: 20_000)
        XCTAssertEqual(kort.map(\.id), MarkerDefinition.builtIn.map(\.id))
        XCTAssertTrue(kort.allSatisfy { (k: MarkerCard) -> Bool in k.value == nil && k.norm == nil && k.count == 0 })
    }

    func testNattmarkörensKortVisarKvartaletOchVadDetJämförsMed() throws {
        let kort = MarkerProfile.cards(person: nil, series: [.restingHeartRate: nätter(nu: 52, före: 54, ifjol: 57)],
                                       log: MeasurementLog(), norms: [], today: 20_005)
        let puls = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .restingHeartRate })
        XCTAssertEqual(puls.value, 52)
        XCTAssertEqual(puls.asOfDay, 20_000, "kvartalet slutar med den senaste natten, inte med idag")
        XCTAssertEqual(puls.count, 40)
        XCTAssertEqual(puls.previous, 54)
        XCTAssertEqual(puls.yearAgo, 57)
        XCTAssertEqual(puls.change, -2)
        XCTAssertEqual(puls.changeOverYear, -5)
        XCTAssertEqual(puls.improved(puls.change), true, "lägre vilopuls är bättre")
        XCTAssertNil(puls.best)
        // Nätter efter `today` räknas inte.
        let tidigare = MarkerProfile.cards(person: nil, series: [.restingHeartRate: nätter(nu: 52, före: 54, ifjol: 57)],
                                           log: MeasurementLog(), norms: [], today: 19_910)
        XCTAssertEqual(tidigare.first { (k: MarkerCard) -> Bool in k.id == .restingHeartRate }?.value, 54)
    }

    func testFörFåNätterGerInget() throws {
        let serie: [DayValue] = (0..<10).map { (i: Int) -> DayValue in DayValue(day: 20_000 - i, value: 60) }
        let kort = MarkerProfile.cards(person: nil, series: [.hrv: serie], log: MeasurementLog(), norms: [],
                                       today: 20_000)
        let hrv = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .hrv })
        XCTAssertNil(hrv.value)
        XCTAssertNil(hrv.change)
        XCTAssertNil(hrv.improved(hrv.change))
    }

    func testDetInskrivnaVisarSenasteFöregåendeOchBästa() throws {
        var logg = MeasurementLog()
        try logg.add(MarkerReading(marker: .vo2max, day: 19_000, value: 41, id: "a"))
        try logg.add(MarkerReading(marker: .vo2max, day: 19_400, value: 45, id: "b"))
        try logg.add(MarkerReading(marker: .vo2max, day: 19_800, value: 43, id: "c"))
        let kort = MarkerProfile.cards(person: nil, series: [:], log: logg, norms: [], today: 20_000)
        let syre = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .vo2max })
        XCTAssertEqual(syre.value, 43)
        XCTAssertEqual(syre.asOfDay, 19_800)
        XCTAssertEqual(syre.count, 3)
        XCTAssertEqual(syre.previous, 45)
        XCTAssertEqual(syre.best, 45)
        XCTAssertEqual(syre.improved(syre.change), false)
        XCTAssertNil(syre.yearAgo)
    }

    func testPassetsMarkörTarSinaVärdenUrSerien() throws {
        let serie = [DayValue(day: 19_990, value: 28), DayValue(day: 19_950, value: 24),
                     DayValue(day: 20_010, value: 99)]
        let kort = MarkerProfile.cards(person: nil, series: [.heartRateRecovery: serie], log: MeasurementLog(),
                                       norms: [], today: 20_000)
        let åter = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .heartRateRecovery })
        XCTAssertEqual(åter.value, 28, "passet efter idag räknas inte")
        XCTAssertEqual(åter.previous, 24)
        XCTAssertEqual(åter.best, 28)
        XCTAssertEqual(åter.count, 2)
    }

    func testPlatsenBlandJämnårigaOchMotsvarandeÅlder() throws {
        var logg = MeasurementLog()
        // Född 1980 och mätt dag 18 445 (2020-07-02): fyrtio år, där den påhittade tabellen har 26, 31, 36, 41, 46.
        try logg.add(MarkerReading(marker: .vo2max, day: 18_445, value: 38, id: "a"))
        let person = Person(birthYear: 1980, sex: .male)
        let kort = MarkerProfile.cards(person: person, series: [:], log: logg, norms: [tabell()], today: 20_000)
        let norm = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.norm)
        XCTAssertEqual(norm.source, "PÅHITTAD")
        XCTAssertEqual(norm.age, 40, accuracy: 0.01, "åldern den dag värdet mättes, inte idag")
        XCTAssertEqual(norm.position.percentile, 60, accuracy: 0.05)
        XCTAssertEqual(norm.betterThan ?? 0, 60, accuracy: 0.05)
        XCTAssertEqual(norm.edge, .inside)
        XCTAssertEqual(norm.equivalentAge, .years(35), "medianen är 38 vid 35 år")
        XCTAssertEqual(norm.ageGap ?? 0, -5, accuracy: 0.01)
        // Utan person, och med en tabell som inte täcker könet, finns ingen plats.
        XCTAssertNil(MarkerProfile.cards(person: nil, series: [:], log: logg, norms: [tabell()], today: 20_000)
            .first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.norm)
        XCTAssertNil(MarkerProfile.cards(person: Person(birthYear: 1980, sex: .female), series: [:], log: logg,
                                         norms: [tabell()], today: 20_000)
            .first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.norm)
    }

    func testLägreÄrBättreVänderAndelen() throws {
        // Vilopulsen 30 vid 40 år ligger mellan percentil 10 (26) och 25 (31) i den påhittade tabellen: 22.
        let t = tabell(.restingHeartRate, trend: .flat)
        let lågt = try XCTUnwrap(MarkerProfile.standing(value: 30, age: 40, sex: .male, table: t, better: .lower))
        XCTAssertEqual(lågt.position.percentile, 22, accuracy: 1e-9)
        XCTAssertEqual(lågt.betterThan ?? 0, 78, accuracy: 1e-9, "lägre än 78 % av de jämnåriga")
        XCTAssertNil(lågt.equivalentAge, "vilopulsen har ingen motsvarande ålder")
        XCTAssertNil(lågt.ageGap)
        // Utanför tabellens kanter: under den lägsta percentilen är den bra sidan när lägre är bättre.
        let under = try XCTUnwrap(MarkerProfile.standing(value: 20, age: 40, sex: .male, table: t, better: .lower))
        XCTAssertEqual(under.betterThan, 90)
        XCTAssertEqual(under.edge, .atLeast)
        let över = try XCTUnwrap(MarkerProfile.standing(value: 60, age: 40, sex: .male, table: t, better: .lower))
        XCTAssertEqual(över.betterThan, 10)
        XCTAssertEqual(över.edge, .atMost)
        // Och tvärtom när högre är bättre.
        let högt = try XCTUnwrap(MarkerProfile.standing(value: 60, age: 40, sex: .male, table: t, better: .higher))
        XCTAssertEqual(högt.betterThan, 90)
        XCTAssertEqual(högt.edge, .atLeast)
        // En markör utan riktning får percentilen men ingen andel.
        let utan = try XCTUnwrap(MarkerProfile.standing(value: 36, age: 40, sex: .male, table: t, better: .neutral))
        XCTAssertNil(utan.betterThan)
        XCTAssertEqual(utan.position.percentile, 50)
    }

    // MARK: Texterna (BESLUT B105)

    func testTalenSkrivsMedDecimalkomma() {
        XCTAssertEqual(MarkerText.number(42.46, decimals: 1), "42,5")
        XCTAssertEqual(MarkerText.number(52, decimals: 0), "52")
        XCTAssertEqual(MarkerText.number(-3.2, decimals: 1), "−3,2")
        XCTAssertEqual(MarkerText.number(-0.04, decimals: 1), "0,0", "aldrig minus noll")
        XCTAssertEqual(MarkerText.signed(2, decimals: 0), "+2")
        XCTAssertEqual(MarkerText.signed(-1.5, decimals: 1), "−1,5")
        XCTAssertEqual(MarkerText.signed(0.4, decimals: 0), "±0")
        XCTAssertEqual(MarkerText.signed(-0.04, decimals: 1), "±0")
    }

    func testDagenSomDatum() {
        XCTAssertEqual(MarkerText.date(day: 0), "1 jan 1970")
        XCTAssertEqual(MarkerText.date(day: 18_445), "2 juli 2020")
        XCTAssertEqual(MarkerText.date(day: 20_407), "15 nov 2025")
        XCTAssertEqual(MarkerText.date(day: 19_782), "29 feb 2024", "skottdagen")
        XCTAssertEqual(MarkerText.date(day: -1), "31 dec 1969")
        for dag in [-800, 0, 59, 11_016, 18_445, 19_782, 19_783, 20_407] {
            let d = MarkerText.civil(day: dag)
            XCTAssertEqual(MarkerText.day(year: d.year, month: d.month, day: d.day), dag)
        }
        XCTAssertEqual(MarkerText.day(year: 2020, month: 7, day: 2), 18_445)
    }

    func testPlatsenOchÅldernSomText() throws {
        let t = tabell()
        // 38,4 vid 40 år: percentilen 50 + 2,4 / 5 × 25 = 62, och medianen är 38,4 vid 25 + 1,6 / 2 × 10 = 33 år.
        let inne = try XCTUnwrap(MarkerProfile.standing(value: 38.4, age: 40, sex: .male, table: t, better: .higher))
        XCTAssertEqual(MarkerText.standing(inne), "Bättre än 62 % av jämnåriga")
        XCTAssertEqual(MarkerText.equivalentAge(inne), "Som en 33-åring")
        let över = try XCTUnwrap(MarkerProfile.standing(value: 60, age: 40, sex: .male, table: t, better: .higher))
        XCTAssertEqual(MarkerText.standing(över), "Bättre än minst 90 % av jämnåriga")
        XCTAssertEqual(MarkerText.equivalentAge(över), "Som en 25-åring eller bättre")
        let under = try XCTUnwrap(MarkerProfile.standing(value: 20, age: 40, sex: .male, table: t, better: .higher))
        XCTAssertEqual(MarkerText.standing(under), "Bättre än högst 10 % av jämnåriga")
        XCTAssertEqual(MarkerText.equivalentAge(under), "Som äldre än 55 år")
        let utan = try XCTUnwrap(MarkerProfile.standing(value: 36, age: 40, sex: .male, table: tabell(trend: .flat),
                                                        better: .neutral))
        XCTAssertNil(MarkerText.standing(utan))
        XCTAssertNil(MarkerText.equivalentAge(utan))
    }

    func testKortetsRader() throws {
        var logg = MeasurementLog()
        try logg.add(MarkerReading(marker: .vo2max, day: 19_400, value: 45, id: "a"))
        try logg.add(MarkerReading(marker: .vo2max, day: 20_407, value: 43.5, id: "b"))
        let kort = MarkerProfile.cards(person: nil, series: [.restingHeartRate: nätter(nu: 52, före: 54, ifjol: 57)],
                                       log: logg, norms: [], today: 20_500)
        let syre = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .vo2max })
        XCTAssertEqual(MarkerText.value(syre), "43,5")
        XCTAssertEqual(MarkerText.change(syre), "−1,5 mot förra mätningen")
        XCTAssertEqual(MarkerText.best(syre), "Bäst 45,0")
        XCTAssertEqual(MarkerText.basis(syre), "15 nov 2025")
        XCTAssertNil(MarkerText.overYear(syre))
        let puls = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .restingHeartRate })
        XCTAssertEqual(MarkerText.value(puls), "52")
        XCTAssertEqual(MarkerText.change(puls), "−2 mot kvartalet före")
        XCTAssertEqual(MarkerText.overYear(puls), "−5 mot för ett år sedan")
        XCTAssertEqual(MarkerText.basis(puls), "Medel av 40 nätter, senaste 90 dagarna")
        XCTAssertNil(MarkerText.best(puls))
        let tomt = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .gripStrength })
        XCTAssertEqual(MarkerText.value(tomt), "–")
        XCTAssertNil(MarkerText.change(tomt))
        XCTAssertNil(MarkerText.basis(tomt))
        XCTAssertNil(MarkerText.best(tomt))
    }

    func testMaxpulsenÄrEnUppgiftUtanOmdöme() throws {
        let kort = MarkerProfile.cards(person: nil, series: [.maxPulse: [DayValue(day: 20_000, value: 182)]],
                                       log: MeasurementLog(), norms: [], today: 20_100)
        let max = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .maxPulse })
        XCTAssertEqual(max.value, 182)
        XCTAssertNil(max.best, "ingen riktning, så inget bästa")
        XCTAssertNil(max.improved(5))
    }

    // MARK: Det Idunn räknat och det inskrivna i samma markör (BESLUT B111)

    func testRäknatOchInskrivetHörTillSammaMarkör() throws {
        // Påhittat: Idunn har räknat konditionen dag 20 000 och 20 100, och ett tal är inskrivet dag 19 900.
        var logg = MeasurementLog()
        try logg.add(MarkerReading(marker: .vo2max, day: 19_900, value: 44, id: "a"))
        let räknat: [MarkerID: [DayValue]] = [.vo2max: [DayValue(day: 20_000, value: 46), DayValue(day: 20_100, value: 47)]]
        let kort = MarkerProfile.cards(person: nil, series: räknat, log: logg, today: 20_200)
        let syre = try XCTUnwrap(kort.first { (k: MarkerCard) -> Bool in k.id == .vo2max })
        XCTAssertEqual(syre.value, 47, "den senaste gäller, räknad eller inskriven")
        XCTAssertEqual(syre.asOfDay, 20_100)
        XCTAssertEqual(syre.previous, 46)
        XCTAssertEqual(syre.definition.name, "Kondition")
        // Ett räknat värde efter idag räknas inte, och ett senare inskrivet tal gäller före det räknade.
        let tidigare = MarkerProfile.cards(person: nil, series: räknat, log: logg, today: 20_050)
        XCTAssertEqual(tidigare.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.value, 46)
        try logg.add(MarkerReading(marker: .vo2max, day: 20_150, value: 45, id: "b"))
        let inskrivet = MarkerProfile.cards(person: nil, series: räknat, log: logg, today: 20_200)
        XCTAssertEqual(inskrivet.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.value, 45)
        // Utan räknade värden är allt som förut.
        let bara = MarkerProfile.cards(person: nil, series: [:], log: logg, today: 20_200)
        XCTAssertEqual(bara.first { (k: MarkerCard) -> Bool in k.id == .vo2max }?.previous, 44)
    }
}
