import Foundation
import WhoopFrames

/// METOD M28 · BESLUT B3 · BESLUT B31
/// Det en natt ur K18 lämnar efter sig i listorna, trenderna, landskapet och
/// kontrollen: bara samlade tal och tider, aldrig ett enskilt slag. Räknas ur
/// `NightResult` (en gång per natt och bygge) och sparas av appen; kurvan,
/// Poincarémolnet och rapportens detaljer räknas om ur dygnsfilerna när en vy
/// behöver dem (de är för stora att spara).
public struct NightDigest: Codable, Equatable, Sendable {
    public var source: NightSource
    /// Uppvakningsdagen som dagar sedan 1970 (`WakeDay.daysSince1970`).
    public var wakeDayNumber: Int
    /// Zonen natten hör till (sekunder öster om Greenwich).
    public var utcOffsetSeconds: Int
    /// Insomning och uppvaknande (sömnperioden, METOD M26).
    public var sleepStart: Date?
    public var sleepEnd: Date?
    /// Sömntiden i minuter: perioden utan vakna stunder och glapp.
    public var sleepMinutes: Double?
    /// Andelen av periodens minuter som har K18 (METOD M24).
    public var coverage: Double?
    /// Sekunder med puls i perioden, för att skilja en natt från en tom.
    public var pulseSeconds: Int
    /// METOD M4 · BESLUT B13. Nattens medel, och den Whoop-lika kandidaten.
    public var rmssdMean: Double?
    public var rmssdWhoopLike: Double?
    /// METOD M76 · BESLUT B131. Nattens första och andra halva (`NightHalves`); `nil` för en halva med för få fönster.
    /// Äldre sparade sammanfattningar saknar fälten och avkodas ändå.
    public var rmssdEarly: Double?
    public var rmssdLate: Double?
    /// METOD M5
    public var restingHeartRate: Double?
    /// BESLUT B34. Medelpulsen över sömnperioden; bara för en natt med sömnperiod (ur K18).
    public var meanHeartRate: Double?
    /// METOD M37 · BESLUT B45. Minuter i lätt sömn, djup sömn och REM; `nil` utan stadier. Äldre sparade
    /// sammanfattningar saknar fälten och avkodas ändå.
    public var lightMinutes: Double?
    public var deepMinutes: Double?
    public var remMinutes: Double?
    /// METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden; `nil` utan K18-lager och vid för låg täckning.
    /// Äldre sparade sammanfattningar saknar fältet och avkodas ändå.
    public var movementMinutes: Int?
    /// METOD M44 · BESLUT B54. Nattens ljud i några tal och de händelser som väckte; `nil` för en natt utan ljud
    /// och i en sammanfattning från före bygge 10. Äldre sparade sammanfattningar saknar fältet och avkodas ändå.
    public var sound: NightSoundDigest?
    /// METOD M50 · BESLUT B63. Sömneffektiviteten i procent (sömntiden delad med sömnperioden) och antalet vakna
    /// stunder i perioden. `nil` utan sömnperiod; äldre sparade sammanfattningar saknar fälten och avkodas ändå.
    public var efficiency: Double?
    public var wakeBouts: Int?
    /// METOD M52 · BESLUT B63. Minuter i stadiet vaken (de andra tre ligger ovan); `nil` utan stadier.
    public var awakeMinutes: Double?
    /// METOD M52. Insomning och uppvaknande som minuter efter midnatt på uppvakningsdagen (`Trends.clockMinutes`).
    public var onsetMinutes: Double?
    public var wakeMinutes: Double?
    /// METOD M10
    public var breathsPerMinute: Double?
    public var validWindows: Int
    /// METOD M25. Nattens hudtemperatur och täckningen den bygger på.
    public var skinTemperature: Double?
    public var skinCoverage: Double?
    /// METOD M18. Nattens form, för den typiska natten.
    public var profile: NightCurve.Profile?
    /// METOD M22. Pulsen på väggklockan, för landskapet.
    public var landscape: NightLandscape.Profile?
    /// METOD M28. Kontrollen av stämpelns tolkning: andelen poster som lade om
    /// sina slag, antalet omläggningar och utelämnade slag.
    public var reanchorings: Int
    public var fractionReanchored: Double
    public var omittedBeats: Int
    public var fractionOmitted: Double
    /// Räknad före klockan 12 (fönstret fram till nu): kan ändras av en senare synk.
    public var preliminary: Bool
    /// METOD M55 · BESLUT B70. Sant när sömnperioden är användaren ändring (somnade och vaknade givna), och då perioden
    /// som hittades ur rörelsen (`nil` om ingen hittades). `nil` för en natt som den hittades och i äldre
    /// sammanfattningar.
    public var edited: Bool?
    public var foundStart: Date?
    public var foundEnd: Date?
    /// METOD M26 · BESLUT B73. K18 saknas vid sömnblockets början eller slut (`SleepPeriod.incompleteStart/End`):
    /// insomningen eller uppvaknandet ligger där datan började eller slutade, och sömntiden är för kort. `nil` utan
    /// sömnperiod och i äldre sammanfattningar; en ändrad period (M55) märks aldrig.
    public var incompleteStart: Bool?
    public var incompleteEnd: Bool?

    public init(_ r: NightResult, preliminary: Bool = false) {
        source = r.source
        utcOffsetSeconds = r.utcOffsetSeconds
        wakeDayNumber = r.wakeDay?.daysSince1970 ?? 0
        sleepStart = r.sleep?.onsetDate ?? r.analysis.start
        sleepEnd = r.sleep?.wakeDate ?? r.analysis.end
        sleepMinutes = r.sleep?.asleepMinutesTotal
        coverage = r.coverage
        pulseSeconds = r.pulse.reduce(0) { (sum: Int, m: PulseMinute) -> Int in sum + m.seconds }
        rmssdMean = r.analysis.rmssd.mean
        rmssdWhoopLike = r.analysis.rmssd.whoopLike
        let halvor: NightHalves.Halves = NightHalves.compute(r)
        rmssdEarly = halvor.early
        rmssdLate = halvor.late
        restingHeartRate = r.analysis.restingHeartRate
        meanHeartRate = r.sleep != nil ? r.analysis.meanHeartRate : nil
        lightMinutes = r.stages?.minutes(.light)
        deepMinutes = r.stages?.minutes(.deep)
        remMinutes = r.stages?.minutes(.rem)
        movementMinutes = r.movementMinutes
        efficiency = r.sleep.flatMap { (p: SleepPeriod) -> Double? in p.periodEfficiency }
        incompleteStart = r.sleep.map { (p: SleepPeriod) -> Bool in p.incompleteStart }
        incompleteEnd = r.sleep.map { (p: SleepPeriod) -> Bool in p.incompleteEnd }
        wakeBouts = r.sleep?.wakeBouts.count
        awakeMinutes = r.stages?.minutes(.wake)
        if let p = r.sleep, let dag = r.wakeDay {
            onsetMinutes = Trends.clockMinutes(p.onsetDate, day: dag, utcOffsetSeconds: r.utcOffsetSeconds)
            wakeMinutes = Trends.clockMinutes(p.wakeDate, day: dag, utcOffsetSeconds: r.utcOffsetSeconds)
        }
        sound = r.sound?.digest
        breathsPerMinute = r.analysis.breathsPerMinute
        validWindows = r.analysis.validWindows
        skinTemperature = r.skin?.celsius
        skinCoverage = r.skin?.coverage
        profile = r.curve?.profile
        landscape = r.landscape
        reanchorings = r.analysis.cleaning.reanchorings
        fractionReanchored = r.analysis.cleaning.fractionReanchored
        omittedBeats = r.analysis.cleaning.omitted
        fractionOmitted = r.analysis.cleaning.fractionOmitted
        self.preliminary = preliminary
        if r.edit != nil {
            edited = true
            foundStart = r.found?.startDate
            foundEnd = r.found?.endDate
        }
    }

    public var wakeDay: WakeDay { WakeDay(daysSince1970: wakeDayNumber) }

    /// Natten som trenderna och morgonkortet ser den (METOD M16, M19).
    public var idunNight: Trends.IdunNight {
        Trends.IdunNight(day: wakeDay, validWindows: validWindows, rmssd: rmssdMean,
                         restingHeartRate: restingHeartRate, breathsPerMinute: breathsPerMinute,
                         skinTemperature: skinTemperature,
                         rmssdWhoopLike: rmssdWhoopLike,
                         sleepHours: sleepMinutes.map { (m: Double) -> Double in m / 60 },
                         sleepEpisode: Trends.sleepEpisode(source: source, start: sleepStart, end: sleepEnd,
                                                           utcOffsetSeconds: utcOffsetSeconds,
                                                           sleepMinutes: sleepMinutes, coverage: coverage),
                         meanHeartRate: meanHeartRate,
                         movementMinutes: movementMinutes,
                         snoringPerHour: sound?.snoringPerHour,
                         source: source,
                         efficiency: efficiency, wakeBouts: wakeBouts, awakeMinutes: awakeMinutes,
                         lightMinutes: lightMinutes, deepMinutes: deepMinutes, remMinutes: remMinutes,
                         onsetMinutes: onsetMinutes, wakeMinutes: wakeMinutes)
    }
}
