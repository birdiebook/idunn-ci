import XCTest
@testable import Journal

/// BESLUT B128 · METOD M74. Dagboken. Alla kvällar, morgnar och tider här är påhittade.
final class JournalTests: XCTestCase {

    /// 2031-03-03 00:00 UTC, som dagar sedan 1970.
    private let dag: Int = 22_341
    private let zon: Int = 3_600

    /// Ett klockslag i zonen `zon` på dagen `dag + dagar`.
    private func tid(_ timme: Int, _ minut: Int = 0, dagar: Int = 0) -> Date {
        Date(timeIntervalSince1970: Double((dag + dagar) * 86_400 + timme * 3_600 + minut * 60 - zon))
    }

    // MARK: Filen

    func testEnKvällOchEnMorgonPerUppvakningsdag() {
        var j = Journal()
        XCTAssertTrue(j.isEmpty)
        j = j.setting(JournalEvening(wakeDayNumber: dag, tags: [EveningTag(id: "stress")], recordedAt: 1))
        j = j.setting(JournalEvening(wakeDayNumber: dag, tags: [EveningTag(id: "alkohol", detail: "2 glas")],
                                     recordedAt: 2))
        j = j.setting(JournalEvening(wakeDayNumber: dag - 1, tags: [], recordedAt: 0))
        XCTAssertEqual(j.evenings.map(\.wakeDayNumber), [dag - 1, dag])
        XCTAssertEqual(j.evening(dag)?.tags, [EveningTag(id: "alkohol", detail: "2 glas")])
        XCTAssertEqual(j.evening(dag - 1)?.tags, [])
        XCTAssertNil(j.evening(dag + 1))

        j = j.setting(JournalMorning(wakeDayNumber: dag, rested: 2, recordedAt: 3))
        j = j.setting(JournalMorning(wakeDayNumber: dag, rested: 4, recordedAt: 4))
        XCTAssertEqual(j.mornings.count, 1)
        XCTAssertEqual(j.morning(dag)?.rested, 4)
    }

    func testEnSkattningUtanför1Till5ÄndrarIngenting() {
        let j = Journal().setting(JournalMorning(wakeDayNumber: dag, rested: 3, recordedAt: 1))
        XCTAssertEqual(j.setting(JournalMorning(wakeDayNumber: dag, rested: 0, recordedAt: 2)), j)
        XCTAssertEqual(j.setting(JournalMorning(wakeDayNumber: dag + 1, rested: 6, recordedAt: 2)), j)
    }

    func testEnÖverhoppadMorgonFrågasInteIgenOchEnSkattningGårFöre() {
        var j = Journal().skippingMorning(dag)
        XCTAssertTrue(j.morningHandled(dag))
        XCTAssertNil(j.morning(dag))
        XCTAssertFalse(j.morningHandled(dag + 1))
        j = j.setting(JournalMorning(wakeDayNumber: dag, rested: 5, recordedAt: 1))
        XCTAssertEqual(j.skippedMornings, [])
        XCTAssertEqual(j.skippingMorning(dag).morning(dag)?.rested, 5)
    }

    func testFilenFramOchTillbakaMedNycklarnaVerktygetLäser() throws {
        var j = Journal()
        j = j.setting(JournalEvening(wakeDayNumber: dag, tags: [EveningTag(id: "sen-maltid", detail: "stor"),
                                                                EveningTag(id: "bastu")], recordedAt: 10))
        j = j.setting(JournalMorning(wakeDayNumber: dag, rested: 3, recordedAt: 20))
        j = j.skippingMorning(dag + 1)
        let data: Data = try j.encoded()
        XCTAssertEqual(try Journal.decode(data), j)
        // `tools/hrv_varianter.py` läser version, evenings (wakeDayNumber, tags med id) och mornings (wakeDayNumber, rested).
        let text: String = String(decoding: data, as: UTF8.self)
        for nyckel in ["\"version\" : 1", "\"evenings\"", "\"mornings\"", "\"wakeDayNumber\"", "\"tags\"", "\"id\"",
                       "\"rested\" : 3", "\"skippedMornings\""] {
            XCTAssertTrue(text.contains(nyckel), nyckel)
        }
    }

    func testEnFilFrånEttNyareByggeLäsesInte() throws {
        let nyare: Data = Data("{\"version\":2,\"evenings\":[],\"mornings\":[],\"skippedMornings\":[]}".utf8)
        XCTAssertThrowsError(try Journal.decode(nyare)) { (fel: Error) -> Void in
            XCTAssertEqual(fel as? JournalError, .unknownVersion)
        }
        XCTAssertThrowsError(try Journal.decode(Data("inte json".utf8)))
    }

    func testNätterPerTagg() {
        var j = Journal()
        j = j.setting(JournalEvening(wakeDayNumber: dag, tags: [EveningTag(id: "stress"), EveningTag(id: "bastu")],
                                     recordedAt: 1))
        j = j.setting(JournalEvening(wakeDayNumber: dag + 1, tags: [EveningTag(id: "stress")], recordedAt: 2))
        j = j.setting(JournalEvening(wakeDayNumber: dag + 2, tags: [EveningTag(id: "alkohol")], recordedAt: 3))
        j = j.setting(JournalEvening(wakeDayNumber: dag + 3, tags: [], recordedAt: 4))
        XCTAssertEqual(j.nightsPerTag, [TagCount(id: "stress", nights: 2), TagCount(id: "alkohol", nights: 1),
                                        TagCount(id: "bastu", nights: 1)])
    }

    func testTaggarnaHarUnikaIdOchDagboksverktygetsNamn() {
        let ids: [String] = JournalTags.standard.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(JournalTags.tag("sen-maltid")?.title, "Sen måltid")
        XCTAssertEqual(JournalTags.tag("sen-maltid")?.options, ["liten", "stor"])
        XCTAssertNil(JournalTags.tag("finns-inte"))
    }

    // MARK: Klockan

    func testKvällenHörTillNattenSomFöljer() {
        XCTAssertEqual(JournalClock.eveningDay(tid(21, 30), utcOffsetSeconds: zon), dag + 1)
        XCTAssertEqual(JournalClock.eveningDay(tid(12), utcOffsetSeconds: zon), dag + 1)
        // Efter midnatt, innan man somnat: natten slutar samma dag.
        XCTAssertEqual(JournalClock.eveningDay(tid(0, 40), utcOffsetSeconds: zon), dag)
        XCTAssertEqual(JournalClock.eveningDay(tid(11, 59), utcOffsetSeconds: zon), dag)
        XCTAssertEqual(JournalClock.morningDay(tid(6, 45), utcOffsetSeconds: zon), dag)
        // Zonen avgör dagen: 23:30 UTC är 00:30 nästa dag i UTC+1.
        let sent: Date = Date(timeIntervalSince1970: Double(dag * 86_400 + 23 * 3_600 + 1_800))
        XCTAssertEqual(JournalClock.morningDay(sent, utcOffsetSeconds: 0), dag)
        XCTAssertEqual(JournalClock.morningDay(sent, utcOffsetSeconds: zon), dag + 1)
    }

    func testMorgonensFrågaMellan3Och14TillsDenÄrBesvaradEllerÖverhoppad() {
        let tom = Journal()
        XCTAssertEqual(JournalClock.prompt(at: tid(3), utcOffsetSeconds: zon, journal: tom),
                       .morning(wakeDayNumber: dag))
        XCTAssertEqual(JournalClock.prompt(at: tid(13, 59), utcOffsetSeconds: zon, journal: tom),
                       .morning(wakeDayNumber: dag))
        XCTAssertNil(JournalClock.prompt(at: tid(14), utcOffsetSeconds: zon, journal: tom))
        XCTAssertNil(JournalClock.prompt(at: tid(17, 59), utcOffsetSeconds: zon, journal: tom))
        let svarad = tom.setting(JournalMorning(wakeDayNumber: dag, rested: 4, recordedAt: 1))
        XCTAssertNil(JournalClock.prompt(at: tid(7), utcOffsetSeconds: zon, journal: svarad))
        XCTAssertNil(JournalClock.prompt(at: tid(7), utcOffsetSeconds: zon, journal: tom.skippingMorning(dag)))
        // Nästa morgon frågas igen.
        XCTAssertEqual(JournalClock.prompt(at: tid(7, dagar: 1), utcOffsetSeconds: zon, journal: svarad),
                       .morning(wakeDayNumber: dag + 1))
    }

    func testKvällensFrågaFrån18OchEfterMidnattTillsDenÄrBesvarad() {
        let tom = Journal()
        XCTAssertEqual(JournalClock.prompt(at: tid(18), utcOffsetSeconds: zon, journal: tom),
                       .evening(wakeDayNumber: dag + 1))
        XCTAssertEqual(JournalClock.prompt(at: tid(23, 50), utcOffsetSeconds: zon, journal: tom),
                       .evening(wakeDayNumber: dag + 1))
        // Efter midnatt gäller frågan samma natt: uppvakningsdagen är nu väggklockans dag.
        XCTAssertEqual(JournalClock.prompt(at: tid(1, dagar: 1), utcOffsetSeconds: zon, journal: tom),
                       .evening(wakeDayNumber: dag + 1))
        let svarad = tom.setting(JournalEvening(wakeDayNumber: dag + 1, tags: [], recordedAt: 1))
        XCTAssertNil(JournalClock.prompt(at: tid(22), utcOffsetSeconds: zon, journal: svarad))
        XCTAssertNil(JournalClock.prompt(at: tid(1, dagar: 1), utcOffsetSeconds: zon, journal: svarad))
        // En besvarad kväll hindrar inte morgonens fråga, och nästa kväll frågas igen.
        XCTAssertEqual(JournalClock.prompt(at: tid(7, dagar: 1), utcOffsetSeconds: zon, journal: svarad),
                       .morning(wakeDayNumber: dag + 1))
        XCTAssertEqual(JournalClock.prompt(at: tid(20, dagar: 1), utcOffsetSeconds: zon, journal: svarad),
                       .evening(wakeDayNumber: dag + 2))
    }
}
