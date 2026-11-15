import Foundation
import HeartRate
import Night
import WhoopFrames

/// METOD M39 · BESLUT B47
/// Vems snarkning: fasen mot din andning. Man snarkar när man andas in, och den
/// egna andningen syns i bandets RR-intervall (pulsen stiger vid inandning och
/// sjunker vid utandning, METOD M10). Din snarkning hamnar därför på samma
/// ställe i varje andetag; någon annans följer en egen andning och glider mot
/// din. En fast skillnad mellan telefonens och bandets klocka vrider alla faser
/// lika mycket och ändrar inte R (så länge andningen är jämn; en skillnad på
/// sekunder får fasen att glida något, och därför läggs snarkningarna i bandets
/// klocka med `SoundClock`:s skattning när den är säker).
///
/// Stegen, per snarkepisod delad i block om högst 10 minuter:
///
///     1. episod: sekunder med snarkning ≥ 50 och högst 30 sekunders
///        mellanrum, minst 60 sekunder lång
///     2. snarkningarnas tider: sekunden + (onset + 0,5) · 62,5 ms
///     3. andningens fas: slagen ur K18 (METOD M28, rensade enligt METOD M3)
///        för blocket ± 60 s, RR på en jämn axel med 4 Hz (som METOD M10),
///        bandpassat till 0,15–0,40 Hz; topparna delar in andetagen och
///        fasen är φ = 2π · (t − pᵢ) / (pᵢ₊₁ − pᵢ)
///     4. R = |medel(e^{iφ})|, z = n · R², p ≈ e^{−z} (Rayleigh)
///     5. din om n ≥ 12 och p < 0,01; någon annans om n ≥ 20, p > 0,2 och
///        snarkningarna har en egen takt; annars okänd
///
/// RR utan tydlig andningstopp (METOD M10, `Breathing.Estimate.isClear`) ger
/// okänd: utan andning finns ingen fas att jämföra mot.
public enum SnoreOwnership {

    // MARK: Konstanter — METOD M39

    /// METOD M39. En sekund räknas som snarkning från den här klassnivån (0–100).
    public static let snoreThreshold = 50
    /// METOD M39. Högst så här många sekunder mellanrum i en episod, och minsta längd.
    public static let episodeGapSeconds = 30
    public static let minEpisodeSeconds = 60
    /// METOD M39. Längsta block, och RR-marginalen på var sida, sekunder.
    public static let blockSeconds = 600
    public static let marginSeconds = 60
    /// METOD M39. Andningens band, Hz (som METOD M10).
    public static let band: ClosedRange<Double> = 0.15...0.40
    /// METOD M39. Tröskeln för din: minst så här många snarkningar och p under gränsen. **Antagande.**
    public static let ownMinSnores = 12
    public static let ownMaxP = 0.01
    /// METOD M39. Tröskeln för någon annans. **Antagande.**
    public static let otherMinSnores = 20
    public static let otherMinP = 0.2
    /// METOD M39. Egen takt: onset-tågets autokorrelation har en topp vid så här
    /// många sekunder och minst så här stor. **Antagande.**
    public static let rhythmLags: ClosedRange<Double> = 2...7
    public static let rhythmMinCorrelation = 0.25
    /// METOD M39. Toppar närmare än så här (sekunder) är samma andetag; ett andetag
    /// längre än 8 s eller kortare än 1,5 s är ingen andning. **Antagande.**
    public static let minPeakSpacing: Double = 2
    public static let breathPeriod: ClosedRange<Double> = 1.5...8

    private static let onsetFrameSeconds: Double = 1.0 / 16.0
    private static let axisRate: Double = 4
    private static let rhythmBin: Double = 0.1
    private static let rhythmKernel: Int = 3

    public enum Verdict: String, Codable, Equatable, Sendable {
        case yours
        case someoneElse
        case unknown
    }

    /// Ett block av en snarkepisod med sitt utlåtande.
    public struct Block: Equatable, Sendable {
        /// Första och sista sekunden i blocket (index i filen).
        public var start: Int
        public var end: Int
        /// Sekunder med snarkning ≥ 50.
        public var snoreSeconds: Int
        /// Snarkningar med en fas (n i Rayleigh-testet).
        public var snores: Int
        public var r: Double?
        public var p: Double?
        /// Hade snarkningarna en egen takt (2–7 s)?
        public var ownRhythm: Bool
        /// Fanns en tydlig andning i RR?
        public var breathingClear: Bool
        public var verdict: Verdict

        public init(start: Int, end: Int, snoreSeconds: Int, snores: Int, r: Double?, p: Double?,
                    ownRhythm: Bool, breathingClear: Bool, verdict: Verdict) {
            self.start = start
            self.end = end
            self.snoreSeconds = snoreSeconds
            self.snores = snores
            self.r = r
            self.p = p
            self.ownRhythm = ownRhythm
            self.breathingClear = breathingClear
            self.verdict = verdict
        }
    }

    // MARK: Episoder och block

    /// Snarkepisoderna delade i block: sekundintervall (index), i ordning.
    public static func blocks(_ seconds: [SoundSecond]) -> [ClosedRange<Int>] {
        let snoring: [Int] = seconds.filter { (s: SoundSecond) -> Bool in
            s.value(of: .snoring) >= snoreThreshold
        }.map { (s: SoundSecond) -> Int in s.second }.sorted()
        var out: [ClosedRange<Int>] = []
        var i = 0
        while i < snoring.count {
            var j = i
            while j + 1 < snoring.count, snoring[j + 1] - snoring[j] - 1 <= episodeGapSeconds { j += 1 }
            let first: Int = snoring[i]
            let last: Int = snoring[j]
            if last - first + 1 >= minEpisodeSeconds {
                var a: Int = first
                while a <= last {
                    out.append(a...min(last, a + blockSeconds - 1))
                    a += blockSeconds
                }
            }
            i = j + 1
        }
        return out
    }

    /// Snarkningarnas tider i blocket: Unix-sekunder med tiondelar, ur sekunden
    /// och onset-ramen. Bara sekunder med snarkning ≥ 50 och en onset.
    public static func snoreTimes(_ seconds: [SoundSecond], in block: ClosedRange<Int>, soundStart: Int) -> [Double] {
        var out: [Double] = []
        for s in seconds where block.contains(s.second) && s.value(of: .snoring) >= snoreThreshold {
            guard s.onset != SoundSecond.noOnset, s.onset < 16 else { continue }
            out.append(Double(soundStart + s.second) + (Double(s.onset) + 0.5) * onsetFrameSeconds)
        }
        return out.sorted()
    }

    // MARK: Utlåtandet

    /// Utlåtande per block i nattens ordning. `soundStart`: filens start (Unix,
    /// telefonens klocka). K18-serien är bandets; `clockOffset` är bandets tid
    /// minus telefonens (`SoundClock`, 0 när den är osäker) och lägger
    /// snarkningarna i bandets klocka. En fast skillnad ändrar nästan ingenting
    /// (se huvudet), men andningens takt varierar, så en skillnad på sekunder
    /// får fasen att glida något.
    public static func classify(_ seconds: [SoundSecond], soundStart: Int, clockOffset: Int = 0,
                                series: K18Series) -> [Block] {
        var out: [Block] = []
        for b in blocks(seconds) {
            out.append(classify(block: b, seconds: seconds, soundStart: soundStart + clockOffset, series: series))
        }
        return out
    }

    /// `soundStart` är här redan lagd i bandets klocka.
    static func classify(block: ClosedRange<Int>, seconds: [SoundSecond], soundStart: Int,
                         series: K18Series) -> Block {
        let inBlock: [SoundSecond] = seconds.filter { (s: SoundSecond) -> Bool in block.contains(s.second) }
        let snoreSeconds: Int = inBlock.filter { (s: SoundSecond) -> Bool in
            s.value(of: .snoring) >= snoreThreshold
        }.count
        let times: [Double] = snoreTimes(seconds, in: block, soundStart: soundStart)
        let rhythm: Bool = ownRhythm(times).found

        let lo: Int = soundStart + block.lowerBound - marginSeconds
        let hi: Int = soundStart + block.upperBound + 1 + marginSeconds
        let recording = K18Beats.recording(series, onset: lo, wake: hi)
        let kept: [Beat] = RRCleaning.clean(recording).filter { (b: Beat) -> Bool in b.isKept }
        let beatTimes: [Double] = kept.map { (b: Beat) -> Double in b.time }
        let beatRR: [Double] = kept.map { (b: Beat) -> Double in b.rrMilliseconds }
        let clear: Bool = Breathing.estimate(times: beatTimes, rrMilliseconds: beatRR)?.isClear ?? false

        var phaseList: [Double] = []
        if clear { phaseList = phases(snoreTimes: times, beatTimes: beatTimes, rrMilliseconds: beatRR) }
        let n: Int = phaseList.count
        var r: Double?
        var p: Double?
        var verdict: Verdict = .unknown
        if n > 0 {
            let t = rayleigh(phaseList)
            r = t.r
            p = t.p
            if n >= ownMinSnores && t.p < ownMaxP {
                verdict = .yours
            } else if n >= otherMinSnores && t.p > otherMinP && rhythm {
                verdict = .someoneElse
            }
        }
        return Block(start: block.lowerBound, end: block.upperBound, snoreSeconds: snoreSeconds, snores: n,
                     r: r, p: p, ownRhythm: rhythm, breathingClear: clear, verdict: verdict)
    }

    // MARK: Fasen

    /// Andningsfasen (0…2π) vid varje snarkning som ligger mellan två toppar i
    /// den bandpassade RR-kurvan. Snarkningar utanför, eller i ett andetag som
    /// är för långt eller kort, får ingen fas.
    public static func phases(snoreTimes: [Double], beatTimes: [Double], rrMilliseconds: [Double]) -> [Double] {
        let curve: [Double] = Breathing.resample(times: beatTimes, values: rrMilliseconds)
        guard curve.count >= 16, let origin = beatTimes.first else { return [] }
        let filtered: [Double] = bandpass(Breathing.detrended(curve))
        let tops: [Double] = peaks(filtered, origin: origin)
        guard tops.count >= 2 else { return [] }
        var out: [Double] = []
        for t in snoreTimes {
            // Sista toppen som inte ligger efter t.
            var lo = 0
            var hi = tops.count
            while lo < hi {
                let mid: Int = (lo + hi) / 2
                if tops[mid] <= t { lo = mid + 1 } else { hi = mid }
            }
            let i: Int = lo - 1
            guard i >= 0, i + 1 < tops.count else { continue }
            let period: Double = tops[i + 1] - tops[i]
            guard breathPeriod.contains(period) else { continue }
            out.append(2 * Double.pi * (t - tops[i]) / period)
        }
        return out
    }

    /// Bandpass 0,15–0,40 Hz på en jämn axel med 4 Hz: FFT, binnarna utanför
    /// bandet nollas, och tillbaka. Serien nollutfylls till en tvåpotens; de
    /// 60 sekunderna marginal på var sida tar upp kanteffekten.
    static func bandpass(_ y: [Double]) -> [Double] {
        let n: Int = y.count
        let size: Int = SoundFFT.paddedLength(n)
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for i in 0..<n { re[i] = y[i] }
        SoundFFT.transform(&re, &im)
        for k in 0..<size {
            let f: Double = Double(min(k, size - k)) * axisRate / Double(size)
            if !band.contains(f) {
                re[k] = 0
                im[k] = 0
            }
        }
        SoundFFT.transform(&re, &im, inverse: true)
        return Array(re[0..<n])
    }

    /// Topparna i kurvan som tider (Unix-sekunder): lokala maxima, förfinade med
    /// en parabel genom toppen och dess grannar. Två toppar närmare än
    /// `minPeakSpacing` är samma andetag, och den högre vinner.
    static func peaks(_ y: [Double], origin: Double) -> [Double] {
        var found: [(index: Int, time: Double, value: Double)] = []
        let spacing: Int = Int((minPeakSpacing * axisRate).rounded())
        guard y.count >= 3 else { return [] }
        for i in 1..<(y.count - 1) where y[i] > y[i - 1] && y[i] >= y[i + 1] {
            let den: Double = y[i - 1] - 2 * y[i] + y[i + 1]
            let d: Double = den < 0 ? 0.5 * (y[i - 1] - y[i + 1]) / den : 0
            let top = (index: i, time: origin + (Double(i) + d) / axisRate, value: y[i])
            if let last = found.last, i - last.index < spacing {
                if top.value > last.value { found[found.count - 1] = top }
            } else {
                found.append(top)
            }
        }
        return found.map { $0.time }
    }

    /// Rayleigh-testet: R = |medel(e^{iφ})|, z = n · R², p ≈ e^{−z}.
    public static func rayleigh(_ phases: [Double]) -> (r: Double, p: Double) {
        guard !phases.isEmpty else { return (0, 1) }
        var c: Double = 0
        var s: Double = 0
        for f in phases {
            c += cos(f)
            s += sin(f)
        }
        let n: Double = Double(phases.count)
        let r: Double = (c * c + s * s).squareRoot() / n
        return (r, exp(-n * r * r))
    }

    // MARK: Egen takt

    /// Har snarkningarna en egen takt? Tiderna läggs som en impulsföljd i
    /// 0,1-sekundersrutor, utslätad med en triangel på ± 0,3 s (så att några
    /// tiondels sekunders skakning inte spelar roll). Autokorrelationen
    /// (medelvärdet bort, delad med lag 0) söks vid 2–7 s: en topp som är en
    /// lokal topp och minst 0,25 är en egen takt.
    public static func ownRhythm(_ times: [Double]) -> (found: Bool, correlation: Double, lagSeconds: Double) {
        guard let t0 = times.min(), let t1 = times.max(), times.count >= 4 else { return (false, 0, 0) }
        let k: Int = rhythmKernel
        let n: Int = Int(((t1 - t0) / rhythmBin).rounded()) + 1 + 2 * k
        var x = [Double](repeating: 0, count: n)
        for t in times {
            let b: Int = Int(((t - t0) / rhythmBin).rounded()) + k
            for d in -k...k {
                let w: Double = 1 - Double(abs(d)) / Double(k + 1)
                if b + d >= 0 && b + d < n { x[b + d] += w }
            }
        }
        let mean: Double = x.reduce(0.0) { (a: Double, v: Double) -> Double in a + v } / Double(n)
        var r0: Double = 0
        for i in 0..<n {
            x[i] -= mean
            r0 += x[i] * x[i]
        }
        guard r0 > 0 else { return (false, 0, 0) }
        let first: Int = Int((rhythmLags.lowerBound / rhythmBin).rounded())
        let last: Int = Int((rhythmLags.upperBound / rhythmBin).rounded())
        guard n > last else { return (false, 0, 0) }
        var corr: [Double] = []
        for lag in first...last {
            var acc: Double = 0
            for i in 0..<(n - lag) { acc += x[i] * x[i + lag] }
            corr.append(acc / r0)
        }
        var best = 0
        for i in 1..<corr.count where corr[i] > corr[best] { best = i }
        let local: Bool = best > 0 && best < corr.count - 1 && corr[best] > corr[best - 1] && corr[best] > corr[best + 1]
        return (local && corr[best] >= rhythmMinCorrelation, corr[best], Double(first + best) * rhythmBin)
    }
}
