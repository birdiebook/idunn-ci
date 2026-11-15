import Foundation
import WhoopImport

/// METOD M26 · METOD M14 · BESLUT B3
/// Idunns sömnperiod mot Whoops sömnpass i exporten: hur långt ifrån varandra
/// ligger insomning, uppvaknande och sömntid? Bara tal, som M14: avvikelsen
/// är Idunn minus Whoop i minuter, så plus betyder att Idunn ligger senare
/// (insomning, uppvaknande) eller mäter mer sömn (sömntid).
public enum SleepComparison {

    /// En natt, tre tal i minuter.
    public struct Deviation: Equatable, Sendable {
        /// Idunns insomning minus Whoops `Sleep onset`.
        public var onsetMinutes: Double
        /// Idunns uppvaknande minus Whoops `Wake onset`.
        public var wakeMinutes: Double
        /// Idunns sömntid minus Whoops `Asleep duration`; `nil` om passet saknar den.
        public var sleepMinutes: Double?
    }

    /// Avvikelserna för ett mått över flera nätter.
    public struct Measure: Equatable, Sendable {
        public var nights: Int
        /// Medel av Idunn − Whoop: systematisk skillnad.
        public var meanDifference: Double?
        /// Medel av |Idunn − Whoop|: hur långt ifrån, utan tecken.
        public var meanAbsoluteDeviation: Double?
    }

    /// Samlade tal, aldrig nätternas egna värden (BESLUT B3).
    public struct Summary: Equatable, Sendable, CustomStringConvertible {
        /// Nätter där Idunn och ett Whoop-pass möttes.
        public var nights: Int
        public var onset: Measure
        public var wake: Measure
        public var sleep: Measure

        /// Färre än `Comparison.minNights` nätter säger för lite för att visas.
        public var isEnough: Bool { nights >= Comparison.minNights }

        public var description: String {
            func tal(_ x: Double?) -> String { x.map { String(format: "%.1f", $0) } ?? "–" }
            return "\(nights) nätter · insomning \(tal(onset.meanDifference)) min "
                + "(±\(tal(onset.meanAbsoluteDeviation))) · uppvaknande \(tal(wake.meanDifference)) min "
                + "(±\(tal(wake.meanAbsoluteDeviation))) · sömntid \(tal(sleep.meanDifference)) min "
                + "(±\(tal(sleep.meanAbsoluteDeviation)))"
        }
    }

    /// METOD M26. Whoop-passet som hör till Idunns natt: det som inte är en
    /// tupplur och överlappar perioden mest. Överlappar inget är svaret `nil`.
    /// (Delar Whoop en natt i två pass gäller det som överlappar mest.)
    public static func whoopPass(for idun: SleepPeriod, in sleeps: [Sleep]) -> Sleep? {
        whoopPass(for: NightSleep(idun), in: sleeps)
    }

    /// METOD M26. Samma val för en sparad period.
    public static func whoopPass(for idun: NightSleep, in sleeps: [Sleep]) -> Sleep? {
        var best: Sleep?
        var bestOverlap: Double = 0
        for s in sleeps where !s.isNap {
            let start: Double = max(Double(idun.onset), s.onset.timeIntervalSince1970)
            let end: Double = min(Double(idun.wake), s.wake.timeIntervalSince1970)
            let overlap: Double = end - start
            if overlap > bestOverlap {
                best = s
                bestOverlap = overlap
            }
        }
        return best
    }

    /// METOD M26. Avvikelserna för en natt mot ett Whoop-pass.
    public static func deviation(idun: SleepPeriod, whoop: Sleep) -> Deviation {
        deviation(idun: NightSleep(idun), whoop: whoop)
    }

    /// METOD M26. Samma avvikelse för en sparad period.
    public static func deviation(idun: NightSleep, whoop: Sleep) -> Deviation {
        Deviation(onsetMinutes: (Double(idun.onset) - whoop.onset.timeIntervalSince1970) / 60,
                  wakeMinutes: (Double(idun.wake) - whoop.wake.timeIntervalSince1970) / 60,
                  sleepMinutes: whoop.asleepMinutes.map { idun.asleepMinutes - Double($0) })
    }

    /// METOD M26. Det jämförelsen behöver av en sömnperiod: insomning,
    /// uppvaknande (Unix-sekunder) och sömntid. Appen sparar dem med natten
    /// (`NightDigest`), så jämförelsen kan göras utan att räkna om perioden.
    public struct NightSleep: Equatable, Sendable {
        public var onset: Int
        public var wake: Int
        public var asleepMinutes: Double

        public init(onset: Int, wake: Int, asleepMinutes: Double) {
            self.onset = onset
            self.wake = wake
            self.asleepMinutes = asleepMinutes
        }

        public init(_ p: SleepPeriod) {
            self.init(onset: p.onset, wake: p.wake, asleepMinutes: p.asleepMinutesTotal)
        }
    }

    /// METOD M26. Natt för natt mot exportens pass, sammanfattat.
    public static func summary(idun: [SleepPeriod], whoop: [Sleep]) -> Summary {
        summary(nights: idun.map { (p: SleepPeriod) -> NightSleep in NightSleep(p) }, whoop: whoop)
    }

    /// METOD M26. Samma jämförelse på sparade perioder (`NightSleep`).
    public static func summary(nights idun: [NightSleep], whoop: [Sleep]) -> Summary {
        var devs: [Deviation] = []
        for night in idun {
            if let pass = whoopPass(for: night, in: whoop) {
                devs.append(deviation(idun: night, whoop: pass))
            }
        }
        return Summary(nights: devs.count,
                       onset: measure(devs.map { Optional($0.onsetMinutes) }),
                       wake: measure(devs.map { Optional($0.wakeMinutes) }),
                       sleep: measure(devs.map(\.sleepMinutes)))
    }

    static func measure(_ values: [Double?]) -> Measure {
        let v: [Double] = values.compactMap { $0 }
        return Measure(nights: v.count,
                       meanDifference: Statistics.mean(v),
                       meanAbsoluteDeviation: Statistics.mean(v.map { abs($0) }))
    }
}
