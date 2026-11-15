import Foundation

/// METOD M45 · BESLUT B55
/// Nattens ljud i tal, som en liten JSON-fil bredvid `.ljud`-filen:
/// `ljud-<start>.sammanfattning.json`. Den följer med Exportera, och
/// `tools/ljud_analys.py` läser den för det som kräver K18-natten och
/// sömnperioden och därför inte går att räkna ur `.ljud`-filen ensam: vems
/// snarkningen är, klockskillnaden och uppvaknandena mot kontrollerna.
///
/// **Bara tal och andelar.** Inga nivåer per sekund och ingen klocktid för en
/// enskild händelse, så att filen går att klistra in (dataregeln). Ett glapp
/// bär sin längd och orsak men inte när det var. Nycklarna är Swifts egna
/// (`JSONEncoder`, sorterade); provet `testNycklarnaÄrDeSammaSomIPython`
/// låser dem mot `tools/tests/test_ljud_analys.py`.
public struct SoundSummary: Codable, Equatable, Sendable {
    /// Stiger om en nyckel byts ut eller byter betydelse.
    public static let version = 1

    /// En räkning efter händelser och vid kontrollerna (`SoundResponse.Rate`).
    public struct Rate: Codable, Equatable, Sendable {
        public var events: Int
        public var awakenings: Int
        public var pulseReactions: Int
        public var controls: Int
        public var controlAwakenings: Int
        public var controlPulseReactions: Int

        public init(events: Int = 0, awakenings: Int = 0, pulseReactions: Int = 0, controls: Int = 0,
                    controlAwakenings: Int = 0, controlPulseReactions: Int = 0) {
            self.events = events
            self.awakenings = awakenings
            self.pulseReactions = pulseReactions
            self.controls = controls
            self.controlAwakenings = controlAwakenings
            self.controlPulseReactions = controlPulseReactions
        }

        init(_ r: SoundResponse.Rate) {
            self.init(events: r.events, awakenings: r.awakenings, pulseReactions: r.pulseReactions,
                      controls: r.controls, controlAwakenings: r.controlAwakenings,
                      controlPulseReactions: r.controlPulseReactions)
        }
    }

    /// Ett glapp i måtten: längden och orsaken (`SoundMark.Kind.rawValue`), inte tiden.
    public struct Gap: Codable, Equatable, Sendable {
        public var seconds: Int
        public var cause: String?

        public init(seconds: Int, cause: String?) {
            self.seconds = seconds
            self.cause = cause
        }
    }

    public var version: Int
    /// Sekunder med mått i natten.
    public var secondsMeasured: Int
    /// Snarkningens minuter, uppdelade efter vems den är (METOD M39).
    public var snoreYoursMinutes: Double
    public var snoreSomeoneElseMinutes: Double
    public var snoreUnknownMinutes: Double
    /// Andelen block med okänd ägare, eller `nil` utan block.
    public var unknownShare: Double?
    /// Dina snarkminuter per timme sömn, eller `nil` utan sömn.
    public var snoringPerHourAsleep: Double?
    /// Antal talade avsnitt (vems går inte att säga).
    public var speechEpisodes: Int
    /// Händelser per klass, i `SoundClass`-ordning.
    public var eventsPerClass: [Int]
    /// Klockskillnaden (bandet minus telefonen) i sekunder, och om den är säker.
    public var clockOffsetSeconds: Int
    public var clockReliable: Bool
    /// Räkningen över alla händelser som kom ifråga, per klass och per nivåsteg.
    public var overall: Rate
    public var perClass: [Rate]
    public var perStep: [Rate]
    public var gaps: [Gap]

    public init(_ n: SoundNight) {
        version = SoundSummary.version
        secondsMeasured = n.secondsMeasured
        snoreYoursMinutes = n.snore.yours
        snoreSomeoneElseMinutes = n.snore.someoneElse
        snoreUnknownMinutes = n.snore.unknown
        unknownShare = n.unknownShare
        snoringPerHourAsleep = n.snoring.perHourAsleep
        speechEpisodes = n.speechEpisodes
        eventsPerClass = n.eventsPerClass
        clockOffsetSeconds = n.clock.offset
        clockReliable = n.clock.isReliable
        overall = Rate(n.response.overall)
        perClass = n.response.perClass.map { (r: SoundResponse.Rate) -> Rate in Rate(r) }
        perStep = n.response.perStep.map { (r: SoundResponse.Rate) -> Rate in Rate(r) }
        gaps = n.gaps.map { (g: SoundGap) -> Gap in Gap(seconds: g.seconds, cause: g.cause?.rawValue) }
    }

    /// Filens namn bredvid `ljud-<start>.ljud`.
    public static func fileName(stem: String) -> String { stem + ".sammanfattning.json" }

    /// Sammanfattningen som filens innehåll.
    public func encoded() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(self)) ?? Data()
    }

    /// Sammanfattningen ur en fil; `nil` om den inte går att läsa eller har en annan version.
    public static func decode(_ data: Data) -> SoundSummary? {
        guard let s = try? JSONDecoder().decode(SoundSummary.self, from: data), s.version == version else {
            return nil
        }
        return s
    }
}
