import Foundation
import XCTest
@testable import Night

// BESLUT B44 · METOD M37. Vikterna kommer som text ur ModelData.swift (som tools/modellfil.py
// --swift skriver ur tools/modeller/*.json; ett Python-prov fäller om filen inte är exakt det
// skriptet skriver). Här: att texten avkodas och har rätt form, och att en fel form ger `nil`
// i stället för en modell som räknar fel.

final class ModelDataTests: XCTestCase {

    func testSömnmodellenAvkodasOchHarRättForm() throws {
        let m = try XCTUnwrap(SleepModels.wake, "somn_vaken.json går inte att läsa")
        XCTAssertEqual(m.sardrag, ["steg_epok", "steg_5min", "steg_over_5grader", "median_5min", "puls_epok",
                                   "puls_5min", "andel_av_natten"])
        XCTAssertEqual(m.medel.count, 7)
        XCTAssertEqual(m.sd.count, 7)
        XCTAssertEqual(m.vikter.count, 8)
        XCTAssertGreaterThan(m.troskel, 0)
        XCTAssertLessThan(m.troskel, 1)
        XCTAssertTrue(m.sd.allSatisfy { (x: Double) -> Bool in x > 0 })
        XCTAssertTrue(m.isConsistent)
    }

    func testStadiemodellenAvkodasOchHarRättForm() throws {
        let m = try XCTUnwrap(SleepModels.stage, "stadier.json går inte att läsa")
        XCTAssertEqual(m.klasser, ["vaken", "lätt", "djup", "REM"])
        XCTAssertEqual(m.hrv.grund, ["puls_e", "lnrmssd_e", "sdpuls_e", "puls_f", "lnrmssd_f", "sdpuls_f",
                                     "lnlfhf_f", "andning_f", "topp_f", "dfa_f"])
        XCTAssertEqual(m.hrv.tid, ["andel_av_natten", "timmar"])
        XCTAssertEqual(m.hrv.normering.satt, "natt+rullande")
        XCTAssertEqual(m.hrv.normering.rullandeEpoker, 120)
        XCTAssertEqual(m.hrv.grannar.skift, [-10, 10])
        XCTAssertEqual(m.hrv.grannar.utjamning, [10, 30])
        XCTAssertEqual(m.hrv.sardrag.count, 102)
        XCTAssertEqual(m.hrv.medel.count, 102)
        XCTAssertEqual(m.hrv.sd.count, 102)
        XCTAssertEqual(m.hrv.vikter.count, 4)
        for rad in m.hrv.vikter { XCTAssertEqual(rad.count, 103) }
        XCTAssertEqual(m.hrv.forekomst.count, 4)
        XCTAssertEqual(m.rorelse.sardrag, ["steg_epok", "steg_5min", "steg_over_5grader", "median_5min",
                                           "andel_av_natten", "timmar"])
        XCTAssertEqual(m.rorelse.medel.count, 6)
        XCTAssertEqual(m.rorelse.sd.count, 6)
        XCTAssertEqual(m.rorelse.vikter.count, 4)
        for rad in m.rorelse.vikter { XCTAssertEqual(rad.count, 7) }
        XCTAssertEqual(m.rorelse.forekomst.count, 4)
        XCTAssertEqual(m.sammanfogning.mal.count, 4)
        // Klass 0 (vaken) är referens: dess vikter är noll.
        XCTAssertTrue(m.hrv.vikter[0].allSatisfy { (x: Double) -> Bool in x == 0 })
        XCTAssertTrue(m.rorelse.vikter[0].allSatisfy { (x: Double) -> Bool in x == 0 })
        // Förekomsterna är andelar.
        XCTAssertEqual(m.hrv.forekomst.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(m.rorelse.forekomst.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(m.sammanfogning.mal.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertTrue(m.isConsistent)
    }

    func testTextenÄrJSONMedDeNycklarSomLäses() throws {
        // Samma text som Python läser: den ska vara giltig JSON med de nycklar avkodningen behöver.
        for text in [ModelData.somnVaken, ModelData.stadier] {
            let obj = try JSONSerialization.jsonObject(with: Data(text.utf8))
            let d = try XCTUnwrap(obj as? [String: Any])
            XCTAssertNotNil(d["modell"])
            XCTAssertNotNil(d["version"])
        }
        let s = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(ModelData.stadier.utf8)) as? [String: Any])
        XCTAssertEqual(s["modell"] as? String, "stadier")
        let v = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(ModelData.somnVaken.utf8)) as? [String: Any])
        XCTAssertEqual(v["modell"] as? String, "somn_vaken")
    }

    func testFelFormGerNilOchInteEnModellSomRäknarFel() {
        XCTAssertNil(SleepModels.decodeWake("{}"))
        XCTAssertNil(SleepModels.decodeWake("inte json"))
        XCTAssertNil(SleepModels.decodeStage("{}"))
        // Ett särdrag med annat namn (listan och filen har glidit isär): ingen modell.
        let bytt: String = ModelData.somnVaken.replacingOccurrences(of: "\"steg_epok\"", with: "\"steg_annat\"")
        XCTAssertNotEqual(bytt, ModelData.somnVaken)
        XCTAssertNil(SleepModels.decodeWake(bytt))
        let bytt2: String = ModelData.stadier.replacingOccurrences(of: "\"natt+rullande\"", with: "\"natt\"")
        XCTAssertNotEqual(bytt2, ModelData.stadier)
        XCTAssertNil(SleepModels.decodeStage(bytt2))
        // Rätt text avkodas.
        XCTAssertNotNil(SleepModels.decodeWake(ModelData.somnVaken))
        XCTAssertNotNil(SleepModels.decodeStage(ModelData.stadier))
    }

    func testVakenSannolikhetenÄrEnLogistiskFunktionAvRörelsen() throws {
        let m = try XCTUnwrap(SleepModels.wake)
        let stilla: [Double] = [0, 0, 0, 0, 0, 0, 0.5]
        var orolig: [Double] = stilla
        orolig[1] = 3.0                                              // medelsteg i ±2,5 min (log1p)
        let a: Double = m.probability(stilla)
        let b: Double = m.probability(orolig)
        XCTAssertTrue(a > 0 && a < 1)
        XCTAssertTrue(b > 0 && b < 1)
        XCTAssertGreaterThan(b, a, "mer rörelse ger högre sannolikhet för vaken")
        // Klippt vid ±30 i exponenten: ingen overflow med orimliga särdrag.
        var extremt: [Double] = stilla
        extremt[1] = 1e9
        XCTAssertTrue(m.probability(extremt).isFinite)
    }

    func testStadiemodellenGerFyraSannolikheterSomÄrEnFördelningOchSaknatÄrMedel() throws {
        let m = try XCTUnwrap(SleepModels.stage)
        let nan = [Double](repeating: Double.nan, count: 102)
        let p: [Double] = m.hrv.part.probabilities(nan)
        XCTAssertEqual(p.count, 4)
        XCTAssertEqual(p.reduce(0, +), 1, accuracy: 1e-12)
        // Saknat = träningens medel = 0 efter standardiseringen: samma som nollor efter medel.
        let medel: [Double] = m.hrv.medel
        let q: [Double] = m.hrv.part.probabilities(medel)
        for c in 0..<4 { XCTAssertEqual(p[c], q[c], accuracy: 1e-12) }
        for x in p { XCTAssertTrue(x > 0 && x < 1) }
    }

    /// BESLUT B36. Data visar `SleepModels.sources`: varje källa i modellfilerna finns med, en gång, med licens.
    func testKällornaÄrAllaIModellfilernaEnGångMedLicens() throws {
        var väntade: [String] = []
        for text in [ModelData.somnVaken, ModelData.stadier] {
            let d = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let kallor = try XCTUnwrap(d["kallor"] as? [[String: Any]], "modellfilen har kallor")
            for k in kallor {
                let namn = try XCTUnwrap(k["namn"] as? String)
                if !väntade.contains(namn) { väntade.append(namn) }
            }
        }
        XCTAssertEqual(SleepModels.sources.map { (k: ModelSource) -> String in k.name }, väntade)
        XCTAssertEqual(väntade.count, 3, "Walch, HMC och CAP")
        for k in SleepModels.sources {
            XCTAssertFalse(k.licence.isEmpty, k.name)
            XCTAssertFalse(k.place.isEmpty, k.name)
        }
        XCTAssertEqual(SleepModels.decodeSources(["inte json"]), [])
    }
}
