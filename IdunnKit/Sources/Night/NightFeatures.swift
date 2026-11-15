import Foundation
import WhoopFrames

/// METOD M37 · METOD M31 · METOD M35
/// Särdragen per 30 s-epok, tal för tal som Python räknar dem (`tools/natt_stadier.py`:
/// `somn_walch.sardrag` för rörelse och puls, `stadier_hmc.sardrag` för hjärtat). Räknesättet är
/// detsamma rad för rad: löpande summor adderade från början (som `np.cumsum`), binärsökning som
/// `np.searchsorted(side="left")` och linjär interpolation som `np.interp`. Skillnaden mot numpy
/// är bara avrundning (parvis summering i numpy, spektrumet som direkt DFT i stället för FFT);
/// den är långt under toleransen i M37.
///
/// Epok j är sekunderna [onset + 30 j, onset + 30 j + 30). Saknade värden är `Double.nan` hela
/// vägen, och modellerna gör dem till träningens medel (`StageModel.Part.probabilities`).
enum NightFeatures {

    // MARK: Konstanter (METOD M35, METOD M37)

    /// 30 s-epoken (PSG-epoken). **Antagande** att den passar bandet; se M37.
    static let epochSeconds = 30
    /// ±2,5 min kring epokens mitt, i sekunder (hjärtat och pulsen).
    static let windowSeconds = 150
    /// Minst så här många behållna slag (skillnader) i epoken, och i ±2,5 min, för hjärtmåtten.
    static let minBeatsEpoch = 5
    static let minBeatsWindow = 60
    /// Omsamplingen i 4 Hz, Welch-bitar på 120 s med halv överlappning (METOD M10).
    static let resampleStep = 0.25
    static let segmentLength = 480
    static let segmentStride = 240
    static let spectrumBins = 51
    /// En omsamplad punkt räknas om behållna slag finns inom 3 s på båda sidor.
    static let maxBeatGapSeconds = 3.0
    /// Spektrumet räknas bara om minst så stor del av ±2,5 min har slag.
    static let minSpectrumShare = 0.8
    /// DFA α1: lådor med 4–16 slag och minst 64 slag i fönstret. Forskning (K31: Peng m.fl. 1995, abstract;
    /// lådorna 4–16 ej kontrollerade i original); 64 slag är ett antagande (METOD M35, M37).
    static let dfaBoxes: ClosedRange<Int> = 4...16
    static let dfaMinBeats = 64
    /// Rörelsefönstret ±2,5 min i femsekundsepoker.
    static let movementWindowEpochs = 30
    /// Pulsen normerad mot nattens nivå klipps till ±5 (som M31).
    static let pulseClip = 5.0

    // MARK: Hjälpare, som numpy

    /// `np.searchsorted(a, x, side="left")`: första index med värde ≥ x.
    static func lowerBound(_ a: [Double], _ x: Double) -> Int {
        var lo: Int = 0
        var hi: Int = a.count
        while lo < hi {
            let mid: Int = lo + (hi - lo) / 2
            if a[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Löpande summa med en nolla först: `c[i]` är summan av de `i` första (som `np.cumsum`).
    static func running(_ v: [Double]) -> [Double] {
        var c = [Double](repeating: 0, count: v.count + 1)
        for i in 0..<v.count { c[i + 1] = c[i] + v[i] }
        return c
    }

    /// Summan över [lo, hi) ur en löpande summa; gränserna klipps till 0…n (`_fonstersumma`).
    static func windowSum(_ c: [Double], _ lo: Int, _ hi: Int) -> Double {
        let n: Int = c.count - 1
        let a: Int = min(max(lo, 0), n)
        let b: Int = min(max(hi, 0), n)
        return c[b] - c[a]
    }

    /// `np.interp(x, xp, fp)` för en punkt, med första och sista värdet utanför. `xp` ska vara stigande.
    static func interpolate(_ x: Double, _ xp: [Double], _ fp: [Double]) -> Double {
        let n: Int = xp.count
        if x < xp[0] { return fp[0] }
        if x > xp[n - 1] { return fp[n - 1] }
        var lo: Int = 0
        var hi: Int = n
        while lo < hi {
            let mid: Int = lo + (hi - lo) / 2
            if xp[mid] <= x { lo = mid + 1 } else { hi = mid }
        }
        let j: Int = lo - 1
        if j >= n - 1 || xp[j] == x { return fp[j] }
        let slope: Double = (fp[j + 1] - fp[j]) / (xp[j + 1] - xp[j])
        var r: Double = slope * (x - xp[j]) + fp[j]
        if r.isNaN {
            r = slope * (x - xp[j + 1]) + fp[j + 1]
            if r.isNaN && fp[j] == fp[j + 1] { r = fp[j] }
        }
        return r
    }

    /// Medianen av de ändliga värdena; `nan` om inga finns (`np.nanmedian`).
    static func finiteMedian(_ x: [Double]) -> Double {
        var v: [Double] = []
        v.reserveCapacity(x.count)
        for e in x where e.isFinite { v.append(e) }
        return Statistics.median(v) ?? Double.nan
    }

    /// Percentil 75 minus 25 över de ändliga värdena; 1 om färre än två värden eller om skillnaden är noll
    /// eller negativ (`stadier_hmc._iqr`).
    static func iqr(_ x: [Double]) -> Double {
        var v: [Double] = []
        for e in x where e.isFinite { v.append(e) }
        if v.count < 2 { return 1.0 }
        let q: Double = SleepDetection.percentile(v, 0.75) - SleepDetection.percentile(v, 0.25)
        return q > 0 ? q : 1.0
    }

    // MARK: Rörelse och puls — 7 särdrag (METOD M31 (d))

    /// Rörelse och puls per epok, i kolumnerna `steg_epok`, `steg_5min`, `steg_over_5grader`,
    /// `median_5min`, `puls_epok`, `puls_5min`, `andel_av_natten` (`somn_walch.SARDRAG`), och om epoken är
    /// mätt (minst `NightStages.minAngleEpochs` av sex femsekundsepoker har armens vinkel; BESLUT B45).
    static func movement(_ series: K18Series, onset: Int, epochs n30: Int) -> (rows: [[Double]], measured: [Bool]) {
        let n5: Int = 6 * n30
        let angles: [Double?] = SleepDetection.epochAngles(series.records, first: onset / SleepDetection.epochSeconds,
                                                           count: n5)
        let steps: [Double?] = SleepDetection.angleSteps(angles)
        var sv = [Double](repeating: 0, count: n5)
        var present = [Double](repeating: 0, count: n5)
        var big = [Double](repeating: 0, count: n5)
        for i in 0..<n5 {
            guard let s = steps[i] else { continue }
            sv[i] = s
            present[i] = 1
            if s > SleepDetection.postureChangeDegrees { big[i] = 1 }
        }
        let csV: [Double] = running(sv)
        let csN: [Double] = running(present)
        let csB: [Double] = running(big)
        let med: [Double?] = SleepDetection.rollingMedian(steps)

        // Pulsen per sekund från insomningen: posten i14 när den är över noll, annars saknad.
        var pulse = [Double](repeating: Double.nan, count: epochSeconds * n30)
        for r in series.records where r.pulse > 0 {
            let k: Int = r.time - onset
            if k >= 0 && k < pulse.count { pulse[k] = Double(r.pulse) }
        }
        var pv = [Double](repeating: 0, count: pulse.count)
        var pn = [Double](repeating: 0, count: pulse.count)
        for i in 0..<pulse.count where pulse[i].isFinite {
            pv[i] = pulse[i]
            pn[i] = 1
        }
        let csPV: [Double] = running(pv)
        let csPN: [Double] = running(pn)

        var movementEpoch = [Double](repeating: 0, count: n30)
        var movementWindow = [Double](repeating: 0, count: n30)
        var bouts = [Double](repeating: 0, count: n30)
        var medianWindow = [Double](repeating: 0, count: n30)
        var pulseEpoch = [Double](repeating: Double.nan, count: n30)
        var pulseWindow = [Double](repeating: Double.nan, count: n30)
        var measured = [Bool](repeating: false, count: n30)
        for j in 0..<n30 {
            let eLo: Int = 6 * j
            let eHi: Int = 6 * j + 6
            let fLo: Int = 6 * j + 3 - movementWindowEpochs
            let fHi: Int = 6 * j + 3 + movementWindowEpochs
            movementEpoch[j] = windowSum(csV, eLo, eHi) / max(windowSum(csN, eLo, eHi), 1)
            movementWindow[j] = windowSum(csV, fLo, fHi) / max(windowSum(csN, fLo, fHi), 1)
            bouts[j] = windowSum(csB, fLo, fHi)
            medianWindow[j] = med[6 * j + 3] ?? movementWindow[j]
            var have: Int = 0
            for i in eLo..<eHi where angles[i] != nil { have += 1 }
            measured[j] = have >= NightStages.minAngleEpochs

            let sLo: Int = epochSeconds * j
            let sHi: Int = epochSeconds * j + epochSeconds
            let gLo: Int = epochSeconds * j + epochSeconds / 2 - windowSeconds
            let gHi: Int = epochSeconds * j + epochSeconds / 2 + windowSeconds
            let nE: Double = windowSum(csPN, sLo, sHi)
            let nF: Double = windowSum(csPN, gLo, gHi)
            if nE > 0 { pulseEpoch[j] = windowSum(csPV, sLo, sHi) / max(nE, 1) }
            if nF > 0 { pulseWindow[j] = windowSum(csPV, gLo, gHi) / max(nF, 1) }
        }

        // Pulsen mot nattens egen nivå: median och IQR av epokpulserna; saknas de, 0 och 1.
        var level: Double = 0
        var spread: Double = 1
        var finite: [Double] = []
        for e in pulseEpoch where e.isFinite { finite.append(e) }
        if finite.count >= 2 {
            level = Statistics.median(finite) ?? 0
            spread = max(SleepDetection.percentile(finite, 0.75) - SleepDetection.percentile(finite, 0.25), 1.0)
        }
        func normalized(_ x: Double) -> Double {
            let v: Double = (x - level) / spread
            if v.isNaN { return 0 }
            return min(max(v, -pulseClip), pulseClip)
        }

        var rows: [[Double]] = []
        rows.reserveCapacity(n30)
        let last: Double = Double(max(n30 - 1, 1))
        for j in 0..<n30 {
            let row: [Double] = [log1p(movementEpoch[j]), log1p(movementWindow[j]), log1p(bouts[j]),
                                 log1p(medianWindow[j]), normalized(pulseEpoch[j]), normalized(pulseWindow[j]),
                                 Double(j) / last]
            rows.append(row)
        }
        return (rows, measured)
    }

    // MARK: Hjärtat — 12 råa särdrag (METOD M35)

    /// De behållna slagen (tid i sekunder från insomningen, RR i ms) och skillnaderna mellan grannar som
    /// båda överlevt (`stadier_hmc.Slagen`).
    struct BeatSeries: Equatable {
        var time: [Double]
        var rr: [Double]
        var diffTime: [Double]
        var diff: [Double]

        /// De behållna slagen i ankomstordning och `RRCleaning.differences`, tiderna minus `onset`.
        init(beats: [Beat], onset: Int) {
            let zero: Double = Double(onset)
            var t: [Double] = []
            var r: [Double] = []
            for b in beats where b.isKept {
                t.append(b.time - zero)
                r.append(b.rrMilliseconds)
            }
            var dt: [Double] = []
            var d: [Double] = []
            for x in RRCleaning.differences(beats) {
                dt.append(x.time - zero)
                d.append(x.milliseconds)
            }
            time = t
            rr = r
            diffTime = dt
            diff = d
        }
    }

    /// Antal, summa och kvadratsumma av ett värde för tider i [lo, hi) (`stadier_hmc._summor`).
    struct Moments {
        var time: [Double]
        var c1: [Double]
        var c2: [Double]

        init(time: [Double], values: [Double]) {
            self.time = time
            c1 = NightFeatures.running(values)
            c2 = NightFeatures.running(values.map { (x: Double) -> Double in x * x })
        }

        func sums(_ lo: Double, _ hi: Double) -> (n: Double, s1: Double, s2: Double) {
            let i0: Int = NightFeatures.lowerBound(time, lo)
            let i1: Int = NightFeatures.lowerBound(time, hi)
            return (Double(i1 - i0), c1[i1] - c1[i0], c2[i1] - c2[i0])
        }
    }

    /// De fyra tidsmåtten i ett fönster (`stadier_hmc._tidsmatt`): medelpuls (60000 / medel-RR), ln RMSSD och
    /// pulsens SD (slag per minut). `nan` när fönstret har färre än `minimum` slag (skillnader).
    static func timeMeasures(rr: Moments, hr: Moments, diff: Moments, lo: Double, hi: Double,
                             minimum: Int) -> (pulse: Double, lnRMSSD: Double, sdPulse: Double) {
        let a = rr.sums(lo, hi)
        let h = hr.sums(lo, hi)
        let d = diff.sums(lo, hi)
        let least: Double = Double(minimum)
        var pulse: Double = Double.nan
        var lnr: Double = Double.nan
        var sd: Double = Double.nan
        if a.n >= least { pulse = 60000.0 / (a.s1 / max(a.n, 1)) }
        if d.n >= least { lnr = 0.5 * log(max(d.s2, 1e-9) / max(d.n, 1)) }
        if h.n >= least {
            let mean: Double = h.s1 / max(h.n, 1)
            let variance: Double = h.s2 / max(h.n, 1) - mean * mean
            sd = (max(variance, 0) * h.n / max(h.n - 1, 1)).squareRoot()
        }
        return (pulse, lnr, sd)
    }

    /// Slagen som RR på en jämn axel i 4 Hz från 0 till `end` sekunder (linjär interpolation) och om varje punkt
    /// har behållna slag inom 3 s på båda sidor (`stadier_hmc.omsampla`). Under två slag: nollor, ingen punkt.
    static func resample(_ s: BeatSeries, end: Double) -> (values: [Double], ok: [Bool]) {
        let count: Int = Int((end / resampleStep).rounded(.up))
        var v = [Double](repeating: 0, count: count)
        var ok = [Bool](repeating: false, count: count)
        let t: [Double] = s.time
        guard t.count >= 2 else { return (v, ok) }
        let first: Double = t[0]
        let last: Double = t[t.count - 1]
        for i in 0..<count {
            let u: Double = Double(i) * resampleStep
            v[i] = interpolate(u, t, s.rr)
            let j: Int = min(max(lowerBound(t, u), 1), t.count - 1)
            ok[i] = u >= first && u <= last && t[j] - t[j - 1] <= maxBeatGapSeconds
        }
        return (v, ok)
    }

    // Tabellerna för den direkta DFT:n över 480 punkter och Hann-fönstret (som `np.hanning`).
    static let cosTable: [Double] = {
        var t = [Double](repeating: 0, count: segmentLength)
        for n in 0..<segmentLength { t[n] = cos(2.0 * Double.pi * Double(n) / Double(segmentLength)) }
        return t
    }()
    static let sinTable: [Double] = {
        var t = [Double](repeating: 0, count: segmentLength)
        for n in 0..<segmentLength { t[n] = sin(2.0 * Double.pi * Double(n) / Double(segmentLength)) }
        return t
    }()
    static let hann: [Double] = {
        var w = [Double](repeating: 0, count: segmentLength)
        let m: Int = segmentLength
        for k in 0..<m {
            let n: Double = Double(1 - m + 2 * k)
            w[k] = 0.5 + 0.5 * cos(Double.pi * n / Double(m - 1))
        }
        return w
    }()

    /// Frekvenserna i bin 0…50 som `np.fft.rfftfreq(480, 0.25)`: `m * (1/120)`.
    static let frequencies: [Double] = {
        var f = [Double](repeating: 0, count: spectrumBins)
        let step: Double = 1.0 / (Double(segmentLength) * resampleStep)
        for m in 0..<spectrumBins { f[m] = Double(m) * step }
        return f
    }()
    /// LF 0,04 ≤ f < 0,15 och HF 0,15 ≤ f ≤ 0,40 Hz (Task Force), i stigande bin.
    static let lowBins: [Int] = (0..<NightFeatures.spectrumBins).filter { (m: Int) -> Bool in
        NightFeatures.frequencies[m] >= 0.04 && NightFeatures.frequencies[m] < 0.15
    }
    static let highBins: [Int] = (0..<NightFeatures.spectrumBins).filter { (m: Int) -> Bool in
        NightFeatures.frequencies[m] >= 0.15 && NightFeatures.frequencies[m] <= 0.40
    }

    /// Effekten i bin 0…50 för en bit på 480 punkter: rät linje bort, Hann-fönster, direkt DFT
    /// (`stadier_hmc.spektrum` för en bit; Welch är medlet av fyra).
    static func periodogram(_ b: [Double]) -> [Double] {
        let n: Int = segmentLength
        var sum: Double = 0
        for x in b { sum += x }
        let mean: Double = sum / Double(n)
        var sxb: Double = 0
        var sxx: Double = 0
        let center: Double = Double(n - 1) / 2
        for k in 0..<n {
            let x: Double = Double(k) - center
            sxb += b[k] * x
            sxx += x * x
        }
        let slope: Double = sxb / sxx
        var y = [Double](repeating: 0, count: n)
        for k in 0..<n {
            let x: Double = Double(k) - center
            let r: Double = b[k] - mean - slope * x
            y[k] = r * hann[k]
        }
        var power = [Double](repeating: 0, count: spectrumBins)
        for m in 0..<spectrumBins {
            var re: Double = 0
            var im: Double = 0
            for k in 0..<n {
                let idx: Int = (k * m) % n
                re += y[k] * cosTable[idx]
                im -= y[k] * sinTable[idx]
            }
            power[m] = re * re + im * im
        }
        return power
    }

    /// DFA α1 (Peng m.fl. 1995): integrerad serie, lådor med 4–16 slag utan överlapp, rät linje bort per låda,
    /// F(n) = RMS av resten, α1 = lutningen av log F mot log n. `nan` under 64 slag eller med färre än tre punkter.
    static func dfaAlpha1(_ rr: [Double]) -> Double {
        guard rr.count >= dfaMinBeats else { return Double.nan }
        var total: Double = 0
        for v in rr { total += v }
        let mean: Double = total / Double(rr.count)
        var y = [Double](repeating: 0, count: rr.count)
        var acc: Double = 0
        for i in 0..<rr.count {
            acc += rr[i] - mean
            y[i] = acc
        }
        var logN: [Double] = []
        var logF: [Double] = []
        for n in dfaBoxes {
            let m: Int = y.count / n
            let center: Double = Double(n - 1) / 2
            var sxx: Double = 0
            for k in 0..<n {
                let x: Double = Double(k) - center
                sxx += x * x
            }
            var squares: Double = 0
            for box in 0..<m {
                let base: Int = box * n
                var bs: Double = 0
                var sxb: Double = 0
                for k in 0..<n {
                    bs += y[base + k]
                    sxb += y[base + k] * (Double(k) - center)
                }
                let bm: Double = bs / Double(n)
                let slope: Double = sxb / sxx
                for k in 0..<n {
                    let r: Double = y[base + k] - bm - slope * (Double(k) - center)
                    squares += r * r
                }
            }
            let f: Double = (squares / Double(m * n)).squareRoot()
            if f > 0 {
                logN.append(log(Double(n)))
                logF.append(log(f))
            }
        }
        guard logN.count >= 3 else { return Double.nan }
        let mx: Double = logN.reduce(0, +) / Double(logN.count)
        let my: Double = logF.reduce(0, +) / Double(logF.count)
        var covariance: Double = 0
        var variance: Double = 0
        for i in 0..<logN.count {
            covariance += (logN[i] - mx) * (logF[i] - my)
            variance += (logN[i] - mx) * (logN[i] - mx)
        }
        return covariance / variance
    }

    /// De tolv råa hjärtsärdragen per epok, i kolumnerna `puls_e`, `lnrmssd_e`, `sdpuls_e`, `puls_f`, `lnrmssd_f`,
    /// `sdpuls_f`, `lnlfhf_f`, `andning_f`, `topp_f`, `dfa_f`, `andel_av_natten`, `timmar` (`stadier_hmc.sardrag`
    /// med start 0).
    static func heart(_ beats: [Beat], onset: Int, epochs n30: Int) -> [[Double]] {
        let s = BeatSeries(beats: beats, onset: onset)
        let rrM = Moments(time: s.time, values: s.rr)
        let hrM = Moments(time: s.time, values: s.rr.map { (x: Double) -> Double in 60000.0 / x })
        let dM = Moments(time: s.diffTime, values: s.diff)

        let end: Double = Double(epochSeconds * (n30 - 1) + epochSeconds + windowSeconds + 1)
        let axis = resample(s, end: end)
        // Bitarnas effekt cachas per startindex: epok j och j + 2 delar tre bitar.
        var bitCache: [Int: [Double]] = [:]
        func bit(_ start: Int) -> [Double] {
            if let c = bitCache[start] { return c }
            let p: [Double] = periodogram(Array(axis.values[start..<(start + segmentLength)]))
            bitCache[start] = p
            return p
        }
        let span: Int = 2 * windowSeconds * 4                  // 1200 punkter
        let df: Double = frequencies[1] - frequencies[0]
        let last: Double = Double(max(n30 - 1, 1))

        var rows: [[Double]] = []
        rows.reserveCapacity(n30)
        for j in 0..<n30 {
            let lo: Double = Double(epochSeconds * j)
            let mid: Double = lo + Double(epochSeconds) / 2
            let e = timeMeasures(rr: rrM, hr: hrM, diff: dM, lo: lo, hi: lo + Double(epochSeconds),
                                 minimum: minBeatsEpoch)
            let w = timeMeasures(rr: rrM, hr: hrM, diff: dM, lo: mid - Double(windowSeconds),
                                 hi: mid + Double(windowSeconds), minimum: minBeatsWindow)

            var lnLFHF: Double = Double.nan
            var breathing: Double = Double.nan
            var peak: Double = Double.nan
            let a: Int = 120 * j - 540                          // rint((mitt − 150) · 4)
            if a >= 0 && a + span <= axis.values.count {
                var good: Int = 0
                for i in a..<(a + span) where axis.ok[i] { good += 1 }
                let share: Double = Double(good) / Double(span)
                var power = [Double](repeating: 0, count: spectrumBins)
                for i in 0..<4 {
                    let p: [Double] = bit(a + segmentStride * i)
                    for m in 0..<spectrumBins { power[m] += p[m] }
                }
                for m in 0..<spectrumBins { power[m] /= 4 }
                var lf: Double = 0
                for m in lowBins { lf += power[m] }
                var hf: Double = 0
                for m in highBins { hf += power[m] }
                var k: Int = highBins[0]
                for m in highBins where power[m] > power[k] { k = m }
                let y0: Double = power[k - 1]
                let y1: Double = power[k]
                let y2: Double = power[min(k + 1, spectrumBins - 1)]
                let nam: Double = y0 - 2 * y1 + y2
                let d: Double = nam < 0 ? 0.5 * (y0 - y2) / nam : 0
                if share >= minSpectrumShare {
                    if lf > 0 && hf > 0 { lnLFHF = log(lf / hf) }
                    if hf > 0 {
                        breathing = frequencies[k] + min(max(d, -0.5), 0.5) * df
                        peak = (y0 + y1 + y2) / hf
                    }
                }
            }

            let i0: Int = lowerBound(s.time, mid - Double(windowSeconds))
            let i1: Int = lowerBound(s.time, mid + Double(windowSeconds))
            let dfa: Double = i1 > i0 ? dfaAlpha1(Array(s.rr[i0..<i1])) : Double.nan
            rows.append([e.pulse, e.lnRMSSD, e.sdPulse, w.pulse, w.lnRMSSD, w.sdPulse, lnLFHF, breathing, peak, dfa,
                         Double(j) / last, Double(epochSeconds * j) / 3600.0])
        }
        return rows
    }
}
