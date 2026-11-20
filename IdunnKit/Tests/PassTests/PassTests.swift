import Foundation
import XCTest
import HeartRate
@testable import Pass

// Alla prov nedan är påhittade (inga riktiga pulsvärden). Tiderna räknas från en
// fast nollpunkt, så att varje sekund går att peka ut.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func tid(_ s: Double) -> Date { t0.addingTimeInterval(s) }

private func puls(_ bpm: Int, kontakt: HeartRateMeasurement.SensorContact? = nil) -> HeartRateMeasurement {
    HeartRateMeasurement(bpm: bpm, sensorContact: kontakt)
}

/// Ett pass med prov varje sekund: `bpm(sekund)` för sekund 0…`till`.
private func passMedProv(stopp: Double?, till: Double, bpm: (Int) -> Int) -> Pass {
    var p = Pass(start: t0, stop: stopp.map(tid))
    for s in 0...Int(till) {
        p.samples.append(PassSample(t: tid(Double(s)), bpm: bpm(s)))
    }
    return p
}

final class PassStatistikTests: XCTestCase {
    func testLägstaSnittHögstaGällerBaraDenAktivaDelen() throws {
        // 0…59 s: 80, 90, 100 upprepade; efter stopp (60 s) sjunker pulsen och får inte påverka talen.
        var p = Pass(start: t0, stop: tid(59))
        for s in 0..<60 { p.samples.append(PassSample(t: tid(Double(s)), bpm: 80 + (s % 3) * 10)) }
        for s in 60..<120 { p.samples.append(PassSample(t: tid(Double(s)), bpm: 40)) }
        XCTAssertEqual(p.minBpm, 80)
        XCTAssertEqual(p.maxBpm, 100)
        XCTAssertEqual(try XCTUnwrap(p.averageBpm), 90, accuracy: 1e-9)
    }

    func testProvetVidStoppFinnsMedIAktivDelOchEfterdel() {
        var p = Pass(start: t0, stop: tid(10))
        p.samples = [PassSample(t: tid(5), bpm: 100), PassSample(t: tid(10), bpm: 120), PassSample(t: tid(15), bpm: 110)]
        XCTAssertEqual(p.activeSamples.map(\.bpm), [100, 120])
        XCTAssertEqual(p.afterSamples.map(\.bpm), [120, 110])
        XCTAssertEqual(p.maxBpm, 120)
    }

    func testUtanStoppGällerAllaProv() throws {
        var p = Pass(start: t0)
        p.samples = [PassSample(t: tid(1), bpm: 70), PassSample(t: tid(2), bpm: 90)]
        XCTAssertEqual(p.minBpm, 70)
        XCTAssertEqual(p.maxBpm, 90)
        XCTAssertEqual(try XCTUnwrap(p.averageBpm), 80, accuracy: 1e-9)
        XCTAssertEqual(p.afterSamples, [])
    }

    func testUtanProvGerNil() {
        let p = Pass(start: t0, stop: tid(30))
        XCTAssertNil(p.minBpm)
        XCTAssertNil(p.maxBpm)
        XCTAssertNil(p.averageBpm)
        XCTAssertNil(p.pulseAtStop)
        XCTAssertEqual(p.duration, 30)
    }

    func testSnittetÄrMedelAvProvenInteTidsviktat() throws {
        var p = Pass(start: t0, stop: tid(100))
        // Tre prov, ojämnt fördelade i tid: medlet av proven, 60 + 60 + 120 = 240 / 3 = 80.
        p.samples = [PassSample(t: tid(1), bpm: 60), PassSample(t: tid(2), bpm: 60), PassSample(t: tid(90), bpm: 120)]
        XCTAssertEqual(try XCTUnwrap(p.averageBpm), 80, accuracy: 1e-9)
    }

    func testLängden() {
        XCTAssertEqual(Pass(start: t0, stop: tid(1234)).duration, 1234)
        // Ej stoppat: till sista provet.
        var p = Pass(start: t0)
        XCTAssertEqual(p.duration, 0)
        p.samples = [PassSample(t: tid(10), bpm: 70), PassSample(t: tid(42), bpm: 71)]
        XCTAssertEqual(p.duration, 42)
    }
}

final class PassÅterhämtningTests: XCTestCase {
    func testPulsenVidStoppOchEfter1_2Och5Minuter() throws {
        // Pulsen faller 1 slag per 10 s från 150 vid stopp (sekund 600).
        let p = passMedProv(stopp: 600, till: 1200) { s in s <= 600 ? 150 : max(50, 150 - (s - 600) / 10) }
        XCTAssertEqual(p.pulseAtStop, 150)
        XCTAssertEqual(p.pulse(after: 60), 144)
        XCTAssertEqual(p.pulse(after: 120), 138)
        XCTAssertEqual(p.pulse(after: 300), 120)
        XCTAssertEqual(p.drop(after: 60), 6)
        XCTAssertEqual(p.drop(after: 300), 30)
        XCTAssertEqual(p.recovery.map(\.seconds), [60, 120, 300])
        XCTAssertEqual(p.recovery.map(\.bpm), [144, 138, 120])
        XCTAssertEqual(p.recovery.map(\.drop), [6, 12, 30])
    }

    func testSaknasProvInomPlusMinus5SekunderBlirDetNil() {
        var p = Pass(start: t0, stop: tid(100))
        // Vid stopp: närmaste prov 6 s bort = utanför. Efter 60 s (160): ett prov 5 s bort = inom.
        p.samples = [PassSample(t: tid(94), bpm: 140), PassSample(t: tid(165), bpm: 120)]
        XCTAssertNil(p.pulseAtStop)
        XCTAssertEqual(p.pulse(after: 60), 120)
        XCTAssertNil(p.drop(after: 60), "utan pulsen vid stopp finns inget fall")
        XCTAssertNil(p.pulse(after: 120))
        XCTAssertNil(p.pulse(after: 300))
        XCTAssertEqual(p.recovery.map(\.bpm), [120, nil, nil])
    }

    func testNärmasteProvVinnerOchLikaAvståndGerDetTidigare() {
        var p = Pass(start: t0, stop: tid(100))
        p.samples = [PassSample(t: tid(97), bpm: 130), PassSample(t: tid(99), bpm: 131), PassSample(t: tid(103), bpm: 132)]
        XCTAssertEqual(p.pulseAtStop, 131)
        p.samples = [PassSample(t: tid(98), bpm: 130), PassSample(t: tid(102), bpm: 132)]
        XCTAssertEqual(p.pulseAtStop, 130)
    }

    func testUtanStoppFinnsIngenÅterhämtning() {
        let p = passMedProv(stopp: nil, till: 100) { _ in 100 }
        XCTAssertNil(p.pulseAtStop)
        XCTAssertNil(p.pulse(after: 60))
        XCTAssertEqual(p.recovery.map(\.bpm), [nil, nil, nil])
    }

    func testEfterperiodenSomInteHunnitFyllasIFårBaraDeFörstaVärdena() {
        // Stopp vid 100 s, mätt till 200 s: 1 min finns, 2 och 5 min saknas ännu.
        let p = passMedProv(stopp: 100, till: 200) { s in s <= 100 ? 120 : 100 }
        XCTAssertEqual(p.recovery.map(\.bpm), [100, nil, nil])
        XCTAssertEqual(p.recovery.map(\.drop), [20, nil, nil])
    }

    func testPulsenKanStigaEfterStoppOchFalletÄrDåNegativt() {
        let p = passMedProv(stopp: 100, till: 170) { s in s <= 100 ? 90 : 95 }
        XCTAssertEqual(p.drop(after: 60), -5)
    }
}

final class PassRecorderTests: XCTestCase {
    func testFasernaFrånStartTillKlar() throws {
        var r = PassRecorder()
        XCTAssertEqual(r.phase, .idle)
        XCTAssertFalse(r.wantsPulse)
        r.start(now: tid(0))
        XCTAssertEqual(r.phase, .running)
        XCTAssertTrue(r.wantsPulse)
        r.add(puls(100), now: tid(1))
        r.add(puls(110), now: tid(2))
        r.stop(now: tid(10))
        XCTAssertEqual(r.phase, .after)
        XCTAssertTrue(r.wantsPulse, "pulsen mäts vidare efter stopp")
        r.add(puls(90), now: tid(20))
        XCTAssertEqual(r.afterRemaining(now: tid(10)), 600)
        XCTAssertEqual(r.afterRemaining(now: tid(310)), 300)
        // Efterperioden: 600 s efter stopp.
        r.tick(now: tid(609))
        XCTAssertEqual(r.phase, .after)
        r.tick(now: tid(610))
        XCTAssertEqual(r.phase, .done)
        XCTAssertFalse(r.wantsPulse)
        let p = try XCTUnwrap(r.finished)
        XCTAssertEqual(p.start, tid(0))
        XCTAssertEqual(p.stop, tid(10))
        XCTAssertEqual(p.afterEnd, tid(610))
        XCTAssertEqual(p.samples.map(\.bpm), [100, 110, 90])
        XCTAssertEqual(p.samples.map(\.t), [tid(1), tid(2), tid(20)])
        XCTAssertNil(r.afterRemaining(now: tid(700)))
    }

    func testFinishNowAvslutarEfterperiodenTidigt() {
        var r = PassRecorder()
        r.start(now: tid(0))
        r.stop(now: tid(30))
        r.finishNow(now: tid(95))
        XCTAssertEqual(r.phase, .done)
        XCTAssertEqual(r.finished?.afterEnd, tid(95))
        XCTAssertFalse(r.wantsPulse)
    }

    func testFinishNowUnderPågåendePassGörInget() {
        var r = PassRecorder()
        r.start(now: tid(0))
        r.finishNow(now: tid(5))
        XCTAssertEqual(r.phase, .running)
        XCTAssertNil(r.finished)
    }

    func testStoppUtanStartOchStoppTvåGångerGörInget() {
        var r = PassRecorder()
        r.stop(now: tid(1))
        XCTAssertEqual(r.phase, .idle)
        r.start(now: tid(0))
        r.stop(now: tid(10))
        r.stop(now: tid(20))
        XCTAssertEqual(r.pass?.stop, tid(10))
    }

    func testStartMedtOchPågårGörInteOm() {
        var r = PassRecorder()
        let id = UUID()
        r.start(now: tid(0), id: id)
        r.start(now: tid(5))
        XCTAssertEqual(r.pass?.id, id)
        XCTAssertEqual(r.pass?.start, tid(0))
    }

    func testBpmNollOchIngenSensorkontaktSparasInte() {
        var r = PassRecorder()
        r.start(now: tid(0))
        r.add(puls(0), now: tid(1))
        r.add(puls(88, kontakt: .notDetected), now: tid(2))
        r.add(puls(89, kontakt: .detected), now: tid(3))
        r.add(puls(90), now: tid(4))
        XCTAssertEqual(r.pass?.samples.map(\.bpm), [89, 90])
    }

    func testProvUtanPassOchEfterKlarSparasInte() {
        var r = PassRecorder()
        r.add(puls(70), now: tid(1))
        XCTAssertNil(r.pass)
        r.start(now: tid(2))
        r.stop(now: tid(3))
        r.finishNow(now: tid(4))
        r.add(puls(75), now: tid(5))
        XCTAssertEqual(r.pass?.samples.count, 0)
    }

    func testProvSomKommerEfterEfterperiodensSlutAvslutarPassetFörstOchSparasInte() {
        var r = PassRecorder()
        r.start(now: tid(0))
        r.add(puls(100), now: tid(1))
        r.stop(now: tid(2))
        r.add(puls(80), now: tid(602))
        XCTAssertEqual(r.phase, .done)
        XCTAssertEqual(r.pass?.afterEnd, tid(602))
        XCTAssertEqual(r.pass?.samples.map(\.bpm), [100])
    }

    func testTypenKanSättasIVarjeFasOchFöljerMedPassetNärDetÄrKlart() {
        var r = PassRecorder()
        r.setKind(.bastu) // inget pass än: ingen verkan
        XCTAssertNil(r.pass)
        r.start(now: tid(0))
        r.stop(now: tid(5))
        r.setKind(.dusch)
        r.setKind(.bastu)
        r.finishNow(now: tid(6))
        XCTAssertEqual(r.finished?.kind, .bastu)
        r.setKind(nil)
        XCTAssertNil(r.finished?.kind)
    }

    func testClearGerIdleNärPassetÄrKlartMenInteUnderPågåendePass() {
        var r = PassRecorder()
        r.start(now: tid(0))
        r.clear()
        XCTAssertEqual(r.phase, .running)
        r.stop(now: tid(1))
        r.finishNow(now: tid(2))
        r.clear()
        XCTAssertEqual(r.phase, .idle)
        XCTAssertNil(r.pass)
        // Ett nytt pass efter ett färdigt.
        r.start(now: tid(10))
        XCTAssertEqual(r.phase, .running)
    }

    func testFyraTimmarUtanProvAvslutasVidSistaProvet() throws {
        var r = PassRecorder()
        r.start(now: tid(0))
        r.add(puls(100), now: tid(100))
        r.add(puls(101), now: tid(200))
        // Strax under 4 timmar efter sista provet: passet pågår fortfarande.
        r.tick(now: tid(200 + 4 * 3600 - 1))
        XCTAssertEqual(r.phase, .running)
        r.tick(now: tid(200 + 4 * 3600))
        XCTAssertEqual(r.phase, .done)
        let p = try XCTUnwrap(r.finished)
        XCTAssertEqual(p.stop, tid(200))
        XCTAssertEqual(p.afterEnd, tid(200))
        XCTAssertEqual(p.duration, 200)
        XCTAssertEqual(p.samples.count, 2)
    }

    func testFyraTimmarUtanNågotProvAvslutasVidStart() {
        var r = PassRecorder()
        r.start(now: tid(0))
        r.tick(now: tid(4 * 3600))
        XCTAssertEqual(r.phase, .done)
        XCTAssertEqual(r.finished?.stop, tid(0))
        XCTAssertEqual(r.finished?.duration, 0)
    }

    func testEttPassSomPågårLängeMenFårProvAvslutasInte() {
        var r = PassRecorder()
        r.start(now: tid(0))
        for s in stride(from: 0, through: 5 * 3600, by: 600) { r.add(puls(100), now: tid(Double(s))) }
        r.tick(now: tid(5 * 3600 + 10))
        XCTAssertEqual(r.phase, .running)
    }

    func testÅterupptagetPassFårFasUrDetSomÄrSatt() {
        var p = Pass(start: tid(0))
        p.samples = [PassSample(t: tid(5), bpm: 100)]

        var r = PassRecorder()
        r.restore(p, now: tid(60))
        XCTAssertEqual(r.phase, .running)
        XCTAssertEqual(r.pass, p)

        p.stop = tid(100)
        r.restore(p, now: tid(160))
        XCTAssertEqual(r.phase, .after)

        // Appen dödad under efterperioden och startad om långt efter: slutet vid sista provet, inte vid 600 s.
        p.samples.append(PassSample(t: tid(250), bpm: 90))
        r.restore(p, now: tid(100 + 3600))
        XCTAssertEqual(r.phase, .done)
        XCTAssertEqual(r.pass?.afterEnd, tid(250))

        p.afterEnd = tid(700)
        r.restore(p, now: tid(5000))
        XCTAssertEqual(r.phase, .done)
        XCTAssertEqual(r.pass?.afterEnd, tid(700))
    }

    func testÅterupptagetPågåendePassSomÄrFyraTimmarGammaltAvslutas() {
        var p = Pass(start: tid(0))
        p.samples = [PassSample(t: tid(50), bpm: 100)]
        var r = PassRecorder()
        r.restore(p, now: tid(50 + 5 * 3600))
        XCTAssertEqual(r.phase, .done)
        XCTAssertEqual(r.pass?.stop, tid(50))
    }

    func testClosedStängerEttOsparatPass() {
        var p = Pass(start: tid(0))
        p.samples = [PassSample(t: tid(50), bpm: 100)]
        let c = p.closed()
        XCTAssertEqual(c.stop, tid(50))
        XCTAssertEqual(c.afterEnd, tid(50))
        XCTAssertTrue(c.isFinished)
        // Ett som stoppats men saknar slut får stoppet som slut; ett färdigt ändras inte.
        p.stop = tid(60)
        XCTAssertEqual(p.closed().afterEnd, tid(60))
        p.afterEnd = tid(400)
        XCTAssertEqual(p.closed(), p)
    }
}

final class PassNedräkningTests: XCTestCase {
    func testEfterperiodensNedräkningRäknasUrStoppet() {
        let p = Pass(start: t0, stop: tid(100))
        XCTAssertEqual(p.afterRemaining(now: tid(100)), 600)
        XCTAssertEqual(p.afterRemaining(now: tid(400)), 300)
        XCTAssertEqual(p.afterRemaining(now: tid(900)), 0)
        XCTAssertNil(Pass(start: t0).afterRemaining(now: tid(5)))
    }
}

final class PassKindTests: XCTestCase {
    func testTypernaOchDeraNamn() {
        XCTAssertEqual(PassKind.allCases.map(\.rawValue),
                       ["bastu", "dusch", "styrka", "kondition", "promenad", "golf"])
        XCTAssertEqual(PassKind.allCases.map(\.displayName),
                       ["Bastu", "Dusch", "Styrka", "Kondition", "Promenad", "Golf"])
    }
}
