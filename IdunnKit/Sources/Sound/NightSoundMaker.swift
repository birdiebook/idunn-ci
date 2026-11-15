import Foundation
import Night
import WhoopFrames

/// METOD M44 · BESLUT B54
/// Ljudet som nattens vyer ser det (`NightSound`, `Night`-målet): ur nattens
/// ljudfiler, K18-serien och lagren. Analysen är ljudets egen (`SoundNight`,
/// METOD M38–M40); det här lägger till det vyerna behöver och som analysen inte
/// ger i en form som går att rita:
///
/// - **En eller flera filer.** Lyssnaren kan startas om under natten (appen
///   avslutad, ett samtal): då finns flera filer. De läggs på en gemensam axel
///   (sekunderna räknas från den första filens start; en sekund som finns i två
///   filer räknas en gång, den senaste gäller) och analyseras som en natt.
///   Varje händelse minns vilken fil och vilken sekund den har där, eftersom
///   klippet ligger efter det (`ljudklipp/<stam>/<sekund>.m4a`).
/// - **Bandets klocka.** Händelsernas tider flyttas med klockskillnaden (M40) så att
///   de ligger på kurvans tidsaxel.
/// - **Nivån** är högsta sekunden i varje klockminut över golvet (aldrig under noll).
///   Högsta, inte medel: en trafikhändelse på sex sekunder försvinner i ett minutmedel.
/// - **Ägaren** till en snarkningshändelse är utlåtandet (M39) för blocket den
///   överlappar mest; utanför alla block (episoder under 60 s) är den okänd.
/// - **Händelserna** är de som börjar inom sömnperioden. Före insomningen och efter
///   uppvaknandet är ljudet inget som påverkar sömnen.
/// - **Snarkminuter per timme sömn.** Dina snarksekunder (blocken som är dina, M39)
///   inom den sovna tiden (`Layers.asleep`), per timme av den sovna tid som ljudet
///   täckte. Täckte ljudet mindre än `minCoverage` av den sovna tiden finns inget
///   tal: en lyssnare som startade vid tre på natten säger inget om natten. Inte heller när mer än
///   `maxUnknownShare` av snarkningen har okänd ägare.
public enum NightSoundMaker {

    /// METOD M44. Minst så här stor andel av den sovna tiden ska ljudet ha täckt för att
    /// snarkminuterna per timme ska räknas. Samma gräns som hudtemperaturens och
    /// rörelsens täckning (M25, M42). **Antagande.**
    public static let minCoverage: Double = 0.5

    /// METOD M44. Är mer än så här stor andel av snarkminuterna av okänd ägare (M39: utan tydlig andning går det
    /// inte att säga vems) finns inget tal: en nolla vore en gissning, och Morgon skulle säga att du snarkade
    /// under normalt när det bara inte gick att avgöra. **Antagande.**
    public static let maxUnknownShare: Double = 0.2

    /// En ljudfil som lästs in.
    public struct Source: Equatable, Sendable {
        /// Filstammen, `ljud-2026-10-14T21-03-00Z` (`SoundFile.stem(start:)`).
        public var stem: String
        /// Filens start, Unix-sekunder, telefonens klocka.
        public var start: Int
        public var seconds: [SoundSecond]
        public var marks: [SoundMark]

        public init(stem: String, start: Int, seconds: [SoundSecond], marks: [SoundMark] = []) {
            self.stem = stem
            self.start = start
            self.seconds = seconds
            self.marks = marks
        }
    }

    /// Var en fil ligger på den gemensamma axeln: sekunderna från första filens start och filens sista sekund.
    private struct Span {
        var offset: Int
        var last: Int
        var stem: String
    }

    /// Nattens ljud ur filerna. `nil` när inga sekunder finns.
    public static func make(sources: [Source], series: K18Series, layers: NightLayers.Layers) -> NightSound? {
        makeWithAnalysis(sources: sources, series: series, layers: layers)?.sound
    }

    /// Samma natt, och analysen den bygger på (`SoundNight`): ur den skrivs också `SoundSummary` (METOD M45), så att
    /// vyerna och exporten räknas från samma `SoundNight` och inte kan skilja sig.
    public static func makeWithAnalysis(sources: [Source], series: K18Series,
                                        layers: NightLayers.Layers) -> (sound: NightSound, analysis: SoundNight)? {
        let ordered: [Source] = sources.filter { (s: Source) -> Bool in !s.seconds.isEmpty }
            .sorted { (a: Source, b: Source) -> Bool in a.start < b.start }
        guard let first = ordered.first else { return nil }
        let base: Int = first.start

        // Filerna på en axel: sekunder från den första filens start. Den senaste filen gäller där de överlappar.
        var byIndex: [Int: SoundSecond] = [:]
        var spans: [Span] = []
        for src in ordered {
            let offset: Int = src.start - base
            var last: Int = 0
            for var s in src.seconds {
                s.second += offset
                byIndex[s.second] = s
                last = max(last, s.second)
            }
            spans.append(Span(offset: offset, last: last, stem: src.stem))
        }
        let merged: [SoundSecond] = byIndex.values.sorted { (a: SoundSecond, b: SoundSecond) -> Bool in a.second < b.second }
        let marks: [SoundMark] = ordered.flatMap { (s: Source) -> [SoundMark] in s.marks }
            .sorted { (a: SoundMark, b: SoundMark) -> Bool in a.time < b.time }

        let analysis: SoundNight = SoundNight.analyze(merged, soundStart: base, series: series, layers: layers,
                                                      marks: marks)
        let offset: Int = analysis.clock.offset
        func bandTime(_ second: Int) -> TimeInterval { TimeInterval(base + second + offset) }

        // Händelserna under sömnperioden.
        var items: [Int: SoundResponse.Item] = [:]
        for it in analysis.response.items { items[it.event.start] = it }
        var events: [NightSound.Event] = []
        for e in analysis.events {
            let t: TimeInterval = bandTime(e.start)
            guard layers.period.contains(t) else { continue }
            let item: SoundResponse.Item? = items[e.start]
            let counted: Bool = item?.counted ?? false
            let span: Span = spans.last(where: { (s: Span) -> Bool in s.offset <= e.start && e.start <= s.last })
                ?? spans[0]
            events.append(NightSound.Event(
                time: t, seconds: e.length, soundClass: e.soundClass.rawValue,
                owner: e.soundClass == .snoring ? owner(of: e, blocks: analysis.blocks) : nil,
                aboveFloor: e.aboveFloor, clip: NightSound.Clip(stem: span.stem, second: e.start - span.offset),
                woke: counted && (item?.awakening ?? false), pulse: counted && (item?.pulseReaction ?? false),
                movement: item?.movementSound ?? false))
        }

        // Nivån över golvet, högsta sekunden per klockminut inom sömnperioden.
        let floors: [Double?] = NoiseFloor.series(merged)
        var perMinute: [Int: Double] = [:]
        for (i, s) in merged.enumerated() {
            guard let f = floors[i] else { continue }
            let t: TimeInterval = bandTime(s.second)
            guard layers.period.contains(t) else { continue }
            let minute: Int = Int((t / 60).rounded(.down))
            perMinute[minute] = max(perMinute[minute] ?? 0, s.levelADB - f)
        }
        let levels: [NightSound.Level] = perMinute.keys.sorted().map { (m: Int) -> NightSound.Level in
            NightSound.Level(start: TimeInterval(m * 60), aboveFloor: max(0, perMinute[m] ?? 0))
        }

        // Täckningen av den sovna tiden och dina snarkminuter per timme sömn.
        let yoursBlocks: [ClosedRange<Int>] = analysis.blocks
            .filter { (b: SnoreOwnership.Block) -> Bool in b.verdict == .yours }
            .map { (b: SnoreOwnership.Block) -> ClosedRange<Int> in b.start...b.end }
        let asleepTotal: Double = layers.asleep.reduce(0.0) { (a: Double, r: ClosedRange<TimeInterval>) -> Double in
            a + (r.upperBound - r.lowerBound)
        }
        var covered = 0
        var own = 0
        for s in merged {
            let t: TimeInterval = bandTime(s.second)
            guard layers.asleep.contains(where: { (r: ClosedRange<TimeInterval>) -> Bool in r.contains(t) }) else { continue }
            covered += 1
            if s.value(of: .snoring) >= SnoreOwnership.snoreThreshold,
               yoursBlocks.contains(where: { (r: ClosedRange<Int>) -> Bool in r.contains(s.second) }) {
                own += 1
            }
        }
        let coverage: Double? = asleepTotal > 0 ? min(1, Double(covered) / asleepTotal) : nil
        var perHour: Double?
        let snarkMinuter: Double = analysis.snore.total
        let okänd: Bool = snarkMinuter > 0 && analysis.snore.unknown > maxUnknownShare * snarkMinuter
        if let c = coverage, c >= minCoverage, covered > 0, !okänd {
            perHour = (Double(own) / 60) / (Double(covered) / 3_600)
        }

        let sound = NightSound(
            start: bandTime(merged[0].second), end: bandTime(merged[merged.count - 1].second),
            levels: levels, events: events, yoursMinutes: analysis.snore.yours,
            someoneElseMinutes: analysis.snore.someoneElse, unknownMinutes: analysis.snore.unknown,
            asleepSeconds: Double(covered), coverage: coverage, snoringPerHour: perHour,
            clockReliable: analysis.clock.isReliable)
        return (sound: sound, analysis: analysis)
    }

    /// Ägaren till en snarkningshändelse: utlåtandet för blocket den överlappar mest, annars okänd.
    static func owner(of e: SoundEvent, blocks: [SnoreOwnership.Block]) -> NightSound.Owner {
        var best: SnoreOwnership.Block?
        var bestOverlap = 0
        for b in blocks {
            let overlap: Int = min(b.end, e.end) - max(b.start, e.start) + 1
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = b
            }
        }
        switch best?.verdict {
        case .some(.yours): return .yours
        case .some(.someoneElse): return .someoneElse
        default: return .unknown
        }
    }
}

/// METOD M44 · BESLUT B54
/// Vilka ljudfiler en natt läser, och analysen som natten kör med dem. Appen
/// läser filerna (`load`); allt som är ett beslut ligger här och går att prova på Linux.
public enum SoundNights {

    /// Det en ljudfil är innan den tolkas: måtten och, om de finns, märkena.
    public struct Raw: Sendable {
        public var measures: Data
        public var marks: Data?

        public init(measures: Data, marks: Data? = nil) {
            self.measures = measures
            self.marks = marks
        }
    }

    /// METOD M44. Filerna som hör till natten som slutar `wakeDay`: de vars start ligger i nattens fönster,
    /// kl 12 dagen före till kl 12 uppvakningsdagen på väggklockan i zonen `utcOffsetSeconds` (samma fönster
    /// som kurvans, METOD M26). Lyssnaren startar kl 20–04 och slutar senast kl 12, så en natts filer börjar
    /// alltid i sitt fönster. I ordningen de började.
    public static func stems(among all: [String], wakeDay: WakeDay, utcOffsetSeconds: Int) -> [String] {
        let from: Int = wakeDay.daysSince1970 * 86_400 - 43_200 - utcOffsetSeconds
        let to: Int = from + 86_400
        var med: [(stem: String, start: Int)] = []
        for stem in all {
            guard let start = SoundFile.start(ofStem: stem), start >= from, start < to else { continue }
            med.append((stem: stem, start: start))
        }
        return med.sorted { (a: (stem: String, start: Int), b: (stem: String, start: Int)) -> Bool in
            (a.start, a.stem) < (b.start, b.stem)
        }.map { (m: (stem: String, start: Int)) -> String in m.stem }
    }

    /// METOD M44 · METOD M45. Analysen som `K18Days` och `NightLedger` kör för varje natt. Läser nattens filer med
    /// `load` (`nil` = filen finns inte eller går inte att läsa), och ger `nil` för en natt utan lager (en gammal
    /// inspelning) och för en natt utan ljud. Med `saveSummary` lämnas nattens tal för datorn (`SoundSummary`,
    /// `ljud-<start>.sammanfattning.json`, BESLUT B55) till appen, som skriver den bredvid `.ljud`-filen: stammen
    /// är nattens första fil. Består natten av flera filer (lyssnaren startad om) gäller sammanfattningen hela
    /// natten och ligger bredvid den första; `tools/ljud_analys.py` skriver en rad om antalen då inte stämmer med
    /// filens egna.
    public static func analyzer(stems all: [String], load: @escaping (String) -> Raw?,
                                saveSummary: ((String, Data) -> Void)? = nil) -> NightSound.Analyzer {
        return { (wakeDay: WakeDay, series: K18Series, result: NightResult) -> NightSound? in
            guard let layers = result.layers else { return nil }
            var sources: [NightSoundMaker.Source] = []
            for stem in SoundNights.stems(among: all, wakeDay: wakeDay, utcOffsetSeconds: result.utcOffsetSeconds) {
                guard let raw = load(stem), let contents = try? SoundFile.decode(raw.measures),
                      !contents.seconds.isEmpty else { continue }
                sources.append(NightSoundMaker.Source(
                    stem: stem, start: contents.start, seconds: contents.seconds,
                    marks: raw.marks.map { (d: Data) -> [SoundMark] in SoundMark.decode(d) } ?? []))
            }
            guard let made = NightSoundMaker.makeWithAnalysis(sources: sources, series: series, layers: layers) else {
                return nil
            }
            if let save = saveSummary, let first = sources.first {
                save(first.stem, SoundSummary(made.analysis).encoded())
            }
            return made.sound
        }
    }
}
