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

    /// BESLUT B152 · METOD M86. Bandets puls strax före Start och strax efter slutet av passet (`marginal` sekunder på var
    /// sida), ur dygnens filer, för den uttonade pulsen kant till kant i kurvan. Bara läsning, som `läs`; körs aldrig på
    /// huvudkön. Tomt när dygnens filer inte har tiden.
    static func omkring(_ pass: Pass, marginal: TimeInterval, now: Date) -> [PassHistory.Reading] {
        let slut: Date = pass.afterEnd ?? pass.stop ?? pass.start
        let från: Date = pass.start.addingTimeInterval(-marginal)
        let till: Date = slut.addingTimeInterval(marginal)
        let zon: Int = TimeZone.current.secondsFromGMT(for: pass.start)
        // Historiken för tiden kan ligga i en senare dygnsfil än passets egen (se ovan).
        let sökTill: Date = min(now, pass.start.addingTimeInterval(PassHistory.searchSeconds)).addingTimeInterval(1)
        var samlare = K18Collector(from: från, to: till)
        for stam in DayLog.stems(touching: från, to: sökTill, utcOffsetSeconds: zon) {
            guard NightFiles.size(stam) > 0, let fil = K18Nights.load(stam) else { continue }
            if let ramar = fil.frames {
                samlare.read(log: ramar)
            } else if let data = fil.archive, let arkiv = try? DayArchive.decode(data) {
                samlare.read(archive: arkiv)
            }
            if let sista = samlare.series().records.last, Double(sista.time) >= till.timeIntervalSince1970 { break }
        }
        return samlare.series().records.map { (r: K18Record) -> PassHistory.Reading in
            PassHistory.Reading(time: r.time, bpm: r.pulse)
        }
    }
}
