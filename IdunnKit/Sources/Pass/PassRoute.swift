import Foundation

/// BESLUT B107 · METOD M63
/// En position från telefonens GPS under ett pass ute: tiden, platsen, farten som
/// telefonen uppgav, höjden och den uppgivna noggrannheten. Spåret visar var passet
/// gick och följer dataregeln som resten av passet.
public struct TrackPoint: Codable, Equatable, Sendable {
    public var t: Date
    public var lat: Double
    public var lon: Double
    /// Farten i m/s som telefonen uppgav; `nil` när den inte gav någon.
    public var speed: Double?
    /// Höjden över havet i meter; `nil` när telefonen inte gav någon.
    public var altitude: Double?
    /// Uppgiven horisontell noggrannhet i meter.
    public var accuracy: Double

    public init(t: Date, lat: Double, lon: Double, speed: Double? = nil, altitude: Double? = nil, accuracy: Double) {
        self.t = t
        self.lat = lat
        self.lon = lon
        self.speed = speed
        self.altitude = altitude
        self.accuracy = accuracy
    }
}

/// BESLUT B107 · METOD M63, M65
/// Rutten ur ett spår: sträckan, tempot, kilometertiderna, kartans utsnitt och rutten
/// delad efter pulsen. Bara räkning; kartan ligger i appen.
public enum PassRoute {
    /// METOD M65. En position med sämre uppgiven noggrannhet än så här (meter) används inte.
    public static let maxAccuracyMeters = 30.0
    /// METOD M65. Ett steg mellan två positioner som kräver högre fart än så här (m/s) är ett hopp
    /// i positionen och räknas inte in i sträckan.
    public static let maxSpeed = 12.0
    /// Jordens medelradie i meter, för avståndet mellan två positioner.
    public static let earthRadius = 6_371_000.0

    /// METOD M65. Positionerna som används: giltig noggrannhet, högst 30 m, i tidsordning.
    public static func usable(_ track: [TrackPoint]) -> [TrackPoint] {
        track.filter { $0.accuracy >= 0 && $0.accuracy <= maxAccuracyMeters }.sorted { $0.t < $1.t }
    }

    /// Avståndet i meter mellan två positioner (haversine).
    public static func meters(_ a: TrackPoint, _ b: TrackPoint) -> Double {
        let f1 = a.lat * .pi / 180
        let f2 = b.lat * .pi / 180
        let df = (b.lat - a.lat) * .pi / 180
        let dl = (b.lon - a.lon) * .pi / 180
        let h = sin(df / 2) * sin(df / 2) + cos(f1) * cos(f2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    /// METOD M65. Stegen mellan positionerna som räknas: tiden vid stegets slut, sekunderna och metrarna.
    /// Ett steg utan tid eller med orimlig fart (ett hopp) räknas inte.
    public static func steps(_ track: [TrackPoint]) -> [(t: Date, seconds: Double, meters: Double)] {
        let p = usable(track)
        guard p.count > 1 else { return [] }
        var ut: [(t: Date, seconds: Double, meters: Double)] = []
        for i in 1..<p.count {
            let dt = p[i].t.timeIntervalSince(p[i - 1].t)
            let m = meters(p[i - 1], p[i])
            guard dt > 0, m / dt <= maxSpeed else { continue }
            ut.append((p[i].t, dt, m))
        }
        return ut
    }

    /// METOD M65. Sträckan i meter.
    public static func distance(_ track: [TrackPoint]) -> Double {
        steps(track).reduce(0) { $0 + $1.meters }
    }

    /// METOD M65. Tempot i sekunder per kilometer över passets tid; `nil` under 100 m.
    public static func pace(distance: Double, seconds: Double) -> Double? {
        guard distance >= 100, seconds > 0 else { return nil }
        return seconds / (distance / 1000)
    }

    /// En hel kilometer: numret (1, 2 …) och sekunderna den tog.
    public struct Split: Equatable, Sendable {
        public var kilometer: Int
        public var seconds: Double

        public init(kilometer: Int, seconds: Double) {
            self.kilometer = kilometer
            self.seconds = seconds
        }
    }

    /// METOD M65. Tiden för varje hel kilometer, räknad från spårets första position. Gränsen läggs
    /// inom steget där kilometern passeras, i proportion till sträckan.
    public static func splits(_ track: [TrackPoint]) -> [Split] {
        let s = steps(track)
        guard let första = usable(track).first?.t else { return [] }
        var ut: [Split] = []
        var sträcka = 0.0
        var förraGräns = första
        for steg in s {
            let före = sträcka
            sträcka += steg.meters
            while sträcka >= Double(ut.count + 1) * 1000 {
                let mål = Double(ut.count + 1) * 1000
                let andel = steg.meters > 0 ? (mål - före) / steg.meters : 1
                let gräns = steg.t.addingTimeInterval(-steg.seconds * (1 - andel))
                ut.append(Split(kilometer: ut.count + 1, seconds: gräns.timeIntervalSince(förraGräns)))
                förraGräns = gräns
            }
        }
        return ut
    }

    /// Kartans utsnitt: ytterkanterna av de använda positionerna; `nil` utan positioner.
    public struct Bounds: Equatable, Sendable {
        public var minLat: Double
        public var maxLat: Double
        public var minLon: Double
        public var maxLon: Double

        public init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            self.minLat = minLat
            self.maxLat = maxLat
            self.minLon = minLon
            self.maxLon = maxLon
        }
    }

    public static func bounds(_ track: [TrackPoint]) -> Bounds? {
        let p = usable(track)
        guard let första = p.first else { return nil }
        var b = Bounds(minLat: första.lat, maxLat: första.lat, minLon: första.lon, maxLon: första.lon)
        for q in p {
            b.minLat = min(b.minLat, q.lat)
            b.maxLat = max(b.maxLat, q.lat)
            b.minLon = min(b.minLon, q.lon)
            b.maxLon = max(b.maxLon, q.lon)
        }
        return b
    }

    /// En bit av rutten med samma klass (till exempel pulszon) hela vägen.
    public struct Run: Equatable, Sendable {
        public var klass: Int
        public var points: [TrackPoint]

        public init(klass: Int, points: [TrackPoint]) {
            self.klass = klass
            self.points = points
        }
    }

    /// METOD M65. Rutten delad i bitar efter pulsen: varje position får klassen för pulsen närmast i tid
    /// (inom ±5 s, annars klassen 0), och intilliggande positioner med samma klass blir en bit. Bitarna
    /// delar sin gränspunkt, så att linjen blir hel på kartan.
    public static func runs(_ track: [TrackPoint], samples: [PassSample], classify: (Int) -> Int) -> [Run] {
        let p = usable(track)
        guard !p.isEmpty else { return [] }
        let prov = samples.sorted { $0.t < $1.t }
        var j = 0
        var ut: [Run] = []
        for q in p {
            while j + 1 < prov.count, abs(prov[j + 1].t.timeIntervalSince(q.t)) <= abs(prov[j].t.timeIntervalSince(q.t)) {
                j += 1
            }
            var klass = 0
            if j < prov.count, abs(prov[j].t.timeIntervalSince(q.t)) <= PassRules.matchToleranceSeconds {
                klass = classify(prov[j].bpm)
            }
            if let sista = ut.last, sista.klass == klass {
                ut[ut.count - 1].points.append(q)
            } else {
                if let förra = ut.last?.points.last {
                    ut.append(Run(klass: klass, points: [förra, q]))
                } else {
                    ut.append(Run(klass: klass, points: [q]))
                }
            }
        }
        return ut
    }
}
