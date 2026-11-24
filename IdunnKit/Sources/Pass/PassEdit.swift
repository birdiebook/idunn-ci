import Foundation

/// BESLUT B150 · METOD M85
/// Märkningen av ett pass: typen (fast eller med egna ord) och en anteckning.
public struct PassLabel: Equatable, Sendable {
    /// Den fasta typen; `nil` när den egna typen gäller eller ingen typ valts.
    public var kind: PassKind?
    /// Den egna typen ("Annat…"). Gäller före `kind` när den inte är tom.
    public var customKind: String?
    public var note: String?

    public init(kind: PassKind? = nil, customKind: String? = nil, note: String? = nil) {
        self.kind = kind
        self.customKind = customKind
        self.note = note
    }

    /// Märkningen som passet bär den.
    public init(_ p: Pass) {
        self.init(kind: p.kind, customKind: p.customKind, note: p.note)
    }
}

/// BESLUT B150 · METOD M85
/// Att ändra ett sparat pass eller ett förslag innan det läggs till: märkningen, och start och slut i minutsteg.
/// Allt räknas om ur proven i det nya fönstret: lägst, snitt, högst, zoner och belastning är räknade egenskaper hos
/// `Pass`, så det räcker att fönstret och proven stämmer.
public enum PassEdit {
    /// METOD M85. **antagande**: start och slut flyttas högst så här långt utanför passets tider när bladet öppnades
    /// (B146: förslagen ligger i medel 10–20 minuter fel, så en timme räcker med marginal).
    public static let marginSeconds: TimeInterval = 3600
    /// METOD M85. Passet är minst en minut långt.
    public static let shortestSeconds: TimeInterval = 60
    /// METOD M85. Egna ord kortas till så här många tecken: det är en typ och en rad, inte en dagbok.
    public static let customKindMaxLength = 40
    /// METOD M85. Anteckningen kortas till så här många tecken.
    public static let noteMaxLength = 500

    /// Text utan blanksteg i kanterna, kortad till `max` tecken; tom blir `nil`.
    public static func clean(_ text: String?, max: Int) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(max))
    }

    /// Lägger märkningen på passet. Egna ord tar över den fasta typen (som blir `nil`); utan egna ord gäller den
    /// fasta typen.
    public static func apply(_ label: PassLabel, to p: inout Pass) {
        if let egen = clean(label.customKind, max: customKindMaxLength) {
            p.customKind = egen
            p.kind = nil
        } else {
            p.customKind = nil
            p.kind = label.kind
        }
        p.note = clean(label.note, max: noteMaxLength)
    }

    /// Gränserna för start och slut: `marginSeconds` före start och efter slut, och aldrig efter `now`.
    public struct Limits: Equatable, Sendable {
        public var earliest: Date
        public var latest: Date

        public init(start: Date, stop: Date, now: Date) {
            earliest = start.addingTimeInterval(-PassEdit.marginSeconds)
            latest = max(stop, min(stop.addingTimeInterval(PassEdit.marginSeconds), now))
        }
    }

    /// Vilken kant som flyttas.
    public enum Edge: Sendable {
        case start, stop
    }

    /// Start och slut med kanten `edge` flyttad `minutes` minuter, inom gränserna och så att passet är minst
    /// `shortestSeconds` långt.
    public static func moved(start: Date, stop: Date, edge: Edge, minutes: Int, limits: Limits)
        -> (start: Date, stop: Date) {
        let steg: TimeInterval = TimeInterval(minutes * 60)
        return set(start: start, stop: stop, edge: edge, to: (edge == .start ? start : stop).addingTimeInterval(steg),
                   limits: limits)
    }

    /// BESLUT B158. Start och slut med kanten `edge` satt till `time` (ur tidshjulet), klampad som `moved`: inom
    /// gränserna och så att passet är minst `shortestSeconds` långt.
    public static func set(start: Date, stop: Date, edge: Edge, to time: Date, limits: Limits)
        -> (start: Date, stop: Date) {
        switch edge {
        case .start:
            let senast: Date = stop.addingTimeInterval(-shortestSeconds)
            return (min(max(time, limits.earliest), max(limits.earliest, senast)), stop)
        case .stop:
            let tidigast: Date = start.addingTimeInterval(shortestSeconds)
            return (start, max(min(time, limits.latest), min(limits.latest, tidigast)))
        }
    }

    /// Passet med nya tider: Start och Stopp flyttas, efterperioden behåller sin längd (högst `PassRules.afterSeconds`)
    /// efter det nya stoppet, och prov utanför det nya fönstret tas bort. Ett pass utan stopp ändras inte. Prov som
    /// saknas i det nya fönstret fylls sedan ur bandets historik (`PassHistory.fill`).
    public static func retimed(_ p: Pass, start: Date, stop: Date) -> Pass {
        guard let gammalStopp = p.stop else { return p }
        let slut: Date = max(start, stop)
        let efter: TimeInterval = p.afterEnd.map { (e: Date) -> TimeInterval in
            min(PassRules.afterSeconds, max(0, e.timeIntervalSince(gammalStopp)))
        } ?? PassRules.afterSeconds
        var ut = p
        ut.start = start
        ut.stop = slut
        ut.afterEnd = slut.addingTimeInterval(efter)
        let fönster: ClosedRange<Date> = start...slut.addingTimeInterval(efter)
        ut.samples = p.samples.filter { fönster.contains($0.t) }
        // Spåret gäller den aktiva delen: sträcka och tempo räknas också om.
        ut.track = p.track.map { (spår: [TrackPoint]) -> [TrackPoint] in spår.filter { (start...slut).contains($0.t) } }
        return ut
    }
}
