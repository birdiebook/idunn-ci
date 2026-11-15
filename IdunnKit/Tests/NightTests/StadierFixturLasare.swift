import Foundation
import WhoopFrames

// METOD M37. Läser raderna i StadierSpegelFixtur (påhittade, heltal) som K18-poster: `rader` är
// `bpm,rr…` per sekund från `start` (`-N` hoppar N sekunder), och gravitationen byter vid raderna i
// `lagen` (`sekund,x,y,z` i tusendels g) och gäller tills nästa rad. Python tolkar samma rader likadant
// (tools/tests/stadier_fixtur.py, `poster`).

enum StadierFixturLasare {

    static func integers(_ rad: Substring) -> [Int] {
        rad.split(separator: ",").map { (x: Substring) -> Int in Int(String(x)) ?? 0 }
    }

    /// Talen på en rad; "nan" blir `Double.nan`.
    static func numbers(_ rad: Substring) -> [Double] {
        rad.split(separator: ",", omittingEmptySubsequences: false).map { (x: Substring) -> Double in
            Double(String(x)) ?? Double.nan
        }
    }

    static func records(_ n: StadierSpegelFixtur.Natt) -> [K18Record] {
        var byten: [(sekund: Int, x: Double, y: Double, z: Double)] = []
        for rad in n.lagen.split(separator: "\n") {
            let d: [Int] = integers(rad)
            byten.append((sekund: d[0], x: Double(d[1]) / 1000.0, y: Double(d[2]) / 1000.0, z: Double(d[3]) / 1000.0))
        }
        var ut: [K18Record] = []
        var s: Int = 0
        var k: Int = -1
        for rad in n.rader.split(separator: "\n") {
            if rad.hasPrefix("-") {
                s += Int(String(rad.dropFirst())) ?? 0
                continue
            }
            while k + 1 < byten.count && byten[k + 1].sekund <= s { k += 1 }
            let d: [Int] = integers(rad)
            let g = K18Record.Gravity(x: byten[k].x, y: byten[k].y, z: byten[k].z)
            ut.append(K18Record(time: n.start + s, pulse: d[0], rr: Array(d.dropFirst()), gravity: g,
                                skinTemperature: 33.0, bandTemperature: 30.0))
            s += 1
        }
        return ut
    }

    static func series(_ n: StadierSpegelFixtur.Natt) -> K18Series { K18Series(records: records(n)) }
}
