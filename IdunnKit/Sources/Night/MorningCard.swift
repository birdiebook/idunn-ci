import Foundation

/// METOD M19 · METOD M33 · BESLUT B16 · BESLUT B40
/// Morgonkortet: en morgon, ett mått per rad, som en prick på ett band — det
/// egna normalområdet. Vardagens kort (`days`) räknas bara ur Idunns nätter
/// (BESLUT B40): ingen Whoop-natt i raderna eller i baslinjen. `rows(idun:whoop:)`
/// med båda källorna finns kvar för jämförelsen; där har varje rad sin källa
/// och källorna blandas aldrig i samma rad (BESLUT B16).
///
/// Bandet är `Baseline`:s normalområde (BESLUT B12, METOD M7): medel ± 0,5 SD
/// över de fyra veckorna före veckan, minst 3 nätter per vecka. För HRV och
/// vilopuls är det forskningens konvention; för andning, sömn och
/// regelbundenhet och minuter i rörelse (METOD M42) är samma form ett antagande (METOD M19).
/// Bara HRV får ett läge (under, inom, över), som i `Baseline`.
public enum MorningCard {

    public typealias Source = NightPoint.Source

    /// METOD M19. Måtten på kortet, i den här ordningen.
    public static let measures: [Trends.Measure] = [.hrv, .restingHeartRate, .meanHeartRate, .breathing,
                                                     .skinTemperature, .sleep, .movement, .regularity]

    /// METOD M19. Axeln bakom bandet spänner över källans nätter så här många
    /// dagar bakåt (baslinjens fyra veckor och veckan som bedöms).
    public static let trackDays = Baseline.historyDays + Baseline.rollingDays

    public struct Row: Equatable, Identifiable, Sendable {
        public var measure: Trends.Measure
        public var source: Source
        /// Natten raden visar.
        public var day: WakeDay
        public var value: Double
        /// METOD M7 · METOD M19. Normalområdet i måttets enhet; `nil` innan det
        /// finns fyra veckor.
        public var range: ClosedRange<Double>?
        /// Axelns spann: källans nätter de senaste `trackDays` dagarna, området
        /// och nattens värde.
        public var track: ClosedRange<Double>
        /// METOD M6. 7-dagarsmedlet som läget gäller (bara HRV).
        public var rolling: Double?
        /// METOD M7. Läget, bara för HRV.
        public var status: Baseline.Status?
        /// METOD M25. Normalområdets medel i måttets enhet; `nil` utan område.
        public var reference: Double? = nil
        /// METOD M25. Normalområdet bygger delvis på Whoops nätter flyttade till
        /// Idunns nivå (bara hudtemperaturen, bara en Idunn-rad).
        public var usesWhoopHistory = false
        /// METOD M33 · METOD M7 (BESLUT B69). Hur många nätter som finns före morgonen (högst
        /// `Baseline.historyDays`); visar hur långt det är kvar till `Baseline.minNightsForRange`.
        public var baselineNights = 0
        /// METOD M7 (BESLUT B69). Området finns men bygger på färre nätter än hela baslinjen: osäkert, och
        /// blir bättre. Appen ritar bandet då som ett utkast (streckad kant, ljusare), utan text.
        public var rangeBuilding = false

        public var id: String { measure.rawValue }

        /// METOD M19. Var ett värde ligger på axeln, 0 till 1.
        public func position(_ x: Double) -> Double {
            let bredd = track.upperBound - track.lowerBound
            guard bredd > 0 else { return 0.5 }
            return min(1, max(0, (x - track.lowerBound) / bredd))
        }

        /// METOD M25. Nattens avvikelse från normalområdets medel, i måttets
        /// enhet (°C för hudtemperaturen); `nil` utan område.
        public var deviation: Double? { reference.map { value - $0 } }

        /// METOD M19. Normalområdet är forskningens (HRV och vilopuls), eller
        /// samma form som ett antagande (de andra).
        public var rangeIsAssumption: Bool { !measure.rangeFollowsResearch }
    }

    /// METOD M19. En rad per mått som har en natt i någon källa.
    public static func rows(idun: Trends.Values, whoop: Trends.Values) -> [Row] {
        measures.compactMap { (m: Trends.Measure) -> Row? in
            row(m, idun: idun[m] ?? [:], whoop: whoop[m] ?? [:])
        }
    }

    /// METOD M33 · BESLUT B40. En morgon på kortet: raderna för dagen och, innan
    /// HRV:s normalområde finns, hur långt baslinjen kommit.
    public struct Day: Equatable, Identifiable, Sendable {
        public var day: WakeDay
        public var rows: [Row]
        /// METOD M33 · BESLUT B69. Antal nätter före morgonen (av `Baseline.minNightsForRange`) så
        /// länge HRV saknar normalområde; `nil` när området finns, och när
        /// kortet inte har något mått med område.
        public var baselineBuilding: Int?
        /// METOD M44 · BESLUT B54. Dina snarkminuter per timme sömn, bara när natten ligger utanför ditt normalområde
        /// (`MorningCard.unusualSnoring`). Står utanför `rows`: raderna är måtten som alltid står på kortet.
        public var snoring: Row? = nil
        public var id: Int { day.daysSince1970 }
    }

    /// METOD M33 · BESLUT B40. Morgonen `day` ur Idunns nätter: varje mått med
    /// natten den dagen, eller sin senaste natt dessförinnan (en äldre natt visar
    /// sitt eget datum). Aldrig något från Whoop, och aldrig något efter dagen.
    public static func day(_ day: WakeDay, idun: Trends.Values) -> Day {
        let rader: [Row] = measures.compactMap { (m: Trends.Measure) -> Row? in
            row(m, idun: idun[m] ?? [:], whoop: [:], upTo: day)
        }
        // HRV är huvudvägen; saknas den räcker ett annat mått med område.
        let styrande: Row? = rader.first { $0.measure == .hrv } ?? rader.first { $0.measure.hasRange }
        let bygger: Int? = styrande.flatMap { (r: Row) -> Int? in r.range == nil ? r.baselineNights : nil }
        return Day(day: day, rows: rader, baselineBuilding: bygger,
                   snoring: unusualSnoring(day, idun: idun[.snoring] ?? [:]))
    }

    /// METOD M44 · BESLUT B54. Morgonens snarkrad: dina snarkminuter per timme sömn den natten, men bara när de
    /// ligger utanför ditt normalområde (M7: medel ± 0,5 SD över de fyra veckorna före veckan, minst 3 nätter med
    /// ljud per vecka). Innan området finns, och för en natt utan ljud, finns ingen rad. En äldre natt än morgonens
    /// ger ingen rad: raden säger något om den här natten.
    public static func unusualSnoring(_ day: WakeDay, idun: [WakeDay: Double]) -> Row? {
        guard let r = row(.snoring, idun: idun, whoop: [:], upTo: day), r.day == day, let område = r.range else {
            return nil
        }
        return område.contains(r.value) ? nil : r
    }

    /// METOD M33 · METOD M50 · METOD M52 · BESLUT B63. Måttets rad för natten `day` och inte en äldre: värdet, det
    /// egna normalområdet och axeln, ur Idunns nätter. Natten visar stadierna, effektiviteten, klockslagen, medelpulsen,
    /// rörelsen och snarkningen mot sitt normala med den. `nil` när natten saknar måttet.
    public static func nightRow(_ m: Trends.Measure, day: WakeDay, idun: Trends.Values) -> Row? {
        guard let r = row(m, idun: idun[m] ?? [:], whoop: [:], upTo: day), r.day == day else { return nil }
        return r
    }

    /// METOD M81 · BESLUT B141. Stadiernas mått, i ordningen vaken, lätt, djup, REM.
    public static let stageMeasures: [Trends.Measure] = [.awakeTime, .lightSleep, .deepSleep, .remSleep]

    /// METOD M81 · BESLUT B141. Stadiets andel av natten (0–1): minuterna delade med de fyra stadiernas summa, och
    /// andelens normalområde med M7:s regel ur nätterna före. En natt räknas bara när alla fyra stadier har ett tal och
    /// summan är över noll. `nil` när natten `day` saknar andel; området är `nil` innan det finns nog med nätter.
    public static func stageShare(_ m: Trends.Measure, day: WakeDay,
                                  idun: Trends.Values) -> (value: Double, range: ClosedRange<Double>?)? {
        guard stageMeasures.contains(m) else { return nil }
        func andel(_ d: WakeDay) -> Double? {
            var summa: Double = 0
            for s in stageMeasures {
                guard let v = idun[s]?[d], v.isFinite, v >= 0 else { return nil }
                summa += v
            }
            guard summa > 0, let v = idun[m]?[d] else { return nil }
            return v / summa
        }
        guard let värde = andel(day) else { return nil }
        let område = Baseline.normalRange(before: day, value: andel)
        return (värde, område.map { (o: Baseline.NormalRange) -> ClosedRange<Double> in
            max(0, o.lower)...min(1, max(o.upper, max(0, o.lower)))
        })
    }

    /// METOD M33 · BESLUT B40. Alla morgnar som har en natt, äldsta först.
    public static func days(idun: Trends.Values) -> [Day] {
        var dagar: Set<WakeDay> = []
        for m in measures {
            for (d, v) in idun[m] ?? [:] where m.accepts(v) { dagar.insert(d) }
        }
        return dagar.sorted().map { (d: WakeDay) -> Day in day(d, idun: idun) }
    }

    /// METOD M33 · BESLUT B82. Morgonen `steps` morgnar bort från `day` i `days` (äldsta först), för pilarna ‹ och › på
    /// Morgon: −1 är föregående morgon med en natt, 1 nästa. `nil` förbi den första eller den senaste morgonen, och när
    /// `day` inte finns bland morgnarna.
    public static func step(_ days: [WakeDay], from day: WakeDay, by steps: Int) -> WakeDay? {
        guard let i = days.firstIndex(of: day) else { return nil }
        let j: Int = i + steps
        return days.indices.contains(j) ? days[j] : nil
    }

    /// METOD M19. Kortets natt: den senaste natten bland raderna.
    public static func night(_ rows: [Row]) -> WakeDay? {
        rows.map(\.day).max()
    }

    /// METOD M19. Måttets rad: senaste natten i någon källa, Idunns om båda har
    /// samma dag (som i `Baseline`). Bandet och axeln ur samma källa.
    /// METOD M33. Med `upTo` räknas morgonen den dagen: nätter efter den ingår inte.
    static func row(_ m: Trends.Measure, idun: [WakeDay: Double], whoop: [WakeDay: Double],
                    upTo: WakeDay? = nil) -> Row? {
        let medDag = { (d: WakeDay) -> Bool in upTo.map { (u: WakeDay) -> Bool in d <= u } ?? true }
        let i = idun.filter { m.accepts($0.value) && medDag($0.key) }
        let w = whoop.filter { m.accepts($0.value) && medDag($0.key) }
        let tarIdun: Bool
        if let a = i.keys.max() {
            tarIdun = w.keys.max().map { (b: WakeDay) -> Bool in a >= b } ?? true
        } else if !w.isEmpty {
            tarIdun = false
        } else {
            return nil
        }
        let källa: Source = tarIdun ? .idun : .whoop
        let x: [WakeDay: Double] = tarIdun ? i : w
        guard let dag = x.keys.max(), let värde = x[dag] else { return nil }

        // METOD M25 · BESLUT B11. Hudtemperaturens historik: Idunns nätter, och
        // där Idunn saknas Whoops flyttade till Idunns nivå (nivåskillnaden i
        // °C ur nätter med båda), så att området finns innan Idunn har fyra
        // veckor. Raden ur Whoop har sitt eget område (BESLUT B16).
        var historik = x
        if m == .skinTemperature && tarIdun {
            historik = Baseline.levelled(idun: i, whoop: w)
        }

        // METOD M7 · METOD M19. Området räknas i måttets skala (ln för HRV).
        let f = historik.mapValues(m.forward)
        let område = Baseline.normalRange(before: dag, value: { (d: WakeDay) -> Double? in f[d] })
        let range: ClosedRange<Double>? = område.map { m.inverse($0.lower)...m.inverse($0.upper) }

        // METOD M6 · METOD M7. Läget gäller 7-dagarsmedlet, bara för HRV.
        var rolling: Double? = nil
        var status: Baseline.Status? = nil
        if m.hasStatus {
            let vecka: [Double] = (0..<Baseline.rollingDays).compactMap { (k: Int) -> Double? in f[dag - k] }
            if vecka.count >= Baseline.minNightsPerWeek, let medel = Statistics.mean(vecka) {
                rolling = m.inverse(medel)
                status = område?.status(medel)
            }
        }

        var alla: [Double] = (0..<trackDays).compactMap { (k: Int) -> Double? in historik[dag - k] }
        if let r = range { alla += [r.lowerBound, r.upperBound] }
        if let r = rolling { alla.append(r) }
        var lo = alla.min() ?? värde
        var hi = alla.max() ?? värde
        if hi - lo < 1e-9 {
            lo -= 1
            hi += 1
        }
        return Row(measure: m, source: källa, day: dag, value: värde, range: range,
                   track: lo...hi, rolling: rolling, status: status,
                   reference: område.map { m.inverse($0.mean) },
                   usesWhoopHistory: historik.count > x.count,
                   baselineNights: Baseline.baselineNights(before: dag, value: { (d: WakeDay) -> Double? in f[d] }),
                   rangeBuilding: område?.isBuilding ?? false)
    }
}
