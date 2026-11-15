import Foundation

/// METOD M24 · METOD M15 · BESLUT B26
/// En K18-post: bandets historik, en per sekund (PROTOKOLL_W5 §6). Fälten
/// avkodas som `tools/k18_analys.py` gör det, som är facit.
///
/// Offseten räknas i ramens inre del (efter huvudet, före CRC32): typ 47 i
/// byte 0, familj 18 i byte 1.
public struct K18Record: Equatable, Sendable {
    public struct Gravity: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }

        /// Avståndet mellan två lägen i g.
        public func distance(to o: Gravity) -> Double {
            let dx = x - o.x, dy = y - o.y, dz = z - o.z
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }

        /// Längden i g: ungefär 1 när bandet vilar (jordens dragning).
        public var length: Double { (x * x + y * y + z * z).squareRoot() }
    }

    /// i7, u32: Unix-sekunder.
    public var time: Int
    /// i14, u8: puls i slag per minut.
    public var pulse: Int
    /// i16…, u16 LE: RR i ms, så många som i15 anger (högst fyra, som facit).
    public var rr: [Int]
    /// i37, i41, i45, f32 LE: gravitationen i g.
    public var gravity: Gravity
    /// i65, u16 LE / 100: temperatur i °C, troligen huden.
    public var skinTemperature: Double
    /// i61, u16 LE / 10: andra temperaturen i °C, troligen bandets egen.
    public var bandTemperature: Double

    public init(time: Int, pulse: Int, rr: [Int], gravity: Gravity,
                skinTemperature: Double, bandTemperature: Double) {
        self.time = time
        self.pulse = pulse
        self.rr = rr
        self.gravity = gravity
        self.skinTemperature = skinTemperature
        self.bandTemperature = bandTemperature
    }

    public static let packetType = 47
    public static let family = 18
    /// Kortare inre delar är inte K18-poster (facit hoppar över dem).
    public static let minimumLength = 112
    static let maxRR = 4

    /// Avkodar en ramens inre del. `nil` om den inte är typ 47 / familj 18
    /// eller är för kort.
    public static func decode(inner b: [UInt8]) -> K18Record? {
        guard b.count >= minimumLength, Int(b[0]) == packetType, Int(b[1]) == family,
              let t = FrameAssembly.u32(b, at: 7) else { return nil }
        let n = min(Int(b[15]), maxRR)
        let rr = (0..<n).map { u16(b, at: 16 + 2 * $0) }
        func g(_ off: Int) -> Double {
            Double(Float(bitPattern: FrameAssembly.u32(b, at: off) ?? 0))
        }
        return K18Record(time: Int(t), pulse: Int(b[14]), rr: rr,
                         gravity: Gravity(x: g(37), y: g(41), z: g(45)),
                         skinTemperature: Double(u16(b, at: 65)) / 100,
                         bandTemperature: Double(u16(b, at: 61)) / 10)
    }

    private static func u16(_ b: [UInt8], at o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8)
    }
}

/// METOD M24. Nattens K18-poster som en serie per sekund, och det som räknas
/// ur den: rörelse, temperatur per minut och täckning.
public struct K18Series: Equatable, Sendable {
    /// Sorterad på tid, högst en post per sekund.
    public private(set) var records: [K18Record]
    /// Poster som kom en gång till för en sekund som redan fanns.
    public private(set) var duplicates = 0
    /// K18-ramar vars CRC32 inte stämde. De räknas inte med.
    public private(set) var badChecksums = 0

    /// Rörelsen en sekund: |Δg| mot sekunden före.
    public struct Movement: Equatable, Sendable {
        public var time: Int
        public var value: Double
    }

    /// En minut med minst en post. Minuten är Unix-minuten (`time / 60`).
    public struct Minute: Equatable, Sendable {
        public var minute: Int
        /// Antal poster (sekunder) i minuten.
        public var seconds: Int
        /// Medel av |Δg| över minutens sekunder med rörelse; `nil` om ingen
        /// sekund har en föregående sekund att jämföra med.
        public var movement: Double?
        /// Median av hudtemperaturen i °C.
        public var skinTemperature: Double
        /// Median av bandets temperatur i °C.
        public var bandTemperature: Double

        public var start: Date { Date(timeIntervalSince1970: Double(minute * 60)) }
    }

    public struct Coverage: Equatable, Sendable {
        public var coveredMinutes: Int
        public var totalMinutes: Int
        public var fraction: Double { Double(coveredMinutes) / Double(totalMinutes) }
    }

    /// Poster i valfri ordning; samma sekund två gånger blir en post (den
    /// senaste gäller, som facit).
    public init(records all: [K18Record]) {
        var bySecond: [Int: K18Record] = [:]
        var dupes = 0
        for r in all {
            if bySecond.updateValue(r, forKey: r.time) != nil { dupes += 1 }
        }
        records = bySecond.values.sorted { $0.time < $1.time }
        duplicates = dupes
    }

    /// Ur nattens notiser (det `.t2.jsonl` innehåller): fogar ihop ramarna
    /// (`FrameAssembly`) och avkodar typ 47 / familj 18.
    public init(notifications: [RawFrame]) {
        let (frames, _) = FrameAssembly.assemble(notifications)
        var all: [K18Record] = []
        var bad = 0
        for f in frames where f.type == K18Record.packetType {
            guard f.inner.count > 1, Int(f.inner[1]) == K18Record.family else { continue }
            guard f.crc32OK else {
                bad += 1
                continue
            }
            if let r = K18Record.decode(inner: f.inner) { all.append(r) }
        }
        self.init(records: all)
        badChecksums = bad
    }

    /// BESLUT B41 · METOD M34. Ur dygnsarkivet: samma poster, och samma antal
    /// K18-ramar med fel CRC32, som rådygnet ger (provat båda vägarna).
    public init(archive: DayArchive) {
        self.init(records: archive.k18Records)
        badChecksums = archive.badK18Checksums
    }

    /// Flera arkiv efter varandra (dygnen i den ordning de läses), som
    /// `K18Series(notifications:)` över deras rådygn efter varandra.
    public init(archives: [DayArchive]) {
        self.init(records: archives.flatMap { (a: DayArchive) -> [K18Record] in a.k18Records })
        badChecksums = archives.reduce(0) { (s: Int, a: DayArchive) -> Int in s + a.badK18Checksums }
    }

    /// Rörelse per sekund. Den första sekunden i varje obruten följd saknas:
    /// ingen Δ över ett glapp (facit: bara när tiden steg med exakt 1).
    public var movementPerSecond: [Movement] {
        zip(records, records.dropFirst()).compactMap { a, b in
            guard b.time - a.time == 1 else { return nil }
            let d = a.gravity.distance(to: b.gravity)
            return d.isFinite ? Movement(time: b.time, value: d) : nil
        }
    }

    /// Per minut med minst en post, i tidsordning. Minuter utan poster är
    /// inte med: de är tomma, inte noll.
    public var minutes: [Minute] {
        var moves: [Int: [Double]] = [:]
        for m in movementPerSecond { moves[m.time / 60, default: []].append(m.value) }
        var out: [Minute] = []
        var i = 0
        while i < records.count {
            let minute = records[i].time / 60
            var j = i
            while j < records.count, records[j].time / 60 == minute { j += 1 }
            let group = records[i..<j]
            let mv = moves[minute]
            out.append(Minute(minute: minute, seconds: group.count,
                              movement: mv.map { $0.reduce(0, +) / Double($0.count) },
                              skinTemperature: Self.median(group.map(\.skinTemperature)),
                              bandTemperature: Self.median(group.map(\.bandTemperature))))
            i = j
        }
        return out
    }

    /// Andelen av intervallets minuter som har minst en post. Minuterna är de
    /// Unix-minuter intervallet rör vid, från `from` till och med minuten med
    /// sekunden före `to`. `nil` för ett tomt eller vänt intervall.
    public func coverage(from: Date, to: Date) -> Coverage? {
        guard let range = Self.minuteRange(from: from, to: to) else { return nil }
        let have = Set(records.map { $0.time / 60 })
        return Coverage(coveredMinutes: range.filter { have.contains($0) }.count,
                        totalMinutes: range.count)
    }

    /// Unix-minuterna ett intervall rör vid (se `coverage`); `nil` för ett
    /// tomt eller vänt intervall.
    static func minuteRange(from: Date, to: Date) -> Range<Int>? {
        guard to > from else { return nil }
        let first = Int((from.timeIntervalSince1970 / 60).rounded(.down))
        let end = Int((to.timeIntervalSince1970 / 60).rounded(.up))
        return end > first ? first..<end : nil
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
