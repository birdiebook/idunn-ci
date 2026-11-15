import Foundation
import Night
import WhoopFrames

/// En liten seedad slumpgenerator (SplitMix64, som `Seeded` i DemoData) för
/// kontrolltiderna: samma natt ger samma kontroller.
struct SoundRandom {
    private var x: UInt64

    init(seed: UInt64) { x = seed }

    mutating func next() -> UInt64 {
        x = x &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Ett heltal 0 ..< n.
    mutating func below(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
}

/// METOD M40 · BESLUT B47
/// Vad som följde en ljudhändelse. Händelser som inte är din snarkning (METOD
/// M39), som börjar i sömn (`Layers.asleep`, sovit minst 60 s) och inte är
/// *rörelseljud*, räknas mot tre saker:
///
///     rörelseljud   K18-rörelse över METOD M32:s gräns som börjar högst 1 s
///                   före ljudet (efter klockan): då är ljudet följden, inte
///                   orsaken, och händelsen räknas aldrig som orsak
///     pulsreaktion  högsta pulsen 1–30 s efter starten minus medel 10 s före
///                   är minst 8 slag/min (Basner m.fl. 2019 skattar uppvaknanden
///                   efter flygbuller ur pulsökningar; gränsen 8 är antagande)
///     uppvaknande   ett vaket pass (`Layers.awake`) börjar 0–60 s efter starten
///
/// **Kontrollen:** samma räkning vid slumpade tider i sömn utan händelse inom
/// ±120 s, fem per händelse, med natten som frö. Effekten är andelen efter
/// händelser minus andelen vid kontrollerna, per klass och per nivåsteg
/// (golv +10–20, +20–30, över +30 dB).
public struct SoundResponse: Equatable, Sendable {

    // MARK: Konstanter — METOD M40

    /// METOD M40. Sovit minst så här länge före händelsen. **Antagande.**
    public static let minSleepBeforeSeconds = 60
    /// METOD M40. Pulsen före: medel över så här många sekunder före starten, och
    /// minst så här många värden. **Antagande.**
    public static let pulseBeforeSeconds = 10
    static let minPulseBefore = 5
    /// METOD M40. Pulsen efter: högsta värdet 1–30 s efter, minst så här många värden.
    public static let pulseAfterSeconds = 30
    static let minPulseAfter = 10
    /// METOD M40. Pulsreaktion från så här många slag/min (Basner m.fl. 2019). **Antagande.**
    public static let pulseRiseBpm: Double = 8
    /// METOD M40. Uppvaknande om ett vaket pass börjar inom så här många sekunder. **Antagande.**
    public static let awakeWithinSeconds = 60
    /// METOD M40. Kontroller per händelse, och avståndet till närmaste händelse. **Antagande.**
    public static let controlsPerEvent = 5
    public static let controlExclusionSeconds = 120
    /// METOD M40. Nivåstegen över golvet, dB: +10–20, +20–30, över +30.
    public static let levelSteps: [Double] = [10, 20, 30]

    // MARK: Resultaten

    /// En händelse med sitt utfall.
    public struct Item: Equatable, Sendable {
        public var event: SoundEvent
        /// Händelsens start i bandets klocka (Unix-sekunder, efter klockskillnaden).
        public var bandTime: Int
        public var movementSound: Bool
        /// Pulsstegringen i slag/min, eller `nil` när pulsen saknas.
        public var pulseRise: Double?
        public var pulseReaction: Bool
        public var awakening: Bool
        /// 0: golv +10–20 dB, 1: +20–30, 2: över +30; `nil` under +10 eller utan golv.
        public var levelStep: Int?

        /// Rörelseljud räknas aldrig som orsak.
        public var counted: Bool { !movementSound }

        public init(event: SoundEvent, bandTime: Int, movementSound: Bool, pulseRise: Double?,
                    pulseReaction: Bool, awakening: Bool, levelStep: Int?) {
            self.event = event
            self.bandTime = bandTime
            self.movementSound = movementSound
            self.pulseRise = pulseRise
            self.pulseReaction = pulseReaction
            self.awakening = awakening
            self.levelStep = levelStep
        }
    }

    /// Antal efter händelser och vid kontrollerna.
    public struct Rate: Equatable, Sendable {
        public var events = 0
        public var awakenings = 0
        public var pulseReactions = 0
        public var controls = 0
        public var controlAwakenings = 0
        public var controlPulseReactions = 0

        public init() {}

        public var awakeningShare: Double? { events > 0 ? Double(awakenings) / Double(events) : nil }
        public var pulseShare: Double? { events > 0 ? Double(pulseReactions) / Double(events) : nil }
        public var controlAwakeningShare: Double? {
            controls > 0 ? Double(controlAwakenings) / Double(controls) : nil
        }
        public var controlPulseShare: Double? {
            controls > 0 ? Double(controlPulseReactions) / Double(controls) : nil
        }

        /// Andelen uppvaknanden efter händelser minus andelen vid kontrollerna.
        public var awakeningEffect: Double? {
            guard let a = awakeningShare, let c = controlAwakeningShare else { return nil }
            return a - c
        }

        /// Andelen pulsreaktioner efter händelser minus andelen vid kontrollerna.
        public var pulseEffect: Double? {
            guard let a = pulseShare, let c = controlPulseShare else { return nil }
            return a - c
        }
    }

    /// Alla händelser som kom ifråga (inte din snarkning, i sömn), rörelseljuden med.
    public var items: [Item]
    /// Räkningen över de händelser som räknas som orsak.
    public var overall: Rate
    /// Per klass (index = `SoundClass.rawValue`) och per nivåsteg (0–2).
    public var perClass: [Rate]
    public var perStep: [Rate]

    public init(items: [Item] = [], overall: Rate = Rate(),
                perClass: [Rate] = [Rate](repeating: Rate(), count: 12),
                perStep: [Rate] = [Rate](repeating: Rate(), count: 3)) {
        self.items = items
        self.overall = overall
        self.perClass = perClass
        self.perStep = perStep
    }

    /// Händelser som följdes av ett uppvaknande, utan rörelseljuden.
    public var awakenings: Int { items.filter { (i: Item) -> Bool in i.counted && i.awakening }.count }
    /// Händelser som följdes av en pulsreaktion, utan rörelseljuden.
    public var pulseReactions: Int { items.filter { (i: Item) -> Bool in i.counted && i.pulseReaction }.count }

    // MARK: Räkningen

    /// Räknar nattens händelser. `soundStart`: filens start (Unix, telefonens klocka).
    /// `blocks`: utlåtandena om snarkningen (METOD M39), så att din snarkning hålls utanför.
    public static func compute(events: [SoundEvent], blocks: [SnoreOwnership.Block], soundStart: Int,
                               clock: SoundClock.Estimate, series: K18Series,
                               layers: NightLayers.Layers) -> SoundResponse {
        var pulse: [Int: Int] = [:]
        for r in series.records where r.pulse > 0 { pulse[r.time] = r.pulse }
        let bursts: [Int] = SoundClock.burstStarts(series)
        let tolerance: Int = clock.toleranceSeconds
        let yours: [ClosedRange<Int>] = blocks.filter { (b: SnoreOwnership.Block) -> Bool in b.verdict == .yours }
            .map { (b: SnoreOwnership.Block) -> ClosedRange<Int> in b.start...b.end }

        func asleep(at t: Int) -> Bool {
            let x: Double = Double(t)
            return layers.asleep.contains { (r: ClosedRange<TimeInterval>) -> Bool in
                r.lowerBound + Double(minSleepBeforeSeconds) <= x && x <= r.upperBound
            }
        }

        func rise(at t: Int) -> Double? {
            var before: [Double] = []
            for s in (t - pulseBeforeSeconds)..<t { if let p = pulse[s] { before.append(Double(p)) } }
            var after: [Double] = []
            for s in (t + 1)...(t + pulseAfterSeconds) { if let p = pulse[s] { after.append(Double(p)) } }
            guard before.count >= minPulseBefore, after.count >= minPulseAfter, let top = after.max() else {
                return nil
            }
            return top - before.reduce(0, +) / Double(before.count)
        }

        func awakens(at t: Int) -> Bool {
            layers.awake.contains { (r: ClosedRange<TimeInterval>) -> Bool in
                r.lowerBound >= Double(t) && r.lowerBound <= Double(t + awakeWithinSeconds)
            }
        }

        var items: [Item] = []
        for e in events {
            if e.soundClass == .snoring, yours.contains(where: { (r: ClosedRange<Int>) -> Bool in
                e.start <= r.upperBound && e.end >= r.lowerBound
            }) { continue }
            let t: Int = soundStart + e.start + clock.offset
            guard asleep(at: t) else { continue }
            let moved: Bool = bursts.contains { (b: Int) -> Bool in b >= t - tolerance && b <= t + 1 }
            let rs: Double? = rise(at: t)
            items.append(Item(event: e, bandTime: t, movementSound: moved, pulseRise: rs,
                              pulseReaction: (rs ?? 0) >= pulseRiseBpm, awakening: awakens(at: t),
                              levelStep: step(of: e.aboveFloor)))
        }

        var overall = Rate()
        var perClass = [Rate](repeating: Rate(), count: SoundClasses.count)
        var perStep = [Rate](repeating: Rate(), count: levelSteps.count)
        for it in items where it.counted {
            overall.events += 1
            if it.awakening { overall.awakenings += 1 }
            if it.pulseReaction { overall.pulseReactions += 1 }
            let c: Int = it.event.soundClass.rawValue
            perClass[c].events += 1
            if it.awakening { perClass[c].awakenings += 1 }
            if it.pulseReaction { perClass[c].pulseReactions += 1 }
            if let s = it.levelStep {
                perStep[s].events += 1
                if it.awakening { perStep[s].awakenings += 1 }
                if it.pulseReaction { perStep[s].pulseReactions += 1 }
            }
        }

        // Kontrollerna: sömnsekunder med bandets puls och ingen händelse inom ±120 s.
        let exclusion: [ClosedRange<Int>] = events.map { (e: SoundEvent) -> ClosedRange<Int> in
            let a: Int = soundStart + e.start + clock.offset - controlExclusionSeconds
            let b: Int = soundStart + e.end + clock.offset + controlExclusionSeconds
            return a...b
        }
        var candidates: [Int] = []
        for r in layers.asleep {
            let from: Int = Int(r.lowerBound.rounded(.up)) + minSleepBeforeSeconds
            let to: Int = Int(r.upperBound.rounded(.down))
            if to < from { continue }
            for t in from...to where pulse[t] != nil {
                if !exclusion.contains(where: { (x: ClosedRange<Int>) -> Bool in x.contains(t) }) { candidates.append(t) }
            }
        }
        var random = SoundRandom(seed: UInt64(truncatingIfNeeded: soundStart))
        if !candidates.isEmpty {
            for it in items where it.counted {
                let c: Int = it.event.soundClass.rawValue
                for _ in 0..<controlsPerEvent {
                    let t: Int = candidates[random.below(candidates.count)]
                    let reaction: Bool = (rise(at: t) ?? 0) >= pulseRiseBpm
                    let wakes: Bool = awakens(at: t)
                    overall.controls += 1
                    perClass[c].controls += 1
                    if wakes { overall.controlAwakenings += 1; perClass[c].controlAwakenings += 1 }
                    if reaction { overall.controlPulseReactions += 1; perClass[c].controlPulseReactions += 1 }
                    if let s = it.levelStep {
                        perStep[s].controls += 1
                        if wakes { perStep[s].controlAwakenings += 1 }
                        if reaction { perStep[s].controlPulseReactions += 1 }
                    }
                }
            }
        }
        return SoundResponse(items: items, overall: overall, perClass: perClass, perStep: perStep)
    }

    /// Nivåsteget för en händelse: 0 för golv +10–20 dB, 1 för +20–30, 2 över +30.
    static func step(of above: Double?) -> Int? {
        guard let a = above, a >= levelSteps[0] else { return nil }
        if a >= levelSteps[2] { return 2 }
        return a >= levelSteps[1] ? 1 : 0
    }
}
