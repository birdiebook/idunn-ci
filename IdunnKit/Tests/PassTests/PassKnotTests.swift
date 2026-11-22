import Foundation
import XCTest
@testable import Pass

// BESLUT B151 · METOD M69. Knuten K3: passen ur pulsen mot dygnets egen nivå och ihållande rörelse, utan vilopuls och
// maxpuls. Allt nedan är påhittat (CLAUDE.md §Dataregeln): sekunderna kommer ur segmenten i `PassKnotFixtur` och
// en slumpgenerator som `tools/tests/pass_fixtur.py` har bit för bit samma av, och facit är vad `tools/pass_hitta.py`
// ger för dem.

final class PassKnotTests: XCTestCase {
    /// Samma LCG som `Lcg` i `tools/tests/pass_fixtur.py`.
    struct Lcg {
        var x: UInt64

        mutating func rnd(_ n: Int) -> Int {
            x = x &* 6364136223846793005 &+ 1442695040888963407
            return Int((x >> 33) % UInt64(n))
        }
    }

    /// Sekunderna ur segmenten: rest (stilla), walk (liten svängning), golf (som walk med en sving var 25:e
    /// sekund), svag (som golf med en svagare sving) och gym (set om 55 sekunder med rörelse och 35 stilla, ny arm-pose per set). Samma ordning på
    /// slumptalen som i Python.
    func sekunder() -> [PassSuggestions.Second] {
        var r = Lcg(x: PassKnotFixtur.frö)
        var ut: [PassSuggestions.Second] = []
        var t: Int = PassKnotFixtur.start
        var px = 0.0
        var py = 0.0
        for (minuter, slag, puls) in PassKnotFixtur.segment {
            for i in 0..<(minuter * 60) {
                let p: Int = puls + r.rnd(3) - 1
                var x = 0.0
                var y = 0.0
                var z = 1.0
                switch slag {
                case .rest:
                    x = Double(r.rnd(3) - 1) / 1000
                    y = Double(r.rnd(3) - 1) / 1000
                    z = 1.0 + Double(r.rnd(3) - 1) / 1000
                case .walk, .golf, .svag:
                    x = Double(r.rnd(401) - 200) / 1000
                    y = Double(r.rnd(401) - 200) / 1000
                    z = 1.0
                    if slag == .golf && i % 25 == 0 && i > 0 {
                        x = 1.4
                        y = 0.0
                        z = 2.4
                    }
                    if slag == .svag && i % 25 == 0 && i > 0 {
                        x = 1.0
                        y = 0.0
                        z = 2.2
                    }
                case .gym:
                    let f: Int = i % 90
                    if f == 0 {
                        px = Double(r.rnd(601) - 300) / 1000
                        py = Double(r.rnd(601) - 300) / 1000
                    }
                    if f < 55 {
                        let wx: Int = i % 12 <= 6 ? i % 12 : 12 - i % 12
                        let wy: Int = i % 8 <= 4 ? i % 8 : 8 - i % 8
                        x = px + Double(wx - 3) / 5
                        y = py + Double(wy - 2) / 4
                        z = 1.0
                    } else {
                        x = px
                        y = py
                        z = 1.0 + Double(r.rnd(3) - 1) / 1000
                    }
                }
                ut.append(PassSuggestions.Second(time: t, pulse: p, x: x, y: y, z: z, skinTemperature: 33))
                t += 1
            }
        }
        return ut
    }

    let zon = TimeZone(secondsFromGMT: PassKnotFixtur.zon) ?? TimeZone(secondsFromGMT: 0)!

    func funna(_ sek: [PassSuggestions.Second], excluded: [ClosedRange<Int>] = []) -> [PassKnotFixtur.Forslag] {
        let m: [PassDetection.Minute] = PassSuggestions.minutes(sek)
        return PassDetection.knotCandidates(m, steps: PassSuggestions.steps(sek), excluded: excluded, timeZone: zon)
            .map { (c: PassDetection.Candidate) -> PassKnotFixtur.Forslag in
                PassKnotFixtur.Forslag(start: c.startMinute, slut: c.endMinute, typ: c.kind, forhojda: c.elevatedMinutes)
            }
    }

    func testMinuternaHarSammaRörelseOchVinkelSomPython() {
        let m: [PassDetection.Minute] = PassSuggestions.minutes(sekunder())
        XCTAssertEqual(m.count, PassKnotFixtur.minuter)
        XCTAssertEqual(m.compactMap { $0.movingShare }.reduce(0, +), PassKnotFixtur.rörligSumma, accuracy: 1e-6)
        XCTAssertEqual(m.compactMap { $0.armAngle }.count, PassKnotFixtur.vinkelAntal)
        XCTAssertEqual(m.compactMap { $0.armAngle }.reduce(0, +), PassKnotFixtur.vinkelSumma, accuracy: 1e-6)
    }

    func testSammaFörslagOchTypSomPython() {
        let f: [PassKnotFixtur.Forslag] = funna(sekunder())
        XCTAssertEqual(f, PassKnotFixtur.förslag)
        // Golf, promenad, styrka och golf igen; dygnets 30 minuter förhöjd puls i stillhet, den korta promenaden
        // och promenaden under dygn 2:s egen gräns ger inga förslag. Sedan promenaden med kanten och den svaga
        // svingen, vars p99 ligger inom golfgränsens marginal: ingen typ.
        let typer: [PassKind?] = [PassKind.golf, PassKind.promenad, PassKind.styrka, PassKind.golf, PassKind.promenad,
                                  nil]
        XCTAssertEqual(f.map { (x: PassKnotFixtur.Forslag) -> PassKind? in x.typ }, typer)
        // Kanten: en ensam förhöjd minut och tre minuter i rörelse under gränsen i varje ände ligger i perioden, och
        // K = 3 drar in förslaget till passets 40 minuter.
        XCTAssertEqual(f[4].slut - f[4].start + 1, 40)
    }

    func testEttPassSomRörsAvEttUteslutetOmrådeVisasInte() {
        let alla: [PassKnotFixtur.Forslag] = PassKnotFixtur.förslag
        let andra: PassKnotFixtur.Forslag = alla[1]
        let utan: [PassKnotFixtur.Forslag] = funna(sekunder(), excluded: [(andra.start + 5)...(andra.start + 6)])
        XCTAssertEqual(utan, alla.filter { $0 != andra })
        XCTAssertEqual(funna(sekunder(), excluded: [(andra.slut + 1)...(andra.slut + 5)]), alla)
    }

    func testEgnaPassOchBortagnaFörslagUtesluts() {
        let alla: [PassKnotFixtur.Forslag] = PassKnotFixtur.förslag
        let första: PassKnotFixtur.Forslag = alla[0]
        let eget = Pass(id: UUID(), start: Date(timeIntervalSince1970: Double((första.start + 10) * 60)),
                        stop: Date(timeIntervalSince1970: Double((första.start + 20) * 60)), kind: .golf)
        var lager = PassSuggestions.Store()
        lager.dismissed.append(PassSuggestions.Dismissed(startMinute: alla[3].start, endMinute: alla[3].slut))
        let hittade: [PassDetection.Candidate] = PassSuggestions.knotSuggestions(
            seconds: sekunder(), passes: [eget], store: lager, timeZone: zon)
        XCTAssertEqual(hittade.map { $0.startMinute }, [alla[1].start, alla[2].start, alla[4].start, alla[5].start])
    }

    func testIngenVilopulsOchTomtGerInget() {
        XCTAssertEqual(PassDetection.knotCandidates([], steps: [], timeZone: zon), [])
        // Utan någon puls finns ingen nivå: inga förslag.
        let utanPuls: [PassSuggestions.Second] = sekunder().prefix(7200).map {
            (s: PassSuggestions.Second) -> PassSuggestions.Second in
            PassSuggestions.Second(time: s.time, pulse: 0, x: s.x, y: s.y, z: s.z)
        }
        XCTAssertEqual(funna(utanPuls), [])
    }

    func testArmvinkelnKräverTioSekunderOchRörelsenEnFöregåendeSekund() throws {
        let t0: Int = 1_800_000_000 - 1_800_000_000 % 60
        let nio: [PassSuggestions.Second] = (0..<9).map { (i: Int) -> PassSuggestions.Second in
            PassSuggestions.Second(time: t0 + i, pulse: 70, x: 0, y: 0, z: 1)
        }
        XCTAssertNil(PassSuggestions.minutes(nio)[0].armAngle)
        // En stilla arm: ingen sekund rör sig och vinkeln är noll.
        let stilla: [PassSuggestions.Second] = (0..<30).map { (i: Int) -> PassSuggestions.Second in
            PassSuggestions.Second(time: t0 + i, pulse: 70, x: 0, y: 0, z: 1)
        }
        let m: PassDetection.Minute = PassSuggestions.minutes(stilla)[0]
        XCTAssertEqual(try XCTUnwrap(m.movingShare), 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(m.armAngle), 0, accuracy: 1e-3)
        // Varannan sekund 0,1 g åt sidan: hälften av sekundernas rörelse är minst 0,05 (alla 29), och en ensam sekund
        // efter ett glapp har ingen rörelse alls.
        let rörlig: [PassSuggestions.Second] = (0..<30).map { (i: Int) -> PassSuggestions.Second in
            PassSuggestions.Second(time: t0 + i, pulse: 70, x: i % 2 == 1 ? 0.1 : 0, y: 0, z: 1)
        }
        XCTAssertEqual(try XCTUnwrap(PassSuggestions.minutes(rörlig)[0].movingShare), 1, accuracy: 1e-12)
        let glapp: [PassSuggestions.Second] = [
            PassSuggestions.Second(time: t0, pulse: 70, x: 0, y: 0, z: 1),
            PassSuggestions.Second(time: t0 + 5, pulse: 70, x: 1, y: 0, z: 1)]
        XCTAssertNil(PassSuggestions.minutes(glapp)[0].movingShare)
        XCTAssertEqual(PassSuggestions.steps(glapp).map { $0.delta }, [nil, nil])
    }

    func testPercentilenÄrLinjär() {
        XCTAssertEqual(PassDetection.percentile([4, 1, 3, 2], 50), 2.5, accuracy: 1e-12)
        XCTAssertEqual(PassDetection.percentile([1, 2, 3, 4, 5], 99), 4.96, accuracy: 1e-12)
        XCTAssertEqual(PassDetection.percentile([7], 75), 7, accuracy: 1e-12)
    }
}
