import Foundation
import WhoopFrames

/// METOD M44 · BESLUT B54
/// Nattens ljud som vyerna ser det: nivån över golvet per minut, händelserna med
/// klass, ägare (för snarkning) och vad som följde dem, och några samlade tal.
/// Räknas av ljudets nattanalys (`Sound`-målet, METOD M40) och läggs på nattens
/// resultat (`NightResult.sound`) i samma uträkning som kurvans lager (METOD M32);
/// `Night` känner alltså bara värdetyperna, inte ljudets räkning. Tiderna är
/// BANDETS klocka (Unix-sekunder, efter klockskillnaden, METOD M40), så att de
/// ligger på kurvans tidsaxel utan omräkning.
///
/// Klasserna är index i `SoundClass` (`Sound`-målet, tolv stycken): en natt
/// utan ljud har ingen `NightSound` (`nil`), och ingen vy visar då något av det.
public struct NightSound: Equatable, Sendable {

    /// Index för klasserna som vyerna behandlar särskilt. Samma tal som
    /// `SoundClass.snoring`, `.breathing` och `.other` (provat i `NightSoundTests`).
    public static let snoringClass = 0
    public static let breathingClass = 1
    public static let otherClass = 11

    /// METOD M39. Vems en snarkning är.
    public enum Owner: String, Codable, Equatable, Sendable {
        case yours
        case someoneElse
        case unknown
    }

    /// Ett klipp: ljudfilens stam (`ljud-2026-10-14T21-03-00Z`) och händelsens första
    /// sekund i den filen. Klippet ligger i `ljudklipp/<stam>/<sekund, fem siffror>.m4a`
    /// i 14 dagar (METOD M38); finns det inte längre (eller sparades aldrig) är det
    /// bara en händelse utan ljud.
    public struct Clip: Codable, Equatable, Hashable, Sendable {
        public var stem: String
        public var second: Int

        public init(stem: String, second: Int) {
            self.stem = stem
            self.second = second
        }

        /// Filnamnet i klippmappen.
        public var fileName: String { String(format: "%05d.m4a", second) }
        /// Nyckeln för klippet, också i facit (BESLUT B56): den överlever klippet.
        public var key: String { stem + "/" + String(format: "%05d", second) }
    }

    /// En ljudhändelse (METOD M38) på kurvans tidsaxel.
    public struct Event: Equatable, Identifiable, Sendable {
        /// Första sekunden, bandets klocka.
        public var time: TimeInterval
        /// Sekunder från första till sista aktiva sekunden.
        public var seconds: Int
        /// Klassen (index i `SoundClass`).
        public var soundClass: Int
        /// Vems snarkningen är; `nil` för allt som inte är snarkning.
        public var owner: Owner?
        /// Högsta nivån över golvet i dB; `nil` före golvet fanns.
        public var aboveFloor: Double?
        public var clip: Clip
        /// METOD M40. Ett vaket pass började 0–60 s efter starten, och ljudet var inte följden av en rörelse.
        public var woke: Bool
        /// METOD M40. Pulsen steg minst 8 slag/min 1–30 s efter starten, och ljudet var inte följden av en rörelse.
        public var pulse: Bool
        /// METOD M40. Rörelseljud: armen rörde sig i samma stund, så ljudet är följden och räknas aldrig som orsak.
        public var movement: Bool

        public var id: String { clip.key }
        /// Följdes av ett uppvaknande eller en pulsreaktion.
        public var followed: Bool { woke || pulse }
        public var isSnoring: Bool { soundClass == NightSound.snoringClass }

        public init(time: TimeInterval, seconds: Int, soundClass: Int, owner: Owner?, aboveFloor: Double?,
                    clip: Clip, woke: Bool, pulse: Bool, movement: Bool) {
            self.time = time
            self.seconds = seconds
            self.soundClass = soundClass
            self.owner = owner
            self.aboveFloor = aboveFloor
            self.clip = clip
            self.woke = woke
            self.pulse = pulse
            self.movement = movement
        }
    }

    /// Nivån över golvet en klockminut (medel av sekundernas `levelA` − golv, aldrig under noll).
    public struct Level: Equatable, Sendable {
        /// Minutens början, bandets klocka.
        public var start: TimeInterval
        public var aboveFloor: Double

        public init(start: TimeInterval, aboveFloor: Double) {
            self.start = start
            self.aboveFloor = aboveFloor
        }
    }

    /// Hur natten läser sitt ljud: räknas när natten räknas (METOD M44).
    public typealias Analyzer = (_ wakeDay: WakeDay, _ series: K18Series, _ result: NightResult) -> NightSound?

    /// Första och sista mätta sekunden, bandets klocka.
    public var start: TimeInterval
    public var end: TimeInterval
    public var levels: [Level]
    /// Händelserna under sömnperioden, i tidsordning.
    public var events: [Event]
    /// Snarkningens minuter efter ägare, hela filen (METOD M40).
    public var yoursMinutes: Double
    public var someoneElseMinutes: Double
    public var unknownMinutes: Double
    /// Sekunder av den sovna tiden (`Layers.asleep`) som ljudet täckte.
    public var asleepSeconds: Double
    /// Andelen av den sovna tiden som ljudet täckte; `nil` utan sovna tid.
    public var coverage: Double?
    /// METOD M44. Dina snarkminuter per timme sömn; `nil` när ljudet täckte för lite av sömnen.
    public var snoringPerHour: Double?
    public var clockReliable: Bool

    public init(start: TimeInterval, end: TimeInterval, levels: [Level], events: [Event], yoursMinutes: Double,
                someoneElseMinutes: Double, unknownMinutes: Double, asleepSeconds: Double, coverage: Double?,
                snoringPerHour: Double?, clockReliable: Bool) {
        self.start = start
        self.end = end
        self.levels = levels
        self.events = events
        self.yoursMinutes = yoursMinutes
        self.someoneElseMinutes = someoneElseMinutes
        self.unknownMinutes = unknownMinutes
        self.asleepSeconds = asleepSeconds
        self.coverage = coverage
        self.snoringPerHour = snoringPerHour
        self.clockReliable = clockReliable
    }

    /// Det som sparas med nattens resultat (varma lagret, BESLUT B41): några tal och de händelser som väckte.
    public var digest: NightSoundDigest {
        NightSoundDigest(
            snoringPerHour: snoringPerHour, yoursMinutes: yoursMinutes, someoneElseMinutes: someoneElseMinutes,
            unknownMinutes: unknownMinutes, events: events.count,
            pulseReactions: events.filter { (e: Event) -> Bool in e.pulse }.count,
            wakers: events.filter { (e: Event) -> Bool in e.woke }.map { (e: Event) -> NightSoundDigest.Waker in
                NightSoundDigest.Waker(time: e.time, soundClass: e.soundClass, owner: e.owner)
            },
            coverage: coverage, clockReliable: clockReliable)
    }

    /// Händelserna som följdes av ett uppvaknande eller en pulsreaktion, i tidsordning.
    public var followed: [Event] { events.filter { (e: Event) -> Bool in e.followed } }
}

/// METOD M44 · BESLUT B54
/// Sammanfattningen av nattens ljud som sparas bredvid nattens resultat
/// (`NightDigest.sound`): bara tal och tider, aldrig ett klipp eller en nivå per
/// sekund. Äldre sparade nätter saknar fältet och avkodas ändå.
public struct NightSoundDigest: Codable, Equatable, Sendable {
    /// En händelse som väckte (METOD M40): när (bandets klocka, Unix-sekunder), vilken klass och vems.
    public struct Waker: Codable, Equatable, Sendable {
        public var time: Double
        public var soundClass: Int
        public var owner: NightSound.Owner?

        public init(time: Double, soundClass: Int, owner: NightSound.Owner?) {
            self.time = time
            self.soundClass = soundClass
            self.owner = owner
        }
    }

    /// Dina snarkminuter per timme sömn (METOD M44); `nil` när ljudet täckte för lite av sömnen.
    public var snoringPerHour: Double?
    public var yoursMinutes: Double
    public var someoneElseMinutes: Double
    public var unknownMinutes: Double
    /// Antal händelser under sömnperioden, och hur många som följdes av en pulsreaktion.
    public var events: Int
    public var pulseReactions: Int
    /// Händelserna som väckte, i tidsordning.
    public var wakers: [Waker]
    public var coverage: Double?
    public var clockReliable: Bool

    public init(snoringPerHour: Double?, yoursMinutes: Double, someoneElseMinutes: Double, unknownMinutes: Double,
                events: Int, pulseReactions: Int, wakers: [Waker], coverage: Double?, clockReliable: Bool) {
        self.snoringPerHour = snoringPerHour
        self.yoursMinutes = yoursMinutes
        self.someoneElseMinutes = someoneElseMinutes
        self.unknownMinutes = unknownMinutes
        self.events = events
        self.pulseReactions = pulseReactions
        self.wakers = wakers
        self.coverage = coverage
        self.clockReliable = clockReliable
    }
}

extension NightSound {
    /// BESLUT B54. Raden för varje symbol i ljuddiagrammet (0 eller 1), så att två händelser tätt intill
    /// varandra inte ritas på varandra (granskningen 2026-10-15: hostan 23:00 låg under bilen 23:10).
    /// `times` i tidsordning; `minGap` är den tid en symbol tar på tidsaxeln. En symbol går på första
    /// raden när den ryms där, annars på den andra, och på den rad som står friast när ingen ryms.
    public static func symbolRows(times: [TimeInterval], minGap: TimeInterval) -> [Int] {
        var senast: [TimeInterval] = [-.infinity, -.infinity]
        var rader: [Int] = []
        for t in times {
            let rad: Int
            if t - senast[0] >= minGap { rad = 0 }
            else if t - senast[1] >= minGap { rad = 1 }
            else { rad = senast[0] <= senast[1] ? 0 : 1 }
            senast[rad] = t
            rader.append(rad)
        }
        return rader
    }
}
