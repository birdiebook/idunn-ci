import Foundation

/// BESLUT B158 · METOD M85 · METOD M68
/// Ett pass som läggs till för hand i efterhand: reglerna för tiderna, standardtiderna i bladet och passet som det
/// sparas. Pulsen fylls ur bandets historik som för ett förslag (`PassHistory.fill`); finns ingen än sparas passet ändå
/// och fylls av samma påfyllnad som för varje sparat pass med luckor (`PassHistory.awaitsHistory`, BESLUT B117).
public enum PassManual {
    /// METOD M85. Ett pass är högst så här långt: samma tak som `PassRules.staleSeconds` (4 timmar, METOD M47).
    public static let maxDurationSeconds: TimeInterval = PassRules.staleSeconds
    /// METOD M85. Start högst så här långt bakåt: så länge appen letar efter bandets historik (`PassHistory.searchSeconds`,
    /// METOD M68; rådygnen sparas 14 dagar, BESLUT B41).
    public static let maxAgeSeconds: TimeInterval = PassHistory.searchSeconds
    /// METOD M85. Standardtiderna i bladet avrundas ner till så här många minuter.
    public static let roundMinutes: Int = 5
    /// METOD M85. Standardstarten ligger så här långt före standardstoppet.
    public static let defaultLengthSeconds: TimeInterval = 30 * 60

    /// Varför tiderna inte går att lägga till.
    public enum Problem: Equatable, Sendable {
        case stopNotAfterStart
        case stopInFuture
        case tooLong
        case tooOld
        case overlaps

        /// Den korta raden under tiderna.
        public var message: String {
            switch self {
            case .stopNotAfterStart: return "Stopp måste vara efter Start."
            case .stopInFuture: return "Stopp kan inte vara senare än nu."
            case .tooLong: return "Ett pass är högst 4 timmar."
            case .tooOld: return "Start kan vara högst 14 dagar bakåt."
            case .overlaps: return "Tiden ligger i ett annat pass."
            }
        }
    }

    /// Tiden nedrundad till hel minut (passets tider sparas i hela minuter).
    public static func wholeMinute(_ t: Date) -> Date {
        Date(timeIntervalSince1970: (t.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    /// Tiden nedrundad till `roundMinutes` minuter.
    public static func rounded(_ t: Date) -> Date {
        let steg: Double = Double(roundMinutes) * 60
        return Date(timeIntervalSince1970: (t.timeIntervalSince1970 / steg).rounded(.down) * steg)
    }

    /// Standardtiderna: Stopp är nu avrundat ner (så att det aldrig hamnar efter nu), Start en halvtimme före det.
    public static func defaults(now: Date) -> (start: Date, stop: Date) {
        let stopp: Date = rounded(now)
        return (rounded(stopp.addingTimeInterval(-defaultLengthSeconds)), stopp)
    }

    /// Stopp ur hjulets klockslag (`PassClock`): samma dag som Start, och dagen efter när klockslaget då skulle ligga före
    /// Start (över midnatt). Det är klockslaget inom ett dygn efter Start, alltså det som ligger närmast tolv timmar efter
    /// Start. Samma klockslag som Start blir Start själv (längd noll), och regeln `stopNotAfterStart` fäller det.
    public static func stopDate(start: Date, wheelMinutes m: Int, timeZone: TimeZone = TimeZone.current) -> Date {
        PassClock.date(wheelMinutes: m, near: start.addingTimeInterval(43_200), timeZone: timeZone)
    }

    /// Reglerna: Stopp efter Start, Stopp högst nu, längd högst `maxDurationSeconds`, Start högst `maxAgeSeconds`
    /// bakåt, och ingen överlappning med ett pass som finns (Start till efterperiodens slut, samma tider som
    /// förslagen stängs ute av, `PassSuggestions.excluded`). `nil` när allt är i sin ordning.
    public static func problem(start: Date, stop: Date, now: Date, existing: [Pass]) -> Problem? {
        let a: Date = wholeMinute(start)
        let b: Date = wholeMinute(stop)
        if b <= a { return .stopNotAfterStart }
        if b > now { return .stopInFuture }
        if b.timeIntervalSince(a) > maxDurationSeconds { return .tooLong }
        if now.timeIntervalSince(a) > maxAgeSeconds { return .tooOld }
        let från: Int = Int(a.timeIntervalSince1970) / 60
        let till: Int = Int(b.addingTimeInterval(PassRules.afterSeconds).timeIntervalSince1970) / 60
        let upptagna: [ClosedRange<Int>] = PassSuggestions.excluded(passes: existing, store: PassSuggestions.Store())
        for r in upptagna where r.lowerBound <= till && r.upperBound >= från {
            return .overlaps
        }
        return nil
    }

    /// Passet som sparas: tiderna i hela minuter, efterperioden stängd efter `PassRules.afterSeconds`, märkningen
    /// (`PassEdit.apply`), märkt som tillagt för hand, och pulsen fylld ur `readings` (kan vara tom: då fylls den
    /// senare, BESLUT B117).
    public static func pass(start: Date, stop: Date, label: PassLabel, readings: [PassHistory.Reading] = [],
                            id: UUID = UUID()) -> Pass {
        let a: Date = wholeMinute(start)
        let b: Date = max(a, wholeMinute(stop))
        var p = Pass(id: id, start: a, stop: b)
        p.afterEnd = b.addingTimeInterval(PassRules.afterSeconds)
        PassEdit.apply(label, to: &p)
        p.addedByHand = true
        return PassHistory.fill(p, readings: readings)
    }
}
