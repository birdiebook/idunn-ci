import Foundation

/// METOD M38 · BESLUT B47
/// En ljudhändelse: aktiva sekunder med högst 3 sekunders mellanrum. Tiderna
/// är sekunder sedan filens start (`SoundSecond.second`).
public struct SoundEvent: Equatable, Sendable {
    /// Första och sista aktiva sekunden.
    public var start: Int
    public var end: Int
    /// Klassen med störst summa över händelsens aktiva sekunder.
    public var soundClass: SoundClass
    /// Högsta `peak` i händelsen, tiondels dBFS.
    public var peak: Int16
    /// Högsta `levelA` över golvet i dB; `nil` om golvet inte fanns (före 30 s).
    public var aboveFloor: Double?
    /// Antal aktiva sekunder.
    public var activeSeconds: Int

    public init(start: Int, end: Int, soundClass: SoundClass, peak: Int16, aboveFloor: Double?,
                activeSeconds: Int) {
        self.start = start
        self.end = end
        self.soundClass = soundClass
        self.peak = peak
        self.aboveFloor = aboveFloor
        self.activeSeconds = activeSeconds
    }

    /// Händelsens id i klippmappen och i `ClipPolicy`: den första sekunden.
    public var id: Int { start }
    /// Sekunder från första till sista aktiva sekunden.
    public var length: Int { end - start + 1 }
}

/// METOD M38 · BESLUT B47
/// Aktiva sekunder blir händelser. En sekund är *aktiv* om `peak` + (`levelA` −
/// `level`) ligger minst 10 dB över golvet, `levelA` minst 6 dB över, eller
/// någon klass utom andning och övrigt når 50. Aktiva sekunder med högst 3
/// sekunders mellanrum är en händelse, som delas efter 60 sekunder.
public enum SoundEvents {
    /// METOD M38. Aktiv om den ovägda toppen (A-justerad) ligger så här många dB över golvet. **Antagande.**
    public static let peakAboveFloorDB: Double = 10
    /// METOD M38. Aktiv om `levelA` ligger så här många dB över golvet. **Antagande.**
    public static let levelAboveFloorDB: Double = 6
    /// METOD M38. Aktiv om en klass (utom andning och övrigt) når så här högt. **Antagande.**
    public static let classThreshold = 50
    /// METOD M38. Högst så här många sekunder utan aktivitet inom en händelse. **Antagande.**
    public static let maxGapSeconds = 3
    /// METOD M38. En händelse delas efter så här många sekunder. **Antagande.**
    public static let maxLengthSeconds = 60

    /// Är sekunden aktiv, givet golvet före den (`nil` före 30 sekunder)?
    public static func isActive(_ s: SoundSecond, floor: Double?) -> Bool {
        for c in SoundClass.allCases where c != .breathing && c != .other {
            if s.value(of: c) >= classThreshold { return true }
        }
        guard let f = floor else { return false }
        let a: Double = s.levelADB
        if a >= f + levelAboveFloorDB { return true }
        return s.peakDB + (s.levelADB - s.levelDB) >= f + peakAboveFloorDB
    }

    /// Händelserna i en natts sekunder, i ordning. Golvet räknas ur sekunderna
    /// själva (`NoiseFloor`), som mätaren gjorde det.
    public static func detect(_ seconds: [SoundSecond]) -> [SoundEvent] {
        var d = Detector()
        var out: [SoundEvent] = []
        for s in seconds { out.append(contentsOf: d.push(s)) }
        out.append(contentsOf: d.finish())
        return out
    }

    /// Händelserna en i taget, för lyssnaren: `push` ger de händelser som
    /// sekunden avslutar, `finish` den som är öppen när lyssnaren slutar.
    public struct Detector: Sendable {
        private struct Open: Sendable {
            var start: Int
            var last: Int
            var sums: [Int]
            var peak: Int16
            var above: Double?
            var active: Int
        }

        private var floor = NoiseFloor()
        private var open: Open?

        public init() {}

        /// Första sekunden i den öppna händelsen, om en är öppen.
        public var openStart: Int? { open?.start }

        public mutating func push(_ s: SoundSecond) -> [SoundEvent] {
            var closed: [SoundEvent] = []
            if let o = open, s.second - o.last > SoundEvents.maxGapSeconds + 1 {
                closed.append(Detector.event(o))
                open = nil
            }
            let f: Double? = floor.value
            if SoundEvents.isActive(s, floor: f) {
                if let o = open, s.second - o.start >= SoundEvents.maxLengthSeconds {
                    closed.append(Detector.event(o))
                    open = nil
                }
                let above: Double? = f.map { (g: Double) -> Double in s.levelADB - g }
                if var o = open {
                    o.last = s.second
                    o.active += 1
                    o.peak = max(o.peak, s.peak)
                    if let a = above { o.above = max(o.above ?? a, a) }
                    for c in 0..<SoundSecond.classCount { o.sums[c] += s.value(of: SoundClass(rawValue: c) ?? .other) }
                    open = o
                } else {
                    var sums = [Int](repeating: 0, count: SoundSecond.classCount)
                    for c in 0..<SoundSecond.classCount { sums[c] = s.value(of: SoundClass(rawValue: c) ?? .other) }
                    open = Open(start: s.second, last: s.second, sums: sums, peak: s.peak, above: above, active: 1)
                }
            }
            floor.add(s.levelADB)
            return closed
        }

        public mutating func finish() -> [SoundEvent] {
            guard let o = open else { return [] }
            open = nil
            return [Detector.event(o)]
        }

        private static func event(_ o: Open) -> SoundEvent {
            var best = 0
            for c in 1..<o.sums.count where o.sums[c] > o.sums[best] { best = c }
            let cls: SoundClass = o.sums[best] > 0 ? (SoundClass(rawValue: best) ?? .other) : .other
            return SoundEvent(start: o.start, end: o.last, soundClass: cls, peak: o.peak, aboveFloor: o.above,
                              activeSeconds: o.active)
        }
    }
}
