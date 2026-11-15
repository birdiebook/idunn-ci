import Foundation
import WhoopImport

/// METOD M17 · BESLUT B21
/// Sömnens regelbundenhet: Sleep Regularity Index (Phillips m.fl. 2017), hur
/// ofta man är i samma läge — sover eller är vaken — vid två minuter med
/// exakt ett dygn emellan. 100 när man sover och vaknar på samma minut varje
/// dag, runt 0 när sömnen ligger slumpvis.
///
/// Vardagens vyer räknar ur Idunns egna sömnperioder (BESLUT B40, METOD M33):
/// ett pass per natt ur K18, med samma modell för den vakna tiden. Ur
/// Whoop-exportens sömnpass, tupplurar inräknade, räknas det för jämförelsen.
/// Exporten har passets början och slut och summan av de vakna minuterna i
/// passet, men inte när de inträffade. Förvalet (`Variant.spreadAwake`, BESLUT B21) sprider den
/// vakna tiden jämnt över passet, som Fischer, Klerman & Phillips (2021)
/// föreslår: varje minut i passet är sömn med sannolikheten sömn / i sängen,
/// och indexet tas på den väntade andelen lika minutpar. `Variant.inBed`
/// räknar hela passet som sömn och står bredvid som jämförelse (METOD M17).
/// En gammal inspelning har ingen sömnperiod (METOD M8, M26) och ger inget pass.
public enum Regularity {

    // MARK: Gränserna — METOD M17

    /// METOD M17. Indexet tas över så många dagar, en hel vecka, som
    /// originalet (hela veckor, för att veckodagarna inte ska väga olika).
    public static let windowDays = 7
    /// METOD M17. Av veckans sex dygnspar måste så många ha båda dagarna
    /// observerade, annars inget index. Antagande.
    public static let minDayPairs = 5
    /// METOD M17. Minuter per dygn: indexet jämför minut för minut.
    public static let minutesPerDay = 1440

    // MARK: Varianterna — METOD M17 · BESLUT B21

    /// METOD M17 · BESLUT B21. Hur den vakna tiden inne i ett pass räknas.
    public enum Variant: String, CaseIterable, Sendable {
        /// Förvalet. Passets vakna minuter sprids jämnt: varje minut i passet
        /// är sömn med sannolikheten `Asleep / In bed`, oberoende mellan
        /// nätterna, och indexet tas på den väntade andelen lika minutpar.
        case spreadAwake
        /// Hela passet, från början till slut, räknas som sömn.
        case inBed
    }

    /// METOD M17 · BESLUT B21. Varianten som trenderna och morgonkortet visar.
    public static let defaultVariant: Variant = .spreadAwake

    // MARK: Indata

    /// Ett sömnpass: insomning, uppvaknande, zonen, om det är en tupplur, och
    /// exportens minuter sömn och i sängen (METOD M17).
    public struct Episode: Equatable, Sendable {
        public var onset: Date
        public var wake: Date
        public var utcOffsetSeconds: Int
        public var isNap: Bool
        /// Exportens `Asleep duration (min)`.
        public var asleepMinutes: Int?
        /// Exportens `In bed duration (min)`: uppmätt lika med passets längd
        /// och med sömn + vaken (METOD M17).
        public var inBedMinutes: Int?

        public init(onset: Date, wake: Date, utcOffsetSeconds: Int, isNap: Bool,
                    asleepMinutes: Int? = nil, inBedMinutes: Int? = nil) {
            self.onset = onset
            self.wake = wake
            self.utcOffsetSeconds = utcOffsetSeconds
            self.isNap = isNap
            self.asleepMinutes = asleepMinutes
            self.inBedMinutes = inBedMinutes
        }

        public init(_ s: Sleep) {
            self.init(onset: s.onset, wake: s.wake, utcOffsetSeconds: s.utcOffsetSeconds, isNap: s.isNap,
                      asleepMinutes: s.asleepMinutes, inBedMinutes: s.inBedMinutes)
        }

        /// METOD M33. Idunns sömnperiod (METOD M26) som ett pass: perioden från
        /// insomning till uppvaknande är tiden i sängen. Sömntiden är minuterna
        /// sömn, och den vakna tiden sprids över passet som för Whoops pass.
        /// Glapp i K18 är okänd tid, inte vaken tid: sömnens andel räknas av den
        /// del av perioden som har K18 (`coverage`, 0…1; `nil` = hela perioden),
        /// så att ett glapp inte gör en regelbunden natt oregelbunden. `nil`
        /// när perioden saknar längd.
        public static func idun(onset: Date, wake: Date, utcOffsetSeconds: Int, sleepMinutes: Double,
                                coverage: Double? = nil) -> Episode? {
            let span: Double = wake.timeIntervalSince(onset) / 60
            guard span >= 1, sleepMinutes.isFinite, sleepMinutes >= 0 else { return nil }
            let heard: Double = min(1, max(0.01, coverage ?? 1))
            let share: Double = min(1, sleepMinutes / (span * heard))
            return Episode(onset: onset, wake: wake, utcOffsetSeconds: utcOffsetSeconds, isNap: false,
                           asleepMinutes: Int((share * span).rounded()), inBedMinutes: Int(span.rounded()))
        }

        /// METOD M17. Andelen av passet som är sömn, `Asleep / In bed`, mellan 0
        /// och 1; `nil` när någon av dem saknas eller tiden i sängen är noll.
        public var asleepFraction: Double? {
            guard let a = asleepMinutes, let b = inBedMinutes, b > 0 else { return nil }
            let x: Double = Double(a) / Double(b)
            return min(1, max(0, x))
        }

        /// METOD M17 · BESLUT B21. Sannolikheten att en minut i passet är sömn.
        /// Saknas minuterna räknas hela passet som sömn, i båda varianterna.
        public func sleepProbability(_ variant: Variant) -> Double {
            switch variant {
            case .inBed: return 1
            case .spreadAwake: return asleepFraction ?? 1
            }
        }
    }

    // MARK: Räkningen

    /// METOD M17. Indexet för veckan som slutar `day`, eller `nil` när för
    /// få dygnspar är observerade.
    public static func index(_ episodes: [Episode], endingOn day: WakeDay,
                             variant: Variant = defaultVariant) -> Double? {
        let d = Days(episodes, variant: variant)
        return d.index(endingOn: day.daysSince1970)
    }

    /// METOD M17. Indexet för varje dag med en hel vecka bakom sig, rullande en
    /// dag i taget.
    public static func rolling(_ episodes: [Episode], variant: Variant = defaultVariant) -> [WakeDay: Double] {
        let d = Days(episodes, variant: variant)
        guard let first = d.observed.min(), let last = d.observed.max() else { return [:] }
        var ut: [WakeDay: Double] = [:]
        var dag = first
        while dag <= last {
            if let x = d.index(endingOn: dag) { ut[WakeDay(daysSince1970: dag)] = x }
            dag += 1
        }
        return ut
    }

    // MARK: Nattens regelbundenhet — METOD M56 · BESLUT B71

    /// METOD M56 · BESLUT B71. Natten jämförs med så många nätter före. Antagande: Whoops beskrivning ("the previous
    /// four days") och mätt på Whoop-exporten (k = 2 och 4 träffade bäst); originalet jämför bara 24 h isär.
    public static let nightComparisons = 4
    /// METOD M56 · BESLUT B65. Så många av nätterna före måste finnas: en, så att talet finns från andra natten.
    public static let nightMinComparisons = 1

    /// METOD M56 · BESLUT B71. Nattens regelbundenhet: SRI:s räkning (Phillips 2017, M17) mellan natten som slutar
    /// `day` och var och en av de `k` nätterna före, minut för minut på samma klockslag från kl. 12 dagen före till
    /// kl. 12, i SRI:s skala −100…100 (medlet av andelarna lika). `nil` när natten saknas eller färre än `minNights`
    /// av nätterna före finns. Spegel: `tools/somnpoang.py:sri_natt`.
    public static func nightIndex(_ episodes: [Episode], day: WakeDay, nights k: Int = nightComparisons,
                                  minNights: Int = nightMinComparisons, variant: Variant = defaultVariant) -> Double? {
        Days(episodes, variant: variant).nightIndex(day.daysSince1970, k: k, minNights: minNights)
    }

    /// METOD M56. Nattens regelbundenhet för varje natt som har ett tal.
    public static func nightly(_ episodes: [Episode], nights k: Int = nightComparisons,
                               minNights: Int = nightMinComparisons,
                               variant: Variant = defaultVariant) -> [WakeDay: Double] {
        let d = Days(episodes, variant: variant)
        var ut: [WakeDay: Double] = [:]
        for dag in d.observed {
            if let x = d.nightIndex(dag, k: k, minNights: minNights) { ut[WakeDay(daysSince1970: dag)] = x }
        }
        return ut
    }

    // MARK: En planerad natt — METOD M53 · METOD M56 · BESLUT B75

    /// METOD M53 · METOD M56 · BESLUT B75. Nattens regelbundenhet (`nightIndex`) för en natt som inte är sovd än, ett
    /// pass från insomning till uppvaknande med sömnens andel `sleepFraction` (1 i `inBed`), mot de `k` nätterna före i
    /// `episodes`. Nätterna före räknas en gång; varje prövad natt kostar sedan två uppslag per natt före, så att
    /// kvällens plan kan pröva läggdags i steg om 5 min för varje morgon. Ger samma tal som `nightIndex` med natten
    /// tillagd bland passen, så länge natten ligger mellan kl. 12 dagen före och kl. 12 (minuter utanför räknas inte).
    public struct PlannedNight: Sendable {
        /// Väggklockans minut sedan 1970 där nattens kurva börjar: kl. 12 dagen före uppvakningsdagen.
        let start: Int
        /// Per natt före: väntat antal olika minutpar mot kurvan utan den planerade natten.
        let base: [Double]
        /// Per natt före: summan till minut m av vad den planerade natten ändrar, (max(c, p) − c) · (1 − 2y).
        let gain: [[Double]]

        /// `nil` när färre än `minNights` av de `k` nätterna före finns: då går regelbundenheten inte att förutsäga.
        public init?(_ episodes: [Episode], day: WakeDay, sleepFraction: Double, nights k: Int = nightComparisons,
                     minNights: Int = nightMinComparisons, variant: Variant = defaultVariant) {
            guard k >= 1 else { return nil }
            let n = Regularity.minutesPerDay
            let d = day.daysSince1970
            let dagar = Days(episodes, variant: variant)
            let p: Double = variant == .inBed ? 1 : min(1, max(0, sleepFraction))
            let c: [Double] = dagar.nightCurve(d)
            var base: [Double] = []
            var gain: [[Double]] = []
            for j in 1...k {
                guard dagar.observed.contains(d - j) else { continue }
                let y: [Double] = dagar.nightCurve(d - j)
                var olika: Double = 0
                var s = [Double](repeating: 0, count: n + 1)
                for m in 0..<n {
                    olika += c[m] * (1 - y[m]) + y[m] * (1 - c[m])
                    s[m + 1] = s[m] + (max(c[m], p) - c[m]) * (1 - 2 * y[m])
                }
                base.append(olika)
                gain.append(s)
            }
            guard !base.isEmpty, base.count >= minNights else { return nil }
            self.start = (d - 1) * n + n / 2
            self.base = base
            self.gain = gain
        }

        /// Nattens regelbundenhet i SRI:s skala om natten sovs från `onset` till `wake`. Minut m hör till natten om
        /// dess början ligger i [insomning, uppvaknande), som i `nightIndex`.
        public func index(onset: Date, wake: Date, utcOffsetSeconds: Int) -> Double {
            let n = Regularity.minutesPerDay
            let off = TimeInterval(utcOffsetSeconds)
            let a: Int = Int(((onset.timeIntervalSince1970 + off) / 60).rounded(.up)) - start
            let b: Int = Int(((wake.timeIntervalSince1970 + off) / 60).rounded(.up)) - start
            let lo: Int = min(n, max(0, a))
            let hi: Int = min(n, max(lo, b))
            var lika: Double = 0
            for (olika, s) in zip(base, gain) {
                lika += 1 - (olika + s[hi] - s[lo]) / Double(n)
            }
            return -100 + 200 * lika / Double(base.count)
        }
    }

    /// METOD M17. Samma sak direkt ur exportens sömnpass.
    public static func rolling(_ sleeps: [Sleep], variant: Variant = defaultVariant) -> [WakeDay: Double] {
        rolling(sleeps.map(Episode.init), variant: variant)
    }

    /// METOD M17 · BESLUT B21. Båda varianterna ur exportens sömnpass, för att
    /// kunna visa dem bredvid varandra.
    public static func rollingVariants(_ sleeps: [Sleep]) -> [Variant: [WakeDay: Double]] {
        let e: [Episode] = sleeps.map(Episode.init)
        var ut: [Variant: [WakeDay: Double]] = [:]
        for v in Variant.allCases { ut[v] = rolling(e, variant: v) }
        return ut
    }

    /// Dagarna minut för minut, i väggklockans tid där varje pass sovs.
    struct Days {
        /// METOD M17 · BESLUT B21. Sannolikheten att man sover minut j av dag d
        /// (dagar sedan 1970, väggklocka): 0 utanför passen, 1 i ett pass i
        /// `inBed`, och passets andel sömn i `spreadAwake`.
        var asleep: [Int: [Double]] = [:]
        /// METOD M17. Dagar som är observerade: ett nattpass vaknar den dagen.
        var observed: Set<Int> = []

        init(_ episodes: [Episode], variant: Variant) {
            let n = Regularity.minutesPerDay
            for e in episodes {
                let off = TimeInterval(e.utcOffsetSeconds)
                // Minut m hör till passet om dess början ligger i [insomning, uppvaknande).
                let lo = Int(((e.onset.timeIntervalSince1970 + off) / 60).rounded(.up))
                let hi = Int(((e.wake.timeIntervalSince1970 + off) / 60).rounded(.up))
                if !e.isNap {
                    observed.insert(WakeDay(e.wake, utcOffsetSeconds: e.utcOffsetSeconds).daysSince1970)
                }
                guard hi > lo else { continue }
                let p: Double = e.sleepProbability(variant)
                for m in lo..<hi {
                    let dag = Int((Double(m) / Double(n)).rounded(.down))
                    let j = m - dag * n
                    // Pass som överlappar: den högsta sannolikheten gäller.
                    let förut: Double = asleep[dag]?[j] ?? 0
                    asleep[dag, default: [Double](repeating: 0, count: n)][j] = max(förut, p)
                }
            }
        }

        /// METOD M17 · BESLUT B21. Väntat antal minuter där dag `i` och dag
        /// `i + 1` är i olika läge; `nil` om någon av dagarna inte är observerad.
        /// Med sannolikheterna a och b för sömn, oberoende mellan nätterna, är
        /// minutparet olika med sannolikheten a(1 − b) + b(1 − a). Med bara 0
        /// och 1 är det antalet olika minuter.
        func disagreements(_ i: Int) -> Double? {
            guard observed.contains(i), observed.contains(i + 1) else { return nil }
            let n = Regularity.minutesPerDay
            let tom = [Double](repeating: 0, count: n)
            let a: [Double] = asleep[i] ?? tom
            let b: [Double] = asleep[i + 1] ?? tom
            var olika: Double = 0
            for j in 0..<n {
                let x: Double = a[j] * (1 - b[j]) + b[j] * (1 - a[j])
                olika += x
            }
            return olika
        }

        /// METOD M17. SRI = −100 + 200 · andelen minutpar i samma läge, över
        /// veckans dygnspar där båda dagarna är observerade; i `spreadAwake`
        /// den väntade andelen.
        func index(endingOn day: Int) -> Double? {
            let n = Regularity.minutesPerDay
            var par = 0
            var olika: Double = 0
            for i in (day - Regularity.windowDays + 1)..<day {
                guard let x = disagreements(i) else { continue }
                par += 1
                olika += x
            }
            guard par >= Regularity.minDayPairs else { return nil }
            let alla: Double = Double(par * n)
            let lika: Double = alla - olika
            return -100 + 200 * (lika / alla)
        }

        /// METOD M56. Sömnens sannolikhet minut för minut från kl. 12 dagen före till kl. 12 på dagen `d`.
        func nightCurve(_ d: Int) -> [Double] {
            let n = Regularity.minutesPerDay
            let h = n / 2
            let tom = [Double](repeating: 0, count: n)
            let a: [Double] = asleep[d - 1] ?? tom
            let b: [Double] = asleep[d] ?? tom
            return Array(a[h..<n]) + Array(b[0..<h])
        }

        /// METOD M56. Natten `d` mot var och en av de `k` nätterna före som är observerade: väntad andel lika
        /// minutpar per natt, medlet av dem i SRI:s skala.
        func nightIndex(_ d: Int, k: Int, minNights: Int) -> Double? {
            guard observed.contains(d), k >= 1 else { return nil }
            let n = Regularity.minutesPerDay
            let x: [Double] = nightCurve(d)
            var lika: [Double] = []
            for j in 1...k {
                guard observed.contains(d - j) else { continue }
                let y: [Double] = nightCurve(d - j)
                var olika: Double = 0
                for m in 0..<n {
                    olika += x[m] * (1 - y[m]) + y[m] * (1 - x[m])
                }
                lika.append(1 - olika / Double(n))
            }
            guard !lika.isEmpty, lika.count >= minNights else { return nil }
            let medel: Double = lika.reduce(0, +) / Double(lika.count)
            return -100 + 200 * medel
        }
    }
}
