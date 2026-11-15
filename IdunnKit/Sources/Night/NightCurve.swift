import Foundation
import HeartRate

/// METOD M18
/// Nattens kurva ur Idunns slag-för-slag-data: pulsen minut för minut, RMSSD
/// och andning per 5-minutersfönster (METOD M4, M10), var pulsen nådde sin
/// lägsta punkt och hur snabbt den kom dit, glappen och slagen som saknas.
/// Och nattens form mot de egna tidigare nätterna: ett band ur nätterna före,
/// med tiden räknad som andel av natten.
///
/// Natten är hela inspelningen, från första till sista räknade slaget:
/// insomning och uppvaknande är inte skattade (METOD M8). "Efter starten"
/// betyder alltså efter att inspelningen började, inte efter insomningen.
public enum NightCurve {

    // MARK: Gränserna — METOD M18

    /// METOD M18. Pulsen räknas per hel klockminut.
    public static let minuteSeconds: TimeInterval = 60
    /// METOD M18. En minut får en puls bara med minst så många behållna slag.
    public static let minBeatsPerMinute = 20
    /// METOD M18. Fallet är nått när ett fönsters puls är högst så här många
    /// slag per minut över nattens lägsta.
    public static let fallMarginBpm: Double = 3
    /// METOD M18. Nattens form delas i så många lika långa delar.
    public static let profileBins = 48
    /// METOD M18. Den typiska natten kräver minst så många tidigare nätter.
    public static let minTypicalNights = 3
    /// METOD M18. Den typiska natten tas ur högst så många av de senaste nätterna.
    public static let maxTypicalNights = 28
    /// METOD M18. Bandet är kvartilerna: från den nedre till den övre.
    public static let lowerQuantile = 0.25
    public static let upperQuantile = 0.75

    // MARK: Resultaten

    /// En klockminut.
    public struct Minute: Equatable, Sendable {
        /// Sekunder sedan 1970, hel minut.
        public var start: TimeInterval
        /// Slag per minut: 60000 / medel av minutens behållna intervall.
        public var heartRate: Double?
        /// Alla slag som kom, även de som kastades (METOD M3).
        public var beats: Int
        public var kept: Int
        /// Slag som bandet utelämnade (METOD M3), skattade ur notisernas tider.
        public var omitted: Int

        public init(start: TimeInterval, heartRate: Double?, beats: Int, kept: Int, omitted: Int) {
            self.start = start
            self.heartRate = heartRate
            self.beats = beats
            self.kept = kept
            self.omitted = omitted
        }

        public var mid: TimeInterval { start + NightCurve.minuteSeconds / 2 }

        /// METOD M18. Andelen av minutens slag som saknas i kurvan: kastade och
        /// utelämnade, av alla som slog. 0 för en minut utan slag alls (det är
        /// ett glapp, och visas som ett).
        public var missingShare: Double {
            let alla = beats + omitted
            return alla > 0 ? Double(beats - kept + omitted) / Double(alla) : 0
        }
    }

    /// Ett 5-minutersfönster ur nattens analys (METOD M4, M5, M10).
    public struct WindowPoint: Equatable, Sendable {
        public var start: TimeInterval
        public var rmssd: Double?
        public var heartRate: Double?
        public var breathsPerMinute: Double?

        public init(start: TimeInterval, rmssd: Double?, heartRate: Double?, breathsPerMinute: Double?) {
            self.start = start
            self.rmssd = rmssd
            self.heartRate = heartRate
            self.breathsPerMinute = breathsPerMinute
        }

        public var mid: TimeInterval { start + NightAnalysis.windowSeconds / 2 }
    }

    /// METOD M18. Nattens lägsta puls: fönstret med lägst medelpuls. Vilopulsen
    /// är 10:e percentilen av fönstren (METOD M5, BESLUT B76), alltså på eller över botten.
    public struct Nadir: Equatable, Sendable {
        /// Fönstrets mitt.
        public var time: TimeInterval
        public var heartRate: Double
        /// Var i natten: 0 vid första slaget, 1 vid sista.
        public var fraction: Double
    }

    /// METOD M18. Hur snabbt pulsen sjönk: tiden från första slaget till
    /// mitten av första fönstret inom `fallMarginBpm` från nattens lägsta.
    public struct Fall: Equatable, Sendable {
        public var seconds: TimeInterval
        /// Första giltiga fönstrets puls.
        public var fromHeartRate: Double
        /// Hur mycket pulsen föll till nattens lägsta, slag per minut.
        public var drop: Double
    }

    /// METOD M18. Nattens form: pulsen och RMSSD i `profileBins` lika långa
    /// delar av natten. Sparas med nattens sammanfattning, så att den typiska
    /// natten kan räknas utan att läsa varje natts fil.
    public struct Profile: Codable, Equatable, Sendable {
        public var heartRate: [Double?]
        public var rmssd: [Double?]
        /// METOD M49 · BESLUT B63. Hudtemperaturen i °C, medel av minuternas värde i varje del. Bara en natt ur K18
        /// har den (lagren, METOD M32); `nil` för en gammal inspelning och i en sparad sammanfattning från före D2,
        /// som avkodas ändå och räknas om vid nytt bygge.
        public var skin: [Double?]? = nil

        public init(heartRate: [Double?], rmssd: [Double?], skin: [Double?]? = nil) {
            self.heartRate = heartRate
            self.rmssd = rmssd
            self.skin = skin
        }
    }

    /// En del av den typiska natten: medianen och kvartilerna över nätterna.
    public struct Band: Equatable, Sendable {
        public var bin: Int
        public var median: Double
        public var lower: Double
        public var upper: Double
        public var nights: Int

        /// Delens mitt, som andel av natten.
        public var fraction: Double { (Double(bin) + 0.5) / Double(NightCurve.profileBins) }
    }

    /// METOD M18. Den typiska natten ur de tidigare nätterna.
    public struct Typical: Equatable, Sendable {
        public var heartRate: [Band]
        public var rmssd: [Band]
        public var nights: Int
        /// METOD M49. Hudtemperaturens band i °C, absolut; vyn ritar det som avvikelse mot normalområdets medel.
        /// Tomt när för få nätter har hudtemperatur i formen.
        public var skin: [Band] = []
    }

    public struct Curve: Equatable, Sendable {
        /// Första och sista räknade slaget.
        public var start: TimeInterval
        public var end: TimeInterval
        public var minutes: [Minute]
        public var windows: [WindowPoint]
        /// METOD M13. Glappen: mer än 60 s utan notis.
        public var gaps: [ClosedRange<TimeInterval>]
        public var nadir: Nadir?
        public var fall: Fall?
        public var profile: Profile?
        /// BESLUT B99. Bandets egen puls per klockminut den sista timmen före axelns början och den första efter dess
        /// slut (`K18Night.outsideMinutes`), för Nattens kurva utanför sömnen. Tom för en gammal inspelning och där
        /// bandet låg av.
        public var outside: [Minute] = []

        /// Ett ögonblick som andel av natten.
        public func time(atFraction f: Double) -> TimeInterval { start + f * (end - start) }
    }

    /// En tidigare natt som den typiska natten ser den.
    public struct Past: Equatable, Sendable {
        public var end: Date
        public var validWindows: Int
        public var profile: Profile?

        public init(end: Date, validWindows: Int, profile: Profile?) {
            self.end = end
            self.validWindows = validWindows
            self.profile = profile
        }
    }

    // MARK: Räkningen

    /// METOD M18. Kurvan för en natt, ur samma rensade slag och analys som
    /// rapporten (`RRCleaning.clean`, `NightAnalysis.analyze(beats:)`).
    public static func make(night: NightRecording, beats: [Beat], analysis: NightAnalysis.Report) -> Curve? {
        guard let s = analysis.start?.timeIntervalSince1970,
              let e = analysis.end?.timeIntervalSince1970 else { return nil }
        let m = minutes(beats, start: s, end: e)
        let w = analysis.windows.map { (x: NightAnalysis.Window) -> WindowPoint in
            WindowPoint(start: x.start.timeIntervalSince1970, rmssd: x.rmssd,
                        heartRate: x.meanHeartRate, breathsPerMinute: x.breathing?.breathsPerMinute)
        }
        let lägsta = nadir(w, start: s, end: e)
        return Curve(start: s, end: e, minutes: m, windows: w, gaps: gaps(night),
                     nadir: lägsta, fall: lägsta.flatMap { fall(w, start: s, nadir: $0) },
                     profile: profile(minutes: m, windows: w, start: s, end: e))
    }

    /// METOD M18. Pulsen per klockminut från första till sista slaget.
    static func minutes(_ beats: [Beat], start: TimeInterval, end: TimeInterval) -> [Minute] {
        let först = Int((start / minuteSeconds).rounded(.down))
        let sist = Int((end / minuteSeconds).rounded(.down))
        guard sist >= först else { return [] }
        let n = sist - först + 1
        var alla = [Int](repeating: 0, count: n)
        var behållna = [Int](repeating: 0, count: n)
        var utelämnade = [Int](repeating: 0, count: n)
        var summa = [Double](repeating: 0, count: n)
        for b in beats {
            let k = Int((b.time / minuteSeconds).rounded(.down)) - först
            guard k >= 0 && k < n else { continue }
            alla[k] += 1
            utelämnade[k] += b.omittedBefore
            if b.isKept {
                behållna[k] += 1
                summa[k] += b.rrMilliseconds
            }
        }
        return (0..<n).map { (k: Int) -> Minute in
            let puls: Double? = behållna[k] >= minBeatsPerMinute ? 60_000 / (summa[k] / Double(behållna[k])) : nil
            return Minute(start: Double(först + k) * minuteSeconds, heartRate: puls,
                          beats: alla[k], kept: behållna[k], omitted: utelämnade[k])
        }
    }

    /// METOD M13 · METOD M18. Glappen mellan notiser, samma regel som kontrollerna.
    static func gaps(_ night: NightRecording) -> [ClosedRange<TimeInterval>] {
        let t = night.samples.map { $0.time.timeIntervalSince1970 }.sorted()
        var ut: [ClosedRange<TimeInterval>] = []
        for (a, b) in zip(t, t.dropFirst()) where b - a > RecordingQuality.gapSeconds {
            ut.append(a...b)
        }
        return ut
    }

    /// METOD M18. Fönstret med lägst medelpuls; vid lika det tidigare.
    static func nadir(_ windows: [WindowPoint], start: TimeInterval, end: TimeInterval) -> Nadir? {
        var bäst: WindowPoint?
        for w in windows.sorted(by: { $0.start < $1.start }) {
            guard let hr = w.heartRate else { continue }
            if let b = bäst, let bhr = b.heartRate, bhr <= hr { continue }
            bäst = w
        }
        guard let b = bäst, let hr = b.heartRate else { return nil }
        let längd = end - start
        let andel: Double = längd > 0 ? min(1, max(0, (b.mid - start) / längd)) : 0
        return Nadir(time: b.mid, heartRate: hr, fraction: andel)
    }

    /// METOD M18. Första fönstret inom marginalen från nattens lägsta.
    static func fall(_ windows: [WindowPoint], start: TimeInterval, nadir: Nadir) -> Fall? {
        let giltiga = windows.filter { $0.heartRate != nil }.sorted { $0.start < $1.start }
        guard let första = giltiga.first?.heartRate else { return nil }
        let gräns: Double = nadir.heartRate + fallMarginBpm
        guard let nått = giltiga.first(where: { $0.heartRate! <= gräns }) else { return nil }
        return Fall(seconds: max(0, nått.mid - start), fromHeartRate: första, drop: första - nadir.heartRate)
    }

    /// METOD M18. Nattens form: medel av minuternas puls och fönstrens RMSSD
    /// vars mitt ligger i varje del av natten. En del utan värde är `nil`.
    static func profile(minutes: [Minute], windows: [WindowPoint],
                        start: TimeInterval, end: TimeInterval) -> Profile? {
        let längd = end - start
        guard längd > 0 else { return nil }
        let n = profileBins
        func del(_ t: TimeInterval) -> Int {
            min(n - 1, max(0, Int(((t - start) / längd * Double(n)).rounded(.down))))
        }
        var puls = [[Double]](repeating: [], count: n)
        var hrv = [[Double]](repeating: [], count: n)
        for m in minutes {
            if let hr = m.heartRate { puls[del(m.mid)].append(hr) }
        }
        for w in windows {
            if let r = w.rmssd { hrv[del(w.mid)].append(r) }
        }
        return Profile(heartRate: puls.map { Statistics.mean($0) }, rmssd: hrv.map { Statistics.mean($0) })
    }

    /// METOD M49 · BESLUT B63. Hudtemperaturens form: medel av minuternas värde (°C) vars mitt ligger i varje del
    /// av natten, samma delar som pulsen och HRV (`profileBins`, andel av `start`…`end`). En del utan minut med värde
    /// är `nil`. Minuter utanför `start`…`end` räknas inte.
    public static func skinProfile(_ minutes: [NightLayers.Minute], start: TimeInterval,
                                   end: TimeInterval) -> [Double?] {
        let längd: TimeInterval = end - start
        let n: Int = profileBins
        guard längd > 0 else { return [Double?](repeating: nil, count: n) }
        var värden: [[Double]] = [[Double]](repeating: [], count: n)
        for m in minutes {
            guard let t = m.skinTemperature, m.mid >= start, m.mid <= end else { continue }
            let del: Int = min(n - 1, max(0, Int(((m.mid - start) / längd * Double(n)).rounded(.down))))
            värden[del].append(t)
        }
        return värden.map { (x: [Double]) -> Double? in Statistics.mean(x) }
    }

    /// METOD M18. Den typiska natten före `start`: nätter (minst 36 giltiga
    /// fönster, som i jämförelsen, METOD M14) som slutade före, de senaste
    /// `maxTypicalNights`. `nil` med färre än `minTypicalNights`.
    public static func typical(before start: Date, nights: [Past]) -> Typical? {
        let valda = nights
            .filter { $0.end <= start && $0.validWindows >= Trends.minValidWindows && $0.profile != nil }
            .sorted { $0.end > $1.end }
            .prefix(maxTypicalNights)
            .compactMap(\.profile)
        guard valda.count >= minTypicalNights else { return nil }
        return typical(Array(valda))
    }

    /// METOD M18. Medianen och kvartilerna i varje del, där minst
    /// `minTypicalNights` nätter har ett värde.
    static func typical(_ profiles: [Profile]) -> Typical {
        func band(_ värden: (Profile) -> [Double?]) -> [Band] {
            (0..<profileBins).compactMap { (b: Int) -> Band? in
                let x: [Double] = profiles.compactMap { (p: Profile) -> Double? in
                    let v = värden(p)
                    return v.count == profileBins ? v[b] : nil
                }
                guard x.count >= minTypicalNights, let med = Statistics.median(x) else { return nil }
                return Band(bin: b, median: med, lower: quantile(x, lowerQuantile),
                            upper: quantile(x, upperQuantile), nights: x.count)
            }
        }
        // METOD M49. Hudtemperaturen: bara nätter vars form har den.
        let hud: [Band] = band { (p: Profile) -> [Double?] in p.skin ?? [] }
        return Typical(heartRate: band(\.heartRate), rmssd: band(\.rmssd), nights: profiles.count, skin: hud)
    }

    /// Kvantil med linjär interpolation mellan de sorterade värdena (som
    /// R:s förval, typ 7). `x` får inte vara tom.
    static func quantile(_ x: [Double], _ p: Double) -> Double {
        let s = x.sorted()
        let h: Double = Double(s.count - 1) * p
        let lo = Int(h.rounded(.down))
        let hi = min(lo + 1, s.count - 1)
        return s[lo] + (h - Double(lo)) * (s[hi] - s[lo])
    }
}
