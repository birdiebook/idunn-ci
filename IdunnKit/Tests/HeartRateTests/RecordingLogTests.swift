import Foundation
import XCTest
@testable import HeartRate

// Påhittade notiser. Tiderna är hela och halva sekunder, så att de går exakt
// genom Date och tillbaka.

final class RecordingLogTests: XCTestCase {
    private let t0 = 1_760_300_000.0

    private func sample(_ dt: Double, _ bpm: Int, _ rr: [Double] = [],
                        _ c: HeartRateMeasurement.SensorContact? = nil) -> HeartRateSample {
        HeartRateSample(time: Date(timeIntervalSince1970: t0 + dt), bpm: bpm, rrMilliseconds: rr, sensorContact: c)
    }

    func testEnNattFramOchTillbaka() {
        let a = sample(0, 52, [1152.34375, 1160.15625], .detected)
        let b = sample(1.5, 53)
        let c = sample(3, 0, [], .notDetected)
        var fil = RecordingLog.header(utcOffsetSeconds: 7200)
        fil.append(RecordingLog.batteryAtStart(81))
        for s in [a, b, c] { fil.append(RecordingLog.line(s)) }
        fil.append(RecordingLog.batteryAtEnd(74))
        fil.append(RecordingLog.stopped(at: Date(timeIntervalSince1970: t0 + 10)))

        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.recording.samples, [a, b, c])
        XCTAssertEqual(ut.recording.batteryAtStart, 81)
        XCTAssertEqual(ut.recording.batteryAtEnd, 74)
        XCTAssertEqual(ut.utcOffsetSeconds, 7200)
        XCTAssertEqual(ut.stopped, Date(timeIntervalSince1970: t0 + 10))
        XCTAssertEqual(ut.skippedLines, 0)
    }

    func testEnRadPerHändelse() {
        let rad = RecordingLog.line(sample(0, 60, [1000]))
        XCTAssertEqual(rad.last, 0x0A)
        XCTAssertEqual(rad.filter { $0 == 0x0A }.count, 1, "JSON-raden får inte bära egna radbrytningar")
    }

    func testHalvskrivenSistaRadEfterKrasch() {
        var fil = RecordingLog.header(utcOffsetSeconds: 0)
        fil.append(RecordingLog.line(sample(0, 50, [1200])))
        let tredje = RecordingLog.line(sample(1, 51, [1180]))
        fil.append(tredje.prefix(tredje.count / 2))

        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.recording.samples.count, 1)
        XCTAssertEqual(ut.skippedLines, 1)
        XCTAssertNil(ut.stopped)
    }

    func testÅterupptagenNattBehållerFörstaStartOchSistaSlut() {
        // iOS stängde appen; nästa start läste batteriet igen och skrev en ny rad.
        var fil = RecordingLog.batteryAtStart(90)
        fil.append(RecordingLog.batteryAtEnd(88))
        fil.append(RecordingLog.batteryAtStart(85))
        fil.append(RecordingLog.batteryAtEnd(80))
        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.recording.batteryAtStart, 90)
        XCTAssertEqual(ut.recording.batteryAtEnd, 80)
    }

    func testRaderUrOrdningSorteras() {
        var fil = RecordingLog.line(sample(5, 50))
        fil.append(RecordingLog.line(sample(1, 51)))
        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.recording.samples.map(\.bpm), [51, 50])
    }

    func testFlaggbytenFramOchTillbaka() {
        // METOD M15.
        let s = HeartRateSample(time: Date(timeIntervalSince1970: t0), bpm: 60, rrMilliseconds: [1000],
                                sensorContact: .detected, flags: 0x16)
        XCTAssertEqual(RecordingLog.decode(RecordingLog.line(s)).recording.samples, [s])
    }

    func testOtolkadNotisRäknasMenBärIngetVärde() {
        // METOD M15: raden har bara tiden, och natten får ingen notis av den.
        var fil = RecordingLog.line(sample(0, 50, [1200]))
        let trasig = RecordingLog.unreadable(at: Date(timeIntervalSince1970: t0 + 1))
        let text = String(decoding: trasig, as: UTF8.self)
        XCTAssertTrue(text.contains("\"trasig\":true"), text)
        XCTAssertFalse(text.contains("bpm") || text.contains("rr"), text)
        fil.append(trasig)
        fil.append(RecordingLog.unreadable(at: Date(timeIntervalSince1970: t0 + 2)))
        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.unreadableNotifications, 2)
        XCTAssertEqual(ut.recording.samples.count, 1)
        XCTAssertEqual(ut.skippedLines, 0)
    }

    func testMärkenFramOchTillbakaUtanAttRöraNatten() {
        // METOD M20: ett märke är tid och ord, ingen notis och ingen trasig rad.
        var fil = RecordingLog.header(utcOffsetSeconds: 0)
        fil.append(RecordingLog.line(sample(0, 50, [1200])))
        fil.append(RecordingLog.marker("skak", at: Date(timeIntervalSince1970: t0 + 1.5)))
        fil.append(RecordingLog.line(sample(2, 51, [1180])))
        fil.append(RecordingLog.marker("still", at: Date(timeIntervalSince1970: t0 + 3)))
        let rad = String(decoding: RecordingLog.marker("kyl", at: Date(timeIntervalSince1970: t0)), as: UTF8.self)
        XCTAssertTrue(rad.contains("\"marke\":\"kyl\""), rad)
        XCTAssertFalse(rad.contains("bpm"), rad)

        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.recording.samples.count, 2)
        XCTAssertEqual(ut.skippedLines, 0)
        XCTAssertEqual(ut.unreadableNotifications, 0)
        XCTAssertEqual(ut.markers, [
            RecordingLog.Marker(time: Date(timeIntervalSince1970: t0 + 1.5), label: "skak"),
            RecordingLog.Marker(time: Date(timeIntervalSince1970: t0 + 3), label: "still"),
        ])
    }

    /// METOD M43. Länkens rader: ord, felkod och text, bredvid märkena men
    /// inga märken, och natten rörs inte.
    func testLänkradernaFramOchTillbaka() {
        var fil = RecordingLog.header(utcOffsetSeconds: 0)
        fil.append(RecordingLog.line(sample(0, 50, [1200])))
        fil.append(RecordingLog.marker("rotera x", at: Date(timeIntervalSince1970: t0 + 1)))
        fil.append(RecordingLog.link(.disconnected, code: 6, text: "Påhittad feltext.",
                                     at: Date(timeIntervalSince1970: t0 + 2)))
        fil.append(RecordingLog.link(.connected, at: Date(timeIntervalSince1970: t0 + 3)))
        fil.append(RecordingLog.link(.imuSilent, at: Date(timeIntervalSince1970: t0 + 4)))
        let rad = String(decoding: RecordingLog.link(.disconnected, code: 6, text: "x",
                                                     at: Date(timeIntervalSince1970: t0)), as: UTF8.self)
        XCTAssertTrue(rad.contains("\"lank\":\"frånkopplad\""), rad)
        XCTAssertTrue(rad.contains("\"fel\":6"), rad)
        XCTAssertFalse(rad.contains("marke"), rad)
        let utanFel = String(decoding: RecordingLog.link(.connected, at: Date(timeIntervalSince1970: t0)), as: UTF8.self)
        XCTAssertFalse(utanFel.contains("fel"), utanFel)
        XCTAssertFalse(utanFel.contains("text"), utanFel)

        let ut = RecordingLog.decode(fil)
        XCTAssertEqual(ut.skippedLines, 0)
        XCTAssertEqual(ut.recording.samples.count, 1)
        XCTAssertEqual(ut.markers.map(\.label), ["rotera x"])
        XCTAssertEqual(ut.links, [
            RecordingLog.LinkEntry(time: Date(timeIntervalSince1970: t0 + 2), word: "frånkopplad", code: 6,
                                   text: "Påhittad feltext."),
            RecordingLog.LinkEntry(time: Date(timeIntervalSince1970: t0 + 3), word: "ansluten"),
            RecordingLog.LinkEntry(time: Date(timeIntervalSince1970: t0 + 4), word: "imu tyst"),
        ])
        XCTAssertEqual(RecordingLog.Link.allCases.map(\.rawValue),
                       ["ansluten", "tjänster klara", "frånkopplad", "anslutning misslyckades", "imu tyst", "imu igen",
                        "appen startad", "väckt av iOS", "i förgrunden", "i bakgrunden", "hämtning klar",
                        "hämtning stoppad", "nätter räknade", "start uppskjuten", "bluetooth", "ansluter",
                        "minnesvarning", "avslutas"])
        let lång = RecordingLog.decode(RecordingLog.link(.failedToConnect, code: 1, text: String(repeating: "y", count: 500),
                                                         at: Date(timeIntervalSince1970: t0)))
        XCTAssertEqual(lång.links.first?.text?.count, 120)
    }

    func testMärketKortas() {
        let långt = String(repeating: "x", count: 100)
        let ut = RecordingLog.decode(RecordingLog.marker(långt, at: Date(timeIntervalSince1970: t0)))
        XCTAssertEqual(ut.markers.first?.label.count, 32)
    }

    func testTomFil() {
        let ut = RecordingLog.decode(Data())
        XCTAssertTrue(ut.recording.samples.isEmpty)
        XCTAssertEqual(ut.skippedLines, 0)
        XCTAssertNil(ut.utcOffsetSeconds)
    }
}
