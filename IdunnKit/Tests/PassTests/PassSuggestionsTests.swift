import Foundation
import XCTest
@testable import Pass

// BESLUT B121 · METOD M69. Från bandets sekunder till förslag och pass. Allt nedan är påhittat (CLAUDE.md §Dataregeln).
// Vilopuls 50 och maxpuls 190: 40 % av pulsreserven är 106 slag.

final class PassSuggestionsTests: XCTestCase {
    typealias Sekund = PassSuggestions.Second
    /// En minutgräns.
    let t0 = 1_800_000_000 - 1_800_000_000 % 60

    /// `minuter` minuter från minut `från` (räknat från t0) med en post per sekund. `rörlig` växlar gravitationen
    /// varannan sekund (|Δg| = 0,2); annars ligger armen stilla.
    func sekunder(_ från: Int, _ minuter: Int, puls: Int, rörlig: Bool, hud: Double? = 33) -> [Sekund] {
        (0..<(minuter * 60)).map { (i: Int) -> Sekund in
            let x: Double = rörlig && i % 2 == 1 ? 0.2 : 0
            return Sekund(time: t0 + från * 60 + i, pulse: puls, x: x, y: 0, z: 1, skinTemperature: hud)
        }
    }

    /// En timme: 20 minuter vila, `pass`, och vila efteråt.
    func timme(_ pass: [Sekund], längd: Int = 25) -> [Sekund] {
        sekunder(0, 20, puls: 65, rörlig: false) + pass + sekunder(20 + längd, 60 - 20 - längd, puls: 65, rörlig: false)
    }

    func testSekundernaBlirMinuter() throws {
        let m = PassSuggestions.minutes(sekunder(0, 2, puls: 120, rörlig: true, hud: 34))
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m[0].minute, t0 / 60)
        XCTAssertEqual(m[0].pulse, 120)
        XCTAssertEqual(try XCTUnwrap(m[0].movement), 0.2, accuracy: 1e-9)
        XCTAssertEqual(m[0].skinTemperature, 34)
        // Stilla arm: rörelsen 0. Puls 0 och orimlig puls är inga prov; utan hud ingen temperatur.
        let stilla = PassSuggestions.minutes(sekunder(0, 1, puls: 0, rörlig: false, hud: nil))
        XCTAssertEqual(stilla.count, 1)
        XCTAssertNil(stilla[0].pulse)
        XCTAssertEqual(stilla[0].movement, 0)
        XCTAssertNil(stilla[0].skinTemperature)
        XCTAssertNil(PassSuggestions.minutes(sekunder(0, 1, puls: 240, rörlig: false))[0].pulse)
        XCTAssertEqual(PassSuggestions.minutes([]), [])
    }

    func testPulsenÄrMedianenOchRörelsenKräverSekundenFöre() throws {
        // Tre sekunder med puls 100, 110, 150: medianen 110.
        let tre = [Sekund(time: t0, pulse: 100, x: 0, y: 0, z: 1), Sekund(time: t0 + 1, pulse: 150, x: 0, y: 0, z: 1),
                   Sekund(time: t0 + 2, pulse: 110, x: 0, y: 0, z: 1)]
        XCTAssertEqual(PassSuggestions.minutes(tre)[0].pulse, 110)
        // En ensam sekund, och en sekund efter ett glapp, har ingen rörelse.
        let glapp = [Sekund(time: t0, pulse: 100, x: 0, y: 0, z: 1), Sekund(time: t0 + 5, pulse: 100, x: 1, y: 0, z: 1)]
        XCTAssertNil(PassSuggestions.minutes(glapp)[0].movement)
        // Ordningen och dubbletter spelar ingen roll.
        XCTAssertEqual(PassSuggestions.minutes(Array(tre.reversed()) + tre), PassSuggestions.minutes(tre))
    }

    func testEttPassIRörelseBlirEttFörslagOchBastuKännsIgen() throws {
        let pass = sekunder(20, 25, puls: 150, rörlig: true)
        let funna = PassSuggestions.suggestions(seconds: timme(pass), restingPulse: 50, maxPulse: 190, passes: [],
                                                store: PassSuggestions.Store())
        XCTAssertEqual(funna.count, 1)
        XCTAssertEqual(funna.first?.startMinute, t0 / 60 + 20)
        XCTAssertEqual(funna.first?.minutes, 25)
        XCTAssertEqual(funna.first?.kind, .kondition)
        let bastu = sekunder(20, 25, puls: 125, rörlig: false, hud: 37)
        XCTAssertEqual(PassSuggestions.suggestions(seconds: timme(bastu), restingPulse: 50, maxPulse: 190, passes: [],
                                                   store: PassSuggestions.Store()).first?.kind, .bastu)
        // Hög puls i stillhet utan värme: inget förslag.
        let oro = sekunder(20, 25, puls: 125, rörlig: false)
        XCTAssertEqual(PassSuggestions.suggestions(seconds: timme(oro), restingPulse: 50, maxPulse: 190, passes: [],
                                                   store: PassSuggestions.Store()), [])
    }

    func testEttPassSomRedanFinnsOchEttBorttagetFörslagGerInget() throws {
        let alla = timme(sekunder(20, 25, puls: 150, rörlig: true))
        let start = Date(timeIntervalSince1970: Double(t0 + 20 * 60))
        // Passet startades för hand: också efterperioden är utesluten.
        let eget = Pass(start: start, stop: start.addingTimeInterval(25 * 60))
        XCTAssertEqual(PassSuggestions.suggestions(seconds: alla, restingPulse: 50, maxPulse: 190, passes: [eget],
                                                   store: PassSuggestions.Store()), [])
        let område = PassSuggestions.excluded(passes: [eget], store: PassSuggestions.Store())
        XCTAssertEqual(område, [(t0 / 60 + 20)...(t0 / 60 + 55)])          // 25 min pass + 10 min efterperiod
        // Ett pass som pågår (inget Stopp) utesluter från Start och efterperiodens längd framåt.
        XCTAssertEqual(PassSuggestions.excluded(passes: [Pass(start: start)], store: PassSuggestions.Store()),
                       [(t0 / 60 + 20)...(t0 / 60 + 30)])
        // Förslaget tas bort: det kommer inte tillbaka.
        var lager = PassSuggestions.Store()
        let förslag = try XCTUnwrap(PassSuggestions.suggestions(seconds: alla, restingPulse: 50, maxPulse: 190,
                                                               passes: [], store: lager).first)
        lager.dismiss(förslag)
        XCTAssertEqual(PassSuggestions.suggestions(seconds: alla, restingPulse: 50, maxPulse: 190, passes: [],
                                                   store: lager), [])
    }

    func testFörslagetBlirEttPassMedPulsenUrHistoriken() throws {
        let pass = sekunder(20, 25, puls: 150, rörlig: true)
        let förslag = try XCTUnwrap(PassSuggestions.suggestions(seconds: timme(pass), restingPulse: 50, maxPulse: 190,
                                                               passes: [], store: PassSuggestions.Store()).first)
        let poster = timme(pass).map { (s: Sekund) -> PassHistory.Reading in PassHistory.Reading(time: s.time, bpm: s.pulse) }
        let id = UUID()
        let p = PassSuggestions.pass(from: förslag, kind: .styrka, readings: poster, id: id)
        XCTAssertEqual(p.id, id)
        XCTAssertEqual(p.kind, .styrka)                                    // typen användaren valde, inte den gissade
        XCTAssertEqual(p.start, Date(timeIntervalSince1970: Double(t0 + 20 * 60)))
        XCTAssertEqual(p.stop, Date(timeIntervalSince1970: Double(t0 + 45 * 60)))
        XCTAssertEqual(p.afterEnd, Date(timeIntervalSince1970: Double(t0 + 55 * 60)))
        XCTAssertTrue(p.isFinished)
        XCTAssertFalse(p.samples.isEmpty)
        XCTAssertTrue(p.samples.allSatisfy { $0.source == .history })
        XCTAssertEqual(p.maxBpm, 150)
        XCTAssertTrue((25 * 60 - 2...25 * 60 + 2).contains(p.activeSamples.count))
        // Passet som nu finns utesluter samma tid: inget nytt förslag.
        XCTAssertEqual(PassSuggestions.suggestions(seconds: timme(pass), restingPulse: 50, maxPulse: 190, passes: [p],
                                                   store: PassSuggestions.Store()), [])
    }

    func testLagretSomFilOchRensningenAvGamlaBorttagna() throws {
        var lager = PassSuggestions.Store()
        let gammalt = PassDetection.Candidate(startMinute: 1000, endMinute: 1030, kind: nil, elevatedMinutes: 30, meanReserve: 0.5)
        let nytt = PassDetection.Candidate(startMinute: 1000 + 31 * 1440, endMinute: 1030 + 31 * 1440, kind: .bastu,
                                           elevatedMinutes: 30, meanReserve: 0.5)
        lager.dismiss(gammalt)
        XCTAssertEqual(lager.dismissed.count, 1)
        lager.dismiss(nytt)                                                // det gamla är äldre än 30 dagar: rensat
        XCTAssertEqual(lager.dismissed, [PassSuggestions.Dismissed(startMinute: nytt.startMinute, endMinute: nytt.endMinute)])
        let data = try JSONEncoder().encode(lager)
        XCTAssertEqual(try JSONDecoder().decode(PassSuggestions.Store.self, from: data), lager)
        // En tom fil och en fil utan nyckeln är ett tomt lager.
        XCTAssertEqual(try JSONDecoder().decode(PassSuggestions.Store.self, from: Data("{}".utf8)), PassSuggestions.Store())
        XCTAssertEqual(PassSuggestions.fileName, "passforslag.json")
    }
}
