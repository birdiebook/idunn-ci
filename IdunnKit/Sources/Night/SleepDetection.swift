import Foundation
import WhoopFrames

/// METOD M26 · METOD M24 · BESLUT B29
/// Sömnperioden och de vakna stunderna ur rörelsen, i armens z-vinkel.
/// Bandet ger gravitationen per sekund (K18), inte rå acceleration, så metoden
/// är vinkelbaserad: HDCZA för perioden (van Hees m.fl. 2018, Sci Rep 8:12975)
/// och ihållande inaktivitet för de vakna stunderna (van Hees m.fl. 2015, PLoS
/// One 10(11):e0142533). Alla konstanter och avvikelser står i M26.
public enum SleepDetection {

    // MARK: Konstanter (METOD M26)

    /// Vinkeln medelvärdesbildas per 5 sekunder (2015 och 2018).
    public static let epochSeconds = 5
    /// **Antagande.** Minsta antal sekunder med K18 för att en 5-sekundersepok
    /// ska finnas. Källorna har rådata och alltid hela epoker.
    public static let minSecondsPerEpoch = 3
    /// 2015: "no change larger than 5°" mellan på varandra följande epoker.
    public static let postureChangeDegrees = 5.0
    /// 2015: inaktivitet "over at least 5 minutes".
    public static let inactivityBoutSeconds = 300
    /// 2018, steg 3–5: rullande median över 5 minuter.
    public static let rollingEpochs = 60
    /// **Antagande.** Minsta antal epoker med ett steg i rullande medianens
    /// fönster. Källan säger inget om saknade epoker.
    public static let minEpochsInRollingWindow = 30
    /// 2018, steg 6: den 10:e percentilen.
    public static let thresholdPercentile = 0.10
    /// 2018, steg 6: multiplicerad med 15.
    public static let thresholdFactor = 15.0
    /// 2018: tröskeln begränsad till 0,13–0,50, i originalet i polysomnografiprovet
    /// (där dygnet saknas); här alltid, eftersom bandet bara bärs på natten.
    public static let thresholdRange: ClosedRange<Double> = 0.13...0.50
    /// 2018, steg 7: block längre än 30 minuter behålls.
    public static let minBlockSeconds = 1800
    /// 2018, steg 8: glapp mellan block kortare än 60 minuter räknas till blocken.
    public static let maxMergeGapSeconds = 3600
    /// BESLUT B73 · **Antagande.** Ett grannblock läggs till det valda om glappet mellan dem är kortare än 120 minuter
    /// (en vaken stund mitt i natten delar då inte natten). GGIR har sammanslagningen som ratt (`spt_max_gap`);
    /// ingen läst källa ger 120.
    public static let neighbourMaxGapSeconds = 7200
    /// BESLUT B73 · **Antagande.** ... och grannblocket är minst 60 minuter långt (en kvällsslummer blir inte insomning).
    public static let neighbourMinBlockSeconds = 3600
    /// BESLUT B73. Ett glapp i K18 (poster som saknas) på minst 30 minuter, HDCZA:s kortaste block, vid blockets kant
    /// gör natten ofullständig där.
    public static let edgeGapSeconds = 1800
    /// BESLUT B73. ... när glappet slutar högst 5 minuter före blocket, eller börjar högst 5 minuter efter det.
    public static let edgeNearSeconds = 300
    /// **Antagande.** En minut räknas som sömn om fler än hälften av dess
    /// tolv epoker är sömn (för hudtemperaturen, M25).
    public static let minAsleepEpochsPerMinute = 7
    /// BESLUT B100 · **Antagande.** Uppvaknandet ur pulsen prövas på vakna stunder som börjar under periodens sista timme.
    public static let pulseWakeTailSeconds = 3600
    /// BESLUT B100 · **Antagande.** ... och som är minst en minut långa (en vändning flyttar inte uppvaknandet).
    public static let pulseWakeMinBoutSeconds = 60
    /// BESLUT B100 · **Antagande.** Pulsen efter stundens början jämförs med halvtimmen före den.
    public static let pulseWakeBeforeSeconds = 1800
    /// BESLUT B100 · **Antagande.** Medianen efter ska ligga minst 7 slag/min över medianen före.
    public static let pulseWakeRiseBpm = 7.0
    /// BESLUT B100 · **Antagande.** Minst 60 sekunder med puls i vardera delen.
    public static let pulseWakeMinSeconds = 60

    // MARK: Z-vinkeln

    /// METOD M26. Armens vinkel mot horisontalplanet i grader, −90…90:
    /// atan(z / √(x² + y²)). `nil` om gravitationen inte är ett ändligt tal.
    public static func zAngle(_ g: K18Record.Gravity) -> Double? {
        let r: Double = (g.x * g.x + g.y * g.y).squareRoot()
        let a: Double = atan2(g.z, r) * 180 / Double.pi
        return a.isFinite ? a : nil
    }

    /// METOD M26. Medelvinkeln per 5-sekundersepok: epok `i` är de sekunder
    /// vars Unix-tid delad med fem är `first + i`. Epoker med färre än
    /// `minSecondsPerEpoch` sekunder saknas (`nil`).
    static func epochAngles(_ records: [K18Record], first: Int, count n: Int) -> [Double?] {
        var sum = [Double](repeating: 0, count: n)
        var seconds = [Int](repeating: 0, count: n)
        for r in records {
            let e: Int = r.time / epochSeconds - first
            guard e >= 0, e < n, let a = zAngle(r.gravity) else { continue }
            sum[e] += a
            seconds[e] += 1
        }
        var out = [Double?](repeating: nil, count: n)
        for i in 0..<n where seconds[i] >= minSecondsPerEpoch {
            out[i] = sum[i] / Double(seconds[i])
        }
        return out
    }

    /// METOD M26. |ändringen| i vinkel mot föregående epok. Saknas någon av
    /// de två epokerna saknas steget: ingen ändring över ett glapp.
    static func angleSteps(_ angles: [Double?]) -> [Double?] {
        var out = [Double?](repeating: nil, count: angles.count)
        guard angles.count > 1 else { return out }
        for i in 1..<angles.count {
            if let a = angles[i], let b = angles[i - 1] { out[i] = abs(a - b) }
        }
        return out
    }

    /// METOD M26. Rullande median av stegen över `rollingEpochs` epoker
    /// (centrerad: epok i−30 … i+29). Saknas steg räknas de som finns, om de
    /// är minst `minEpochsInRollingWindow`; annars saknas värdet.
    static func rollingMedian(_ steps: [Double?]) -> [Double?] {
        let n: Int = steps.count
        let before: Int = rollingEpochs / 2
        var out = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            let lo: Int = max(0, i - before)
            let hi: Int = min(n, i - before + rollingEpochs)
            var window: [Double] = []
            window.reserveCapacity(rollingEpochs)
            for k in lo..<hi {
                if let s = steps[k] { window.append(s) }
            }
            if window.count >= minEpochsInRollingWindow { out[i] = Statistics.median(window) }
        }
        return out
    }

    /// METOD M26. Percentil med linjär interpolation mellan rangerna
    /// (h = (n−1)·p), som R:s förval. **Antagande:** 2018 anger ingen metod.
    static func percentile(_ values: [Double], _ p: Double) -> Double {
        let s: [Double] = values.sorted()
        guard s.count > 1 else { return s[0] }
        let h: Double = Double(s.count - 1) * p
        let lo: Int = Int(h.rounded(.down))
        let hi: Int = min(lo + 1, s.count - 1)
        return s[lo] + (h - Double(lo)) * (s[hi] - s[lo])
    }

    /// METOD M26. Tröskeln: 10:e percentilen gånger 15, hållen inom 0,13–0,50.
    static func threshold(percentile10 p: Double) -> Double {
        min(max(p * thresholdFactor, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// METOD M26. Följder av epoker där rullande medianen är under tröskeln
    /// och som varar längre än `minBlockSeconds`.
    static func blocks(_ medians: [Double?], threshold: Double) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        let n: Int = medians.count
        while i < n {
            guard let m = medians[i], m < threshold else {
                i += 1
                continue
            }
            var j: Int = i + 1
            while j < n, let mj = medians[j], mj < threshold { j += 1 }
            if (j - i) * epochSeconds > minBlockSeconds { out.append(i..<j) }
            i = j
        }
        return out
    }

    /// METOD M26. Block med ett glapp kortare än `maxMergeGapSeconds` emellan
    /// slås ihop till ett.
    static func merged(_ blocks: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for b in blocks {
            if let last = out.last, (b.lowerBound - last.upperBound) * epochSeconds < maxMergeGapSeconds {
                out[out.count - 1] = last.lowerBound..<b.upperBound
            } else {
                out.append(b)
            }
        }
        return out
    }

    /// METOD M26 · BESLUT B73. Det valda blocket och de grannblock (åt båda håll, upprepat) som ligger mindre än
    /// `neighbourMaxGapSeconds` ifrån och själva är minst `neighbourMinBlockSeconds` långa, som ett block.
    /// `blocks` är de sammanslagna blocken i tidsordning och `chosen` ett av dem.
    static func withNeighbours(_ blocks: [Range<Int>], chosen: Range<Int>) -> Range<Int> {
        guard var lo = blocks.firstIndex(of: chosen) else { return chosen }
        var hi: Int = lo
        func joins(gap: Int, _ neighbour: Range<Int>) -> Bool {
            gap * epochSeconds < neighbourMaxGapSeconds && neighbour.count * epochSeconds >= neighbourMinBlockSeconds
        }
        while lo > 0, joins(gap: blocks[lo].lowerBound - blocks[lo - 1].upperBound, blocks[lo - 1]) { lo -= 1 }
        while hi < blocks.count - 1, joins(gap: blocks[hi + 1].lowerBound - blocks[hi].upperBound, blocks[hi + 1]) {
            hi += 1
        }
        return blocks[lo].lowerBound..<blocks[hi].upperBound
    }

    /// Första index i `records` (sorterade på tid) vars tid är minst `t`.
    static func firstIndex(_ records: [K18Record], atOrAfter t: Int) -> Int {
        var lo = 0
        var hi: Int = records.count
        while lo < hi {
            let mid: Int = (lo + hi) / 2
            if records[mid].time < t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// METOD M26 · BESLUT B73. Om natten är ofullständig i början och i slutet: början när ett glapp i K18 på minst
    /// `edgeGapSeconds` slutar högst `edgeNearSeconds` före blocket (`windowStart`), slutet när ett sådant börjar
    /// högst `edgeNearSeconds` efter det (`windowEnd`). Glappet är poster som saknas (inte puls 0), räknat på
    /// sekunderna i dygnsfönstret `from`…`to`; fönstrets kant räknas som glappets början eller slut när ingen post
    /// finns före eller efter. Då ligger insomningen eller uppvaknandet där datan börjar eller slutar.
    /// BESLUT B125. Slutglappet mäts till det tidigaste av fönstrets slut och `now` (sekunder, `nil` = fönstrets
    /// slut): en natt som räknas strax efter sista posten har inget glapp, datan har inte hunnit längre än så.
    static func incomplete(_ records: [K18Record], from: Int, to: Int,
                           windowStart: Int, windowEnd: Int, now: Int? = nil) -> (start: Bool, end: Bool) {
        let lo: Int = firstIndex(records, atOrAfter: from)
        let hi: Int = firstIndex(records, atOrAfter: to)
        guard lo < hi else { return (false, false) }
        var start = false
        let i: Int = max(lo, firstIndex(records, atOrAfter: windowStart - edgeNearSeconds))
        if i < hi {
            let before: Int = i > lo ? records[i - 1].time : from
            start = records[i].time - before >= edgeGapSeconds
        }
        var end = false
        let j: Int = min(hi, firstIndex(records, atOrAfter: windowEnd + edgeNearSeconds + 1)) - 1
        if j >= lo {
            let measuredTo: Int = min(to, now ?? to)
            let next: Int = j + 1 < hi ? records[j + 1].time : measuredTo
            end = next - records[j].time >= edgeGapSeconds
        }
        return (start, end)
    }

    /// METOD M26 · BESLUT B100. Uppvaknandet ur pulsen: början av den första vakna stunden i `p` som börjar under
    /// periodens sista `pulseWakeTailSeconds`, är minst `pulseWakeMinBoutSeconds` lång, och där medianen av bandets
    /// puls (poster med puls över 0) från stundens början till periodens slut ligger minst `pulseWakeRiseBpm` över
    /// medianen den halvtimme som går före. `nil` när ingen stund uppfyller det. Den som ligger vaken och stilla i
    /// sängen gör ett inaktivitetspass som 5°-regeln kallar sömn; pulsen sjunker inte tillbaka till sömnens nivå.
    static func pulseWake(_ records: [K18Record], _ p: SleepPeriod) -> Int? {
        func pulses(from: Int, to: Int) -> [Double] {
            var out: [Double] = []
            var i: Int = firstIndex(records, atOrAfter: from)
            while i < records.count, records[i].time < to {
                if records[i].pulse > 0 { out.append(Double(records[i].pulse)) }
                i += 1
            }
            return out
        }
        for b in p.wakeBouts where b.start >= p.wake - pulseWakeTailSeconds && b.seconds >= pulseWakeMinBoutSeconds {
            let after: [Double] = pulses(from: b.start, to: p.wake)
            let before: [Double] = pulses(from: b.start - pulseWakeBeforeSeconds, to: b.start)
            guard after.count >= pulseWakeMinSeconds, before.count >= pulseWakeMinSeconds,
                  let a = Statistics.median(after), let f = Statistics.median(before) else { continue }
            if a - f >= pulseWakeRiseBpm { return b.start }
        }
        return nil
    }

    /// METOD M26. Det längsta blocket; vid lika långa det tidigaste.
    static func longest(_ blocks: [Range<Int>]) -> Range<Int>? {
        var best: Range<Int>?
        for b in blocks {
            if let cur = best, b.count <= cur.count { continue }
            best = b
        }
        return best
    }

    /// METOD M26. Epoker som ligger i ett ihållande inaktivitetspass: en följd
    /// av epoker utan ändring över `postureChangeDegrees` som varar minst
    /// `inactivityBoutSeconds`. En ändring över gränsen startar ett nytt pass
    /// på epoken där den skedde; en saknad epok avbryter.
    static func inactivity(_ angles: [Double?], _ steps: [Double?]) -> [Bool] {
        let n: Int = angles.count
        var inBout = [Bool](repeating: false, count: n)
        var i = 0
        while i < n {
            guard angles[i] != nil else {
                i += 1
                continue
            }
            var j: Int = i + 1
            while j < n, angles[j] != nil, let s = steps[j], s <= postureChangeDegrees { j += 1 }
            if (j - i) * epochSeconds >= inactivityBoutSeconds {
                for k in i..<j { inBout[k] = true }
            }
            i = j
        }
        return inBout
    }

    // MARK: Perioden

    /// METOD M26. Dygnsfönstret kl 12–12 som HDCZA räknar i: från klockan
    /// tolv dagen före uppvakningsdagen till klockan tolv på den, i zonernas
    /// egen väggklocka (zonen kan ha bytt, sommartid). Fönstret är därför 23
    /// eller 25 timmar vid ett zonbyte.
    public static func dayWindow(wakeDay: WakeDay, startOffsetSeconds: Int,
                                 endOffsetSeconds: Int) -> (from: Date, to: Date) {
        let from: Int = (wakeDay.daysSince1970 - 1) * 86_400 + 43_200 - startOffsetSeconds
        let to: Int = wakeDay.daysSince1970 * 86_400 + 43_200 - endOffsetSeconds
        return (Date(timeIntervalSince1970: Double(from)), Date(timeIntervalSince1970: Double(to)))
    }

    /// METOD M26. Fönstrets femsekundsepoker: vinkel, steg och inaktivitetspass. `first` är första hela epoken i
    /// fönstret (epokens nummer från 1970); index `k` är epok `first + k`.
    struct Scan {
        let first: Int
        let angles: [Double?]
        let steps: [Double?]
        let inBout: [Bool]
    }

    /// METOD M26. Vinklarna, stegen och passen över fönstrets hela epoker; `nil` när fönstret saknar en hel epok.
    static func scan(_ series: K18Series, from: Date, to: Date) -> Scan? {
        let first: Int = Int((from.timeIntervalSince1970 / Double(epochSeconds)).rounded(.up))
        let last: Int = Int((to.timeIntervalSince1970 / Double(epochSeconds)).rounded(.down))
        let n: Int = last - first
        guard n > 0 else { return nil }
        let angles: [Double?] = epochAngles(series.records, first: first, count: n)
        let steps: [Double?] = angleSteps(angles)
        return Scan(first: first, angles: angles, steps: steps, inBout: inactivity(angles, steps))
    }

    /// METOD M26. Sömnperioden i ett dygnsfönster `from`…`to`, eller `nil`
    /// när fönstret inte har något block längre än 30 minuter, eller inget
    /// inaktivitetspass inom blocket (en dag utan sömn). Bara hela epoker
    /// inom fönstret räknas.
    ///
    /// BESLUT B125. `now` (klockan, förd in som värde) begränsar var slutglappet mäts: till det tidigaste av `to`
    /// och `now`. `nil` = `to`, som förut.
    public static func detect(_ series: K18Series, from: Date, to: Date, now: Date? = nil) -> SleepPeriod? {
        guard let s = scan(series, from: from, to: to) else { return nil }
        let medians: [Double?] = rollingMedian(s.steps)
        let present: [Double] = medians.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        let limit: Double = threshold(percentile10: percentile(present, thresholdPercentile))
        let joined: [Range<Int>] = merged(blocks(medians, threshold: limit))
        guard let chosen = longest(joined) else { return nil }
        // BESLUT B73: grannblocken läggs till det längsta.
        let window: Range<Int> = withNeighbours(joined, chosen: chosen)

        // Perioden räknas från första till sista inaktivitetspasset i
        // blocket (2015: insomning = början av första passet, uppvaknande =
        // slutet av sista). Blocket självt behålls som `windowStart/End`.
        var firstBout: Int?
        var lastBout: Int?
        for k in window where s.inBout[k] {
            if firstBout == nil { firstBout = k }
            lastBout = k
        }
        guard let startEpoch = firstBout, let lastEpoch = lastBout else { return nil }
        var p: SleepPeriod = period(s, startEpoch..<(lastEpoch + 1), window: window, threshold: limit)
        // BESLUT B100: en vaken stund i slutet med pulsen kvar uppe är uppvaknandet, även om armen sedan låg stilla.
        if let w = pulseWake(series.records, p) {
            let end: Int = w / epochSeconds - s.first
            if end > startEpoch { p = period(s, startEpoch..<end, window: window, threshold: limit) }
        }
        let edge = incomplete(series.records, from: Int(from.timeIntervalSince1970.rounded(.up)),
                              to: Int(to.timeIntervalSince1970.rounded(.down)),
                              windowStart: p.windowStart, windowEnd: p.windowEnd,
                              now: now.map { (d: Date) -> Int in Int(d.timeIntervalSince1970.rounded(.down)) })
        p.incompleteStart = edge.start
        p.incompleteEnd = edge.end
        return p
    }

    /// METOD M55 · BESLUT B70. Sömnperioden när insomning och uppvaknande är givna (användaren ändring av natten):
    /// perioden är `onset`…`wake` i stället för den hittade, och vinklarna, stegen och passen räknas över hela
    /// dygnsfönstret som i `detect`, så att sömn, vaken och glapp inom perioden blir desamma som för en hittad period
    /// med samma gränser. Gränserna avrundas inåt till hela femsekundsepoker. `nil` när perioden inte ligger inom
    /// fönstret, saknar en hel epok eller inte har en enda epok med K18. Tröskeln är 0: ingen tröskel valde perioden,
    /// och blocket (`windowStart/End`) är perioden själv. Perioden märks aldrig som ofullständig (BESLUT B73):
    /// klockslagen är användaren egna, inte där datan började.
    public static func given(_ series: K18Series, from: Date, to: Date, onset: Int, wake: Int) -> SleepPeriod? {
        guard let s = scan(series, from: from, to: to) else { return nil }
        let a: Int = Int((Double(onset) / Double(epochSeconds)).rounded(.up)) - s.first
        let b: Int = Int((Double(wake) / Double(epochSeconds)).rounded(.down)) - s.first
        guard a >= 0, b <= s.angles.count, a < b else { return nil }
        let range: Range<Int> = a..<b
        guard range.contains(where: { (k: Int) -> Bool in s.angles[k] != nil }) else { return nil }
        return period(s, range, window: range, threshold: 0)
    }

    /// METOD M26. Perioden `range` (epokindex i `s`): varje epok är sömn (i ett pass), vaken (med K18 utanför
    /// passen) eller glapp (utan K18), med de vakna stunderna, glappen och sömnminuterna.
    static func period(_ s: Scan, _ range: Range<Int>, window: Range<Int>, threshold limit: Double) -> SleepPeriod {
        let first: Int = s.first
        let angles: [Double?] = s.angles
        let inBout: [Bool] = s.inBout
        // Varje epok i perioden är sömn, vaken eller glapp (METOD M26).
        var asleep = 0
        var awake = 0
        var gap = 0
        var perMinute: [Int: Int] = [:]
        for k in range {
            if angles[k] == nil {
                gap += 1
            } else if inBout[k] {
                asleep += 1
                perMinute[(first + k) / 12, default: 0] += 1
            } else {
                awake += 1
            }
        }
        func intervals(_ test: (Int) -> Bool) -> [SleepInterval] {
            var out: [SleepInterval] = []
            var k: Int = range.lowerBound
            while k < range.upperBound {
                guard test(k) else {
                    k += 1
                    continue
                }
                var j: Int = k + 1
                while j < range.upperBound, test(j) { j += 1 }
                out.append(SleepInterval(start: (first + k) * epochSeconds, end: (first + j) * epochSeconds))
                k = j
            }
            return out
        }
        let wakeBouts: [SleepInterval] = intervals { (k: Int) -> Bool in angles[k] != nil && !inBout[k] }
        let gaps: [SleepInterval] = intervals { (k: Int) -> Bool in angles[k] == nil }
        let asleepMinutes: [Int] = perMinute.filter { $0.value >= minAsleepEpochsPerMinute }.keys.sorted()

        return SleepPeriod(onset: (first + range.lowerBound) * epochSeconds,
                           wake: (first + range.upperBound) * epochSeconds,
                           windowStart: (first + window.lowerBound) * epochSeconds,
                           windowEnd: (first + window.upperBound) * epochSeconds,
                           wakeBouts: wakeBouts, gaps: gaps,
                           asleepSeconds: asleep * epochSeconds,
                           awakeSeconds: awake * epochSeconds,
                           gapSeconds: gap * epochSeconds,
                           threshold: limit,
                           asleepMinutes: asleepMinutes)
    }
}

/// METOD M26. Ett tidsintervall i Unix-sekunder, början med och slutet utan.
public struct SleepInterval: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var seconds: Int { end - start }
    public var startDate: Date { Date(timeIntervalSince1970: Double(start)) }
    public var endDate: Date { Date(timeIntervalSince1970: Double(end)) }
}

/// METOD M26. Natten som sömnperiod: från början av första till slutet av
/// sista inaktivitetspasset i nattens block, med de vakna stunderna och
/// glappen i K18 inom den.
///
/// **Regeln för glapp:** en epok utan K18 är varken sömn eller vaken. Perioden
/// är därför summan av tre: `asleepSeconds + awakeSeconds + gapSeconds`.
/// Sömntiden är bara det som mättes som sömn; ett glapp räknas aldrig dit.
public struct SleepPeriod: Equatable, Sendable {
    /// Insomning och uppvaknande, Unix-sekunder (5-sekundersepokernas gränser).
    public var onset: Int
    public var wake: Int
    /// HDCZA:s block som perioden valdes inom (2018:s SPT-fönster).
    public var windowStart: Int
    public var windowEnd: Int
    /// Vakna stunder inom perioden: epoker med K18 som inte ligger i något
    /// inaktivitetspass. Tidsordning.
    public var wakeBouts: [SleepInterval]
    /// Glapp i K18 inom perioden. Tidsordning.
    public var gaps: [SleepInterval]
    public var asleepSeconds: Int
    public var awakeSeconds: Int
    public var gapSeconds: Int
    /// Tröskeln (grader) som blocket hittades med.
    public var threshold: Double
    /// Unix-minuter som räknas som sömn (för hudtemperaturen, M25).
    public var asleepMinutes: [Int]
    /// BESLUT B73. K18 saknas vid blockets början (ett glapp på minst 30 min som slutar högst 5 min före det): då är
    /// insomningen där datan börjar, inte där sömnen gjorde det, och sömntiden är för kort.
    public var incompleteStart: Bool = false
    /// BESLUT B73. K18 saknas vid blockets slut: uppvaknandet är där datan slutar.
    public var incompleteEnd: Bool = false

    public var onsetDate: Date { Date(timeIntervalSince1970: Double(onset)) }
    public var wakeDate: Date { Date(timeIntervalSince1970: Double(wake)) }
    public var periodSeconds: Int { wake - onset }
    /// Sömntiden i minuter: perioden utan vakna stunder och glapp.
    public var asleepMinutesTotal: Double { Double(asleepSeconds) / 60 }

    /// Andelen av perioden som har K18 (0…1).
    public var coverage: Double {
        periodSeconds > 0 ? Double(asleepSeconds + awakeSeconds) / Double(periodSeconds) : 0
    }

    /// METOD M50 · BESLUT B63. Sömneffektiviteten i procent som appen visar: sömntiden delad med hela sömnperioden
    /// (insomning till uppvaknande, glapp i K18 inräknade som icke-sömn), högst 100. `nil` för en period utan längd.
    public var periodEfficiency: Double? {
        periodSeconds > 0 ? min(100, 100 * Double(asleepSeconds) / Double(periodSeconds)) : nil
    }

    /// Sömntid delat med tid med K18 i perioden: sömneffektiviteten (2018:
    /// "percentage of time asleep within the SPT-window"), utan glapp.
    public var efficiency: Double? {
        let measured: Int = asleepSeconds + awakeSeconds
        return measured > 0 ? Double(asleepSeconds) / Double(measured) : nil
    }
}

extension SkinTemperature {
    /// METOD M25 · METOD M26. Nattens hudtemperatur: över sömnperiodens
    /// sömnminuter när perioden finns, annars (fallback) över inspelningens
    /// stilla minuter `recordingFrom`…`recordingTo` som före R4.
    public static func night(_ series: K18Series, sleep: SleepPeriod?,
                             recordingFrom: Date, recordingTo: Date) -> Night {
        guard let sleep else {
            return night(series, from: recordingFrom, to: recordingTo)
        }
        return night(series, asleepMinutes: sleep.asleepMinutes,
                     from: sleep.onsetDate, to: sleep.wakeDate)
    }
}
