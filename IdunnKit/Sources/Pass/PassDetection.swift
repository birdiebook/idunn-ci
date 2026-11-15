import Foundation

/// BESLUT B120 · METOD M69
/// Pass som hittas av sig själva: perioder på dagen där pulsen ligger tydligt över vilan länge nog, ur bandets
/// historik minut för minut. Ett hittat pass är ett förslag; inget läggs till utan ett tryck.
public enum PassDetection {
    /// En minut ur bandets historik: Unix-minuten, pulsen (medianen över minutens sekunder med puls), rörelsen
    /// (medel av |Δg|, METOD M24) och hudtemperaturen i °C. Det som saknas är `nil`.
    public struct Minute: Equatable, Sendable {
        public var minute: Int
        public var pulse: Double?
        public var movement: Double?
        public var skinTemperature: Double?

        public init(minute: Int, pulse: Double?, movement: Double? = nil, skinTemperature: Double? = nil) {
            self.minute = minute
            self.pulse = pulse
            self.movement = movement
            self.skinTemperature = skinTemperature
        }
    }

    /// Trösklarna. Alla är antaganden tills verktyget är kört på riktiga dygn (METOD M69).
    public struct Rules: Equatable, Sendable {
        /// En minut är förhöjd när pulsen ligger minst så här högt i pulsreserven (måttlig ansträngning och uppåt).
        public var elevatedReserve = 0.40
        /// Från den här andelen av pulsreserven räknas minuten som hård.
        public var vigorousReserve = 0.60
        /// Ett pass har minst så här många förhöjda minuter,
        public var minElevatedMinutes = 10
        /// tål avbrott på högst så här många minuter i följd,
        public var maxGapMinutes = 2
        /// och minst den här andelen av minuterna från första till sista är förhöjda.
        public var minElevatedFraction = 0.8
        /// En minut är stilla när rörelsen ligger under det här (g, METOD M26).
        public var stillMovement = 0.02
        /// Passet räknas som stilla när minst den här andelen av minuterna med rörelse är stilla.
        public var stillFraction = 0.7
        /// Huden räknas som varm när passets högsta hudtemperatur ligger minst så här många grader över minuterna före.
        public var heatRise = 2.0
        /// Minuterna före passet som hudtemperaturen jämförs med.
        public var baselineMinutes = 15
        /// Hårt pass i rörelse: minst den här andelen av de förhöjda minuterna är hårda.
        public var vigorousFraction = 0.5

        public init() {}
    }

    /// Ett hittat pass: första och sista minuten (Unix-minuter, båda med), gissad typ (`nil` när den inte går att
    /// gissa), antalet förhöjda minuter och medelandelen av pulsreserven över dem.
    public struct Candidate: Equatable, Sendable {
        public var startMinute: Int
        public var endMinute: Int
        public var kind: PassKind?
        public var elevatedMinutes: Int
        public var meanReserve: Double

        public init(startMinute: Int, endMinute: Int, kind: PassKind?, elevatedMinutes: Int, meanReserve: Double) {
            self.startMinute = startMinute
            self.endMinute = endMinute
            self.kind = kind
            self.elevatedMinutes = elevatedMinutes
            self.meanReserve = meanReserve
        }

        public var start: Date { Date(timeIntervalSince1970: Double(startMinute * 60)) }
        /// Slutet av den sista minuten.
        public var end: Date { Date(timeIntervalSince1970: Double((endMinute + 1) * 60)) }
        public var minutes: Int { endMinute - startMinute + 1 }
    }

    /// METOD M69. Andelen av pulsreserven: (puls − vilopuls) / (maxpuls − vilopuls).
    public static func reserve(pulse: Double, restingPulse: Double, maxPulse: Double) -> Double? {
        guard maxPulse > restingPulse else { return nil }
        return (pulse - restingPulse) / (maxPulse - restingPulse)
    }

    /// METOD M69. Passen i minuterna. `excluded` är tider som inte ska ge förslag (natten, pass som redan finns),
    /// som slutna områden av Unix-minuter. Minuterna får komma i valfri ordning; en minut två gånger räknas en gång.
    public static func candidates(_ minutes: [Minute], restingPulse: Double, maxPulse: Double,
                                  excluded: [ClosedRange<Int>] = [], rules: Rules = Rules()) -> [Candidate] {
        guard maxPulse > restingPulse else { return [] }
        var perMinut: [Int: Minute] = [:]
        for m in minutes { perMinut[m.minute] = m }
        let ordnade = perMinut.values.sorted { $0.minute < $1.minute }

        // De förhöjda minuterna, utanför det uteslutna.
        var förhöjda: [(minute: Int, reserve: Double)] = []
        for m in ordnade {
            guard let puls = m.pulse, let r = reserve(pulse: puls, restingPulse: restingPulse, maxPulse: maxPulse),
                  r >= rules.elevatedReserve else { continue }
            if excluded.contains(where: { $0.contains(m.minute) }) { continue }
            förhöjda.append((m.minute, r))
        }

        // Följder av förhöjda minuter med högst `maxGapMinutes` minuter emellan.
        var följder: [[(minute: Int, reserve: Double)]] = []
        for f in förhöjda {
            if let sist = följder.last?.last, f.minute - sist.minute - 1 <= rules.maxGapMinutes {
                följder[följder.count - 1].append(f)
            } else {
                följder.append([f])
            }
        }

        var ut: [Candidate] = []
        for följd in följder {
            guard let första = följd.first?.minute, let sista = följd.last?.minute else { continue }
            let längd = sista - första + 1
            guard följd.count >= rules.minElevatedMinutes,
                  Double(följd.count) / Double(längd) >= rules.minElevatedFraction else { continue }
            let iPasset = ordnade.filter { $0.minute >= första && $0.minute <= sista }
            let före = ordnade.filter { $0.minute >= första - rules.baselineMinutes && $0.minute < första }
            guard case .pass(let typ) = verdict(inPass: iPasset, before: före, reserves: följd.map { $0.reserve },
                                                rules: rules) else { continue }
            let medel = följd.reduce(0) { $0 + $1.reserve } / Double(följd.count)
            ut.append(Candidate(startMinute: första, endMinute: sista, kind: typ, elevatedMinutes: följd.count,
                                meanReserve: medel))
        }
        return ut
    }

    /// Vad en förhöjd period är.
    enum Verdict: Equatable {
        /// Hög puls i stillhet utan varm hud (oro, kaffe, feber): inget förslag.
        case notAPass
        /// Ett pass, med typen när den går att gissa.
        case pass(PassKind?)
    }

    /// METOD M69. Stilla och varm hud är bastu; stilla utan värme är inget pass; i rörelse är det ett pass, och
    /// konditionspass när minst hälften av de förhöjda minuterna är hårda.
    static func verdict(inPass: [Minute], before: [Minute], reserves: [Double], rules: Rules) -> Verdict {
        let rörelser = inPass.compactMap { $0.movement }
        let varm = heat(inPass: inPass, before: before, rules: rules)
        if rörelser.isEmpty {
            // Ingen rörelse att läsa: ett pass, men typen går inte att gissa (utom bastu när huden säger det).
            return .pass(varm == true ? .bastu : nil)
        }
        let stillaAndel = Double(rörelser.filter { $0 < rules.stillMovement }.count) / Double(rörelser.count)
        if stillaAndel >= rules.stillFraction {
            return varm == true ? .pass(.bastu) : .notAPass
        }
        let hårda = reserves.filter { $0 >= rules.vigorousReserve }.count
        if Double(hårda) / Double(reserves.count) >= rules.vigorousFraction { return .pass(.kondition) }
        return .pass(nil)
    }

    /// Har huden blivit varm under passet? `nil` när temperaturen saknas i passet eller före det.
    static func heat(inPass: [Minute], before: [Minute], rules: Rules) -> Bool? {
        let iPasset = inPass.compactMap { $0.skinTemperature }
        let före = before.compactMap { $0.skinTemperature }.sorted()
        guard let högst = iPasset.max(), !före.isEmpty else { return nil }
        let n = före.count
        let median = n % 2 == 1 ? före[n / 2] : (före[n / 2 - 1] + före[n / 2]) / 2
        return högst - median >= rules.heatRise
    }
}
