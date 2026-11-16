import Foundation
import HeartRate
import Night
import WhoopFrames

/// BESLUT B15 · BESLUT B3
/// Nätterna på telefonen, i appens Application Support/recordings. En natt är
/// tre filer med samma början (`<start>`, telefonens tid i UTC):
///
///     <start>.jsonl          pulsnotiserna, zon, batteri, stopp (RecordingLog)
///     <start>.t2.jsonl       Whoops råa ramar, T2 (RawFrameLog)
///     <start>.summary.json   nattens sammanfattning, räknas om vid nytt bygge
///
/// Lyssnaren (PLAN.md A1, BESLUT B30) skriver i stället en dygnsfil per lokalt
/// datum, `dygn-<yyyy-MM-dd>.jsonl` (zon, märken) och `.t2.jsonl` (Whoops råa
/// notiser). De räknas inte som nätter och syns inte i nattlistan (`stems()`),
/// utan i listan över dygn (`dayStems()`).
///
/// BESLUT B41 · METOD M34. Ett färdigt dygn arkiveras till `dygn-<yyyy-MM-dd>.arkiv`
/// (`DayArchive`, det ljumma lagret) och rådygnet raderas efter 14 dagar, när
/// arkivet är läst tillbaka och täcker det (`DayArchiver`). Rådygnen är
/// undantagna från säkerhetskopian i iCloud (`isExcludedFromBackup`); arkiven
/// och nätternas resultat (`natt-….k18.json`) följer med.
///
/// Ingen fil lämnar telefonen: appen har ingen nätverkskod.
enum NightFiles {
    static let folder: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("recordings", isDirectory: true)

    /// "Fram till första upplåsningen": filerna går att skriva medan telefonen
    /// ligger låst hela natten, men är krypterade efter en omstart tills
    /// telefonen låsts upp en gång.
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    static func stem(for start: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: start).replacingOccurrences(of: ":", with: "-")
    }

    static func pulse(_ stem: String) -> URL { folder.appendingPathComponent(stem + ".jsonl") }
    static func frames(_ stem: String) -> URL { folder.appendingPathComponent(stem + ".t2.jsonl") }
    static func summary(_ stem: String) -> URL { folder.appendingPathComponent(stem + ".summary.json") }
    /// BESLUT B41. Dygnsarkivet.
    static func archive(_ stem: String) -> URL { folder.appendingPathComponent(stem + ".arkiv") }

    static func prepareFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: protection])
    }

    /// Alla filstammar (nätter och dygn), senaste först.
    private static func allStems() -> [String] {
        let namn = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        // Ett dygn kan ha bara `.t2.jsonl` (sidofilen ännu inte skriven) och en
        // natt bara `.jsonl`; båda ger en stam.
        let stammar = namn.compactMap { n -> String? in
            if n.hasSuffix(".arkiv") { return String(n.dropLast(".arkiv".count)) }
            if n.hasSuffix(".t2.jsonl") { return String(n.dropLast(".t2.jsonl".count)) }
            if n.hasSuffix(".jsonl") { return String(n.dropLast(".jsonl".count)) }
            return nil
        }
        return Array(Set(stammar)).sorted(by: >)
    }

    /// Alla nätter (inspelningar och hämtningar), senaste först. Dygnsfilerna är inte med.
    static func stems() -> [String] {
        allStems().filter { !DayLog.isDayStem($0) && FileManager.default.fileExists(atPath: pulse($0).path) }
    }

    /// BESLUT B30. Alla dygnsfiler, senaste först (`dygn-yyyy-MM-dd`).
    static func dayStems() -> [String] {
        allStems().filter { DayLog.isDayStem($0) }
    }

    /// Filens storlek i byte; 0 om den saknas.
    static func fileSize(_ url: URL) -> Int {
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attr?[.size] as? NSNumber)?.intValue ?? 0
    }

    /// Rådygnets filer (sidofilen och notiserna) i byte.
    static func rawSize(_ stem: String) -> Int { fileSize(pulse(stem)) + fileSize(frames(stem)) }

    /// BESLUT B41. Arkivets storlek i byte.
    static func archiveSize(_ stem: String) -> Int { fileSize(archive(stem)) }

    /// Filernas storlek i byte, för listan över dygn: rådygnet och arkivet.
    static func size(_ stem: String) -> Int { rawSize(stem) + archiveSize(stem) }

    /// BESLUT B41. Sätter filen utanför iCloud-säkerhetskopian. Det gäller
    /// rådygnen: de är stora, ligger kvar i 14 dagar och finns sedan i arkivet.
    static func excludeFromBackup(_ url: URL) {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? u.setResourceValues(values)
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        return v?.isExcludedFromBackup ?? false
    }

    /// BESLUT B41. Dygnsarkivet, om det finns och går att läsa.
    static func loadArchive(_ stem: String) -> DayArchive? {
        guard let data = try? Data(contentsOf: archive(stem), options: .mappedIfSafe) else { return nil }
        return try? DayArchive.decode(data)
    }

    /// BESLUT B41 · METOD M34. Dygnets sidofil och notiser: rådygnets filer när
    /// de finns, annars (rådygnet raderat efter 14 dagar) återskapade ur
    /// arkivet (`DayArchive.rawLog`: K18, K26, händelser och synkmärken, en
    /// notis per ram). `nil` när varken rådygn eller arkiv finns.
    static func dayData(_ stem: String) -> (pulse: Data, frames: Data?)? {
        let sida: Data? = try? Data(contentsOf: pulse(stem))
        let ramar: Data? = try? Data(contentsOf: frames(stem), options: .mappedIfSafe)
        if let sida = sida, ramar != nil { return (sida, ramar) }
        let arkiv: DayArchive? = loadArchive(stem)
        if sida == nil && ramar == nil && arkiv == nil { return nil }
        return (sida ?? arkiv?.sidecar ?? Data(), ramar ?? arkiv?.rawLog())
    }

    static func delete(_ stem: String) {
        for url in [pulse(stem), frames(stem), summary(stem), archive(stem)] {
            try? FileManager.default.removeItem(at: url)
        }
        NightExport.remove(stem)
    }

    static func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// En fil som bara växer. Öppnas en gång per natt, och varje rad skrivs
/// direkt, så att en krasch eller en avstängd app förlorar högst en rad.
final class AppendFile {
    private let handle: FileHandle
    private(set) var failures = 0

    init(url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: NightFiles.protection])
        }
        // BESLUT B41. Rådygnen följer inte med iCloud-säkerhetskopian.
        NightFiles.excludeFromBackup(url)
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func append(_ data: Data) {
        do { try handle.write(contentsOf: data) } catch { failures += 1 }
    }

    /// METOD M23. Skriver ned det som står i filen till disken (fsync), före
    /// en kvittens till bandet. `false` om det inte gick.
    func sync() -> Bool {
        do {
            try handle.synchronize()
            return true
        } catch {
            failures += 1
            return false
        }
    }

    func close() {
        try? handle.synchronize()
        try? handle.close()
    }
}

/// BESLUT B3. En natt som listan och morgonen behöver den: bara nattens samlade
/// tal, aldrig en enskild puls eller ett intervall.
struct NightSummary: Codable, Identifiable, Equatable, Sendable {
    var id: String { stem }
    var stem: String
    /// Bygget som räknade. Ett nytt bygge räknar om (räkningen kan ha ändrats).
    var build: String
    var start: Date?
    var end: Date?
    var utcOffsetSeconds: Int
    var samples: Int
    /// METOD M13
    var passes: Bool
    var gapFraction: Double?
    /// METOD M4 · BESLUT B13
    var rmssdMean: Double?
    var rmssdWhoopLike: Double?
    /// METOD M76 · BESLUT B131. Nattens första och andra halva; bara nätter ur K18, och `nil` i äldre sammanfattningar.
    var rmssdEarly: Double?
    var rmssdLate: Double?
    /// METOD M5
    var restingHeartRate: Double?
    /// METOD M10
    var breathsPerMinute: Double?
    var validWindows: Int
    var batteryAtStart: Int?
    var batteryAtEnd: Int?
    /// När inspelningen stoppades. Bär datumet för en hämtning utan puls (BESLUT B25).
    var stopped: Date?
    /// METOD M18. Nattens form, för den typiska natten i andra nätters kurva.
    var profile: NightCurve.Profile?
    /// METOD M22. Pulsen på väggklockan, för nattlandskapet.
    var landscape: NightLandscape.Profile?
    /// METOD M25. Nattens hudtemperatur i °C ur K18 (median över de stilla
    /// minuterna). `nil` när K18 täckte inspelningen för lite, eller saknas.
    var skinTemperature: Double?
    /// METOD M24. Andelen av inspelningens minuter som har K18 (0…1); `nil` för
    /// en summa räknad före K18 fanns eller utan inspelningstid.
    var skinCoverage: Double?
    /// METOD M28 · BESLUT B31. Varifrån slagen kom. `nil` i en sammanfattning
    /// från före A2 och i en gammal inspelning (`origin`).
    var source: NightSource?
    /// A2. Uppvakningsdagen som dagar sedan 1970; sätts för nätter ur K18, där
    /// den är nyckeln. En gammal inspelning räknar den ur sin sista notis.
    var wakeDayNumber: Int?
    /// METOD M26. Idunns sömntid i minuter (sömnperioden utan vakna stunder
    /// och glapp); bara K18-nätter har en.
    var sleepMinutes: Double?
    /// METOD M24. Andelen av sömnperiodens minuter som har K18 (0…1).
    var coverage: Double?
    /// Räknad före klockan 12 på uppvakningsdagen (fönstret fram till nu).
    var preliminary: Bool?
    /// METOD M28. Kontrollen av stämpelns tolkning: antal och andel omlagda
    /// poster, och antal och andel utelämnade slag.
    var reanchorings: Int?
    var fractionReanchored: Double?
    var omittedBeats: Int?
    var fractionOmitted: Double?
    /// METOD M37 · BESLUT B34. Medelpulsen över sömnperioden i slag per minut.
    /// `nil` för en gammal inspelning och i en sammanfattning från före V5.
    var meanHeartRate: Double?
    /// METOD M37 · BESLUT B45. Minuter i lätt, djup och REM sömn (summan är
    /// sömntiden). `nil` utan stadier: en gammal inspelning och före V5.
    var lightMinutes: Double?
    var deepMinutes: Double?
    var remMinutes: Double?
    /// METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden. `nil` för en gammal inspelning, vid för låg
    /// K18-täckning och i en sammanfattning från före bygge 10.
    var movementMinutes: Int?
    /// METOD M44 · BESLUT B54. Nattens ljud i några tal och de händelser som väckte. `nil` för en natt utan ljud,
    /// för en gammal inspelning och i en sammanfattning från före bygge 10.
    var sound: NightSoundDigest?
    /// METOD M50 · METOD M52 · BESLUT B63. Sömneffektivitet i procent, antal vakna stunder, minuter i vaken sömn och
    /// insomning och uppvaknande som minuter efter midnatt på uppvakningsdagen. `nil` för en gammal inspelning och i
    /// en sammanfattning från före D2 (den räknas om vid nytt bygge).
    var efficiency: Double?
    var wakeBouts: Int?
    var awakeMinutes: Double?
    var onsetMinutes: Double?
    var wakeMinutes: Double?
    /// METOD M55 · BESLUT B70. Sant när användaren har ändrat sömnperioden (märket i Natten), och perioden som hittades
    /// ur rörelsen. `nil` för en natt som den hittades, en gammal inspelning och en äldre sammanfattning.
    var edited: Bool?
    var foundStart: Date?
    var foundEnd: Date?
    /// METOD M26 · BESLUT B73. K18 saknas vid sömnblockets början eller slut (`NightDigest.incompleteStart/End`).
    /// Visas i Natten under Sömnperiod (BESLUT B83); `nil` utan sömnperiod och i en äldre sammanfattning.
    var incompleteStart: Bool?
    var incompleteEnd: Bool?

    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// Läser sammanfattningen om den är räknad av det här bygget, annars räknas
    /// den om ur nattens fil och sparas.
    static func load(_ stem: String) -> NightSummary? {
        if let d = try? Data(contentsOf: NightFiles.summary(stem)),
           let s = try? JSONDecoder().decode(NightSummary.self, from: d), s.build == currentBuild {
            return s
        }
        guard let report = NightReport.make(stem: stem) else { return nil }
        let s = NightSummary(report)
        if let d = try? JSONEncoder().encode(s) { NightFiles.write(d, to: NightFiles.summary(stem)) }
        return s
    }

    init(_ r: NightReport) {
        let night = r.contents.recording
        stem = r.stem
        build = Self.currentBuild
        start = night.start
        end = night.end
        utcOffsetSeconds = r.contents.utcOffsetSeconds ?? TimeZone.current.secondsFromGMT()
        samples = night.samples.count
        passes = r.quality.passes
        gapFraction = r.quality.gaps?.fraction
        rmssdMean = r.analysis.rmssd.mean
        rmssdWhoopLike = r.analysis.rmssd.whoopLike
        restingHeartRate = r.analysis.restingHeartRate
        breathsPerMinute = r.analysis.breathsPerMinute
        validWindows = r.analysis.validWindows
        batteryAtStart = night.batteryAtStart
        batteryAtEnd = night.batteryAtEnd
        stopped = r.contents.stopped
        profile = r.curve?.profile
        landscape = r.curve.flatMap { NightLandscape.profile(minutes: $0.minutes, utcOffsetSeconds: utcOffsetSeconds) }
        skinTemperature = r.skin?.celsius
        skinCoverage = r.skin?.coverage
    }

    /// METOD M28 · METOD M26. En natt ur K18 (appens koppling, A2): sammanfattningen
    /// av `NightDigest`, nycklad på uppvakningsdagen (`stem` = `natt-yyyy-MM-dd`).
    /// Insomning och uppvaknande är `start` och `end`.
    init(digest d: NightDigest, stem: String, build: String) {
        self.stem = stem
        self.build = build
        start = d.sleepStart
        end = d.sleepEnd
        utcOffsetSeconds = d.utcOffsetSeconds
        samples = d.pulseSeconds
        passes = (d.coverage ?? 0) >= ListenerCheck.minCoverage
        gapFraction = d.coverage.map { (c: Double) -> Double in 1 - c }
        rmssdMean = d.rmssdMean
        rmssdWhoopLike = d.rmssdWhoopLike
        rmssdEarly = d.rmssdEarly
        rmssdLate = d.rmssdLate
        restingHeartRate = d.restingHeartRate
        breathsPerMinute = d.breathsPerMinute
        validWindows = d.validWindows
        profile = d.profile
        landscape = d.landscape
        skinTemperature = d.skinTemperature
        skinCoverage = d.skinCoverage
        source = d.source
        wakeDayNumber = d.wakeDayNumber
        sleepMinutes = d.sleepMinutes
        coverage = d.coverage
        preliminary = d.preliminary
        reanchorings = d.reanchorings
        fractionReanchored = d.fractionReanchored
        omittedBeats = d.omittedBeats
        fractionOmitted = d.fractionOmitted
        meanHeartRate = d.meanHeartRate
        lightMinutes = d.lightMinutes
        deepMinutes = d.deepMinutes
        remMinutes = d.remMinutes
        movementMinutes = d.movementMinutes
        sound = d.sound
        efficiency = d.efficiency
        wakeBouts = d.wakeBouts
        awakeMinutes = d.awakeMinutes
        onsetMinutes = d.onsetMinutes
        wakeMinutes = d.wakeMinutes
        edited = d.edited
        foundStart = d.foundStart
        foundEnd = d.foundEnd
        incompleteStart = d.incompleteStart
        incompleteEnd = d.incompleteEnd
    }

    /// METOD M55 · BESLUT B70. Är sömnperioden användaren ändring?
    var isEdited: Bool { edited == true }

    /// METOD M55. Går sömnperioden att ändra? Bara en natt ur bandets historik har en period (en gammal inspelning är
    /// hela inspelningen).
    var canEditSleep: Bool { origin == .k18 && wakeDay != nil }

    /// METOD M28. Källan; en gammal inspelning är 2A37.
    var origin: NightSource { source ?? .notification }

    /// METOD M14. Uppvakningsdagen: nyckeln för en K18-natt, annars sista
    /// notisen i zonen natten spelades in i.
    var wakeDay: WakeDay? {
        if let n = wakeDayNumber { return WakeDay(daysSince1970: n) }
        return end.map { WakeDay($0, utcOffsetSeconds: utcOffsetSeconds) }
    }

    /// METOD M16 · METOD M19. Natten som trenderna och morgonkortet ser den.
    var idunNight: Trends.IdunNight? {
        guard let dag = wakeDay else { return nil }
        let timmar: Double? = sleepMinutes.map { (m: Double) -> Double in m / 60 }
        return Trends.IdunNight(day: dag, validWindows: validWindows, rmssd: rmssdMean,
                                restingHeartRate: restingHeartRate, breathsPerMinute: breathsPerMinute,
                                skinTemperature: skinTemperature, rmssdWhoopLike: rmssdWhoopLike,
                                sleepHours: timmar,
                                sleepEpisode: Trends.sleepEpisode(source: origin, start: start, end: end,
                                                                  utcOffsetSeconds: utcOffsetSeconds,
                                                                  sleepMinutes: sleepMinutes, coverage: coverage),
                                meanHeartRate: meanHeartRate, movementMinutes: movementMinutes,
                                snoringPerHour: sound?.snoringPerHour, source: origin, id: id,
                                efficiency: efficiency, wakeBouts: wakeBouts, awakeMinutes: awakeMinutes,
                                lightMinutes: lightMinutes, deepMinutes: deepMinutes, remMinutes: remMinutes,
                                onsetMinutes: onsetMinutes, wakeMinutes: wakeMinutes)
    }

    /// METOD M26. Insomning, uppvaknande och sömntid, för jämförelsen mot
    /// Whoops pass. Bara K18-nätter har en sömnperiod.
    var sleepPeriod: SleepComparison.NightSleep? {
        guard origin == .k18, let a = start, let b = end, let m = sleepMinutes else { return nil }
        return SleepComparison.NightSleep(onset: Int(a.timeIntervalSince1970), wake: Int(b.timeIntervalSince1970),
                                          asleepMinutes: m)
    }

    /// Dagen natten visas under i listor och rubriker.
    var titleDate: Date? { end ?? start ?? stopped }

    /// En natt per uppvakningsdag, K18 före en gammal inspelning (METOD M28),
    /// nätter under minsta antal fönster utsorterade (METOD M14), nyaste först.
    /// Samma val som trenderna och morgonkortet gör (`Trends.idunPerDay`).
    static func preferred(_ alla: [NightSummary]) -> [NightSummary] {
        var perId: [String: NightSummary] = [:]
        for s in alla where perId[s.id] == nil { perId[s.id] = s }
        let nätter: [Trends.IdunNight] = alla.compactMap { (s: NightSummary) -> Trends.IdunNight? in s.idunNight }
        let valda: [Trends.IdunNight] = Array(Trends.idunPerDay(nätter).values)
        let ut: [NightSummary] = valda.compactMap { (n: Trends.IdunNight) -> NightSummary? in perId[n.id] }
        return ut.sorted { (a: NightSummary, b: NightSummary) -> Bool in
            (a.titleDate ?? .distantPast) > (b.titleDate ?? .distantPast)
        }
    }

    /// METOD M18. Natten som den typiska natten ser den.
    var past: NightCurve.Past? {
        end.map { NightCurve.Past(end: $0, validWindows: validWindows, profile: profile) }
    }
}

/// BESLUT B3. Allt rapporten visar för en natt, räknat ur filerna. Bara
/// samlade tal; glappens lägen är tider, inga hälsovärden.
struct NightReport: Sendable {
    var stem: String
    var contents: RecordingLog.Contents
    /// METOD M13
    var quality: RecordingQuality.Report
    /// METOD M15. Hur RR kommer i notiserna; bara andelar och kvoter.
    var diagnostics: RecordingQuality.Diagnostics
    /// METOD M3 · METOD M4 · METOD M5 · METOD M10
    var analysis: NightAnalysis.Report
    /// METOD M18 · BESLUT B19. Nattens kurva; visas i en egen vy, inte i rapporten.
    var curve: NightCurve.Curve?
    /// Glappen som andelar av natten (0…1), för bilden av natten.
    var gaps: [ClosedRange<Double>]
    /// METOD M12 · BESLUT B14. Antal ramar per karakteristik och pakettyp.
    var tally: FrameTally
    /// METOD M25 · METOD M24. Nattens hudtemperatur och K18-täckning.
    var skin: SkinTemperature.Night?

    static func make(stem: String) -> NightReport? {
        guard let data = try? Data(contentsOf: NightFiles.pulse(stem)) else { return nil }
        let frames = (try? Data(contentsOf: NightFiles.frames(stem))).map { RawFrameLog.decode($0).frames } ?? []
        return make(stem: stem, contents: RecordingLog.decode(data), frames: frames)
    }

    /// Rapporten ur en natt som redan är läst (förhandsvisningen, IdunnProv,
    /// räknar sina påhittade nätter samma väg).
    /// `k18` är K18-serien om den redan är byggd (förhandsvisningen); annars
    /// avkodas den ur `frames`.
    static func make(stem: String, contents: RecordingLog.Contents, frames: [RawFrame],
                     k18: K18Series? = nil) -> NightReport {
        let night = contents.recording
        // METOD M3 · METOD M18. Slagen rensas en gång; rapporten och kurvan delar dem.
        let beats = RRCleaning.clean(night)
        let analysis = NightAnalysis.analyze(beats: beats)
        // METOD M25. Hudtemperaturen över inspelningens stilla minuter.
        let serie: K18Series = k18 ?? K18Series(notifications: frames)
        let skin: SkinTemperature.Night? = night.start.flatMap { (a: Date) -> SkinTemperature.Night? in
            night.end.map { (b: Date) -> SkinTemperature.Night in SkinTemperature.night(serie, from: a, to: b) }
        }
        return NightReport(stem: stem, contents: contents,
                           quality: RecordingQuality.report(night),
                           diagnostics: RecordingQuality.diagnostics(night),
                           analysis: analysis,
                           curve: NightCurve.make(night: night, beats: beats, analysis: analysis),
                           gaps: gapPositions(night),
                           tally: FrameTally(frames),
                           skin: skin)
    }

    /// METOD M13. Var glappen ligger: samma regel som `RecordingQuality.gaps`.
    static func gapPositions(_ night: NightRecording) -> [ClosedRange<Double>] {
        let s = night.samples
        guard let first = s.first?.time, night.span > 0 else { return [] }
        var ut: [ClosedRange<Double>] = []
        for (a, b) in zip(s, s.dropFirst()) where b.time.timeIntervalSince(a.time) > RecordingQuality.gapSeconds {
            ut.append(a.time.timeIntervalSince(first) / night.span ... b.time.timeIntervalSince(first) / night.span)
        }
        return ut
    }
}
