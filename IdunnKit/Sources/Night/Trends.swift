import Foundation
import WhoopImport

/// METOD M16 · BESLUT B16
/// Över tid: ett mått i taget, natt för natt, med det rullande 7-dagarsmedlet
/// och, för HRV och vilopuls, det egna normalområdet (METOD M6, M7). Idunns och
/// Whoops nätter hålls isär hela vägen — egna punkter, eget medel och eget
/// normalområde — eftersom deras nivå kan skilja (METOD M2). Visningen ligger i
/// appen; här finns bara serierna.
public enum Trends {

    public typealias Source = NightPoint.Source

    // MARK: Måtten och perioderna

    /// METOD M16. Ett diagram per mått, i den här ordningen.
    public enum Measure: String, CaseIterable, Sendable {
        /// RMSSD i millisekunder (Idunn: nattens medel, BESLUT B13).
        case hrv
        /// Slag per minut (METOD M5).
        case restingHeartRate
        /// BESLUT B34. Slag per minut: medelpulsen över sömnperioden, bredvid vilopulsen (10:e percentilen av fönstren, METOD M5).
        case meanHeartRate
        /// Timmar sömn: Whoops `Asleep duration`, och Idunns sömntid ur
        /// sömnperioden (METOD M26; K18-nätter, inte gamla inspelningar).
        case sleep
        /// METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden (bara Idunns nätter ur K18).
        case movement
        /// METOD M44 · BESLUT B54. Dina snarkminuter per timme sömn (bara nätter med ljud).
        case snoring
        /// METOD M17 · METOD M33. Sömnens regelbundenhet (SRI) över veckan som
        /// slutar dagen: Idunns ur nätternas sömnperioder, Whoops ur exportens
        /// sömnpass, med den vakna tiden spridd över passet (BESLUT B21).
        case regularity
        /// Andetag per minut (METOD M10).
        case breathing
        /// Grader Celsius (METOD M25): Idunns natt ur K18, Whoops ur exporten.
        case skinTemperature
        /// METOD M50 · BESLUT B63. Sömneffektivitet i procent: sömntiden delad med sömnperioden (bara nätter ur K18).
        case efficiency
        /// METOD M52 · BESLUT B63. Minuter i stadierna vaken, lätt, djup och REM under sömnperioden (bara nätter med
        /// stadier). Står här för att Natten visar dem mot ditt normala; Över tid visar djupsömnen.
        case awakeTime
        case lightSleep
        case deepSleep
        case remSleep
        /// METOD M52 · BESLUT B63. Insomning och uppvaknande som minuter efter midnatt på uppvakningsdagen (insomning
        /// före midnatt är negativ). Bara nätter ur K18. Regelbundenheten på Natten visar dem mot ditt normala.
        case sleepOnset
        case sleepWake

        /// METOD M7 · METOD M25 · METOD M42 · METOD M44 · METOD M50 · METOD M52. Normalområdet räknas för HRV,
        /// vilopuls, medelpuls, hudtemperatur, minuter i rörelse, snarkminuter, effektivitet, stadiernas minuter och
        /// insomning och uppvaknande, som i `Baseline`.
        public var hasRange: Bool {
            switch self {
            case .hrv, .restingHeartRate, .meanHeartRate, .skinTemperature, .movement, .snoring, .efficiency,
                 .awakeTime, .lightSleep, .deepSleep, .remSleep, .sleepOnset, .sleepWake:
                return true
            case .sleep, .regularity, .breathing:
                return false
            }
        }
        /// METOD M7. Normalområdets form är forskningens (Javaloyes, Vesterinen)
        /// bara för HRV och vilopuls; för de andra måtten är samma form ett antagande.
        public var rangeFollowsResearch: Bool { self == .hrv || self == .restingHeartRate }
        /// METOD M7. Bara HRV får ett läge (under, inom, över); vilopulsen står bredvid.
        public var hasStatus: Bool { self == .hrv }
        /// METOD M6. HRV räknas i ln(RMSSD) och visas i millisekunder.
        var isLogarithmic: Bool { self == .hrv }
        /// METOD M17. Värdet täcker redan en hel vecka (SRI), så det får inget
        /// 7-dagarsmedel ovanpå: linjen är värdena själva.
        public var isWeekly: Bool { self == .regularity }

        func forward(_ x: Double) -> Double { isLogarithmic ? log(x) : x }
        func inverse(_ x: Double) -> Double { isLogarithmic ? exp(x) : x }
        /// Ett värde som inte går att räkna med hoppas över: ej ändligt, eller
        /// noll och under för ett logaritmiskt mått.
        func accepts(_ x: Double) -> Bool { x.isFinite && (!isLogarithmic || x > 0) }
    }

    /// METOD M16. Hur långt bakåt diagrammen visar, räknat från senaste natten.
    public enum Period: String, CaseIterable, Sendable {
        case days30
        case days90
        case all

        /// Antal dagar, sista natten inräknad; `nil` för allt.
        public var days: Int? {
            switch self {
            case .days30: return 30
            case .days90: return 90
            case .all: return nil
            }
        }
    }

    // MARK: Indata

    /// METOD M14 · METOD M16. En inspelning med färre giltiga 5-minutersfönster
    /// än så (3 timmar) är ett prov, ingen natt.
    public static let minValidWindows = 36

    /// En av Idunns nätter som trenderna ser den: bara nattens samlade tal.
    public struct IdunNight: Equatable, Sendable {
        public var day: WakeDay
        public var validWindows: Int
        /// METOD M4 · BESLUT B13. Nattens medel av fönstrens RMSSD, ms.
        public var rmssd: Double?
        public var restingHeartRate: Double?
        /// BESLUT B34. Medelpulsen över sömnperioden; `nil` för en gammal inspelning, som inte har någon period.
        public var meanHeartRate: Double?
        public var breathsPerMinute: Double?
        /// METOD M42 · BESLUT B51. Minuter i rörelse under sömnperioden; `nil` för en gammal inspelning och för
        /// en natt där K18 täckte perioden för lite.
        public var movementMinutes: Int?
        /// METOD M44 · BESLUT B54. Dina snarkminuter per timme sömn; `nil` för en natt utan ljud (och när ljudet
        /// täckte för lite av sömnen).
        public var snoringPerHour: Double?
        /// METOD M25. Nattens hudtemperatur i °C; `nil` när K18 inte täckte
        /// natten tillräckligt.
        public var skinTemperature: Double?
        /// METOD M4 · BESLUT B13. Den Whoop-lika kandidaten, för jämförelsen.
        public var rmssdWhoopLike: Double?
        /// METOD M26. Idunns sömntid i timmar: sömnperioden utan vakna stunder
        /// och glapp. `nil` för en gammal inspelning, som inte har någon period.
        public var sleepHours: Double?
        /// METOD M33. Sömnperioden som ett pass för regelbundenheten (SRI).
        /// `nil` för en gammal inspelning, som inte har någon period.
        public var sleepEpisode: Regularity.Episode?
        /// METOD M28. Varifrån slagen kom. K18 går före en gammal inspelning
        /// samma dag (`idunPerDay`).
        public var source: NightSource
        /// Anroparens eget id (appens sammanfattning), så att vyn hittar tillbaka
        /// till natten som valdes. Räknas inte med i valet.
        public var id: String
        /// METOD M50 · BESLUT B63. Sömneffektivitet i procent (0–100): sömntiden delad med sömnperioden; `nil` för
        /// en gammal inspelning.
        public var efficiency: Double?
        /// METOD M50. Antal vakna stunder i sömnperioden; `nil` för en gammal inspelning.
        public var wakeBouts: Int?
        /// METOD M52. Minuter i vaken, lätt, djup och REM; `nil` utan stadier.
        public var awakeMinutes: Double?
        public var lightMinutes: Double?
        public var deepMinutes: Double?
        public var remMinutes: Double?
        /// METOD M52. Insomning och uppvaknande, minuter efter midnatt på uppvakningsdagen (`Trends.clockMinutes`).
        public var onsetMinutes: Double?
        public var wakeMinutes: Double?

        public init(day: WakeDay, validWindows: Int, rmssd: Double?,
                    restingHeartRate: Double?, breathsPerMinute: Double?,
                    skinTemperature: Double? = nil, rmssdWhoopLike: Double? = nil,
                    sleepHours: Double? = nil, sleepEpisode: Regularity.Episode? = nil,
                    meanHeartRate: Double? = nil, movementMinutes: Int? = nil, snoringPerHour: Double? = nil,
                    source: NightSource = .notification, id: String = "",
                    efficiency: Double? = nil, wakeBouts: Int? = nil, awakeMinutes: Double? = nil,
                    lightMinutes: Double? = nil, deepMinutes: Double? = nil, remMinutes: Double? = nil,
                    onsetMinutes: Double? = nil, wakeMinutes: Double? = nil) {
            self.day = day
            self.validWindows = validWindows
            self.rmssd = rmssd
            self.restingHeartRate = restingHeartRate
            self.breathsPerMinute = breathsPerMinute
            self.skinTemperature = skinTemperature
            self.rmssdWhoopLike = rmssdWhoopLike
            self.sleepHours = sleepHours
            self.sleepEpisode = sleepEpisode
            self.meanHeartRate = meanHeartRate
            self.movementMinutes = movementMinutes
            self.snoringPerHour = snoringPerHour
            self.source = source
            self.id = id
            self.efficiency = efficiency
            self.wakeBouts = wakeBouts
            self.awakeMinutes = awakeMinutes
            self.lightMinutes = lightMinutes
            self.deepMinutes = deepMinutes
            self.remMinutes = remMinutes
            self.onsetMinutes = onsetMinutes
            self.wakeMinutes = wakeMinutes
        }
    }

    /// METOD M52 · BESLUT B63. Ett klockslag som minuter efter midnatt på uppvakningsdagen `day`, i zonen
    /// `utcOffsetSeconds`: 06:58 är 418 och 22:57 kvällen före är −63. Samma tidsaxel över midnatt, så att ett
    /// medel och ett normalområde av insomningstider fungerar. Räknat för hand ur sekunder, som `WakeDay`.
    public static func clockMinutes(_ t: Date, day: WakeDay, utcOffsetSeconds: Int) -> Double {
        (t.timeIntervalSince1970 + Double(utcOffsetSeconds) - Double(day.daysSince1970) * 86_400) / 60
    }

    /// METOD M33. Sömnperioden som ett pass för regelbundenheten: bara en natt
    /// ur K18 har en period (METOD M26); en gammal inspelning ger `nil`.
    public static func sleepEpisode(source: NightSource, start: Date?, end: Date?,
                                    utcOffsetSeconds: Int, sleepMinutes: Double?,
                                    coverage: Double? = nil) -> Regularity.Episode? {
        guard source == .k18, let a = start, let b = end, let m = sleepMinutes else { return nil }
        return Regularity.Episode.idun(onset: a, wake: b, utcOffsetSeconds: utcOffsetSeconds,
                                       sleepMinutes: m, coverage: coverage)
    }

    /// Ett värde per dag och mått, för en källa.
    public typealias Values = [Measure: [WakeDay: Double]]

    /// METOD M14 · METOD M28. En natt per uppvakningsdag: nätter under
    /// `minValidWindows` hoppas över, K18 går före en gammal inspelning samma
    /// dag, och av flera från samma källa gäller den med flest giltiga
    /// fönster (vid lika den första).
    public static func idunPerDay(_ nights: [IdunNight]) -> [WakeDay: IdunNight] {
        var ut: [WakeDay: IdunNight] = [:]
        for n in nights where n.validWindows >= minValidWindows {
            if let finns = ut[n.day] {
                if finns.source == .k18 && n.source != .k18 { continue }
                if finns.source == n.source && finns.validWindows >= n.validWindows { continue }
            }
            ut[n.day] = n
        }
        return ut
    }

    /// METOD M16 · METOD M25 · METOD M26 · METOD M33 · METOD M42 · METOD M44. Idunns värden per dag:
    /// HRV, vilopuls, medelpuls, andning, hudtemperatur, sömntid, minuter i rörelse, snarkminuter och regelbundenheten
    /// (SRI över veckan som slutar dagen, ur nätternas sömnperioder).
    public static func idunValues(_ nights: [IdunNight]) -> Values {
        let perDag = idunPerDay(nights)
        let pass: [Regularity.Episode] = perDag.values.compactMap { $0.sleepEpisode }
        // METOD M42. Minuterna som tal per dag; en natt utan tal har ingen punkt.
        let rörelse: [WakeDay: Double] = perDag.compactMapValues { (n: IdunNight) -> Double? in
            n.movementMinutes.map { (m: Int) -> Double in Double(m) }
        }
        var ut: Values = [
            .regularity: Regularity.rolling(pass),
            .hrv: perDag.compactMapValues(\.rmssd),
            .restingHeartRate: perDag.compactMapValues(\.restingHeartRate),
            .meanHeartRate: perDag.compactMapValues(\.meanHeartRate),
            .movement: rörelse,
            .snoring: perDag.compactMapValues(\.snoringPerHour),
            .breathing: perDag.compactMapValues(\.breathsPerMinute),
            .skinTemperature: perDag.compactMapValues(\.skinTemperature),
            .sleep: perDag.compactMapValues(\.sleepHours),
        ]
        // METOD M50 · METOD M52. Effektiviteten, stadiernas minuter och klockslagen; en natt utan tal har ingen punkt.
        ut[.efficiency] = perDag.compactMapValues(\.efficiency)
        ut[.awakeTime] = perDag.compactMapValues(\.awakeMinutes)
        ut[.lightSleep] = perDag.compactMapValues(\.lightMinutes)
        ut[.deepSleep] = perDag.compactMapValues(\.deepMinutes)
        ut[.remSleep] = perDag.compactMapValues(\.remMinutes)
        ut[.sleepOnset] = perDag.compactMapValues(\.onsetMinutes)
        ut[.sleepWake] = perDag.compactMapValues(\.wakeMinutes)
        return ut
    }

    /// METOD M16. Whoops värden per uppvakningsdag (METOD M14), ur dygnen och
    /// sömnpassen. Regelbundenheten i varianten `regularity`, förvalt den med
    /// den vakna tiden spridd över passet (METOD M17, BESLUT B21).
    public static func whoopValues(cycles: [Cycle], sleeps: [Sleep],
                                   regularity: Regularity.Variant = Regularity.defaultVariant) -> Values {
        [
            .hrv: WhoopReference.byWakeDay(cycles) { c in c.hrv.map { Double($0) } },
            .restingHeartRate: WhoopReference.byWakeDay(cycles) { c in c.restingHeartRate.map { Double($0) } },
            .sleep: sleepHours(sleeps),
            .regularity: Regularity.rolling(sleeps, variant: regularity),
            .breathing: WhoopReference.byWakeDay(cycles) { $0.respiratoryRate },
            .skinTemperature: WhoopReference.byWakeDay(cycles) { $0.skinTempCelsius },
        ]
    }

    /// METOD M16. Timmar sömn per uppvakningsdag: summan av `Asleep duration`
    /// för passen som inte är tupplurar och vaknar den dagen, i passets zon.
    /// Pass utan längd räknas inte; en dag utan något pass med längd saknas.
    public static func sleepHours(_ sleeps: [Sleep]) -> [WakeDay: Double] {
        var minuter: [WakeDay: Int] = [:]
        for s in sleeps where !s.isNap {
            guard let m = s.asleepMinutes else { continue }
            minuter[WakeDay(s.wake, utcOffsetSeconds: s.utcOffsetSeconds), default: 0] += m
        }
        return minuter.mapValues { (m: Int) -> Double in Double(m) / 60 }
    }

    // MARK: Serien

    /// En natt i diagrammet.
    public struct Point: Equatable, Identifiable, Sendable {
        public var day: WakeDay
        public var value: Double
        public var source: Source
        public var id: String { "\(source.rawValue)-\(day.daysSince1970)" }
    }

    /// METOD M6. Det rullande 7-dagarsmedlet en dag. Dagar i följd hör till
    /// samma `segment`; där medlet saknas bryts linjen och nästa segment börjar.
    public struct Rolling: Equatable, Identifiable, Sendable {
        public var day: WakeDay
        public var value: Double
        public var source: Source
        public var segment: Int
        /// METOD M7. Medlet mot normalområdet samma dag; bara för HRV.
        public var status: Baseline.Status?
        public var id: String { "\(source.rawValue)-\(day.daysSince1970)" }
        /// En linje per källa och segment.
        public var line: String { "\(source.rawValue)-\(segment)" }
    }

    /// METOD M7. Normalområdet en dag, i måttets enhet.
    public struct Band: Equatable, Identifiable, Sendable {
        public var day: WakeDay
        public var lower: Double
        public var upper: Double
        public var source: Source
        public var id: String { "\(source.rawValue)-\(day.daysSince1970)" }
    }

    /// Senaste 7-dagarsmedlet i serien.
    public struct Latest: Equatable, Sendable {
        public var day: WakeDay
        public var value: Double
        public var source: Source
        public var status: Baseline.Status?
    }

    /// En källas värden en dag, för avläsningen.
    public struct Reading: Equatable, Sendable {
        public var source: Source
        public var night: Double?
        public var rolling: Double?
    }

    public struct Series: Equatable, Sendable {
        public var measure: Measure
        /// Nätterna, i dagordning (Idunn före Whoop samma dag).
        public var points: [Point]
        public var rolling: [Rolling]
        public var bands: [Band]

        /// Källorna som har minst en natt, Idunn först.
        public var sources: [Source] {
            Source.order.filter { s in points.contains { $0.source == s } }
        }

        /// METOD M16. Serien inom dagarna `days`. Medel och normalområden är
        /// räknade på hela historiken, så periodens första dagar har sina.
        public func clipped(to days: ClosedRange<WakeDay>) -> Series {
            Series(measure: measure,
                   points: points.filter { days.contains($0.day) },
                   rolling: rolling.filter { days.contains($0.day) },
                   bands: bands.filter { days.contains($0.day) })
        }

        /// METOD M16. Senaste dagen med ett 7-dagarsmedel. Har båda källorna
        /// ett den dagen gäller Idunns (som i `Baseline`).
        public var latest: Latest? {
            var bäst: Rolling?
            for r in rolling {
                guard let b = bäst else { bäst = r; continue }
                if r.day > b.day || (r.day == b.day && r.source == .idun) { bäst = r }
            }
            return bäst.map { Latest(day: $0.day, value: $0.value, source: $0.source, status: $0.status) }
        }

        /// En dags värden per källa, Idunn först. Källor utan något den dagen hoppas över.
        public func readings(on day: WakeDay) -> [Reading] {
            Source.order.compactMap { (s: Source) -> Reading? in
                let natt = points.first { $0.day == day && $0.source == s }?.value
                let medel = rolling.first { $0.day == day && $0.source == s }?.value
                return natt == nil && medel == nil ? nil : Reading(source: s, night: natt, rolling: medel)
            }
        }
    }

    // MARK: Räkningen

    /// METOD M16. Alla måtten, i diagrammens ordning.
    public static func series(idun: Values, whoop: Values) -> [Series] {
        Measure.allCases.map { series($0, idun: idun[$0] ?? [:], whoop: whoop[$0] ?? [:]) }
    }

    /// METOD M16. Ett mått: nätterna, 7-dagarsmedlet och normalområdet per
    /// källa, var för sig.
    public static func series(_ measure: Measure, idun: [WakeDay: Double], whoop: [WakeDay: Double]) -> Series {
        var points: [Point] = []
        var rolling: [Rolling] = []
        var bands: [Band] = []
        for (source, values) in [(Source.idun, idun), (Source.whoop, whoop)] {
            let giltiga = values.filter { measure.accepts($0.value) }
            let x = giltiga.mapValues(measure.forward)
            guard let first = x.keys.min(), let last = x.keys.max() else { continue }
            for d in giltiga.keys.sorted() {
                points.append(Point(day: d, value: giltiga[d]!, source: source))
            }
            var segment = 0
            var föregående = false
            var d = first
            while d <= last {
                // METOD M6. Medlet över dagen och de sex före, med minst 3 nätter.
                // METOD M17. Ett veckomått (SRI) är redan en vecka: linjen är värdet.
                let vecka: [Double] = (0..<Baseline.rollingDays).compactMap { (k: Int) -> Double? in x[d - k] }
                let medel: Double?
                if measure.isWeekly {
                    medel = x[d]
                } else {
                    medel = vecka.count >= Baseline.minNightsPerWeek ? Statistics.mean(vecka) : nil
                }
                // METOD M7. Normalområdet ur de fyra veckorna före veckan.
                var område: Baseline.NormalRange? = nil
                if measure.hasRange {
                    område = Baseline.normalRange(before: d, value: { (e: WakeDay) -> Double? in x[e] })
                }
                if let o = område {
                    bands.append(Band(day: d, lower: measure.inverse(o.lower),
                                      upper: measure.inverse(o.upper), source: source))
                }
                if let m = medel {
                    if !föregående { segment += 1 }
                    let läge: Baseline.Status? = measure.hasStatus ? område.map { $0.status(m) } : nil
                    rolling.append(Rolling(day: d, value: measure.inverse(m), source: source,
                                           segment: segment, status: läge))
                }
                föregående = medel != nil
                d = d + 1
            }
        }
        let ordning: (WakeDay, Source, WakeDay, Source) -> Bool = { a, sa, b, sb in
            a != b ? a < b : Source.order.firstIndex(of: sa)! < Source.order.firstIndex(of: sb)!
        }
        return Series(measure: measure,
                      points: points.sorted { ordning($0.day, $0.source, $1.day, $1.source) },
                      rolling: rolling.sorted { ordning($0.day, $0.source, $1.day, $1.source) },
                      bands: bands.sorted { ordning($0.day, $0.source, $1.day, $1.source) })
    }

    /// METOD M16. Dagarna som perioden visar: från så många dagar bakåt till
    /// senaste natten i någon serie, eller från den första för allt. `nil` utan nätter.
    public static func window(_ period: Period, _ series: [Series]) -> ClosedRange<WakeDay>? {
        let dagar = series.flatMap { $0.points.map(\.day) }
        guard let first = dagar.min(), let last = dagar.max() else { return nil }
        guard let n = period.days else { return first...last }
        return (last - (n - 1))...last
    }
}

// MARK: Över tid: veckan, månaden och halvåret (METOD M51 · BESLUT B63)

extension Trends {

    /// METOD M51. Trendvyns perioder: V (7 dagar), M (30) och 6M (182 dagar). **Antagande**: längderna är skissens (B62).
    /// Sedan B82 är varje punkt en natt, också i 6M, där dagarna ritas som en svag linje under månadernas medel.
    public enum Span: String, CaseIterable, Sendable {
        case week
        case month
        case halfYear

        /// Antal dagar, sista natten inräknad.
        public var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .halfYear: return 182
            }
        }

        /// Antal punkter i diagrammet: en per dag.
        public var buckets: Int { days }
    }

    /// METOD M51. En punkt i perioden: en natt. `value` är `nil` utan natt. Bandet är normalområdet den dagen.
    public struct Bucket: Equatable, Sendable {
        public var day: WakeDay
        public var value: Double?
        public var lower: Double?
        public var upper: Double?
        public var nights: Int
    }

    /// METOD M51. Ett mått över en period: punkterna, periodens medel och ändringen mot perioden före.
    public struct Overview: Equatable, Sendable {
        public var measure: Measure
        public var span: Span
        /// Periodens första och sista dag.
        public var first: WakeDay
        public var end: WakeDay
        public var buckets: [Bucket]
        /// Medel över periodens nätter; `nil` med färre än `Baseline.minNightsPerWeek` nätter.
        public var mean: Double?
        /// Medel över lika många dagar närmast före perioden, samma regel.
        public var previousMean: Double?
        /// Medlet mot medlet före, som andel av det förras belopp (0,05 är fem procent över); `nil` när något av
        /// medlen saknas eller det förra är noll.
        public var change: Double?
        /// Antal nätter i perioden.
        public var nights: Int
        /// METOD M51 · BESLUT B82. Kalendermånaderna som perioden rör, äldst först, med medel och ändringen mot
        /// månaden före; bara i 6M (tom i V och M).
        public var months: [MonthMean]
    }

    /// METOD M51 · BESLUT B82. En kalendermånad i 6M: dagarna den täcker i perioden, medlet av månadens nätter fram
    /// till periodens slut och ändringen mot kalendermånaden före.
    public struct MonthMean: Equatable, Sendable {
        /// Månadens första dag i kalendern (kan ligga före perioden).
        public var monthStart: WakeDay
        /// Månadens första och sista dag inom perioden.
        public var first: WakeDay
        public var last: WakeDay
        /// Medlet av månadens nätter fram till periodens slut, också dagarna före perioden; `nil` med färre än
        /// `Baseline.minNightsPerWeek` nätter.
        public var mean: Double?
        public var nights: Int
        /// Medlet mot kalendermånaden före (samma regel), som andel av det förras belopp; `nil` när något medel
        /// saknas eller det förra är noll.
        public var change: Double?
    }

    /// METOD M51. Sista dagen med en natt i någon av serierna, för en gemensam periodslut.
    public static func lastDay(_ series: [Series]) -> WakeDay? {
        series.flatMap { (s: Series) -> [WakeDay] in s.points.map(\.day) }.max()
    }

    /// METOD M51. Första dagen med en natt i någon av serierna: längre bakåt än så går det inte att bläddra.
    public static func firstDay(_ series: [Series]) -> WakeDay? {
        series.flatMap { (s: Series) -> [WakeDay] in s.points.map(\.day) }.min()
    }

    /// METOD M51 · BESLUT B82. Periodens slut ett steg bakåt (`by: -1`) eller framåt (`by: 1`): slutet flyttas en hel
    /// period. Framåt stannar steget vid den sista natten `last` (ett slut mellan två perioder kommer dit i ett steg);
    /// `nil` när slutet redan är där, eller när steget bakåt ger en period som slutar före den första natten `first`.
    public static func stepped(end: WakeDay, span: Span, by steps: Int, first: WakeDay, last: WakeDay) -> WakeDay? {
        let ny: WakeDay = end + steps * span.days
        if steps > 0 {
            if end >= last { return nil }
            return ny > last ? last : ny
        }
        if steps < 0 && ny < first { return nil }
        return ny
    }

    /// METOD M51 · BESLUT B82. Kalendermånaderna som dagarna `first`…`end` rör, med varje månads medel (nätterna i
    /// månaden fram till `end`, minst `Baseline.minNightsPerWeek`) och ändringen mot månaden före. Månaderna räknas
    /// i den gregorianska kalendern direkt ur dagnumret (`WakeDay.monthStart`), som `WakeDay` räknas ur sekunder.
    public static func months(_ series: Series, first: WakeDay, end: WakeDay) -> [MonthMean] {
        var värden: [WakeDay: Double] = [:]
        for p in series.points where p.source == .idun && p.day <= end { värden[p.day] = p.value }
        func medel(_ start: WakeDay) -> (mean: Double?, nights: Int) {
            let slut: WakeDay = min(start.nextMonthStart - 1, end)
            var x: [Double] = []
            var d: WakeDay = start
            while d <= slut {
                if let v = värden[d] { x.append(v) }
                d = d + 1
            }
            return (x.count >= Baseline.minNightsPerWeek ? Statistics.mean(x) : nil, x.count)
        }
        var ut: [MonthMean] = []
        guard first <= end else { return ut }
        var start: WakeDay = first.monthStart
        while start <= end {
            let nu = medel(start)
            let före = medel((start - 1).monthStart)
            var ändring: Double? = nil
            if let a = nu.mean, let b = före.mean, b != 0 { ändring = (a - b) / abs(b) }
            ut.append(MonthMean(monthStart: start, first: max(start, first), last: min(start.nextMonthStart - 1, end),
                                mean: nu.mean, nights: nu.nights, change: ändring))
            start = start.nextMonthStart
        }
        return ut
    }

    /// METOD M51 · BESLUT B63 · BESLUT B82. Måttet `series` över perioden `span` som slutar `end`: en punkt per dag,
    /// periodens medel och ändringen mot perioden före (Idunns nätter, aritmetiskt, också för HRV: det är det som visas),
    /// och i 6M kalendermånaderna (`months`).
    public static func overview(_ series: Series, span: Span, end: WakeDay) -> Overview {
        var värden: [WakeDay: Double] = [:]
        for p in series.points where p.source == .idun { värden[p.day] = p.value }
        var band: [WakeDay: Band] = [:]
        for b in series.bands where b.source == .idun { band[b.day] = b }
        let dagar: Int = span.days
        let första: WakeDay = end - (dagar - 1)

        var punkter: [Bucket] = []
        for k in 0..<dagar {
            let d: WakeDay = första + k
            let v: Double? = värden[d]
            punkter.append(Bucket(day: d, value: v, lower: band[d]?.lower, upper: band[d]?.upper, nights: v == nil ? 0 : 1))
        }

        func medel(_ från: WakeDay, _ till: WakeDay) -> (mean: Double?, nights: Int) {
            var x: [Double] = []
            var d: WakeDay = från
            while d <= till {
                if let v = värden[d] { x.append(v) }
                d = d + 1
            }
            return (x.count >= Baseline.minNightsPerWeek ? Statistics.mean(x) : nil, x.count)
        }
        let nu = medel(första, end)
        let före = medel(första - dagar, första - 1)
        var ändring: Double? = nil
        if let a = nu.mean, let b = före.mean, b != 0 { ändring = (a - b) / abs(b) }
        let månader: [MonthMean] = span == .halfYear ? months(series, first: första, end: end) : []
        return Overview(measure: series.measure, span: span, first: första, end: end, buckets: punkter,
                        mean: nu.mean, previousMean: före.mean, change: ändring, nights: nu.nights, months: månader)
    }
}

extension NightPoint.Source {
    /// Idunn först: appens egna nätter går före Whoops (som i `Baseline`).
    public static let order: [NightPoint.Source] = [.idun, .whoop]
}

extension WakeDay {
    /// METOD M16. Dagen som ett ögonblick för en tidsaxel: mitt på dagen i UTC,
    /// så att den hamnar på rätt datum i varje zon inom ±11 timmar.
    public var noonUTC: Date {
        Date(timeIntervalSince1970: Double(daysSince1970) * 86_400 + 43_200)
    }

    /// Dagens början i UTC; nästa dags början är dagens slut.
    public var startUTC: Date {
        Date(timeIntervalSince1970: Double(daysSince1970) * 86_400)
    }

    /// METOD M16. Dagen närmast ett ögonblick på tidsaxeln (en markering i diagrammet).
    public init(nearest date: Date) {
        self.init(date, utcOffsetSeconds: 0)
    }

    /// METOD M51. År, månad (1–12) och dag i den gregorianska kalendern, räknat för hand ur dagnumret (Howard Hinnants
    /// `civil_from_days`), så att telefonens kalender och zon inte spelar in.
    public var civil: (year: Int, month: Int, day: Int) {
        let z: Int = daysSince1970 + 719_468
        let era: Int = (z >= 0 ? z : z - 146_096) / 146_097
        let doe: Int = z - era * 146_097
        let yoe: Int = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy: Int = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp: Int = (5 * doy + 2) / 153
        let d: Int = doy - (153 * mp + 2) / 5 + 1
        let m: Int = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    /// METOD M51. Första dagen i dagens kalendermånad.
    public var monthStart: WakeDay { self - (civil.day - 1) }

    /// METOD M51. Första dagen i nästa kalendermånad (en månad har högst 31 dagar).
    public var nextMonthStart: WakeDay { (monthStart + 31).monthStart }
}
