import Foundation

/// METOD M38 · BESLUT B47
/// Nattens golv: 10:e percentilen av `levelA` de senaste 600 sekunderna, alltså
/// L90, bakgrundsnivån. Först när minst 30 sekunder finns. Percentilen är
/// rangen ceil(0,1 · n), så att talen blir desamma på alla plattformar.
/// Värdetyp: appen och analysen räknar samma golv ur samma sekunder.
public struct NoiseFloor: Equatable, Sendable {
    /// METOD M38. Fönstret, sekunder. **Antagande.**
    public static let windowSeconds = 600
    /// METOD M38. Minst så här många sekunder före första golvet. **Antagande.**
    public static let minimumSeconds = 30

    private var recent: [Double] = []
    private var sorted: [Double] = []

    public init() {}

    /// Antal sekunder i fönstret.
    public var count: Int { recent.count }

    /// Golvet i dB (A-vägt), eller `nil` före `minimumSeconds` sekunder.
    public var value: Double? {
        guard recent.count >= NoiseFloor.minimumSeconds else { return nil }
        let rank: Int = max(0, (sorted.count + 9) / 10 - 1)
        return sorted[rank]
    }

    /// Lägger till en sekunds A-vägda nivå (dB) och glömmer den äldsta över 600.
    public mutating func add(_ levelA: Double) {
        recent.append(levelA)
        sorted.insert(levelA, at: NoiseFloor.lowerBound(sorted, levelA))
        if recent.count > NoiseFloor.windowSeconds {
            let old: Double = recent.removeFirst()
            let i: Int = NoiseFloor.lowerBound(sorted, old)
            if i < sorted.count { sorted.remove(at: i) }
        }
    }

    /// Golvet före varje sekund i `seconds` (som `SoundEvents` ser det), i ordning.
    public static func series(_ seconds: [SoundSecond]) -> [Double?] {
        var f = NoiseFloor()
        var out: [Double?] = []
        out.reserveCapacity(seconds.count)
        for s in seconds {
            out.append(f.value)
            f.add(s.levelADB)
        }
        return out
    }

    /// Första index i den sorterade listan vars värde inte är mindre än `v`.
    private static func lowerBound(_ a: [Double], _ v: Double) -> Int {
        var lo = 0
        var hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < v { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
