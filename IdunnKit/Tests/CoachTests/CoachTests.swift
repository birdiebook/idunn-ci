import Foundation
import XCTest
import Fitness
import Markers
import Night
import Pass
import SleepNeed
@testable import Coach

// Alla värden nedan är påhittade (dataregeln). Tiderna räknas från en fast nollpunkt.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00:00 UTC

private func tid(_ s: Double) -> Date { t0.addingTimeInterval(s) }

private func natt(dag: Int, timmar: Double? = 7.5, rmssd: Double? = 61.23456, källa: NightSource = .k18)
    -> Trends.IdunNight {
    Trends.IdunNight(day: WakeDay(daysSince1970: dag), validWindows: 80, rmssd: rmssd, restingHeartRate: 48.44,
                     breathsPerMinute: 14.26, skinTemperature: 33.456, sleepHours: timmar, meanHeartRate: 52.31,
                     movementMinutes: 12, snoringPerHour: 1.26, source: källa, id: "n\(dag)", efficiency: 91.26,
                     wakeBouts: 3, awakeMinutes: 31.4, lightMinutes: 240.2, deepMinutes: 95.6, remMinutes: 110.1,
                     onsetMinutes: -42.4, wakeMinutes: 415.6)
}

/// Ett pass ute med ett prov i sekunden och ett spår längs en meridian.
private func passUte() -> Pass {
    var p = Pass(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, start: t0, stop: tid(600),
                 afterEnd: tid(1_200), kind: .kondition, track: [])
    for s in 0...900 {
        let bpm: Int = s <= 600 ? 120 + (s / 60) * 5 : 150 - (s - 600) / 6
        p.samples.append(PassSample(t: tid(Double(s)), bpm: bpm))
    }
    for s in stride(from: 0, through: 600, by: 10) {
        p.track?.append(TrackPoint(t: tid(Double(s)), lat: 59.3 + Double(s) * 0.00003, lon: 18.05, accuracy: 5))
    }
    return p
}

private func json(_ item: CoachItem) -> String {
    String(data: CoachCoding.json(item) ?? Data(), encoding: .utf8) ?? ""
}

private func nycklar(_ item: CoachItem) throws -> Set<String> {
    let data: Data = try XCTUnwrap(CoachCoding.json(item))
    let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return Set(obj.keys)
}

final class CoachDokumentTests: XCTestCase {
    func testDagenSkrivsSomDatumUtanTidszon() {
        XCTAssertEqual(CoachRound.dag(0), "1970-01-01")
        XCTAssertEqual(CoachRound.dag(-1), "1969-12-31")
        XCTAssertEqual(CoachRound.dag(19_782), "2024-02-29")
        XCTAssertEqual(CoachRound.dag(20_833), "2027-01-15")
        XCTAssertEqual(CoachRound.tid(t0), "2027-01-15T08:00:00Z")
        XCTAssertEqual(CoachRound.tid(tid(86_399.9)), "2027-01-16T07:59:59Z")
    }

    func testNattenBärSammanfattningenAvrundadOchHuvudtalen() throws {
        let n = CoachNight(natt(dag: 20_833),
                           scores: CoachScores(sleepScore: 82, scoreAmount: 88.4, scoreContinuity: 79.6,
                                               scoreRegularity: nil, recovery: 67, dragHrv: -3.26, dragPulse: 1.04,
                                               dragSleep: 0, breathingHigh: false, needHours: 8.257, needBase: 8,
                                               needPass: 0.1234, needDebt: 0.13, debtHours: 0.5))
        XCTAssertEqual(n.day, "2027-01-15")
        XCTAssertEqual(n.source, "K18")
        XCTAssertEqual(n.hrvRmssd, 61.2)
        XCTAssertEqual(n.restingHeartRate, 48.4)
        XCTAssertEqual(n.skinTemperature, 33.46)
        XCTAssertEqual(n.onsetMinutes, -42)
        XCTAssertEqual(n.wakeMinutes, 416)
        XCTAssertEqual(n.deepMinutes, 96)
        XCTAssertEqual(n.sleepScore, 82)
        XCTAssertEqual(n.recovery, 67)
        XCTAssertEqual(n.needHours, 8.26)
        XCTAssertNil(n.scoreRegularity)

        let k = try nycklar(CoachItem(n))
        XCTAssertTrue(k.isSuperset(of: ["day", "source", "sleep_hours", "hrv_rmssd", "resting_heart_rate",
                                         "mean_heart_rate", "deep_minutes", "rem_minutes", "sleep_score",
                                         "recovery", "need_hours", "debt_hours", "onset_minutes"]))
        // Ett tal som saknas skickas inte alls.
        XCTAssertFalse(k.contains("score_regularity"))
    }

    func testNattenUtanHuvudtalSkickarBaraNatten() throws {
        let k = try nycklar(CoachItem(CoachNight(natt(dag: 20_833, timmar: nil, rmssd: nil))))
        XCTAssertFalse(k.contains("sleep_score"))
        XCTAssertFalse(k.contains("recovery"))
        XCTAssertFalse(k.contains("hrv_rmssd"))
        XCTAssertFalse(k.contains("sleep_hours"))
        XCTAssertTrue(k.contains("day"))
    }

    func testEnNattPerDagK18FöreGammalInspelningOchLängstSovtid() {
        let valda = CoachNight.perDay([
            natt(dag: 3, timmar: 6, källa: .notification),
            natt(dag: 3, timmar: 5, källa: .k18),
            natt(dag: 2, timmar: 7, källa: .k18),
            natt(dag: 2, timmar: 7.5, källa: .k18),
            natt(dag: 1, timmar: 4, källa: .notification),
        ])
        XCTAssertEqual(valda.map(\.day.daysSince1970), [1, 2, 3])
        XCTAssertEqual(valda[0].source, .notification)
        XCTAssertEqual(valda[1].sleepHours, 7.5)
        XCTAssertEqual(valda[2].source, .k18)
        XCTAssertEqual(valda[2].sleepHours, 5)
    }

    func testPassetBärTalenMenAldrigSpåretEllerProven() throws {
        let p = CoachPass(passUte(), maxPulse: 190, utcOffsetSeconds: 3_600)
        XCTAssertEqual(p.id, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(p.kind, "kondition")
        XCTAssertEqual(p.day, "2027-01-15")
        XCTAssertEqual(p.start, "2027-01-15T08:00:00Z")
        XCTAssertEqual(p.stop, "2027-01-15T08:10:00Z")
        XCTAssertEqual(p.durationSeconds, 600)
        XCTAssertEqual(p.minBpm, 120)
        XCTAssertEqual(p.maxBpm, 170)
        XCTAssertEqual(p.pulseAtStop, 170)
        XCTAssertNotNil(p.drop60)
        XCTAssertEqual(p.pulseSamples, 601)
        XCTAssertFalse(p.pulseFromHistory)
        XCTAssertTrue(p.outdoor)
        // 600 s × 0,00003° ≈ 2 km längs meridianen.
        let meter: Double = try XCTUnwrap(p.distanceMeters)
        XCTAssertEqual(meter, 2_001, accuracy: 15)
        XCTAssertNotNil(p.paceSecondsPerKm)
        // Tiden per zon summerar till passets aktiva tid (ett prov i sekunden, inga glapp).
        let zoner: Int = [p.zone1Seconds, p.zone2Seconds, p.zone3Seconds, p.zone4Seconds, p.zone5Seconds]
            .compactMap { $0 }.reduce(0, +)
        XCTAssertLessThanOrEqual(zoner, 600)
        XCTAssertGreaterThan(zoner, 500)
        XCTAssertEqual(p.maxPulseUsed, 190)
        XCTAssertNotNil(p.load)

        // Inget fält för spåret eller proven, och inga koordinater någonstans i texten.
        let k = try nycklar(CoachItem(p))
        for förbjudet in ["track", "samples", "lat", "lon", "accuracy", "altitude", "speed"] {
            XCTAssertFalse(k.contains(förbjudet), "passet får inte bära \(förbjudet)")
        }
        let text: String = json(CoachItem(p))
        for koordinat in ["59.3", "18.05"] {
            XCTAssertFalse(text.contains(koordinat), "passet får inte bära en position")
        }
    }

    func testPassetsDagFöljerVäggklockan() {
        var p = Pass(start: tid(15 * 3_600 + 1_800), stop: tid(16 * 3_600))   // 23:30 UTC
        p.kind = .styrka
        XCTAssertEqual(CoachPass(p, maxPulse: nil, utcOffsetSeconds: 0).day, "2027-01-15")
        XCTAssertEqual(CoachPass(p, maxPulse: nil, utcOffsetSeconds: 3_600).day, "2027-01-16")
    }

    func testPassUtanMaxpulsHarIngaZonerOchIngenBelastning() throws {
        var p = Pass(start: t0, stop: tid(120), afterEnd: tid(720), kind: .styrka)
        for s in 0...120 { p.samples.append(PassSample(t: tid(Double(s)), bpm: 100, source: .history)) }
        let c = CoachPass(p, maxPulse: nil, utcOffsetSeconds: 0)
        XCTAssertNil(c.zone1Seconds)
        XCTAssertNil(c.load)
        XCTAssertNil(c.distanceMeters)
        XCTAssertFalse(c.outdoor)
        XCTAssertTrue(c.pulseFromHistory)
        let k = try nycklar(CoachItem(c))
        XCTAssertFalse(k.contains("zone1_seconds"))
        XCTAssertTrue(k.isSuperset(of: ["id", "day", "start", "stop", "duration_seconds", "avg_bpm", "outdoor",
                                         "pulse_samples", "pulse_from_history", "kind"]))
    }

    func testMätningenBärMarkörensNamnOchEnhet() throws {
        var logg = MeasurementLog()
        let egen = try logg.addCustom(name: "Kroppsvikt", unit: "kg", better: .neutral, id: "vikt")
        try logg.add(MarkerReading(marker: egen.id, day: 20_833, value: 81.4, note: "morgon", id: "m1"))
        try logg.add(MarkerReading(marker: .gripStrength, day: 20_834, value: 52, id: "m2"))
        let alla = CoachMeasurement.all(logg)
        XCTAssertEqual(alla.count, 2)
        XCTAssertEqual(alla[0].name, "Kroppsvikt")
        XCTAssertEqual(alla[0].unit, "kg")
        XCTAssertEqual(alla[0].day, "2027-01-15")
        XCTAssertEqual(alla[0].value, 81.4)
        XCTAssertEqual(alla[0].note, "morgon")
        XCTAssertEqual(alla[1].name, "Greppstyrka")
        XCTAssertEqual(CoachItem(alla[0]).name, "matning/m1")
    }

    func testProfilenTarKönOchÅrFrånPersonen() {
        let p = CoachProfile(profile: FitnessProfile(birthYear: 1970, sex: .kvinna, heightCm: 181.24, weightKg: 80.06),
                             person: Person(birthYear: 1985, sex: .male), maxPulse: 187.6, restingPulse: 47.83,
                             shown: FitnessSummary.Shown(value: 48.26, uncertainty: 3.44, basis: .passive(nights: 9)))
        XCTAssertEqual(p.birthYear, 1985)
        XCTAssertEqual(p.sex, "man")
        XCTAssertEqual(p.heightCm, 181.2)
        XCTAssertEqual(p.weightKg, 80.1)
        XCTAssertEqual(p.maxPulse, 188)
        XCTAssertEqual(p.restingPulse, 47.8)
        XCTAssertEqual(p.vo2max, 48.3)
        XCTAssertEqual(p.vo2maxBasis, "skattad")
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(CoachProfile(profile: FitnessProfile(), person: nil, maxPulse: nil, restingPulse: nil,
                                   shown: nil).isEmpty)
    }

    func testIngetDokumentHarEttFältFörRådata() throws {
        // Vakten för dataregeln (BESLUT B127): nycklarna i varje slags dokument, mot orden för det som aldrig skickas.
        var logg = MeasurementLog()
        try logg.add(MarkerReading(marker: .vo2max, day: 20_833, value: 47, id: "m"))
        let alla: [CoachItem] = [
            CoachItem(CoachNight(natt(dag: 20_833), scores: CoachScores(sleepScore: 80, recovery: 60))),
            CoachItem(CoachPass(passUte(), maxPulse: 190, utcOffsetSeconds: 0)),
            CoachItem(CoachMeasurement.all(logg)[0]),
            CoachItem(CoachProfile(profile: FitnessProfile(weightKg: 80), person: nil, maxPulse: 190,
                                   restingPulse: 48, shown: nil)),
            CoachItem(CoachStatus(build: "42")),
        ]
        let förbjudna: [String] = ["track", "sample", "beat", "rr", "lat", "lon", "position", "clip", "audio",
                                   "frame", "raw", "curve", "whoop"]
        for i in alla {
            for k in try nycklar(i) {
                for ord in förbjudna {
                    XCTAssertFalse(k == ord || k.hasPrefix(ord + "_") || k.hasSuffix("_" + ord)
                                   || k.contains("_" + ord + "_"), "\(i.kind.rawValue) har fältet \(k)")
                }
            }
        }
        // `pulse_samples` är ett antal, inte proven.
        XCTAssertTrue(try nycklar(alla[1]).contains("pulse_samples"))
    }
}

final class CoachKopplingTests: XCTestCase {
    private let länk = CoachLink(host: "abcdefghijklmnopqrst.supabase.co", key: "sb_publishable_ABCdef123456-_.xyz",
                                 code: "ABCDEFGH23456789JKMN")

    func testKopplingenLäsesTillbakaUrSinText() {
        let text: String = länk.text
        XCTAssertTrue(text.hasPrefix("IDUNN1."))
        XCTAssertEqual(CoachLink.parse(text), länk)
        XCTAssertEqual(CoachLink.parse("  \n" + text + "\n "), länk)
    }

    func testKopplingenVägrarAnnatÄnTjänstensVärd() {
        func med(_ värd: String) -> String {
            CoachLink(host: värd, key: länk.key, code: länk.code).text
        }
        XCTAssertNil(CoachLink.parse(med("example.com")))
        XCTAssertNil(CoachLink.parse(med("abcdefghijklmnopqrst.supabase.co.example.com")))
        XCTAssertNil(CoachLink.parse(med("evil.com/abcdefghij.supabase.co")))
        XCTAssertNil(CoachLink.parse(med("a.b.supabase.co")))
        XCTAssertNil(CoachLink.parse(med("abcdefghij:443.supabase.co")))
        XCTAssertNil(CoachLink.parse(med(".supabase.co")))
        XCTAssertNil(CoachLink.parse("hej"))
        XCTAssertNil(CoachLink.parse("IDUNN1.inte-base64!"))
        XCTAssertNil(CoachLink.parse(CoachLink(host: länk.host, key: "kort", code: länk.code).text))
        XCTAssertNil(CoachLink.parse(CoachLink(host: länk.host, key: länk.key, code: "med mellanslag").text))
        // Versaler i värden och gemener i koden rättas.
        let blandad = CoachLink(host: "ABCDEFGHIJKLMNOPQRST.supabase.co", key: länk.key, code: "abcdefgh23456789jkmn")
        XCTAssertEqual(CoachLink.parse(blandad.text), länk)
    }

    func testHemlighetenÄrSextiofyraHextecken() {
        let a: String = CoachToken.make()
        let b: String = CoachToken.make()
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, CoachToken.minimumLength)
    }

    func testKopplingsanropet() throws {
        let anrop = try XCTUnwrap(CoachCall.pair(link: länk, token: "t" + String(repeating: "0", count: 63),
                                                 device: "iPhone"))
        XCTAssertEqual(anrop.host, länk.host)
        XCTAssertEqual(anrop.path, "/rest/v1/rpc/idunn_pair")
        XCTAssertEqual(anrop.headers["apikey"], länk.key)
        let kropp = try XCTUnwrap(try JSONSerialization.jsonObject(with: anrop.body) as? [String: Any])
        XCTAssertEqual(kropp["p_code"] as? String, länk.code)
        XCTAssertEqual(kropp["p_device"] as? String, "iPhone")
        XCTAssertEqual((kropp["p_token"] as? String)?.count, 64)
    }

    func testSändningenBärDokumentenOchBorttagningarSomNull() throws {
        let config = CoachConfig(host: länk.host, key: länk.key, token: String(repeating: "a", count: 64))
        let saker: [CoachItem] = [
            CoachItem(CoachNight(natt(dag: 20_833))),
            CoachItem(kind: .pass, key: "ett \"konstigt\" id", data: nil),
        ]
        let anrop = try XCTUnwrap(CoachCall.ingest(config: config, items: saker))
        XCTAssertEqual(anrop.path, "/rest/v1/rpc/idunn_ingest")
        let kropp = try XCTUnwrap(try JSONSerialization.jsonObject(with: anrop.body) as? [String: Any])
        XCTAssertEqual(kropp["p_token"] as? String, config.token)
        let lista = try XCTUnwrap(kropp["p_items"] as? [[String: Any]])
        XCTAssertEqual(lista.count, 2)
        XCTAssertEqual(lista[0]["kind"] as? String, "natt")
        XCTAssertEqual(lista[0]["key"] as? String, "2027-01-15")
        XCTAssertEqual((lista[0]["data"] as? [String: Any])?["hrv_rmssd"] as? Double, 61.2)
        XCTAssertEqual(lista[1]["key"] as? String, "ett \"konstigt\" id")
        XCTAssertTrue(lista[1]["data"] is NSNull)

        XCTAssertNil(CoachCall.ingest(config: config, items: []))
        XCTAssertNil(CoachCall.ingest(config: CoachConfig(host: "example.com", key: länk.key, token: config.token),
                                      items: saker))
        XCTAssertNil(CoachCall.ingest(config: CoachConfig(host: länk.host, key: länk.key, token: "kort"),
                                      items: saker))
    }

    func testSvaret() {
        XCTAssertEqual(CoachReply.parse(status: 200, body: Data(#"{"ok":true,"count":7}"#.utf8)), .ok(count: 7))
        XCTAssertEqual(CoachReply.parse(status: 200, body: Data(#"{"ok":true}"#.utf8)), .ok(count: 0))
        let okänd = CoachReply.parse(status: 200, body: Data(#"{"ok":false,"error":"okand"}"#.utf8))
        XCTAssertEqual(okänd, .refused("okand"))
        XCTAssertTrue(okänd.isUnknownDevice)
        XCTAssertFalse(CoachReply.parse(status: 200, body: Data(#"{"ok":false,"error":"fullt"}"#.utf8))
            .isUnknownDevice)
        XCTAssertEqual(CoachReply.parse(status: 401, body: Data(#"{"message":"nej"}"#.utf8)), .http(401))
        XCTAssertEqual(CoachReply.parse(status: 200, body: Data("<html>".utf8)), .http(200))
    }
}

final class CoachLoggTests: XCTestCase {
    private func nätter(_ dagar: [Int], rmssd: Double = 60) -> [CoachItem] {
        dagar.map { (d: Int) -> CoachItem in CoachItem(CoachNight(natt(dag: d, rmssd: rmssd))) }
    }

    func testBaraNyaOchÄndradeDokumentSkickas() {
        var logg = CoachLedger()
        let första: [CoachItem] = nätter([1, 2, 3])
        XCTAssertEqual(logg.pending(första).map(\.key), ["1970-01-02", "1970-01-03", "1970-01-04"])
        logg.mark(första)
        XCTAssertEqual(logg.count, 3)
        XCTAssertTrue(logg.pending(första).isEmpty)

        // Natt 2 räknas om till ett annat tal, och natt 4 är ny.
        var andra: [CoachItem] = nätter([1, 3, 4])
        andra.append(CoachItem(CoachNight(natt(dag: 2, rmssd: 71))))
        XCTAssertEqual(Set(logg.pending(andra).map(\.key)), ["1970-01-03", "1970-01-05"])

        // En omräkning som bara flyttar en decimal som inte skickas ger samma dokument.
        XCTAssertTrue(logg.pending(nätter([1, 2, 3], rmssd: 60.01)).isEmpty)
    }

    func testBorttagningBaraFörSlagSomFårTasBort() {
        var logg = CoachLedger()
        let pass = CoachItem(CoachPass(passUte(), maxPulse: 190, utcOffsetSeconds: 0))
        let allt: [CoachItem] = nätter([1, 2]) + [pass]
        logg.mark(allt)

        // Tom lista: ingenting tas bort utan uttryckligt slag (en låst telefon ger tomma listor).
        XCTAssertTrue(logg.pending([]).isEmpty)
        // Bara passet får tas bort; nätterna står kvar hur listan än ser ut.
        let bort: [CoachItem] = logg.pending(nätter([1]), deletable: [.pass])
        XCTAssertEqual(bort.count, 1)
        XCTAssertEqual(bort[0].kind, .pass)
        XCTAssertEqual(bort[0].key, pass.key)
        XCTAssertNil(bort[0].data)

        logg.mark(bort)
        XCTAssertEqual(logg.count, 2)
        XCTAssertTrue(logg.pending(nätter([1, 2]), deletable: [.pass]).isEmpty)
    }

    func testLoggenÖverleverFilenOchBitarnaÄrHögstHundra() throws {
        var logg = CoachLedger()
        logg.mark(nätter(Array(1...5)))
        let tillbaka = try JSONDecoder().decode(CoachLedger.self, from: JSONEncoder().encode(logg))
        XCTAssertEqual(tillbaka, logg)
        XCTAssertTrue(tillbaka.pending(nätter(Array(1...5))).isEmpty)

        let bitar: [[CoachItem]] = CoachLedger.batches(nätter(Array(1...250)))
        XCTAssertEqual(bitar.map(\.count), [100, 100, 50])
        XCTAssertTrue(CoachLedger.batches([]).isEmpty)
    }

    func testFingeravtrycketFöljerInnehållet() {
        XCTAssertEqual(CoachLedger.fingerprint(Data()), "cbf29ce484222325")
        XCTAssertEqual(CoachLedger.fingerprint(Data("a".utf8)), "af63dc4c8601ec8c")
        XCTAssertNotEqual(CoachLedger.fingerprint(Data("ab".utf8)), CoachLedger.fingerprint(Data("ba".utf8)))
    }
}
