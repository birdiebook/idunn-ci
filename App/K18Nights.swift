import Foundation
import HeartRate
import Night
import WhoopFrames

/// METOD M28 · BESLUT B28 · BESLUT B30 · BESLUT B31
/// Nätterna ur K18 (PLAN.md A2, appens koppling): filarbetet runt IdunnKits
/// `K18Days` och `NightLedger`. En natt är en uppvakningsdag; den räknas ur
/// dygnsfilerna (kvällen före och dagen själv, och dygnet efter när natten
/// satt sig), och dess samlade tal sparas i `natt-<yyyy-MM-dd>.k18.json` i
/// recordings, bredvid dygnsfilerna. Där ligger också dagar utan natt (ingen
/// sömnperiod, B31), så att de inte räknas om vid varje öppning. Inget av det
/// här lämnar telefonen; mappen speglas inte till Documents.
///
/// BESLUT B48. En natt som spelades in före dygnsfilerna har sin K18 i
/// inspelningens `<start>.t2.jsonl`; inspelningarna läses som dygn när de
/// överlappar nattens fönster.
///
/// Vad som ska räknas, och när, avgör IdunnKit (`NightLedger.computeDue`,
/// provat, och `K18Days.night` som väljer filerna); här läses filerna och
/// svaret sparas. Allt på en bakgrundskö (Recorder).
enum K18Nights {

    /// `natt-2026-10-14` för uppvakningsdagen.
    static func stem(_ day: WakeDay) -> String {
        "natt-" + DayLog.Day(daysSince1970: day.daysSince1970).text
    }

    static func entryURL(_ day: WakeDay) -> URL {
        NightFiles.folder.appendingPathComponent(stem(day) + ".k18.json")
    }

    /// Alla sparade dagar, med och utan natt.
    static func entries() -> [WakeDay: NightLedger.Entry] {
        let namn: [String] = (try? FileManager.default.contentsOfDirectory(atPath: NightFiles.folder.path)) ?? []
        var ut: [WakeDay: NightLedger.Entry] = [:]
        for n in namn where n.hasPrefix("natt-") && n.hasSuffix(".k18.json") {
            let url = NightFiles.folder.appendingPathComponent(n)
            guard let data = try? Data(contentsOf: url),
                  let e = try? JSONDecoder().decode(NightLedger.Entry.self, from: data) else { continue }
            ut[e.wakeDay] = e
        }
        return ut
    }

    /// Nätterna som redan är räknade, som sammanfattningar (också de från ett
    /// äldre bygge: de visas tills de räknats om).
    static func summaries() -> [NightSummary] {
        var ut: [NightSummary] = []
        for (dag, e) in entries() {
            guard let d = e.digest else { continue }
            ut.append(NightSummary(digest: d, stem: stem(dag), build: e.build))
        }
        return ut
    }

    /// Räknar nätterna som `NightLedger` säger är dags, nyaste först. Ger
    /// sant om något sparades. Läser tiotals MB per natt: körs aldrig på huvudkön.
    /// BESLUT B159. `minutes` är minuterna med K18 som telefonen har (`nil`: okänt), `awake` att appen är öppen och
    /// `forced` nätter som räknas om oavsett (Räkna om nätterna på Data).
    static func computeDue(now: Date = Date(), minutes: Set<Int>? = nil, awake: Bool = true,
                           forced: Set<WakeDay> = []) -> Bool {
        let zon: Int = TimeZone.current.secondsFromGMT(for: now)
        var ändrat = false
        NightLedger.computeDue(dayStems: NightFiles.dayStems(), recordingStems: NightFiles.stems(),
                               entries: entries(), build: NightSummary.currentBuild, now: now,
                               utcOffsetSeconds: zon, load: load, save: { (post: NightLedger.Entry) -> Void in
            if let data = try? JSONEncoder().encode(post) {
                NightFiles.write(data, to: entryURL(post.wakeDay))
                ändrat = true
            }
        }, sound: SoundFiles.analyzer(writeSummary: true), edits: SleepEditFile.load(), minutes: minutes,
           awake: awake, forced: forced)
        return ändrat
    }

    /// En fil som IdunnKit ber om, dygn eller inspelning (samma tre filer med
    /// samma namn): sidofilen, notiserna och, när rådygnet är borta, arkivet.
    /// `nil` = ingen av dem finns.
    static func load(_ stem: String) -> K18Days.File? {
        let sida: Data? = try? Data(contentsOf: NightFiles.pulse(stem))
        let ramar: Data? = try? Data(contentsOf: NightFiles.frames(stem), options: .mappedIfSafe)
        // BESLUT B41. Är rådygnet borta (raderat efter 14 dagar) läses arkivet.
        let arkiv: Data? = ramar == nil
            ? (try? Data(contentsOf: NightFiles.archive(stem), options: .mappedIfSafe)) : nil
        if sida == nil && ramar == nil && arkiv == nil { return nil }
        return K18Days.File(stem: stem, sidecar: sida, frames: ramar, archive: arkiv)
    }

    /// Natten för uppvakningsdagen ur dygnsfilerna och de gamla inspelningarna
    /// som överlappar fönstret (BESLUT B48); `nil` = ingen natt.
    /// BESLUT B125. `now` är klockan: slutglappet ("slutet saknas") mäts till nu.
    static func compute(_ day: WakeDay, includeNext: Bool, fallbackOffset: Int, now: Date = Date()) -> NightResult? {
        // METOD M44 · BESLUT B54. Natten läser också sitt ljud, så att kurvan och sammanfattningen delar uträkningen.
        // METOD M55 · BESLUT B70. En ändrad natt räknas med sin givna period, som sammanfattningen.
        K18Days.night(wakeDay: day, includeNext: includeNext, recordingStems: NightFiles.stems(),
                      fallbackOffsetSeconds: fallbackOffset, load: load, sound: SoundFiles.analyzer(),
                      edit: SleepEditFile.load()[day], now: now)
    }

    /// Hela resultatet för en vy (kurvan, Poincarémolnet): räknas om ur
    /// filerna, på samma sätt som nattens sammanfattning, eftersom kurvan och
    /// slagen är för stora att spara.
    static func result(for s: NightSummary, now: Date = Date()) -> NightResult? {
        guard let n = s.wakeDayNumber else { return nil }
        let dag = WakeDay(daysSince1970: n)
        let zon: Int = TimeZone.current.secondsFromGMT(for: now)
        let satt: Bool = NightLedger.isSettled(dag, now: now, utcOffsetSeconds: zon)
        return compute(dag, includeNext: satt, fallbackOffset: zon, now: now)
    }
}

/// METOD M55 · BESLUT B70
/// användaren ändringar av sömnperioden (`SleepEdits`): filen `somn-andringar.json` bredvid nätterna i recordings, med
/// samma skyddsklass. Bara appen skriver den, och "Exportera alla dygn" tar med den. Nätterna räknas om av
/// `K18Nights.computeDue` när en ändring tillkommit, flyttats eller tagits bort (`NightLedger`).
enum SleepEditFile {
    static var url: URL { NightFiles.folder.appendingPathComponent(SleepEdits.fileName) }

    /// Ändringarna; en fil som saknas eller inte går att läsa är inga ändringar.
    static func load(from url: URL = SleepEditFile.url) -> SleepEdits {
        guard let data = try? Data(contentsOf: url), let e = try? SleepEdits.decode(data) else { return SleepEdits() }
        return e
    }

    /// Skriver ändringarna, eller tar bort filen när de är slut.
    static func save(_ edits: SleepEdits, to url: URL = SleepEditFile.url) {
        if edits.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? edits.encoded() else { return }
        try? NightFiles.prepareFolder()
        NightFiles.write(data, to: url)
    }
}

/// Natten som en vy behöver den: ur dygnsfilerna för en natt ur K18, och ur
/// inspelningen för en gammal (`NightReport`, som förut).
enum NightLoader {
    /// METOD M32. Kurvan och, för en natt ur K18, lagren på dess tidsaxel
    /// (rörelse, hudtemperatur, glapp med orsak, sömnperiod). En gammal
    /// inspelning har inga lager och ritas som förut.
    struct CurveBundle: Sendable {
        var curve: NightCurve.Curve
        var layers: NightLayers.Layers?
        /// METOD M44 · BESLUT B54. Nattens ljud; `nil` för en natt utan ljud och för en gammal inspelning.
        var sound: NightSound? = nil
    }

    static func bundle(for s: NightSummary) -> CurveBundle? {
        if s.origin == .k18 {
            guard let r = K18Nights.result(for: s), let c = r.curve else { return nil }
            return CurveBundle(curve: c, layers: r.layers, sound: r.sound)
        }
        guard let c = NightReport.make(stem: s.stem)?.curve else { return nil }
        return CurveBundle(curve: c, layers: nil)
    }

    /// BESLUT B52. Nyckeln för den delade uträkningen: hela sammanfattningen (en natt som räknats om är en
    /// annan), och om natten hunnit sätta sig (`K18Nights.result` läser dygnet efter först då).
    private struct Delad: Equatable {
        var summary: NightSummary
        var satt: Bool
    }

    /// BESLUT B52. Den senast begärda nattens uträkning. Bara en natt hålls kvar.
    @MainActor private static var delad: (nyckel: Delad, uträkning: Task<CurveBundle?, Never>)?

    /// BESLUT B52. `bundle(for:)` på en bakgrundskö, delad mellan Morgons kontroll (E3) och Nattens kurva:
    /// den som frågar efter samma natt medan den räknas väntar på samma uträkning i stället för att räkna
    /// natten en gång till, och den som frågar efteråt får svaret direkt.
    @MainActor
    static func sharedBundle(for s: NightSummary, priority: TaskPriority) async -> CurveBundle? {
        let nu = Date()
        var satt = false
        if s.origin == .k18, let dag = s.wakeDay {
            satt = NightLedger.isSettled(dag, now: nu, utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: nu))
        }
        let nyckel = Delad(summary: s, satt: satt)
        if let d = delad, d.nyckel == nyckel { return await d.uträkning.value }
        let uträkning = Task.detached(priority: priority) { () -> CurveBundle? in NightLoader.bundle(for: s) }
        delad = (nyckel: nyckel, uträkning: uträkning)
        return await uträkning.value
    }

    static func poincare(for s: NightSummary) -> PoincareModel? {
        if s.origin == .k18 {
            return K18Nights.result(for: s).flatMap { (r: NightResult) -> PoincareModel? in PoincareModel.make(result: r) }
        }
        return PoincareModel.make(stem: s.stem)
    }
}
