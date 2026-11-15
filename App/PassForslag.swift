import Foundation
import Pass
import WhoopFrames

/// BESLUT B121 · METOD M69
/// Underlaget till förslagen i passlistan: bandets sekunder för de två senaste dygnen, läst ur dygnens filer, och
/// filen med de borttagna förslagen. Bara läsning av nattens filer (samma väg som `PassHistorik`); körs på filkön,
/// aldrig på huvudkön: en dygnsfil kan vara tiotals MB.
enum PassForslag {
    /// Så långt bakåt läses historiken för förslagen.
    static let bakåtSekunder: TimeInterval = 2 * 86400

    /// Filen med de borttagna förslagen, bredvid passens mapp.
    static var fil: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(PassSuggestions.fileName)
    }

    /// En fil som saknas eller är trasig är ett tomt lager.
    static func läsLager() -> PassSuggestions.Store {
        guard let data = try? Data(contentsOf: fil),
              let lager = try? JSONDecoder().decode(PassSuggestions.Store.self, from: data) else {
            return PassSuggestions.Store()
        }
        return lager
    }

    /// Skriver lagret med appens skyddsklass.
    static func skriv(_ lager: PassSuggestions.Store) {
        let kodare = JSONEncoder()
        kodare.outputFormatting = [.sortedKeys]
        guard let data = try? kodare.encode(lager) else { return }
        try? FileManager.default.createDirectory(at: fil.deletingLastPathComponent(), withIntermediateDirectories: true)
        NightFiles.write(data, to: fil)
    }

    /// Bandets sekunder från `now - bakåtSekunder` till `now`, och samma poster som pulsprov för att fylla ett pass.
    static func sekunder(now: Date) -> (sekunder: [PassSuggestions.Second], poster: [PassHistory.Reading]) {
        let från: Date = now.addingTimeInterval(-bakåtSekunder)
        let zon: Int = TimeZone.current.secondsFromGMT(for: från)
        var samlare = K18Collector(from: från, to: now)
        for stam in DayLog.stems(touching: från, to: now.addingTimeInterval(1), utcOffsetSeconds: zon) {
            guard NightFiles.size(stam) > 0, let fil = K18Nights.load(stam) else { continue }
            if let ramar = fil.frames {
                samlare.read(log: ramar)
            } else if let data = fil.archive, let arkiv = try? DayArchive.decode(data) {
                samlare.read(archive: arkiv)
            }
        }
        let poster: [K18Record] = samlare.series().records
        let sek: [PassSuggestions.Second] = poster.map { (r: K18Record) -> PassSuggestions.Second in
            PassSuggestions.Second(time: r.time, pulse: r.pulse, x: r.gravity.x, y: r.gravity.y, z: r.gravity.z,
                                   skinTemperature: r.skinTemperature)
        }
        let prov: [PassHistory.Reading] = poster.map { (r: K18Record) -> PassHistory.Reading in
            PassHistory.Reading(time: r.time, bpm: r.pulse)
        }
        return (sek, prov)
    }
}
