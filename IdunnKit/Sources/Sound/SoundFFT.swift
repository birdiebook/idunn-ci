import Foundation

/// METOD M38 · METOD M39
/// En radix-2-FFT med bara Foundation (inget Accelerate, så att den går på
/// Linux). Används av `SoundMeter` (1 024 punkter per ram) och av bandpasset
/// över andningen (`SnoreOwnership`, godtycklig tvåpotens).
enum SoundFFT {

    /// Tvåpotens ≥ `n`.
    static func paddedLength(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    private static let table1024: (cos: [Double], sin: [Double]) = makeTable(1_024)

    private static func makeTable(_ n: Int) -> (cos: [Double], sin: [Double]) {
        let half = n / 2
        var c = [Double](repeating: 0, count: half)
        var s = [Double](repeating: 0, count: half)
        for k in 0..<half {
            let a: Double = 2 * Double.pi * Double(k) / Double(n)
            c[k] = cos(a)
            s[k] = -sin(a)
        }
        return (c, s)
    }

    /// Transformerar på plats. Längden ska vara en tvåpotens. `inverse` ger
    /// den omvända transformen, delad med längden.
    static func transform(_ re: inout [Double], _ im: inout [Double], inverse: Bool = false) {
        let n = re.count
        precondition(n >= 2 && n & (n - 1) == 0 && im.count == n, "FFT-längden ska vara en tvåpotens")
        let table = n == 1_024 ? table1024 : makeTable(n)

        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }

        let sign: Double = inverse ? -1 : 1
        var len = 2
        while len <= n {
            let half = len / 2
            let step = n / len
            var start = 0
            while start < n {
                for k in 0..<half {
                    let wr: Double = table.cos[k * step]
                    let wi: Double = sign * table.sin[k * step]
                    let a = start + k
                    let b = a + half
                    let tr: Double = re[b] * wr - im[b] * wi
                    let ti: Double = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
                start += len
            }
            len <<= 1
        }
        if inverse {
            let inv: Double = 1 / Double(n)
            for i in 0..<n {
                re[i] *= inv
                im[i] *= inv
            }
        }
    }
}
