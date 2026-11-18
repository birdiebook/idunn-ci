import Foundation

/// BESLUT B120 · BESLUT B142 · METOD M69
/// Pass som hittas av sig själva: perioder på dagen där pulsen ligger tydligt över vilan länge nog, ur bandets
/// historik minut för minut. Två vägar: ett måttligt pass (pulsen högt nog i minst tio minuter) och ett lätt pass i
/// rörelse (lägre puls, men längre och med handen i rörelse: golf, en lång promenad). Ett hittat pass är ett
/// förslag; inget läggs till utan ett tryck.
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
        /// BESLUT B142. Ett lätt pass i rörelse räknar minuter från den här andelen av pulsreserven (lätt
        /// ansträngning),
        public var lightReserve = 0.30
        /// har minst så här många sådana minuter (avbrotten och andelen som för ett måttligt pass),
        public var minLightMinutes = 20
        /// och rörelsens median över periodens minuter ligger minst så här högt (g, METOD M24).
        public var movingMovement = 0.2

        public init() {}
    }

    /// Ett hittat pass: första och sista minuten (Unix-minuter, båda med), gissad typ (`nil` när den inte går att
    /// gissa), antalet minuter över passets gräns (förhöjda, eller för ett lätt pass från `lightReserve`) och
    /// medelandelen av pulsreserven över dem.
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

    /// METOD M69 · BESLUT B142. Passen i minuterna. `excluded` är tider som inte ska ge förslag (natten, pass som
    /// redan finns), som slutna områden av Unix-minuter. Minuterna får komma i valfri ordning. Står samma minut två
    /// gånger räknas den en gång, och är raderna olika gäller den som står sist i listan. Ett lätt pass i rörelse
    /// tar över de måttliga pass det rör: hela golfrundan, inte backen i den.
    public static func candidates(_ minutes: [Minute], restingPulse: Double, maxPulse: Double,
                                  excluded: [ClosedRange<Int>] = [], rules: Rules = Rules()) -> [Candidate] {
        guard maxPulse > restingPulse else { return [] }
        var perMinut: [Int: Minute] = [:]
        for m in minutes { perMinut[m.minute] = m }
        let ordnade = perMinut.values.sorted { $0.minute < $1.minute }

        // Minuterna med puls och deras andel av reserven, utanför det uteslutna.
        var andelar: [(minute: Int, reserve: Double)] = []
        for m in ordnade {
            guard let puls = m.pulse,
                  let r = reserve(pulse: puls, restingPulse: restingPulse, maxPulse: maxPulse) else { continue }
            if excluded.contains(where: { $0.contains(m.minute) }) { continue }
            andelar.append((m.minute, r))
        }

        func underlag(_ följd: [(minute: Int, reserve: Double)]) -> (iPasset: [Minute], före: [Minute]) {
            let första = följd[0].minute, sista = följd[följd.count - 1].minute
            return (ordnade.filter { $0.minute >= första && $0.minute <= sista },
                    ordnade.filter { $0.minute >= första - rules.baselineMinutes && $0.minute < första })
        }

        func kandidat(_ följd: [(minute: Int, reserve: Double)], _ typ: PassKind?) -> Candidate {
            Candidate(startMinute: följd[0].minute, endMinute: följd[följd.count - 1].minute, kind: typ,
                      elevatedMinutes: följd.count,
                      meanReserve: följd.reduce(0) { $0 + $1.reserve } / Double(följd.count))
        }

        // Måttliga pass: följder av förhöjda minuter.
        var måttliga: [Candidate] = []
        for följd in sequences(andelar.filter { $0.reserve >= rules.elevatedReserve },
                               minCount: rules.minElevatedMinutes, rules: rules) {
            let u = underlag(följd)
            guard case .pass(let typ) = verdict(inPass: u.iPasset, before: u.före, reserves: följd.map { $0.reserve },
                                                rules: rules) else { continue }
            måttliga.append(kandidat(följd, typ))
        }

        // Lätta pass i rörelse (BESLUT B142): följder från den lägre gränsen, längre, och med handen i rörelse.
        // Typen gissas på de förhöjda minuterna i dem, som för ett måttligt pass.
        var lätta: [Candidate] = []
        for följd in sequences(andelar.filter { $0.reserve >= rules.lightReserve },
                               minCount: rules.minLightMinutes, rules: rules) {
            let u = underlag(följd)
            guard moving(u.iPasset, rules: rules) else { continue }
            let förhöjda = följd.map { $0.reserve }.filter { $0 >= rules.elevatedReserve }
            guard case .pass(let typ) = verdict(inPass: u.iPasset, before: u.före, reserves: förhöjda,
                                                rules: rules) else { continue }
            lätta.append(kandidat(följd, typ))
        }

        let kvar = måttliga.filter { (m: Candidate) -> Bool in
            !lätta.contains { $0.startMinute <= m.endMinute && m.startMinute <= $0.endMinute }
        }
        return (lätta + kvar).sorted { $0.startMinute < $1.startMinute }
    }

    /// METOD M69. Följder av minuterna med högst `maxGapMinutes` minuter emellan, som har minst `minCount` minuter
    /// och där minst `minElevatedFraction` av minuterna från den första till den sista är med.
    static func sequences(_ minuter: [(minute: Int, reserve: Double)], minCount: Int,
                          rules: Rules) -> [[(minute: Int, reserve: Double)]] {
        var följder: [[(minute: Int, reserve: Double)]] = []
        for f in minuter {
            if let sist = följder.last?.last, f.minute - sist.minute - 1 <= rules.maxGapMinutes {
                följder[följder.count - 1].append(f)
            } else {
                följder.append([f])
            }
        }
        return följder.filter { (följd: [(minute: Int, reserve: Double)]) -> Bool in
            guard let första = följd.first?.minute, let sista = följd.last?.minute else { return false }
            return följd.count >= minCount
                && Double(följd.count) / Double(sista - första + 1) >= rules.minElevatedFraction
        }
    }

    /// BESLUT B142. Är perioden i rörelse? Rörelsens median över minuterna med rörelse ligger på `movingMovement`
    /// eller mer. Utan rörelse att läsa går det inte att säga, och då är svaret nej.
    static func moving(_ inPass: [Minute], rules: Rules) -> Bool {
        let r = inPass.compactMap { $0.movement }.sorted()
        guard !r.isEmpty else { return false }
        let n = r.count
        let median = n % 2 == 1 ? r[n / 2] : (r[n / 2 - 1] + r[n / 2]) / 2
        return median >= rules.movingMovement
    }

    /// Vad en förhöjd period är.
    enum Verdict: Equatable {
        /// Hög puls i stillhet utan varm hud (oro, kaffe, feber): inget förslag.
        case notAPass
        /// Ett pass, med typen när den går att gissa.
        case pass(PassKind?)
    }

    /// METOD M69. Stilla och varm hud är bastu; stilla utan värme är inget pass; i rörelse är det ett pass, och
    /// konditionspass när minst hälften av de förhöjda minuterna är hårda och de är minst `minElevatedMinutes`
    /// (för ett lätt pass är `reserves` bara dess förhöjda minuter, och kan vara färre eller inga).
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
        if reserves.count >= rules.minElevatedMinutes,
           Double(hårda) / Double(reserves.count) >= rules.vigorousFraction { return .pass(.kondition) }
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
