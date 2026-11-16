import Foundation
import HeartRate
import WhoopFrames

/// METOD M28 · BESLUT B28
/// Varifrån en natts slag kommer. Sparas med nattens sammanfattning, så att
/// appen kan visa källan och räkna om en gammal inspelning som förut.
public enum NightSource: String, Codable, Equatable, Sendable {
    /// Den strömmade pulsen (2A37), inspelningar före B28.
    case notification = "2A37"
    /// Bandets historik (K18) över sömnperioden.
    case k18 = "K18"
}

/// METOD M28. Allt som räknas ur en natts slag, oavsett källa: samma kedja
/// som rapporten och kurvan i appen (rensning M3, HRV M4, vilopuls M5,
/// andning M10, kurvan M18, landskapet M22, Poincaré M21) och bandets egen
/// puls per minut. Bara samlade tal och tider.
public struct NightResult: Equatable, Sendable {
    public var source: NightSource
    /// Sömnperioden (METOD M26); `nil` för en gammal inspelning, vars natt är
    /// hela inspelningen.
    public var sleep: SleepPeriod?
    /// Zonen natten hör till (sekunder öster om Greenwich).
    public var utcOffsetSeconds: Int
    /// Uppvakningsdagen (METOD M14).
    public var wakeDay: WakeDay?
    /// Slagen med utslag (METOD M3), som Poincarémolnet och kurvan ritar dem.
    public var beats: [Beat]
    public var analysis: NightAnalysis.Report
    public var curve: NightCurve.Curve?
    public var landscape: NightLandscape.Profile?
    public var poincarePairs: [Poincare.Pair]
    public var poincare: Poincare.Descriptors?
    /// Bandets egen puls per minut (i14 eller 2A37).
    public var pulse: [PulseMinute]
    /// Hudtemperaturen (METOD M25). K18 över sömnperioden; en gammal
    /// inspelning över sina stilla minuter, och bara om K18 skickades med.
    public var skin: SkinTemperature.Night?
    /// Andelen av periodens minuter som har K18 (METOD M24); `nil` för en
    /// gammal inspelning.
    public var coverage: Double?
    /// Lagren på kurvans tidsaxel (METOD M32): rörelse, hudtemperatur, sömnperioden
    /// och glappen med orsak. Bara för en natt ur K18; en gammal inspelning har
    /// inga och ritas som förut.
    public var layers: NightLayers.Layers?
    /// METOD M37 · BESLUT B45. Natten per 30 s-epok: vaken, lätt, djup och REM. `nil` för en gammal inspelning
    /// (2A37) och när sömnmodellerna inte gick att läsa. `sleep` är då perioden förfinad ur epokerna.
    public var stages: NightStages.Night? = nil
    /// METOD M44 · BESLUT B54. Nattens ljud (nivån, händelserna och vad som följde dem), lagt på av ljudets analys
    /// när natten räknas med en `NightSound.Analyzer`. `nil` för en natt utan ljud: ingen vy visar då något av det.
    public var sound: NightSound? = nil
    /// METOD M55 · BESLUT B70. Ändringen natten räknades med (somnade och vaknade givna); `nil` när perioden är den
    /// hittade. `found` är då perioden som hittades ur rörelsen (METOD M26), `nil` om ingen hittades.
    public var edit: SleepEdit? = nil
    public var found: SleepInterval? = nil

    /// METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden, ur lagrens rörelse (METOD M32); `nil` för en
    /// gammal inspelning (inga lager) och för en natt där för få av periodens minuter har K18.
    public var movementMinutes: Int? {
        layers.flatMap { (l: NightLayers.Layers) -> Int? in NightLayers.movementMinutes(l) }
    }

    static func assemble(source: NightSource, recording: NightRecording, beats: [Beat],
                         sleep: SleepPeriod?, utcOffsetSeconds: Int, wakeDay: WakeDay?,
                         skin: SkinTemperature.Night?, coverage: Double?) -> NightResult {
        let analysis: NightAnalysis.Report = NightAnalysis.analyze(beats: beats)
        let curve: NightCurve.Curve? = NightCurve.make(night: recording, beats: beats, analysis: analysis)
        var landscape: NightLandscape.Profile?
        if let c = curve {
            landscape = NightLandscape.profile(minutes: c.minutes, utcOffsetSeconds: utcOffsetSeconds)
        }
        let pairs: [Poincare.Pair] = Poincare.pairs(beats)
        var day: WakeDay? = wakeDay
        if day == nil, let e = analysis.end {
            day = WakeDay(e, utcOffsetSeconds: utcOffsetSeconds)
        }
        return NightResult(source: source, sleep: sleep, utcOffsetSeconds: utcOffsetSeconds, wakeDay: day,
                           beats: beats, analysis: analysis, curve: curve, landscape: landscape,
                           poincarePairs: pairs, poincare: Poincare.descriptors(pairs),
                           pulse: K18Beats.pulsePerMinute(recording), skin: skin, coverage: coverage)
    }

    /// METOD M28. Den gamla vägen, som appen räknar en inspelning i dag
    /// (`NightReport.make`): hela inspelningen är natten och slagen kommer ur
    /// 2A37. Med `k18` (om bandet också hördes) räknas hudtemperaturen över
    /// inspelningens stilla minuter, som förut.
    public static func fromNotifications(_ night: NightRecording, k18: K18Series? = nil,
                                         utcOffsetSeconds: Int) -> NightResult {
        let beats: [Beat] = RRCleaning.clean(night)
        var skin: SkinTemperature.Night?
        if let serie = k18, let a = night.start, let b = night.end {
            skin = SkinTemperature.night(serie, from: a, to: b)
        }
        return assemble(source: .notification, recording: night, beats: beats, sleep: nil,
                        utcOffsetSeconds: utcOffsetSeconds, wakeDay: nil, skin: skin, coverage: nil)
    }
}

/// METOD M28 · BESLUT B28 · BESLUT B31
/// Natten ur K18: sömnperioden (METOD M26) avgör vilka poster som är natten,
/// och slagen i dem går genom samma kedja som 2A37 gjorde (`K18Beats`).
public enum K18Night {

    /// METOD M28. Natten som slutar på `wakeDay`: dygnsfönstret kl 12–12
    /// (METOD M26), sömnperioden i det, och analysen över perioden. **Utan
    /// sömnperiod finns ingen natt**: en dag utan ett sömnblock på över 30
    /// minuter, eller utan K18, ger `nil`, och ingenting gissas fram ur
    /// dygnet. `startOffsetSeconds`/`endOffsetSeconds` är telefonens zon vid
    /// dygnsfönstrets början och slut.
    ///
    /// BESLUT B125. `now` förs vidare till `SleepDetection.detect`: slutglappet mäts till det tidigaste av
    /// fönstrets slut och `now`; `nil` = fönstrets slut.
    ///
    /// METOD M55 · BESLUT B70. Med `edit` (användaren ändring för dagen) är perioden den givna i stället för den hittade
    /// (`SleepDetection.given`), och resten räknas som vanligt inom den; natten finns då även en dag där ingen period
    /// hittades. En ändring för en annan dag, som avvisas av `SleepEdit.check` mot dygnsfönstret, eller vars period
    /// saknar K18, gäller inte: natten räknas med den hittade perioden som utan ändring.
    public static func analyze(_ series: K18Series, wakeDay: WakeDay,
                               startOffsetSeconds: Int, endOffsetSeconds: Int, edit: SleepEdit? = nil,
                               now: Date? = nil) -> NightResult? {
        let w = SleepDetection.dayWindow(wakeDay: wakeDay, startOffsetSeconds: startOffsetSeconds,
                                         endOffsetSeconds: endOffsetSeconds)
        let found: SleepPeriod? = SleepDetection.detect(series, from: w.from, to: w.to, now: now)
        if let e = edit, e.wakeDay == wakeDay, (try? e.check(window: w.from, to: w.to)) != nil,
           let given = SleepDetection.given(series, from: w.from, to: w.to, onset: e.onset, wake: e.wake) {
            var r: NightResult = analyze(series, sleep: given, utcOffsetSeconds: endOffsetSeconds)
            r.edit = e
            r.found = found.map { (p: SleepPeriod) -> SleepInterval in SleepInterval(start: p.onset, end: p.wake) }
            return r
        }
        guard let sleep = found else { return nil }
        return analyze(series, sleep: sleep, utcOffsetSeconds: endOffsetSeconds)
    }

    /// METOD M28 · METOD M37. Analysen över en sömnperiod som redan är hittad. Slagen är
    /// posterna från insomning till före uppvaknande; stadierna räknas per 30 s-epok ur dem och armens
    /// rörelse, och perioden förfinas ur epokerna (BESLUT B37, B45: sömn, vaken och glapp inom perioden
    /// kommer ur modellen, inte ur 5°-passen). Hudtemperaturen är över den förfinade periodens sömnminuter
    /// (METOD M25); uppvakningsdagen är periodens slut i zonen `utcOffsetSeconds`. Utan stadier (för kort
    /// period, vikterna ej läsbara) gäller perioden som den kom.
    public static func analyze(_ series: K18Series, sleep: SleepPeriod, utcOffsetSeconds: Int) -> NightResult {
        let recording: NightRecording = K18Beats.recording(series, onset: sleep.onset, wake: sleep.wake)
        let beats: [Beat] = RRCleaning.clean(recording)
        let stages: NightStages.Night? = NightStages.estimate(series, onset: sleep.onset, wake: sleep.wake,
                                                              beats: beats)
        var period: SleepPeriod = sleep
        if let n = stages { period = NightStages.refine(sleep, with: n) }
        let skin: SkinTemperature.Night = SkinTemperature.night(series, sleep: period,
                                                                recordingFrom: period.onsetDate,
                                                                recordingTo: period.wakeDate)
        let coverage: Double? = series.coverage(from: period.onsetDate, to: period.wakeDate)?.fraction
        var result: NightResult = NightResult.assemble(source: .k18, recording: recording, beats: beats,
                                                       sleep: period, utcOffsetSeconds: utcOffsetSeconds,
                                                       wakeDay: WakeDay(period.wakeDate, utcOffsetSeconds: utcOffsetSeconds),
                                                       skin: skin, coverage: coverage)
        result.stages = stages
        // METOD M32 · METOD M37. Rörelse, temperatur, sömnperiod och stadier på kurvans tidsaxel.
        if let c = result.curve {
            let lager: NightLayers.Layers = NightLayers.make(curve: c, series: series, sleep: period, stages: stages)
            result.layers = lager
            // METOD M49 · BESLUT B63. Hudtemperaturens form följer med nattens form, för den typiska natten.
            var kurva: NightCurve.Curve = c
            kurva.profile?.skin = NightCurve.skinProfile(lager.minutes, start: c.start, end: c.end)
            // BESLUT B99. Pulsen utanför sömnen, en timme åt var sida om axeln.
            kurva.outside = outsideMinutes(series.records, from: lager.start - outsideSeconds, to: lager.start)
                + outsideMinutes(series.records, from: lager.end, to: lager.end + outsideSeconds)
            result.curve = kurva
        }
        return result
    }

    /// BESLUT B99. Så långt före och efter nattens axel räknas pulsen utanför sömnen.
    public static let outsideSeconds: TimeInterval = 3600

    /// BESLUT B99. Bandets egen puls (K18:s puls, inte slagen) per hel klockminut med början i `from..<to`: medel av
    /// minutens poster med puls över 0. Bandets puls finns även när armen rör sig, där slagen saknas; minuter utan en
    /// enda sådan post (bandet av, glapp) är inte med.
    public static func outsideMinutes(_ records: [K18Record], from: TimeInterval, to: TimeInterval) -> [NightCurve.Minute] {
        let första: Int = Int((from / NightCurve.minuteSeconds).rounded(.up))
        let sista: Int = Int((to / NightCurve.minuteSeconds).rounded(.up))
        guard sista > första else { return [] }
        let minut: Int = Int(NightCurve.minuteSeconds)
        var summa: [Int: (puls: Int, antal: Int)] = [:]
        for r in records where r.pulse > 0 {
            let k: Int = r.time / minut
            guard k >= första, k < sista else { continue }
            let s = summa[k] ?? (0, 0)
            summa[k] = (s.puls + r.pulse, s.antal + 1)
        }
        return summa.keys.sorted().map { (k: Int) -> NightCurve.Minute in
            let s = summa[k] ?? (0, 1)
            return NightCurve.Minute(start: Double(k * minut), heartRate: Double(s.puls) / Double(s.antal),
                                     beats: 0, kept: 0, omitted: 0)
        }
    }
}
