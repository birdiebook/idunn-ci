import Foundation
import WhoopFrames

/// METOD M32 · BESLUT B26 · BESLUT B39
/// Det Nattens kurva lägger på pulsens tidsaxel för en natt ur K18 (PLAN.md
/// R2): rörelse och hudtemperatur per klockminut, sömnperioden med de vakna
/// stunderna, och glappen i slagen med sin orsak. Bara värden och tider; vyn
/// ritar dem. En gammal inspelning har inga lager (`NightResult.layers` är
/// `nil`) och kurvan ritas som förut.
public enum NightLayers {

    // MARK: Gränsen (METOD M32)

    /// METOD M32. En minut räknas som rörelse när dess rörelse (medel av
    /// |Δg|, METOD M24) är minst så här många g: motsatsen till en stilla
    /// minut (`SkinTemperature.stillMovement`, METOD M25), så att kurvan och
    /// hudtemperaturen delar gräns. **Antagande**, samma som M25.
    public static let movementThreshold: Double = SkinTemperature.stillMovement

    /// METOD M32. Ett glapp är rörelse när minst hälften av de minuter i det
    /// som har ett rörelsetal ligger över gränsen. **Antagande.**
    public static let movementShare: Double = 0.5

    /// METOD M42. Minuter i rörelse under sömnperioden räknas bara när minst så stor andel av periodens hela
    /// minuter har ett rörelsetal, annars är talet en underskattning och natten får inget. Samma gräns som
    /// hudtemperaturens täckning (METOD M25). **Antagande.**
    public static let movementMinCoverage: Double = SkinTemperature.minCoverage

    // MARK: Resultaten

    /// Varför slagen saknas i ett glapp (METOD M32).
    public enum GapCause: String, Equatable, Sendable {
        /// Armen rörde sig: bandet ger inga slag då (PROTOKOLL_W5 §6).
        case movement
        /// Ingen känd orsak: K18 saknas, eller armen var stilla (METOD M15).
        case unknown
    }

    /// Ett glapp i slagen: tid utan puls ur slag, med sin orsak.
    public struct Gap: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var cause: GapCause

        public init(start: TimeInterval, end: TimeInterval, cause: GapCause) {
            self.start = start
            self.end = end
            self.cause = cause
        }

        public var range: ClosedRange<TimeInterval> { start...end }
    }

    /// En klockminut. Värdena är `nil` när minuten saknar K18 (tom, inte noll)
    /// eller, för rörelsen, när bara en sekund fanns att jämföra.
    public struct Minute: Equatable, Sendable {
        /// Sekunder sedan 1970, hel minut (samma start som `NightCurve.Minute`).
        public var start: TimeInterval
        /// Medel av |Δg| i g (METOD M24).
        public var movement: Double?
        /// Median av hudtemperaturen i °C (METOD M24).
        public var skinTemperature: Double?

        public init(start: TimeInterval, movement: Double?, skinTemperature: Double?) {
            self.start = start
            self.movement = movement
            self.skinTemperature = skinTemperature
        }

        public var mid: TimeInterval { start + NightCurve.minuteSeconds / 2 }
    }

    /// METOD M37 · BESLUT B45 · BESLUT B46 · BESLUT B85. En följd av epoker i rad med samma stadium: en ruta i
    /// stadiebandet, med nivån ur medlet av epokernas säkerhet. Tiderna är sekunder sedan 1970, som resten av lagren.
    public struct StageSpan: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var stage: SleepStage
        /// Säkerhetens nivå 0, 1 eller 2 (`NightStages.certaintyLimits`) för medlet över följden (BESLUT B85).
        public var certainty: Int

        public init(start: TimeInterval, end: TimeInterval, stage: SleepStage, certainty: Int) {
            self.start = start
            self.end = end
            self.stage = stage
            self.certainty = certainty
        }

        public var range: ClosedRange<TimeInterval> { start...end }
    }

    public struct Layers: Equatable, Sendable {
        /// Axelns spann: kurvan och sömnperioden tillsammans.
        public var start: TimeInterval
        public var end: TimeInterval
        /// Varje klockminut från `start` till `end`, tomma minuter med.
        public var minutes: [Minute]
        /// Glappen i slagen, i tidsordning, med orsak.
        public var gaps: [Gap]
        /// Sömnperioden (METOD M26): insomning till uppvaknande.
        public var period: ClosedRange<TimeInterval>
        /// Perioden där Idunn mätte sömn: utan de vakna stunderna och
        /// glappen i K18. Avbrotten mellan dem är vakna stunder.
        public var asleep: [ClosedRange<TimeInterval>]
        /// De vakna stunderna inom perioden (METOD M26).
        public var awake: [ClosedRange<TimeInterval>]
        /// Andelen av spannets minuter som har K18 (METOD M24).
        public var coverage: Double?
        /// METOD M37 · BESLUT B45. Stadierna som följder av epoker i rad (omätta epoker bryter), i tidsordning.
        /// Tom när natten saknar stadier.
        public var stages: [NightLayers.StageSpan] = []

        /// Offentlig sedan J1: ljudets nattanalys (METOD M40) och förhandsvisningens
        /// påhittade nätter bygger lager för hand.
        public init(start: TimeInterval, end: TimeInterval, minutes: [Minute], gaps: [Gap],
                    period: ClosedRange<TimeInterval>, asleep: [ClosedRange<TimeInterval>],
                    awake: [ClosedRange<TimeInterval>], coverage: Double?,
                    stages: [NightLayers.StageSpan] = []) {
            self.start = start
            self.end = end
            self.minutes = minutes
            self.gaps = gaps
            self.period = period
            self.asleep = asleep
            self.awake = awake
            self.coverage = coverage
            self.stages = stages
        }

        /// Minuten som `t` ligger i; `nil` utanför spannet. Värdena i den är
        /// `nil` när minuten saknar K18 (en tryckning i ett glapp visar ingenting).
        public func minute(at t: TimeInterval) -> Minute? {
            guard let first = minutes.first else { return nil }
            let i: Int = Int(((t - first.start) / NightCurve.minuteSeconds).rounded(.down))
            return i >= 0 && i < minutes.count ? minutes[i] : nil
        }

        /// Sant om `t` ligger i en vaken stund inom perioden.
        public func isAwake(_ t: TimeInterval) -> Bool { awake.contains { $0.contains(t) } }

        /// METOD M37. Stadiet vid `t`: första spannet med `start <= t < end`; `nil` utanför och i glapp.
        public func stage(at t: TimeInterval) -> NightLayers.StageSpan? {
            stages.first { (s: NightLayers.StageSpan) -> Bool in s.start <= t && t < s.end }
        }
    }

    // MARK: Räkningen

    /// METOD M32. Lagren för en natt: kurvan (slagen), K18-serien (rörelse och
    /// temperatur) och sömnperioden. Med `stages` (METOD M37) följer stadierna med som spann.
    public static func make(curve: NightCurve.Curve, series: K18Series, sleep: SleepPeriod,
                            stages: NightStages.Night? = nil) -> Layers {
        let onset = Double(sleep.onset)
        let wake = Double(sleep.wake)
        let start: TimeInterval = min(curve.start, onset)
        let end: TimeInterval = max(curve.end, wake)
        let minutes: [Minute] = grid(series, start: start, end: end)
        let spann: Date = Date(timeIntervalSince1970: start)
        let slut: Date = Date(timeIntervalSince1970: end)
        let cuts: [SleepInterval] = (sleep.wakeBouts + sleep.gaps).sorted { $0.start < $1.start }
        return Layers(start: start, end: end, minutes: minutes,
                      gaps: gaps(curve: curve, minutes: minutes),
                      period: onset...wake,
                      asleep: asleepIntervals(onset: sleep.onset, wake: sleep.wake, cuts: cuts),
                      awake: sleep.wakeBouts.map { (i: SleepInterval) -> ClosedRange<TimeInterval> in
                          Double(i.start)...Double(i.end)
                      },
                      coverage: series.coverage(from: spann, to: slut)?.fraction,
                      stages: stageSpans(stages))
    }

    /// METOD M37 · BESLUT B45 · BESLUT B85. Epokerna som spann: en ruta per följd i rad (nästa start är förra
    /// slutet) med samma stadium. Nivån är medlet av epokernas säkerhet för stadiet som visas (summerat från
    /// vänster), så att en följd som B85 döpt om blir blek om epokerna var osäkra. Omätta epoker (inget stadium)
    /// bryter följden och blir inget spann. Som `natt_stadier.spann`.
    static func stageSpans(_ night: NightStages.Night?) -> [StageSpan] {
        guard let night = night else { return [] }
        var out: [StageSpan] = []
        var sums: [Double] = []
        var counts: [Int] = []
        for e in night.epochs {
            guard let stage = e.stage, let c = e.certainty else { continue }
            if let last = out.last, last.end == Double(e.start), last.stage == stage {
                out[out.count - 1].end = Double(e.end)
                sums[sums.count - 1] += c
                counts[counts.count - 1] += 1
            } else {
                out.append(StageSpan(start: Double(e.start), end: Double(e.end), stage: stage, certainty: 0))
                sums.append(c)
                counts.append(1)
            }
        }
        for i in 0..<out.count { out[i].certainty = NightStages.level(sums[i] / Double(counts[i])) }
        return out
    }

    /// METOD M32. Varje klockminut från `start` till `end`; en minut utan
    /// poster i K18 får inga värden.
    static func grid(_ series: K18Series, start: TimeInterval, end: TimeInterval) -> [Minute] {
        let first: Int = Int((start / NightCurve.minuteSeconds).rounded(.down))
        let last: Int = Int((end / NightCurve.minuteSeconds).rounded(.down))
        guard last >= first else { return [] }
        var byMinute: [Int: K18Series.Minute] = [:]
        for m in series.minutes where m.minute >= first && m.minute <= last { byMinute[m.minute] = m }
        return (first...last).map { (k: Int) -> Minute in
            let m: K18Series.Minute? = byMinute[k]
            return Minute(start: Double(k) * NightCurve.minuteSeconds,
                          movement: m?.movement, skinTemperature: m?.skinTemperature)
        }
    }

    /// METOD M32. Glappen i slagen: de som kurvan redan har (mer än 60 s utan
    /// notis, METOD M13) och varje följd av minuter utan puls ur slag, ihopslagna
    /// där de rör vid varandra och klippta till kurvan. Bara hela minuter inom kurvan räknas. Orsaken sätts per glapp.
    static func gaps(curve: NightCurve.Curve, minutes: [Minute]) -> [Gap] {
        var ranges: [ClosedRange<TimeInterval>] = curve.gaps
        // Bara hela minuter inom kurvan: första och sista minuten är bara
        // delvis med och har få slag utan att något saknas.
        let hela: [NightCurve.Minute] = curve.minutes.filter { (m: NightCurve.Minute) -> Bool in
            m.start >= curve.start && m.start + NightCurve.minuteSeconds <= curve.end
        }
        var runStart: TimeInterval?
        for m in hela {
            if m.heartRate == nil {
                if runStart == nil { runStart = m.start }
            } else if let s = runStart {
                ranges.append(s...m.start)
                runStart = nil
            }
        }
        if let s = runStart, let sista = hela.last {
            ranges.append(s...(sista.start + NightCurve.minuteSeconds))
        }
        var clipped: [ClosedRange<TimeInterval>] = []
        for r in ranges {
            let a: TimeInterval = max(r.lowerBound, curve.start)
            let b: TimeInterval = min(r.upperBound, curve.end)
            if b > a { clipped.append(a...b) }
        }
        clipped.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<TimeInterval>] = []
        for r in clipped {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged.map { (r: ClosedRange<TimeInterval>) -> Gap in
            Gap(start: r.lowerBound, end: r.upperBound, cause: cause(of: r, minutes: minutes))
        }
    }

    /// METOD M32. Orsaken till ett glapp: rörelse när minst `movementShare`
    /// av de minuter som rör vid glappet och har ett rörelsetal ligger över
    /// `movementThreshold`; annars okänd, också när ingen minut har K18.
    static func cause(of range: ClosedRange<TimeInterval>, minutes: [Minute]) -> GapCause {
        var med: Int = 0
        var över: Int = 0
        for m in minutes where m.start < range.upperBound && m.start + NightCurve.minuteSeconds > range.lowerBound {
            guard let v = m.movement else { continue }
            med += 1
            if v >= movementThreshold { över += 1 }
        }
        guard med > 0 else { return .unknown }
        return Double(över) / Double(med) >= movementShare ? .movement : .unknown
    }

    /// METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden: hela klockminuter inom perioden vars
    /// rörelse är minst `movementThreshold` (samma gräns som kurvans rörelselager, METOD M32). En minut utan
    /// rörelsetal (utan K18, eller med en enda sekund) är okänd och räknas varken som rörelse eller stillhet.
    /// Är mindre än `movementMinCoverage` av periodens hela minuter kända, eller rymmer perioden ingen hel
    /// minut, finns inget tal (`nil`), inte en gissad nolla.
    public static func movementMinutes(_ minutes: [Minute], period: ClosedRange<TimeInterval>) -> Int? {
        var inne: Int = 0
        var kända: Int = 0
        var rörelse: Int = 0
        for m in minutes {
            guard m.start >= period.lowerBound, m.start + NightCurve.minuteSeconds <= period.upperBound else { continue }
            inne += 1
            guard let v = m.movement else { continue }
            kända += 1
            if v >= movementThreshold { rörelse += 1 }
        }
        guard inne > 0, Double(kända) / Double(inne) >= movementMinCoverage else { return nil }
        return rörelse
    }

    /// METOD M42. Lagrens minuter över lagrens sömnperiod (den förfinade, METOD M37).
    public static func movementMinutes(_ layers: Layers) -> Int? {
        movementMinutes(layers.minutes, period: layers.period)
    }

    /// METOD M32. Perioden utan de vakna stunderna och glappen i K18 (`cuts`,
    /// i tidsordning): det som mättes som sömn.
    static func asleepIntervals(onset: Int, wake: Int, cuts: [SleepInterval]) -> [ClosedRange<TimeInterval>] {
        var ut: [ClosedRange<TimeInterval>] = []
        var cursor: Int = onset
        for c in cuts {
            if c.start > cursor && c.start <= wake { ut.append(Double(cursor)...Double(c.start)) }
            cursor = max(cursor, c.end)
        }
        if cursor < wake { ut.append(Double(cursor)...Double(wake)) }
        return ut
    }
}
