import Foundation

/// BESLUT B44 · METOD M37 · METOD M31 · METOD M35
/// De två modellerna ur `ModelData` (som genereras av `tools/modellfil.py --swift`):
/// sömn/vaken per 30 s-epok (BESLUT B37, METOD M31 regel (d)) och stadierna (BESLUT B42,
/// METOD M35). Avkodas en gång; går en av dem inte att läsa, eller har fel form, är den
/// `nil` och `NightStages.estimate` ger `nil`. Formen kontrolleras mot namnen och
/// måtten Python tränade med, så att en ändrad särdragslista utan omskriven fil syns.

/// METOD M31 regel (d). Logistisk regression på sju särdrag.
/// P(vaken) = 1 / (1 + exp(−(vikter[0] + Σ vikter[i+1] · (x_i − medel_i) / sd_i))); vaken om P(vaken) ≥ tröskeln.
struct WakeModel: Decodable, Equatable {
    var sardrag: [String]
    var medel: [Double]
    var sd: [Double]
    var vikter: [Double]
    var troskel: Double

    /// Särdragen i den ordning modellen tränades (`somn_walch.SARDRAG`).
    static let expectedFeatures: [String] = ["steg_epok", "steg_5min", "steg_over_5grader", "median_5min",
                                             "puls_epok", "puls_5min", "andel_av_natten"]

    var isConsistent: Bool {
        guard sardrag == WakeModel.expectedFeatures else { return false }
        guard medel.count == 7, sd.count == 7, vikter.count == 8 else { return false }
        guard SleepModels.allFinite(medel), SleepModels.allFinite(vikter), SleepModels.allPositive(sd) else {
            return false
        }
        return troskel > 0 && troskel < 1
    }

    /// P(vaken) för sju råa särdrag (METOD M31 (d)).
    func probability(_ x: [Double]) -> Double {
        var z: Double = vikter[0]
        for i in 0..<7 {
            let s: Double = (x[i] - medel[i]) / sd[i]
            z += vikter[i + 1] * s
        }
        let c: Double = min(max(z, -30), 30)
        return 1.0 / (1.0 + exp(-c))
    }
}

/// METOD M35 · BESLUT B42. Stadiemodellen: HRV-delen (grannepoker) och rörelsedelen, var för sig en
/// multinomial logistisk regression, fogade med klassernas förekomst (METOD M35, V3b).
struct StageModel: Decodable, Equatable {
    /// Medel, SD, vikter (4 klasser × (särdrag + 1), klass 0 är referens) och träningens klassförekomst.
    struct Part: Decodable, Equatable {
        var sardrag: [String]
        var medel: [Double]
        var sd: [Double]
        var vikter: [[Double]]
        var forekomst: [Double]

        func isConsistent(features n: Int) -> Bool {
            guard sardrag.count == n, medel.count == n, sd.count == n, vikter.count == 4, forekomst.count == 4 else {
                return false
            }
            for row in vikter {
                guard row.count == n + 1, SleepModels.allFinite(row) else { return false }
            }
            return SleepModels.allFinite(medel) && SleepModels.allPositive(sd) && SleepModels.allPositive(forekomst)
        }

        /// Sannolikheterna för de fyra klasserna ur råa särdrag; saknade värden (NaN) blir träningens medel.
        func probabilities(_ x: [Double]) -> [Double] {
            let n: Int = sardrag.count
            var z = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let s: Double = (x[i] - medel[i]) / sd[i]
                z[i] = s.isNaN ? 0 : s
            }
            var logits = [Double](repeating: 0, count: 4)
            for c in 0..<4 {
                var l: Double = vikter[c][0]
                for i in 0..<n { l += vikter[c][i + 1] * z[i] }
                logits[c] = l
            }
            return SleepModels.softmax(logits)
        }
    }

    struct Normalization: Decodable, Equatable {
        var satt: String
        var rullandeEpoker: Int

        enum CodingKeys: String, CodingKey {
            case satt
            case rullandeEpoker = "rullande_epoker"
        }
    }

    struct Neighbours: Decodable, Equatable {
        var skift: [Int]
        var utjamning: [Int]
    }

    struct Hrv: Decodable, Equatable {
        var grund: [String]
        var tid: [String]
        var normering: Normalization
        var grannar: Neighbours
        var sardrag: [String]
        var medel: [Double]
        var sd: [Double]
        var vikter: [[Double]]
        var forekomst: [Double]

        var part: Part {
            Part(sardrag: sardrag, medel: medel, sd: sd, vikter: vikter, forekomst: forekomst)
        }
    }

    struct Fusion: Decodable, Equatable {
        var mal: [Double]
    }

    var klasser: [String]
    var hrv: Hrv
    var rorelse: Part
    var sammanfogning: Fusion

    static let expectedClasses: [String] = ["vaken", "lätt", "djup", "REM"]
    static let expectedBase: [String] = ["puls_e", "lnrmssd_e", "sdpuls_e", "puls_f", "lnrmssd_f", "sdpuls_f",
                                         "lnlfhf_f", "andning_f", "topp_f", "dfa_f"]
    static let expectedTime: [String] = ["andel_av_natten", "timmar"]
    static let expectedMovement: [String] = ["steg_epok", "steg_5min", "steg_over_5grader", "median_5min",
                                             "andel_av_natten", "timmar"]

    /// 10 grundsärdrag normerade mot natten och den rullande (20), fyra gånger grannarna (80) och tiden (2).
    static let hrvFeatures = 102

    var isConsistent: Bool {
        guard klasser == StageModel.expectedClasses else { return false }
        guard hrv.grund == StageModel.expectedBase, hrv.tid == StageModel.expectedTime else { return false }
        guard hrv.normering.satt == "natt+rullande", hrv.normering.rullandeEpoker == 120 else { return false }
        guard hrv.grannar.skift == [-10, 10], hrv.grannar.utjamning == [10, 30] else { return false }
        guard hrv.part.isConsistent(features: StageModel.hrvFeatures) else { return false }
        guard rorelse.sardrag == StageModel.expectedMovement, rorelse.isConsistent(features: 6) else { return false }
        return sammanfogning.mal.count == 4 && SleepModels.allPositive(sammanfogning.mal)
    }
}

/// BESLUT B36 · METOD M37. En källa som tränat en inbyggd modell, ur `kallor` i modellfilen.
/// Data visar dem under Källor (licenserna kräver att källan anges).
public struct ModelSource: Decodable, Equatable, Sendable {
    public var name: String
    public var place: String
    public var licence: String
    public var doi: String?
    public var articleDOI: String?

    enum CodingKeys: String, CodingKey {
        case name = "namn"
        case place = "plats"
        case licence = "licens"
        case doi
        case articleDOI = "artikel_doi"
    }
}

/// Bara `kallor` ur en modellfil; resten av filen läses inte här.
private struct SourceList: Decodable {
    var kallor: [ModelSource]
}

/// Modellerna, avkodade en gång. `nil` om texten inte går att läsa eller har fel form.
public enum SleepModels {
    static let wake: WakeModel? = decodeWake(ModelData.somnVaken)
    static let stage: StageModel? = decodeStage(ModelData.stadier)

    /// BESLUT B36. Källorna i båda modellfilerna, i filernas ordning och en gång per namn.
    public static let sources: [ModelSource] = decodeSources([ModelData.somnVaken, ModelData.stadier])

    static func decodeSources(_ texts: [String]) -> [ModelSource] {
        var out: [ModelSource] = []
        for text in texts {
            guard let list = try? JSONDecoder().decode(SourceList.self, from: Data(text.utf8)) else { continue }
            for k in list.kallor where !out.contains(where: { (o: ModelSource) -> Bool in o.name == k.name }) {
                out.append(k)
            }
        }
        return out
    }

    static func decodeWake(_ text: String) -> WakeModel? {
        guard let m = try? JSONDecoder().decode(WakeModel.self, from: Data(text.utf8)), m.isConsistent else {
            return nil
        }
        return m
    }

    static func decodeStage(_ text: String) -> StageModel? {
        guard let m = try? JSONDecoder().decode(StageModel.self, from: Data(text.utf8)), m.isConsistent else {
            return nil
        }
        return m
    }

    static func allFinite(_ x: [Double]) -> Bool {
        for v in x where !v.isFinite { return false }
        return true
    }

    static func allPositive(_ x: [Double]) -> Bool {
        for v in x where !(v > 0 && v.isFinite) { return false }
        return true
    }

    /// exp(x − max) delat med summan (stadier_hmc._softmax).
    static func softmax(_ z: [Double]) -> [Double] {
        let top: Double = z.max() ?? 0
        var e = [Double](repeating: 0, count: z.count)
        var sum: Double = 0
        for i in 0..<z.count {
            e[i] = exp(z[i] - top)
            sum += e[i]
        }
        return e.map { (x: Double) -> Double in x / sum }
    }
}
