import Foundation
import HeartRate
import WhoopFrames

/// METOD M28 · METOD M27 · METOD M26
/// Telefonens zon vid ett ögonblick, ur dygnsfilernas sidofiler
/// (`dygn-<datum>.jsonl`): natten kl 12–12 (M26) räknas på väggklockan i
/// zonen vid fönstrets början och i zonen vid dess slut, och de kan skilja
/// (sommartid, en resa). Sidofilerna bär zonen på två sätt (M27): ett huvud
/// utan tid när filen skapas, och en rad med tid när zonen ändras inom ett
/// dygn eller filen öppnas igen.
///
/// **Huvudets zon** gäller från filens första ögonblick, alltså midnatt på
/// filens datum i just den zonen. Det är en tolkning (huvudet har ingen tid),
/// men en ny fil skapas vid första notisen på datumet, så den ligger inom
/// några timmar från midnatt; avvikelsen kan bara flytta zonens gräns, inte
/// byta zon.
public struct DayZones: Sendable, Equatable {

    /// En zon som gäller från och med `time`.
    public struct Entry: Equatable, Sendable {
        public var time: Date
        public var utcOffsetSeconds: Int
    }

    public private(set) var entries: [Entry]

    /// Sidofilerna för några dygn: stam (`dygn-yyyy-MM-dd`) och innehåll.
    public init(days: [(stem: String, contents: RecordingLog.Contents)]) {
        var all: [Entry] = []
        for d in days {
            if let zon = d.contents.utcOffsetSeconds, let dag = DayLog.day(ofStem: d.stem) {
                all.append(Entry(time: DayLog.date(of: dag, utcOffsetSeconds: zon), utcOffsetSeconds: zon))
            }
            for c in d.contents.zoneChanges {
                all.append(Entry(time: c.time, utcOffsetSeconds: c.utcOffsetSeconds))
            }
        }
        // Stabil sortering: samma tid behåller skrivordningen.
        entries = all.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Zonen vid `date`: den senaste ändringen vid eller före, annars den
    /// första kända. `nil` utan någon zonrad.
    public func offset(at date: Date) -> Int? {
        guard let first = entries.first else { return nil }
        var zon: Int = first.utcOffsetSeconds
        for e in entries {
            if e.time > date { break }
            zon = e.utcOffsetSeconds
        }
        return zon
    }

    /// Zonerna vid dygnsfönstret kl 12–12 som slutar uppvakningsdagen: vid
    /// början (kl 12 dagen före) och vid slutet (kl 12 den dagen). Fönstrets
    /// gränser beror på zonen, så den prövas två gånger från `fallback`
    /// (telefonens zon nu, när sidofilerna saknar en rad).
    public func windowOffsets(wakeDay: WakeDay, fallback: Int) -> (start: Int, end: Int) {
        func zon(atNoon dagar: Int, guess: Int) -> Int {
            var z: Int = guess
            for _ in 0..<2 {
                let ögonblick = Date(timeIntervalSince1970: Double(dagar * 86_400 + 43_200 - z))
                z = offset(at: ögonblick) ?? fallback
            }
            return z
        }
        let start: Int = zon(atNoon: wakeDay.daysSince1970 - 1, guess: fallback)
        let end: Int = zon(atNoon: wakeDay.daysSince1970, guess: start)
        return (start, end)
    }
}
