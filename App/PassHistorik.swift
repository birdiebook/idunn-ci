import Foundation
import Pass
import WhoopFrames

/// BESLUT B117 · METOD M68
/// Bandets historik för ett pass, läst ur dygnens filer: posterna per sekund (familjen som natten räknas ur) med
/// bandets tid i passets fönster, som `PassHistory.Reading`. Historiken för en tid hörs först när bandet synkar,
/// så den kan ligga i en senare dygnsfil än passets egen: dygnen läses i ordning från passets dag, och läsningen
/// slutar när historiken nått förbi passets slut.
///
/// Bara läsning, med samma väg som natten (`K18Nights.load` och `K18Collector`); inget i nattens filer eller
/// räkning ändras. Körs på passets filkö, aldrig på huvudkön: en dygnsfil kan vara tiotals MB.
enum PassHistorik {
    /// METOD M68. **antagande**. Så långt efter passets slut läses poster, för att se att historiken nått förbi det.
    static let efterSekunder: TimeInterval = 6 * 3600

    struct Läst {
        var poster: [PassHistory.Reading] = []
        /// Den senaste tiden historiken setts nå, om någon post efter fönstrets början fanns.
        var nått: Date?
        /// Dygnens filer som lästs, med storleken de hade: ett dygn som inte vuxit läses inte om för samma pass.
        var sedda: [String: Int] = [:]
    }

    /// Posterna i passets fönster ur de dygn som tillkommit eller vuxit sedan `sedda`.
    static func läs(_ pass: Pass, now: Date, sedda: [String: Int]) -> Läst {
        var ut = Läst(sedda: sedda)
        guard let w = PassHistory.window(pass) else { return ut }
        let slut: Date = w.upperBound.addingTimeInterval(efterSekunder)
        let zon: Int = TimeZone.current.secondsFromGMT(for: pass.start)
        let till: Date = min(now, pass.start.addingTimeInterval(PassHistory.searchSeconds)).addingTimeInterval(1)
        var samlare = K18Collector(from: w.lowerBound, to: slut)
        for stam in DayLog.stems(touching: w.lowerBound, to: till, utcOffsetSeconds: zon) {
            let storlek: Int = NightFiles.size(stam)
            guard storlek > 0, sedda[stam] != storlek, let fil = K18Nights.load(stam) else { continue }
            if let ramar = fil.frames {
                samlare.read(log: ramar)
            } else if let data = fil.archive, let arkiv = try? DayArchive.decode(data) {
                samlare.read(archive: arkiv)
            }
            ut.sedda[stam] = storlek
            // Historiken har nått förbi passets slut: senare dygn behövs inte.
            if let sista = samlare.series().records.last, Double(sista.time) >= w.upperBound.timeIntervalSince1970 { break }
        }
        let poster: [K18Record] = samlare.series().records
        ut.nått = poster.last.map { Date(timeIntervalSince1970: TimeInterval($0.time)) }
        ut.poster = poster.map { (r: K18Record) -> PassHistory.Reading in PassHistory.Reading(time: r.time, bpm: r.pulse) }
        return ut
    }

    /// BESLUT B146. Pulsen under `sekunder` före passets Start ur dygnens filer, för kurvans del före Start. Bara
    /// läsning; passet ändras inte. Poster utan puls (utanför `PassHistory.bpmRange`) tas bort.
    static func före(_ pass: Pass, sekunder: TimeInterval) -> [PassHistory.Reading] {
        guard sekunder > 0 else { return [] }
        let från: Date = pass.start.addingTimeInterval(-sekunder)
        let zon: Int = TimeZone.current.secondsFromGMT(for: pass.start)
        var samlare = K18Collector(from: från, to: pass.start)
        // Posterna kan ha kommit med en senare synk: läs från dygnet då fönstret börjar till dygnet efter passet.
        let till: Date = min(Date(), pass.start.addingTimeInterval(86_400))
        for stam in DayLog.stems(touching: från, to: till, utcOffsetSeconds: zon) {
            guard NightFiles.size(stam) > 0, let fil = K18Nights.load(stam) else { continue }
            if let ramar = fil.frames {
                samlare.read(log: ramar)
            } else if let data = fil.archive, let arkiv = try? DayArchive.decode(data) {
                samlare.read(archive: arkiv)
            }
        }
        let start: Int = Int(pass.start.timeIntervalSince1970.rounded(.down))
        return samlare.series().records
            .filter { (r: K18Record) -> Bool in r.time < start && PassHistory.bpmRange.contains(r.pulse) }
            .map { (r: K18Record) -> PassHistory.Reading in PassHistory.Reading(time: r.time, bpm: r.pulse) }
    }
}
