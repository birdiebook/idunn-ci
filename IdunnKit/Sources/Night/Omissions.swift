import Foundation
import HeartRate

/// METOD M3 · BESLUT B17
/// Utelämnade slag: bandet kan hoppa över ett slag och skicka nästa intervall
/// som om det följde direkt. Värdena ser rimliga ut, så 20 %-regeln ser inget,
/// men skillnaden mellan intervallen runt luckan är inte en skillnad mellan
/// grannslag. Luckan syns bara i tiden: notiserna fortsätter komma, men
/// intervallen fyller inte tiden mellan dem.
///
/// Varje notis med slag säger två saker om hur långt slagens klocka (summan av
/// RR i avsnittet) ligger efter notisernas klocka, kallat förskjutningen:
/// notisens sista slag slog innan notisen skickades (övre gräns), och dess
/// första slag efter att förra notisen skickades (undre gräns, med toleransen
/// `latencyTolerance` för att radions fördröjning varierar mellan två notiser).
/// Så länge inget slag fattas är förskjutningen densamma; varje utelämnat slag
/// ökar den med slagets längd, som antas ligga inom 20 % av den lokala medianen.
///
/// Idunn söker den billigaste förklaringen av alla gränser: ett utelämnat slag
/// efter en notis utan RR kostar lite (det är där ett ensamt slag försvinner),
/// på andra ställen mer, och ett slag till på samma ställe ännu mer. Som mest
/// `beamWidth` förklaringar hålls öppna åt gången (strålsökning). Lika billiga
/// förklaringar som bara skiljer i var slaget fattas räknas alla: ingen
/// skillnad räknas över någon av platserna. Antalet utelämnade slag tas ur en
/// av dem.
enum Omissions {

    // MARK: Gränserna — METOD M3

    /// METOD M3. Så mycket får radions fördröjning skilja mellan två notiser.
    static let latencyTolerance: TimeInterval = 0.3
    /// METOD M3. Ett utelämnat slag antas ligga inom så här stor andel av den
    /// lokala medianen, samma gräns som 20 %-regeln.
    static let omittedDeviation: Double = RRCleaning.maxDeviation
    /// METOD M3. Medianen tas över så här många av de senaste giltiga slagen.
    static let medianBeats = 10
    /// METOD M3. Kostnaden för ett utelämnat slag direkt efter en notis utan
    /// RR, för ett på annat ställe, och för varje slag till på samma ställe.
    static let costAfterEmpty = 0.5
    static let costElsewhere = 1.5
    static let costExtraBeat = 2.0
    /// METOD M3. Som mest så många slag i rad på ett ställe; fler tas av omstarten.
    static let maxBeatsPerPlace = 3
    /// METOD M3. Så många förklaringar hålls öppna åt gången.
    static let beamWidth = 16
    /// METOD M3. Gamla gränser glöms så här fort (sekunder per sekund), så att
    /// en klocka som glider eller avrundningen till 1/1024 s inte samlas på hela natten.
    static let driftPerSecond = 1e-4
    /// METOD M3. Går ingen förklaring ihop startas sökningen om. Kräver gränserna
    /// då ett hopp på minst så här stor del av medianen räknas det som utelämnade
    /// slag; ett mindre hopp (en sen notis) bryter ingenting.
    static let restartFraction = 0.5

    /// Per slag i nattens ordning: hur många slag som fattas närmast före (den
    /// valda förklaringen), och om någon lika god förklaring lägger en lucka där.
    struct Result: Equatable {
        var omittedBefore: [Int]
        var gapBefore: [Bool]
    }

    /// METOD M3. Notiserna i tidsordning; avsnitten bryts som i `RRCleaning`
    /// (glapp över `RRCleaning.gapSeconds`), och slagen räknas i samma ordning.
    static func detect(_ ordered: [HeartRateSample]) -> Result {
        var result = Result(omittedBefore: [], gapBefore: [])
        var rows: [Row] = []
        var base: TimeInterval?
        var clock: Double = 0
        var previous: TimeInterval?
        var last: TimeInterval?
        var afterEmpty = false
        var recent: [Double] = []

        func finish() {
            solve(rows, into: &result)
            rows = []
            base = nil
            clock = 0
            previous = nil
            afterEmpty = false
            recent = []
        }

        for s in ordered {
            let absolute: TimeInterval = s.time.timeIntervalSince1970
            if let l = last, absolute - l > RRCleaning.gapSeconds { finish() }
            last = absolute
            // Tider räknas från avsnittets första notis, så att talen är små.
            if base == nil { base = absolute }
            let t: TimeInterval = absolute - (base ?? absolute)
            guard let firstRR = s.rrMilliseconds.first else {
                previous = t
                afterEmpty = true
                continue
            }
            let firstEnd: Double = clock + firstRR / 1000
            clock += s.rrMilliseconds.reduce(0, +) / 1000
            for r in s.rrMilliseconds where RRCleaning.plausibleRR.contains(r) { recent.append(r) }
            if recent.count > medianBeats { recent.removeFirst(recent.count - medianBeats) }
            let median: Double = (Statistics.median(recent) ?? 1000) / 1000
            let lower: Double = previous.map { (p: TimeInterval) -> Double in p - firstEnd - latencyTolerance } ?? -.infinity
            rows.append(Row(firstBeat: result.omittedBefore.count, time: t, lower: lower,
                            upper: t - clock, afterEmpty: afterEmpty, median: median))
            result.omittedBefore.append(contentsOf: [Int](repeating: 0, count: s.rrMilliseconds.count))
            result.gapBefore.append(contentsOf: [Bool](repeating: false, count: s.rrMilliseconds.count))
            previous = t
            afterEmpty = false
        }
        finish()
        return result
    }

    // MARK: Sökningen

    /// En notis med slag. Förskjutningen (notisernas klocka minus slagens) ska
    /// ligga över `lower` och högst på `upper`.
    struct Row {
        var firstBeat: Int
        var time: TimeInterval
        var lower: Double
        var upper: Double
        /// Förra notisen i avsnittet bar inget RR.
        var afterEmpty: Bool
        /// Lokala medianen i sekunder.
        var median: Double
    }

    /// En förklaring: vad den kostat, var förskjutningen kan ligga nu, och
    /// dess senaste nod (−1 = inga utelämnade slag än).
    struct Hypothesis {
        var cost: Double
        var lo: Double
        var hi: Double
        var node: Int
        var width: Double { hi - lo }
    }

    /// Ett ställe med utelämnade slag, eller en sammanslagning av två lika
    /// goda förklaringar (`row == -1`, `other` är den andra).
    struct Node {
        var parent: Int
        var other: Int
        var row: Int
        var beats: Int
    }

    static func solve(_ rows: [Row], into result: inout Result) {
        guard !rows.isEmpty else { return }
        var nodes: [Node] = []
        var hyps: [Hypothesis] = [Hypothesis(cost: 0, lo: -.infinity, hi: .infinity, node: -1)]

        for (i, r) in rows.enumerated() {
            let w: Double = i > 0 ? driftPerSecond * (r.time - rows[i - 1].time) : 0
            let maxK: Int = i > 0 ? maxBeatsPerPlace : 0
            var cand: [(h: Hypothesis, beats: Int, order: Int)] = []
            for h in hyps {
                let lo: Double = h.lo - w
                let hi: Double = h.hi + w
                for k in 0...maxK {
                    let kostnad: Double = k == 0 ? 0
                        : (r.afterEmpty ? costAfterEmpty : costElsewhere) + Double(k - 1) * costExtraBeat
                    let l: Double = max(lo + Double(k) * r.median * (1 - omittedDeviation), r.lower)
                    let u: Double = min(hi + Double(k) * r.median * (1 + omittedDeviation), r.upper)
                    if l < u {
                        let order: Int = cand.count
                        cand.append((h: Hypothesis(cost: h.cost + kostnad, lo: l, hi: u, node: h.node),
                                     beats: k, order: order))
                    }
                }
            }

            if cand.isEmpty {
                // Ingen förklaring går ihop: börja om från notisen. Ett stort hopp
                // uppåt är utelämnade slag; ett litet, eller ett nedåt (upprepade
                // slag, en sen notis), bryter ingenting.
                let best: Hypothesis = hyps.min(by: better) ?? hyps[0]
                var node: Int = best.node
                let jump: Double = r.lower - (best.hi + w)
                if jump >= restartFraction * r.median {
                    let k: Int = max(1, Int((jump / r.median).rounded()))
                    nodes.append(Node(parent: node, other: -1, row: i, beats: k))
                    node = nodes.count - 1
                }
                let giltig: Bool = r.lower < r.upper
                hyps = [Hypothesis(cost: best.cost, lo: giltig ? r.lower : -.infinity,
                                   hi: giltig ? r.upper : .infinity, node: node)]
                continue
            }

            cand.sort { (a: (h: Hypothesis, beats: Int, order: Int), b: (h: Hypothesis, beats: Int, order: Int)) -> Bool in
                if a.h.cost != b.h.cost { return a.h.cost < b.h.cost }
                if a.h.width != b.h.width { return a.h.width > b.h.width }
                return a.order < b.order
            }
            var next: [Hypothesis] = []
            for c in cand {
                var node: Int = c.h.node
                if c.beats > 0 {
                    nodes.append(Node(parent: node, other: -1, row: i, beats: c.beats))
                    node = nodes.count - 1
                }
                if let j = next.firstIndex(where: { (x: Hypothesis) -> Bool in same(x.lo, c.h.lo) && same(x.hi, c.h.hi) }) {
                    // Samma gränser: den billigare räcker. Lika billig med en
                    // annan väg hit: båda vägarnas luckor räknas.
                    if abs(next[j].cost - c.h.cost) < 1e-9 && next[j].node != node {
                        nodes.append(Node(parent: next[j].node, other: node, row: -1, beats: 0))
                        next[j].node = nodes.count - 1
                    }
                    continue
                }
                next.append(Hypothesis(cost: c.h.cost, lo: c.h.lo, hi: c.h.hi, node: node))
                if next.count >= beamWidth { break }
            }
            hyps = next
        }

        // Antalet ur den bästa förklaringen.
        guard let best = hyps.min(by: better) else { return }
        var n: Int = best.node
        while n >= 0 {
            let x: Node = nodes[n]
            if x.beats > 0 { result.omittedBefore[rows[x.row].firstBeat] += x.beats }
            n = x.parent
        }
        // Luckorna ur alla lika billiga.
        var seen = [Bool](repeating: false, count: nodes.count)
        var stack: [Int] = hyps.filter { (h: Hypothesis) -> Bool in abs(h.cost - best.cost) < 1e-9 }.map(\.node)
        while let m = stack.popLast() {
            guard m >= 0, !seen[m] else { continue }
            seen[m] = true
            let x: Node = nodes[m]
            if x.beats > 0 { result.gapBefore[rows[x.row].firstBeat] = true }
            stack.append(x.parent)
            if x.other >= 0 { stack.append(x.other) }
        }
    }

    /// Billigast först, vid lika den med bredast gränser.
    static func better(_ a: Hypothesis, _ b: Hypothesis) -> Bool {
        a.cost != b.cost ? a.cost < b.cost : a.width > b.width
    }

    static func same(_ a: Double, _ b: Double) -> Bool { a == b || abs(a - b) < 1e-9 }
}
