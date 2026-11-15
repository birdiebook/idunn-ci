// PÅHITTADE ljudnätter (BESLUT B47, METOD M38–M40). Inget kommer från en riktig
// mikrofon eller ett riktigt band: sekunderna, K18-posterna, slagen och
// andningen räknas fram ur formler och en seedad slumpgenerator, så att varje
// körning ger exakt samma natt. Lägg ALDRIG in riktiga värden här — se CLAUDE.md
// §Dataregeln.
//
// `night` är 100 minuter i sängen (6 000 sekunder), med facit i `Truth`:
//   · 20 minuter vaken med tolv vändningar (rörelse och prassel samtidigt)
//   · insomning efter 1 200 s, uppvaknande efter 5 700 s
//   · en snarkepisod i fas med K18-nattens andning (din), 570 s
//   · tre trafikhändelser; de två första följs av en pulsreaktion och ett
//     uppvaknande, den tredje av ingenting
//   · två rörelseljud i sömnen (armen rör sig i samma sekund som prasslet);
//     det andra följs av ett uppvaknande, som inte får räknas mot ljudet
//   · en snarkepisod i egen takt (någon annans), 570 s
//   · en talepisod på 12 s
//   · bandets klocka går 7 s före telefonens (`clockOffset`)
//
// Andningen i slagen har en långsam variation i takten (±4 %), som en riktig
// andning, så att fasen mot snarkningarna inte är en ren sinus.

import Foundation
import Night
import Sound
import WhoopFrames

public enum DemoSound {

    /// Bandets tid minus telefonens, sekunder, i `night`.
    public static let clockOffset = 7

    // MARK: Facit

    /// Det som är sant om den påhittade natten. Sekunder är index i ljudfilen.
    public struct Truth: Equatable, Sendable {
        public var onset: Int
        public var wake: Int
        public var yoursEpisode: ClosedRange<Int>
        public var othersEpisode: ClosedRange<Int>
        /// Trafikhändelsernas första sekund, och om de följdes av ett uppvaknande.
        public var traffic: [Int]
        public var trafficWoke: [Bool]
        /// Rörelseljuden i sömnen (första sekunden).
        public var movementSounds: [Int]
        public var speech: ClosedRange<Int>
        /// De vakna passen i sömnen.
        public var wakeBouts: [ClosedRange<Int>]
    }

    public struct Night: Equatable, Sendable {
        /// Filens start, Unix-sekunder, telefonens klocka.
        public var start: Int
        public var clockOffset: Int
        public var seconds: [SoundSecond]
        public var series: K18Series
        public var layers: NightLayers.Layers
        public var truth: Truth
    }

    /// En kort bit med bara snarkning, för kontrollen av vems den är.
    public struct Snippet: Equatable, Sendable {
        public var start: Int
        public var seconds: [SoundSecond]
        public var series: K18Series
        /// Snarkningarnas sanna tider, sekunder efter starten.
        public var snoreTimes: [Double]
        /// Snarkningen följer andningens fas (din) eller inte.
        public var inPhase: Bool
    }

    // MARK: Andningen

    private static let variation = 0.04
    private static let variationPeriod = 97.0

    /// Andningens fas (radianer) vid tiden `t` sekunder: takten `hz` varierar ±4 %.
    private static func theta(_ t: Double, hz: Double, phase0: Double) -> Double {
        let w: Double = 2 * Double.pi
        let slow: Double = hz * variation * variationPeriod / w * (1 - cos(w * t / variationPeriod))
        return w * (hz * t + slow) + phase0
    }

    /// Tiderna då andningens fas passerar `at` (modulo 2π) var `cycles`:e andetag,
    /// med spridning `sigma` radianer och en snarkning i `share` av passagerna.
    /// `cycles` 1 ger en snarkning i fas med andningen; 1,1 ger en egen takt som
    /// ändå följer andningens variation, så att faserna fördelas jämnt.
    private static func inPhaseSnores(from t0: Double, to t1: Double, hz: Double, phase0: Double, at: Double,
                                      cycles: Double = 1, sigma: Double, share: Double,
                                      random r: inout Seeded) -> [Double] {
        let w: Double = 2 * Double.pi
        var out: [Double] = []
        var previous: Double = ((theta(t0, hz: hz, phase0: phase0) - at) / (w * cycles)).rounded(.down)
        var t: Double = t0 + 0.01
        while t < t1 {
            let cycle: Double = ((theta(t, hz: hz, phase0: phase0) - at) / (w * cycles)).rounded(.down)
            if cycle > previous {
                let when: Double = t + sigma * r.gauss() / (w * hz)
                if r.uniform() < share && when > t0 && when < t1 { out.append(when) }
            }
            previous = cycle
            t += 0.01
        }
        return out
    }

    /// Snarkningar i egen takt: var `period`:e sekund med `jitter` sekunders spridning.
    private static func ownRhythmSnores(from t0: Double, to t1: Double, period: Double, jitter: Double,
                                        random r: inout Seeded) -> [Double] {
        var out: [Double] = []
        var t: Double = t0 + 0.3
        while t < t1 {
            let when: Double = t + jitter * r.gauss()
            if when > t0 && when < t1 { out.append(when) }
            t += period
        }
        return out
    }

    // MARK: Ljudspåret

    /// Sekunderna som arrayer, byggda i omgångar: bakgrunden, händelserna, snarkningarna.
    private struct Track {
        var extra: [Double]
        var classes: [[UInt8]]
        var onset: [UInt8]
        var attack: [Bool]

        init(seconds n: Int, random r: inout Seeded) {
            extra = [Double](repeating: 0, count: n)
            onset = [UInt8](repeating: SoundSecond.noOnset, count: n)
            attack = [Bool](repeating: false, count: n)
            classes = []
            classes.reserveCapacity(n)
            for _ in 0..<n {
                var c = [UInt8](repeating: 0, count: SoundSecond.classCount)
                for k in 0..<SoundSecond.classCount { c[k] = UInt8(r.uniform() * 3) }
                c[SoundClass.breathing.rawValue] = UInt8(min(40, 10 + Int(8 * abs(r.gauss()))))
                classes.append(c)
            }
        }

        /// Ett ljud: `db` över bakgrunden i `length` sekunder, med klassens värde.
        mutating func loud(from: Int, length: Int, db: Double, _ cls: SoundClass, value: Int,
                           random r: inout Seeded) {
            let to: Int = min(extra.count, from + length)
            guard from >= 0, from < to else { return }
            for i in from..<to {
                extra[i] += db
                classes[i][cls.rawValue] = UInt8(min(100, value + Int(10 * r.uniform())))
                classes[i][SoundClass.breathing.rawValue] = 5
            }
            attack[from] = true
        }

        /// Snarkningens tid: sekundens onset-ram (första snarkningen i sekunden gäller).
        mutating func snore(at t: Double) {
            let j: Int = Int(t.rounded(.down))
            guard j >= 0, j < onset.count, onset[j] == SoundSecond.noOnset else { return }
            let frame: Int = Int(((t - Double(j)) * 16).rounded(.down))
            onset[j] = UInt8(min(15, max(0, frame)))
        }

        func seconds(random r: inout Seeded) -> [SoundSecond] {
            let shape: [Double] = [-2, -4, -7, -10, -13, -17, -21, -26]
            var out: [SoundSecond] = []
            out.reserveCapacity(extra.count)
            for i in 0..<extra.count {
                let a: Double = -60 + r.gauss() + extra[i]
                let l: Double = a + 3 + 0.3 * r.gauss()
                let attackDB: Double = attack[i] ? 3 : 0
                let p: Double = l + 3 + 0.5 * abs(r.gauss()) + attackDB
                let bands: [Int16] = shape.map { (s: Double) -> Int16 in SoundSecond.tenths(l + s) }
                out.append(SoundSecond(second: i, level: SoundSecond.tenths(l), levelA: SoundSecond.tenths(a),
                                       peak: SoundSecond.tenths(p), bands: bands, onset: onset[i],
                                       classes: classes[i]))
            }
            return out
        }
    }

    // MARK: K18

    /// En post per sekund i bandets klocka (`bandStart` + sekund): slag med
    /// andningsvåg i RR (±50 ms), en puls kring 58 med `bumps` (sekund, höjd),
    /// och gravitationen med vändningar (`bursts`: tre rörelsesekunder) och vakna
    /// pass (`wakeBouts`: tre rörelsesekunder i passets början).
    private static func k18(seconds n: Int, bandStart: Int, hz: Double, phase0: Double, bursts: [Int],
                            wakeBouts: [Int], bumps: [(at: Int, rise: Int)],
                            random r: inout Seeded) -> [K18Record] {
        var perSecond = [[Int]](repeating: [], count: n + 1)
        var t: Double = 0
        while t < Double(n) {
            let wave: Double = 50 * sin(theta(t, hz: hz, phase0: phase0))
            let rr: Double = (1_034 + wave + 15 * r.gauss()).rounded()
            t += rr / 1000
            let s: Int = Int(t.rounded(.up))
            if s <= n { perSecond[s].append(Int(rr)) }
        }

        var shift = [Double](repeating: 0, count: n)
        for s in bursts where s + 1 < n {
            shift[s] = 0.3
            shift[s + 1] = -0.3
        }
        for w in wakeBouts {
            for k in w..<min(n, w + 3) { shift[k] = k % 2 == 0 ? 0.2 : -0.2 }
        }

        var pulse = [Int](repeating: 58, count: n)
        for s in 0..<n { pulse[s] = Int((58 + r.gauss()).rounded()) }
        for b in bumps {
            for k in 4...14 where b.at + k < n {
                let ramp: Double = min(1, Double(k - 3) / 3)
                pulse[b.at + k] += Int((Double(b.rise) * ramp).rounded())
            }
        }

        var out: [K18Record] = []
        out.reserveCapacity(n)
        for s in 0..<n {
            let x: Double = shift[s] + 0.002 * r.gauss()
            let y: Double = 0.002 * r.gauss()
            let z: Double = max(0, 1 - x * x).squareRoot()
            out.append(K18Record(time: bandStart + s, pulse: pulse[s], rr: perSecond[s],
                                 gravity: K18Record.Gravity(x: x, y: y, z: z),
                                 skinTemperature: 33, bandTemperature: 30))
        }
        return out
    }

    // MARK: Natten

    /// Natten som beskrivs i filhuvudet. Samma `seed` ger samma natt.
    public static func night(seed: UInt64 = 1) -> Night {
        let n = 6_000
        let start: Int = Int(DemoNights.lastWakeDayUTC) - 4 * 3_600 // 22:00 lokal tid
        let hz = 0.25
        let phase0 = 0.7
        var rs = Seeded(seed &* 31 &+ 5)
        var rk = Seeded(seed &* 31 &+ 6)
        var rn = Seeded(seed &* 31 &+ 7)

        let onset = 1_200
        let wake = 5_700
        let yoursEpisode = 1_500...2_069
        let othersEpisode = 3_800...4_369
        let traffic: [Int] = [2_400, 3_000, 3_600]
        let trafficWoke: [Bool] = [true, true, false]
        let sleepingMoves: [Int] = [2_700, 5_000]
        let walkingMoves: [Int] = [100, 170, 300, 410, 470, 610, 650, 790, 860, 960, 1_010, 1_100]
        let speech = 4_800...4_811
        let wakeStarts: [Int] = [2_415, 3_020, 5_015]
        let wakeBouts: [ClosedRange<Int>] = [2_415...2_445, 3_020...3_050, 5_015...5_040]

        var track = Track(seconds: n, random: &rs)
        for s in walkingMoves + sleepingMoves { track.loud(from: s, length: 3, db: 20, .other, value: 40, random: &rs) }
        for s in traffic { track.loud(from: s, length: 6, db: 22, .traffic, value: 65, random: &rs) }
        track.loud(from: speech.lowerBound, length: speech.count, db: 20, .speech, value: 70, random: &rs)
        track.loud(from: yoursEpisode.lowerBound, length: yoursEpisode.count, db: 22, .snoring, value: 70,
                   random: &rs)
        track.loud(from: othersEpisode.lowerBound, length: othersEpisode.count, db: 22, .snoring, value: 70,
                   random: &rs)
        let mine: [Double] = inPhaseSnores(from: Double(yoursEpisode.lowerBound), to: Double(yoursEpisode.upperBound),
                                           hz: hz, phase0: phase0, at: 1.0, sigma: 0.5, share: 0.7, random: &rn)
        for t in mine { track.snore(at: t) }
        // Någon annans snarkning: 1,1 andetag emellan, så att den har en egen takt (cirka 4,4 s).
        let theirs: [Double] = inPhaseSnores(from: Double(othersEpisode.lowerBound),
                                             to: Double(othersEpisode.upperBound), hz: hz, phase0: phase0,
                                             at: 1.0, cycles: 1.1, sigma: 0.1, share: 1, random: &rn)
        for t in theirs { track.snore(at: t) }
        let seconds: [SoundSecond] = track.seconds(random: &rs)

        let bandStart: Int = start + clockOffset
        let records: [K18Record] = k18(seconds: n, bandStart: bandStart, hz: hz, phase0: phase0,
                                       bursts: walkingMoves + sleepingMoves, wakeBouts: wakeStarts,
                                       bumps: [(at: traffic[0], rise: 14), (at: traffic[1], rise: 12)],
                                       random: &rk)

        // Lagren i bandets klocka: sömnen utan de vakna passen.
        func band(_ s: Int) -> Double { Double(bandStart + s) }
        var asleep: [ClosedRange<Double>] = []
        var cursor: Int = onset
        for w in wakeBouts {
            asleep.append(band(cursor)...band(w.lowerBound))
            cursor = w.upperBound
        }
        asleep.append(band(cursor)...band(wake))
        let layers = NightLayers.Layers(
            start: band(0), end: band(n), minutes: [], gaps: [],
            period: band(onset)...band(wake), asleep: asleep,
            awake: wakeBouts.map { (w: ClosedRange<Int>) -> ClosedRange<Double> in band(w.lowerBound)...band(w.upperBound) },
            coverage: 1)

        let truth = Truth(onset: onset, wake: wake, yoursEpisode: yoursEpisode, othersEpisode: othersEpisode,
                          traffic: traffic, trafficWoke: trafficWoke, movementSounds: sleepingMoves,
                          speech: speech, wakeBouts: wakeBouts)
        return Night(start: start, clockOffset: clockOffset, seconds: seconds, series: K18Series(records: records),
                     layers: layers, truth: truth)
    }

    // MARK: Kontrollen

    /// En bit på 420 sekunder med 300 sekunders snarkning och en andningsvåg i
    /// slagen. Med `inPhase` följer snarkningen andningens fas; annars har den en
    /// egen takt (3,4–5,6 s, 0,25 s spridning) som skiljer sig från andningens
    /// med minst 0,02 Hz. Andningen varierar ±0,01 Hz, och en takt närmare än så
    /// kan följa den i stunder och bli "din" (METOD M39, svagheter).
    public static func snippet(seed: UInt64, inPhase: Bool) -> Snippet {
        let n = 420
        var rs = Seeded(seed &* 7919 &+ 11)
        var rk = Seeded(seed &* 7919 &+ 12)
        var rn = Seeded(seed &* 7919 &+ 13)
        let hz: Double = 0.2 + 0.1 * rn.uniform()
        let phase0: Double = 2 * Double.pi * rn.uniform()

        var track = Track(seconds: n, random: &rs)
        track.loud(from: 60, length: 300, db: 22, .snoring, value: 70, random: &rs)
        var times: [Double]
        if inPhase {
            let at: Double = 2 * Double.pi * rn.uniform()
            times = inPhaseSnores(from: 60, to: 360, hz: hz, phase0: phase0, at: at, sigma: 0.5, share: 0.7,
                                  random: &rn)
        } else {
            var period: Double = 3.4 + 2.2 * rn.uniform()
            while abs(1 / period - hz) < 0.02 { period = 3.4 + 2.2 * rn.uniform() }
            times = ownRhythmSnores(from: 60, to: 360, period: period, jitter: 0.25, random: &rn)
        }
        for t in times { track.snore(at: t) }
        let start: Int = 1_791_000_000 + Int(seed % 1_000) * 86_400
        let records: [K18Record] = k18(seconds: n, bandStart: start, hz: hz, phase0: phase0, bursts: [],
                                       wakeBouts: [], bumps: [], random: &rk)
        return Snippet(start: start, seconds: track.seconds(random: &rs), series: K18Series(records: records),
                       snoreTimes: times, inPhase: inPhase)
    }

    // MARK: Ljud till en påhittad K18-natt (J3, BESLUT B54)

    /// Ett ljud att lägga i en natt: `length` sekunder från sekund `from`, `db` över bakgrunden, med klassens värde.
    public struct Plant: Equatable, Sendable {
        public var from: Int
        public var length: Int
        public var db: Double
        public var soundClass: SoundClass
        public var value: Int

        public init(from: Int, length: Int, db: Double, soundClass: SoundClass, value: Int) {
            self.from = from
            self.length = length
            self.db = db
            self.soundClass = soundClass
            self.value = value
        }
    }

    /// `count` sekunder bakgrund med ljuden i `plants`. Samma `seed` ger samma sekunder.
    public static func seconds(count n: Int, plants: [Plant], seed: UInt64 = 1) -> [SoundSecond] {
        var rs = Seeded(seed &* 31 &+ 9)
        var track = Track(seconds: n, random: &rs)
        for p in plants {
            track.loud(from: p.from, length: p.length, db: p.db, p.soundClass, value: p.value, random: &rs)
        }
        return track.seconds(random: &rs)
    }

    /// Ljudets plan för en påhittad K18-natt (`DemoK18Nights`): filen börjar 40 minuter före insomningen och slutar
    /// 20 minuter efter uppvaknandet, och klockorna går lika (telefonens och bandets).
    public struct Plan: Equatable, Sendable {
        /// Filens start, Unix-sekunder.
        public var start: Int
        public var count: Int
        public var plants: [Plant]
        /// Trafikljudet som läggs strax före nattens första vakna stund: det som ska följas av ett uppvaknande.
        public var wakingTraffic: Int
    }

    /// En natts ljud: en snarkepisod, en trafikhändelse 25–55 s före en vaken stund (på en tid utan rörelseskur,
    /// så att den inte räknas som rörelseljud), en dörr, en hosta, ett djur, någon annans snarkning och en talepisod.
    public static func plan(layers: NightLayers.Layers, series: K18Series) -> Plan {
        let lead = 2_400
        let period = layers.period
        let start: Int = Int(period.lowerBound) - lead
        let len: Int = Int(period.upperBound - period.lowerBound)
        let bursts: [Int] = SoundClock.burstStarts(series)

        // Tiden ska ligga i sömn minst en minut efter att den började (METOD M40) och inte nära en rörelseskur.
        func fits(_ t: Int) -> Bool {
            let x: Double = Double(t)
            let asleep: Bool = layers.asleep.contains { (r: ClosedRange<TimeInterval>) -> Bool in
                r.lowerBound + 90 <= x && x <= r.upperBound
            }
            return asleep && !bursts.contains(where: { (b: Int) -> Bool in b >= t - 10 && b <= t + 4 })
        }
        var traffic: Int = lead + Int(Double(len) * 0.4)
        search: for a in layers.awake where a.lowerBound > period.lowerBound + 900 {
            for before in stride(from: 25, through: 55, by: 5) {
                let t: Int = Int(a.lowerBound) - before
                if fits(t) {
                    traffic = t - start
                    break search
                }
            }
        }
        // Övriga ljud ligger på andelar av sömnperioden, men inte nära trafiken.
        func at(_ share: Double) -> Int {
            let t: Int = lead + Int(Double(len) * share)
            return abs(t - traffic) < 150 ? t + 200 : t
        }
        let plants: [Plant] = [
            Plant(from: at(0.18), length: 480, db: 20, soundClass: .snoring, value: 70),
            Plant(from: traffic, length: 6, db: 22, soundClass: .traffic, value: 65),
            Plant(from: at(0.30), length: 3, db: 18, soundClass: .door, value: 62),
            Plant(from: at(0.50), length: 4, db: 18, soundClass: .cough, value: 60),
            Plant(from: at(0.58), length: 420, db: 20, soundClass: .snoring, value: 70),
            Plant(from: at(0.72), length: 5, db: 18, soundClass: .animal, value: 60),
            Plant(from: at(0.86), length: 10, db: 18, soundClass: .speech, value: 70),
        ]
        return Plan(start: start, count: len + lead + 1_200, plants: plants, wakingTraffic: traffic)
    }

    /// De påhittade K18-nätterna saknar andningsvåg i slagen, så analysen kan inte skilja din snarkning från
    /// någon annans: bilden i förhandsvisningen sätter ägarna för hand. Första snarkepisoden blir din, den
    /// andra någon annans, resten okända; minuterna och snarkminuterna per timme följer med. Din snarkning
    /// räknas inte som orsak (METOD M40): den följs aldrig av ett uppvaknande i bilden.
    public static func withDemoOwners(_ night: NightSound, snoringPerHour: Double) -> NightSound {
        var out: NightSound = night
        var run = -1
        var lastEnd: Double = -1e18
        for i in out.events.indices where out.events[i].isSnoring {
            if out.events[i].time - lastEnd > 30 { run += 1 }
            lastEnd = out.events[i].time + Double(out.events[i].seconds)
            let owner: NightSound.Owner = run == 0 ? .yours : (run == 1 ? .someoneElse : .unknown)
            out.events[i].owner = owner
            if owner == .yours {
                out.events[i].woke = false
                out.events[i].pulse = false
            }
        }
        func minutes(_ o: NightSound.Owner) -> Double {
            Double(out.events.filter { (e: NightSound.Event) -> Bool in e.isSnoring && e.owner == o }
                .reduce(0) { (a: Int, e: NightSound.Event) -> Int in a + e.seconds }) / 60
        }
        out.yoursMinutes = minutes(.yours)
        out.someoneElseMinutes = minutes(.someoneElse)
        out.unknownMinutes = minutes(.unknown)
        out.snoringPerHour = snoringPerHour
        return out
    }

    /// Dina snarkminuter per timme sömn `k` morgnar före den sista, påhittade för de äldre nätterna i
    /// förhandsvisningen: kring 5, och en natt av nio utan ljud (`nil`).
    public static func snoringPerHour(daysBeforeLast k: Int, seed: UInt64 = 1) -> Double? {
        if k % 9 == 4 { return nil }
        var r = Seeded(seed &+ UInt64(k) &* 104_729 &+ 77)
        let v: Double = 5 + 2.5 * r.gauss()
        return max(0, (v * 10).rounded() / 10)
    }

    /// Sammanfattningen av en äldre natts ljud ur `snoringPerHour(daysBeforeLast:)`; `nil` för en natt utan ljud.
    public static func digest(daysBeforeLast k: Int, seed: UInt64 = 1) -> NightSoundDigest? {
        guard let v = snoringPerHour(daysBeforeLast: k, seed: seed) else { return nil }
        return NightSoundDigest(snoringPerHour: v, yoursMinutes: v * 7, someoneElseMinutes: 0, unknownMinutes: 0,
                                events: 12, pulseReactions: 1, wakers: [], coverage: 0.95, clockReliable: true)
    }
}
