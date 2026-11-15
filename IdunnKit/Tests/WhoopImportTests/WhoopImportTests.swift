import XCTest
@testable import WhoopImport

final class CSVTests: XCTestCase {
    func testCitatKommaOchDubbladeCitattecken() {
        let rows = CSV.parse("a,\"b, c\",\"sa \"\"hej\"\"\"\n1,,3")
        XCTAssertEqual(rows, [["a", "b, c", "sa \"hej\""], ["1", "", "3"]])
    }

    func testCRLFOchBOMOchAvslutandeRadbrytning() {
        let rows = CSV.parse("\u{FEFF}x,y\r\n1,2\r\n")
        XCTAssertEqual(rows, [["x", "y"], ["1", "2"]])
    }

    func testRadbrytningInutiCitat() {
        XCTAssertEqual(CSV.parse("\"rad1\nrad2\",b"), [["rad1\nrad2", "b"]])
    }

    func testCiteratTomtSistaFältRäknas() {
        XCTAssertEqual(CSV.parse("a,\"\""), [["a", ""]])
    }
}

final class WhoopTimeTests: XCTestCase {
    func testZon() {
        XCTAssertEqual(WhoopTime.offsetSeconds("UTC+02:00"), 7200)
        XCTAssertEqual(WhoopTime.offsetSeconds("UTC-05:30"), -19_800)
        XCTAssertEqual(WhoopTime.offsetSeconds("UTC"), 0)
        XCTAssertNil(WhoopTime.offsetSeconds("UTC+2"))
        XCTAssertNil(WhoopTime.offsetSeconds("Europe/Stockholm"))
    }

    func testVäggklockaIZonBlirRättÖgonblick() {
        // 2026-10-25 06:20 i UTC+02:00 = 04:20 UTC.
        let d = WhoopTime.date("2026-10-25 06:20:00", offsetSeconds: 7200)
        XCTAssertEqual(d, Date(timeIntervalSince1970: 1_792_902_000))
    }

    func testKalendern() {
        XCTAssertEqual(WhoopTime.daysFromCivil(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(WhoopTime.daysFromCivil(year: 2000, month: 3, day: 1), 11_017)
        XCTAssertNotNil(WhoopTime.date("2028-02-29 00:00:00", offsetSeconds: 0))
        XCTAssertNil(WhoopTime.date("2026-02-29 00:00:00", offsetSeconds: 0))
        XCTAssertNil(WhoopTime.date("2026-13-01 00:00:00", offsetSeconds: 0))
        XCTAssertNil(WhoopTime.date("2026-10-25T06:20:00", offsetSeconds: 0))
    }
}

final class WhoopExportTests: XCTestCase {
    func testDygnenLäsesÄldstFörstMedPågåendeSist() throws {
        let c = try WhoopExport.parseCycles(Fixtures.cycles)
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c.map(\.recoveryScore), [34, 71, nil])
        XCTAssertEqual(c.map(\.hrv), [41, 63, nil])
        XCTAssertEqual(c.map(\.restingHeartRate), [58, 52, nil])
        XCTAssertNil(c[2].end, "det pågående dygnet har ingen sluttid")
        XCTAssertEqual(try XCTUnwrap(c[0].skinTempCelsius), 34.2, accuracy: 1e-9)
        XCTAssertEqual(c[1].bloodOxygenPercent, 96.4)
    }

    func testZonbytetMittISerien() throws {
        let c = try WhoopExport.parseCycles(Fixtures.cycles)
        XCTAssertEqual(c.map(\.utcOffsetSeconds), [7200, 3600, 3600])
        // Sömnen 24/10 23:10 (+02) till 25/10 06:20 (+02) är 7 h 10 min.
        let natt = try XCTUnwrap(c[0].wakeOnset).timeIntervalSince(try XCTUnwrap(c[0].sleepOnset))
        XCTAssertEqual(natt, 7 * 3600 + 10 * 60)
        // Start 23:10 och slut 23:40 dagen efter, båda i +02: 24 h 30 min.
        let dygn = try XCTUnwrap(c[0].end).timeIntervalSince(c[0].start)
        XCTAssertEqual(dygn, 24 * 3600 + 30 * 60)
    }

    func testDygnenHängerIhopÄvenÖverZonbytet() throws {
        let c = try WhoopExport.parseCycles(Fixtures.cycles)
        for (a, b) in zip(c, c.dropFirst()) {
            XCTAssertEqual(a.end, b.start, "ett dygn slutar där nästa börjar")
        }
    }

    func testSömnpassMedTupplur() throws {
        let s = try WhoopExport.parseSleeps(Fixtures.sleeps)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.map(\.isNap), [false, false, true])
        XCTAssertEqual(s[1].deepMinutes, 102)
        XCTAssertNil(s[1].consistencyPercent)
        XCTAssertEqual(s[0].consistencyPercent, 76)
    }

    func testDagbokMedKommaIFrågan() throws {
        let j = try WhoopExport.parseJournal(Fixtures.journal)
        XCTAssertEqual(j.count, 3)
        XCTAssertTrue(j.contains { $0.question == "Read (non-screened device, book) while in bed?" && $0.answeredYes })
        XCTAssertTrue(j.allSatisfy { $0.notes == nil })
    }

    func testSaknadKolumnFelarHögt() {
        let utanHRV = Fixtures.cycles.replacingOccurrences(of: "Heart rate variability (ms)", with: "HRV")
        XCTAssertThrowsError(try WhoopExport.parseCycles(utanHRV)) { e in
            XCTAssertEqual(e as? WhoopImportError,
                           .missingColumn(file: "physiological_cycles.csv", column: "Heart rate variability (ms)"))
        }
    }

    func testFeletPekarUtRadMenVisarAldrigVärdet() {
        let trasig = Fixtures.cycles.replacingOccurrences(of: ",71,52,63,", with: ",71,52,sextiotre,")
        XCTAssertThrowsError(try WhoopExport.parseCycles(trasig)) { e in
            XCTAssertEqual(e as? WhoopImportError,
                           .badValue(file: "physiological_cycles.csv", line: 3, column: "Heart rate variability (ms)"))
            XCTAssertFalse("\(e)".contains("sextiotre"))
        }
    }

    func testFelAntalKolumner() {
        let kort = Fixtures.sleeps + "\n2026-10-20 23:00:00,UTC+02:00"
        XCTAssertThrowsError(try WhoopExport.parseSleeps(kort)) { e in
            XCTAssertEqual(e as? WhoopImportError, .badRowLength(file: "sleeps.csv", line: 5))
        }
    }

    func testLaddaMappUtanExportGerNil() throws {
        let tom = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tom, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tom) }
        XCTAssertNil(try WhoopExport.load(directory: tom))

        try Fixtures.cycles.write(to: tom.appendingPathComponent(WhoopExport.cyclesFile), atomically: true, encoding: .utf8)
        let export = try XCTUnwrap(try WhoopExport.load(directory: tom))
        XCTAssertEqual(export.cycles.count, 3)
        XCTAssertEqual(export.sleeps, [], "sömn och dagbok är valfria")
    }
}
