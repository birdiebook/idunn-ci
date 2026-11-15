import Foundation

/// BESLUT B117 · METOD M68
/// Pulsen i ett pass ur bandets egen historik, i efterhand. Bandet sparar sin puls en gång i sekunden vare sig
/// telefonen hör det eller inte, och lämnar den vid nästa synk. Ett pass där telefonen låg utom räckhåll (i skåpet
/// under bastun) har därför inga prov när det sparas, men får dem när historiken för passets tid finns på telefonen.
///
/// Här finns bara räkningen, utan filer och utan bandets format: appen läser historikens poster ur dygnens filer
/// och lämnar dem som `Reading` (tid och puls).
///
/// - **Fönstret** är Start till slutet av efterperioden.
/// - **Liveprov behålls.** Historiken fyller bara luckor: sträckor i fönstret där två liveprov i följd (eller
///   fönstrets kant och ett liveprov) ligger mer än `gapSeconds` isär. Ett pass helt utan liveprov är en enda lucka.
/// - **Varje fyllt prov bär sin källa** (`PassSample.source == .history`).
/// - **Idempotent och växande:** att fylla igen med samma poster ändrar ingenting, och poster som fyllts förut
///   ligger kvar även när en senare läsning ger färre (rådygnet raderat).
public enum PassHistory {
    /// En post ur bandets historik: bandets tid i hela sekunder sedan 1970, och pulsen.
    public struct Reading: Equatable, Sendable {
        public var time: Int
        public var bpm: Int

        public init(time: Int, bpm: Int) {
            self.time = time
            self.bpm = bpm
        }
    }

    /// METOD M68. **antagande**: en lucka är mer än så här mellan två prov (liveproven kommer en gång i sekunden).
    public static let gapSeconds: TimeInterval = 10
    /// METOD M68. Samma gränser som för realtidspulsen (M48): historiken har poster med puls 0 när bandet inte
    /// har någon puls att ge, och de är inte prov.
    public static let bpmRange = 25...230
    /// METOD M68. **antagande**: så länge efter passet letar appen efter historiken, och säger vyn att den väntar.
    public static let searchSeconds: TimeInterval = 14 * 86400

    /// Fönstret: Start till slutet av efterperioden. `nil` medan passet pågår (inget stopp).
    public static func window(_ p: Pass) -> ClosedRange<Date>? {
        guard let stop = p.stop else { return nil }
        let slut: Date = p.afterEnd ?? stop.addingTimeInterval(PassRules.afterSeconds)
        guard slut >= p.start else { return nil }
        return p.start...slut
    }

    /// Luckorna i fönstret: sträckor längre än `gapSeconds` utan prov. `liveOnly` räknar bara liveproven (det
    /// historiken får fylla); annars alla prov (det som fortfarande saknas).
    public static func gaps(_ p: Pass, liveOnly: Bool = false) -> [ClosedRange<Date>] {
        guard let w = window(p) else { return [] }
        var tider: [Date] = p.samples
            .filter { (!liveOnly || $0.source == nil) && w.contains($0.t) }
            .map(\.t)
            .sorted()
        tider.insert(w.lowerBound, at: 0)
        tider.append(w.upperBound)
        var ut: [ClosedRange<Date>] = []
        for i in 1..<tider.count where tider[i].timeIntervalSince(tider[i - 1]) > gapSeconds {
            ut.append(tider[i - 1]...tider[i])
        }
        return ut
    }

    /// Sekunder av fönstret som ligger i en lucka.
    public static func missingSeconds(_ p: Pass) -> TimeInterval {
        gaps(p).reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
    }

    /// Passet väntar på bandets historik: det är stoppat, har luckor, är högst `searchSeconds` gammalt, och
    /// historiken har inte setts nå förbi passets slut. När den har det är luckorna som finns kvar bandets egna
    /// (bandet satt inte på), och passet väntar inte längre.
    public static func awaitsHistory(_ p: Pass, now: Date) -> Bool {
        guard let w = window(p), now.timeIntervalSince(p.start) <= searchSeconds else { return false }
        if let nått = p.historyThrough, nått >= w.upperBound { return false }
        return !gaps(p).isEmpty
    }

    /// Passet med luckorna fyllda ur historiken. `through` är den senaste tiden historiken setts nå (för
    /// `awaitsHistory`); den backar aldrig.
    public static func fill(_ p: Pass, readings: [Reading], through: Date? = nil) -> Pass {
        var ut = p
        if let t = through { ut.historyThrough = max(p.historyThrough ?? t, t) }
        guard let w = window(p) else { return ut }
        let live: [PassSample] = p.samples.filter { $0.source == nil }
        // Historiken per sekund: det som fyllts förut, och de nya posterna ovanpå.
        var perSekund: [Int: Int] = [:]
        for s in p.samples where s.source == .history {
            perSekund[Int(s.t.timeIntervalSince1970.rounded(.down))] = s.bpm
        }
        for r in readings where bpmRange.contains(r.bpm) { perSekund[r.time] = r.bpm }
        let luckor = gaps(p, liveOnly: true)
        let liveTider: Set<Date> = Set(live.map(\.t))
        var fyllda: [PassSample] = []
        for (sekund, bpm) in perSekund {
            let t = Date(timeIntervalSince1970: TimeInterval(sekund))
            // I en lucka (kanterna räknas, så att fönstrets första och sista sekund fylls), men aldrig på ett liveprov.
            guard luckor.contains(where: { $0.contains(t) }), !liveTider.contains(t) else { continue }
            fyllda.append(PassSample(t: t, bpm: bpm, source: .history))
        }
        ut.samples = (live + fyllda).sorted { (a: PassSample, b: PassSample) -> Bool in
            a.t != b.t ? a.t < b.t : (a.source == nil && b.source != nil)
        }
        return ut
    }
}
