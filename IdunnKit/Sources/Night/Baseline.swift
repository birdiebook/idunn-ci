import Foundation

/// METOD M14
/// Dagen man vaknar, som dagar sedan 1970-01-01 i den zon man vaknade i. Idunns
/// nätter och Whoops dygn möts på den dagen, och baslinjen räknar i den.
/// Räknas för hand ur sekunder och zonens förskjutning, utan Calendar, så att
/// telefonens kalender och zon inte spelar in (som BESLUT B6).
public struct WakeDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var daysSince1970: Int

    public init(daysSince1970: Int) {
        self.daysSince1970 = daysSince1970
    }

    /// Väggklockans dag för ögonblicket `date` i en zon `utcOffsetSeconds` öster om Greenwich.
    public init(_ date: Date, utcOffsetSeconds: Int) {
        let local = date.timeIntervalSince1970 + TimeInterval(utcOffsetSeconds)
        daysSince1970 = Int((local / 86_400).rounded(.down))
    }

    public static func < (a: WakeDay, b: WakeDay) -> Bool { a.daysSince1970 < b.daysSince1970 }

    public static func + (a: WakeDay, days: Int) -> WakeDay { WakeDay(daysSince1970: a.daysSince1970 + days) }
    public static func - (a: WakeDay, days: Int) -> WakeDay { WakeDay(daysSince1970: a.daysSince1970 - days) }

    public var description: String { "dag \(daysSince1970)" }
}

/// METOD M6
/// En natt som baslinjen ser den: dagen man vaknade, ln(RMSSD), vilopulsen
/// och varifrån värdena kommer. Whoops och Idunns nätter hålls isär med
/// `source`, eftersom deras nivå kan skilja (METOD M2).
public struct NightPoint: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case idun
        case whoop
    }

    public var day: WakeDay
    /// ln av RMSSD i millisekunder.
    public var lnRMSSD: Double?
    /// Slag per minut.
    public var restingHeartRate: Double?
    /// METOD M25. Nattens hudtemperatur i °C.
    public var skinTemperature: Double?
    public var source: Source

    public init(day: WakeDay, lnRMSSD: Double?, restingHeartRate: Double?,
                skinTemperature: Double? = nil, source: Source) {
        self.day = day
        self.lnRMSSD = lnRMSSD
        self.restingHeartRate = restingHeartRate
        self.skinTemperature = skinTemperature
        self.source = source
    }

    /// RMSSD i millisekunder; ett värde som inte är över noll ger ingen ln.
    public init(day: WakeDay, rmssd: Double?, restingHeartRate: Double?,
                skinTemperature: Double? = nil, source: Source) {
        self.init(day: day,
                  lnRMSSD: rmssd.flatMap { $0 > 0 ? log($0) : nil },
                  restingHeartRate: restingHeartRate,
                  skinTemperature: skinTemperature,
                  source: source)
    }
}

/// METOD M6 · METOD M7 · BESLUT B11
/// Morgonens läge mot den egna baslinjen: nattens ln(RMSSD) som ett rullande
/// 7-dagarsmedel, jämfört med det egna normalområdet ur de fyra veckorna före
/// veckan (forskningens konvention, BESLUT B12).
/// Vilopulsen står bredvid som stöd. Ingen sammanvägd poäng (METOD M7).
public enum Baseline {

    // MARK: Gränserna — METOD M6 och M7

    /// METOD M6. Det rullande medlet tas över morgonens dag och de sex före
    /// (Plews m.fl. 2012, 2013).
    public static let rollingDays = 7
    /// METOD M6 · METOD M7. Minst så många nätter med värde i varje vecka:
    /// i veckan bakom det rullande medlet och i varje vecka av baslinjen
    /// (Plews m.fl. 2014: "a minimum of 3 … valid data points per week").
    public static let minNightsPerWeek = 3
    /// METOD M7. Baslinjen är så många veckor närmast före veckan som bedöms
    /// (Javaloyes m.fl. 2019, Vesterinen m.fl. 2016: fyra veckor).
    public static let baselineWeeks = 4
    /// METOD M7. Baslinjens längd i dagar, dag −7 till −34 från morgonen.
    public static let historyDays = baselineWeeks * rollingDays
    /// METOD M7. Normalområdet är medel ± så många standardavvikelser
    /// (Javaloyes m.fl. 2019, Vesterinen m.fl. 2016). En konvention, inte ett fynd.
    public static let rangeWidthSD = 0.5
    /// METOD M7 (rättad, BESLUT B69). Normalområdet visas redan med så här många nätter före morgonen, som ett
    /// antagande: bredare ju färre nätter, och smalare mot den vanliga bredden när nätterna blir fler.
    public static let minNightsForRange = 7

    /// METOD M7. Tvåsidig 95-procentig t-kvantil för df = 1…27 (n = 2…28 nätter). Standardtabell.
    static let tQuantile975: [Double] = [
        12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, 2.201, 2.179, 2.160, 2.145,
        2.131, 2.120, 2.110, 2.101, 2.093, 2.086, 2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052,
    ]

    /// METOD M7 (BESLUT B69). Hur mycket bredare bandet är med `nights` nätter än med hela baslinjens
    /// `historyDays`: t-kvantilen för n − 1 frihetsgrader delad med den för 27. 1 vid 28 nätter eller fler,
    /// cirka 1,19 vid 7. **antagande**: en vanlig form för en SD som skattats ur få värden, inte läst ur
    /// Javaloyes eller Vesterinen (de räknar bara med fyra veckor).
    public static func widthFactor(nights: Int) -> Double {
        guard nights < historyDays else { return 1 }
        let df = max(1, nights - 1)
        return tQuantile975[df - 1] / tQuantile975[historyDays - 2]
    }

    // MARK: Resultaten

    public enum Status: String, Equatable, Sendable {
        /// Veckans medel under normalområdet.
        case below
        /// Inom normalområdet, gränserna inräknade.
        case within
        /// Över normalområdet.
        case above
    }

    /// METOD M7. Normalområdet: medel ± `rangeWidthSD` · SD över baslinjens nätter.
    public struct NormalRange: Equatable, Sendable {
        public var mean: Double
        /// Stickprovets standardavvikelse (n − 1).
        public var standardDeviation: Double
        public var nights: Int
        /// METOD M7 (BESLUT B69). Bredden mot hela baslinjens: 1 med 28 nätter, större med färre.
        public var widthFactor: Double = 1
        public var lower: Double { mean - Baseline.rangeWidthSD * widthFactor * standardDeviation }
        public var upper: Double { mean + Baseline.rangeWidthSD * widthFactor * standardDeviation }
        /// METOD M7 (BESLUT B69). Området bygger på färre nätter än hela baslinjen: osäkert, och blir bättre.
        public var isBuilding: Bool { nights < Baseline.historyDays }

        public func status(_ x: Double) -> Status {
            x < lower ? .below : (x > upper ? .above : .within)
        }
    }

    public struct Morning: Equatable, Sendable {
        public var day: WakeDay
        /// Nattens egna värden, om natten finns.
        public var lnRMSSD: Double?
        public var restingHeartRate: Double?
        /// METOD M6. Rullande medel av ln(RMSSD) och antalet nätter bakom det.
        public var rollingLnRMSSD: Double?
        public var rollingNights: Int
        /// METOD M7. ln(RMSSD):s normalområde ur de fyra veckorna före veckan.
        public var range: NormalRange?
        /// METOD M7. Veckans medel mot normalområdet; `nil` när något saknas.
        public var status: Status?
        /// METOD M7. Vilopulsens normalområde, räknat på samma sätt (slag per minut).
        public var restingHeartRateRange: NormalRange?
        /// METOD M25. Nattens hudtemperatur (°C).
        public var skinTemperature: Double?
        /// METOD M25. Hudtemperaturens normalområde, räknat på samma sätt (°C,
        /// aritmetiskt). Inget läge: HRV är huvudvägen (BESLUT B12).
        public var skinTemperatureRange: NormalRange?
    }

    // MARK: Räkningen

    /// METOD M6 · METOD M7. Morgonens läge. Nätterna får komma i vilken ordning
    /// som helst; finns flera för samma dag gäller Idunns före Whoops, och sedan
    /// den sista i listan.
    public static func morning(_ day: WakeDay, nights: [NightPoint]) -> Morning {
        let perDag = onePerDay(nights)
        let vecka = (0..<rollingDays).compactMap { perDag[day - $0]?.lnRMSSD }
        let rolling = vecka.count >= minNightsPerWeek ? Statistics.mean(vecka) : nil

        // METOD M7. Baslinjen slutar dagen före veckan, så att veckan som
        // bedöms inte ingår i sitt eget normalområde.
        let range = normalRange(before: day, perDag) { $0.lnRMSSD }
        let status: Status? = rolling.flatMap { r in range.map { $0.status(r) } }

        return Morning(day: day,
                       lnRMSSD: perDag[day]?.lnRMSSD,
                       restingHeartRate: perDag[day]?.restingHeartRate,
                       rollingLnRMSSD: rolling,
                       rollingNights: vecka.count,
                       range: range,
                       status: status,
                       restingHeartRateRange: normalRange(before: day, perDag) { $0.restingHeartRate },
                       skinTemperature: perDag[day]?.skinTemperature,
                       skinTemperatureRange: normalRange(before: day, perDag) { $0.skinTemperature })
    }

    /// Varje dag som har en natt, i tidsordning.
    public static func mornings(_ nights: [NightPoint]) -> [Morning] {
        onePerDay(nights).keys.sorted().map { morning($0, nights: nights) }
    }

    /// METOD M6 · BESLUT B11. Idunns och Whoops nätter i en serie, med Whoops
    /// flyttade till Idunns nivå: `whoopLnOffset` läggs på Whoops ln(RMSSD) och
    /// `whoopRestingOffset` på Whoops vilopuls (förslag: medelskillnaden
    /// Idunn − Whoop över nätter med båda, `Comparison.summary`) och
    /// `whoopSkinOffset` på Whoops hudtemperatur (METOD M25, förslag:
    /// `levelOffset`, i °C). En dag med båda får Idunns natt. Utan anrop hit
    /// ingår ingen Whoop-natt alls, så den importerade baslinjen förblir
    /// avskiljbar.
    public static func combine(idun: [NightPoint], whoop: [NightPoint],
                               whoopLnOffset: Double = 0, whoopRestingOffset: Double = 0,
                               whoopSkinOffset: Double = 0) -> [NightPoint] {
        let egna = Set(idun.map(\.day))
        let flyttade = whoop.filter { !egna.contains($0.day) }.map { (p: NightPoint) -> NightPoint in
            var q = p
            q.lnRMSSD = p.lnRMSSD.map { $0 + whoopLnOffset }
            q.restingHeartRate = p.restingHeartRate.map { $0 + whoopRestingOffset }
            q.skinTemperature = p.skinTemperature.map { $0 + whoopSkinOffset }
            return q
        }
        return (idun + flyttade).sorted { $0.day < $1.day }
    }

    /// METOD M25 · BESLUT B11. Nivåskillnaden mellan två källors värden per
    /// dag: medelskillnaden Idunn − Whoop över dagar med båda, i måttets
    /// egen enhet. För hudtemperaturen alltså i °C (en temperaturskillnad är
    /// additiv), där HRV räknar sin i ln (METOD M6). `nil` med färre än
    /// `Comparison.minNights` dagar med båda: då finns ingen nivåskillnad
    /// att flytta med.
    public static func levelOffset(idun: [WakeDay: Double], whoop: [WakeDay: Double]) -> Double? {
        let s = Comparison.summary(idun: idun, whoop: whoop)
        return s.nights >= Comparison.minNights ? s.meanDifference : nil
    }

    /// METOD M25. Idunns värden per dag och, för dagar utan Idunn, Whoops
    /// flyttade med `levelOffset`. Saknas nivåskillnaden ingår ingen
    /// Whoop-natt alls: en Whoop-natt utan känd nivå är inte jämförbar.
    public static func levelled(idun: [WakeDay: Double], whoop: [WakeDay: Double]) -> [WakeDay: Double] {
        guard let offset = levelOffset(idun: idun, whoop: whoop) else { return idun }
        var ut = idun
        for (d, v) in whoop where ut[d] == nil { ut[d] = v + offset }
        return ut
    }

    // MARK: Hjälp

    /// METOD M33 · METOD M7 (rättad, BESLUT B69). Hur många nätter med värde som finns före `day` (dag −1 till
    /// −34, högst `historyDays`). Visar hur långt det är kvar till `minNightsForRange` innan normalområdet finns.
    public static func baselineNights(before day: WakeDay, value: (WakeDay) -> Double?) -> Int {
        let n: Int = (1..<(rollingDays + historyDays)).reduce(0) { (n: Int, k: Int) -> Int in
            n + (value(day - k) != nil ? 1 : 0)
        }
        return min(n, historyDays)
    }

    static func onePerDay(_ nights: [NightPoint]) -> [WakeDay: NightPoint] {
        var out: [WakeDay: NightPoint] = [:]
        for p in nights {
            if let finns = out[p.day], finns.source == .idun, p.source != .idun { continue }
            out[p.day] = p
        }
        return out
    }

    /// METOD M7. Normalområdet ur de `baselineWeeks` veckorna före veckan som
    /// slutar `day`. Varje vecka måste ha minst `minNightsPerWeek` nätter med
    /// värde (Plews m.fl. 2014 räknar per vecka); annars gäller reserven i `normalRange(before:value:)`.
    static func normalRange(before day: WakeDay, _ perDag: [WakeDay: NightPoint],
                            _ value: (NightPoint) -> Double?) -> NormalRange? {
        normalRange(before: day) { (d: WakeDay) -> Double? in perDag[d].flatMap(value) }
    }

    /// METOD M7. Samma regel för ett värde per dag, var det än kommer ifrån
    /// (trenderna, METOD M16).
    static func normalRange(before day: WakeDay, value: (WakeDay) -> Double?) -> NormalRange? {
        var x: [Double] = []
        var fullBaslinje = true
        for vecka in 1...baselineWeeks {
            let värden: [Double] = (0..<rollingDays).compactMap { (k: Int) -> Double? in
                value(day - (vecka * rollingDays + k))
            }
            if värden.count < minNightsPerWeek { fullBaslinje = false }
            x.append(contentsOf: värden)
        }
        if !fullBaslinje {
            // METOD M7 (rättad, BESLUT B69). Reserven: nätterna som finns i dag −7 till −34, om de är minst
            // `minNightsForRange`; annars också veckan närmast före morgonen (dag −1 till −6), de senaste
            // `historyDays` nätterna. Färre än `minNightsForRange` nätter ger inget område.
            let utanSenasteVeckan: [Double] = (rollingDays..<(rollingDays + historyDays)).compactMap {
                (k: Int) -> Double? in value(day - k)
            }
            if utanSenasteVeckan.count >= minNightsForRange {
                x = utanSenasteVeckan
            } else {
                let senaste: [Double] = (1..<(rollingDays + historyDays)).compactMap { (k: Int) -> Double? in
                    value(day - k)
                }
                guard senaste.count >= minNightsForRange else { return nil }
                x = Array(senaste.prefix(historyDays))
            }
        }
        guard let m = Statistics.mean(x),
              let sd = Statistics.sampleStandardDeviation(x) else { return nil }
        return NormalRange(mean: m, standardDeviation: sd, nights: x.count, widthFactor: widthFactor(nights: x.count))
    }
}
