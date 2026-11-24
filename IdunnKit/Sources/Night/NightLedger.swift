import Foundation
import WhoopFrames

/// METOD M28 · BESLUT B28 · BESLUT B48
/// Vilka nätter ur K18 som ska räknas (om), och vad som sparas om dem. En natt
/// räknas per uppvakningsdag ur dygnsfilerna (`K18Days`); att räkna kostar
/// att läsa två eller tre dygnsfiler på tiotals MB, så det görs bara när det
/// behövs:
///
/// - **Ingen natt sparad** för en dag som har dygnsfiler, eller en gammal
///   inspelning som började i dess fönster (B48): räkna.
/// - **Nytt bygge:** räkningen kan ha ändrats, räkna om (som `NightSummary.load`).
/// - **Ny data** (BESLUT B159, METOD M87): telefonen har fler minuter med K18 i nattens fönster än natten räknades
///   på. Då räknas den om, oavsett vem som hämtade datan eller hur sent den kom.
/// - **Pågående natt** (före klockan 12 på uppvakningsdagen): räknas fram till
///   nu och märks preliminär, men bara medan appen är öppen (`awake`), och utan ny data högst var
///   `preliminaryMinutes` minut. I bakgrunden väntar den till appen öppnas eller fönstret stänger.
/// - **Färdig natt** som räknades preliminär: räknas om när fönstret passerats.
/// - **Satt natt:** Whoop-appen kan synka en natt först timmar efter att den
///   mättes, och posten hamnar då i en senare dygnsfil. En natt räknas därför
///   en gång till `settleHours` timmar efter fönstrets slut, med dygnet efter
///   med.
///
/// - **Ändrad natt** (METOD M55, BESLUT B70): användaren har ändrat sömnperioden,
///   eller återställt den, sedan natten räknades. Posten bär ändringen den
///   räknades med, så en ny eller borttagen ändring räknar om natten direkt.
///
/// En dag utan sömnperiod sparas också (utan natt), annars räknades den om
/// vid varje öppning.
public enum NightLedger {

    /// En pågående natt räknas inte om oftare än så här. **Antagande**: en
    /// halvtimme är tätt nog för en morgon man tittar på, och glest nog att
    /// inte läsa tiotals MB i onödan.
    public static let preliminaryMinutes: Double = 30

    /// Timmar efter fönstrets slut då en natt anses ha satt sig. **Antagande**
    /// (hur sent Whoops synk kommer är inte mätt): ett dygn.
    public static let settleHours: Double = 24

    /// Det som sparas för en dag.
    public struct Entry: Codable, Equatable, Sendable {
        public var build: String
        public var wakeDayNumber: Int
        public var computedAt: Date
        /// Räknad före fönstrets slut.
        public var preliminary: Bool
        /// Räknad efter att natten satt sig (`settleHours`).
        public var settled: Bool
        /// `nil`: dagen hade ingen sömnperiod, alltså ingen natt (BESLUT B31).
        public var digest: NightDigest?
        /// METOD M55 · BESLUT B70. Ändringen natten räknades med (`nil`: ingen). Äldre poster saknar fältet.
        public var edit: SleepEdit?
        /// BESLUT B159. Minuterna med K18 i fönstret som telefonen hade när natten räknades (`coveredMinutes`); `nil`:
        /// okänt (äldre poster, eller statusen var inte läst).
        public var coverage: Int?

        public init(build: String, wakeDay: WakeDay, computedAt: Date, preliminary: Bool, settled: Bool,
                    digest: NightDigest?, edit: SleepEdit? = nil, coverage: Int? = nil) {
            self.build = build
            self.wakeDayNumber = wakeDay.daysSince1970
            self.computedAt = computedAt
            self.preliminary = preliminary
            self.settled = settled
            self.digest = digest
            self.edit = edit
            self.coverage = coverage
        }

        public var wakeDay: WakeDay { WakeDay(daysSince1970: wakeDayNumber) }
    }

    /// En natt att räkna.
    public struct Job: Equatable, Sendable {
        public var wakeDay: WakeDay
        public var preliminary: Bool
        public var settled: Bool
    }

    /// Fönstrets slut: kl 12 på uppvakningsdagen i zonen `utcOffsetSeconds`.
    public static func windowEnd(_ wakeDay: WakeDay, utcOffsetSeconds: Int) -> Date {
        Date(timeIntervalSince1970: Double(wakeDay.daysSince1970 * 86_400 + 43_200 - utcOffsetSeconds))
    }

    /// BESLUT B159 · METOD M87. Minuterna i nattens fönster (kl 18 kvällen före till kl 12, `NightWindow`) som har K18
    /// i `minutes` (unix-minuter, `ListenerStatus.k18Minutes`).
    public static func coveredMinutes(_ wakeDay: WakeDay, minutes: Set<Int>, utcOffsetSeconds: Int) -> Int {
        let slut = Int(windowEnd(wakeDay, utcOffsetSeconds: utcOffsetSeconds).timeIntervalSince1970) / 60
        let längd = (24 - NightWindow.eveningHour + NightWindow.morningHour) * 60
        return (slut - längd..<slut).reduce(0) { (n: Int, m: Int) -> Int in minutes.contains(m) ? n + 1 : n }
    }

    /// Har natten satt sig, `settleHours` efter fönstrets slut?
    public static func isSettled(_ wakeDay: WakeDay, now: Date, utcOffsetSeconds: Int) -> Bool {
        now >= windowEnd(wakeDay, utcOffsetSeconds: utcOffsetSeconds).addingTimeInterval(settleHours * 3600)
    }

    /// Uppvakningsdagarna som kan ha en natt ur dygnsfilerna: en dag har en
    /// natt om dygnet före eller dygnet självt finns, och ingen i framtiden.
    ///
    /// BESLUT B48. Och ur gamla inspelningar (`recordingStems`): en dag har en
    /// natt om en inspelning började i dess fönster kl 12–12 (`K18Days.wakeDays`).
    /// Dagen räknas på väggklockan i zonen `utcOffsetSeconds`.
    public static func candidates(dayStems: [String], recordingStems: [String] = [], utcOffsetSeconds: Int = 0,
                                  today: WakeDay) -> [WakeDay] {
        var dagar: Set<WakeDay> = []
        for stem in dayStems {
            guard let dag = DayLog.day(ofStem: stem) else { continue }
            let w = WakeDay(daysSince1970: dag.daysSince1970)
            dagar.insert(w)
            dagar.insert(w + 1)
        }
        for stem in recordingStems {
            guard let start = RecordingStem.start(ofStem: stem) else { continue }
            for w in K18Days.wakeDays(ofRecordingStart: start, utcOffsetSeconds: utcOffsetSeconds) { dagar.insert(w) }
        }
        return dagar.filter { (w: WakeDay) -> Bool in w <= today }.sorted(by: >)
    }

    /// Nätterna som ska räknas nu, de nyaste först. Ett nytt bygge (`build`)
    /// räknar om varje natt, också de som sparats som dagar utan natt: det är
    /// så en natt ur en gammal inspelning (`recordingStems`, BESLUT B48) hittas
    /// för en dag som tidigare räknades utan den. En dag vars ändring (`edits`, METOD M55) inte är den posten
    /// räknades med räknas om, oavsett klockan.
    ///
    /// BESLUT B159 · METOD M87. `minutes` är minuterna med K18 som telefonen har nu (`nil`: okänt). En natt vars fönster
    /// har fler minuter än posten räknades på räknas om: en färdig natt direkt, en pågående när appen är öppen
    /// (`awake`). Det ersätter regeln om hämtningarnas slut (A3) och synken ikapp (B158). `forced` räknas om oavsett.
    public static func jobs(dayStems: [String], recordingStems: [String] = [], entries: [WakeDay: Entry],
                            build: String, now: Date, utcOffsetSeconds: Int,
                            edits: SleepEdits = SleepEdits(), minutes: Set<Int>? = nil, awake: Bool = true,
                            forced: Set<WakeDay> = []) -> [Job] {
        let today = WakeDay(now, utcOffsetSeconds: utcOffsetSeconds)
        var ut: [Job] = []
        for w in candidates(dayStems: dayStems, recordingStems: recordingStems,
                            utcOffsetSeconds: utcOffsetSeconds, today: today) {
            let slut = windowEnd(w, utcOffsetSeconds: utcOffsetSeconds)
            let pågår: Bool = now < slut
            let satt: Bool = isSettled(w, now: now, utcOffsetSeconds: utcOffsetSeconds)
            guard let e = entries[w], e.build == build, e.edit == edits[w], !forced.contains(w) else {
                ut.append(Job(wakeDay: w, preliminary: pågår, settled: satt))
                continue
            }
            let nytt: Bool = minutes.map { (m: Set<Int>) -> Bool in
                coveredMinutes(w, minutes: m, utcOffsetSeconds: utcOffsetSeconds) > (e.coverage ?? 0)
            } ?? false
            if pågår {
                if awake && (nytt || now.timeIntervalSince(e.computedAt) >= preliminaryMinutes * 60) {
                    ut.append(Job(wakeDay: w, preliminary: true, settled: false))
                }
            } else if e.preliminary || (satt && !e.settled) || nytt {
                ut.append(Job(wakeDay: w, preliminary: false, settled: satt))
            }
        }
        return ut
    }

    /// BESLUT B48 · METOD M28. Räknar nätterna som är dags (`jobs`), nyaste
    /// först, en i taget, och lämnar varje post till `save` så fort den är
    /// klar (en natt som hunnit räknas går inte förlorad om appen stängs under
    /// nästa). Filerna läses med `load` (`K18Days.night`): appen läser dem ur
    /// Application Support, proven ger dem ur minnet. Det här är vad telefonen
    /// kör, från filerna till posten med nattens sammanfattning (`digest`,
    /// `nil` = en dag utan natt, BESLUT B31). Ger antalet poster. Med `sound` (METOD M44, BESLUT B54) läser varje
    /// natt också sitt ljud, och sammanfattningen bär det (`NightDigest.sound`). Med `edits` (METOD M55, BESLUT B70)
    /// räknas en ändrad natt med sin givna period, och posten bär ändringen.
    @discardableResult
    public static func computeDue(dayStems: [String], recordingStems: [String] = [],
                                  entries: [WakeDay: Entry], build: String, now: Date, utcOffsetSeconds: Int,
                                  load: (String) -> K18Days.File?, save: (Entry) -> Void,
                                  sound: NightSound.Analyzer? = nil, edits: SleepEdits = SleepEdits(),
                                  minutes: Set<Int>? = nil, awake: Bool = true, forced: Set<WakeDay> = []) -> Int {
        let jobb: [Job] = jobs(dayStems: dayStems, recordingStems: recordingStems, entries: entries,
                               build: build, now: now, utcOffsetSeconds: utcOffsetSeconds, edits: edits,
                               minutes: minutes, awake: awake, forced: forced)
        for j in jobb {
            let ändring: SleepEdit? = edits[j.wakeDay]
            let resultat: NightResult? = K18Days.night(wakeDay: j.wakeDay, includeNext: j.settled,
                                                       recordingStems: recordingStems,
                                                       fallbackOffsetSeconds: utcOffsetSeconds, load: load,
                                                       sound: sound, edit: ändring, now: now)
            let digest: NightDigest? = resultat.map { (r: NightResult) -> NightDigest in
                NightDigest(r, preliminary: j.preliminary)
            }
            let täckt: Int? = minutes.map { (m: Set<Int>) -> Int in
                coveredMinutes(j.wakeDay, minutes: m, utcOffsetSeconds: utcOffsetSeconds)
            }
            save(Entry(build: build, wakeDay: j.wakeDay, computedAt: now, preliminary: j.preliminary,
                       settled: j.settled, digest: digest, edit: ändring, coverage: täckt))
        }
        return jobb.count
    }
}
