import Foundation
import Night
import WhoopFrames

/// Ett glapp i ljudets sekunder, med orsaken ur ljudsessionens märke om det finns ett.
public struct SoundGap: Equatable, Sendable {
    /// Första och sista sekunden som saknas (index i filen).
    public var start: Int
    public var end: Int
    /// Märket närmast före glappet (± 5 s), eller `nil` när inget märke förklarar det.
    public var cause: SoundMark.Kind?

    public init(start: Int, end: Int, cause: SoundMark.Kind?) {
        self.start = start
        self.end = end
        self.cause = cause
    }

    public var seconds: Int { end - start + 1 }
}

/// METOD M40 · BESLUT B47
/// Nattens ljud i siffror: snarkningen (vems och hur länge), talet, händelserna
/// per klass och vad som följde dem, klockskillnaden och glappen. Räknas ur
/// nattens sekunder, K18-serien och lagren (`NightLayers.Layers`, METOD M32);
/// saknas lagren (en natt utan K18-period) räknas ingenting som kräver sömnen.
/// Värdetyp, så att appen kan spara sammanfattningen och vyerna kan rita den.
public struct SoundNight: Equatable, Sendable {

    /// METOD M40. Ett talat avsnitt: sekunder med tal ≥ 50 och högst 30 sekunders
    /// mellanrum, minst 3 sekunder. **Antagande.**
    public static let speechGapSeconds = 30
    public static let minSpeechSeconds = 3

    /// Snarkningens minuter, uppdelade efter vems den är. Snarkning utanför
    /// episoderna (kortare än 60 s) räknas som okänd.
    public struct SnoreMinutes: Equatable, Sendable {
        public var yours: Double
        public var someoneElse: Double
        public var unknown: Double

        public init(yours: Double = 0, someoneElse: Double = 0, unknown: Double = 0) {
            self.yours = yours
            self.someoneElse = someoneElse
            self.unknown = unknown
        }

        public var total: Double { yours + someoneElse + unknown }
    }

    /// Din snarkning genom natten (METOD M40): minuter per timme sömn, per
    /// stadium, per tredjedel av sömnperioden, och styrkan.
    public struct SnoringProfile: Equatable, Sendable {
        /// Dina snarkminuter.
        public var minutes: Double
        /// Per timme sömn (`Layers.asleep`); `nil` utan sömn.
        public var perHourAsleep: Double?
        /// Dina snarkminuter per stadium (index = `SleepStage.rawValue`); tom utan stadier.
        public var perStage: [Double]
        /// Dina snarkminuter per tredjedel av sömnperioden.
        public var perThird: [Double]
        /// Median av `levelA` − golv i dina snarksekunder, dB.
        public var strengthDB: Double?

        public init(minutes: Double = 0, perHourAsleep: Double? = nil, perStage: [Double] = [],
                    perThird: [Double] = [], strengthDB: Double? = nil) {
            self.minutes = minutes
            self.perHourAsleep = perHourAsleep
            self.perStage = perStage
            self.perThird = perThird
            self.strengthDB = strengthDB
        }
    }

    /// Filens start (Unix, telefonens klocka) och antal sekunder med mått.
    public var start: Int
    public var secondsMeasured: Int
    public var snore: SnoreMinutes
    public var blocks: [SnoreOwnership.Block]
    public var snoring: SnoringProfile
    /// Antal talade avsnitt (vems går inte att säga).
    public var speechEpisodes: Int
    /// Alla händelser, i ordning, och antal per klass (index = `SoundClass.rawValue`).
    public var events: [SoundEvent]
    public var eventsPerClass: [Int]
    /// Händelser som följdes av uppvaknande respektive pulsreaktion (utan rörelseljud).
    public var followedByAwakening: Int
    public var followedByPulse: Int
    public var response: SoundResponse
    public var clock: SoundClock.Estimate
    /// Ljudets glapp, i ordning.
    public var gaps: [SoundGap]

    public init(start: Int, secondsMeasured: Int, snore: SnoreMinutes, blocks: [SnoreOwnership.Block],
                snoring: SnoringProfile, speechEpisodes: Int, events: [SoundEvent], eventsPerClass: [Int],
                followedByAwakening: Int, followedByPulse: Int, response: SoundResponse,
                clock: SoundClock.Estimate, gaps: [SoundGap]) {
        self.start = start
        self.secondsMeasured = secondsMeasured
        self.snore = snore
        self.blocks = blocks
        self.snoring = snoring
        self.speechEpisodes = speechEpisodes
        self.events = events
        self.eventsPerClass = eventsPerClass
        self.followedByAwakening = followedByAwakening
        self.followedByPulse = followedByPulse
        self.response = response
        self.clock = clock
        self.gaps = gaps
    }

    /// Andelen block med okänd ägare (visas på Data, METOD M39).
    public var unknownShare: Double? {
        guard !blocks.isEmpty else { return nil }
        var unknown = 0
        for b in blocks where b.verdict == .unknown { unknown += 1 }
        return Double(unknown) / Double(blocks.count)
    }

    // MARK: Räkningen

    /// Analyserar en natt. `soundStart`: filens start; `marks`: märkena ur
    /// märkesfilen (förklarar glappen). Utan `layers` (en natt utan sömnperiod)
    /// räknas varken klockan mot sömnen eller vad som följde händelserna.
    public static func analyze(_ seconds: [SoundSecond], soundStart: Int, series: K18Series,
                               layers: NightLayers.Layers?, marks: [SoundMark] = []) -> SoundNight {
        let sorted: [SoundSecond] = seconds.sorted { (a: SoundSecond, b: SoundSecond) -> Bool in a.second < b.second }
        let events: [SoundEvent] = SoundEvents.detect(sorted)
        let clock: SoundClock.Estimate = SoundClock.estimate(sorted, soundStart: soundStart, series: series)
        let blocks: [SnoreOwnership.Block] = SnoreOwnership.classify(sorted, soundStart: soundStart,
                                                                     clockOffset: clock.offset, series: series)

        var perClass = [Int](repeating: 0, count: SoundClasses.count)
        for e in events { perClass[e.soundClass.rawValue] += 1 }

        var response = SoundResponse()
        if let l = layers {
            response = SoundResponse.compute(events: events, blocks: blocks, soundStart: soundStart,
                                             clock: clock, series: series, layers: l)
        }
        return SoundNight(start: soundStart, secondsMeasured: sorted.count,
                          snore: snoreMinutes(sorted, blocks: blocks),
                          blocks: blocks,
                          snoring: snoringProfile(sorted, blocks: blocks, soundStart: soundStart,
                                                  clock: clock, layers: layers),
                          speechEpisodes: speechEpisodes(sorted, layers: layers, soundStart: soundStart,
                                                         offset: clock.offset),
                          events: events, eventsPerClass: perClass,
                          followedByAwakening: response.awakenings, followedByPulse: response.pulseReactions,
                          response: response, clock: clock, gaps: gaps(sorted, marks: marks, soundStart: soundStart))
    }

    /// Sekunder med snarkning ≥ 50 per utlåtande; sekunder utanför blocken är okända.
    static func snoreMinutes(_ seconds: [SoundSecond], blocks: [SnoreOwnership.Block]) -> SnoreMinutes {
        var yours = 0
        var other = 0
        var unknown = 0
        for s in seconds where s.value(of: .snoring) >= SnoreOwnership.snoreThreshold {
            let owner: SnoreOwnership.Verdict? = blocks.first(where: { (b: SnoreOwnership.Block) -> Bool in
                s.second >= b.start && s.second <= b.end
            })?.verdict
            switch owner {
            case .some(.yours): yours += 1
            case .some(.someoneElse): other += 1
            default: unknown += 1
            }
        }
        return SnoreMinutes(yours: Double(yours) / 60, someoneElse: Double(other) / 60, unknown: Double(unknown) / 60)
    }

    /// METOD M40. Dina snarksekunder: per timme sömn, per stadium, per tredjedel
    /// av sömnperioden, och styrkan som median `levelA` − golv.
    static func snoringProfile(_ seconds: [SoundSecond], blocks: [SnoreOwnership.Block], soundStart: Int,
                               clock: SoundClock.Estimate, layers: NightLayers.Layers?) -> SnoringProfile {
        let own: [ClosedRange<Int>] = blocks.filter { (b: SnoreOwnership.Block) -> Bool in b.verdict == .yours }
            .map { (b: SnoreOwnership.Block) -> ClosedRange<Int> in b.start...b.end }
        var mine: [SoundSecond] = []
        for s in seconds where s.value(of: .snoring) >= SnoreOwnership.snoreThreshold {
            if own.contains(where: { (r: ClosedRange<Int>) -> Bool in r.contains(s.second) }) { mine.append(s) }
        }
        guard !mine.isEmpty else { return SnoringProfile() }

        let floors: [Double?] = NoiseFloor.series(seconds)
        var strengths: [Double] = []
        let wanted: Set<Int> = Set(mine.map { (s: SoundSecond) -> Int in s.second })
        for (i, s) in seconds.enumerated() where wanted.contains(s.second) {
            if let f = floors[i] { strengths.append(s.levelADB - f) }
        }
        strengths.sort()
        let strength: Double? = strengths.isEmpty ? nil : strengths[strengths.count / 2]

        var profile = SnoringProfile(minutes: Double(mine.count) / 60, perHourAsleep: nil, perStage: [],
                                     perThird: [], strengthDB: strength)
        guard let l = layers else { return profile }
        let asleepSeconds: Double = l.asleep.reduce(0.0) { (a: Double, r: ClosedRange<TimeInterval>) -> Double in
            a + (r.upperBound - r.lowerBound)
        }
        if asleepSeconds > 0 { profile.perHourAsleep = profile.minutes / (asleepSeconds / 3_600) }

        var perThird = [Double](repeating: 0, count: 3)
        var perStage = [Double](repeating: 0, count: SleepStage.allCases.count)
        let length: Double = l.period.upperBound - l.period.lowerBound
        for s in mine {
            let t: Double = Double(soundStart + s.second + clock.offset)
            if length > 0 {
                let third: Int = Int(((t - l.period.lowerBound) / length * 3).rounded(.down))
                if third >= 0 && third < 3 { perThird[third] += 1.0 / 60 }
            }
            if let span = l.stage(at: t) { perStage[span.stage.rawValue] += 1.0 / 60 }
        }
        profile.perThird = perThird
        profile.perStage = l.stages.isEmpty ? [] : perStage
        return profile
    }

    /// Talade avsnitt: sekunder med tal ≥ 50, högst 30 sekunders mellanrum, minst
    /// 3 sekunder. Med lager räknas bara de som börjar inom sömnperioden.
    static func speechEpisodes(_ seconds: [SoundSecond], layers: NightLayers.Layers?, soundStart: Int,
                               offset: Int) -> Int {
        let speaking: [Int] = seconds.filter { (s: SoundSecond) -> Bool in
            s.value(of: .speech) >= SnoreOwnership.snoreThreshold
        }.map { (s: SoundSecond) -> Int in s.second }
        var count = 0
        var i = 0
        while i < speaking.count {
            var j = i
            while j + 1 < speaking.count, speaking[j + 1] - speaking[j] - 1 <= speechGapSeconds { j += 1 }
            if speaking[j] - speaking[i] + 1 >= minSpeechSeconds {
                if let l = layers {
                    let t: Double = Double(soundStart + speaking[i] + offset)
                    if l.period.contains(t) { count += 1 }
                } else {
                    count += 1
                }
            }
            i = j + 1
        }
        return count
    }

    /// Saknade sekunder mellan två mätta, med märket närmast före glappet som orsak.
    static func gaps(_ seconds: [SoundSecond], marks: [SoundMark], soundStart: Int) -> [SoundGap] {
        var out: [SoundGap] = []
        for (a, b) in zip(seconds, seconds.dropFirst()) where b.second - a.second > 1 {
            let from: Int = soundStart + a.second
            let to: Int = soundStart + b.second
            var cause: SoundMark.Kind?
            for m in marks where m.time >= from - 5 && m.time <= to + 5 {
                switch m.kind {
                case .interruptedCall, .interruptedAlarm, .interruptedOther, .routeLost, .failed, .stopped:
                    cause = m.kind
                default:
                    break
                }
            }
            out.append(SoundGap(start: a.second + 1, end: b.second - 1, cause: cause))
        }
        return out
    }
}
