import Foundation

/// METOD M21
/// Poincarédiagrammet för en natt: varje rensat intervall mot nästa, RR(n) mot
/// RR(n+1), med SD1 och SD2 och ellipsen de spänner upp (Brennan, Palaniswami
/// & Kamen 2001). Bara par som `RRCleaning.differences` också räknar: båda
/// slagen behållna, samma avsnitt och inget utelämnat slag emellan (BESLUT
/// B17). Molnet ritas som ett rutnät med antal per ruta, inte punkt för punkt.
public enum Poincare {

    // MARK: Gränserna — METOD M21

    /// METOD M21. Rutnätets steg: 1/128 s = 7,8125 ms, som Task Force (s. 356)
    /// anger för de geometriska metoderna.
    public static let binMilliseconds: Double = 1000.0 / 128.0
    /// METOD M21. Axeln täcker parens intervall från den här kvantilen ...
    public static let axisLowerQuantile: Double = 0.005
    /// ... till den här, så att ett fåtal udda par inte krymper molnet.
    public static let axisUpperQuantile: Double = 0.995
    /// METOD M21. Axelns ändar avrundas utåt till hela så här många ms.
    public static let axisStepMilliseconds: Double = 50
    /// METOD M21. Axeln är minst så här lång, så att en jämn natt inte blåses upp.
    public static let minAxisSpanMilliseconds: Double = 200
    /// METOD M21. Uppspelningen visar paren i ett så här långt fönster.
    public static let windowSeconds: TimeInterval = 300
    /// METOD M21 · BESLUT B32. Pulsaxelns möjliga steg i slag/min; det minsta
    /// som ger högst `maxPulseTicks` streck väljs.
    public static let pulseTickSteps: [Double] = [1, 2, 5, 10, 20, 50]
    /// METOD M21 · BESLUT B32. Högst så här många streck på pulsaxeln.
    public static let maxPulseTicks: Int = 5

    // MARK: Resultaten

    /// Ett par: intervallet `x` = RR(n) och nästa, `y` = RR(n+1). Tiden är det
    /// senare slagets, som för skillnaderna (METOD M4).
    public struct Pair: Equatable, Sendable {
        public var time: TimeInterval
        public var x: Double
        public var y: Double

        public init(time: TimeInterval, x: Double, y: Double) {
            self.time = time
            self.x = x
            self.y = y
        }
    }

    /// METOD M21. Molnets mått, alla i ms. Spridningarna delar med antalet par
    /// (n), som RMSSD (METOD M4).
    public struct Descriptors: Equatable, Sendable {
        public var count: Int
        /// Molnets mitt: medel av RR(n) och av RR(n+1).
        public var meanX: Double
        public var meanY: Double
        /// Spridningen vinkelrätt mot identitetslinjen (bredden).
        public var sd1: Double
        /// Spridningen längs identitetslinjen (längden).
        public var sd2: Double
        /// Standardavvikelsen för skillnaderna RR(n+1) − RR(n).
        public var sdsd: Double
        /// Roten ur medelkvadraten av samma skillnader.
        public var rmssd: Double
        /// Intervallens spridning: roten ur medel av Var(RR(n)) och Var(RR(n+1)).
        public var sdrr: Double

        /// SD1/SD2; `nil` när molnet saknar längd (SD2 under 1 ns, avrundningens brus).
        public var ratio: Double? { sd2 > 1e-6 ? sd1 / sd2 : nil }
    }

    /// En punkt i diagrammets plan, i ms.
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// METOD M21. Antal par per ruta. Rutorna ligger rad för rad: index =
    /// `yBin * bins + xBin`, med `lower` i hörnet nere till vänster.
    public struct Histogram: Equatable, Sendable {
        public var lower: Double
        public var binWidth: Double
        public var bins: Int
        public var counts: [Int]
        /// Par utanför axeln (de kommer inte med i rutorna).
        public var outside: Int

        public var upper: Double { lower + Double(bins) * binWidth }
        public var maxCount: Int { counts.max() ?? 0 }
        public var total: Int { counts.reduce(0, +) }

        public func count(x: Int, y: Int) -> Int {
            guard x >= 0, y >= 0, x < bins, y < bins else { return 0 }
            return counts[y * bins + x]
        }
    }

    // MARK: Räkningen

    /// METOD M21 · BESLUT B17. Paren ur nattens rensade slag, med samma regel
    /// som `RRCleaning.differences`: grannar i serien, båda behållna, samma
    /// avsnitt, och inget utelämnat slag före det senare.
    public static func pairs(_ beats: [Beat]) -> [Pair] {
        var out: [Pair] = []
        out.reserveCapacity(beats.count)
        for i in beats.indices.dropFirst() {
            let a: Beat = beats[i - 1]
            let b: Beat = beats[i]
            guard a.segment == b.segment, a.isKept, b.isKept, !b.gapBefore else { continue }
            out.append(Pair(time: b.time, x: a.rrMilliseconds, y: b.rrMilliseconds))
        }
        return out
    }

    /// METOD M21. SD1 och SD2 som spridningen kring molnets mitt i axlarna
    /// vridna 45° (Brennan m.fl. 2001, ekv. 5–6): x1 = (RR(n) − RR(n+1))/√2
    /// och x2 = (RR(n) + RR(n+1))/√2. Då är SD1 = SDSD/√2 exakt, och
    /// SD1² + SD2² = 2·SDRR² (ekv. 9). `nil` med färre än två par.
    public static func descriptors(_ pairs: [Pair]) -> Descriptors? {
        guard pairs.count >= 2 else { return nil }
        let n: Double = Double(pairs.count)
        let roten2: Double = 2.0.squareRoot()
        var sx: Double = 0
        var sy: Double = 0
        var su: Double = 0
        var sv: Double = 0
        var sd: Double = 0
        var sdd: Double = 0
        for p in pairs {
            let d: Double = p.y - p.x
            sx += p.x
            sy += p.y
            su += (p.x - p.y) / roten2
            sv += (p.x + p.y) / roten2
            sd += d
            sdd += d * d
        }
        let mx: Double = sx / n
        let my: Double = sy / n
        let mu: Double = su / n
        let mv: Double = sv / n
        let md: Double = sd / n
        var vu: Double = 0
        var vv: Double = 0
        var vd: Double = 0
        var vx: Double = 0
        var vy: Double = 0
        for p in pairs {
            let u: Double = (p.x - p.y) / roten2 - mu
            let v: Double = (p.x + p.y) / roten2 - mv
            let d: Double = p.y - p.x - md
            vu += u * u
            vv += v * v
            vd += d * d
            vx += (p.x - mx) * (p.x - mx)
            vy += (p.y - my) * (p.y - my)
        }
        let sdrr: Double = ((vx / n + vy / n) / 2).squareRoot()
        return Descriptors(count: pairs.count, meanX: mx, meanY: my,
                           sd1: (vu / n).squareRoot(), sd2: (vv / n).squareRoot(),
                           sdsd: (vd / n).squareRoot(), rmssd: (sdd / n).squareRoot(), sdrr: sdrr)
    }

    /// METOD M21. Ellipsen: mitt i molnets mitt, halvaxeln SD2 längs
    /// identitetslinjen och SD1 vinkelrätt mot den. `points` punkter runt,
    /// den första upprepad sist så att kurvan sluts.
    public static func ellipse(_ d: Descriptors, points: Int = 96) -> [Point] {
        let k: Int = max(8, points)
        let roten2: Double = 2.0.squareRoot()
        var out: [Point] = []
        out.reserveCapacity(k + 1)
        for i in 0...k {
            let a: Double = 2 * Double.pi * Double(i) / Double(k)
            let längs: Double = d.sd2 * cos(a)
            let tvärs: Double = d.sd1 * sin(a)
            // Längs (1, 1)/√2 och tvärs (−1, 1)/√2.
            let x: Double = d.meanX + (längs - tvärs) / roten2
            let y: Double = d.meanY + (längs + tvärs) / roten2
            out.append(Point(x: x, y: y))
        }
        return out
    }

    /// METOD M21. Ändpunkterna för SD1- och SD2-axlarna, från mitten.
    public static func axes(_ d: Descriptors) -> (sd1: Point, sd2: Point) {
        let roten2: Double = 2.0.squareRoot()
        let sd1 = Point(x: d.meanX - d.sd1 / roten2, y: d.meanY + d.sd1 / roten2)
        let sd2 = Point(x: d.meanX + d.sd2 / roten2, y: d.meanY + d.sd2 / roten2)
        return (sd1, sd2)
    }

    /// METOD M21. Samma axel för RR(n) och RR(n+1), så att identitetslinjen är
    /// diagonalen: kvantilerna av alla parens intervall, utåt till hela 50 ms,
    /// minst 200 ms lång. `nil` utan par.
    public static func axis(_ pairs: [Pair]) -> ClosedRange<Double>? {
        guard !pairs.isEmpty else { return nil }
        var alla: [Double] = []
        alla.reserveCapacity(pairs.count * 2)
        for p in pairs {
            alla.append(p.x)
            alla.append(p.y)
        }
        let lo0: Double = NightCurve.quantile(alla, axisLowerQuantile)
        let hi0: Double = NightCurve.quantile(alla, axisUpperQuantile)
        let steg: Double = axisStepMilliseconds
        var lo: Double = (lo0 / steg).rounded(.down) * steg
        var hi: Double = (hi0 / steg).rounded(.up) * steg
        if hi - lo < minAxisSpanMilliseconds {
            let mitt: Double = ((lo + hi) / 2 / steg).rounded() * steg
            lo = mitt - minAxisSpanMilliseconds / 2
            hi = mitt + minAxisSpanMilliseconds / 2
        }
        return lo...hi
    }

    /// METOD M21. Pulsen i slag/min för ett intervall i ms (och tvärtom).
    public static func pulse(_ milliseconds: Double) -> Double { 60_000 / milliseconds }

    /// METOD M21 · BESLUT B32. Strecken på pulsaxeln, i slag/min, lägst
    /// först: hela steg ur `pulseTickSteps` inom axeln. Axeln är i ms, så det
    /// längsta intervallet är den lägsta pulsen. Tom för en axel som inte
    /// ligger över noll.
    public static func pulseTicks(_ axis: ClosedRange<Double>) -> [Double] {
        guard axis.lowerBound > 0 else { return [] }
        let lo: Double = pulse(axis.upperBound)
        let hi: Double = pulse(axis.lowerBound)
        var ut: [Double] = []
        for steg in pulseTickSteps {
            ut = []
            var v: Double = (lo / steg).rounded(.up) * steg
            while v <= hi + 1e-9 {
                ut.append(v)
                v += steg
            }
            if ut.count <= maxPulseTicks { return ut }
        }
        return ut
    }

    /// METOD M21. Antal par per ruta på axeln, `binWidth` ms per ruta. Ett par
    /// på en rutgräns hör till rutan ovanför; den övre änden räknas till
    /// sista rutan.
    public static func histogram(_ pairs: [Pair], axis: ClosedRange<Double>,
                                 binWidth: Double = binMilliseconds) -> Histogram {
        let span: Double = axis.upperBound - axis.lowerBound
        let bins: Int = max(1, Int((span / binWidth).rounded(.up)))
        var counts = [Int](repeating: 0, count: bins * bins)
        var utanför = 0
        func ruta(_ v: Double) -> Int? {
            guard v >= axis.lowerBound, v <= axis.upperBound else { return nil }
            return min(bins - 1, Int(((v - axis.lowerBound) / binWidth).rounded(.down)))
        }
        for p in pairs {
            guard let i = ruta(p.x), let j = ruta(p.y) else {
                utanför += 1
                continue
            }
            counts[j * bins + i] += 1
        }
        return Histogram(lower: axis.lowerBound, binWidth: binWidth, bins: bins, counts: counts, outside: utanför)
    }

    /// METOD M21. Paren i fönstret (`end` − `seconds`, `end`], som index i
    /// `pairs` (som ska vara i tidsordning, som `pairs(_:)` ger dem).
    public static func window(_ pairs: [Pair], endingAt end: TimeInterval,
                              seconds: TimeInterval = windowSeconds) -> Range<Int> {
        let a: Int = firstIndex(pairs, after: end - seconds)
        let b: Int = firstIndex(pairs, after: end)
        return a..<max(a, b)
    }

    /// Första index vars tid är större än `t` (binärsökning).
    static func firstIndex(_ pairs: [Pair], after t: TimeInterval) -> Int {
        var lo = 0
        var hi = pairs.count
        while lo < hi {
            let m: Int = (lo + hi) / 2
            if pairs[m].time <= t { lo = m + 1 } else { hi = m }
        }
        return lo
    }

    /// METOD M21. Rutans klass för färgen, 1 till `classes`, på logaritmisk
    /// skala mot den fullaste rutan; 0 för en tom ruta. Logaritmen gör att
    /// både molnets kärna och dess kanter syns.
    public static func densityClass(_ count: Int, max: Int, classes: Int) -> Int {
        guard count > 0, max > 0, classes > 0 else { return 0 }
        if max == 1 { return classes }
        let t: Double = log(Double(count)) / log(Double(max))
        return Swift.min(classes, 1 + Int((t * Double(classes)).rounded(.down)))
    }
}
