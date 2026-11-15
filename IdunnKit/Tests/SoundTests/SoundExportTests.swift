import Foundation
import XCTest
import HeartRate
@testable import Sound
@testable import WhoopFrames

// METOD M45 · BESLUT B55. Ljudet i exporten: vilka filer som följer med ett
// tidsspann, att klippen bara följer med när de väljs, och att de gamla
// filerna i zip-filen är orörda. PÅHITTADE filer i en tillfällig mapp;
// klippen är påhittade byte, ingen röst.

final class SoundExportTests: XCTestCase {

    // 2026-10-14 21:03:00 UTC; nästa natt tre dygn senare.
    let nightA = 1_792_011_780
    var nightB: Int { nightA + 3 * 86_400 }

    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("idunn-ljudexport-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Skriver en natts filer som lyssnaren gör: måtten, märkena, valfritt
    /// sammanfattningen och två klipp (id = händelsens första sekund).
    @discardableResult
    func write(night start: Int, seconds: Int = 600, summary: Bool = true, clipIds: [Int] = [12, 300]) throws -> String {
        let fm = FileManager.default
        let stem = SoundFile.stem(start: start)
        let measure = root.appendingPathComponent("ljud", isDirectory: true)
        try fm.createDirectory(at: measure, withIntermediateDirectories: true)
        try SoundFile.encode(start: start, seconds: SoundFixtures.quiet(0, seconds))
            .write(to: measure.appendingPathComponent(stem + ".ljud"))
        try SoundMark(time: start, kind: .started).line().write(to: measure.appendingPathComponent(stem + ".markningar"))
        if summary {
            try SoundSummary(SoundFixtures.summary).encoded()
                .write(to: measure.appendingPathComponent(SoundSummary.fileName(stem: stem)))
        }
        let clips = root.appendingPathComponent("ljudklipp", isDirectory: true)
            .appendingPathComponent(stem, isDirectory: true)
        try fm.createDirectory(at: clips, withIntermediateDirectories: true)
        for id in clipIds {
            try Data("klipp \(id) i \(stem)".utf8).write(to: clips.appendingPathComponent(String(format: "%05d.m4a", id)))
        }
        return stem
    }

    func date(_ t: Int) -> Date { Date(timeIntervalSince1970: Double(t)) }

    func names(_ c: SoundExport.Collected) -> [String] {
        c.entries.map { (e: ZipArchive.Entry) -> String in e.name }
    }

    // MARK: Namn och tid

    func testStammenGårFramOchTillbaka() {
        let stem = SoundFile.stem(start: nightA)
        XCTAssertEqual(stem, "ljud-2026-10-14T21-03-00Z")
        XCTAssertEqual(SoundExport.startOfStem(stem), nightA)
        XCTAssertEqual(SoundExport.utcStart(ofIsoStem: "2026-10-12T20-00-00Z"), 1_791_835_200)
        XCTAssertEqual(SoundExport.utcStart(ofIsoStem: "2026-10-13T22-00-00Z"), 1_791_928_800)
        XCTAssertNil(SoundExport.startOfStem("natt-2026-10-14"))
        XCTAssertNil(SoundExport.startOfStem("ljud-2026-13-14T21-03-00Z"))
        XCTAssertNil(SoundExport.utcStart(ofIsoStem: "dygn-2026-10-14"))
    }

    func testFilensSpannUrHuvudetOchSistaPosten() {
        // Glapp i mitten: sista postens sekund är 59, inte antalet poster.
        var secs = SoundFixtures.quiet(0, 10)
        secs.append(contentsOf: SoundFixtures.quiet(50, 10))
        let file = SoundFile.encode(start: nightA, seconds: secs)
        XCTAssertEqual(SoundExport.span(of: file), nightA...(nightA + 59))
        // En halv post sist räknas inte.
        var cut = file
        cut.append(Data(repeating: 7, count: 20))
        XCTAssertEqual(SoundExport.span(of: cut), nightA...(nightA + 59))
        // Bara huvudet: en enda tidpunkt.
        XCTAssertEqual(SoundExport.span(of: SoundFile.header(start: nightA)), nightA...nightA)
        // Inte en ljudfil.
        XCTAssertNil(SoundExport.span(of: Data("inte en ljudfil alls, bara text".utf8)))
        XCTAssertNil(SoundExport.span(of: Data()))
    }

    func testTidsspannetFörEttDygnOchEnInspelning() {
        // Ett dygn är det lokala datumet i telefonens zon (här +2 h).
        let day = SoundExport.exportSpan(stem: "dygn-2026-10-14", pulse: Data(), utcOffsetSeconds: 7_200)
        let midnight = SoundExport.utcStart(ofIsoStem: "2026-10-13T22-00-00Z")!
        XCTAssertEqual(day?.from, date(midnight))
        XCTAssertEqual(day?.to, date(midnight + 86_400))

        // En inspelning går från sin start till stoppet.
        var pulse = RecordingLog.header(utcOffsetSeconds: 7_200)
        let t0 = SoundExport.utcStart(ofIsoStem: "2026-10-14T20-00-00Z")!
        pulse.append(RecordingLog.stopped(at: date(t0 + 9 * 3_600)))
        let night = SoundExport.exportSpan(stem: "2026-10-14T20-00-00Z", pulse: pulse, utcOffsetSeconds: 7_200)
        XCTAssertEqual(night?.from, date(t0))
        XCTAssertEqual(night?.to, date(t0 + 9 * 3_600))

        // Utan stopp eller puls antas en natt vara 14 timmar.
        let open = SoundExport.exportSpan(stem: "2026-10-14T20-00-00Z", pulse: Data(), utcOffsetSeconds: 7_200)
        XCTAssertEqual(open?.to, date(t0 + 14 * 3_600))
        XCTAssertNil(SoundExport.exportSpan(stem: "natt-2026-10-14", pulse: Data(), utcOffsetSeconds: 0))
    }

    // MARK: Urvalet

    func testMåttenMärkenaOchSammanfattningenFölјerMedUtanKlipp() throws {
        let stem = try write(night: nightA)
        let c = SoundExport.collect(root: root, from: date(nightA - 3_600), to: date(nightA + 8 * 3_600),
                                    withClips: false)
        XCTAssertEqual(names(c), ["ljud/\(stem).ljud", "ljud/\(stem).markningar", "ljud/\(stem).sammanfattning.json"])
        XCTAssertEqual(c.nights, 1)
        XCTAssertEqual(c.clips, 0)
        let klippNamn: [String] = names(c).filter { (n: String) -> Bool in n.contains("ljudklipp") || n.hasSuffix(".m4a") }
        XCTAssertEqual(klippNamn, [], "inga klipp utan det uttryckliga valet")
        // Filens byte är de som skrevs.
        let onDisk = try Data(contentsOf: root.appendingPathComponent("ljud/\(stem).ljud"))
        XCTAssertEqual(c.entries[0].data, onDisk)
    }

    func testKlippenFölјerBaraMedValet() throws {
        let stem = try write(night: nightA, clipIds: [12, 300, 5_000])
        // Intervallet täcker de två första klippen men inte det sista (sekund 5 000 efter start).
        let to = date(nightA + 1_000)
        let med = SoundExport.collect(root: root, from: date(nightA - 60), to: to, withClips: true)
        XCTAssertEqual(med.clips, 2)
        XCTAssertEqual(names(med).filter { (n: String) -> Bool in n.hasSuffix(".m4a") },
                       ["ljudklipp/\(stem)/00012.m4a", "ljudklipp/\(stem)/00300.m4a"])
        let klipp = med.entries.first { (e: ZipArchive.Entry) -> Bool in e.name.hasSuffix("00012.m4a") }
        XCTAssertEqual(klipp?.data, Data("klipp 12 i \(stem)".utf8))
        let utan = SoundExport.collect(root: root, from: date(nightA - 60), to: to, withClips: false)
        XCTAssertEqual(utan.clips, 0)
        XCTAssertEqual(names(utan).count, 3)
    }

    func testBaraFilerSomÖverlapparTidsspannetFölјerMed() throws {
        let a = try write(night: nightA)
        let b = try write(night: nightB)
        let bara = { (from: Int, to: Int) -> [String] in
            SoundExport.collect(root: self.root, from: self.date(from), to: self.date(to), withClips: false)
                .entries.map { (e: ZipArchive.Entry) -> String in e.name }
                .filter { (n: String) -> Bool in n.hasSuffix(".ljud") }
        }
        XCTAssertEqual(bara(nightA, nightA + 60), ["ljud/\(a).ljud"])
        XCTAssertEqual(bara(nightB - 60, nightB + 60), ["ljud/\(b).ljud"])
        XCTAssertEqual(bara(nightA, nightB + 60), ["ljud/\(a).ljud", "ljud/\(b).ljud"])
        // Före och efter alla nätter.
        XCTAssertEqual(bara(nightA - 30 * 86_400, nightA - 20 * 86_400), [])
        XCTAssertEqual(bara(nightB + 5 * 86_400, nightB + 6 * 86_400), [])
        // Filen slutar 599 s efter starten: ett intervall som börjar sedan nås inte.
        XCTAssertEqual(bara(nightA + 700, nightA + 800), [])
        XCTAssertEqual(bara(nightA + 599, nightA + 800), ["ljud/\(a).ljud"])
    }

    func testEnNattSomSlutarNästaDagNåsAvDetDygnet() throws {
        // Natten startar 22:03 lokal tid (+2 h) och går sex timmar, över midnatt.
        let start = SoundExport.utcStart(ofIsoStem: "2026-10-14T20-03-00Z")!
        let stem = try write(night: start, seconds: 6 * 3_600)
        for day in ["dygn-2026-10-14", "dygn-2026-10-15"] {
            let span = try XCTUnwrap(SoundExport.exportSpan(stem: day, pulse: Data(), utcOffsetSeconds: 7_200))
            let c = SoundExport.collect(root: root, from: span.from, to: span.to, withClips: false)
            XCTAssertEqual(c.nights, 1, day)
            XCTAssertTrue(names(c).contains("ljud/\(stem).ljud"))
        }
        let other = try XCTUnwrap(SoundExport.exportSpan(stem: "dygn-2026-10-17", pulse: Data(), utcOffsetSeconds: 7_200))
        XCTAssertEqual(SoundExport.collect(root: root, from: other.from, to: other.to, withClips: false).nights, 0)
    }

    func testSammanfattningenSaknasOmDenInteFinns() throws {
        let stem = try write(night: nightA, summary: false)
        let c = SoundExport.collect(root: root, from: date(nightA), to: date(nightA + 100), withClips: false)
        XCTAssertEqual(names(c), ["ljud/\(stem).ljud", "ljud/\(stem).markningar"])
    }

    func testIngenLjudmappGerIngenting() {
        let c = SoundExport.collect(root: root, from: date(0), to: date(nightB), withClips: true)
        XCTAssertTrue(c.entries.isEmpty)
        XCTAssertEqual(c.nights, 0)
    }

    func testEnFilUtanLäsbartHuvudGårEfterNamnet() throws {
        let fm = FileManager.default
        let folder = root.appendingPathComponent("ljud", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = SoundFile.stem(start: nightA)
        try Data("trasig".utf8).write(to: folder.appendingPathComponent(stem + ".ljud"))
        try Data("ingen tid i namnet".utf8).write(to: folder.appendingPathComponent("ljud-x.ljud"))
        let c = SoundExport.collect(root: root, from: date(nightA - 10), to: date(nightA + 10), withClips: false)
        XCTAssertEqual(names(c), ["ljud/\(stem).ljud"], "namnet säger tiden; en fil utan tid i namn och huvud hoppas över")
    }

    func testFilnamnetMedKlippSkiljsFrånDetUtan() {
        XCTAssertEqual(SoundExport.clipFileName("idunn-2026-10-14T20-00-00Z.zip"),
                       "idunn-2026-10-14T20-00-00Z-ljudklipp.zip")
        XCTAssertEqual(SoundExport.clipFileName("x"), "x-ljudklipp")
    }

    // MARK: Zip-filen

    /// Läser en zip ur katalogen i slutet (så att katalogens avstånd prövas),
    /// med lagrade filer (metod 0).
    func read(_ zip: Data) -> [String: Data] {
        let b = [UInt8](zip)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let n = b.count
        XCTAssertEqual(u32(n - 22), 0x0605_4B50, "slutposten")
        var pos = u32(n - 6)
        var out: [String: Data] = [:]
        for _ in 0..<u16(n - 12) {
            XCTAssertEqual(u32(pos), 0x0201_4B50, "katalogpost")
            XCTAssertEqual(u16(pos + 10), 0, "lagrad")
            let size = u32(pos + 24)
            let nameLength = u16(pos + 28)
            let local = u32(pos + 42)
            let name = String(decoding: b[(pos + 46)..<(pos + 46 + nameLength)], as: UTF8.self)
            XCTAssertEqual(u32(local), 0x0403_4B50, "lokalt huvud för \(name)")
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            let data = Data(b[start..<(start + size)])
            XCTAssertEqual(FrameAssembly.crc32(data), UInt32(u32(pos + 16)), "summan för \(name)")
            out[name] = data
            pos += 46 + nameLength + u16(pos + 30) + u16(pos + 32)
        }
        return out
    }

    func testZipenFårLjudetEfterDeFilerSomFanns() throws {
        let stem = try write(night: nightA)
        let a = Data("{\"zon\":7200}\n".utf8)
        let c = Data((0..<1_000).map { UInt8($0 % 251) })
        let base = ZipArchive.make([.init(name: "natt.jsonl", data: a), .init(name: "natt.t2.jsonl", data: c)],
                                   date: date(nightA), compress: false)
        let both = try XCTUnwrap(SoundExport.extend(base, root: root, from: date(nightA - 60), to: date(nightA + 1_000),
                                                    withClips: true, date: date(nightA), compress: false))
        let files = read(both)
        XCTAssertEqual(Set(files.keys), ["natt.jsonl", "natt.t2.jsonl", "ljud/\(stem).ljud", "ljud/\(stem).markningar",
                                         "ljud/\(stem).sammanfattning.json", "ljudklipp/\(stem)/00012.m4a",
                                         "ljudklipp/\(stem)/00300.m4a"])
        XCTAssertEqual(files["natt.jsonl"], a, "de gamla filerna är orörda")
        XCTAssertEqual(files["natt.t2.jsonl"], c)
        XCTAssertEqual(files["ljud/\(stem).ljud"],
                       try Data(contentsOf: root.appendingPathComponent("ljud/\(stem).ljud")))
        XCTAssertEqual(files["ljudklipp/\(stem)/00300.m4a"], Data("klipp 300 i \(stem)".utf8))

        // Utan klipp: samma zip minus klippen, och inte en klippfil i den.
        let utan = try XCTUnwrap(SoundExport.extend(base, root: root, from: date(nightA - 60), to: date(nightA + 1_000),
                                                    withClips: false, date: date(nightA), compress: false))
        XCTAssertEqual(Set(read(utan).keys), ["natt.jsonl", "natt.t2.jsonl", "ljud/\(stem).ljud",
                                              "ljud/\(stem).markningar", "ljud/\(stem).sammanfattning.json"])
        XCTAssertFalse(String(decoding: utan, as: UTF8.self).contains("klipp 12"), "inga klippbyte utan valet")
    }

    func testEnZipUtanLjudBlirOförändrad() {
        let base = ZipArchive.make([.init(name: "natt.jsonl", data: Data("x".utf8))], date: date(nightA), compress: false)
        let same = SoundExport.extend(base, root: root, from: date(nightA), to: date(nightA + 10), withClips: true)
        XCTAssertEqual(same, base)
    }

    func testEnZipSomInteÄrEnZipGerNil() {
        let entry = ZipArchive.Entry(name: "a", data: Data("x".utf8))
        XCTAssertNil(ZipAppend.append([entry], to: Data("det här är ingen zip".utf8)))
        XCTAssertNil(ZipAppend.append([entry], to: Data()))
        // Slutposten med en kommentar förstås inte.
        var withComment = ZipArchive.make([], compress: false)
        withComment.append(Data("kommentar".utf8))
        XCTAssertNil(ZipAppend.append([entry], to: withComment))
    }

    func testFlerAvbyggdaAvZipenGerSammaFiler() throws {
        // Lägger man till i två steg blir det samma filer som i ett.
        let base = ZipArchive.make([.init(name: "a", data: Data("1".utf8))], date: date(nightA), compress: false)
        let one = try XCTUnwrap(ZipAppend.append([.init(name: "b", data: Data("2".utf8))], to: base,
                                                 date: date(nightA), compress: false))
        let two = try XCTUnwrap(ZipAppend.append([.init(name: "c/d", data: Data("3".utf8))], to: one,
                                                 date: date(nightA), compress: false))
        XCTAssertEqual(read(two), ["a": Data("1".utf8), "b": Data("2".utf8), "c/d": Data("3".utf8)])
    }

    // MARK: Sammanfattningen

    func testSammanfattningenGårFramOchTillbakaOchBärDemonattensTal() throws {
        let n = SoundFixtures.summary
        let s = SoundSummary(n)
        XCTAssertEqual(SoundSummary.decode(s.encoded()), s)
        XCTAssertEqual(s.eventsPerClass, n.eventsPerClass)
        XCTAssertEqual(s.eventsPerClass.count, SoundClasses.count)
        XCTAssertEqual(s.overall.awakenings, n.response.overall.awakenings)
        XCTAssertEqual(s.overall.controls, n.response.overall.controls)
        XCTAssertEqual(s.perClass.count, 12)
        XCTAssertEqual(s.perStep.count, 3)
        XCTAssertEqual(s.clockOffsetSeconds, n.clock.offset)
        XCTAssertEqual(s.clockReliable, n.clock.isReliable)
        XCTAssertEqual(s.snoreYoursMinutes, n.snore.yours)
        XCTAssertEqual(s.gaps.count, n.gaps.count)
        XCTAssertNil(SoundSummary.decode(Data("inte json".utf8)))
        XCTAssertNil(SoundSummary.decode(Data("{}".utf8)))
    }

    /// Nycklarna står också i `tools/tests/test_ljud_analys.py` (NYCKLAR): ändras
    /// ena listan utan den andra faller ett av proven.
    func testNycklarnaÄrDeSammaSomIPython() throws {
        let json = try JSONSerialization.jsonObject(with: SoundSummary(SoundFixtures.summary).encoded())
        let top = try XCTUnwrap(json as? [String: Any])
        // `unknownShare` och `snoringPerHourAsleep` utelämnas när de är `nil`.
        let required: Set<String> = ["version", "secondsMeasured", "snoreYoursMinutes", "snoreSomeoneElseMinutes",
                                     "snoreUnknownMinutes", "speechEpisodes", "eventsPerClass",
                                     "clockOffsetSeconds", "clockReliable", "overall", "perClass", "perStep", "gaps"]
        let optional: Set<String> = ["unknownShare", "snoringPerHourAsleep"]
        let keys = Set(top.keys)
        XCTAssertTrue(required.isSubset(of: keys), "saknas: \(required.subtracting(keys))")
        XCTAssertTrue(keys.isSubset(of: required.union(optional)), "extra: \(keys.subtracting(required.union(optional)))")
        let rate = try XCTUnwrap(top["overall"] as? [String: Any])
        XCTAssertEqual(Set(rate.keys), ["events", "awakenings", "pulseReactions", "controls", "controlAwakenings",
                                        "controlPulseReactions"])
    }

    func testSammanfattningenBärInteEnEnskildTid() throws {
        // Dataregeln: tal och andelar, ingen klocktid. Inget fält heter start/time/at och inget är en Unix-tid.
        let data = SoundSummary(SoundFixtures.summary).encoded()
        let text = String(decoding: data, as: UTF8.self)
        for word in ["\"start\"", "\"time\"", "\"at\"", "\"end\""] {
            XCTAssertFalse(text.contains(word), word)
        }
        func numbers(_ any: Any) -> [Double] {
            if let d = any as? [String: Any] { return d.values.flatMap { (v: Any) -> [Double] in numbers(v) } }
            if let a = any as? [Any] { return a.flatMap { (v: Any) -> [Double] in numbers(v) } }
            if let n = any as? NSNumber { return [n.doubleValue] }
            return []
        }
        let all: [Double] = numbers(try JSONSerialization.jsonObject(with: data))
        XCTAssertFalse(all.isEmpty)
        XCTAssertLessThan(all.map { (x: Double) -> Double in abs(x) }.max() ?? 0, 1_000_000_000,
                          "ingen Unix-tid: ett tal så stort som en klocktid fanns")
    }
}
