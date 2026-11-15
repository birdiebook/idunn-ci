import Foundation
import XCTest
@testable import WhoopFrames

// METOD M27 · BESLUT B50 (L2). Fönstret på Data byts när det nya börjar, kl 18:00,
// inte vid midnatt: före 18 det som slutar idag, från 18 det som slutar i morgon.
// Rena klockslag och zoner, inga värden. Zonbytet prövas på de två nätterna då
// Sverige ställer om klockan (sista söndagen i oktober och i mars).

/// En hel K18-ram för bandets tid `time`, hörd samma sekund (som `Notiser` i DayLogTests).
private func k18Ram(_ time: Int) -> RawFrame {
    RawFrame(time: Date(timeIntervalSince1970: Double(time)), characteristic: "fd4b0005",
             bytes: Ramar.ram(Ramar.pad([47, 18, 0] + Ramar.u32(0) + Ramar.u32(UInt32(time)), 112)))
}

final class NightWindowTests: XCTestCase {

    /// Klockan `h:m:s` den lokala dagen `y-m-d` i zonen `zon`.
    func tid(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ s: Int = 0, zon: Int) -> Date {
        DayLog.date(of: DayLog.Day(year: y, month: m, day: d), hour: h, minute: min, utcOffsetSeconds: zon)
            .addingTimeInterval(Double(s))
    }

    // MARK: Gränsen kl 18

    func testFöreAttonSlutarFönstretIdagOchFrånAttonIMorgon() {
        let z = 7200
        // (klockslag, dagen fönstret slutar på) — 2026-10-13 är en tisdag.
        let fall: [(h: Int, m: Int, s: Int, slutar: Int)] = [
            (0, 0, 0, 13), (0, 30, 0, 13), (9, 0, 0, 13), (11, 59, 59, 13), (12, 0, 0, 13),
            (15, 0, 0, 13), (17, 59, 59, 13),
            (18, 0, 0, 14), (18, 0, 1, 14), (20, 38, 0, 14), (23, 59, 59, 14),
        ]
        for f in fall {
            let nu = tid(2026, 10, 13, f.h, f.m, f.s, zon: z)
            let w = NightWindow.latest(now: nu, utcOffsetSeconds: z)
            XCTAssertEqual(w.end, tid(2026, 10, f.slutar, 12, zon: z), "slut vid \(f.h):\(f.m):\(f.s)")
            XCTAssertEqual(w.start, tid(2026, 10, f.slutar - 1, 18, zon: z), "början vid \(f.h):\(f.m):\(f.s)")
            XCTAssertEqual(w.until, min(w.end, nu), "fram till nu eller slutet")
        }
    }

    func testKvällenRäknasFramTillNuOchEftermiddagenStårKvar() {
        let z = 7200
        let kväll = tid(2026, 10, 13, 20, 38, zon: z)
        let k = NightWindow.latest(now: kväll, utcOffsetSeconds: z)
        XCTAssertTrue(k.inProgress, "natten som börjat pågår")
        XCTAssertEqual(k.until, kväll)
        XCTAssertEqual(k.until.timeIntervalSince(k.start), 158 * 60, "18:00 till 20:38")

        let eftermiddag = tid(2026, 10, 13, 15, zon: z)
        let e = NightWindow.latest(now: eftermiddag, utcOffsetSeconds: z)
        XCTAssertFalse(e.inProgress, "natten som var är slut")
        XCTAssertEqual(e.until, e.end)
    }

    func testPrecisKlockan18ÄrFönstretTomtOchHarIngenTäckning() {
        let z = 7200
        let nu = tid(2026, 10, 13, 18, zon: z)
        let w = NightWindow.latest(now: nu, utcOffsetSeconds: z)
        XCTAssertEqual(w.start, nu)
        XCTAssertEqual(w.until, nu)
        XCTAssertNil(ListenerStatus().coverage(w), "ett tomt fönster har ingen täckning")
        // En minut senare räknas den första minuten.
        let senare = NightWindow.latest(now: tid(2026, 10, 13, 18, 1, zon: z), utcOffsetSeconds: z)
        XCTAssertEqual(ListenerStatus().coverage(senare)?.totalMinutes, 1)
    }

    func testKvällensStapelRäknasPåNattenSomBörjatInteGårdagens() {
        // användaren fall 2026-10-13 kl 20:38: K18 hördes sedan 20:38, och stapeln
        // stod på 0 % eftersom den räknade gårdagens natt (BESLUT B50).
        let z = 7200
        let nu = tid(2026, 10, 13, 20, 38, zon: z)
        let w = NightWindow.latest(now: nu, utcOffsetSeconds: z)
        var s = ListenerStatus()
        for m in stride(from: Int(tid(2026, 10, 13, 20, 0, zon: z).timeIntervalSince1970),
                        to: Int(nu.timeIntervalSince1970), by: 60) {
            s.add(k18Ram(m))
        }
        let c = s.coverage(w)
        XCTAssertEqual(c?.totalMinutes, 158)
        XCTAssertEqual(c?.coveredMinutes, 38)
        // Det gamla fönstret (som slutade idag kl 12) såg ingenting av detta.
        let gammalt = NightWindow.endingToday(now: nu, utcOffsetSeconds: z)
        XCTAssertEqual(s.coverage(gammalt)?.coveredMinutes, 0)
    }

    // MARK: Zoner

    func testGränsenFöljerVäggklockanIVarjeZon() {
        // Samma ögonblick är olika klockslag i olika zoner: 16:30 UTC är 18:30 i
        // +02:00 (i kväll) men 17:30 i +01:00 (i eftermiddags).
        let ögonblick = tid(2026, 10, 13, 16, 30, zon: 0)
        let sommar = NightWindow.latest(now: ögonblick, utcOffsetSeconds: 7200)
        XCTAssertEqual(sommar.end, tid(2026, 10, 14, 12, zon: 7200))
        let vinter = NightWindow.latest(now: ögonblick, utcOffsetSeconds: 3600)
        XCTAssertEqual(vinter.end, tid(2026, 10, 13, 12, zon: 3600))
        // Väster om Greenwich går dagen på den lokala dagen, inte UTC:s.
        let väst = NightWindow.latest(now: tid(2026, 10, 13, 2, 0, zon: 0), utcOffsetSeconds: -5 * 3600)
        XCTAssertEqual(väst.start, tid(2026, 10, 12, 18, zon: -5 * 3600), "02:00 UTC är 21:00 den 12:e i −05:00")
        XCTAssertEqual(väst.end, tid(2026, 10, 13, 12, zon: -5 * 3600))
    }

    /// Sverige: sommartid (+02:00) till och med 01:00 UTC den 25 oktober 2026, sedan +01:00.
    func hösten(_ d: Date) -> Int {
        d >= tid(2026, 10, 25, 1, zon: 0) ? 3600 : 7200
    }

    /// Sverige: vintertid (+01:00) till och med 01:00 UTC den 28 mars 2027, sedan +02:00.
    func våren(_ d: Date) -> Int {
        d >= tid(2027, 3, 28, 1, zon: 0) ? 7200 : 3600
    }

    func testNattenOverOmställningenTillVintertidÄrNittonTimmar() {
        // Lördag 24 okt 20:00 (+02:00): natten slutar söndag 25 okt kl 12:00 i +01:00.
        let nu = tid(2026, 10, 24, 20, zon: 7200)
        let w = NightWindow.latest(now: nu, offsetAt: hösten)
        XCTAssertEqual(w.start, tid(2026, 10, 24, 18, zon: 7200))
        XCTAssertEqual(w.end, tid(2026, 10, 25, 12, zon: 3600), "klockan 12 på söndagen är i vintertid")
        XCTAssertEqual(w.end.timeIntervalSince(w.start), 19 * 3600)
        XCTAssertEqual(w.until, nu)
        // Med en enda zon (den nuvarande) blir slutet en timme fel.
        let enZon = NightWindow.latest(now: nu, utcOffsetSeconds: 7200)
        XCTAssertEqual(enZon.end.timeIntervalSince(enZon.start), 18 * 3600)
        XCTAssertNotEqual(enZon.end, w.end)
    }

    func testDagenOmställningenSkerBytsFönstretFortfarandeKlockan18() {
        // Söndag 25 okt: 17:59 i +01:00 hör till natten som slutade kl 12, 18:00 till nästa.
        let före = tid(2026, 10, 25, 17, 59, 59, zon: 3600)
        let a = NightWindow.latest(now: före, offsetAt: hösten)
        XCTAssertEqual(a.start, tid(2026, 10, 24, 18, zon: 7200), "början i sommartid")
        XCTAssertEqual(a.end, tid(2026, 10, 25, 12, zon: 3600))
        XCTAssertFalse(a.inProgress)
        XCTAssertEqual(a.end.timeIntervalSince(a.start), 19 * 3600)

        let efter = tid(2026, 10, 25, 18, zon: 3600)
        let b = NightWindow.latest(now: efter, offsetAt: hösten)
        XCTAssertEqual(b.start, efter)
        XCTAssertEqual(b.end, tid(2026, 10, 26, 12, zon: 3600))
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 18 * 3600)
        XCTAssertTrue(b.inProgress)
    }

    func testNattenOverOmställningenTillSommartidÄrSjuttonTimmar() {
        // Lördag 27 mars 2027 kl 20:00 (+01:00): natten slutar söndag 28 mars kl 12 i +02:00.
        let nu = tid(2027, 3, 27, 20, zon: 3600)
        let w = NightWindow.latest(now: nu, offsetAt: våren)
        XCTAssertEqual(w.start, tid(2027, 3, 27, 18, zon: 3600))
        XCTAssertEqual(w.end, tid(2027, 3, 28, 12, zon: 7200))
        XCTAssertEqual(w.end.timeIntervalSince(w.start), 17 * 3600)
        // Klockan 17:59 den 28:e (+02:00) hör fortfarande till natten som slutade.
        let efter = tid(2027, 3, 28, 17, 59, 59, zon: 7200)
        let a = NightWindow.latest(now: efter, offsetAt: våren)
        XCTAssertEqual(a.end, tid(2027, 3, 28, 12, zon: 7200))
        XCTAssertEqual(NightWindow.latest(now: tid(2027, 3, 28, 18, zon: 7200), offsetAt: våren).end,
                       tid(2027, 3, 29, 12, zon: 7200))
    }

    func testEnFastZonGerSammaFönsterSomFörutOchSomZonfunktionen() {
        let z = 7200
        for h in [0, 6, 12, 17, 18, 19, 23] {
            let nu = tid(2026, 10, 13, h, 15, zon: z)
            XCTAssertEqual(NightWindow.latest(now: nu, utcOffsetSeconds: z),
                           NightWindow.latest(now: nu, offsetAt: { (_: Date) -> Int in z }), "kl \(h):15")
        }
        let dag = DayLog.Day(year: 2026, month: 10, day: 14)
        XCTAssertEqual(NightWindow.ending(on: dag, utcOffsetSeconds: z),
                       NightWindow.ending(on: dag, offsetAt: { (_: Date) -> Int in z }),
                       "natten som slutar en dag är densamma, med en zon eller en zonfunktion")
    }

    // MARK: Det gamla beteendet, för den som behöver det

    func testSlutarIdagÄrDetGamlaFönstretHelaDygnet() {
        let z = 7200
        for h in [0, 9, 12, 17, 18, 20, 23] {
            let nu = tid(2026, 10, 13, h, 5, zon: z)
            let w = NightWindow.endingToday(now: nu, utcOffsetSeconds: z)
            XCTAssertEqual(w.end, tid(2026, 10, 13, 12, zon: z), "kl \(h):05")
            XCTAssertEqual(w.start, tid(2026, 10, 12, 18, zon: z))
            XCTAssertEqual(w.until, min(w.end, nu))
        }
    }

    func testDagenFönstretSlutarPå() {
        let z = 7200
        XCTAssertEqual(NightWindow.endingDay(now: tid(2026, 10, 13, 17, 59, 59, zon: z), utcOffsetSeconds: z).text,
                       "2026-10-13")
        XCTAssertEqual(NightWindow.endingDay(now: tid(2026, 10, 13, 18, zon: z), utcOffsetSeconds: z).text,
                       "2026-10-14")
        // Över månadsskiftet och årsskiftet.
        XCTAssertEqual(NightWindow.endingDay(now: tid(2026, 10, 31, 22, zon: z), utcOffsetSeconds: z).text,
                       "2026-11-01")
        XCTAssertEqual(NightWindow.endingDay(now: tid(2026, 12, 31, 23, 30, zon: z), utcOffsetSeconds: z).text,
                       "2027-01-01")
        // Före epoken: negativa tider ger rätt klockslag.
        XCTAssertEqual(NightWindow.endingDay(now: Date(timeIntervalSince1970: -3600), utcOffsetSeconds: 0).text,
                       "1970-01-01", "23:00 den 31 dec 1969 slutar natten den 1 jan")
    }
}
