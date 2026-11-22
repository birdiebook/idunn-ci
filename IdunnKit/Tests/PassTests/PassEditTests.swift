import Foundation
import XCTest
@testable import Pass

// BESLUT B150 · METOD M85. Påhittade pass: märkningen, flyttade tider och förslagets ursprung.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Ett påhittat pass på 30 minuter med ett prov i sekunden: pulsen 100 de första 10 minuterna, sedan 150, och 90 i
/// efterperioden.
private func trettio() -> Pass {
    var p = Pass(start: t0, stop: t0.addingTimeInterval(1800), afterEnd: t0.addingTimeInterval(2400), kind: .styrka)
    for s in 0...2400 {
        let bpm: Int = s > 1800 ? 90 : (s < 600 ? 100 : 150)
        p.samples.append(PassSample(t: t0.addingTimeInterval(Double(s)), bpm: bpm))
    }
    return p
}

final class PassEditTests: XCTestCase {

    func testEnFilUtanDeNyaNycklarnaLäsesSomFörut() throws {
        // Ett pass som ett äldre bygge skrev det: inga nycklar för egen typ, anteckning eller förslag.
        let json = """
        {"afterEnd":"2027-01-15T08:12:00Z","id":"7C3B6F2A-1D8E-4F51-9A63-0B2C4D5E6F70","kind":"bastu",\
        "samples":[{"bpm":90,"t":"2027-01-15T08:00:00Z"}],"start":"2027-01-15T08:00:00Z","stop":"2027-01-15T08:02:00Z"}
        """
        let p = try PassFile.decode(Data(json.utf8))
        XCTAssertEqual(p.kind, .bastu)
        XCTAssertNil(p.customKind)
        XCTAssertNil(p.note)
        XCTAssertNil(p.suggested)
        XCTAssertEqual(p.kindName, "Bastu")
        // Och ett pass utan de nya fälten skrivs utan nycklarna, som förut.
        let s = String(decoding: try PassFile.encode(p), as: UTF8.self)
        XCTAssertFalse(s.contains("customKind"))
        XCTAssertFalse(s.contains("note"))
        XCTAssertFalse(s.contains("suggested"))
    }

    func testEgenTypOchAnteckningFramOchTillbaka() throws {
        var p = trettio()
        PassEdit.apply(PassLabel(kind: .styrka, customKind: "  Klättring ", note: " tung dag \n"), to: &p)
        XCTAssertNil(p.kind)                                               // egna ord tar över den fasta typen
        XCTAssertEqual(p.customKind, "Klättring")
        XCTAssertEqual(p.note, "tung dag")
        XCTAssertEqual(p.kindName, "Klättring")
        XCTAssertEqual(try PassFile.decode(try PassFile.encode(p)), p)
        // Tomma egna ord: den fasta typen gäller, och en tom anteckning är ingen.
        PassEdit.apply(PassLabel(kind: .golf, customKind: "   ", note: ""), to: &p)
        XCTAssertEqual(p.kind, .golf)
        XCTAssertNil(p.customKind)
        XCTAssertNil(p.note)
        // Långa ord kortas.
        PassEdit.apply(PassLabel(customKind: String(repeating: "a", count: 100)), to: &p)
        XCTAssertEqual(p.customKind?.count, PassEdit.customKindMaxLength)
        XCTAssertEqual(PassLabel(p), PassLabel(kind: nil, customKind: p.customKind, note: nil))
    }

    func testInspelarenSätterMärkningenOchEnFastTypTömmerDeEgnaOrden() {
        var r = PassRecorder()
        r.start(now: t0)
        r.setLabel(PassLabel(customKind: "Padel", note: "dubbel"))
        XCTAssertEqual(r.pass?.customKind, "Padel")
        XCTAssertNil(r.pass?.kind)
        XCTAssertEqual(r.pass?.note, "dubbel")
        r.setKind(.kondition)
        XCTAssertEqual(r.pass?.kind, .kondition)
        XCTAssertNil(r.pass?.customKind)
        XCTAssertEqual(r.pass?.note, "dubbel")                             // anteckningen står kvar
    }

    func testStatistikenRäknasOmPåDetNyaFönstret() {
        let p = trettio()
        XCTAssertEqual(p.minBpm, 100)
        // Start flyttad 10 minuter senare: bara pulsen 150 är kvar i den aktiva delen.
        let q = PassEdit.retimed(p, start: t0.addingTimeInterval(600), stop: t0.addingTimeInterval(1800))
        XCTAssertEqual(q.start, t0.addingTimeInterval(600))
        XCTAssertEqual(q.minBpm, 150)
        XCTAssertEqual(q.maxBpm, 150)
        XCTAssertEqual(q.averageBpm, 150)
        XCTAssertEqual(q.duration, 1200)
        XCTAssertEqual(q.samples.first?.t, t0.addingTimeInterval(600))    // proven före den nya starten är borta
        XCTAssertEqual(q.afterEnd, t0.addingTimeInterval(2400))           // efterperioden har kvar sin längd
        // Stopp 5 minuter tidigare: efterperioden flyttar med, och proven efter den är borta.
        let r = PassEdit.retimed(p, start: t0, stop: t0.addingTimeInterval(1500))
        XCTAssertEqual(r.afterEnd, t0.addingTimeInterval(2100))
        XCTAssertEqual(r.samples.last?.t, t0.addingTimeInterval(2100))
        XCTAssertEqual(r.activeSamples.count, 1501)
        XCTAssertEqual(r.pulseAtStop, 150)
        // Zonerna räknas ur samma prov.
        let zoner = PassZones.time(q.activeSamples) { (bpm: Int) -> Int in bpm >= 150 ? 3 : 1 }
        XCTAssertEqual(zoner.first(where: { $0.zone == 1 })?.seconds ?? 0, 0)
        // Ett pass som pågår ändras inte.
        let pågår = Pass(start: t0)
        XCTAssertEqual(PassEdit.retimed(pågår, start: t0.addingTimeInterval(60), stop: t0.addingTimeInterval(120)), pågår)
    }

    func testFlyttadStartFyllsUrHistoriken() {
        // Ett förslag startade 10 minuter för sent: användaren flyttar starten bakåt, och historiken fyller de minuterna.
        var p = Pass(start: t0.addingTimeInterval(600), stop: t0.addingTimeInterval(1800),
                     afterEnd: t0.addingTimeInterval(2400), kind: .styrka)
        let poster: [PassHistory.Reading] = (0...2400).map { PassHistory.Reading(time: 1_800_000_000 + $0, bpm: 120) }
        p = PassHistory.fill(p, readings: poster)
        XCTAssertEqual(p.samples.first?.t, t0.addingTimeInterval(600))
        let q = PassHistory.fill(PassEdit.retimed(p, start: t0, stop: t0.addingTimeInterval(1800)), readings: poster)
        XCTAssertEqual(q.samples.first?.t, t0)
        XCTAssertEqual(q.activeSamples.count, 1801)
    }

    func testFlyttenHållerSigInomGränsernaOchMinstEnMinut() {
        let start: Date = t0
        let stopp: Date = t0.addingTimeInterval(1800)
        let nu: Date = t0.addingTimeInterval(2000)
        let g = PassEdit.Limits(start: start, stop: stopp, now: nu)
        XCTAssertEqual(g.earliest, t0.addingTimeInterval(-3600))
        XCTAssertEqual(g.latest, nu)                                       // aldrig efter nu
        var t = PassEdit.moved(start: start, stop: stopp, edge: .start, minutes: -5, limits: g)
        XCTAssertEqual(t.start, t0.addingTimeInterval(-300))
        XCTAssertEqual(t.stop, stopp)
        t = PassEdit.moved(start: start, stop: stopp, edge: .start, minutes: -90, limits: g)
        XCTAssertEqual(t.start, g.earliest)
        t = PassEdit.moved(start: start, stop: stopp, edge: .start, minutes: 60, limits: g)
        XCTAssertEqual(t.start, stopp.addingTimeInterval(-60))              // minst en minut kvar
        t = PassEdit.moved(start: start, stop: stopp, edge: .stop, minutes: 10, limits: g)
        XCTAssertEqual(t.stop, nu)
        t = PassEdit.moved(start: start, stop: stopp, edge: .stop, minutes: -60, limits: g)
        XCTAssertEqual(t.stop, start.addingTimeInterval(60))
    }

    func testFörslagetsUrsprungSparasBreddvidDetSomValdes() throws {
        let förslag = PassDetection.Candidate(startMinute: 30_000_000, endMinute: 30_000_029, kind: .kondition,
                                              elevatedMinutes: 30, meanReserve: 0.6)
        let poster: [PassHistory.Reading] = (0..<3600).map {
            PassHistory.Reading(time: 30_000_000 * 60 - 600 + $0, bpm: 130)
        }
        let start: Date = förslag.start.addingTimeInterval(-300)
        let stopp: Date = förslag.end.addingTimeInterval(-120)
        let p = PassSuggestions.pass(from: förslag, kind: nil, readings: poster,
                                     label: PassLabel(customKind: "Padel", note: "med Erik"),
                                     start: start, stop: stopp)
        XCTAssertEqual(p.start, start)
        XCTAssertEqual(p.stop, stopp)
        XCTAssertEqual(p.afterEnd, stopp.addingTimeInterval(PassRules.afterSeconds))
        XCTAssertNil(p.kind)
        XCTAssertEqual(p.customKind, "Padel")
        XCTAssertEqual(p.note, "med Erik")
        XCTAssertEqual(p.suggested, PassOrigin(start: förslag.start, end: förslag.end, kind: .kondition))
        XCTAssertEqual(p.samples.first?.t, start)                         // pulsen fylld från den flyttade starten
        // Ursprunget står kvar i filen, och när passet ändras senare.
        let läst = try PassFile.decode(try PassFile.encode(p))
        XCTAssertEqual(läst.suggested, p.suggested)
        let ändrat = PassEdit.retimed(läst, start: start.addingTimeInterval(60), stop: stopp)
        XCTAssertEqual(ändrat.suggested, p.suggested)
        // Utan märkning och tider: förslagets egna, och ursprunget ändå sparat.
        let enkelt = PassSuggestions.pass(from: förslag, kind: .kondition, readings: poster)
        XCTAssertEqual(enkelt.start, förslag.start)
        XCTAssertEqual(enkelt.stop, förslag.end)
        XCTAssertEqual(enkelt.suggested?.kind, .kondition)
    }
}
