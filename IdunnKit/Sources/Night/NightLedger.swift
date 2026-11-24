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
/// - **Pågående natt** (före klockan 12 på uppvakningsdagen): räknas fram till
///   nu och märks preliminär, men högst var `preliminaryMinutes` minut.
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

        public init(build: String, wakeDay: WakeDay, computedAt: Date, preliminary: Bool, settled: Bool,
                    digest: NightDigest?, edit: SleepEdit? = nil) {
            self.build = build
            self.wakeDayNumber = wakeDay.daysSince1970
            self.computedAt = computedAt
            self.preliminary = preliminary
            self.settled = settled
            self.digest = digest
            self.edit = edit
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
    /// PLAN.md A3. `fetches` är när Idunns egna hämtningar slutade (sidofilernas `hämtning klar`/`hämtning stoppad`).
    /// En hämtning som slutat efter att natten räknades, i en dygnsfil natten läser, räknar om den direkt: utan
    /// Whoop-appen kommer nattens data med hämtningen, och den kan komma efter att natten räknats färdigt (en
    /// hämtning dagen efter, efter att natten satt sig, lästes annars aldrig in). En pågående natt väntar då inte
    /// in `preliminaryMinutes`.
    public static func jobs(dayStems: [String], recordingStems: [String] = [], entries: [WakeDay: Entry],
                            build: String, now: Date, utcOffsetSeconds: Int,
                            edits: SleepEdits = SleepEdits(), fetches: [Date] = []) -> [Job] {
        let today = WakeDay(now, utcOffsetSeconds: utcOffsetSeconds)
        var ut: [Job] = []
        for w in candidates(dayStems: dayStems, recordingStems: recordingStems,
                            utcOffsetSeconds: utcOffsetSeconds, today: today) {
            let slut = windowEnd(w, utcOffsetSeconds: utcOffsetSeconds)
            let pågår: Bool = now < slut
            let satt: Bool = isSettled(w, now: now, utcOffsetSeconds: utcOffsetSeconds)
            guard let e = entries[w], e.build == build, e.edit == edits[w] else {
                ut.append(Job(wakeDay: w, preliminary: pågår, settled: satt))
                continue
            }
            let hämtat: Bool = fetches.contains { (t: Date) -> Bool in
                t > e.computedAt && t <= now && reads(w, fetchedAt: t, settled: satt, utcOffsetSeconds: utcOffsetSeconds)
            }
            if pågår {
                if hämtat || now.timeIntervalSince(e.computedAt) >= preliminaryMinutes * 60 {
                    ut.append(Job(wakeDay: w, preliminary: true, settled: false))
                }
            } else if e.preliminary || (satt && !e.settled) || hämtat {
                ut.append(Job(wakeDay: w, preliminary: false, settled: satt))
            }
        }
        return ut
    }

    /// PLAN.md A3. Läser natten för `w` dygnsfilen som en hämtning vid `t` hamnade i? Hämtningen sparas i filen för
    /// det lokala datum den hördes (`DayLog.stem`); natten läser dygnet före och dagen själv, och dygnet efter när
    /// den satt sig (`K18Days.stems`).
    static func reads(_ w: WakeDay, fetchedAt t: Date, settled: Bool, utcOffsetSeconds: Int) -> Bool {
        guard let dag = DayLog.day(ofStem: DayLog.stem(for: t, utcOffsetSeconds: utcOffsetSeconds)) else { return false }
        let d: Int = dag.daysSince1970 - w.daysSince1970
        return d == -1 || d == 0 || (d == 1 && settled)
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
                                  fetches: [Date] = []) -> Int {
        let jobb: [Job] = jobs(dayStems: dayStems, recordingStems: recordingStems, entries: entries,
                               build: build, now: now, utcOffsetSeconds: utcOffsetSeconds, edits: edits,
                               fetches: fetches)
        for j in jobb {
            let ändring: SleepEdit? = edits[j.wakeDay]
            let resultat: NightResult? = K18Days.night(wakeDay: j.wakeDay, includeNext: j.settled,
                                                       recordingStems: recordingStems,
                                                       fallbackOffsetSeconds: utcOffsetSeconds, load: load,
                                                       sound: sound, edit: ändring, now: now)
            let digest: NightDigest? = resultat.map { (r: NightResult) -> NightDigest in
                NightDigest(r, preliminary: j.preliminary)
            }
            save(Entry(build: build, wakeDay: j.wakeDay, computedAt: now, preliminary: j.preliminary,
                       settled: j.settled, digest: digest, edit: ändring))
        }
        return jobb.count
    }
}
