import Foundation
import XCTest
@testable import HeartRate

// Notiserna nedan är påhittade och skrivna byte för byte efter Bluetooth SIG:s
// Heart Rate Service 1.0 (METOD M1). Ingen kommer från ett riktigt band.

final class HeartRateMeasurementTests: XCTestCase {
    func testPulsSomEnByteUtanRR() throws {
        let m = try XCTUnwrap(HeartRateMeasurement(bytes: [0x00, 72]))
        XCTAssertEqual(m.bpm, 72)
        XCTAssertNil(m.sensorContact)
        XCTAssertEqual(m.rrMilliseconds, [])
    }

    func testPulsSomTvåByteLittleEndian() throws {
        // 0x0104 = 260: den höga byten måste läsas, och i rätt ordning.
        let m = try XCTUnwrap(HeartRateMeasurement(bytes: [0x01, 0x04, 0x01]))
        XCTAssertEqual(m.bpm, 260)
    }

    func testSensorkontakt() {
        XCTAssertEqual(HeartRateMeasurement(bytes: [0x06, 60])?.sensorContact, .detected)
        XCTAssertEqual(HeartRateMeasurement(bytes: [0x04, 60])?.sensorContact, .notDetected)
        // Bit 1 utan bit 2: kontakt stöds inte, då finns inget att säga.
        XCTAssertNotNil(HeartRateMeasurement(bytes: [0x02, 60]))
        XCTAssertNil(HeartRateMeasurement(bytes: [0x02, 60])?.sensorContact)
    }

    func testRRIEnheten1Genom1024Sekund() throws {
        // 0x0400 = 1024 → exakt 1000 ms; 0x0333 = 819 → 819 × 1000 / 1024 ms.
        let m = try XCTUnwrap(HeartRateMeasurement(bytes: [0x10, 60, 0x00, 0x04, 0x33, 0x03]))
        XCTAssertEqual(m.bpm, 60)
        XCTAssertEqual(m.rrMilliseconds, [1000, 799.8046875])
        XCTAssertEqual(m.rrMilliseconds.map { HeartRateMeasurement.rrUnits(milliseconds: $0) }, [1024, 819])
    }

    func testFlaggbytenFöljerMed() throws {
        // METOD M15: flaggorna sparas för diagnosen, och följer med till notisen.
        let m = try XCTUnwrap(HeartRateMeasurement(bytes: [0x16, 60, 0x00, 0x04]))
        XCTAssertEqual(m.flags, 0x16)
        XCTAssertEqual(HeartRateSample(m, at: Date(timeIntervalSince1970: 0)).flags, 0x16)
        XCTAssertNil(HeartRateMeasurement(bpm: 60).flags)
    }

    func testEnergifältetHoppasÖver() throws {
        // Flaggor: puls uint16, kontakt, energi, RR. Energin 0xBEEF får inte bli ett RR.
        let m = try XCTUnwrap(HeartRateMeasurement(bytes: [0x1F, 0x3C, 0x00, 0xEF, 0xBE, 0x00, 0x04]))
        XCTAssertEqual(m.bpm, 60)
        XCTAssertEqual(m.sensorContact, .detected)
        XCTAssertEqual(m.rrMilliseconds, [1000])
    }

    func testRRFlaggaUtanIntervallGerTomLista() throws {
        let m = try XCTUnwrap(HeartRateMeasurement(bytes: [0x10, 55]))
        XCTAssertEqual(m.rrMilliseconds, [])
    }

    func testAvklippteNotiserGerNil() {
        XCTAssertNil(HeartRateMeasurement(bytes: []))
        XCTAssertNil(HeartRateMeasurement(bytes: [0x00]), "flaggor utan puls")
        XCTAssertNil(HeartRateMeasurement(bytes: [0x01, 0x48]), "uint16-puls med en byte")
        XCTAssertNil(HeartRateMeasurement(bytes: [0x08, 72, 0x01]), "energifältet avklippt")
        XCTAssertNil(HeartRateMeasurement(bytes: [0x10, 72, 0x00, 0x04, 0x33]), "udda byte bland RR")
    }

    func testDataSkivaMedFörskjutetIndex() throws {
        // CoreBluetooth kan lämna en skiva vars första index inte är 0.
        let skiva = Data([0xFF, 0x10, 60, 0x00, 0x04]).dropFirst()
        let m = try XCTUnwrap(HeartRateMeasurement(data: skiva))
        XCTAssertEqual(m.bpm, 60)
        XCTAssertEqual(m.rrMilliseconds, [1000])
    }

    func testSkräpKrascharAldrig() {
        let hel: [UInt8] = [0x1F, 0x3C, 0x00, 0xEF, 0xBE, 0x00, 0x04, 0x33, 0x03]
        for n in 0..<hel.count { _ = HeartRateMeasurement(bytes: Array(hel.prefix(n))) }
        var r = Seeded(7)
        for _ in 0..<20_000 {
            let bytes = (0..<Int(r.next() % 24)).map { _ in UInt8(truncatingIfNeeded: r.next()) }
            if let m = HeartRateMeasurement(bytes: bytes), bytes[0] & 0x10 != 0 {
                let huvud = 1 + (bytes[0] & 0x01 != 0 ? 2 : 1) + (bytes[0] & 0x08 != 0 ? 2 : 0)
                XCTAssertEqual(m.rrMilliseconds.count, (bytes.count - huvud) / 2)
            }
        }
    }
}

final class NightRecordingTests: XCTestCase {
    func testNotisernaHamnarITidsordning() {
        var n = NightRecording()
        let t = Date(timeIntervalSince1970: NightFixtures.t0)
        n.append(HeartRateMeasurement(bpm: 60, rrMilliseconds: [1000]), at: t)
        n.append(HeartRateMeasurement(bpm: 62), at: t.addingTimeInterval(2))
        n.append(HeartRateMeasurement(bpm: 61), at: t.addingTimeInterval(1))
        XCTAssertEqual(n.samples.map(\.bpm), [60, 61, 62])
        XCTAssertEqual(n.span, 2)
    }

    func testKodasOchAvkodasOförändrad() throws {
        var n = NightRecording(batteryAtStart: 80)
        n.append(HeartRateSample(time: Date(timeIntervalSince1970: NightFixtures.t0), bpm: 58,
                                 rrMilliseconds: [1000, 799.8046875], sensorContact: .detected))
        n.append(HeartRateSample(time: Date(timeIntervalSince1970: NightFixtures.t0 + 1), bpm: 57))
        n.batteryAtEnd = 71
        let tillbaka = try JSONDecoder().decode(NightRecording.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(tillbaka, n)
    }
}
