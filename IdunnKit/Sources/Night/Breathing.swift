import Foundation

/// METOD M10
/// Andningsfrekvensen ur RR-intervallen. Pulsen stiger vid inandning och sjunker
/// vid utandning, så andningen syns som en topp i intervallens spektrum i
/// HF-bandet 0,15–0,4 Hz. Toppens frekvens × 60 är andetag per minut.
///
/// Metoden, steg för steg:
///
///     1. de rensade slagen (METOD M3) som punkter (tid, RR), lagda på en jämn
///        axel med 4 Hz linjär interpolation
///     2. delade i 120-sekundersbitar med halv överlappning (Welchs metod)
///     3. varje bit: en rät linje bort (minsta kvadrat), sedan ett Hann-fönster
///     4. effekten i varje frekvens k/120 Hz med en rak DFT, medel över bitarna
///     5. högsta frekvensen i 0,15–0,4 Hz, förfinad med en parabel genom
///        toppen och dess två grannar
///
/// Toppen är **tydlig** bara om den är en lokal topp även mot grannar utanför
/// bandet, bär minst 40 % av bandets effekt i sig och sina grannar, och serien
/// varierar mer än upplösningen. Annars "ingen tydlig topp".
public enum Breathing {

    // MARK: Gränserna — METOD M10

    /// METOD M10. Den jämna axelns takt, Hz.
    public static let sampleRate: Double = 4
    /// METOD M10. Welch-bitarnas längd i sekunder: upplösningen blir 1/120 Hz,
    /// alltså 0,5 andetag per minut före parabeln.
    public static let segmentSeconds: Double = 120
    /// METOD M10. HF-bandet, Hz: 9–24 andetag per minut.
    public static let band: ClosedRange<Double> = 0.15...0.40
    /// METOD M10. Toppen och dess grannar ska bära minst så här stor del av bandets effekt.
    public static let minPeakShare: Double = 0.4
    /// METOD M10. Varierar serien mindre än så här (ms, RMS efter linjen) finns
    /// ingen andningsvåg att se: upplösningen är 0,977 ms (METOD M1).
    public static let minVariationMilliseconds: Double = 0.5

    /// Skattningen för en serie. Talen är frekvenser och andelar.
    public struct Estimate: Equatable, Sendable {
        /// Högsta frekvensen i bandet, Hz, även när den inte är tydlig.
        public var peakHz: Double
        /// Toppens och grannarnas del av bandets effekt.
        public var peakShare: Double
        public var isClear: Bool
        /// Andetag per minut, eller `nil` när toppen inte är tydlig.
        public var breathsPerMinute: Double? { isClear ? peakHz * 60 : nil }
    }

    /// METOD M10. `nil` när serien är kortare än en Welch-bit (120 s).
    /// Tiderna i sekunder, intervallen i millisekunder, i slagens ordning.
    public static func estimate(times: [TimeInterval], rrMilliseconds: [Double]) -> Estimate? {
        let x = resample(times: times, values: rrMilliseconds)
        let L = Int(segmentSeconds * sampleRate)
        guard x.count >= L else { return nil }
        let step = L / 2
        let segments = (x.count - L) / step + 1

        // Bandets frekvenser k/120 Hz, plus en granne på var sida.
        let kMin = Int((band.lowerBound * segmentSeconds - 1e-9).rounded(.up))
        let kMax = Int((band.upperBound * segmentSeconds + 1e-9).rounded(.down))
        let ks: [Int] = Array((kMin - 1)...(kMax + 1))
        let hann: [Double] = (0..<L).map { (n: Int) -> Double in
            0.5 - 0.5 * cos(2 * Double.pi * Double(n) / Double(L))
        }
        let cosT: [[Double]] = ks.map { (k: Int) -> [Double] in
            (0..<L).map { (n: Int) -> Double in cos(2 * Double.pi * Double(k * n) / Double(L)) }
        }
        let sinT: [[Double]] = ks.map { (k: Int) -> [Double] in
            (0..<L).map { (n: Int) -> Double in sin(2 * Double.pi * Double(k * n) / Double(L)) }
        }

        var power = [Double](repeating: 0, count: ks.count)
        var sumSquares = 0.0
        for s in 0..<segments {
            var seg = detrended(Array(x[(s * step)..<(s * step + L)]))
            sumSquares += seg.reduce(0.0) { (a: Double, v: Double) -> Double in a + v * v }
            for n in 0..<L { seg[n] *= hann[n] }
            for j in ks.indices {
                var re = 0.0
                var im = 0.0
                let c = cosT[j]
                let si = sinT[j]
                for n in 0..<L {
                    re += seg[n] * c[n]
                    im += seg[n] * si[n]
                }
                power[j] += re * re + im * im
            }
        }

        // Toppen i bandet (index 1 … ks.count − 2); vid lika vinner den lägre.
        var j = 1
        for i in 1...(ks.count - 2) where power[i] > power[j] { j = i }
        let total = power[1...(ks.count - 2)].reduce(0, +)
        let rms = (sumSquares / Double(segments * L)).squareRoot()
        guard total > 0, rms >= minVariationMilliseconds else {
            return Estimate(peakHz: Double(ks[j]) / segmentSeconds, peakShare: 0, isClear: false)
        }
        let lo = max(j - 1, 1)
        let hi = min(j + 1, ks.count - 2)
        let share = power[lo...hi].reduce(0, +) / total
        let isLocalPeak = power[j] >= power[j - 1] && power[j] >= power[j + 1]

        // Parabeln genom toppen och grannarna flyttar toppen högst en halv frekvens.
        var d = 0.0
        let den = power[j - 1] - 2 * power[j] + power[j + 1]
        if den < 0 {
            d = min(0.5, max(-0.5, 0.5 * (power[j - 1] - power[j + 1]) / den))
        }
        return Estimate(peakHz: (Double(ks[j]) + d) / segmentSeconds,
                        peakShare: share,
                        isClear: isLocalPeak && share >= minPeakShare)
    }

    /// METOD M10. Linjär interpolation till en jämn axel med `sampleRate`, från
    /// första till sista punkten. En punkt som inte ligger efter den förra
    /// (klockan lagd om, METOD M3) hoppas över.
    /// Offentlig sedan J1: ljudets fasräkning (METOD M39) lägger RR på samma axel.
    public static func resample(times: [TimeInterval], values: [Double]) -> [Double] {
        var t: [Double] = []
        var v: [Double] = []
        for (a, b) in zip(times, values) where t.last.map({ a > $0 }) ?? true {
            t.append(a)
            v.append(b)
        }
        guard t.count >= 2 else { return [] }
        let n = Int(((t[t.count - 1] - t[0]) * sampleRate).rounded(.down)) + 1
        var out: [Double] = []
        out.reserveCapacity(n)
        var j = 0
        for i in 0..<n {
            let x = t[0] + Double(i) / sampleRate
            while j < t.count - 2 && t[j + 1] <= x { j += 1 }
            let f = min(1, max(0, (x - t[j]) / (t[j + 1] - t[j])))
            out.append(v[j] + f * (v[j + 1] - v[j]))
        }
        return out
    }

    /// Minsta kvadrat-linjen genom biten dras bort.
    public static func detrended(_ x: [Double]) -> [Double] {
        let n = Double(x.count)
        let mn = (n - 1) / 2
        let mx = x.reduce(0, +) / n
        var sxy = 0.0
        var sxx = 0.0
        for (i, v) in x.enumerated() {
            let di = Double(i) - mn
            sxy += di * (v - mx)
            sxx += di * di
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        var out = x
        for i in out.indices { out[i] = x[i] - mx - slope * (Double(i) - mn) }
        return out
    }
}
