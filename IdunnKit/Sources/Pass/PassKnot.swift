import Foundation

/// BESLUT B151 · METOD M69
/// Knuten K3: passupptäckten utan vilopuls och maxpuls. Perioden hittas ur pulsen mot dygnets egen nivå (medianen
/// över dygnets minuter med puls, räknad per kalenderdygn i lokal tid) och ihållande rörelse; kanten dras in till
/// första och sista följden av minst `edgeMinutes` minuter som är både förhöjda och i rörelse; typen (golf,
/// promenad, styrka eller ingen) sätts på det beskurna fönstret ur sekundernas rörelse och armens vinkel.
/// Konstanterna är låsta (mätta mot Whoops pass, METOD M69). `tools/pass_hitta.py` räknar samma sak i Python, och
/// `PassKnotTests` kräver samma svar ur ett påhittat dygn.
extension PassDetection {
    /// |Δg| i g för en sekund som rör sig (METOD M69, antagande ur ett delat dygn).
    public static let movingDelta = 0.05

    /// En sekund ur rörelsen: tiden (Unix-sekunder) och |Δg| mot sekunden precis före (`nil` när den saknas).
    public struct Step: Equatable, Sendable {
        public var time: Int
        public var delta: Double?

        public init(time: Int, delta: Double?) {
            self.time = time
            self.delta = delta
        }
    }

    /// Konstanterna i knuten K3. Alla är antaganden, inställda mot Whoops pass med korsvalidering (METOD M69).
    public struct Knot: Equatable, Sendable {
        /// En minut är förhöjd när pulsen är minst dygnets medianpuls plus så här många slag.
        public let over = 20.0
        /// En period kräver att andelen sekunder i rörelse (medianen över minuterna) når det här, och en minut är
        /// i rörelse (för kanten, och aktiv för typen) när den når det.
        public let movingShare = 0.5
        /// Följder av förhöjda minuter fogas när det är högst så här många minuter emellan.
        public let joinGap = 5
        /// En period är minst så här många minuter.
        public let minMinutes = 20
        /// En period behålls när Σ(puls − N − over) är minst så här mycket,
        public let dose = 600.0
        /// eller när armvinkelns median är högst så här många grader (gång). Samma gräns är en gångminut.
        public let walkAngle = 10.0
        /// Kanten: första och sista följden av minst så här många minuter som är både förhöjda och i rörelse.
        public let edgeMinutes = 3
        /// Typen läser kärnan: första och sista minuten med rörelse minst så här, om den är minst `coreMinutes`.
        public let coreShare = 0.3
        public let coreMinutes = 10
        /// Under så här många giltiga sekunder med |Δg| får fönstret ingen typ.
        public let minSeconds = 60
        /// Golf när p99 av |Δg| är minst så här (g); inom ±`golfMargin` av gränsen blir typen tom.
        public let golfLimit = 1.65
        public let golfMargin = 0.10
        /// En stilla följd är minst så här många sekunder med |Δg| under `PassDetection.movingDelta`.
        public let stillSeconds = 30
        /// Promenad eller styrka: medel och spridning för (aktiv armvinkel, andelen gångminuter, kvartilavståndet i
        /// vinkel), och de två typernas medelpunkter i de standardiserade talen.
        public let means: [Double] = [17.64, 0.37, 16.81]
        public let spreads: [Double] = [12.08, 0.33, 9.85]
        public let walkCentre: [Double] = [-0.65, 0.59, -0.61]
        public let strengthCentre: [Double] = [0.87, -0.79, 0.81]
        /// Typen blir tom när avståndet till den näst närmaste är mindre än så här mycket större (relativt).
        public let margin = 0.25
        /// Säger medelpunkten styrka men andelen stilla sekunder (i följder om minst `stillSeconds`) är under det
        /// här, blir det promenad.
        public let strengthStill = 0.044
        /// BESLUT B159. Bastun: förhöjda följder med högst så här många minuter emellan är ett pass (rundorna med
        /// svalkan emellan).
        public let saunaJoin = 20

        public init() {}
    }

    /// Ett hittat pass i knuten K3 före typen: första och sista minuten (båda med) och antalet förhöjda minuter.
    typealias KnotPeriod = (start: Int, end: Int, elevated: Int)

    /// BESLUT B151 · METOD M69. Passen ur minuterna och sekundernas rörelse med knuten K3. `excluded` är tider som inte
    /// ska ge förslag (pass som redan finns, borttagna förslag): ett förslag som rör ett sådant område visas inte.
    /// Minuterna får komma i valfri ordning; står samma minut två gånger gäller den som står sist.
    /// `timeZone` ger kalenderdygnen som dygnets medianpuls räknas över. Varken vilopuls eller maxpuls behövs.
    public static func knotCandidates(_ minutes: [Minute], steps: [Step], excluded: [ClosedRange<Int>] = [],
                                      timeZone: TimeZone = .current, knot: Knot = Knot()) -> [Candidate] {
        var perMinut: [Int: Minute] = [:]
        for m in minutes { perMinut[m.minute] = m }
        let sekunder: [Step] = steps.sorted { (a: Step, b: Step) -> Bool in a.time < b.time }
        let tider: [Int] = sekunder.map { (s: Step) -> Int in s.time }
        var ut: [Candidate] = []
        let knutens: [KnotPeriod] = knotPeriods(perMinut, timeZone: timeZone, knot: knot)
        // BESLUT B159. Bastun bredvid knutens perioder: knuten kräver rörelse, och i bastun sitter man still.
        let bastun: [KnotPeriod] = saunaPeriods(perMinut, timeZone: timeZone, knot: knot, besides: knutens)
        var alla: [(period: KnotPeriod, sauna: Bool)] = []
        for p in knutens { alla.append((p, false)) }
        for p in bastun { alla.append((p, true)) }
        alla.sort { (x: (period: KnotPeriod, sauna: Bool), y: (period: KnotPeriod, sauna: Bool)) -> Bool in
            x.period.start < y.period.start
        }
        for (p, bastu) in alla {
            let rörs: Bool = excluded.contains { (r: ClosedRange<Int>) -> Bool in
                r.lowerBound <= p.end && p.start <= r.upperBound
            }
            if rörs { continue }
            let typ: PassKind? = bastu
                ? PassKind.bastu
                : knotKind(perMinut, steps: sekunder, times: tider, start: p.start, end: p.end, knot: knot)
            ut.append(Candidate(startMinute: p.start, endMinute: p.end, kind: typ, elevatedMinutes: p.elevated,
                                meanReserve: 0))
        }
        return ut
    }

    /// BESLUT B159 · METOD M69. Bastun i knuten K3: förhöjda minuter mot dygnets egen nivå (N + `over`) i följder om
    /// minst `edgeMinutes` minuter, fogade till ett pass när det är högst `saunaJoin` minuter emellan. Passet behålls
    /// när det har minst `Rules.minElevatedMinutes` förhöjda minuter, inte rör någon av knutens perioder (`taken`),
    /// och huden blivit varm mot minuterna före (`heat`, samma regel som B120). Rörelsen krävs inte.
    /// `tools/pass_hitta.py` (`perioder_bastu`) räknar samma sak.
    static func saunaPeriods(_ perMinut: [Int: Minute], timeZone: TimeZone, knot: Knot,
                             besides taken: [KnotPeriod]) -> [KnotPeriod] {
        let regler = Rules()
        var grupper: [Int: [Minute]] = [:]
        for k in perMinut.keys.sorted() {
            if let m = perMinut[k] { grupper[dayKey(k, timeZone), default: []].append(m) }
        }
        var ut: [KnotPeriod] = []
        for nyckel in grupper.keys.sorted() {
            let dag: [Minute] = grupper[nyckel] ?? []
            let pulser: [Double] = dag.compactMap { (m: Minute) -> Double? in m.pulse }
            if pulser.isEmpty { continue }
            let gräns: Double = medianOf(pulser) + knot.over
            var lista: [(minute: Int, reserve: Double)] = []
            for m in dag {
                if let p = m.pulse, p >= gräns { lista.append((m.minute, 0)) }
            }
            var följder: [(Int, Int)] = []
            for f in sequences(lista, minCount: 1, rules: regler) {
                if let a = f.first?.minute, let b = f.last?.minute { följder.append((a, b)) }
            }
            följder = joinRuns(följder, gap: knot.joinGap).filter { (r: (Int, Int)) -> Bool in
                r.1 - r.0 + 1 >= knot.edgeMinutes
            }
            for (a, b) in joinRuns(följder, gap: knot.saunaJoin) {
                let rörs: Bool = taken.contains { (t: KnotPeriod) -> Bool in t.start <= b && a <= t.end }
                if rörs { continue }
                var iPasset: [Minute] = []
                for m in a...b {
                    if let x = perMinut[m] { iPasset.append(x) }
                }
                var före: [Minute] = []
                for m in (a - regler.baselineMinutes)..<a {
                    if let x = perMinut[m] { före.append(x) }
                }
                var förhöjda = 0
                for x in iPasset {
                    if let p = x.pulse, p >= gräns { förhöjda += 1 }
                }
                if förhöjda >= regler.minElevatedMinutes && heat(inPass: iPasset, before: före, rules: regler) == true {
                    ut.append((a, b, förhöjda))
                }
            }
        }
        return ut
    }

    /// Första index i den sorterade listan vars värde är minst `x`.
    static func lowerBound(_ a: [Int], _ x: Int) -> Int {
        var lo = 0
        var hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    static func medianOf(_ v: [Double]) -> Double {
        let s = v.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Som numpy.percentile (linjär interpolation).
    static func percentile(_ v: [Double], _ q: Double) -> Double {
        let s = v.sorted()
        let pos = Double(s.count - 1) * (q / 100.0)
        let lo = Int(pos)
        let hi = min(lo + 1, s.count - 1)
        let t = pos - Double(lo)
        let a = s[lo]
        let b = s[hi]
        return t >= 0.5 ? b - (b - a) * (1 - t) : a + (b - a) * t
    }

    /// Följder av minuter (första, sista) fogas när det är högst `gap` minuter emellan.
    static func joinRuns(_ f: [(Int, Int)], gap: Int) -> [(Int, Int)] {
        let sorterade: [(Int, Int)] = f.sorted { (a: (Int, Int), b: (Int, Int)) -> Bool in
            a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
        }
        var ut: [(Int, Int)] = []
        for r in sorterade {
            if let sist = ut.last, r.0 - sist.1 - 1 <= gap {
                ut[ut.count - 1].1 = max(sist.1, r.1)
            } else {
                ut.append(r)
            }
        }
        return ut
    }

    /// Kalenderdygnets nummer i lokal tid för en Unix-minut.
    static func dayKey(_ minute: Int, _ timeZone: TimeZone) -> Int {
        let tid: Int = minute * 60 + timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(minute * 60)))
        return tid >= 0 ? tid / 86400 : -((-tid + 86399) / 86400)
    }

    /// Perioderna med kanterna indragna, dygn för dygn, i tidsordning.
    static func knotPeriods(_ perMinut: [Int: Minute], timeZone: TimeZone, knot: Knot) -> [KnotPeriod] {
        var grupper: [Int: [Minute]] = [:]
        for k in perMinut.keys.sorted() {
            if let m = perMinut[k] { grupper[dayKey(k, timeZone), default: []].append(m) }
        }
        var ut: [KnotPeriod] = []
        for nyckel in grupper.keys.sorted() {
            let dag: [Minute] = grupper[nyckel] ?? []
            let pulser: [Double] = dag.compactMap { (m: Minute) -> Double? in m.pulse }
            if pulser.isEmpty { continue }
            let nivå: Double = medianOf(pulser)
            let gräns: Double = nivå + knot.over
            let mi: [Int] = dag.map { (m: Minute) -> Int in m.minute }
            let pu: [Double] = dag.map { (m: Minute) -> Double in m.pulse ?? -1 }
            let ih: [Double] = dag.map { (m: Minute) -> Double in m.movingShare ?? 0 }
            var vinklar: [Int: Double] = [:]
            for m in dag { if let v = m.armAngle { vinklar[m.minute] = v } }

            var lista: [(minute: Int, reserve: Double)] = []
            for i in 0..<dag.count where pu[i] >= gräns { lista.append((mi[i], 0)) }
            var följder: [(Int, Int)] = []
            for f in sequences(lista, minCount: 1, rules: Rules()) {
                if let a = f.first?.minute, let b = f.last?.minute { följder.append((a, b)) }
            }
            följder = joinRuns(följder, gap: knot.joinGap).filter { (r: (Int, Int)) -> Bool in
                r.1 - r.0 + 1 >= knot.minMinutes
            }

            var perioder: [(Int, Int)] = []
            for (a, b) in följder {
                let j0: Int = lowerBound(mi, a)
                let j1: Int = lowerBound(mi, b + 1)
                if j1 <= j0 || medianOf(Array(ih[j0..<j1])) < knot.movingShare { continue }
                var vm: [Double] = []
                for m in a...b { if let v = vinklar[m] { vm.append(v) } }
                let vinkelMedian: Double = vm.isEmpty ? 99 : medianOf(vm)
                var dos = 0.0
                for x in pu[j0..<j1] where x > 0 { dos += x - nivå - knot.over }
                if !(dos >= knot.dose || vinkelMedian <= knot.walkAngle) { continue }
                var första: Int?
                var sista: Int?
                for i in j0..<j1 where ih[i] >= knot.movingShare {
                    if första == nil { första = i }
                    sista = i
                }
                guard let f = första, let l = sista else { continue }
                if mi[l] - mi[f] + 1 >= knot.minMinutes { perioder.append((mi[f], mi[l])) }
            }

            for (a0, b0) in joinRuns(perioder, gap: 0) {
                var a = a0
                var b = b0
                var j0: Int = lowerBound(mi, a)
                var j1: Int = lowerBound(mi, b + 1)
                // Kanten: första och sista följden av minst `edgeMinutes` bra minuter i rad (index i minuterna).
                var startIndex: Int?
                var endIndex: Int?
                var i = j0
                while i < j1 {
                    if ih[i] >= knot.movingShare && pu[i] >= gräns {
                        var j = i
                        while j < j1 && ih[j] >= knot.movingShare && pu[j] >= gräns { j += 1 }
                        if j - i >= knot.edgeMinutes {
                            if startIndex == nil { startIndex = i }
                            endIndex = j - 1
                        }
                        i = j
                    } else {
                        i += 1
                    }
                }
                if let s = startIndex, let e = endIndex {      // annars behålls periodens kanter
                    a = mi[s]
                    b = mi[e]
                    j0 = lowerBound(mi, a)
                    j1 = lowerBound(mi, b + 1)
                }
                var förhöjda = 0
                for k in j0..<j1 where pu[k] >= gräns { förhöjda += 1 }
                ut.append((a, b, förhöjda))
            }
        }
        return ut
    }

    /// Typen på fönstret `start...end`: golf, promenad, styrka eller `nil` (METOD M69).
    static func knotKind(_ perMinut: [Int: Minute], steps: [Step], times: [Int], start: Int, end: Int,
                         knot: Knot) -> PassKind? {
        var a = start
        var b = end
        // Kärnan: första och sista minuten med rörelse, om den är minst `coreMinutes` minuter.
        var första: Int?
        var sista: Int?
        for m in a...b {
            if let x = perMinut[m], (x.movingShare ?? 0) >= knot.coreShare {
                if första == nil { första = m }
                sista = m
            }
        }
        if let f = första, let l = sista, l - f + 1 >= knot.coreMinutes {
            a = f
            b = l
        }
        let s0: Int = lowerBound(times, a * 60)
        let s1: Int = lowerBound(times, (b + 1) * 60)
        let fönster: ArraySlice<Step> = steps[s0..<s1]
        let giltiga: [Double] = fönster.compactMap { (s: Step) -> Double? in s.delta }
        if giltiga.count < knot.minSeconds { return nil }
        let p99: Double = percentile(giltiga, 99)
        var stilla = 0
        var följd = 0
        for s in fönster {
            if let d = s.delta, d < movingDelta {
                följd += 1
            } else {
                if följd >= knot.stillSeconds { stilla += följd }
                följd = 0
            }
        }
        if följd >= knot.stillSeconds { stilla += följd }
        let stilla30: Double = Double(stilla) / Double(fönster.count)
        if abs(p99 - knot.golfLimit) < knot.golfMargin * knot.golfLimit { return nil }
        if p99 >= knot.golfLimit { return .golf }

        var vinklar: [Double] = []
        var aktiva: [Double] = []
        for m in a...b {
            guard let x = perMinut[m], let v = x.armAngle else { continue }
            vinklar.append(v)
            if (x.movingShare ?? 0) >= knot.movingShare { aktiva.append(v) }
        }
        let aktivVinkel: Double = aktiva.isEmpty ? 60 : medianOf(aktiva)
        let gång: Double = aktiva.isEmpty
            ? 0 : Double(aktiva.filter { (v: Double) -> Bool in v <= knot.walkAngle }.count) / Double(aktiva.count)
        let iqr: Double = vinklar.count > 3 ? percentile(vinklar, 75) - percentile(vinklar, 25) : 0
        let drag: [Double] = [aktivVinkel, gång, iqr]
        var promenad = 0.0
        var styrka = 0.0
        for i in 0..<3 {
            let x: Double = (drag[i] - knot.means[i]) / knot.spreads[i]
            promenad += (x - knot.walkCentre[i]) * (x - knot.walkCentre[i])
            styrka += (x - knot.strengthCentre[i]) * (x - knot.strengthCentre[i])
        }
        let närmast: Double = min(promenad, styrka)
        let näst: Double = max(promenad, styrka)
        if (näst - närmast) / (näst + 1e-9) < knot.margin { return nil }
        if promenad <= styrka { return .promenad }
        return stilla30 < knot.strengthStill ? .promenad : .styrka
    }
}
