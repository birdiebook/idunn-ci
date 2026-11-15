import Foundation
import XCTest
import DemoData
import HeartRate
import WhoopFrames
@testable import Night

// METOD M28 · BESLUT B30 · BESLUT B31. Appens väg från dygnsfiler till natt:
// påhittade K18-nätter (DemoK18Nights) skrivna som ramar i dygnsfiler (som
// lyssnaren gör), lästa strömmande och jämförda med att räkna samma ramar i
// ett svep. Inga värden kommer från ett riktigt band.

final class K18DaysTests: XCTestCase {

    // MARK: Hjälpare

    /// Dygnsfilerna som lyssnaren skulle ha skrivit: varje notis i filen för
    /// det lokala datum den hördes, `delay` sekunder efter att den mättes.
    func dygnsfiler(_ nätter: [DemoK18Nights.Night], delay: Double = 0, zon: Int) -> [K18Days.File] {
        var perDag: [String: [RawFrame]] = [:]
        for n in nätter {
            for x in DemoK18Frames.notifications(n.records, delay: delay) {
                perDag[DayLog.stem(for: x.time, utcOffsetSeconds: zon), default: []].append(x)
            }
        }
        return perDag.keys.sorted().map { (stem: String) -> K18Days.File in
            K18Days.File(stem: stem, sidecar: RecordingLog.header(utcOffsetSeconds: zon),
                         frames: DemoK18Frames.log(perDag[stem] ?? []))
        }
    }

    /// Det appen läser för en natt: bara filerna natten behöver.
    func inläsning(_ filer: [K18Days.File], dag: WakeDay, nästa: Bool) -> [K18Days.File] {
        let behövs = Set(K18Days.stems(wakeDay: dag, includeNext: nästa))
        return filer.filter { behövs.contains($0.stem) }
    }

    func uppvakningsdag(_ n: DemoK18Nights.Night) -> WakeDay {
        WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
    }

    /// Facit: samma ramar i ett svep, utan filer och utan strömmande läsning.
    func facit(_ nätter: [DemoK18Nights.Night], dag: WakeDay, zon: Int) -> NightResult? {
        var notiser: [RawFrame] = []
        for n in nätter { notiser += DemoK18Frames.notifications(n.records) }
        return K18Night.analyze(K18Series(notifications: notiser), wakeDay: dag,
                                startOffsetSeconds: zon, endOffsetSeconds: zon)
    }

    // MARK: Filerna en natt läser

    func testEnNattLäserDygnetFöreOchSjälvOchDygnetEfterNärDenSattSig() {
        let d = WakeDay(daysSince1970: DayLog.Day(year: 2026, month: 10, day: 14).daysSince1970)
        XCTAssertEqual(K18Days.stems(wakeDay: d, includeNext: false), ["dygn-2026-10-13", "dygn-2026-10-14"])
        XCTAssertEqual(K18Days.stems(wakeDay: d, includeNext: true),
                       ["dygn-2026-10-13", "dygn-2026-10-14", "dygn-2026-10-15"])
        let månad = WakeDay(daysSince1970: DayLog.Day(year: 2026, month: 3, day: 1).daysSince1970)
        XCTAssertEqual(K18Days.stems(wakeDay: månad, includeNext: false), ["dygn-2026-02-28", "dygn-2026-03-01"])
    }

    // MARK: Samma natt som i ett svep

    func testNattenUrDygnsfilernaÄrSammaNattSomIEttSvep() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let filer = dygnsfiler([n], zon: z)
        XCTAssertEqual(filer.count, 2, "kvällen före midnatt och natten efter")

        let ur = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(filer, dag: dag, nästa: false),
                                                fallbackOffsetSeconds: 0))
        let svep = try XCTUnwrap(facit([n], dag: dag, zon: z))
        XCTAssertEqual(ur.source, .k18)
        XCTAssertEqual(ur.wakeDay, dag)
        XCTAssertEqual(ur.utcOffsetSeconds, z, "zonen kommer ur sidofilen, inte ur reservzonen")
        XCTAssertGreaterThan(ur.analysis.validWindows, 40)
        XCTAssertTrue(ur == svep, "natten ur filerna skiljer sig från natten i ett svep")
    }

    func testEnAnnanNattIFilernaPåverkarInteDennaNatt() throws {
        let a = DemoK18Nights.night(daysBeforeLast: 1, shortGaps: false)
        let b = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = b.utcOffsetSeconds
        let dag = uppvakningsdag(b)
        XCTAssertEqual(uppvakningsdag(a) + 1, dag)
        let filer = dygnsfiler([a, b], zon: z)
        let ur = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(filer, dag: dag, nästa: false),
                                                fallbackOffsetSeconds: z))
        let bara = try XCTUnwrap(facit([b], dag: dag, zon: z))
        XCTAssertTrue(ur == bara, "föregående natts poster i samma fil ska inte räknas")
        let igår = try XCTUnwrap(K18Days.compute(wakeDay: dag - 1,
                                                  files: inläsning(filer, dag: dag - 1, nästa: false),
                                                  fallbackOffsetSeconds: z))
        XCTAssertEqual(igår.wakeDay, dag - 1)
    }

    func testReservzonenGällerBaraNärSidofilerSaknas() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let utanSida: [K18Days.File] = dygnsfiler([n], zon: z).map {
            K18Days.File(stem: $0.stem, sidecar: nil, frames: $0.frames)
        }
        let ur = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: utanSida, fallbackOffsetSeconds: z))
        XCTAssertEqual(ur.utcOffsetSeconds, z)
        let svep = try XCTUnwrap(facit([n], dag: dag, zon: z))
        XCTAssertTrue(ur == svep)
    }

    // MARK: Ur dygnsarkivet (BESLUT B41, METOD M34)

    /// Dygnsfilerna som arkiv: rådygnet borta, arkivet kvar.
    func somArkiv(_ filer: [K18Days.File], compress: Bool = true) -> [K18Days.File] {
        filer.map { (f: K18Days.File) -> K18Days.File in
            let dag = DayLog.day(ofStem: f.stem) ?? DayLog.Day(year: 1970, month: 1, day: 1)
            let a = DayArchive.build(day: dag, sidecar: f.sidecar, frames: f.frames)
            return K18Days.File(stem: f.stem, sidecar: nil, frames: nil, archive: a.encode(compress: compress))
        }
    }

    func testNattenUrArkivenÄrSammaNattSomUrDygnsfilerna() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let filer = dygnsfiler([n], zon: z)
        let rå = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(filer, dag: dag, nästa: false),
                                                fallbackOffsetSeconds: 0))
        for packa in [false, true] {
            let arkiv = somArkiv(filer, compress: packa)
            let ur = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(arkiv, dag: dag, nästa: false),
                                                    fallbackOffsetSeconds: 0))
            XCTAssertEqual(ur.utcOffsetSeconds, z, "zonen kommer ur sidofilen i arkivet")
            XCTAssertTrue(ur == rå, "natten ur arkivet skiljer sig från natten ur rådygnen")
        }
    }

    func testEttDygnSomArkivOchEttSomRådygnGerSammaNatt() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let filer = dygnsfiler([n], zon: z)
        let rå = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(filer, dag: dag, nästa: false),
                                                fallbackOffsetSeconds: 0))
        let arkiv = somArkiv(filer)
        let blandat = [arkiv[0], filer[1]]
        let ur = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(blandat, dag: dag, nästa: false),
                                                fallbackOffsetSeconds: 0))
        XCTAssertTrue(ur == rå)
        // Finns båda gäller rådygnet.
        let bådaDelar = zip(filer, arkiv).map { (f: K18Days.File, a: K18Days.File) -> K18Days.File in
            K18Days.File(stem: f.stem, sidecar: f.sidecar, frames: f.frames, archive: a.archive)
        }
        let båda = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(bådaDelar, dag: dag, nästa: false),
                                                  fallbackOffsetSeconds: 0))
        XCTAssertTrue(båda == rå)
    }

    func testEttTrasigtArkivRäknasSomEnFilSomSaknas() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let arkiv = somArkiv(dygnsfiler([n], zon: z)).map { (f: K18Days.File) -> K18Days.File in
            K18Days.File(stem: f.stem, sidecar: nil, frames: nil, archive: Data((f.archive ?? Data()).dropLast(3)))
        }
        XCTAssertNil(K18Days.compute(wakeDay: dag, files: inläsning(arkiv, dag: dag, nästa: false),
                                     fallbackOffsetSeconds: z))
    }

    /// BESLUT B85 · BESLUT B41. Ett nytt bygge räknar om en natt vars rådygn är borta, ur arkivet, med appens väg
    /// (`NightLedger.computeDue` som `K18Nights.computeDue`): den får samma sammanfattning som ur rådygnen och
    /// stadierna efter B85, så att gamla nätter får det nya räknesättet.
    func testEttNyttByggeRäknarOmEnNattUrArkivetMedDetNyaRäknesättet() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false, stages: true)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let rå = dygnsfiler([n], zon: z)
        let nu: Date = NightLedger.windowEnd(dag, utcOffsetSeconds: z).addingTimeInterval(30 * 3_600)
        var poster: [WakeDay: NightLedger.Entry] = [:]
        func räkna(_ filer: [K18Days.File], bygge: String) -> Int {
            var perStam: [String: K18Days.File] = [:]
            for f in filer { perStam[f.stem] = f }
            return NightLedger.computeDue(dayStems: filer.map(\.stem), entries: poster, build: bygge, now: nu,
                                          utcOffsetSeconds: z, load: { (s: String) -> K18Days.File? in perStam[s] },
                                          save: { (e: NightLedger.Entry) -> Void in poster[e.wakeDay] = e })
        }
        XCTAssertGreaterThan(räkna(rå, bygge: "1"), 0)
        let urRå: NightDigest = try XCTUnwrap(poster[dag]?.digest)
        XCTAssertNotNil(urRå.lightMinutes, "natten har stadier")

        let arkiv = somArkiv(rå)
        XCTAssertTrue(arkiv.allSatisfy { $0.frames == nil && $0.sidecar == nil && $0.archive != nil })
        XCTAssertEqual(räkna(arkiv, bygge: "1"), 0, "samma bygge räknar inte om")
        XCTAssertGreaterThan(räkna(arkiv, bygge: "2"), 0, "ett nytt bygge räknar om, också ur arkivet")
        XCTAssertEqual(poster[dag]?.build, "2")
        XCTAssertEqual(poster[dag]?.digest, urRå, "samma natt ur arkivet som ur rådygnen")

        // Natten ur arkivet har stadierna efter B85: varje följd av lätt, djup eller REM i en mätt sträcka med
        // fler än en följd är minst fyra epoker.
        let r = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(arkiv, dag: dag, nästa: true),
                                               fallbackOffsetSeconds: z))
        let stadier = try XCTUnwrap(r.stages)
        let st: [Int] = stadier.epochs.map { (e: NightStages.Epoch) -> Int in e.stage?.rawValue ?? -1 }
        var j = 0
        var prövade = 0
        while j < st.count {
            if st[j] < 0 {
                j += 1
                continue
            }
            let a = j
            while j < st.count && st[j] >= 0 { j += 1 }
            let f: [[Int]] = NightStages.runs(st, a, j)
            if f.count < 2 { continue }
            for x in f where x[2] != SleepStage.wake.rawValue {
                XCTAssertGreaterThanOrEqual(x[1] - x[0], NightStages.minSleepRunEpochs)
                prövade += 1
            }
        }
        XCTAssertGreaterThan(prövade, 0)
    }

    // MARK: Ingen natt

    func testIngaFilerOchEnDagUtanDataGerIngenNatt() {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let dag = uppvakningsdag(n)
        XCTAssertNil(K18Days.compute(wakeDay: dag, files: [], fallbackOffsetSeconds: 7200))
        let filer = dygnsfiler([n], zon: n.utcOffsetSeconds)
        XCTAssertNil(K18Days.compute(wakeDay: dag + 5, files: filer, fallbackOffsetSeconds: 7200),
                     "filer som inte rör dagens fönster")
        let tomma = [K18Days.File(stem: "dygn-2026-10-10", sidecar: nil, frames: Data())]
        XCTAssertNil(K18Days.compute(wakeDay: dag, files: tomma, fallbackOffsetSeconds: 7200))
    }

    // MARK: En natt som hörs dygnet efter

    func testEnNattSomSynkasEfterEttDygnFinnsBaraMedDygnetEfter() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        // Alla poster hörs 30 timmar efter att de mättes: i filen efter uppvakningsdagen.
        let filer = dygnsfiler([n], delay: 30 * 3600, zon: z)
        XCTAssertNil(K18Days.compute(wakeDay: dag, files: inläsning(filer, dag: dag, nästa: false),
                                     fallbackOffsetSeconds: z), "bara dygnen före och självt: ingenting")
        let satt = try XCTUnwrap(K18Days.compute(wakeDay: dag, files: inläsning(filer, dag: dag, nästa: true),
                                                  fallbackOffsetSeconds: z))
        let svep = try XCTUnwrap(facit([n], dag: dag, zon: z))
        XCTAssertTrue(satt == svep)
    }

    // MARK: Sammanfattningen

    func testSammanfattningenBärTalenUrNatten() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: true)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let r = try XCTUnwrap(facit([n], dag: dag, zon: z))
        let d = NightDigest(r, preliminary: true)
        XCTAssertEqual(d.source, .k18)
        XCTAssertEqual(d.wakeDay, dag)
        XCTAssertEqual(d.utcOffsetSeconds, z)
        XCTAssertTrue(d.preliminary)
        XCTAssertEqual(d.rmssdMean, r.analysis.rmssd.mean)
        XCTAssertEqual(d.rmssdWhoopLike, r.analysis.rmssd.whoopLike)
        XCTAssertEqual(d.restingHeartRate, r.analysis.restingHeartRate)
        XCTAssertEqual(d.breathsPerMinute, r.analysis.breathsPerMinute)
        XCTAssertEqual(d.validWindows, r.analysis.validWindows)
        XCTAssertEqual(d.sleepStart, r.sleep?.onsetDate)
        XCTAssertEqual(d.sleepEnd, r.sleep?.wakeDate)
        XCTAssertEqual(d.sleepMinutes, r.sleep?.asleepMinutesTotal)
        XCTAssertEqual(d.coverage, r.coverage)
        XCTAssertEqual(d.skinTemperature, r.skin?.celsius)
        XCTAssertEqual(d.skinCoverage, r.skin?.coverage)
        XCTAssertEqual(d.profile, r.curve?.profile)
        XCTAssertEqual(d.landscape, r.landscape)
        XCTAssertEqual(d.reanchorings, r.analysis.cleaning.reanchorings)
        XCTAssertEqual(d.omittedBeats, r.analysis.cleaning.omitted)
        XCTAssertGreaterThan(d.pulseSeconds, 3600 * 4)
        XCTAssertNotNil(d.sleepMinutes)
        XCTAssertFalse(NightDigest(r).preliminary)

        // Trenderna och kortet ser sömntiden i timmar och källan.
        let natt = d.idunNight
        XCTAssertEqual(natt.day, dag)
        let timmar = try XCTUnwrap(natt.sleepHours)
        let minuter = try XCTUnwrap(d.sleepMinutes)
        XCTAssertEqual(timmar, minuter / 60, accuracy: 1e-12)
        XCTAssertEqual(natt.source, .k18)
        XCTAssertEqual(natt.rmssdWhoopLike, d.rmssdWhoopLike)
        // METOD M33. Sömnperioden är passet som regelbundenheten räknar på.
        let pass = try XCTUnwrap(natt.sleepEpisode)
        XCTAssertEqual(pass.onset, d.sleepStart)
        XCTAssertEqual(pass.wake, d.sleepEnd)
        XCTAssertEqual(pass.utcOffsetSeconds, z)
        let period = try XCTUnwrap(d.sleepEnd).timeIntervalSince(try XCTUnwrap(d.sleepStart)) / 60
        XCTAssertEqual(try XCTUnwrap(pass.inBedMinutes), Int(period.rounded()))
        XCTAssertLessThanOrEqual(try XCTUnwrap(pass.asleepMinutes), try XCTUnwrap(pass.inBedMinutes))
        XCTAssertFalse(pass.isNap)
    }

    func testSammanfattningenGårAttSparaOchLäsaIgen() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 2, shortGaps: true)
        let dag = uppvakningsdag(n)
        let r = try XCTUnwrap(facit([n], dag: dag, zon: n.utcOffsetSeconds))
        let d = NightDigest(r)
        let data = try JSONEncoder().encode(d)
        let tillbaka = try JSONDecoder().decode(NightDigest.self, from: data)
        XCTAssertEqual(tillbaka, d)
        // BESLUT B3: ett enda slag eller intervall ryms inte i sammanfattningen.
        XCTAssertLessThan(data.count, 20_000, "bara samlade tal och profiler")
    }

    func testKontrollenAvStämpelnsTolkningBärOmläggningarnaOchDeUtelämnade() throws {
        // M28: många omläggningar skulle visa att stämpeln tolkas fel. Sammanfattningen
        // bär exakt det analysen räknade, så att Data kan visa det natt för natt.
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: true)
        let r = try XCTUnwrap(facit([n], dag: uppvakningsdag(n), zon: n.utcOffsetSeconds))
        let d = NightDigest(r)
        XCTAssertEqual(d.reanchorings, r.analysis.cleaning.reanchorings)
        XCTAssertEqual(d.fractionReanchored, r.analysis.cleaning.fractionReanchored)
        XCTAssertEqual(d.omittedBeats, r.analysis.cleaning.omitted)
        XCTAssertEqual(d.fractionOmitted, r.analysis.cleaning.fractionOmitted)
        XCTAssertTrue((0.0...1.0).contains(d.fractionReanchored))
        XCTAssertTrue((0.0...1.0).contains(d.fractionOmitted))
    }
}
