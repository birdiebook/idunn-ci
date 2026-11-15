import Foundation
import Night
import Pass

/// BESLUT B64 · METOD M53
/// En natt som sömnbehovet räknar med. Tiderna är lokala: `day` är uppvakningsdagen
/// (dagar sedan 1970-01-01 i nattens zon), och insomning och uppvaknande är minuter
/// från uppvakningsdagens midnatt, så en insomning 23.30 är −30.
public struct SleepNight: Equatable, Sendable {
    public var day: Int
    /// Sovtid i minuter: sömn inom perioden, utan vakna stunder (M26, M37).
    public var asleepMinutes: Double
    /// Perioden från insomning till uppvaknande i minuter.
    public var periodMinutes: Double
    public var onsetMinute: Double
    public var wakeMinute: Double

    public init(day: Int, asleepMinutes: Double, periodMinutes: Double, onsetMinute: Double,
                wakeMinute: Double) {
        self.day = day
        self.asleepMinutes = asleepMinutes
        self.periodMinutes = periodMinutes
        self.onsetMinute = onsetMinute
        self.wakeMinute = wakeMinute
    }

    /// Natten ur insomning och uppvaknande i en zon.
    public init(onset: Date, wake: Date, asleepMinutes: Double, timeZone: TimeZone) {
        let w = LocalClock(wake, timeZone)
        self.init(day: w.day, asleepMinutes: asleepMinutes,
                  periodMinutes: max(0, wake.timeIntervalSince(onset)) / 60,
                  onsetMinute: LocalClock(onset, timeZone).minutes(from: w.day),
                  wakeMinute: w.minutes(from: w.day))
    }
}

/// BESLUT B64 · METOD M53
/// Ett pass som sömnbehovet räknar med: dagen det slutade, slutet i minuter från
/// den dagens midnatt, och belastningen (`PassLoad`).
public struct PassDay: Equatable, Sendable {
    public var day: Int
    public var stopMinute: Double
    public var load: Double

    public init(day: Int, stopMinute: Double, load: Double) {
        self.day = day
        self.stopMinute = stopMinute
        self.load = load
    }

    /// Passet i en zon. Slutet är Stopp, eller sista provet om passet aldrig stoppades.
    public init(_ pass: Pass, maxPulse: Double, timeZone: TimeZone) {
        let end = pass.stop ?? pass.start.addingTimeInterval(pass.duration)
        let c = LocalClock(end, timeZone)
        self.init(day: c.day, stopMinute: c.minutes(from: c.day), load: PassLoad.load(pass, maxPulse: maxPulse))
    }
}

/// Ett ögonblick i lokal tid: dagnumret och sekunderna sedan 1970-01-01 i zonen
/// (som DayLog.localDay, utan Calendar).
struct LocalClock {
    let local: Double
    let day: Int

    init(_ t: Date, _ zone: TimeZone) {
        local = t.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: t))
        day = Int((local / 86400).rounded(.down))
    }

    /// Minuter från midnatt på dagen `d`.
    func minutes(from d: Int) -> Double { (local - Double(d) * 86400) / 60 }
}

/// BESLUT B64 · BESLUT B67 · METOD M53
/// Grundbehovet: medel och SD i minuter sovtid. Priorn 8 h ± 30 min, uppdaterad med Whoops behov för dig när
/// exporten finns (`fromWhoop`).
public struct BaseNeed: Equatable, Sendable {
    public var minutes: Double
    public var sdMinutes: Double
    public var fromWhoop: Bool

    public init(minutes: Double, sdMinutes: Double, fromWhoop: Bool = false) {
        self.minutes = minutes
        self.sdMinutes = sdMinutes
        self.fromWhoop = fromWhoop
    }
}

/// BESLUT B64 · METOD M53
/// Natten i räkningen: behovet den natten och skulden efter den.
public struct NightNeed: Equatable, Sendable {
    public var day: Int
    public var baseMinutes: Double
    /// Tillägget efter gårdagens pass.
    public var passMinutes: Double
    /// Nattens behov: grundbehov + tillägg (skulden ingår inte, den följer i `debtMinutes`).
    public var needMinutes: Double
    /// Sovtiden; `nil` när natten saknas, och då står skulden still.
    public var sleptMinutes: Double?
    /// Skulden efter natten, i minuter sovtid.
    public var debtMinutes: Double
}

/// BESLUT B64 · METOD M53
/// Kvällens behov och läggdags. Minuterna för väckning och läggdags räknas från
/// midnatt på uppvakningsdagen, så en läggdags 22.40 är −80.
public struct TonightPlan: Equatable, Sendable {
    public var day: Int
    public var baseMinutes: Double
    public var passMinutes: Double
    /// Skulden efter senaste natten.
    public var debtMinutes: Double
    /// Den del av skulden som läggs på kvällens behov (högst 60 min).
    public var debtPartMinutes: Double
    public var needMinutes: Double
    public var wakeMinute: Double
    /// Sovtid delad med perioden, median över de senaste nätterna.
    public var efficiency: Double
    /// Läggdags för full sömn: väcktid − behov / effektivitet − 15 min.
    public var bedtimeMinute: Double
    /// BESLUT B75 · METOD M53. Läggdags för bästa förväntade sömnpoäng (M56), sovtiden den ger och poängen; poängen
    /// för full sömn bredvid. Utan någon natt bland de fyra före är det läggdags för full sömn.
    public var bestBedtimeMinute: Double
    public var bestAsleepMinutes: Double
    public var bestScore: Double
    public var fullScore: Double
}

/// BESLUT B65 · METOD M53
/// En dag som vyerna visar den (`SleepNeed.days`). Minuterna för läggdags räknas från midnatt
/// på dagen efter (`tonight.day`), som i `TonightPlan`.
public struct NeedDay: Equatable, Sendable {
    public var day: Int
    public var base: BaseNeed
    /// Tillägget efter gårdagens pass.
    public var passMinutes: Double
    /// Den del av skulden före natten som lades på nattens behov (högst 60 min).
    public var debtPartMinutes: Double
    /// Nattens behov: grundbehov + tillägg + skuldens del.
    public var needMinutes: Double
    /// Sovtiden; `nil` när natten saknas.
    public var sleptMinutes: Double?
    /// Skulden efter natten.
    public var debtMinutes: Double
    /// Kvällens plan efter morgonen: behovet och läggdags för natten som slutar dagen efter.
    public var tonight: TonightPlan?
}

/// BESLUT B64 · METOD M53
/// Sömnbehovet per natt (PLAN.md H1): grundbehov + tillägg efter gårdagens pass,
/// skulden natt för natt, och kvällens behov med läggdags.
public enum SleepNeed {
    /// Medianen; medel av de två mittersta vid jämnt antal. `nil` för en tom lista.
    public static func median(_ x: [Double]) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// De senaste nätterna före dagen `day` (högst `windowNights`), äldst först.
    static func recent(_ nights: [SleepNight], before day: Int) -> [SleepNight] {
        Array(nights.filter { $0.day < day }.sorted { $0.day < $1.day }.suffix(SleepNeedRules.windowNights))
    }

    /// METOD M53. Den vanliga insomningen före natten som slutar dagen `day`.
    public static func usualOnset(_ nights: [SleepNight], before day: Int) -> Double? {
        median(recent(nights, before: day).map(\.onsetMinute))
    }

    /// METOD M53. Tillägget för natten som slutar dagen `day`: passen som slutade dagen
    /// före, minst 8 h före den vanliga insomningen, gånger 0,01 min per enhet, högst 10 min.
    /// Utan vanlig insomning går tiden inte att bedöma, och tillägget är 0.
    public static func passAddition(_ passes: [PassDay], day: Int, usualOnset: Double?) -> Double {
        guard let onset = usualOnset else { return 0 }
        var load = 0.0
        for p in passes where p.day == day - 1 {
            // Passets slut i minuter från uppvakningsdagens midnatt.
            let hoursBefore = (onset - (p.stopMinute - 1440)) / 60
            if hoursBefore >= SleepNeedRules.passMinHoursBeforeOnset { load += p.load }
        }
        return min(SleepNeedRules.passCapMinutes, SleepNeedRules.minutesPerLoad * load)
    }

    /// METOD M53 · BESLUT B67. Grundbehovet: priorn 8 h ± 30 min, uppdaterad med Whoops grundbehov för dig
    /// (`whoopBase`, SD 15 min) när exporten finns: precisionerna summeras och medlet är det precisionsvägda.
    public static func baseNeed(whoopBase: Double?) -> BaseNeed {
        let s0 = SleepNeedRules.priorBaseSDMinutes
        var precision = 1 / (s0 * s0)
        var sum = SleepNeedRules.priorBaseMinutes * precision
        if let w = whoopBase {
            let s = SleepNeedRules.whoopObservationSDMinutes
            precision += 1 / (s * s)
            sum += w / (s * s)
        }
        return BaseNeed(minutes: sum / precision, sdMinutes: 1 / precision.squareRoot(), fromWhoop: whoopBase != nil)
    }

    /// METOD M53 · BESLUT B67. Whoops grundbehov ur par av (gårdagens strain, behov − skuld): medianen av behov −
    /// skuld de nätter vars gårdag hade strain i lägsta fjärdedelen, så att Whoops tillägg för belastning blir litet
    /// (som `jamfor_somnbehov.whoops_grund`). `nil` med färre än 7 par.
    public static func whoopBase(pairs: [(strain: Double, base: Double)]) -> Double? {
        guard pairs.count >= SleepNeedRules.whoopMinNights else { return nil }
        let limit = pairs.map(\.strain).sorted()[pairs.count / 4]
        return median(pairs.filter { $0.strain <= limit }.map(\.base))
    }

    /// METOD M53 · BESLUT B68. Skulden natt för natt från första natten: skuld = skuld i går × e^(−1/1,5)
    /// + (behov − sovtid), aldrig under 0. En natt som saknas ger ingen ändring.
    public static func ledger(nights: [SleepNight], passes: [PassDay], base: Double) -> [NightNeed] {
        guard let first = nights.map(\.day).min(), let last = nights.map(\.day).max() else { return [] }
        let byDay = Dictionary(nights.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let decay = exp(-1 / SleepNeedRules.debtTimeConstantNights)
        var debt = 0.0
        var out: [NightNeed] = []
        for d in first...last {
            let add = passAddition(passes, day: d, usualOnset: usualOnset(nights, before: d))
            let need = base + add
            let slept = byDay[d]?.asleepMinutes
            if let s = slept { debt = max(0, debt * decay + need - s) }
            out.append(NightNeed(day: d, baseMinutes: base, passMinutes: add, needMinutes: need,
                                 sleptMinutes: slept, debtMinutes: debt))
        }
        return out
    }

    /// METOD M53. Kvällens behov för natten som slutar dagen `day`: grundbehov + tillägg
    /// efter dagens pass + skulden, högst 60 min av den. Läggdags = väcktid − behov /
    /// effektivitet − 15 min. `nil` utan någon natt före, eller utan en period att räkna
    /// effektiviteten på. Med `wakeMinute` (minuter efter midnatt på uppvakningsdagen, BESLUT B74) räknas läggdags från
    /// den tiden i stället för det vanliga uppvaknandet; behovet och skulden ändras inte av den.
    public static func tonight(nights: [SleepNight], passes: [PassDay], base: Double, day: Int,
                               wakeMinute: Double? = nil) -> TonightPlan? {
        let before = nights.filter { $0.day < day }
        let debt = ledger(nights: before, passes: passes, base: base).last?.debtMinutes ?? 0
        return tonight(nights: nights, passes: passes, base: base, day: day, debt: debt, wakeMinute: wakeMinute)
    }

    /// Kvällens plan med skulden redan räknad (skulden efter senaste natten före `day`).
    static func tonight(nights: [SleepNight], passes: [PassDay], base: Double, day: Int, debt: Double,
                        wakeMinute: Double? = nil) -> TonightPlan? {
        let window = recent(nights, before: day)
        guard let wake = wakeMinute ?? median(window.map(\.wakeMinute)),
              let eff = median(window.filter { $0.periodMinutes > 0 }.map { $0.asleepMinutes / $0.periodMinutes }),
              eff > 0 else { return nil }
        let add = passAddition(passes, day: day, usualOnset: median(window.map(\.onsetMinute)))
        let part = min(debt, SleepNeedRules.debtInTonightCapMinutes)
        let need = base + add + part
        let full = wake - need / eff - SleepNeedRules.sleepLatencyMinutes
        let före: [Regularity.Episode] = window.filter { $0.day >= day - Regularity.nightComparisons }
            .compactMap(episode)
        let best = bestBedtime(day: day, wake: wake, efficiency: eff, need: need, full: full,
                               regularity: Regularity.PlannedNight(före, day: WakeDay(daysSince1970: day),
                                                                   sleepFraction: eff))
        return TonightPlan(day: day, baseMinutes: base, passMinutes: add, debtMinutes: debt,
                           debtPartMinutes: part, needMinutes: need, wakeMinute: wake, efficiency: eff,
                           bedtimeMinute: full, bestBedtimeMinute: best.bedtime, bestAsleepMinutes: best.asleep,
                           bestScore: best.score, fullScore: best.fullScore)
    }

    /// METOD M53 · BESLUT B75. En natt som ett pass för regelbundenheten (M33): väggklockans tid som UTC, sömnens andel
    /// ur sovtiden och perioden. `nil` när perioden saknar längd.
    static func episode(_ n: SleepNight) -> Regularity.Episode? {
        let t0 = Double(n.day) * 86400
        return Regularity.Episode.idun(onset: Date(timeIntervalSince1970: t0 + n.onsetMinute * 60),
                                       wake: Date(timeIntervalSince1970: t0 + n.wakeMinute * 60),
                                       utcOffsetSeconds: 0, sleepMinutes: n.asleepMinutes)
    }

    /// METOD M53 · METOD M56 · BESLUT B75. Nattens förväntade sömnpoäng med läggdags `bedtime`: sovtiden är (väcktid −
    /// läggdags − insomningstiden) × effektiviteten, mängden mot kvällens behov, kontinuiteten effektiviteten, och
    /// regelbundenheten nattens SRI för en natt sovd från insomningen till väcktiden mot de fyra nätterna före
    /// (`regularity`, `nil` utan underlag). Spegel: `tools/somnbehov.py:forvantad_poang`.
    public static func expectedScore(day: Int, bedtime: Double, wake: Double, efficiency eff: Double, need: Double,
                                     regularity: Regularity.PlannedNight?) -> (score: Double, asleep: Double) {
        let onset = bedtime + SleepNeedRules.sleepLatencyMinutes
        let asleep = max(0, (wake - onset) * eff)
        var sri: Double?
        if let r = regularity, wake > onset {
            let t0 = Double(day) * 86400
            sri = r.index(onset: Date(timeIntervalSince1970: t0 + onset * 60),
                          wake: Date(timeIntervalSince1970: t0 + wake * 60), utcOffsetSeconds: 0)
        }
        let s = SleepScoring.score(day: day, asleepMinutes: asleep, needMinutes: need, efficiency: 100 * eff,
                                   regularity: sri)
        return (s?.score ?? 0, asleep)
    }

    /// METOD M53 · BESLUT B75 · BESLUT B84. Läggdags med högst förväntad sömnpoäng: läggdags för full sömn ± steg om
    /// 5 min inom 12–4 h före väcktiden; vid lika den närmast full sömn (den tidigare först). Den gäller bara när den ger
    /// minst `bestBedtimeMinGainScore` (1 poäng) mer än full sömn, annars full sömn (trögheten, B84). Utan underlag för
    /// regelbundenheten gäller full sömn. Spegel: `tools/somnbehov.py:basta_laggdags`.
    static func bestBedtime(day: Int, wake: Double, efficiency eff: Double, need: Double, full: Double,
                            regularity: Regularity.PlannedNight?)
        -> (bedtime: Double, asleep: Double, score: Double, fullScore: Double) {
        let f = expectedScore(day: day, bedtime: full, wake: wake, efficiency: eff, need: need, regularity: regularity)
        guard regularity != nil else { return (full, f.asleep, f.score, f.score) }
        let steg = SleepNeedRules.bestBedtimeStepMinutes
        let lo = Int(((wake - 60 * SleepNeedRules.bestBedtimeEarliestHoursBeforeWake - full) / steg).rounded(.up))
        let hi = Int(((wake - 60 * SleepNeedRules.bestBedtimeLatestHoursBeforeWake - full) / steg).rounded(.down))
        var bäst = (bedtime: full, asleep: f.asleep, score: f.score)
        let längst = max(abs(lo), abs(hi))
        if längst >= 1 {
            for k in 1...längst {
                for i in [-k, k] where lo <= i && i <= hi {
                    let b = full + steg * Double(i)
                    let e = expectedScore(day: day, bedtime: b, wake: wake, efficiency: eff, need: need,
                                          regularity: regularity)
                    if e.score > bäst.score + SleepNeedRules.bestBedtimeTieScore { bäst = (b, e.asleep, e.score) }
                }
            }
        }
        // BESLUT B84: trögheten. En bråkdel av en poäng flyttar inte läggdags från full sömn.
        guard bäst.score - f.score >= SleepNeedRules.bestBedtimeMinGainScore else {
            return (full, f.asleep, f.score, f.score)
        }
        return (bäst.bedtime, bäst.asleep, bäst.score, f.score)
    }

    /// METOD M53 · BESLUT B65. Dag för dag från första natten till sista, det vyerna visar: nattens behov
    /// (grundbehov + tillägg + skulden före natten, högst 60 min av den), skulden efter natten och kvällens plan efter
    /// morgonen. Med `wakeMinute` (BESLUT B74) räknas kvällens läggdags från den väcktiden; allt annat som förut.
    public static func days(nights: [SleepNight], passes: [PassDay], whoopBase: Double? = nil,
                            wakeMinute: Double? = nil) -> [NeedDay] {
        days(nights: nights, passes: passes, whoopBase: whoopBase) { (_: Int) -> Double? in wakeMinute }
    }

    /// BESLUT B102. Dagarna med väcktiden per uppvakningsdag (`wake`, `nil` = det vanliga uppvaknandet): en enda tid
    /// (B74) eller schemat (`WakeSchedule`).
    static func days(nights: [SleepNight], passes: [PassDay], whoopBase: Double?,
                     wake: (Int) -> Double?) -> [NeedDay] {
        let base = baseNeed(whoopBase: whoopBase)
        var debtBefore = 0.0
        var out: [NeedDay] = []
        for n in ledger(nights: nights, passes: passes, base: base.minutes) {
            let part = min(debtBefore, SleepNeedRules.debtInTonightCapMinutes)
            out.append(NeedDay(day: n.day, base: base, passMinutes: n.passMinutes, debtPartMinutes: part,
                               needMinutes: base.minutes + n.passMinutes + part, sleptMinutes: n.sleptMinutes,
                               debtMinutes: n.debtMinutes,
                               tonight: tonight(nights: nights, passes: passes, base: base.minutes, day: n.day + 1,
                                                debt: n.debtMinutes, wakeMinute: wake(n.day + 1))))
            debtBefore = n.debtMinutes
        }
        return out
    }
}
