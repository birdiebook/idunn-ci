// GENERERAD av tools/tests/pass_fixtur.py --skriv — redigera inte för hand.
// PÅHITTADE sekunder (METOD M69, BESLUT B151) och facit ur tools/pass_hitta.py, Python-spegeln av knuten K3.
// Segmenten och generatorn i `PassKnotTests` ger sekunderna; inget kommer från ett riktigt band.

@testable import Pass

enum PassKnotFixtur {
    enum Slag {
        case rest, walk, golf, gym
    }

    struct Forslag: Equatable {
        let start: Int
        let slut: Int
        let typ: PassKind?
        let forhojda: Int
    }

    static let frö: UInt64 = 20261122
    /// Lokal tid: sekunder öster om Greenwich.
    static let zon: Int = 7200
    /// Första sekunden (Unix).
    static let start: Int = 1800007200
    /// (minuter, slag, puls): dygn 1 är de första 720 minuterna, dygn 2 resten.
    static let segment: [(Int, Slag, Int)] = [
        (60, .rest, 64),
        (4, .rest, 100),
        (90, .golf, 108),
        (3, .rest, 100),
        (80, .rest, 64),
        (30, .rest, 105),
        (40, .rest, 64),
        (45, .walk, 110),
        (60, .rest, 64),
        (50, .gym, 125),
        (100, .rest, 64),
        (12, .walk, 110),
        (146, .rest, 64),
        (60, .rest, 78),
        (30, .walk, 92),
        (60, .rest, 78),
        (40, .golf, 110),
        (30, .rest, 78),
    ]

    static let minuter: Int = 940
    static let rörligSumma: Double = 239.2
    static let vinkelSumma: Double = 2586.848691587684
    static let vinkelAntal: Int = 940
    static let förslag: [Forslag] = [
        Forslag(start: 30000184, slut: 30000273, typ: .golf, forhojda: 90),
        Forslag(start: 30000427, slut: 30000471, typ: .promenad, forhojda: 45),
        Forslag(start: 30000532, slut: 30000581, typ: .styrka, forhojda: 50),
        Forslag(start: 30000990, slut: 30001029, typ: .golf, forhojda: 40),
    ]
}
