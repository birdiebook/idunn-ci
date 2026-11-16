import Foundation
import Fitness
import Markers
import Night
import Pass
import SleepNeed

/// BESLUT B127 · METOD M73
/// Det Idunn skickar till coachen: en sammanfattning per natt, per pass och per inskriven mätning, och profilen.
/// Bara samlade tal. Här finns inget fält för ett enskilt slag, ett pulsprov, en position eller ett ljud, så det
/// som inte får lämna telefonen går inte att lägga i ett dokument (prövat i `CoachTests`).
///
/// Dokumenten kodas med sorterade nycklar i snake_case; namnen här är alltså kolumnerna coachen läser.
public enum CoachKind: String, Codable, CaseIterable, Sendable {
    case night = "natt"
    case pass = "pass"
    case measurement = "matning"
    case profile = "profil"
    case status = "status"
}

/// METOD M73. Avrundningen: talen skickas med så många decimaler som de visas med, så att en omräkning som bara
/// flyttar en sista decimal inte skickar natten igen.
enum CoachRound {
    static func r(_ v: Double?, _ decimaler: Int) -> Double? {
        guard let v, v.isFinite else { return nil }
        let p: Double = pow(10, Double(decimaler))
        return (v * p).rounded() / p
    }

    /// `yyyy-MM-dd` för en dag räknad som dagar sedan 1970-01-01, utan DateFormatter (BESLUT B6).
    static func dag(_ daysSince1970: Int) -> String {
        // Civil from days (Howard Hinnant): proleptiska gregorianska kalendern.
        let z: Int = daysSince1970 + 719_468
        let era: Int = (z >= 0 ? z : z - 146_096) / 146_097
        let doe: Int = z - era * 146_097
        let yoe: Int = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy: Int = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp: Int = (5 * doy + 2) / 153
        let d: Int = doy - (153 * mp + 2) / 5 + 1
        let m: Int = mp < 10 ? mp + 3 : mp - 9
        let y: Int = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Ögonblicket som ISO 8601 i UTC, hela sekunder.
    static func tid(_ t: Date) -> String {
        let s: Int = Int(t.timeIntervalSince1970.rounded(.down))
        let dagar: Int = Int((Double(s) / 86_400).rounded(.down))
        let rest: Int = s - dagar * 86_400
        return dag(dagar) + String(format: "T%02d:%02d:%02dZ", rest / 3_600, (rest % 3_600) / 60, rest % 60)
    }
}

/// BESLUT B127. Huvudtalen för en morgon, som appen räknat dem (`SömnbehovModell`): sömnpoängen med sina delar,
/// återhämtningen med vad som drog, och sömnbehovet i timmar. Allt valfritt: ett tal som inte finns skickas inte.
public struct CoachScores: Equatable, Sendable {
    public var sleepScore: Int?
    public var scoreAmount: Double?
    public var scoreContinuity: Double?
    public var scoreRegularity: Double?
    public var recovery: Int?
    public var dragHrv: Double?
    public var dragPulse: Double?
    public var dragSleep: Double?
    public var breathingHigh: Bool?
    public var needHours: Double?
    public var needBase: Double?
    public var needPass: Double?
    public var needDebt: Double?
    public var debtHours: Double?

    public init(sleepScore: Int? = nil, scoreAmount: Double? = nil, scoreContinuity: Double? = nil,
                scoreRegularity: Double? = nil, recovery: Int? = nil, dragHrv: Double? = nil,
                dragPulse: Double? = nil, dragSleep: Double? = nil, breathingHigh: Bool? = nil,
                needHours: Double? = nil, needBase: Double? = nil, needPass: Double? = nil,
                needDebt: Double? = nil, debtHours: Double? = nil) {
        self.sleepScore = sleepScore
        self.scoreAmount = scoreAmount
        self.scoreContinuity = scoreContinuity
        self.scoreRegularity = scoreRegularity
        self.recovery = recovery
        self.dragHrv = dragHrv
        self.dragPulse = dragPulse
        self.dragSleep = dragSleep
        self.breathingHigh = breathingHigh
        self.needHours = needHours
        self.needBase = needBase
        self.needPass = needPass
        self.needDebt = needDebt
        self.debtHours = debtHours
    }
}

/// BESLUT B127 · METOD M73
/// En natt som coachen ser den: uppvakningsdagen, sömnen, nattens mått och morgonens huvudtal.
public struct CoachNight: Codable, Equatable, Sendable {
    /// Uppvakningsdagen, `yyyy-MM-dd`. Nattens nyckel.
    public var day: String
    /// Varifrån slagen kom (`NightSource`).
    public var source: String
    public var sleepHours: Double?
    /// Insomning och uppvaknande i minuter efter midnatt på uppvakningsdagen (negativt = kvällen före).
    public var onsetMinutes: Double?
    public var wakeMinutes: Double?
    public var efficiency: Double?
    public var wakeBouts: Int?
    public var awakeMinutes: Double?
    public var lightMinutes: Double?
    public var deepMinutes: Double?
    public var remMinutes: Double?
    /// Nattens HRV (RMSSD, ms), vilopuls och medelpuls (slag/min), andning (andetag/min) och hudtemperatur (°C).
    public var hrvRmssd: Double?
    public var restingHeartRate: Double?
    public var meanHeartRate: Double?
    public var breathsPerMinute: Double?
    public var skinTemperature: Double?
    public var movementMinutes: Int?
    public var snoringPerHour: Double?
    public var sleepScore: Int?
    public var scoreAmount: Double?
    public var scoreContinuity: Double?
    public var scoreRegularity: Double?
    public var recovery: Int?
    public var dragHrv: Double?
    public var dragPulse: Double?
    public var dragSleep: Double?
    public var breathingHigh: Bool?
    public var needHours: Double?
    public var needBase: Double?
    public var needPass: Double?
    public var needDebt: Double?
    public var debtHours: Double?

    public init(_ n: Trends.IdunNight, scores s: CoachScores? = nil) {
        day = CoachRound.dag(n.day.daysSince1970)
        source = n.source.rawValue
        sleepHours = CoachRound.r(n.sleepHours, 2)
        onsetMinutes = CoachRound.r(n.onsetMinutes, 0)
        wakeMinutes = CoachRound.r(n.wakeMinutes, 0)
        efficiency = CoachRound.r(n.efficiency, 1)
        wakeBouts = n.wakeBouts
        awakeMinutes = CoachRound.r(n.awakeMinutes, 0)
        lightMinutes = CoachRound.r(n.lightMinutes, 0)
        deepMinutes = CoachRound.r(n.deepMinutes, 0)
        remMinutes = CoachRound.r(n.remMinutes, 0)
        hrvRmssd = CoachRound.r(n.rmssd, 1)
        restingHeartRate = CoachRound.r(n.restingHeartRate, 1)
        meanHeartRate = CoachRound.r(n.meanHeartRate, 1)
        breathsPerMinute = CoachRound.r(n.breathsPerMinute, 1)
        skinTemperature = CoachRound.r(n.skinTemperature, 2)
        movementMinutes = n.movementMinutes
        snoringPerHour = CoachRound.r(n.snoringPerHour, 1)
        sleepScore = s?.sleepScore
        scoreAmount = CoachRound.r(s?.scoreAmount, 0)
        scoreContinuity = CoachRound.r(s?.scoreContinuity, 0)
        scoreRegularity = CoachRound.r(s?.scoreRegularity, 0)
        recovery = s?.recovery
        dragHrv = CoachRound.r(s?.dragHrv, 1)
        dragPulse = CoachRound.r(s?.dragPulse, 1)
        dragSleep = CoachRound.r(s?.dragSleep, 1)
        breathingHigh = s?.breathingHigh
        needHours = CoachRound.r(s?.needHours, 2)
        needBase = CoachRound.r(s?.needBase, 2)
        needPass = CoachRound.r(s?.needPass, 2)
        needDebt = CoachRound.r(s?.needDebt, 2)
        debtHours = CoachRound.r(s?.debtHours, 2)
    }

    /// METOD M73. En natt per uppvakningsdag, äldst först: natten ur bandets historik går före en gammal
    /// inspelning, och av två ur samma källa gäller den med längst sovtid (samma val som sömnbehovet, METOD M53).
    public static func perDay(_ nights: [Trends.IdunNight]) -> [Trends.IdunNight] {
        var bäst: [Int: Trends.IdunNight] = [:]
        for n in nights {
            guard let finns = bäst[n.day.daysSince1970] else {
                bäst[n.day.daysSince1970] = n
                continue
            }
            let nyK18: Bool = n.source == .k18
            let gammalK18: Bool = finns.source == .k18
            if nyK18 != gammalK18 {
                if nyK18 { bäst[n.day.daysSince1970] = n }
            } else if (n.sleepHours ?? 0) > (finns.sleepHours ?? 0) {
                bäst[n.day.daysSince1970] = n
            }
        }
        return bäst.values.sorted { (a: Trends.IdunNight, b: Trends.IdunNight) -> Bool in a.day < b.day }
    }
}

/// BESLUT B127 · METOD M73
/// Ett pass som coachen ser det: typen, tiderna, pulsen i tal, tiden per zon, belastningen och, för ett pass ute,
/// sträckan och tempot. Aldrig spåret (BESLUT B107) och aldrig pulsproven.
public struct CoachPass: Codable, Equatable, Sendable {
    /// Passets id. Nyckeln.
    public var id: String
    public var kind: String?
    /// Dagen passet började, `yyyy-MM-dd` på väggklockan.
    public var day: String
    public var start: String
    public var stop: String?
    public var durationSeconds: Int
    public var minBpm: Int?
    public var avgBpm: Double?
    public var maxBpm: Int?
    public var pulseAtStop: Int?
    /// Pulsens fall 1, 2 och 5 minuter efter stopp (METOD M47).
    public var drop60: Int?
    public var drop120: Int?
    public var drop300: Int?
    /// Sekunder i zon 1–5 (METOD M53, M71); `nil` utan maxpuls.
    public var zone1Seconds: Int?
    public var zone2Seconds: Int?
    public var zone3Seconds: Int?
    public var zone4Seconds: Int?
    public var zone5Seconds: Int?
    /// Belastningen (METOD M53) och maxpulsen den räknades mot.
    public var load: Double?
    public var maxPulseUsed: Double?
    public var outdoor: Bool
    public var distanceMeters: Double?
    public var paceSecondsPerKm: Double?
    public var stepHeightCm: Double?
    /// Antal pulsprov i den aktiva delen, och om något av dem kom ur bandets historik i efterhand (BESLUT B117).
    public var pulseSamples: Int
    public var pulseFromHistory: Bool

    public init(_ p: Pass, maxPulse: Double?, utcOffsetSeconds: Int) {
        id = p.id.uuidString
        kind = p.kind?.rawValue
        day = CoachRound.dag(WakeDay(p.start, utcOffsetSeconds: utcOffsetSeconds).daysSince1970)
        start = CoachRound.tid(p.start)
        stop = p.stop.map { (t: Date) -> String in CoachRound.tid(t) }
        durationSeconds = Int(p.duration.rounded())
        minBpm = p.minBpm
        avgBpm = CoachRound.r(p.averageBpm, 1)
        maxBpm = p.maxBpm
        pulseAtStop = p.pulseAtStop
        drop60 = p.drop(after: 60)
        drop120 = p.drop(after: 120)
        drop300 = p.drop(after: 300)
        let aktiva: [PassSample] = p.activeSamples
        if let mp = maxPulse, mp > 0 {
            let delar: [PassZones.Share] = PassZones.time(aktiva) { (bpm: Int) -> Int in
                PassLoad.zone(bpm: bpm, maxPulse: mp)
            }
            func sek(_ zon: Int) -> Int {
                Int((delar.first { (d: PassZones.Share) -> Bool in d.zone == zon }?.seconds ?? 0).rounded())
            }
            zone1Seconds = sek(1)
            zone2Seconds = sek(2)
            zone3Seconds = sek(3)
            zone4Seconds = sek(4)
            zone5Seconds = sek(5)
            load = CoachRound.r(PassLoad.load(p, maxPulse: mp), 1)
            maxPulseUsed = CoachRound.r(mp, 0)
        }
        outdoor = p.isOutdoor
        if let spår = p.track {
            let meter: Double = PassRoute.distance(spår)
            distanceMeters = CoachRound.r(meter, 0)
            paceSecondsPerKm = CoachRound.r(PassRoute.pace(distance: meter, seconds: p.duration), 0)
        }
        stepHeightCm = p.stepHeightCm
        pulseSamples = aktiva.count
        pulseFromHistory = aktiva.contains { (s: PassSample) -> Bool in s.source == .history }
    }
}

/// BESLUT B127 · METOD M73
/// En mätning användaren skrivit in på Profil (BESLUT B104): markören med namn och enhet, dagen och värdet.
public struct CoachMeasurement: Codable, Equatable, Sendable {
    public var id: String
    public var marker: String
    public var name: String
    public var unit: String
    public var day: String
    public var value: Double
    public var note: String?

    public init(_ m: MarkerReading, definition d: MarkerDefinition?) {
        id = m.id
        marker = m.marker.rawValue
        name = d?.name ?? m.marker.rawValue
        unit = d?.unit ?? ""
        day = CoachRound.dag(m.day)
        value = m.value
        note = m.note
    }

    /// Alla inskrivna mätningar i loggen, med markörens namn och enhet.
    public static func all(_ log: MeasurementLog) -> [CoachMeasurement] {
        log.measurements.map { (m: MarkerReading) -> CoachMeasurement in
            CoachMeasurement(m, definition: log.definition(m.marker))
        }
    }
}

/// BESLUT B127 · METOD M73
/// Profilen: kroppens mått, maxpulsen, vilopulsen och konditionen som Idunn visar dem.
public struct CoachProfile: Codable, Equatable, Sendable {
    public var birthYear: Int?
    public var sex: String?
    public var heightCm: Double?
    public var weightKg: Double?
    public var waistCm: Double?
    public var maxPulse: Double?
    /// Vilopulsen (medianen av de senaste nätterna, METOD M61).
    public var restingPulse: Double?
    /// Konditionen (VO2 max, ml/kg/min) med osäkerhet, och vad den vilar på: "matt" (steptest och pass) eller
    /// "skattad" (vila och profil).
    public var vo2max: Double?
    public var vo2maxUncertainty: Double?
    public var vo2maxBasis: String?

    public init(profile p: FitnessProfile, person: Person?, maxPulse: Double?, restingPulse: Double?,
                shown: FitnessSummary.Shown?) {
        birthYear = person?.birthYear ?? p.birthYear
        if let kön = person?.sex {
            sex = kön == .male ? "man" : "kvinna"
        } else {
            sex = p.sex?.rawValue
        }
        heightCm = CoachRound.r(p.heightCm, 1)
        weightKg = CoachRound.r(p.weightKg, 1)
        waistCm = CoachRound.r(p.waistCm, 1)
        self.maxPulse = CoachRound.r(maxPulse, 0)
        self.restingPulse = CoachRound.r(restingPulse, 1)
        vo2max = CoachRound.r(shown?.value, 1)
        vo2maxUncertainty = CoachRound.r(shown?.uncertainty, 1)
        if let s = shown {
            switch s.basis {
            case .measurements: vo2maxBasis = "matt"
            case .passive: vo2maxBasis = "skattad"
            }
        }
    }

    /// Profilen är tom när inget fält är satt: då skickas den inte.
    public var isEmpty: Bool {
        birthYear == nil && sex == nil && heightCm == nil && weightKg == nil && waistCm == nil && maxPulse == nil
            && restingPulse == nil && vo2max == nil
    }
}

/// BESLUT B127. Vad som skickade: bygget och dokumentens form. Formen höjs när ett fält byter betydelse.
public struct CoachStatus: Codable, Equatable, Sendable {
    public static let currentSchema: Int = 1

    public var build: String
    public var schema: Int

    public init(build: String) {
        self.build = build
        schema = CoachStatus.currentSchema
    }
}

/// BESLUT B127 · METOD M73
/// Ett dokuments innehåll, ett av slagen. Kodas som innehållet självt (utan omslag).
public enum CoachPayload: Equatable, Sendable, Encodable {
    case night(CoachNight)
    case pass(CoachPass)
    case measurement(CoachMeasurement)
    case profile(CoachProfile)
    case status(CoachStatus)

    public var kind: CoachKind {
        switch self {
        case .night: return .night
        case .pass: return .pass
        case .measurement: return .measurement
        case .profile: return .profile
        case .status: return .status
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .night(let v): try c.encode(v)
        case .pass(let v): try c.encode(v)
        case .measurement(let v): try c.encode(v)
        case .profile(let v): try c.encode(v)
        case .status(let v): try c.encode(v)
        }
    }
}

/// BESLUT B127 · METOD M73
/// Ett dokument på väg till coachen: slaget, nyckeln och innehållet. `data == nil` tar bort dokumentet där.
public struct CoachItem: Equatable, Sendable {
    public var kind: CoachKind
    public var key: String
    public var data: CoachPayload?

    public init(kind: CoachKind, key: String, data: CoachPayload?) {
        self.kind = kind
        self.key = key
        self.data = data
    }

    public init(_ n: CoachNight) { self.init(kind: .night, key: n.day, data: .night(n)) }
    public init(_ p: CoachPass) { self.init(kind: .pass, key: p.id, data: .pass(p)) }
    public init(_ m: CoachMeasurement) { self.init(kind: .measurement, key: m.id, data: .measurement(m)) }
    public init(_ p: CoachProfile) { self.init(kind: .profile, key: "profil", data: .profile(p)) }
    public init(_ s: CoachStatus) { self.init(kind: .status, key: "status", data: .status(s)) }

    /// Namnet i loggen över det skickade: slaget och nyckeln.
    public var name: String { kind.rawValue + "/" + key }
}

/// METOD M73. Kodningen: sorterade nycklar i snake_case, så att samma dokument alltid ger samma byte.
public enum CoachCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return e
    }

    /// Dokumentets innehåll som JSON; `nil` för en borttagning.
    public static func json(_ item: CoachItem) -> Data? {
        guard let d = item.data else { return nil }
        return try? encoder().encode(d)
    }
}
