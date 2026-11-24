import Foundation
import XCTest
@testable import Pass

// BESLUT B158 · METOD M85. Ett pass som läggs till för hand i efterhand. Allt nedan är påhittat (CLAUDE.md §Dataregeln).

/// Nu: en hel minut, och en hel 5-minutersgräns.
private let nu = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000 % 300)

private func gmt() -> Calendar {
    var k = Calendar(identifier: .gregorian)
    k.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
    return k
}

final class PassManualTests: XCTestCase {

    func minuter(_ m: Double) -> TimeInterval { m * 60 }

    func testStandardtidernÄrNuAvrundatNerOchEnHalvtimmeFöre() {
        // 12:07:41 blir 12:05 och 11:35.
        let nuOjämn: Date = nu.addingTimeInterval(minuter(7) + 41)
        let d = PassManual.defaults(now: nuOjämn)
        XCTAssertEqual(d.stop, nu.addingTimeInterval(minuter(5)))
        XCTAssertEqual(d.start, d.stop.addingTimeInterval(-minuter(30)))
        XCTAssertLessThanOrEqual(d.stop, nuOjämn)
        // På en hel gräns ändras ingenting.
        XCTAssertEqual(PassManual.defaults(now: nu).stop, nu)
        XCTAssertNil(PassManual.problem(start: d.start, stop: d.stop, now: nuOjämn, existing: []))
    }

    func testStoppSammaDagSomStartOchÖverMidnatt() {
        let k: Calendar = gmt()
        let zon: TimeZone = k.timeZone
        func klockan(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
            k.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) ?? Date.distantPast
        }
        func hjul(_ h: Int, _ mi: Int) -> Int { PassClock.wheelMinutes(klockan(2030, 1, 1, h, mi), timeZone: zon) }
        let start: Date = klockan(2027, 3, 10, 18, 30)
        XCTAssertEqual(PassManual.stopDate(start: start, wheelMinutes: hjul(19, 45), timeZone: zon),
                       klockan(2027, 3, 10, 19, 45))
        // 00:15 ligger före Start samma dag: dagen efter.
        XCTAssertEqual(PassManual.stopDate(start: start, wheelMinutes: hjul(0, 15), timeZone: zon),
                       klockan(2027, 3, 11, 0, 15))
        // Samma klockslag som Start: Start själv, och regeln fäller det.
        let samma: Date = PassManual.stopDate(start: start, wheelMinutes: hjul(18, 30), timeZone: zon)
        XCTAssertEqual(PassManual.problem(start: start, stop: samma, now: klockan(2027, 3, 12, 0, 0), existing: []),
                       .stopNotAfterStart)
        // En minut efter Start är samma dag, en minut före är dagen efter.
        XCTAssertEqual(PassManual.stopDate(start: start, wheelMinutes: hjul(18, 31), timeZone: zon),
                       klockan(2027, 3, 10, 18, 31))
        XCTAssertEqual(PassManual.stopDate(start: start, wheelMinutes: hjul(18, 29), timeZone: zon),
                       klockan(2027, 3, 11, 18, 29))
    }

    func testRegelnStoppEfterStart() {
        let s: Date = nu.addingTimeInterval(-3600)
        XCTAssertEqual(PassManual.problem(start: s, stop: s, now: nu, existing: []), .stopNotAfterStart)
        XCTAssertEqual(PassManual.problem(start: s, stop: s.addingTimeInterval(-300), now: nu, existing: []),
                       .stopNotAfterStart)
        // Sekunderna räknas inte: samma minut är ingen längd.
        XCTAssertEqual(PassManual.problem(start: s, stop: s.addingTimeInterval(40), now: nu, existing: []),
                       .stopNotAfterStart)
        XCTAssertNil(PassManual.problem(start: s, stop: s.addingTimeInterval(60), now: nu, existing: []))
    }

    func testRegelnStoppHögstNu() {
        let s: Date = nu.addingTimeInterval(-1800)
        XCTAssertNil(PassManual.problem(start: s, stop: nu, now: nu, existing: []))
        XCTAssertEqual(PassManual.problem(start: s, stop: nu.addingTimeInterval(60), now: nu, existing: []),
                       .stopInFuture)
    }

    func testRegelnHögstFyraTimmar() {
        let s: Date = nu.addingTimeInterval(-6 * 3600)
        XCTAssertNil(PassManual.problem(start: s, stop: s.addingTimeInterval(4 * 3600), now: nu, existing: []))
        XCTAssertEqual(PassManual.problem(start: s, stop: s.addingTimeInterval(4 * 3600 + 60), now: nu, existing: []),
                       .tooLong)
        XCTAssertEqual(PassManual.maxDurationSeconds, PassRules.staleSeconds)
    }

    func testRegelnStartHögstFjortonDagarBakåt() {
        let gräns: Date = nu.addingTimeInterval(-14 * 86_400)
        XCTAssertNil(PassManual.problem(start: gräns, stop: gräns.addingTimeInterval(1800), now: nu, existing: []))
        let före: Date = gräns.addingTimeInterval(-60)
        XCTAssertEqual(PassManual.problem(start: före, stop: före.addingTimeInterval(1800), now: nu, existing: []),
                       .tooOld)
        XCTAssertEqual(PassManual.maxAgeSeconds, 14 * 86_400)
    }

    func testEttPassSomÖverlapparEttBefintligtTillåtsInte() {
        // Ett pass 10:00–10:30 med efterperiod till 10:40.
        let a: Date = nu.addingTimeInterval(-5 * 3600)
        let finns = Pass(start: a, stop: a.addingTimeInterval(1800), afterEnd: a.addingTimeInterval(2400), kind: .styrka)
        func prova(_ från: Double, _ till: Double) -> PassManual.Problem? {
            PassManual.problem(start: a.addingTimeInterval(minuter(från)), stop: a.addingTimeInterval(minuter(till)),
                               now: nu, existing: [finns])
        }
        XCTAssertEqual(prova(-20, 5), .overlaps)      // slutar inne i passet
        XCTAssertEqual(prova(10, 20), .overlaps)      // mitt i
        XCTAssertEqual(prova(-10, 60), .overlaps)     // omsluter
        XCTAssertEqual(prova(35, 50), .overlaps)      // starten i efterperioden
        XCTAssertEqual(prova(-50, -9), .overlaps)     // den nya efterperioden på tio minuter når in i passet
        XCTAssertNil(prova(-60, -20))                 // före, och den nya efterperioden slutar före passet
        XCTAssertNil(prova(41, 70))                   // efter den befintliga efterperioden
    }

    func testPassetByggsOchMärksSomTillagtForHand() throws {
        let start: Date = nu.addingTimeInterval(-3600 + 25)
        let stopp: Date = nu.addingTimeInterval(-1800 + 40)
        let p: Pass = PassManual.pass(start: start, stop: stopp, label: PassLabel(kind: .bastu, note: "  Efter golfen "))
        XCTAssertEqual(p.start, PassManual.wholeMinute(start))
        XCTAssertEqual(p.stop, PassManual.wholeMinute(stopp))
        XCTAssertEqual(p.afterEnd, p.stop?.addingTimeInterval(PassRules.afterSeconds))
        XCTAssertEqual(p.kind, .bastu)
        XCTAssertEqual(p.note, "Efter golfen")
        XCTAssertEqual(p.addedByHand, true)
        XCTAssertNil(p.suggested)
        XCTAssertTrue(p.isFinished)
        // Egna ord tar över typen.
        let egen: Pass = PassManual.pass(start: start, stop: stopp, label: PassLabel(customKind: "Padel"))
        XCTAssertEqual(egen.kindName, "Padel")
        XCTAssertNil(egen.kind)
    }

    func testPulsenFyllsUrHistorikenOchSaknasDenVäntarPassetPåDen() throws {
        let start: Date = nu.addingTimeInterval(-3600)
        let stopp: Date = nu.addingTimeInterval(-1800)
        // Utan historik: sparat ändå, utan prov, och det väntar på historiken (BESLUT B117).
        let tomt: Pass = PassManual.pass(start: start, stop: stopp, label: PassLabel(kind: .bastu))
        XCTAssertTrue(tomt.samples.isEmpty)
        XCTAssertTrue(PassHistory.awaitsHistory(tomt, now: nu))
        // Med historik för fönstret och efterperioden: puls 110 i en post per sekund.
        let från: Int = Int(tomt.start.timeIntervalSince1970)
        let till: Int = Int(tomt.afterEnd?.timeIntervalSince1970 ?? 0)
        let poster: [PassHistory.Reading] = (från...till).map { (t: Int) -> PassHistory.Reading in
            PassHistory.Reading(time: t, bpm: 110)
        }
        let fyllt: Pass = PassManual.pass(start: start, stop: stopp, label: PassLabel(kind: .bastu), readings: poster,
                                          id: tomt.id)
        XCTAssertEqual(fyllt.samples.count, poster.count)
        XCTAssertTrue(fyllt.samples.allSatisfy { $0.source == .history })
        XCTAssertEqual(fyllt.averageBpm, 110)
        // Samma påfyllnad som för varje sparat pass fyller det tomma passet senare, och ger samma pass.
        let senare: Pass = PassHistory.fill(tomt, readings: poster, through: tomt.afterEnd)
        XCTAssertEqual(senare.samples, fyllt.samples)
        XCTAssertFalse(PassHistory.awaitsHistory(senare, now: nu))
    }

    func testEttTillagtPassStängerUteFörslagPåSammaTid() {
        let start: Date = nu.addingTimeInterval(-3600)
        let p: Pass = PassManual.pass(start: start, stop: start.addingTimeInterval(1800), label: PassLabel(kind: .bastu))
        let ut: [ClosedRange<Int>] = PassSuggestions.excluded(passes: [p], store: PassSuggestions.Store())
        let minut: Int = Int(start.timeIntervalSince1970) / 60 + 10
        XCTAssertTrue(ut.contains { (r: ClosedRange<Int>) -> Bool in r.contains(minut) })
    }

    func testFilenFramOchTillbakaOchEnÄldreFilUtanFältetLäsesSomFörut() throws {
        let start: Date = nu.addingTimeInterval(-3600)
        let p: Pass = PassManual.pass(start: start, stop: start.addingTimeInterval(1800), label: PassLabel(kind: .bastu))
        let tillbaka: Pass = try PassFile.decode(try PassFile.encode(p))
        XCTAssertEqual(tillbaka, p)
        XCTAssertEqual(tillbaka.addedByHand, true)
        // Ett vanligt pass skriver inte nyckeln, och en fil utan den läses som förut.
        let vanligt = Pass(start: start, stop: start.addingTimeInterval(1800), kind: .styrka)
        let json: String = String(decoding: try PassFile.encode(vanligt), as: UTF8.self)
        XCTAssertFalse(json.contains("addedByHand"))
        XCTAssertNil(try PassFile.decode(Data(json.utf8)).addedByHand)
    }
}
