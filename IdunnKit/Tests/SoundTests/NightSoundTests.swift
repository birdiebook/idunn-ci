import Foundation
import XCTest
import DemoData
import HeartRate
import Night
import WhoopFrames
@testable import Sound

// METOD M44 · BESLUT B54 (J3). Nattens ljud som vyerna ser det, på den påhittade ljudnatten (DemoSound):
// två snarkepisoder (första din, andra någon annans), tre trafikhändelser (de två första väckte), två
// rörelseljud, en talepisod och en klockskillnad på 7 s. Facit står i `DemoSound.Truth`.

final class NightSoundTests: XCTestCase {

    static let natt: DemoSound.Night = SoundFixtures.night

    static func källa(_ n: DemoSound.Night, seconds: [SoundSecond]? = nil, start: Int? = nil) -> NightSoundMaker.Source {
        let s: Int = start ?? n.start
        return NightSoundMaker.Source(stem: SoundFile.stem(start: s), start: s, seconds: seconds ?? n.seconds)
    }

    static let ljudet: NightSound = {
        let n = NightSoundTests.natt
        return NightSoundMaker.make(sources: [NightSoundTests.källa(n)], series: n.series, layers: n.layers)!
    }()

    var ljud: NightSound { Self.ljudet }

    func trafik() -> [NightSound.Event] {
        ljud.events.filter { (e: NightSound.Event) -> Bool in e.soundClass == SoundClass.traffic.rawValue }
    }

    // MARK: Klasserna

    /// Granskningen 2026-10-15: två symboler tätt intill varandra får var sin rad, glesa symboler stannar på
    /// den första, och en tredje i trängseln hamnar på den rad som står friast.
    func testTätaSymbolerFårEnAndraRad() {
        XCTAssertEqual(NightSound.symbolRows(times: [], minGap: 600), [])
        XCTAssertEqual(NightSound.symbolRows(times: [0, 3600, 7200], minGap: 600), [0, 0, 0])
        XCTAssertEqual(NightSound.symbolRows(times: [0, 300, 1200], minGap: 600), [0, 1, 0])
        XCTAssertEqual(NightSound.symbolRows(times: [0, 100, 200, 900], minGap: 600), [0, 1, 0, 0])
    }

    func testKlassindexenIVyernaÄrLjudetsKlasser() {
        XCTAssertEqual(NightSound.snoringClass, SoundClass.snoring.rawValue)
        XCTAssertEqual(NightSound.breathingClass, SoundClass.breathing.rawValue)
        XCTAssertEqual(NightSound.otherClass, SoundClass.other.rawValue)
    }

    // MARK: Händelserna

    func testHändelsernaUnderSömnperiodenHarKlassÄgareOchFöljd() {
        let n = Self.natt
        let klasser = ljud.events.map { $0.soundClass }
        // Din snarkning (10) och någon annans (10), trafik (3), tal (1) och de två rörelseljuden i sömnen; de tolv
        // prasslen före insomningen är utanför sömnperioden.
        XCTAssertEqual(klasser.filter { $0 == SoundClass.snoring.rawValue }.count, 20)
        XCTAssertEqual(klasser.filter { $0 == SoundClass.traffic.rawValue }.count, 3)
        XCTAssertEqual(klasser.filter { $0 == SoundClass.speech.rawValue }.count, 1)
        XCTAssertEqual(klasser.filter { $0 == SoundClass.other.rawValue }.count, 2)
        XCTAssertEqual(ljud.events.count, 26)
        for e in ljud.events { XCTAssertTrue(n.layers.period.contains(e.time), "inom sömnperioden") }
        XCTAssertEqual(ljud.events.map { $0.time }, ljud.events.map { $0.time }.sorted(), "i tidsordning")

        // Ägaren: första episoden din, andra någon annans; allt annat har ingen ägare.
        let snarkning = ljud.events.filter { $0.isSnoring }
        XCTAssertEqual(snarkning.prefix(10).map { $0.owner }, [NightSound.Owner?](repeating: .yours, count: 10))
        XCTAssertEqual(snarkning.suffix(10).map { $0.owner }, [NightSound.Owner?](repeating: .someoneElse, count: 10))
        XCTAssertTrue(ljud.events.filter { !$0.isSnoring }.allSatisfy { $0.owner == nil })

        // Tiderna är bandets klocka: telefonens sekund + filens start + klockskillnaden på 7 s.
        let t = trafik()
        XCTAssertEqual(t.count, n.truth.traffic.count)
        for (e, sekund) in zip(t, n.truth.traffic) {
            // Klockskillnaden skattas på en sekund när (METOD M40, J1: 7 ± 1 s).
            XCTAssertEqual(e.time, Double(n.start + sekund + n.clockOffset), accuracy: 1.5)
        }
        XCTAssertTrue(ljud.clockReliable)
    }

    func testTrafikenSomVäckteÄrMarkeradOchRörelseljudetÄrIngenOrsak() {
        let t = trafik()
        XCTAssertEqual(t.map { $0.woke }, Self.natt.truth.trafficWoke)
        XCTAssertEqual(t.map { $0.pulse }, [true, true, false])
        XCTAssertTrue(t.allSatisfy { !$0.movement })
        XCTAssertEqual(ljud.followed.count, 2)
        XCTAssertEqual(ljud.followed.map { $0.soundClass }, [SoundClass.traffic.rawValue, SoundClass.traffic.rawValue])

        // Det andra rörelseljudet följs av ett uppvaknande, men det är armen som väckte, inte ljudet.
        let rörelse = ljud.events.filter { $0.movement }
        XCTAssertEqual(rörelse.count, 2)
        XCTAssertTrue(rörelse.allSatisfy { !$0.woke && !$0.pulse }, "räknas aldrig som orsak")
        // Din snarkning räknas inte heller som orsak.
        XCTAssertTrue(ljud.events.filter { $0.owner == .yours }.allSatisfy { !$0.followed })
    }

    func testKlippenPekarPåFilenOchSekunden() {
        let n = Self.natt
        let stam = SoundFile.stem(start: n.start)
        XCTAssertEqual(SoundFile.start(ofStem: stam), n.start)
        XCTAssertNil(SoundFile.start(ofStem: "dygn-2026-10-14"))
        XCTAssertNil(SoundFile.start(ofStem: "2026-10-14T21-03-00Z"), "en inspelning är ingen ljudfil")
        let t = trafik()
        XCTAssertEqual(t.map { $0.clip.second }, n.truth.traffic)
        XCTAssertTrue(t.allSatisfy { $0.clip.stem == stam })
        XCTAssertEqual(t[0].clip.fileName, "02400.m4a")
        XCTAssertEqual(t[0].clip.key, stam + "/02400")
        XCTAssertEqual(Set(ljud.events.map { $0.id }).count, ljud.events.count, "ett id per händelse")
    }

    // MARK: Nivån

    func testNivånÖverGolvetPerMinutInomSömnperioden() {
        let n = Self.natt
        XCTAssertFalse(ljud.levels.isEmpty)
        XCTAssertTrue(ljud.levels.allSatisfy { $0.aboveFloor >= 0 })
        XCTAssertTrue(ljud.levels.allSatisfy { n.layers.period.contains($0.start + 59) || n.layers.period.contains($0.start) })
        XCTAssertEqual(ljud.levels.map { $0.start }, ljud.levels.map { $0.start }.sorted())
        XCTAssertEqual(Double(ljud.levels.count), 75, accuracy: 1, "75 minuter från insomning till uppvaknande")
        // Trafiken (22 dB över bakgrunden) syns som den högsta minuten; en tyst minut ligger nära golvet.
        let top = ljud.levels.map { $0.aboveFloor }.max() ?? 0
        XCTAssertGreaterThan(top, 18)
        let nivåer: [NightSound.Level] = ljud.levels
        let minut: (Double) -> NightSound.Level? = { (t: Double) -> NightSound.Level? in
            nivåer.first { (l: NightSound.Level) -> Bool in l.start == (t / 60).rounded(.down) * 60 }
        }
        let trafiken = Double(n.start + n.truth.traffic[2] + n.clockOffset + 1)
        XCTAssertGreaterThan(minut(trafiken)?.aboveFloor ?? 0, 15)
        let tyst = Double(n.start + 4_500 + n.clockOffset)
        XCTAssertLessThan(minut(tyst)?.aboveFloor ?? 99, 8)
    }

    // MARK: Snarkminuter per timme sömn

    func testDinaSnarkminuterPerTimmeSömnUrDenSovnaTiden() throws {
        // 9,5 minuter (570 s) din snarkning i 4 415 s mätt sömn (heltalssekunderna i de fyra sovna bitarna: 4 419).
        XCTAssertEqual(ljud.yoursMinutes, 9.5, accuracy: 1e-9)
        XCTAssertEqual(ljud.someoneElseMinutes, 9.5, accuracy: 1e-9)
        XCTAssertEqual(ljud.unknownMinutes, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ljud.coverage), 1, accuracy: 0.01, "ljudet täckte hela den sovna tiden")
        XCTAssertEqual(try XCTUnwrap(ljud.snoringPerHour), 9.5 / (4_419.0 / 3_600), accuracy: 0.02)
    }

    func testTäckerLjudetMindreÄnHälftenAvSömnenFinnsInteTalet() {
        let n = Self.natt
        let sista = n.seconds.filter { $0.second >= 4_000 }
        let s = NightSoundMaker.make(sources: [Self.källa(n, seconds: sista)], series: n.series, layers: n.layers)
        XCTAssertNotNil(s)
        XCTAssertNil(s?.snoringPerHour, "en lyssnare som startade sent säger inget om natten")
        XCTAssertLessThan(s?.coverage ?? 1, NightSoundMaker.minCoverage)
        XCTAssertFalse((s?.events ?? []).isEmpty, "händelserna finns ändå")
        XCTAssertEqual(NightSoundMaker.minCoverage, 0.5)
    }

    func testNärDetÄrOtydligtVemsSnarkningenÄrFinnsInteTalet() throws {
        // Utan andning i slagen blir all snarkning okänd: ingen av den är din, men en nolla vore en gissning.
        let n = Self.natt
        var platt: [K18Record] = n.series.records
        for i in platt.indices { platt[i].rr = platt[i].rr.isEmpty ? [] : [1_000] }
        let s = try XCTUnwrap(NightSoundMaker.make(sources: [Self.källa(n)], series: K18Series(records: platt),
                                                   layers: n.layers))
        XCTAssertEqual(s.yoursMinutes, 0, accuracy: 1e-9)
        XCTAssertEqual(s.unknownMinutes, 19, accuracy: 1e-9)
        XCTAssertNil(s.snoringPerHour, "mer än en femtedel av snarkningen har okänd ägare")
        XCTAssertEqual(NightSoundMaker.maxUnknownShare, 0.2)
        XCTAssertTrue(s.events.filter { $0.isSnoring }.allSatisfy { $0.owner == .unknown })
    }

    // MARK: Flera filer

    func testFlerFilerPåEnAxelGerSammaNattOchKlippenPekarPåRätFil() throws {
        let n = Self.natt
        let delning = 3_000
        let a = n.seconds.filter { $0.second < delning + 100 }
        // Den andra filen börjar 100 sekunder före delningen: de sekunderna finns i båda och räknas en gång.
        let b = n.seconds.filter { $0.second >= delning }.map { (s: SoundSecond) -> SoundSecond in
            var x = s
            x.second -= delning
            return x
        }
        let andraStart = n.start + delning
        let s = try XCTUnwrap(NightSoundMaker.make(
            sources: [Self.källa(n, seconds: a), Self.källa(n, seconds: b, start: andraStart)],
            series: n.series, layers: n.layers))
        XCTAssertEqual(s.events.map { $0.time }, ljud.events.map { $0.time }, "samma händelser som i en fil")
        XCTAssertEqual(s.events.map { $0.soundClass }, ljud.events.map { $0.soundClass })
        XCTAssertEqual(s.events.map { $0.woke }, ljud.events.map { $0.woke })
        XCTAssertEqual(try XCTUnwrap(s.snoringPerHour), try XCTUnwrap(ljud.snoringPerHour), accuracy: 1e-9)
        // Trafiken vid 2 400 ligger i första filen, den vid 3 000 och 3 600 i den andra (sekund 0 respektive 600).
        let t = s.events.filter { $0.soundClass == SoundClass.traffic.rawValue }
        XCTAssertEqual(t.map { $0.clip.stem }, [SoundFile.stem(start: n.start), SoundFile.stem(start: andraStart),
                                                SoundFile.stem(start: andraStart)])
        XCTAssertEqual(t.map { $0.clip.second }, [2_400, 0, 600])
    }

    func testIngaFilerEllerTommaFilerGerIngetLjud() {
        let n = Self.natt
        XCTAssertNil(NightSoundMaker.make(sources: [], series: n.series, layers: n.layers))
        XCTAssertNil(NightSoundMaker.make(sources: [Self.källa(n, seconds: [])], series: n.series, layers: n.layers))
    }

    // MARK: Sammanfattningen

    func testSammanfattningenBärDeSomVäckteOchSparasSomJSON() throws {
        let d = ljud.digest
        XCTAssertEqual(d.wakers.count, 2)
        XCTAssertEqual(d.wakers.map { $0.soundClass }, [SoundClass.traffic.rawValue, SoundClass.traffic.rawValue])
        XCTAssertEqual(d.wakers.map { $0.time }, Array(trafik().prefix(2)).map { $0.time })
        XCTAssertTrue(d.wakers.allSatisfy { $0.owner == nil })
        XCTAssertEqual(d.events, 26)
        XCTAssertEqual(d.pulseReactions, 2)
        XCTAssertEqual(d.snoringPerHour, ljud.snoringPerHour)
        XCTAssertEqual(d.yoursMinutes, 9.5, accuracy: 1e-9)
        XCTAssertTrue(d.clockReliable)

        let data = try JSONEncoder().encode(d)
        XCTAssertEqual(try JSONDecoder().decode(NightSoundDigest.self, from: data), d)
        XCTAssertLessThan(data.count, 1_500, "några tal och två tider, inga nivåer per sekund")
    }

    // MARK: Filerna en natt läser

    func testNattenLäserFilernaSomBörjadeIDessFönster() {
        let z = 7_200
        let dag = WakeDay(daysSince1970: 20_740)         // 2026-10-14
        func stam(_ d: Int, _ h: Int, _ m: Int) -> String {
            let lokal = DayLog.date(of: DayLog.Day(daysSince1970: d), hour: h, minute: m, utcOffsetSeconds: z)
            return SoundFile.stem(start: Int(lokal.timeIntervalSince1970))
        }
        let kväll = stam(20_739, 21, 3)                  // 13 okt 21:03 lokal tid
        let sent = stam(20_740, 3, 40)                   // 14 okt 03:40: lyssnaren startades om
        let middag = stam(20_740, 12, 0)                 // klockan 12 är nästa natts fönster
        let nästa = stam(20_740, 22, 0)
        let tidigare = stam(20_738, 22, 0)
        let före = stam(20_739, 11, 59)
        let alla = [nästa, sent, "dygn-2026-10-14", tidigare, kväll, middag, "natt-2026-10-14", före]
        XCTAssertEqual(SoundNights.stems(among: alla, wakeDay: dag, utcOffsetSeconds: z), [kväll, sent])
        XCTAssertEqual(SoundNights.stems(among: alla, wakeDay: dag + 1, utcOffsetSeconds: z), [middag, nästa])
        XCTAssertEqual(SoundNights.stems(among: [], wakeDay: dag, utcOffsetSeconds: z), [])
    }

    // MARK: Sammanfattningen för datorn (METOD M45, BESLUT B55)

    /// Appen skriver `SoundSummary` ur samma `SoundNight` som vyerna räknas från: bredvid den första filen,
    /// och talen är analysens.
    func testAnalysenLämnarSammanfattningenFörExportenTillAppen() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false, stages: true)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let fil = inspelning(n)
        let filer: [String: K18Days.File] = [fil.stem: fil]
        let serie = K18Series(notifications: DemoK18Frames.notifications(n.records))
        let utan = try XCTUnwrap(K18Days.night(wakeDay: dag, includeNext: false, recordingStems: [fil.stem],
                                               fallbackOffsetSeconds: z, load: { filer[$0] }))
        let lager = try XCTUnwrap(utan.layers)
        let plan = DemoSound.plan(layers: lager, series: serie)
        let sekunder = DemoSound.seconds(count: plan.count, plants: plan.plants)
        let stam = SoundFile.stem(start: plan.start)
        let rå = SoundNights.Raw(measures: SoundFile.encode(start: plan.start, seconds: sekunder))
        var sparade: [(String, Data)] = []
        let analys = SoundNights.analyzer(stems: [stam], load: { (s: String) -> SoundNights.Raw? in s == stam ? rå : nil },
                                          saveSummary: { (s: String, d: Data) -> Void in sparade.append((s, d)) })
        let med = try XCTUnwrap(K18Days.night(wakeDay: dag, includeNext: false, recordingStems: [fil.stem],
                                              fallbackOffsetSeconds: z, load: { filer[$0] }, sound: analys))
        let ljud = try XCTUnwrap(med.sound)
        XCTAssertEqual(sparade.count, 1)
        XCTAssertEqual(sparade[0].0, stam, "bredvid .ljud-filen")
        XCTAssertEqual(SoundSummary.fileName(stem: stam), stam + ".sammanfattning.json")
        let s = try XCTUnwrap(SoundSummary.decode(sparade[0].1), "filen går att läsa tillbaka")
        let facit = SoundNight.analyze(sekunder, soundStart: plan.start, series: serie, layers: lager)
        XCTAssertEqual(s, SoundSummary(facit), "samma SoundNight, samma tal")
        XCTAssertEqual(s.overall.awakenings, ljud.events.filter { $0.woke }.count, "uppvaknandena är desamma i vyerna")
        XCTAssertEqual(s.eventsPerClass.reduce(0, +), facit.events.count)

        // Utan saveSummary skrivs inget, och utan ljudfil lämnas ingen sammanfattning.
        XCTAssertNotNil(SoundNights.analyzer(stems: [stam], load: { (_: String) -> SoundNights.Raw? in rå })(dag, serie, med))
        var ingen: [(String, Data)] = []
        let utanFil = SoundNights.analyzer(stems: [stam], load: { (_: String) -> SoundNights.Raw? in nil },
                                           saveSummary: { (s: String, d: Data) -> Void in ingen.append((s, d)) })
        XCTAssertNil(utanFil(dag, serie, med))
        XCTAssertTrue(ingen.isEmpty)
    }

    // MARK: Telefonens väg

    func uppvakningsdag(_ n: DemoK18Nights.Night) -> WakeDay {
        WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
    }

    /// En påhittad K18-natt skriven som en gammal inspelning (sidofil och K18-notiser), som `NattvalVaktTests`.
    func inspelning(_ n: DemoK18Nights.Night) -> K18Days.File {
        let stam = RecordingStem.stem(for: Date(timeIntervalSince1970: Double(n.records[0].time) - 90))
        return K18Days.File(stem: stam, sidecar: RecordingLog.header(utcOffsetSeconds: n.utcOffsetSeconds),
                            frames: DemoK18Frames.log(DemoK18Frames.notifications(n.records)))
    }

    /// Klart när (J3): natten läser sitt ljud när den räknas — `K18Days.night` som `K18Nights.result`, och
    /// `NightLedger.computeDue` som `K18Nights.computeDue` — och sammanfattningen bär det som väckte.
    func testNattenLäserSittLjudNärDenRäknasOchSammanfattningenBärDet() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false, stages: true)
        let z = n.utcOffsetSeconds
        let dag = uppvakningsdag(n)
        let fil = inspelning(n)
        let filer: [String: K18Days.File] = [fil.stem: fil]
        let serie = K18Series(notifications: DemoK18Frames.notifications(n.records))

        // Utan ljud: ingen ljuddel, och inget annat i natten skiljer sig.
        let utan = try XCTUnwrap(K18Days.night(wakeDay: dag, includeNext: false, recordingStems: [fil.stem],
                                               fallbackOffsetSeconds: z, load: { filer[$0] }))
        XCTAssertNil(utan.sound, "en natt utan ljud har inget ljud")
        let lager = try XCTUnwrap(utan.layers)

        let plan = DemoSound.plan(layers: lager, series: serie)
        let sekunder = DemoSound.seconds(count: plan.count, plants: plan.plants)
        let stam = SoundFile.stem(start: plan.start)
        let rå = SoundNights.Raw(measures: SoundFile.encode(start: plan.start, seconds: sekunder))
        let analys = SoundNights.analyzer(stems: [stam, "ljud-2020-01-01T00-00-00Z"],
                                          load: { (s: String) -> SoundNights.Raw? in s == stam ? rå : nil })

        let med = try XCTUnwrap(K18Days.night(wakeDay: dag, includeNext: false, recordingStems: [fil.stem],
                                              fallbackOffsetSeconds: z, load: { filer[$0] }, sound: analys))
        var utanLjud: NightResult = med
        utanLjud.sound = nil
        XCTAssertTrue(utanLjud == utan, "ljudet ändrar inget annat i natten")
        let ljud = try XCTUnwrap(med.sound, "natten fick sitt ljud")
        let trafikklass = SoundClass.traffic.rawValue
        let trafik = try XCTUnwrap(ljud.events.first { $0.soundClass == trafikklass }, "trafiken i planen")
        XCTAssertTrue(trafik.woke, "trafiken ligger strax före nattens vakna stund")
        XCTAssertFalse(trafik.movement)
        XCTAssertEqual(trafik.clip.stem, stam)
        for e in ljud.events { XCTAssertTrue(lager.period.contains(e.time)) }
        XCTAssertTrue(ljud.events.contains { $0.soundClass == SoundClass.door.rawValue })
        XCTAssertTrue(ljud.events.contains { $0.soundClass == SoundClass.speech.rawValue })

        // Ledgern sparar det i sammanfattningen, och sammanfattningen når Över tid.
        let nu = NightLedger.windowEnd(dag, utcOffsetSeconds: z).addingTimeInterval(3 * 3600)
        var sparade: [NightLedger.Entry] = []
        NightLedger.computeDue(dayStems: [], recordingStems: [fil.stem], entries: [:], build: "10", now: nu,
                               utcOffsetSeconds: z, load: { filer[$0] },
                               save: { (e: NightLedger.Entry) -> Void in sparade.append(e) }, sound: analys)
        let digest = try XCTUnwrap(sparade.first { $0.wakeDay == dag }?.digest)
        let sd = try XCTUnwrap(digest.sound, "sammanfattningen bär ljudet")
        XCTAssertTrue(sd.wakers.contains { $0.soundClass == trafikklass }, "trafiken väckte")
        XCTAssertEqual(sd.wakers.count, ljud.digest.wakers.count)
        XCTAssertEqual(digest.idunNight.snoringPerHour, sd.snoringPerHour)
        let data = try JSONEncoder().encode(sparade[0])
        let tillbaka = try JSONDecoder().decode(NightLedger.Entry.self, from: data)
        XCTAssertEqual(tillbaka.digest?.sound, sd, "sparas och läses tillbaka")

        // Utan analys, och i ett nytt bygge utan ljudfilen, har sammanfattningen inget ljud.
        var utanAnalys: [NightLedger.Entry] = []
        NightLedger.computeDue(dayStems: [], recordingStems: [fil.stem], entries: [:], build: "10", now: nu,
                               utcOffsetSeconds: z, load: { filer[$0] },
                               save: { (e: NightLedger.Entry) -> Void in utanAnalys.append(e) })
        XCTAssertNil(utanAnalys.first?.digest?.sound)
        let tom = SoundNights.analyzer(stems: [], load: { (_: String) -> SoundNights.Raw? in nil })
        XCTAssertNil(tom(dag, serie, med), "inga filer, inget ljud")
    }

    func testEnNattUtanLagerKanInteLäsaLjud() throws {
        // En gammal inspelning (2A37) har inga lager: analysen ger inget ljud, hur många filer som än finns.
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let dag = uppvakningsdag(n)
        let serie = K18Series(notifications: DemoK18Frames.notifications(n.records))
        var r = try XCTUnwrap(K18Night.analyze(serie, wakeDay: dag, startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        r.layers = nil
        let stam = SoundFile.stem(start: n.onset - 600)
        let rå = SoundNights.Raw(measures: SoundFile.encode(start: n.onset - 600, seconds: SoundFixtures.quiet(0, 60)))
        let analys = SoundNights.analyzer(stems: [stam], load: { (_: String) -> SoundNights.Raw? in rå })
        XCTAssertNil(analys(dag, serie, r))
    }

    func testEnOläsligFilHoppasÖver() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let dag = uppvakningsdag(n)
        let serie = K18Series(notifications: DemoK18Frames.notifications(n.records))
        let r = try XCTUnwrap(K18Night.analyze(serie, wakeDay: dag, startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        let stam = SoundFile.stem(start: n.onset - 600)
        let skräp = SoundNights.Raw(measures: Data([1, 2, 3]))
        let analys = SoundNights.analyzer(stems: [stam], load: { (_: String) -> SoundNights.Raw? in skräp })
        XCTAssertNil(analys(dag, serie, r), "en fil som inte går att läsa ger inget ljud, inget fel")
    }
}
