import Foundation
import HeartRate

/// BESLUT B58 · METOD M47
/// Passets typ: väljs när passet sparas, aldrig före. Rå-värdet är svenska och
/// sparas i filen, så ett värde ändras aldrig (en fil från ett äldre bygge ska
/// gå att läsa).
public enum PassKind: String, Codable, CaseIterable, Sendable {
    case bastu
    case dusch
    case styrka
    case kondition
    case promenad
    /// BESLUT B142.
    case golf

    /// Namnet som visas, med stor bokstav.
    public var displayName: String {
        switch self {
        case .bastu: return "Bastu"
        case .dusch: return "Dusch"
        case .styrka: return "Styrka"
        case .kondition: return "Kondition"
        case .promenad: return "Promenad"
        case .golf: return "Golf"
        }
    }
}

/// BESLUT B147 · METOD M84
/// Förslaget ett pass kom ur, som det var när det lades till: start, slut och den gissade typen (`nil` när ingen
/// gissades). Står bredvid det användaren valde, så att skillnaden visar var förslagen låg fel.
public struct PassOrigin: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var kind: PassKind?

    public init(start: Date, end: Date, kind: PassKind?) {
        self.start = start
        self.end = end
        self.kind = kind
    }
}

/// BESLUT B117 · METOD M68
/// Varifrån ett pulsprov kom, när det inte kom live under passet.
public enum PassSampleSource: String, Codable, Sendable {
    /// Ur bandets egen historik, läst i efterhand (`PassHistory.fill`).
    case history = "historik"
}

/// BESLUT B58 · METOD M47
/// Ett pulsprov: tiden det kom och slag per minut. `source` är `nil` för ett prov som kom live under passet,
/// och nyckeln skrivs då inte: en fil från ett äldre bygge saknar den och läses som live (BESLUT B117).
public struct PassSample: Codable, Equatable, Sendable {
    public var t: Date
    public var bpm: Int
    public var source: PassSampleSource?

    public init(t: Date, bpm: Int, source: PassSampleSource? = nil) {
        self.t = t
        self.bpm = bpm
        self.source = source
    }
}

/// BESLUT B58 · METOD M47
/// Konstanterna för passets tider och för pulsens återhämtning efter stopp.
public enum PassRules {
    /// METOD M47. Efterperioden: Idunn mäter 10 minuter efter stopp. 10 min är
    /// ett antagande (ett längre svar på hur pulsen sjunker än källans 1 min).
    public static let afterSeconds: TimeInterval = 600
    /// METOD M47. Återhämtningen läses vid 1, 2 och 5 minuter efter stopp.
    /// 1 min är källans mått (Cole m.fl. 1999); 2 och 5 min är antaganden.
    public static let recoveryOffsets: [Int] = [60, 120, 300]
    /// METOD M47. Ett prov räknas som pulsen vid en tidpunkt om det ligger
    /// högst så här många sekunder från den; annars saknas värdet.
    public static let matchToleranceSeconds: TimeInterval = 5
    /// BESLUT B58. Ett pass som aldrig stoppats och inte fått ett prov på så
    /// här länge avslutas vid sista provet (appen dödad mitt i passet).
    public static let staleSeconds: TimeInterval = 4 * 3600
}

/// BESLUT B58 · METOD M47
/// Pulsen vid en tid efter stopp, och fallet från pulsen vid stopp.
public struct PassRecoveryPoint: Equatable, Sendable {
    /// Sekunder efter stopp (60, 120, 300).
    public var seconds: Int
    /// Pulsen då, `nil` när inget prov ligger inom toleransen.
    public var bpm: Int?
    /// Fallet i slag per minut från pulsen vid stopp (positivt = pulsen har sjunkit);
    /// `nil` när pulsen då eller vid stopp saknas.
    public var drop: Int?
}

/// BESLUT B58 · METOD M47
/// Ett pass: pulsen från Start till Stopp, och efteråt mätningen av hur pulsen
/// sjunker. Bara pulsproven sparas; en pass med typ, tider och prov är hela
/// filen.
public struct Pass: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// När användaren tryckte Start.
    public var start: Date
    /// När användaren tryckte Stopp; `nil` medan passet pågår.
    public var stop: Date?
    /// Slutet på mätningen efter stopp; `nil` tills passet är färdigt.
    public var afterEnd: Date?
    public var kind: PassKind?
    public var samples: [PassSample]
    /// BESLUT B107 · METOD M63. Spåret från telefonens GPS: `nil` för ett pass inomhus, en lista (som kan
    /// vara tom innan första positionen kommit) för ett pass ute. En fil från ett äldre bygge saknar nyckeln.
    public var track: [TrackPoint]?
    /// BESLUT B106 · METOD M62. Stegets höjd i cm när passet är ett steptest, annars `nil`.
    public var stepHeightCm: Double?
    /// BESLUT B117 · METOD M68. Så långt hade bandets historik nått när passet senast fylldes ur den; `nil` innan
    /// någon historik efter passets slut är sedd. En fil från ett äldre bygge saknar nyckeln.
    public var historyThrough: Date?
    /// BESLUT B147. användaren egen typ med egna ord ("Annat…"), när ingen av de fasta passar; `kind` är då `nil`.
    /// En fil från ett äldre bygge saknar nyckeln.
    public var customKind: String?
    /// BESLUT B147. En valfri anteckning. En fil från ett äldre bygge saknar nyckeln.
    public var note: String?
    /// BESLUT B147 · METOD M84. Förslaget passet kom ur, som det var när det lades till: facit för passupptäckten.
    /// `nil` för ett pass som startats för hand och i en fil från ett äldre bygge.
    public var suggested: PassOrigin?

    public init(id: UUID = UUID(), start: Date, stop: Date? = nil, afterEnd: Date? = nil,
                kind: PassKind? = nil, samples: [PassSample] = [], track: [TrackPoint]? = nil,
                stepHeightCm: Double? = nil, historyThrough: Date? = nil, customKind: String? = nil,
                note: String? = nil, suggested: PassOrigin? = nil) {
        self.id = id
        self.start = start
        self.stop = stop
        self.afterEnd = afterEnd
        self.kind = kind
        self.samples = samples
        self.track = track
        self.stepHeightCm = stepHeightCm
        self.historyThrough = historyThrough
        self.customKind = customKind
        self.note = note
        self.suggested = suggested
    }

    /// BESLUT B147. Namnet på passets typ: den egna typen, annars den fasta, annars "Pass".
    public var kindName: String {
        customKind ?? kind?.displayName ?? "Pass"
    }

    /// Passet mäts ute, med spår.
    public var isOutdoor: Bool { track != nil }
    /// Passet är ett steptest.
    public var isStepTest: Bool { stepHeightCm != nil }

    /// BESLUT B107. Passet utan positioner, för en export utan spår.
    public func withoutTrack() -> Pass {
        var p = self
        p.track = nil
        return p
    }

    /// Passet är färdigt när mätningen efter stopp är slut.
    public var isFinished: Bool { afterEnd != nil }

    /// Längden: Start till Stopp, eller medan passet pågår (eller om det aldrig
    /// stoppades) till sista provet. 0 utan prov och utan stopp.
    public var duration: TimeInterval {
        if let s = stop { return max(0, s.timeIntervalSince(start)) }
        guard let last = samples.last?.t else { return 0 }
        return max(0, last.timeIntervalSince(start))
    }

    /// Proven i den aktiva delen: Start…Stopp (alla prov om passet inte stoppats).
    public var activeSamples: [PassSample] {
        guard let s = stop else { return samples }
        return samples.filter { $0.t <= s }
    }

    /// Proven från Stopp och framåt (efterperioden); tom utan stopp.
    public var afterSamples: [PassSample] {
        guard let s = stop else { return [] }
        return samples.filter { $0.t >= s }
    }

    /// METOD M47. Lägsta puls i den aktiva delen.
    public var minBpm: Int? { activeSamples.map(\.bpm).min() }
    /// METOD M47. Högsta puls i den aktiva delen.
    public var maxBpm: Int? { activeSamples.map(\.bpm).max() }
    /// METOD M47. Snittet: medel av den aktiva delens prov (inte tidsviktat).
    public var averageBpm: Double? {
        let a = activeSamples
        guard !a.isEmpty else { return nil }
        return Double(a.reduce(0) { $0 + $1.bpm }) / Double(a.count)
    }

    /// METOD M47. Pulsen vid tiden `time`: närmaste prov inom ±5 s, annars `nil`.
    /// Vid lika avstånd gäller det tidigare provet.
    public func pulse(at time: Date) -> Int? {
        var best: PassSample?
        var bestDistance = PassRules.matchToleranceSeconds + 1
        for s in samples {
            let d = abs(s.t.timeIntervalSince(time))
            if d <= PassRules.matchToleranceSeconds, d < bestDistance {
                best = s
                bestDistance = d
            }
        }
        return best?.bpm
    }

    /// METOD M47. Pulsen vid stopp; `nil` utan stopp eller utan prov nära stoppet.
    public var pulseAtStop: Int? {
        guard let s = stop else { return nil }
        return pulse(at: s)
    }

    /// METOD M47. Pulsen `seconds` efter stopp.
    public func pulse(after seconds: Int) -> Int? {
        guard let s = stop else { return nil }
        return pulse(at: s.addingTimeInterval(TimeInterval(seconds)))
    }

    /// METOD M47. Fallet i slag per minut från pulsen vid stopp till `seconds` efter stopp.
    public func drop(after seconds: Int) -> Int? {
        guard let a = pulseAtStop, let b = pulse(after: seconds) else { return nil }
        return a - b
    }

    /// METOD M47. Återhämtningen vid 1, 2 och 5 minuter; värden som ännu inte
    /// mätts eller saknar prov är `nil`.
    public var recovery: [PassRecoveryPoint] {
        PassRules.recoveryOffsets.map {
            PassRecoveryPoint(seconds: $0, bpm: pulse(after: $0), drop: drop(after: $0))
        }
    }

    /// Sekunder kvar av efterperioden vid tiden `now`; `nil` när passet inte stoppats. Räknas ur stoppet,
    /// så att vyn kan visa nedräkningen utan tillståndsmaskinen.
    public func afterRemaining(now: Date) -> TimeInterval? {
        guard let s = stop else { return nil }
        return max(0, PassRules.afterSeconds - now.timeIntervalSince(s))
    }

    /// BESLUT B58. Passet avslutat som det står: ett osparat pass som hittas
    /// när något annat redan pågår stängs vid stopp (eller sista provet).
    public func closed() -> Pass {
        var p = self
        let slut: Date = stop ?? samples.last?.t ?? start
        if p.stop == nil { p.stop = slut }
        if p.afterEnd == nil { p.afterEnd = p.stop }
        return p
    }
}
