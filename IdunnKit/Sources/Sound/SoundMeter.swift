import Foundation

/// METOD M38 · BESLUT B47
/// Mäter en sekund ljud: 16 000 prov (Float32, 16 kHz mono) blir en
/// `SoundSecond`. Sekunden delas i 16 ramar à 1 000 prov (62,5 ms), var och en
/// med Hann-fönster, nollutfylld till 1 024 och transformerad med en egen
/// radix-2-FFT (bara Foundation, så att det går på Linux). Ur den:
///
///     level   Leq i dBFS över alla prov, ovägd
///     peak    högsta ramnivån, ovägd (ramens medel(x²) före fönstret)
///     bands   åtta oktavband, mitt 63 … 8 000 Hz, gränser fc/√2 … fc·√2,
///             normerade så att de tillsammans ger `level` (Parseval)
///     levelA  A-vägd nivå ur banden (vikterna vid bandens mitt)
///     onset   ramen där den A-vägda ramnivån steg mest (minst 6 dB, och ramen
///             minst 6 dB över golvet), annars 255
///
/// **Mätaren håller golvet själv** (`NoiseFloor`): varje sekund läggs till efter
/// mätningen, och `onset` använder golvet från före sekunden. Appen skickar
/// alltså bara prov; analysen i efterhand räknar samma golv ur de sparade
/// sekunderna (`SoundEvents`, `NoiseFloor.series`) och får samma tal.
///
/// Klasserna (`SoundSecond.classes`) kommer från SoundAnalysis i appen och
/// sätts av den som äger sekunden; mätaren lämnar dem på 0.
public struct SoundMeter: Sendable {
    // MARK: Konstanter — METOD M38

    /// METOD M38. Provtakten efter konverteringen, Hz.
    public static let sampleRate = 16_000
    /// METOD M38. Ramar per sekund och prov per ram (62,5 ms).
    public static let frameCount = 16
    public static let frameLength = 1_000
    /// METOD M38. FFT-längden: ramen nollutfylld.
    public static let fftLength = 1_024
    /// METOD M38. Oktavbandens mitt, Hz.
    public static let bandCenters: [Double] = [63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000]
    /// METOD M38 (IEC 61672-1). A-vikterna vid bandens mitt, dB.
    public static let aWeights: [Double] = [-26.2, -16.1, -8.6, -3.2, 0, 1.2, 1.0, -1.1]
    /// METOD M38. Ett steg räknas som onset från så här många dB, och ramen ska
    /// ligga lika många dB över golvet. **Antagande.**
    public static let onsetStepDB: Double = 6
    public static let onsetAboveFloorDB: Double = 6

    /// Golvet, uppdaterat med varje sekund.
    public private(set) var floor: NoiseFloor
    private var lastFrameA: Double?

    public init(floor: NoiseFloor = NoiseFloor()) {
        self.floor = floor
    }

    // MARK: Tabeller

    private static let window: [Double] = (0..<SoundMeter.frameLength).map { (n: Int) -> Double in
        0.5 - 0.5 * cos(2 * Double.pi * Double(n) / Double(SoundMeter.frameLength - 1))
    }

    private static let windowEnergy: Double = SoundMeter.window.reduce(0.0) { (s: Double, w: Double) -> Double in
        s + w * w
    }

    /// Bandet varje FFT-bin 0…512 hör till (−1 = inget band). En bin räknas till
    /// det första bandet vars gränser rymmer den, så ingen bin räknas två gånger.
    private static let bandOfBin: [Int] = (0...(SoundMeter.fftLength / 2)).map { (k: Int) -> Int in
        let f: Double = Double(k) * Double(SoundMeter.sampleRate) / Double(SoundMeter.fftLength)
        let root2: Double = 2.0.squareRoot()
        let centers: [Double] = SoundMeter.bandCenters
        for b in 0..<centers.count {
            let lo: Double = centers[b] / root2
            let hi: Double = b == centers.count - 1 ? Double.infinity : centers[b] * root2
            if f >= lo && f < hi { return b }
        }
        return -1
    }

    private static let aLinear: [Double] = SoundMeter.aWeights.map { (w: Double) -> Double in pow(10, w / 10) }

    /// 10·log10 av en effekt, med −120 dB som golv.
    static func db(_ power: Double) -> Double {
        guard power.isFinite, power > 1e-12 else { return SoundSecond.silence }
        return max(SoundSecond.silence, 10 * log10(power))
    }

    // MARK: Mätningen

    /// Mäter en sekund. `nil` om bufferten inte är exakt 16 000 prov. Icke
    /// ändliga prov räknas som 0. `second` är sekundens index i filen.
    public mutating func measure(_ samples: [Float], second: Int = 0) -> SoundSecond? {
        guard samples.count == SoundMeter.sampleRate else { return nil }
        let n: Int = SoundMeter.sampleRate
        var x = [Double](repeating: 0, count: n)
        var sumSquares: Double = 0
        for i in 0..<n {
            let v: Double = Double(samples[i])
            let w: Double = v.isFinite ? v : 0
            x[i] = w
            sumSquares += w * w
        }
        let level: Double = SoundMeter.db(sumSquares / Double(n))

        let scale: Double = 1 / (Double(SoundMeter.fftLength) * SoundMeter.windowEnergy)
        var bandPower = [Double](repeating: 0, count: SoundSecond.bandCount)
        var frameA = [Double](repeating: SoundSecond.silence, count: SoundMeter.frameCount)
        var peak: Double = SoundSecond.silence
        var re = [Double](repeating: 0, count: SoundMeter.fftLength)
        var im = [Double](repeating: 0, count: SoundMeter.fftLength)
        for f in 0..<SoundMeter.frameCount {
            let base: Int = f * SoundMeter.frameLength
            var frameSquares: Double = 0
            for i in 0..<SoundMeter.frameLength {
                let v: Double = x[base + i]
                frameSquares += v * v
                re[i] = v * SoundMeter.window[i]
                im[i] = 0
            }
            for i in SoundMeter.frameLength..<SoundMeter.fftLength {
                re[i] = 0
                im[i] = 0
            }
            peak = max(peak, SoundMeter.db(frameSquares / Double(SoundMeter.frameLength)))
            SoundFFT.transform(&re, &im)
            var perBand = [Double](repeating: 0, count: SoundSecond.bandCount)
            for k in 1...(SoundMeter.fftLength / 2) {
                let b: Int = SoundMeter.bandOfBin[k]
                if b < 0 { continue }
                // Ensidigt spektrum: alla bin utom Nyquist räknas två gånger.
                let weight: Double = k == SoundMeter.fftLength / 2 ? 1 : 2
                perBand[b] += weight * (re[k] * re[k] + im[k] * im[k])
            }
            var weighted: Double = 0
            for b in 0..<SoundSecond.bandCount {
                let p: Double = perBand[b] * scale
                bandPower[b] += p / Double(SoundMeter.frameCount)
                weighted += p * SoundMeter.aLinear[b]
            }
            frameA[f] = SoundMeter.db(weighted)
        }

        var weightedMean: Double = 0
        for b in 0..<SoundSecond.bandCount { weightedMean += bandPower[b] * SoundMeter.aLinear[b] }
        let levelA: Int16 = SoundSecond.tenths(SoundMeter.db(weightedMean))
        let bands: [Int16] = bandPower.map { (p: Double) -> Int16 in SoundSecond.tenths(SoundMeter.db(p)) }

        let onset: UInt8 = findOnset(frameA)
        lastFrameA = frameA[SoundMeter.frameCount - 1]
        floor.add(Double(levelA) / 10)

        return SoundSecond(second: second, level: SoundSecond.tenths(level), levelA: levelA,
                           peak: SoundSecond.tenths(peak), bands: bands, onset: onset)
    }

    /// Ramen där den A-vägda nivån steg mest mot ramen före, om steget är minst
    /// 6 dB och ramen ligger minst 6 dB över golvet. Första ramen jämförs mot
    /// förra sekundens sista. Utan golv (före 30 sekunder) finns ingen onset.
    private func findOnset(_ frameA: [Double]) -> UInt8 {
        guard let golv = floor.value else { return SoundSecond.noOnset }
        var best: Int = -1
        var bestStep: Double = SoundMeter.onsetStepDB
        for f in 0..<SoundMeter.frameCount {
            let before: Double? = f == 0 ? lastFrameA : frameA[f - 1]
            guard let b = before else { continue }
            let step: Double = frameA[f] - b
            if step >= bestStep && frameA[f] >= golv + SoundMeter.onsetAboveFloorDB {
                best = f
                bestStep = step
            }
        }
        return best < 0 ? SoundSecond.noOnset : UInt8(best)
    }
}
