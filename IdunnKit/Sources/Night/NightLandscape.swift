import Foundation

/// METOD M22
/// Nattlandskapet: de senaste nätternas puls som åsar staplade på varandra,
/// den nyaste längst fram (nederst). Tiden är väggklockan i nattens egen zon,
/// så att två nätter som började vid samma klockslag börjar på samma ställe,
/// även över midnatt och efter en resa. Pulsen tas ur nattens kurva (METOD
/// M18) i steg om 5 minuter och sparas med nattens sammanfattning.
public enum NightLandscape {

    // MARK: Gränserna — METOD M22

    /// METOD M22. Klockans steg.
    public static let binSeconds: TimeInterval = 300
    /// METOD M22. Ett dygn i steg; stegen räknas från kl. 12 dagen natten började.
    public static let binsPerDay = 288
    /// METOD M22. Ett steg får en puls med minst så många minuter med puls.
    public static let minMinutesPerBin = 3
    /// METOD M22. Högst så många nätter, de senaste.
    public static let maxNights = 30
    /// METOD M22. Klockaxeln avrundas utåt till hela timmar (12 steg).
    public static let binsPerHour = 12
    /// METOD M22. En ås får resa sig så här många radavstånd över sin baslinje,
    /// alltså skymma de närmast bakom.
    public static let overlap: Double = 3

    // MARK: Resultaten

    /// METOD M22. En natts puls på klockan: medlet av minuternas puls i varje
    /// steg om 5 minuter, från steget `firstBin` räknat från kl. 12 lokal tid
    /// dagen natten började. Ett steg utan puls är `nil`.
    public struct Profile: Codable, Equatable, Sendable {
        public var firstBin: Int
        public var heartRate: [Double?]

        public init(firstBin: Int, heartRate: [Double?]) {
            self.firstBin = firstBin
            self.heartRate = heartRate
        }

        /// Steget efter det sista.
        public var endBin: Int { firstBin + heartRate.count }

        /// Pulsen i steget `bin` (räknat från kl. 12), eller `nil`.
        public func heartRate(atBin bin: Int) -> Double? {
            let i: Int = bin - firstBin
            guard i >= 0, i < heartRate.count else { return nil }
            return heartRate[i]
        }
    }

    /// En natt som landskapet ser den.
    public struct Night: Equatable, Sendable {
        /// Sista notisen; ordningen och datumet.
        public var end: Date
        public var utcOffsetSeconds: Int
        /// METOD M14. Nätter med färre giltiga fönster än `Trends.minValidWindows` tas inte med.
        public var validWindows: Int
        /// METOD M5. Vilopulsen.
        public var restingHeartRate: Double?
        /// METOD M4 · BESLUT B13. Nattens HRV.
        public var rmssd: Double?
        public var profile: Profile?

        public init(end: Date, utcOffsetSeconds: Int, validWindows: Int, restingHeartRate: Double?,
                    rmssd: Double?, profile: Profile?) {
            self.end = end
            self.utcOffsetSeconds = utcOffsetSeconds
            self.validWindows = validWindows
            self.restingHeartRate = restingHeartRate
            self.rmssd = rmssd
            self.profile = profile
        }

        /// METOD M14. Uppvakningsdagen.
        public var wakeDay: WakeDay { WakeDay(end, utcOffsetSeconds: utcOffsetSeconds) }
    }

    /// METOD M22. Landskapet: åsarna äldst först (bakerst, överst), klockans
    /// spann i steg och pulsens spann för alla åsar.
    public struct Scene: Equatable, Sendable {
        public var ridges: [Night]
        public var bins: ClosedRange<Int>
        public var heartRate: ClosedRange<Double>

        /// Ett steg som klockslag, minuter efter midnatt (0–1439).
        public static func clockMinutes(bin: Int) -> Int {
            ((bin * Int(binSeconds) / 60 + 12 * 60) % 1440 + 1440) % 1440
        }
    }

    // MARK: Räkningen

    /// METOD M22. Kl. 12 lokal tid närmast före ögonblicket `t`, som ett ögonblick.
    static func referenceNoon(_ t: TimeInterval, utcOffsetSeconds: Int) -> TimeInterval {
        let lokal: TimeInterval = t + TimeInterval(utcOffsetSeconds)
        let dagar: Double = ((lokal - 43_200) / 86_400).rounded(.down)
        return dagar * 86_400 + 43_200 - TimeInterval(utcOffsetSeconds)
    }

    /// METOD M22. Nattens profil ur kurvans minuter (METOD M18), i zonen natten
    /// spelades in i. Steget räknas från kl. 12 före nattens första minut med
    /// puls; ett dygn längre än så kapas. `nil` utan någon minut med puls.
    public static func profile(minutes: [NightCurve.Minute], utcOffsetSeconds: Int) -> Profile? {
        guard let först = minutes.first(where: { $0.heartRate != nil }) else { return nil }
        let middag: TimeInterval = referenceNoon(först.start, utcOffsetSeconds: utcOffsetSeconds)
        var summa = [Double](repeating: 0, count: binsPerDay)
        var antal = [Int](repeating: 0, count: binsPerDay)
        for m in minutes {
            guard let hr = m.heartRate else { continue }
            let k: Int = Int(((m.start - middag) / binSeconds).rounded(.down))
            guard k >= 0, k < binsPerDay else { continue }
            summa[k] += hr
            antal[k] += 1
        }
        guard let a = antal.firstIndex(where: { $0 > 0 }),
              let b = antal.lastIndex(where: { $0 > 0 }) else { return nil }
        let puls: [Double?] = (a...b).map { (k: Int) -> Double? in
            antal[k] >= minMinutesPerBin ? summa[k] / Double(antal[k]) : nil
        }
        guard puls.contains(where: { $0 != nil }) else { return nil }
        return Profile(firstBin: a, heartRate: puls)
    }

    /// METOD M22. Landskapet ur nätterna: de med profil och minst
    /// `Trends.minValidWindows` giltiga fönster, de `maxNights` senaste, äldst
    /// först. Klockans spann täcker alla åsar, utåt till hela timmar; pulsens
    /// spann går från lägsta till högsta steg, utåt till hela slag/min.
    public static func scene(_ nights: [Night]) -> Scene? {
        let senaste: [Night] = Array(nights
            .filter { (n: Night) -> Bool in n.validWindows >= Trends.minValidWindows && n.profile != nil }
            .sorted { (a: Night, b: Night) -> Bool in a.end > b.end }
            .prefix(maxNights))
        let valda: [Night] = Array(senaste.reversed())
        guard !valda.isEmpty else { return nil }
        var lo = Int.max
        var hi = Int.min
        var minHR = Double.infinity
        var maxHR = -Double.infinity
        for n in valda {
            guard let p = n.profile else { continue }
            lo = min(lo, p.firstBin)
            hi = max(hi, p.endBin)
            for v in p.heartRate {
                guard let v else { continue }
                minHR = min(minHR, v)
                maxHR = max(maxHR, v)
            }
        }
        guard minHR.isFinite, maxHR.isFinite else { return nil }
        let h: Int = binsPerHour
        let start: Int = Int((Double(lo) / Double(h)).rounded(.down)) * h
        let slut: Int = Int((Double(hi) / Double(h)).rounded(.up)) * h
        var golv: Double = minHR.rounded(.down)
        var tak: Double = maxHR.rounded(.up)
        if tak - golv < 1 {
            golv -= 1
            tak += 1
        }
        return Scene(ridges: valda, bins: start...max(slut, start + h), heartRate: golv...tak)
    }

    // MARK: Bilden

    /// METOD M22. Var åsarna ligger i en ruta `width` × `height` (punkter, y
    /// nedåt). Ås `i` (0 = äldst, överst) har sin baslinje `i` radavstånd under
    /// den översta, och den högsta pulsen når `overlap` radavstånd upp, så att
    /// den översta åsens topp når rutans överkant.
    public struct Layout: Equatable, Sendable {
        public var width: Double
        public var height: Double
        public var count: Int
        public var bins: ClosedRange<Int>
        public var heartRate: ClosedRange<Double>
        public var overlap: Double

        public init(width: Double, height: Double, scene: Scene, overlap: Double = NightLandscape.overlap) {
            self.width = width
            self.height = height
            self.count = scene.ridges.count
            self.bins = scene.bins
            self.heartRate = scene.heartRate
            self.overlap = overlap
        }

        /// Avståndet mellan två baslinjer.
        public var rowSpacing: Double {
            height / (Double(max(0, count - 1)) + overlap)
        }

        /// Den högsta åsens höjd över sin baslinje.
        public var ridgeHeight: Double { overlap * rowSpacing }

        public func baseline(_ i: Int) -> Double {
            ridgeHeight + Double(i) * rowSpacing
        }

        /// Stegets mitt i x.
        public func x(bin: Double) -> Double {
            let spann: Double = Double(bins.upperBound - bins.lowerBound)
            return spann > 0 ? (bin + 0.5 - Double(bins.lowerBound)) / spann * width : 0
        }

        /// Steget vid `x` (kan ligga utanför spannet).
        public func bin(x: Double) -> Int {
            let spann: Double = Double(bins.upperBound - bins.lowerBound)
            return Int((x / width * spann).rounded(.down)) + bins.lowerBound
        }

        /// Pulsen `hr` på ås `i`, i y.
        public func y(_ i: Int, heartRate hr: Double) -> Double {
            let lo: Double = heartRate.lowerBound
            let spann: Double = heartRate.upperBound - lo
            let andel: Double = spann > 0 ? (hr - lo) / spann : 0
            return baseline(i) - andel * ridgeHeight
        }

        /// METOD M22. Åsen ett tryck i (`x`, `y`) träffar: den främsta vars yta
        /// (mellan kurvan och baslinjen) täcker punkten, annars den vars
        /// baslinje ligger närmast. `nil` utan åsar.
        public func hit(x: Double, y: Double, scene: Scene) -> Int? {
            guard count > 0, scene.ridges.count == count else { return nil }
            let b: Int = bin(x: x)
            for i in stride(from: count - 1, through: 0, by: -1) {
                guard let hr = scene.ridges[i].profile?.heartRate(atBin: b) else { continue }
                if y <= baseline(i) && y >= self.y(i, heartRate: hr) { return i }
            }
            var bäst = 0
            var avstånd = Double.infinity
            for i in 0..<count {
                let d: Double = abs(baseline(i) - y)
                if d < avstånd {
                    avstånd = d
                    bäst = i
                }
            }
            return bäst
        }
    }
}
