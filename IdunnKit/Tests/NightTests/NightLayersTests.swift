import Foundation
import XCTest
import HeartRate
import WhoopFrames
import DemoData
@testable import Night

// METOD M32. Lagren på Nattens kurva (PLAN.md R2) på påhittade nätter
// (DemoSleep, DemoK18Nights): rörelse och hudtemperatur per minut, tomma
// minuter, glappen med orsak och sömnperioden. Inga värden kommer från ett
// riktigt band.

final class NightLayersTests: XCTestCase {

    /// Delbart med 60 och med 5: nattens faser börjar på hel minut.
    static let t0 = 1_699_999_980
    static let minute = 60

    /// En natt med känd form, i minuter från `t0`: uppe 10, sömn 60, uppe 3
    /// (armen i rörelse, inga slag), sömn 60, 5 utan K18, sömn 60, uppe 10.
    /// Slagen kommer i varje post utom i de tre rörliga minuterna; hudtemperaturen
    /// stiger 0,1 °C per minut (0…0,9) och börjar om.
    struct Natt {
        var series: K18Series
        var sleep: SleepPeriod
        var result: NightResult
        /// Sekunder: de tre rörliga minuterna och minuterna utan K18.
        var rörelse: ClosedRange<Int>
        var utanK18: ClosedRange<Int>
    }

    func natt() throws -> Natt {
        let m = Self.minute
        let phases: [DemoSleep.Phase] = [
            .active(seconds: 10 * m),
            .still(seconds: 60 * m),
            .active(seconds: 3 * m),
            .still(seconds: 60 * m),
            .gap(seconds: 5 * m),
            .still(seconds: 60 * m),
            .active(seconds: 10 * m),
        ]
        let rörelseFrån: Int = Self.t0 + 70 * m
        let rörelseTill: Int = Self.t0 + 73 * m
        let glappFrån: Int = Self.t0 + 133 * m
        let glappTill: Int = Self.t0 + 138 * m
        let slut: Int = Self.t0 + 208 * m
        var records: [K18Record] = DemoSleep.records(start: Self.t0, phases: phases, seed: 7)
        for i in records.indices {
            let t: Int = records[i].time
            let sömn: Bool = t >= Self.t0 + 10 * m && t < slut - 10 * m
            if sömn && !(t >= rörelseFrån && t < rörelseTill) {
                records[i].rr = [1000 + Int((40 * sin(Double(t) / 9)).rounded())]
                records[i].pulse = 60
            }
            records[i].skinTemperature = 33 + Double(((t - Self.t0) / m) % 10) * 0.1
        }
        let series = K18Series(records: records)
        let p = try XCTUnwrap(SleepDetection.detect(series, from: Date(timeIntervalSince1970: Double(Self.t0)),
                                                    to: Date(timeIntervalSince1970: Double(slut))))
        let r = K18Night.analyze(series, sleep: p, utcOffsetSeconds: 0)
        return Natt(series: series, sleep: p, result: r,
                    rörelse: rörelseFrån...rörelseTill, utanK18: glappFrån...glappTill)
    }

    func summa(_ x: [ClosedRange<TimeInterval>]) -> Double {
        x.reduce(0.0) { (s: Double, r: ClosedRange<TimeInterval>) -> Double in s + (r.upperBound - r.lowerBound) }
    }

    // MARK: Tidsaxeln

    func testMinutrarnaLiggerPåSammaTidSomPulsen() throws {
        let n = try natt()
        let l = try XCTUnwrap(n.result.layers)
        let c = try XCTUnwrap(n.result.curve)
        XCTAssertFalse(l.minutes.isEmpty)
        for (a, b) in zip(l.minutes, l.minutes.dropFirst()) {
            XCTAssertEqual(b.start - a.start, NightCurve.minuteSeconds, "en minut i taget, inga hål")
        }
        let lager: Set<Double> = Set(l.minutes.map(\.start))
        for m in c.minutes {
            XCTAssertTrue(lager.contains(m.start), "pulsens minut \(m.start) finns också i lagren")
        }
        XCTAssertLessThanOrEqual(l.start, c.start)
        XCTAssertGreaterThanOrEqual(l.end, c.end)
        XCTAssertLessThanOrEqual(l.start, Double(n.sleep.onset))
        XCTAssertGreaterThanOrEqual(l.end, Double(n.sleep.wake))
    }

    func testTidenÄrUnixtidOchBerorInteAvZonen() throws {
        let n = try natt()
        let a = K18Night.analyze(n.series, sleep: n.sleep, utcOffsetSeconds: 0)
        let b = K18Night.analyze(n.series, sleep: n.sleep, utcOffsetSeconds: 7200)
        XCTAssertNotNil(a.layers)
        XCTAssertTrue(a.layers == b.layers, "zonen avgör uppvakningsdagen, inte lagrens tid")
    }

    // MARK: Rörelse och temperatur, tomma minuter

    func testMinuterUtanK18ÄrTommaInteNoll() throws {
        let n = try natt()
        let l = try XCTUnwrap(n.result.layers)
        let har: Set<Int> = Set(n.series.records.map { $0.time / 60 })
        var tomma = 0
        for m in l.minutes {
            let finns: Bool = har.contains(Int(m.start) / 60)
            XCTAssertEqual(m.skinTemperature != nil, finns, "temperatur bara där K18 finns, \(m.start)")
            if !finns {
                tomma += 1
                XCTAssertNil(m.movement, "tom minut är inte noll")
                XCTAssertNil(m.skinTemperature)
            }
        }
        XCTAssertGreaterThanOrEqual(tomma, 5, "de fem minuterna utan K18")
        let c = try XCTUnwrap(l.coverage)
        XCTAssertLessThan(c, 1)
        XCTAssertGreaterThan(c, 0.9)
    }

    func testRörelsenOchTemperaturenÄrMinutensEgna() throws {
        let n = try natt()
        let l = try XCTUnwrap(n.result.layers)
        let facit: [Int: K18Series.Minute] = Dictionary(uniqueKeysWithValues: n.series.minutes.map { ($0.minute, $0) })
        var jämförda = 0
        for m in l.minutes {
            guard let f = facit[Int(m.start) / 60] else { continue }
            XCTAssertEqual(m.movement, f.movement)
            XCTAssertEqual(m.skinTemperature, f.skinTemperature)
            jämförda += 1
        }
        XCTAssertGreaterThan(jämförda, 150)
        // En stilla minut (minut 25: 33,5 °C) och en rörlig (minut 71).
        let still = try XCTUnwrap(l.minutes.first { Int($0.start) == Self.t0 + 25 * Self.minute })
        XCTAssertEqual(try XCTUnwrap(still.skinTemperature), 33.5, accuracy: 1e-9)
        XCTAssertLessThan(try XCTUnwrap(still.movement), NightLayers.movementThreshold)
        let rör = try XCTUnwrap(l.minutes.first { Int($0.start) == Self.t0 + 71 * Self.minute })
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(rör.movement), NightLayers.movementThreshold)
        XCTAssertEqual(l.minute(at: still.mid), still)
        XCTAssertEqual(l.minute(at: still.start), still)
        XCTAssertNil(l.minute(at: (l.minutes.first?.start ?? 0) - 1))
        XCTAssertNil(l.minute(at: l.end + 120))
        let tom = try XCTUnwrap(l.minute(at: Double(n.utanK18.lowerBound + 90)))
        XCTAssertNil(tom.movement, "en tryckning i ett glapp ger inget värde")
        XCTAssertNil(tom.skinTemperature)
    }

    // MARK: Glappen med orsak

    func testGlappetMedRörelseFärgasEfterRörelseOchEttK18GlappÄrOkänt() throws {
        let n = try natt()
        let l = try XCTUnwrap(n.result.layers)
        let rörelse = l.gaps.filter { $0.cause == .movement }
        let okänd = l.gaps.filter { $0.cause == .unknown }
        XCTAssertEqual(rörelse.count, 1, "armen i rörelse: \(l.gaps)")
        let r = try XCTUnwrap(rörelse.first)
        XCTAssertEqual(r.start, Double(n.rörelse.lowerBound), accuracy: 60)
        XCTAssertEqual(r.end, Double(n.rörelse.upperBound), accuracy: 60)

        let k = okänd.filter { $0.start > Double(Self.t0 + 120 * Self.minute) }
        XCTAssertEqual(k.count, 1, "fem minuter utan K18: \(l.gaps)")
        let g = try XCTUnwrap(k.first)
        XCTAssertEqual(g.start, Double(n.utanK18.lowerBound), accuracy: 60)
        XCTAssertEqual(g.end, Double(n.utanK18.upperBound), accuracy: 60)

        for (a, b) in zip(l.gaps, l.gaps.dropFirst()) {
            XCTAssertLessThan(a.end, b.start, "glappen är i tidsordning och rör inte varandra")
        }
    }

    func testOrsakenPerGlapp() {
        let g = NightLayers.movementThreshold
        let minuter: [NightLayers.Minute] = [
            .init(start: 0, movement: 0.5, skinTemperature: 33),
            .init(start: 60, movement: 0.001, skinTemperature: 33),
            .init(start: 120, movement: nil, skinTemperature: nil),
            .init(start: 180, movement: g, skinTemperature: 33),
        ]
        XCTAssertEqual(g, SkinTemperature.stillMovement, "samma gräns som stilla minuter (METOD M25)")
        XCTAssertEqual(NightLayers.cause(of: 0...59, minutes: minuter), .movement)
        XCTAssertEqual(NightLayers.cause(of: 60...119, minutes: minuter), .unknown, "stilla minut")
        XCTAssertEqual(NightLayers.cause(of: 0...119, minutes: minuter), .movement, "hälften räcker")
        XCTAssertEqual(NightLayers.cause(of: 60...181, minutes: minuter), .movement, "en av två minuter med tal: hälften")
        XCTAssertEqual(NightLayers.cause(of: 120...179, minutes: minuter), .unknown, "minuten utan K18 säger inget")
        XCTAssertEqual(NightLayers.cause(of: 180...239, minutes: minuter), .movement, "exakt på gränsen är rörelse")
        XCTAssertEqual(NightLayers.cause(of: 600...660, minutes: minuter), .unknown, "ingen minut alls")
    }

    // MARK: Sömnperioden

    func testSömnenOchDeVaknaStunderna() throws {
        let n = try natt()
        let l = try XCTUnwrap(n.result.layers)
        // METOD M37. Perioden i resultatet är förfinad ur epokerna: samma insomning och uppvaknande, men sömn,
        // vaken och glapp inom den kommer ur modellen.
        let s = try XCTUnwrap(n.result.sleep)
        XCTAssertEqual(s.onset, n.sleep.onset)
        XCTAssertEqual(s.wake, n.sleep.wake)
        XCTAssertEqual(l.period.lowerBound, Double(s.onset))
        XCTAssertEqual(l.period.upperBound, Double(s.wake))
        XCTAssertEqual(summa(l.asleep), Double(s.asleepSeconds), accuracy: 0.5,
                       "sömnbitarna är exakt det som mättes som sömn")
        XCTAssertEqual(summa(l.awake), Double(s.awakeSeconds), accuracy: 0.5)
        XCTAssertEqual(s.asleepSeconds + s.awakeSeconds + s.gapSeconds, s.wake - s.onset)
        let stadier = try XCTUnwrap(n.result.stages)
        XCTAssertEqual(Double(s.asleepSeconds) / 60,
                       stadier.minutes(.light) + stadier.minutes(.deep) + stadier.minutes(.rem), accuracy: 1e-9)
        XCTAssertFalse(l.stages.isEmpty, "stadierna följer med i lagren")
        for a in l.asleep {
            XCTAssertGreaterThanOrEqual(a.lowerBound, l.period.lowerBound)
            XCTAssertLessThanOrEqual(a.upperBound, l.period.upperBound)
        }
        for (a, b) in zip(l.asleep, l.asleep.dropFirst()) {
            XCTAssertLessThan(a.upperBound, b.lowerBound, "ett avbrott mellan sömnbitarna")
        }
        // De tre rörliga minuterna och minuterna utan K18 är avbrott i sömnen.
        let mitt: Double = Double(Self.t0 + 71 * Self.minute)
        XCTAssertTrue(l.isAwake(mitt))
        XCTAssertFalse(l.asleep.contains { $0.contains(mitt) })
        let glapp: Double = Double(Self.t0 + 135 * Self.minute)
        XCTAssertFalse(l.asleep.contains { $0.contains(glapp) })
        XCTAssertFalse(l.isAwake(glapp), "ett glapp i K18 är varken sömn eller vaken")
        let sömn: Double = Double(Self.t0 + 40 * Self.minute)
        XCTAssertTrue(l.asleep.contains { $0.contains(sömn) })
        XCTAssertFalse(l.isAwake(sömn))
    }

    func testEnStilNattHarEnSömnbitOchIngenVakenStund() throws {
        let m = Self.minute
        let records = DemoSleep.records(start: Self.t0, phases: [.active(seconds: 10 * m), .still(seconds: 90 * m),
                                                                .active(seconds: 10 * m)], seed: 3)
        var med: [K18Record] = records
        for i in med.indices where med[i].time >= Self.t0 + 10 * m && med[i].time < Self.t0 + 100 * m {
            med[i].rr = [1000 + Int((40 * sin(Double(med[i].time) / 9)).rounded())]
        }
        let series = K18Series(records: med)
        let p = try XCTUnwrap(SleepDetection.detect(series, from: Date(timeIntervalSince1970: Double(Self.t0)),
                                                    to: Date(timeIntervalSince1970: Double(Self.t0 + 110 * m))))
        let l = try XCTUnwrap(K18Night.analyze(series, sleep: p, utcOffsetSeconds: 0).layers)
        XCTAssertEqual(l.asleep.count, 1)
        XCTAssertTrue(l.awake.isEmpty)
        XCTAssertEqual(l.asleep.first?.lowerBound, l.period.lowerBound)
        // METOD M37. En rest kortare än en epok (30 s) i slutet av perioden är glapp, inte sömn.
        XCTAssertEqual(try XCTUnwrap(l.asleep.first).upperBound, l.period.upperBound, accuracy: 30)
        XCTAssertLessThanOrEqual(try XCTUnwrap(l.asleep.first).upperBound, l.period.upperBound)
        XCTAssertEqual(try XCTUnwrap(l.coverage), 1, accuracy: 1e-9)
        XCTAssertTrue(l.gaps.isEmpty, "slag i varje minut: inga glapp \(l.gaps)")
    }

    // MARK: En påhittad natt ur DemoK18Nights, och de gamla inspelningarna

    func testEnPåhittadNattHarTommaMinuterVidGlappet() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
        let series = K18Series(records: n.records)
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let r = try XCTUnwrap(K18Night.analyze(series, wakeDay: dag, startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        let l = try XCTUnwrap(r.layers)
        let har: Set<Int> = Set(series.records.map { $0.time / 60 })
        var tomma = 0
        for m in l.minutes where !har.contains(Int(m.start) / 60) {
            tomma += 1
            XCTAssertNil(m.movement)
            XCTAssertNil(m.skinTemperature)
        }
        XCTAssertGreaterThanOrEqual(tomma, 2, "glappet på 3–7 minuter")
        XCTAssertTrue(l.gaps.contains { $0.cause == .unknown }, "glappet syns som glapp")
        XCTAssertEqual(r.layers?.period.lowerBound, Double(r.sleep?.onset ?? -1))
    }

    func testEnPåhittadNattMedRörelseHarEttGlappMedRörelseSomOrsak() throws {
        let n = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false, movementBout: true)
        let series = K18Series(records: n.records)
        let dag = WakeDay(Date(timeIntervalSince1970: Double(n.wake)), utcOffsetSeconds: n.utcOffsetSeconds)
        let r = try XCTUnwrap(K18Night.analyze(series, wakeDay: dag, startOffsetSeconds: n.utcOffsetSeconds,
                                               endOffsetSeconds: n.utcOffsetSeconds))
        let l = try XCTUnwrap(r.layers)
        let rörelse = l.gaps.filter { $0.cause == .movement }
        XCTAssertEqual(rörelse.count, 1, "fyra minuter med armen i rörelse: \(l.gaps)")
        let g = try XCTUnwrap(rörelse.first)
        XCTAssertGreaterThanOrEqual(g.end - g.start, 120)
        XCTAssertLessThanOrEqual(g.end - g.start, 360)
        XCTAssertGreaterThanOrEqual(g.start, l.period.lowerBound)
        XCTAssertLessThanOrEqual(g.end, l.period.upperBound)
        XCTAssertTrue(l.gaps.contains { $0.cause == .unknown }, "glappet i K18 har okänd orsak")
        XCTAssertTrue(l.isAwake((g.start + g.end) / 2), "armen i rörelse är en vaken stund")
    }

    func testGamlaInspelningarHarIngaLager() {
        let n = DemoK18Nights.night(daysBeforeLast: 1, shortGaps: false)
        var rec = NightRecording()
        for x in n.measurements() where Int(x.time.timeIntervalSince1970) < n.onset + 3_600 {
            rec.append(x.measurement, at: x.time)
        }
        let r = NightResult.fromNotifications(rec, utcOffsetSeconds: n.utcOffsetSeconds)
        XCTAssertEqual(r.source, .notification)
        XCTAssertNil(r.layers)
    }

    /// BESLUT B141. Stunderna per stadium: spann som möts blir en stund, ett glapp gör två, och ett stadium som
    /// saknas ger inget.
    func testStundernaRäknasPerStadiumOchSpannSomMötsÄrEnStund() {
        let spann: [NightLayers.StageSpan] = [
            NightLayers.StageSpan(start: 0, end: 600, stage: .light, certainty: 2),
            NightLayers.StageSpan(start: 600, end: 1800, stage: .deep, certainty: 2),
            NightLayers.StageSpan(start: 1800, end: 2100, stage: .deep, certainty: 1),
            NightLayers.StageSpan(start: 2100, end: 2400, stage: .light, certainty: 2),
            NightLayers.StageSpan(start: 3000, end: 3300, stage: .deep, certainty: 2),
        ]
        let l = NightLayers.Layers(start: 0, end: 3300, minutes: [], gaps: [], period: 0...3300, asleep: [],
                                   awake: [], coverage: nil, stages: spann)
        XCTAssertEqual(l.stunder(.deep)?.antal, 2)
        XCTAssertEqual(l.stunder(.deep)?.längst, 1500)
        XCTAssertEqual(l.stunder(.light)?.antal, 2)
        XCTAssertEqual(l.stunder(.light)?.längst, 600)
        XCTAssertNil(l.stunder(.rem))
    }
}
