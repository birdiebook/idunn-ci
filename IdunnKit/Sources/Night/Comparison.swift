import Foundation
import WhoopImport

/// METOD M14 · BESLUT B8 · BESLUT B3
/// Följer Idunn Whoop natt för natt? Idunns nätter och Whoops dygn paras på
/// uppvakningsdagen, och ut kommer bara samlade tal: antal nätter,
/// rangkorrelation, medelavvikelse och medelskillnad — aldrig nätternas värden,
/// så att en skärmbild av jämförelsen kan skickas vidare.
public enum Comparison {

    /// METOD M14. Färre nätter än så ger ingen rangkorrelation.
    public static let minNights = 3

    /// Samlade tal för två serier över samma nätter. Bara aggregat (BESLUT B3).
    public struct Summary: Equatable, Sendable, CustomStringConvertible {
        /// Nätter med värde från båda källorna.
        public var nights: Int
        /// Spearmans rangkorrelation, −1…1.
        public var spearman: Double?
        /// Medel av |Idunn − Whoop|, i måttets enhet.
        public var meanAbsoluteDeviation: Double?
        /// Medel av Idunn − Whoop: nivåskillnaden (METOD M6).
        public var meanDifference: Double?

        public var description: String {
            func tal(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "–" }
            return "\(nights) nätter · rangkorrelation \(tal(spearman)) · "
                + "medelavvikelse \(tal(meanAbsoluteDeviation)) · medelskillnad \(tal(meanDifference))"
        }
    }

    /// METOD M14. Paren i dagordning, för dagar som finns i båda.
    public static func pairs(idun: [WakeDay: Double], whoop: [WakeDay: Double]) -> [(day: WakeDay, idun: Double, whoop: Double)] {
        idun.keys.sorted().compactMap { (d: WakeDay) -> (day: WakeDay, idun: Double, whoop: Double)? in
            guard let a = idun[d], let b = whoop[d] else { return nil }
            return (day: d, idun: a, whoop: b)
        }
    }

    /// METOD M14. Idunn mot Whoop över dagarna som finns i båda.
    public static func summary(idun: [WakeDay: Double], whoop: [WakeDay: Double]) -> Summary {
        let p = pairs(idun: idun, whoop: whoop)
        let x = p.map(\.idun)
        let y = p.map(\.whoop)
        let skillnad = zip(x, y).map { $0.0 - $0.1 }
        return Summary(nights: p.count,
                       spearman: spearman(x, y),
                       meanAbsoluteDeviation: meanAbsoluteDeviation(x, y),
                       meanDifference: Statistics.mean(skillnad))
    }

    /// METOD M14. Spearmans rangkorrelation: Pearsons korrelation mellan
    /// rangerna, där lika värden får medlet av sina rangplatser. `nil` med
    /// olika långa serier, färre än `minNights` par, eller en serie utan spridning.
    public static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= minNights else { return nil }
        let rx = ranks(x)
        let ry = ranks(y)
        let mx = rx.reduce(0, +) / Double(rx.count)
        let my = ry.reduce(0, +) / Double(ry.count)
        var sxy = 0.0
        var sxx = 0.0
        var syy = 0.0
        for i in rx.indices {
            let dx = rx[i] - mx
            let dy = ry[i] - my
            sxy += dx * dy
            sxx += dx * dx
            syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    /// METOD M14. Medel av |x − y|. `nil` med olika långa eller tomma serier.
    public static func meanAbsoluteDeviation(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, !x.isEmpty else { return nil }
        return Statistics.mean(zip(x, y).map { abs($0.0 - $0.1) })
    }

    /// Rang 1…n, lika värden delar medlet av sina platser.
    static func ranks(_ x: [Double]) -> [Double] {
        let order = x.indices.sorted { x[$0] < x[$1] }
        var out = [Double](repeating: 0, count: x.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count && x[order[j + 1]] == x[order[i]] { j += 1 }
            let rang = Double(i + j) / 2 + 1
            for k in i...j { out[order[k]] = rang }
            i = j + 1
        }
        return out
    }
}

/// METOD M14 · METOD M6 · METOD M2
/// Whoops dygn som nätter: uppvakningsdagen ur `Wake onset` i radens zon, och
/// HRV och vilopuls som Whoop räknat dem. Hålls som en egen källa (`.whoop`),
/// så att baslinjen kan börja i dem utan att blandas ihop med Idunns nätter.
public enum WhoopReference {

    /// METOD M14. En natt per uppvakningsdag. Dygn utan uppvaknande (det
    /// pågående) hoppas över. Har två dygn samma uppvakningsdag gäller det
    /// med längst sömn, och vid lika det senare.
    public static func nights(_ cycles: [Cycle]) -> [NightPoint] {
        var out: [NightPoint] = []
        for (d, c) in perWakeDay(cycles) {
            out.append(NightPoint(day: d,
                                  rmssd: c.hrv.map { Double($0) },
                                  restingHeartRate: c.restingHeartRate.map { Double($0) },
                                  skinTemperature: c.skinTempCelsius,
                                  source: .whoop))
        }
        return out
    }

    /// METOD M14. Ett mått per uppvakningsdag, för `Comparison.summary`, t.ex.
    /// `WhoopReference.byWakeDay(cycles) { $0.respiratoryRate }`.
    public static func byWakeDay(_ cycles: [Cycle], _ value: (Cycle) -> Double?) -> [WakeDay: Double] {
        var out: [WakeDay: Double] = [:]
        for (d, c) in perWakeDay(cycles) {
            if let v = value(c) { out[d] = v }
        }
        return out
    }

    static func perWakeDay(_ cycles: [Cycle]) -> [(WakeDay, Cycle)] {
        var valda: [WakeDay: Cycle] = [:]
        for c in cycles.sorted(by: { $0.start < $1.start }) {
            guard let wake = c.wakeOnset else { continue }
            let d = WakeDay(wake, utcOffsetSeconds: c.utcOffsetSeconds)
            if let finns = valda[d], sleepLength(finns) > sleepLength(c) { continue }
            valda[d] = c
        }
        return valda.keys.sorted().map { ($0, valda[$0]!) }
    }

    static func sleepLength(_ c: Cycle) -> TimeInterval {
        guard let a = c.sleepOnset, let b = c.wakeOnset else { return 0 }
        return b.timeIntervalSince(a)
    }
}
