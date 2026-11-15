// GENERERAD av tools/tests/somn_fixtur.py --skriv — redigera inte för hand.
// PÅHITTADE nätter (METOD M26, METOD M31) och facit ur tools/somn_regler.py,
// Python-spegeln av SleepDetection. Frön och faser är DemoSleeps; inget kommer
// från ett riktigt band.

import DemoData

enum SomnSpegelFixtur {
    enum Kalla: Sendable {
        case faser([DemoSleep.Phase], seed: UInt64)
        case trolig(seed: UInt64)
    }

    /// Uppvakningstid och zonernas förskjutning (sekunder öster om Greenwich); då
    /// är fönstret `SleepDetection.dayWindow` och inte `from`/`to` rakt av.
    struct Zon: Sendable {
        let wakeTime: Int
        let startOffset: Int
        let endOffset: Int
    }

    struct Facit: Sendable {
        let onset: Int
        let wake: Int
        let windowStart: Int
        let windowEnd: Int
        /// Antal 5-sekundersepoker.
        let sleepEpochs: Int
        let wakeEpochs: Int
        let gapEpochs: Int
        let threshold: Double
        /// [start, slut] i Unix-sekunder.
        let wakeBouts: [[Int]]
        let gaps: [[Int]]
        /// [första, sista] Unix-minut, bägge med.
        let minuteRuns: [[Int]]
        /// BESLUT B73: K18 saknas vid blockets början eller slut.
        let incompleteStart: Bool
        let incompleteEnd: Bool
    }

    struct Natt: Sendable {
        let name: String
        let start: Int
        let kalla: Kalla
        let from: Int
        let to: Int
        let zon: Zon?
        /// `nil`: ingen period.
        let facit: Facit?
    }

    static let nätter: [Natt] = [
        Natt(
            name: "stilla natt", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 10800), .turn, .still(seconds: 7200), .turn, .still(seconds: 7200), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760029440, zon: nil,
            facit: Facit(onset: 1760001850, wake: 1760027040, windowStart: 1760001850, windowEnd: 1760027045, sleepEpochs: 5038, wakeEpochs: 0, gapEpochs: 0, threshold: 0.27220252017206903, wakeBouts: [], gaps: [], minuteRuns: [[29333364, 29333783]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "orolig natt", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 7200), .restless(seconds: 1200, every: 100), .still(seconds: 7200), .restless(seconds: 900, every: 100), .still(seconds: 7200), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760027940, zon: nil,
            facit: Facit(onset: 1760001850, wake: 1760025540, windowStart: 1760001850, windowEnd: 1760025540, sleepEpochs: 4358, wakeEpochs: 380, gapEpochs: 0, threshold: 0.26114633270481136, wakeBouts: [[1760009040, 1760010140], [1760017440, 1760018240]], gaps: [], minuteRuns: [[29333364, 29333483], [29333502, 29333623], [29333637, 29333758]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "glapp 40 min", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 10800), .gap(seconds: 2400), .still(seconds: 10800), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760028240, zon: nil,
            facit: Facit(onset: 1760001850, wake: 1760025840, windowStart: 1760001850, windowEnd: 1760025840, sleepEpochs: 4318, wakeEpochs: 0, gapEpochs: 480, threshold: 0.26968542536678797, wakeBouts: [], gaps: [[1760012640, 1760015040]], minuteRuns: [[29333364, 29333543], [29333584, 29333763]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "glapp 90 min", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 7200), .gap(seconds: 5400), .still(seconds: 14400), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760031240, zon: nil,
            facit: Facit(onset: 1760001850, wake: 1760028840, windowStart: 1760001850, windowEnd: 1760028840, sleepEpochs: 4318, wakeEpochs: 0, gapEpochs: 1080, threshold: 0.26909235241150853, wakeBouts: [], gaps: [[1760009040, 1760014440]], minuteRuns: [[29333364, 29333483], [29333574, 29333813]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "korta glapp", start: 1760000040,
            kalla: .faser([.active(seconds: 1200), .still(seconds: 6000), .gap(seconds: 12), .still(seconds: 6000), .gap(seconds: 13), .still(seconds: 6000), .restless(seconds: 600, every: 90), .still(seconds: 3600), .active(seconds: 1200)], seed: 3),
            from: 1759999440, to: 1760025265, zon: nil,
            facit: Facit(onset: 1760001250, wake: 1760023465, windowStart: 1760001250, windowEnd: 1760023465, sleepEpochs: 4330, wakeEpochs: 108, gapEpochs: 5, threshold: 0.25732281236969357, wakeBouts: [[1760019265, 1760019805]], gaps: [[1760007240, 1760007250], [1760013250, 1760013265]], minuteRuns: [[29333354, 29333653], [29333663, 29333723]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "dag utan sömn", start: 1760000040,
            kalla: .faser([.active(seconds: 50400)], seed: 7),
            from: 1759999440, to: 1760051040, zon: nil,
            facit: nil),
        Natt(
            name: "glapp 150 min", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 7200), .gap(seconds: 9000), .still(seconds: 14400), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760034840, zon: nil,
            facit: Facit(onset: 1760018045, wake: 1760032440, windowStart: 1760018045, windowEnd: 1760032440, sleepEpochs: 2879, wakeEpochs: 0, gapEpochs: 0, threshold: 0.26909235241150853, wakeBouts: [], gaps: [], minuteRuns: [[29333634, 29333873]], incompleteStart: true, incompleteEnd: false)),
        Natt(
            name: "vaken stund 99 min", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 13500), .active(seconds: 5940), .still(seconds: 17400), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760041080, zon: nil,
            facit: Facit(onset: 1760001850, wake: 1760038680, windowStart: 1760001850, windowEnd: 1760038685, sleepEpochs: 6179, wakeEpochs: 1187, gapEpochs: 0, threshold: 0.2717665614857978, wakeBouts: [[1760015340, 1760021275]], gaps: [], minuteRuns: [[29333364, 29333588], [29333688, 29333977]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "kvällsslummer 40 min", start: 1760000040,
            kalla: .faser([.active(seconds: 3600), .still(seconds: 2400), .active(seconds: 6000), .still(seconds: 25200), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760039640, zon: nil,
            facit: Facit(onset: 1760012045, wake: 1760037240, windowStart: 1760012045, windowEnd: 1760037245, sleepEpochs: 5039, wakeEpochs: 0, gapEpochs: 0, threshold: 0.27038432389009603, wakeBouts: [], gaps: [], minuteRuns: [[29333534, 29333953]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "kvällsslummer 70 min", start: 1760000040,
            kalla: .faser([.active(seconds: 3600), .still(seconds: 4200), .active(seconds: 6000), .still(seconds: 25200), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760041440, zon: nil,
            facit: Facit(onset: 1760003650, wake: 1760039040, windowStart: 1760003650, windowEnd: 1760039040, sleepEpochs: 5878, wakeEpochs: 1200, gapEpochs: 0, threshold: 0.27090555515833614, wakeBouts: [[1760007840, 1760013840]], gaps: [], minuteRuns: [[29333394, 29333463], [29333564, 29333983]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "början saknas", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .gap(seconds: 5400), .still(seconds: 24000), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760033640, zon: nil,
            facit: Facit(onset: 1760007245, wake: 1760031240, windowStart: 1760007245, windowEnd: 1760031245, sleepEpochs: 4799, wakeEpochs: 0, gapEpochs: 0, threshold: 0.26757931962839265, wakeBouts: [], gaps: [], minuteRuns: [[29333454, 29333853]], incompleteStart: true, incompleteEnd: false)),
        Natt(
            name: "slutet saknas", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 24000), .gap(seconds: 3600), .active(seconds: 1200)], seed: 7),
            from: 1759999440, to: 1760031240, zon: nil,
            facit: Facit(onset: 1760001850, wake: 1760025840, windowStart: 1760001850, windowEnd: 1760025845, sleepEpochs: 4798, wakeEpochs: 0, gapEpochs: 0, threshold: 0.2673641745718971, wakeBouts: [], gaps: [], minuteRuns: [[29333364, 29333763]], incompleteStart: false, incompleteEnd: true)),
        Natt(
            name: "kort glapp före", start: 1760000040,
            kalla: .faser([.active(seconds: 1800), .gap(seconds: 600), .still(seconds: 24000), .active(seconds: 1800)], seed: 7),
            from: 1759999440, to: 1760028840, zon: nil,
            facit: Facit(onset: 1760002445, wake: 1760026440, windowStart: 1760002445, windowEnd: 1760026445, sleepEpochs: 4799, wakeEpochs: 0, gapEpochs: 0, threshold: 0.26757931962839265, wakeBouts: [], gaps: [], minuteRuns: [[29333374, 29333773]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "natt över midnatt och zonbyte", start: 1792873800,
            kalla: .faser([.active(seconds: 1800), .still(seconds: 32400), .active(seconds: 1800)], seed: 11),
            from: 1792836000, to: 1792926000, zon: Zon(wakeTime: 1792908000, startOffset: 7200, endOffset: 3600),
            facit: Facit(onset: 1792875610, wake: 1792908000, windowStart: 1792875610, windowEnd: 1792908010, sleepEpochs: 6478, wakeEpochs: 0, gapEpochs: 0, threshold: 0.2611350250488931, wakeBouts: [], gaps: [], minuteRuns: [[29881260, 29881799]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "trolig natt, frö 5", start: 1760000040,
            kalla: .trolig(seed: 5),
            from: 1759999440, to: 1760025720, zon: nil,
            facit: Facit(onset: 1760001910, wake: 1760023620, windowStart: 1760001910, windowEnd: 1760023620, sleepEpochs: 4182, wakeEpochs: 160, gapEpochs: 0, threshold: 0.2625390507503411, wakeBouts: [[1760013480, 1760014280]], gaps: [], minuteRuns: [[29333365, 29333557], [29333571, 29333726]], incompleteStart: false, incompleteEnd: false)),
        Natt(
            name: "trolig natt, frö 9", start: 1760000040,
            kalla: .trolig(seed: 9),
            from: 1759999440, to: 1760025960, zon: nil,
            facit: Facit(onset: 1760001490, wake: 1760023860, windowStart: 1760001490, windowEnd: 1760023860, sleepEpochs: 4354, wakeEpochs: 120, gapEpochs: 0, threshold: 0.25995377439633316, wakeBouts: [[1760012700, 1760013300]], gaps: [], minuteRuns: [[29333358, 29333544], [29333555, 29333730]], incompleteStart: false, incompleteEnd: false)),
    ]
}
