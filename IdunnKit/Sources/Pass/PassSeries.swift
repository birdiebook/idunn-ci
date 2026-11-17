import Foundation

/// BESLUT B138 · METOD M79
/// Kurvorna i det sparade passet utöver pulsen: tempot och höjden över passets tid, ur spåret.
public enum PassSeries {
    /// METOD M79. Tempot räknas per hel minut av passet.
    public static let paceBucketSeconds: TimeInterval = 60
    /// METOD M79. En minut med kortare sträcka än så här (meter) har inget tempo (stillastående, METOD M77).
    public static let minBucketMeters = 30.0

    /// En punkt på en kurva: sekunder sedan Start och värdet.
    public struct Point: Equatable, Sendable {
        public var seconds: TimeInterval
        public var value: Double

        public init(seconds: TimeInterval, value: Double) {
            self.seconds = seconds
            self.value = value
        }
    }

    /// METOD M79. Tempot i sekunder per kilometer för varje hel minut av passet, vid minutens mitt: minutens
    /// sträcka (METOD M65) mot minutens tid med positioner. En minut med under 30 m har ingen punkt.
    public static func pace(_ track: [TrackPoint], start: Date) -> [Point] {
        var meter: [Int: Double] = [:]
        var sekunder: [Int: Double] = [:]
        for s in PassRoute.steps(track) {
            let t = s.t.timeIntervalSince(start)
            guard t > 0 else { continue }
            let hink = Int((t - 0.000_001) / paceBucketSeconds)
            meter[hink, default: 0] += s.meters
            sekunder[hink, default: 0] += s.seconds
        }
        return meter.keys.sorted().compactMap { (h: Int) -> Point? in
            guard let m = meter[h], let sek = sekunder[h], m >= minBucketMeters, sek > 0 else { return nil }
            return Point(seconds: (Double(h) + 0.5) * paceBucketSeconds, value: sek / (m / 1000))
        }
    }

    /// METOD M79. Höjden i meter över passets tid, ur spårets användbara positioner med höjd (METOD M65), i
    /// tidsordning. Positioner före Start är inte med.
    public static func altitude(_ track: [TrackPoint], start: Date) -> [Point] {
        PassRoute.usable(track).compactMap { (p: TrackPoint) -> Point? in
            guard let h = p.altitude else { return nil }
            let t = p.t.timeIntervalSince(start)
            guard t >= 0 else { return nil }
            return Point(seconds: t, value: h)
        }
    }

    /// METOD M79. Pulsen över passets tid, alla prov (också efter stopp), i tidsordning.
    public static func pulse(_ pass: Pass) -> [Point] {
        pass.samples.map { (s: PassSample) -> Point in
            Point(seconds: s.t.timeIntervalSince(pass.start), value: Double(s.bpm))
        }
    }

    /// Punkten närmast tiden `seconds` (för markören); `nil` utan punkter.
    public static func nearest(_ points: [Point], to seconds: TimeInterval) -> Point? {
        points.min { (a: Point, b: Point) -> Bool in abs(a.seconds - seconds) < abs(b.seconds - seconds) }
    }
}
