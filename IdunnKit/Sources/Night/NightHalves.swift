import Foundation

/// BESLUT B129 · METOD M75
/// Nattens HRV i två halvor: medianen av RMSSD i de glidande 5-minutersfönstren (METOD M4 (d)) vars mitt ligger i
/// nattens första respektive andra halva, utan de fönster som är mest vakna. Nattens medel (METOD M4 (a)) kan dölja en
/// natt som börjar lågt och slutar högt; halvorna visar den. Räknas som `kväll` och `morgon` i
/// `tools/hrv_varianter.py` (METOD M73), så att appens tal är de verktyget jämför.
public enum NightHalves {

    // MARK: Gränserna — METOD M73

    /// METOD M73. Ett fönster som är mer vaket än så här räknas inte.
    public static let maxWakeFraction: Double = 0.5
    /// METOD M73. En halva med färre fönster än så här har inget värde (cirka 15 minuter).
    public static let minWindows: Int = 20

    // MARK: Resultaten

    /// Halvornas RMSSD i millisekunder; `nil` för en halva med för få fönster.
    public struct Halves: Equatable, Sendable {
        public var early: Double?
        public var late: Double?

        public init(early: Double?, late: Double?) {
            self.early = early
            self.late = late
        }
    }

    /// Ett glidande fönster: när det börjar och dess RMSSD.
    struct Window: Equatable {
        var start: TimeInterval
        var rmssd: Double
    }

    /// METOD M75. Vad halvorna säger mot sina egna normalområden.
    public enum Pattern: Equatable, Sendable {
        /// Första halvan under sitt normala, andra inte.
        case lowEarly
        /// Andra halvan under sitt normala, första inte.
        case lowLate
        /// Båda under sitt normala.
        case lowBoth
    }

    // MARK: Räkningen

    /// METOD M4 (d). De glidande fönstren med sin starttid: samma räkning som `NightAnalysis.slidingRMSSD`.
    static func slidingWindows(_ diffs: [RRCleaning.Difference], first: TimeInterval, last: TimeInterval) -> [Window] {
        let d = diffs.sorted { $0.time < $1.time }
        var summa: [Double] = [0]
        summa.reserveCapacity(d.count + 1)
        for x in d {
            let kvadrat: Double = x.milliseconds * x.milliseconds
            summa.append(summa[summa.count - 1] + kvadrat)
        }
        let steg: Double = ((last - first - NightAnalysis.windowSeconds) / NightAnalysis.slidingStepSeconds).rounded(.down)
        let antal: Int = max(0, Int(steg)) + 1
        var ut: [Window] = []
        var lo = 0
        var hi = 0
        for k in 0..<antal {
            let start: TimeInterval = first + Double(k) * NightAnalysis.slidingStepSeconds
            let slut: TimeInterval = start + NightAnalysis.windowSeconds
            while lo < d.count && d[lo].time < start { lo += 1 }
            while hi < d.count && d[hi].time < slut { hi += 1 }
            let n: Int = hi - lo
            guard n >= NightAnalysis.minDifferencesPerWindow else { continue }
            let medel: Double = (summa[hi] - summa[lo]) / Double(n)
            ut.append(Window(start: start, rmssd: max(0, medel).squareRoot()))
        }
        return ut
    }

    /// METOD M73. Andelen av fönstret som ligger i epoker med stadiet vaken. En epok som inte är mätt räknas inte.
    static func wakeFraction(start: TimeInterval, stages: NightStages.Night) -> Double {
        let epok: Double = Double(NightStages.epochSeconds)
        let onset: Double = Double(stages.onset)
        let slut: TimeInterval = start + NightAnalysis.windowSeconds
        var vaken: Double = 0
        var i: Int = max(0, Int(((start - onset) / epok).rounded(.down)))
        while i < stages.epochs.count {
            let a: Double = onset + Double(i) * epok
            if a >= slut { break }
            if stages.epochs[i].stage == .wake {
                vaken += max(0, min(slut, a + epok) - max(start, a))
            }
            i += 1
        }
        return vaken / NightAnalysis.windowSeconds
    }

    /// METOD M75. Halvorna ur nattens skillnader (`RRCleaning.differences`), från första till sista räknade slaget.
    /// Ett fönster hör till den halva där dess mitt ligger. Med stadier tas fönster som är mer än hälften vakna bort;
    /// utan stadier (`nil`) räknas alla.
    public static func compute(differences: [RRCleaning.Difference], first: TimeInterval, last: TimeInterval,
                               stages: NightStages.Night?) -> Halves {
        let mitt: TimeInterval = (first + last) / 2
        let halv: TimeInterval = NightAnalysis.windowSeconds / 2
        var tidiga: [Double] = []
        var sena: [Double] = []
        for w in slidingWindows(differences, first: first, last: last) {
            if let s = stages, wakeFraction(start: w.start, stages: s) > maxWakeFraction { continue }
            if w.start + halv < mitt {
                tidiga.append(w.rmssd)
            } else {
                sena.append(w.rmssd)
            }
        }
        return Halves(early: tidiga.count >= minWindows ? Statistics.median(tidiga) : nil,
                      late: sena.count >= minWindows ? Statistics.median(sena) : nil)
    }

    /// METOD M75. Halvorna för en räknad natt: slagen, stadierna och nattens första och sista slag ur `NightResult`.
    public static func compute(_ r: NightResult) -> Halves {
        guard let a = r.analysis.start, let b = r.analysis.end else { return Halves(early: nil, late: nil) }
        return compute(differences: RRCleaning.differences(r.beats),
                       first: a.timeIntervalSince1970, last: b.timeIntervalSince1970, stages: r.stages)
    }

    /// METOD M75. Mönstret när någon halva ligger under sitt eget normalområde; `nil` när båda ligger inom eller
    /// över, och när ett värde eller ett område saknas.
    public static func pattern(early: Double?, earlyRange: ClosedRange<Double>?,
                               late: Double?, lateRange: ClosedRange<Double>?) -> Pattern? {
        guard let e = early, let er = earlyRange, let l = late, let lr = lateRange else { return nil }
        let lågTidigt: Bool = e < er.lowerBound
        let lågSent: Bool = l < lr.lowerBound
        if lågTidigt && lågSent { return .lowBoth }
        if lågTidigt { return .lowEarly }
        if lågSent { return .lowLate }
        return nil
    }
}
