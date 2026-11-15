import Foundation
import XCTest
@testable import Night
@testable import WhoopImport

// Påhittade sömnscheman, bara tider. METOD M17. Facit är räknat för hand ur
// definitionen: SRI = −100 + 200 · andelen minutpar ett dygn isär i samma läge.
// Med vaken tid spridd (BESLUT B21) är ett minutpar olika med sannolikheten
// a(1 − b) + b(1 − a), där a och b är andelen sömn i passen dygnet isär.

final class RegularityTests: XCTestCase {
    /// Påhittad första dag, dagar sedan 1970.
    let dag0 = 20_000
    let zon = 3_600

    /// Ett pass som börjar `dag` (dagar sedan 1970) och går från `från` till
    /// `till` minuter efter midnatt den dagen, i väggklocka. Över 1440 = nästa dag.
    /// Med `vaken` bär passet exportens minuter: i sängen = passets längd och
    /// sömn = längden − vaken, som i exporten (METOD M17).
    func pass(_ dag: Int, _ från: Int, _ till: Int, tupplur: Bool = false, vaken: Int? = nil) -> Regularity.Episode {
        let bas: Double = Double(dag) * 86_400 - Double(zon)
        let längd: Int = till - från
        return Regularity.Episode(onset: Date(timeIntervalSince1970: bas + Double(från) * 60),
                                  wake: Date(timeIntervalSince1970: bas + Double(till) * 60),
                                  utcOffsetSeconds: zon, isNap: tupplur,
                                  asleepMinutes: vaken.map { (v: Int) -> Int in längd - v },
                                  inBedMinutes: vaken == nil ? nil : längd)
    }

    func dag(_ k: Int) -> WakeDay { WakeDay(daysSince1970: dag0 + k) }

    func testSammaTiderVarjeDagGer100() throws {
        let p: [Regularity.Episode] = (0..<14).map { (k: Int) -> Regularity.Episode in pass(dag0 + k, 60, 480) }
        let r = Regularity.rolling(p)
        // Första veckan med minst fem dygnspar slutar dag 5 (dag −1 saknas).
        XCTAssertEqual(r.keys.min(), dag(5))
        XCTAssertEqual(r.keys.max(), dag(13))
        XCTAssertEqual(r.count, 9)
        for (_, x) in r { XCTAssertEqual(x, 100, accuracy: 1e-12) }
        XCTAssertNil(Regularity.index(p, endingOn: dag(4)))
    }

    func testPassÖverMidnattRäknasTillUppvakningsdagen() throws {
        // 23:00–07:00 varje natt. Dag 0 har bara kvällen och är inte observerad.
        let p: [Regularity.Episode] = (0..<14).map { (k: Int) -> Regularity.Episode in pass(dag0 + k, 23 * 60, 31 * 60) }
        let r = Regularity.rolling(p)
        XCTAssertEqual(try XCTUnwrap(r[dag(6)]), 100, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(r[dag(13)]), 100, accuracy: 1e-12)
        // Sista dagen har ingen kväll (ingen natt till), så sista dygnsparet
        // skiljer en timme: 100 − 200 · 60 / (6 · 1440).
        let väntat: Double = 100 - 200 * 60 / (6 * 1440)
        XCTAssertEqual(try XCTUnwrap(r[dag(14)]), väntat, accuracy: 1e-9)
    }

    func testVäxlandeSchemaGerKäntIndex() throws {
        // Varannan dag 01–08, varannan 03–10: varje dygnspar skiljer 2 + 2 timmar.
        let p: [Regularity.Episode] = (0..<21).map { (k: Int) -> Regularity.Episode in
            k % 2 == 0 ? pass(dag0 + k, 60, 480) : pass(dag0 + k, 180, 600)
        }
        let väntat: Double = -100 + 200 * (1440.0 - 240.0) / 1440.0
        XCTAssertEqual(väntat, 66.666_666_666, accuracy: 1e-6)
        let r = Regularity.rolling(p)
        XCTAssertEqual(r.count, 16)
        for (_, x) in r { XCTAssertEqual(x, väntat, accuracy: 1e-9) }
    }

    func testTupplurenSänkerVeckorDärDenIngår() throws {
        var p: [Regularity.Episode] = (0..<14).map { (k: Int) -> Regularity.Episode in pass(dag0 + k, 60, 480) }
        p.append(pass(dag0 + 10, 14 * 60, 15 * 60, tupplur: true))
        let r = Regularity.rolling(p)
        let ettPar: Double = 100 - 200 * 60 / (6 * 1440)
        let tvåPar: Double = 100 - 200 * 120 / (6 * 1440)
        XCTAssertEqual(try XCTUnwrap(r[dag(9)]), 100, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(r[dag(10)]), ettPar, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r[dag(11)]), tvåPar, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r[dag(13)]), tvåPar, accuracy: 1e-9)
        XCTAssertEqual(tvåPar, 97.222_222, accuracy: 1e-5)
    }

    func testDagUtanNattpassRäknasInte() throws {
        // Dag 7 har bara en tupplur: den är inte observerad, och dess två
        // dygnspar räknas inte.
        var p: [Regularity.Episode] = (0..<14).filter { $0 != 7 }.map { (k: Int) -> Regularity.Episode in
            pass(dag0 + k, 60, 480)
        }
        p.append(pass(dag0 + 7, 14 * 60, 15 * 60, tupplur: true))
        let r = Regularity.rolling(p)
        XCTAssertNil(r[dag(8)], "fyra dygnspar")
        XCTAssertNil(r[dag(10)], "fyra dygnspar")
        XCTAssertEqual(try XCTUnwrap(r[dag(13)]), 100, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(Regularity.index(p, endingOn: dag(13))), 100, accuracy: 1e-12)
        XCTAssertEqual(Regularity.minDayPairs, 5)
        XCTAssertEqual(Regularity.windowDays, 7)
    }

    func testSömnOchVakenVarannatDygnGerMinus100() throws {
        // Sover dag 0, 2, 4 … hela dygnet och är vaken dag 1, 3, 5 …: varje
        // dygnspar är motsatt, alltså −100 (originalet: möjligt i teorin,
        // sällsynt i praktiken).
        var p: [Regularity.Episode] = []
        for k in stride(from: 0, to: 16, by: 2) {
            // Vaknar vid midnatt: dag k + 1 blir observerad.
            p.append(pass(dag0 + k, 0, 1440))
            // Ett pass utan längd som vaknar vid nästa midnatt: dag k + 2 blir observerad.
            p.append(pass(dag0 + k + 1, 1440, 1440))
        }
        let r = Regularity.rolling(p)
        let veckor = r.filter { $0.key <= dag(15) }
        XCTAssertEqual(veckor.count, 10)
        for (_, x) in veckor { XCTAssertEqual(x, -100, accuracy: 1e-9) }
    }

    func testTrendernaVisarVeckansIndexUtanEgetMedel() throws {
        let p: [Regularity.Episode] = (0..<21).map { (k: Int) -> Regularity.Episode in
            k % 2 == 0 ? pass(dag0 + k, 60, 480) : pass(dag0 + k, 180, 600)
        }
        let x = Regularity.rolling(p)
        let s = Trends.series(.regularity, idun: [:], whoop: x)
        XCTAssertTrue(Trends.Measure.regularity.isWeekly)
        XCTAssertFalse(Trends.Measure.regularity.hasRange)
        XCTAssertEqual(s.points.count, x.count)
        XCTAssertEqual(s.rolling.count, x.count)
        for r in s.rolling { XCTAssertEqual(r.value, try XCTUnwrap(x[r.day]), accuracy: 1e-12) }
        XCTAssertTrue(s.bands.isEmpty)
        XCTAssertEqual(Set(s.rolling.map(\.segment)), [1])
    }

    // MARK: Vaken tid i passet — BESLUT B21

    func testFörvaletSprider() throws {
        XCTAssertEqual(Regularity.defaultVariant, .spreadAwake)
        XCTAssertEqual(Regularity.Variant.allCases, [.spreadAwake, .inBed])
    }

    func testUtanExportensMinuterÄrVarianternaLika() throws {
        // Passen i testerna ovan saknar minuterna: hela passet är sömn i båda
        // varianterna, så de gamla facit gäller oförändrade för `inBed`.
        let scheman: [[Regularity.Episode]] = [
            (0..<14).map { (k: Int) -> Regularity.Episode in pass(dag0 + k, 60, 480) },
            (0..<14).map { (k: Int) -> Regularity.Episode in pass(dag0 + k, 23 * 60, 31 * 60) },
            (0..<21).map { (k: Int) -> Regularity.Episode in
                k % 2 == 0 ? pass(dag0 + k, 60, 480) : pass(dag0 + k, 180, 600)
            },
        ]
        for p in scheman {
            let a = Regularity.rolling(p, variant: .inBed)
            let b = Regularity.rolling(p, variant: .spreadAwake)
            XCTAssertFalse(a.isEmpty)
            XCTAssertEqual(a, b)
        }
        let växlande: Double = -100 + 200 * (1440.0 - 240.0) / 1440.0
        let p = scheman[2]
        for (_, x) in Regularity.rolling(p, variant: .inBed) { XCTAssertEqual(x, växlande, accuracy: 1e-9) }
    }

    func testSammaTiderOchIngenVakenTidGer100() throws {
        let p: [Regularity.Episode] = (0..<14).map { (k: Int) -> Regularity.Episode in
            pass(dag0 + k, 60, 540, vaken: 0)
        }
        for v in Regularity.Variant.allCases {
            let r = Regularity.rolling(p, variant: v)
            XCTAssertEqual(r.count, 9)
            for (_, x) in r { XCTAssertEqual(x, 100, accuracy: 1e-12) }
        }
    }

    func testSammaTiderMedVakenTidGerKäntIndex() throws {
        // 01–09 varje natt (T = 480 min) med W = 120 min vaken: andelen sömn
        // p = 3/4 i varje minut av passet. Ett minutpar i passet är olika med
        // sannolikheten 2p(1 − p) = 3/8, alltså 2W(1 − W/T) = 180 minuter per
        // dygnspar: SRI = 100 − 200 · 180 / 1440 = 75. Hela fönstret som sömn: 100.
        let p: [Regularity.Episode] = (0..<14).map { (k: Int) -> Regularity.Episode in
            pass(dag0 + k, 60, 540, vaken: 120)
        }
        let b = Regularity.rolling(p)
        let a = Regularity.rolling(p, variant: .inBed)
        XCTAssertEqual(b.count, 9)
        XCTAssertEqual(Set(a.keys), Set(b.keys))
        for (_, x) in b { XCTAssertEqual(x, 75, accuracy: 1e-9) }
        for (_, x) in a { XCTAssertEqual(x, 100, accuracy: 1e-12) }
        XCTAssertEqual(try XCTUnwrap(Regularity.index(p, endingOn: dag(13))), 75, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Regularity.index(p, endingOn: dag(13), variant: .inBed)), 100, accuracy: 1e-12)
    }

    func testMerÄnHalvaPassetVakenHöjerIndexetIgen() throws {
        // Samma tider, olika mycket vaken tid: 2W(1 − W/T) olika minuter per
        // dygnspar är störst vid W = T/2 och lika för W och T − W. Så sjunker
        // indexet först och stiger sedan, som hos Fischer m.fl. (2021).
        let t = 480
        func sri(_ w: Int) throws -> Double {
            let p: [Regularity.Episode] = (0..<14).map { (k: Int) -> Regularity.Episode in
                pass(dag0 + k, 60, 60 + t, vaken: w)
            }
            return try XCTUnwrap(Regularity.index(p, endingOn: dag(13)))
        }
        for w in [0, 60, 120, 240, 360, 480] {
            let olika: Double = 2 * Double(w) * (1 - Double(w) / Double(t))
            XCTAssertEqual(try sri(w), 100 - 200 * olika / 1440, accuracy: 1e-9, "W = \(w)")
        }
        XCTAssertEqual(try sri(240), 100 - 200.0 * 240 / 1440, accuracy: 1e-9)
        XCTAssertLessThan(try sri(240), try sri(120))
        XCTAssertEqual(try sri(120), try sri(360), accuracy: 1e-9)
    }

    func testFörskjutetSchemaMedVakenTid() throws {
        // Varannan dag 01–08, varannan 03–10 (T = 420), W = 105: p = 3/4.
        // Per dygnspar: 03–08 (300 min) i båda passen ger 300 · 3/8 = 112,5,
        // och 01–03 och 08–10 (120 + 120 min) i bara det ena ger 240 · 3/4 = 180.
        // B = 100 − 200 · 292,5 / 1440 = 59,375; A = 100 − 200 · 240 / 1440.
        let p: [Regularity.Episode] = (0..<21).map { (k: Int) -> Regularity.Episode in
            k % 2 == 0 ? pass(dag0 + k, 60, 480, vaken: 105) : pass(dag0 + k, 180, 600, vaken: 105)
        }
        let b = Regularity.rolling(p)
        let a = Regularity.rolling(p, variant: .inBed)
        XCTAssertEqual(b.count, 16)
        let väntatB: Double = 100 - 200 * 292.5 / 1440
        XCTAssertEqual(väntatB, 59.375, accuracy: 1e-12)
        let väntatA: Double = 100 - 200 * 240 / 1440
        for (_, x) in b { XCTAssertEqual(x, väntatB, accuracy: 1e-9) }
        for (_, x) in a { XCTAssertEqual(x, väntatA, accuracy: 1e-9) }
    }

    func testTupplurensVakenTidSprids() throws {
        // Fasta nätter utan vaken tid, och en tupplur 14–15 dag 10 med 30 min
        // vaken: varje dygnspar med tuppluren skiljer 60 · 1/2 = 30 minuter.
        var p: [Regularity.Episode] = (0..<14).map { (k: Int) -> Regularity.Episode in
            pass(dag0 + k, 60, 480, vaken: 0)
        }
        p.append(pass(dag0 + 10, 14 * 60, 15 * 60, tupplur: true, vaken: 30))
        let r = Regularity.rolling(p)
        XCTAssertEqual(try XCTUnwrap(r[dag(9)]), 100, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(r[dag(10)]), 100 - 200 * 30 / (6 * 1440), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r[dag(11)]), 100 - 200 * 60 / (6 * 1440), accuracy: 1e-9)
        let a = Regularity.rolling(p, variant: .inBed)
        XCTAssertEqual(try XCTUnwrap(a[dag(11)]), 100 - 200 * 120 / (6 * 1440), accuracy: 1e-9)
    }

    func testAndelenSömn() throws {
        let bas = Date(timeIntervalSince1970: 0)
        func e(_ a: Int?, _ b: Int?) -> Regularity.Episode {
            Regularity.Episode(onset: bas, wake: bas, utcOffsetSeconds: 0, isNap: false,
                               asleepMinutes: a, inBedMinutes: b)
        }
        XCTAssertEqual(try XCTUnwrap(e(360, 480).asleepFraction), 0.75, accuracy: 1e-12)
        XCTAssertNil(e(nil, 480).asleepFraction)
        XCTAssertNil(e(360, nil).asleepFraction)
        XCTAssertNil(e(0, 0).asleepFraction)
        // Mer sömn än tid i sängen kapas vid 1.
        XCTAssertEqual(try XCTUnwrap(e(500, 480).asleepFraction), 1, accuracy: 1e-12)
        XCTAssertEqual(e(nil, nil).sleepProbability(.spreadAwake), 1)
        XCTAssertEqual(e(360, 480).sleepProbability(.inBed), 1)
        XCTAssertEqual(e(360, 480).sleepProbability(.spreadAwake), 0.75, accuracy: 1e-12)
    }

    /// Ett påhittat sömnpass i exportens form.
    func sömn(_ dag: Int, _ från: Int, _ till: Int, vaken: Int) -> Sleep {
        let e = pass(dag, från, till, vaken: vaken)
        return Sleep(cycleStart: e.onset, utcOffsetSeconds: zon, onset: e.onset, wake: e.wake,
                     isNap: false, performancePercent: nil, respiratoryRate: nil,
                     asleepMinutes: (till - från) - vaken, inBedMinutes: till - från,
                     lightMinutes: nil, deepMinutes: nil, remMinutes: nil, awakeMinutes: vaken,
                     needMinutes: nil, debtMinutes: nil, efficiencyPercent: nil, consistencyPercent: nil)
    }

    func testExportensPassGerFörvaletITrendernaOchBådaVarianterna() throws {
        let s: [Sleep] = (0..<14).map { (k: Int) -> Sleep in sömn(dag0 + k, 60, 540, vaken: 120) }
        let e = Regularity.Episode(s[0])
        XCTAssertEqual(e.asleepMinutes, 360)
        XCTAssertEqual(e.inBedMinutes, 480)

        let båda = Regularity.rollingVariants(s)
        let b = try XCTUnwrap(båda[.spreadAwake])
        let a = try XCTUnwrap(båda[.inBed])
        XCTAssertEqual(b, Regularity.rolling(s))
        XCTAssertEqual(a, Regularity.rolling(s, variant: .inBed))
        XCTAssertEqual(try XCTUnwrap(b[dag(13)]), 75, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a[dag(13)]), 100, accuracy: 1e-12)

        // Trenderna och morgonkortet får förvalet; `inBed` går att be om.
        let förval = try XCTUnwrap(Trends.whoopValues(cycles: [], sleeps: s)[.regularity])
        XCTAssertEqual(förval, b)
        let helaFönstret = try XCTUnwrap(Trends.whoopValues(cycles: [], sleeps: s, regularity: .inBed)[.regularity])
        XCTAssertEqual(helaFönstret, a)
        let kort = MorningCard.rows(idun: [:], whoop: [.regularity: förval])
        XCTAssertEqual(try XCTUnwrap(kort.first { $0.measure == .regularity }).value, 75, accuracy: 1e-9)
    }
}
