import Foundation

/// METOD M38 · BESLUT B47
/// Vilka klipp som sparas. Lyssnaren ger policyn nattens händelser en i taget,
/// i ordning (när de är avslutade), och får veta om klippet ska sparas, ersätta
/// ett tidigare eller utebli:
///
/// - **Snarkning** ger högst ett klipp per 10 minuter i en episod (sekunder med
///   snarkning och högst 30 sekunders mellanrum), det högsta: ett högre klipp i
///   samma 10-minutersblock ersätter det förra.
/// - **Allt annat**, tal också, får ett klipp.
/// - **Taket** är 150 klipp per natt. När det är nått ersätter ett klipp med
///   högre `peak` det lägsta; annars uteblir det nya.
///
/// Klippets innehåll: från 3 sekunder före händelsen till 2 sekunder efter,
/// högst 30 sekunder (`span`). Allt är **antagande** (METOD M38).
public struct ClipPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        /// Spara klippet för händelsen.
        case save
        /// Spara klippet och radera klippet för händelsen med det här id:t.
        case replace(Int)
        /// Spara inget.
        case skip
    }

    /// METOD M38. Tak per natt.
    public static let maxClips = 150
    /// METOD M38. Block för snarkning, sekunder.
    public static let snoreBlockSeconds = 600
    /// METOD M38. Högst så här många sekunder mellan snarkningar i en episod.
    public static let snoreEpisodeGapSeconds = 30
    /// METOD M38. Före och efter händelsen, och längsta klippet, sekunder.
    public static let beforeSeconds = 3
    public static let afterSeconds = 2
    public static let maxClipSeconds = 30

    private struct Kept: Equatable, Sendable {
        var id: Int
        var peak: Int16
    }

    private var kept: [Kept] = []
    private var blockStart: Int?
    private var blockClip: Kept?
    private var lastSnoreEnd: Int?

    public init() {}

    /// Antal klipp som policyn håller just nu.
    public var count: Int { kept.count }

    /// Sekunderna ett klipp för händelsen ska innehålla: första sekunden och
    /// sekunden efter den sista (halvöppet), högst 30 sekunder. Kan börja före 0;
    /// lyssnaren klipper mot det den har i ringbufferten.
    public static func span(of e: SoundEvent) -> Range<Int> {
        let from: Int = e.start - beforeSeconds
        let to: Int = min(e.end + afterSeconds + 1, from + maxClipSeconds)
        return from..<max(to, from + 1)
    }

    public mutating func decide(_ e: SoundEvent) -> Decision {
        if e.soundClass == .snoring { return decideSnoring(e) }
        return admit(e)
    }

    private mutating func decideSnoring(_ e: SoundEvent) -> Decision {
        let newEpisode: Bool = lastSnoreEnd.map { (end: Int) -> Bool in
            e.start - end > ClipPolicy.snoreEpisodeGapSeconds
        } ?? true
        lastSnoreEnd = max(lastSnoreEnd ?? e.end, e.end)
        let newBlock: Bool = newEpisode || blockStart.map { (b: Int) -> Bool in
            e.start - b >= ClipPolicy.snoreBlockSeconds
        } ?? true
        if newBlock {
            let d: Decision = admit(e)
            if d != .skip {
                blockStart = e.start
                blockClip = Kept(id: e.id, peak: e.peak)
            } else {
                // Taket hindrade klippet: blocket räknas ändå, så att nästa
                // snarkning i det inte öppnar ett nytt.
                blockStart = e.start
                blockClip = nil
            }
            return d
        }
        guard let current = blockClip else { return .skip }
        guard e.peak > current.peak else { return .skip }
        // Ersätt blockets klipp: räknaren i `kept` byter id.
        if let i = kept.firstIndex(where: { (k: Kept) -> Bool in k.id == current.id }) {
            kept[i] = Kept(id: e.id, peak: e.peak)
        }
        blockClip = Kept(id: e.id, peak: e.peak)
        return .replace(current.id)
    }

    /// Tar in ett klipp under taket, eller låter det ersätta det lägsta.
    private mutating func admit(_ e: SoundEvent) -> Decision {
        if kept.count < ClipPolicy.maxClips {
            kept.append(Kept(id: e.id, peak: e.peak))
            return .save
        }
        guard let lowest = kept.indices.min(by: { (a: Int, b: Int) -> Bool in kept[a].peak < kept[b].peak }) else {
            return .skip
        }
        guard e.peak > kept[lowest].peak else { return .skip }
        let gone: Int = kept[lowest].id
        kept[lowest] = Kept(id: e.id, peak: e.peak)
        if blockClip?.id == gone { blockClip = nil }
        return .replace(gone)
    }
}
