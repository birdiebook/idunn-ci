import Foundation
import HeartRate
import WhoopFrames

/// METOD M28 · METOD M26 · METOD M41 · BESLUT B30 · BESLUT B48
/// En natt ur dygnsfilerna: appen läser filerna (det enda som är filarbete)
/// och lämnar innehållet hit, där resten är värden och går att provas på Linux.
///
/// Ett uppvakningsdygns fönster är kl 12–12 (M26). Dygnsfilen heter efter
/// datumet notisen *hördes* (M27), och bandets historik hörs först när Whoop
/// synkar, så fönstret kan ligga i tre filer: dygnet före uppvakningsdagen,
/// uppvakningsdagen och, när natten ska ha satt sig (`NightLedger`), dygnet
/// efter. Notiserna läses strömmande (`K18Collector`) och bara poster med
/// bandets tid i fönstret behålls.
///
/// BESLUT B48. Nätter som spelades in före dygnsfilerna har sin K18 i
/// inspelningens `<start>.t2.jsonl`, och en inspelning som överlappar fönstret
/// läses på samma sätt som ett dygn (samma filformat, samma tidsfilter). En
/// sekund som finns i både en inspelning och ett dygn räknas en gång
/// (`K18Series`).
public enum K18Days {

    /// METOD M41. Hur många timmar före fönstrets början en inspelning kan ha
    /// börjat och ändå ha poster i fönstret. **Antagande**: en natts inspelning
    /// är inte längre än så. Fel åt det långa hållet kostar bara att en fil
    /// läses i onödan (tidsfiltret i `K18Collector` släpper posterna); fel åt det
    /// korta att en natt saknar poster.
    public static let recordingReachHours: Double = 12

    /// En dygnsfil som lästs in: stammen, sidofilen (zon, zonbyten, märken) och
    /// notiserna (`.t2.jsonl`). Filer som saknas är `nil`.
    public struct File: Sendable {
        public var stem: String
        public var sidecar: Data?
        public var frames: Data?
        /// BESLUT B41 · METOD M34. Dygnsarkivet (`DayArchive`), för ett dygn
        /// vars rådygn är raderat. Rådygnet gäller när det finns; arkivet fyller
        /// i det som saknas (notiserna, och sidofilen om den också saknas).
        public var archive: Data?

        public init(stem: String, sidecar: Data?, frames: Data?, archive: Data? = nil) {
            self.stem = stem
            self.sidecar = sidecar
            self.frames = frames
            self.archive = archive
        }
    }

    /// Dygnsfilerna en natt läser, i tidsordning. `includeNext`: dygnet efter
    /// uppvakningsdagen med (för en natt som satt sig, `NightLedger.settleHours`).
    public static func stems(wakeDay: WakeDay, includeNext: Bool) -> [String] {
        let dagar: [Int] = includeNext
            ? [wakeDay.daysSince1970 - 1, wakeDay.daysSince1970, wakeDay.daysSince1970 + 1]
            : [wakeDay.daysSince1970 - 1, wakeDay.daysSince1970]
        return dagar.map { (n: Int) -> String in DayLog.stem(for: DayLog.Day(daysSince1970: n)) }
    }

    /// BESLUT B48 · METOD M41. Uppvakningsdagarna vars fönster (kl 12–12) en
    /// inspelning som började `start` kan ha poster i: fönstret den började i,
    /// och det efter om den började mindre än `recordingReachHours` före sitt
    /// slut (klockan 00–12, en inspelning som löper över middagen). Dagen
    /// räknas på väggklockan i zonen `utcOffsetSeconds` (stammen bär bara UTC).
    public static func wakeDays(ofRecordingStart start: Date, utcOffsetSeconds: Int) -> [WakeDay] {
        let lokal: Int = Int(start.timeIntervalSince1970.rounded(.down)) + utcOffsetSeconds
        let räckvidd: Int = Int(recordingReachHours * 3600)
        // Fönstret för dag n är [n·86400 − 43200, n·86400 + 43200) lokalt; inspelningen
        // hör dit om den började i fönstret eller högst `räckvidd` före dess början.
        let första: Int = Int((Double(lokal - 43_200) / 86_400).rounded(.down)) + 1
        let sista: Int = Int((Double(lokal + 43_200 + räckvidd) / 86_400).rounded(.down))
        guard första <= sista else { return [] }
        return (första...sista).map { (n: Int) -> WakeDay in WakeDay(daysSince1970: n) }
    }

    /// BESLUT B48. Inspelningarna bland `recordingStems` som kan ha poster i
    /// fönstret för `wakeDay`, i den ordning de började. Stammar som inte är
    /// en inspelning (`RecordingStem.start`) räknas inte.
    public static func recordingStems(wakeDay: WakeDay, among recordingStems: [String],
                                      utcOffsetSeconds: Int) -> [String] {
        var med: [(stem: String, start: Date)] = []
        for stem in recordingStems {
            guard let start = RecordingStem.start(ofStem: stem) else { continue }
            if wakeDays(ofRecordingStart: start, utcOffsetSeconds: utcOffsetSeconds).contains(wakeDay) {
                med.append((stem: stem, start: start))
            }
        }
        return med.sorted { (a: (stem: String, start: Date), b: (stem: String, start: Date)) -> Bool in
            (a.start, a.stem) < (b.start, b.stem)
        }.map { (m: (stem: String, start: Date)) -> String in m.stem }
    }

    /// BESLUT B48. Alla filer en natt läser: dygnsfilerna (`stems(wakeDay:includeNext:)`)
    /// och inspelningarna som överlappar fönstret, dygnen först.
    public static func stems(wakeDay: WakeDay, includeNext: Bool, recordingStems: [String],
                             utcOffsetSeconds: Int) -> [String] {
        stems(wakeDay: wakeDay, includeNext: includeNext)
            + Self.recordingStems(wakeDay: wakeDay, among: recordingStems, utcOffsetSeconds: utcOffsetSeconds)
    }

    /// BESLUT B48 · METOD M28. Natten som slutar `wakeDay` ur alla filer som
    /// finns: väljer vilka (dygnen och de överlappande inspelningarna), läser
    /// dem med `load` (appen läser filerna, proven ger dem ur minnet; `nil` =
    /// filen finns inte) och räknar. Det här är vad appen kör för varje natt,
    /// så ett prov av den är ett prov av telefonens väg. `nil` = ingen natt. Med `sound` (METOD M44, BESLUT B54)
    /// läser natten också sitt ljud: analysen får K18-serien och nattens lager och lägger resultatet på
    /// `NightResult.sound`; utan den, eller utan ljud, är `sound` `nil`.
    ///
    /// METOD M55 · BESLUT B70. Med `edit` räknas natten med den givna perioden (`K18Night.analyze(…, edit:)`).
    /// BESLUT B125. Med `now` mäts slutglappet till nu (`SleepDetection.detect`); `nil` = dygnsfönstrets slut.
    public static func night(wakeDay: WakeDay, includeNext: Bool, recordingStems: [String],
                             fallbackOffsetSeconds: Int, load: (String) -> File?,
                             sound: NightSound.Analyzer? = nil, edit: SleepEdit? = nil,
                             now: Date? = nil) -> NightResult? {
        var filer: [File] = []
        for stem in stems(wakeDay: wakeDay, includeNext: includeNext, recordingStems: recordingStems,
                          utcOffsetSeconds: fallbackOffsetSeconds) {
            if let f = load(stem) { filer.append(f) }
        }
        guard !filer.isEmpty else { return nil }
        return compute(wakeDay: wakeDay, files: filer, fallbackOffsetSeconds: fallbackOffsetSeconds, sound: sound,
                       edit: edit, now: now)
    }

    /// Natten som slutar `wakeDay`: zonerna ur sidofilerna (`fallbackOffsetSeconds`,
    /// telefonens zon nu, när de saknas), strömmande läsning av notiserna och
    /// `K18Night.analyze`. `nil` = ingen natt (ingen sömnperiod, BESLUT B31).
    public static func compute(wakeDay: WakeDay, files: [File], fallbackOffsetSeconds: Int,
                               sound: NightSound.Analyzer? = nil, edit: SleepEdit? = nil,
                               now: Date? = nil) -> NightResult? {
        // Ett arkiv som inte går att läsa räknas som en fil som saknas.
        var arkiv: [String: DayArchive] = [:]
        for f in files where f.frames == nil {
            if let a = f.archive, let d = try? DayArchive.decode(a) { arkiv[f.stem] = d }
        }
        var dagar: [(stem: String, contents: RecordingLog.Contents)] = []
        for f in files {
            let ur: Data? = arkiv[f.stem].flatMap { (d: DayArchive) -> Data? in d.sidecar.isEmpty ? nil : d.sidecar }
            guard let side = f.sidecar ?? ur else { continue }
            var innehåll: RecordingLog.Contents = RecordingLog.decode(side)
            // BESLUT B48. Zonen i en inspelnings huvud har ingen tid, och `DayZones` tolkar ett
            // huvud som midnatt på dygnsfilens datum. En inspelning har inget datum i namnet,
            // bara starten: huvudets zon gäller därifrån.
            if let start = RecordingStem.start(ofStem: f.stem), let zon = innehåll.utcOffsetSeconds {
                innehåll.zoneChanges.append(RecordingLog.ZoneChange(time: start, utcOffsetSeconds: zon))
            }
            dagar.append((stem: f.stem, contents: innehåll))
        }
        let zoner = DayZones(days: dagar).windowOffsets(wakeDay: wakeDay, fallback: fallbackOffsetSeconds)
        let fönster = SleepDetection.dayWindow(wakeDay: wakeDay, startOffsetSeconds: zoner.start,
                                               endOffsetSeconds: zoner.end)
        var samlare = K18Collector(from: fönster.from, to: fönster.to)
        for f in files {
            if let ramar = f.frames {
                samlare.read(log: ramar)
            } else if let a = arkiv[f.stem] {
                samlare.read(archive: a)
            }
        }
        let serie: K18Series = samlare.series()
        guard var natt = K18Night.analyze(serie, wakeDay: wakeDay,
                                          startOffsetSeconds: zoner.start, endOffsetSeconds: zoner.end,
                                          edit: edit, now: now) else {
            return nil
        }
        // METOD M44. Ljudet räknas mot samma serie och samma lager som kurvan.
        if let analys = sound { natt.sound = analys(wakeDay, serie, natt) }
        return natt
    }
}
