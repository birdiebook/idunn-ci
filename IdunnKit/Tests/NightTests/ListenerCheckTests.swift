import Foundation
import XCTest
import DemoData
import WhoopFrames
@testable import Night

// METOD M29 · BESLUT B38 · BESLUT B52. När lyssnaren säger till på Morgon: bara när något
// är fel. Påhittade K18-poster (DemoListener), inga värden.

final class ListenerCheckTests: XCTestCase {
    let zon = 7200

    /// Klockan `h:m` den lokala dagen `d` (oktober 2026).
    func tid(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        DayLog.date(of: DayLog.Day(year: 2026, month: 10, day: d), hour: h, minute: m, utcOffsetSeconds: zon)
    }

    /// Statusen efter K18 för varje minut i `[från, till)`.
    func status(_ från: Date, _ till: Date) -> ListenerStatus {
        ListenerStatus.read(DemoListener.notifications(start: från, end: till))
    }

    func larm(_ s: ListenerStatus, nu: Date, täckning: Double? = nil, bt: ListenerCheck.Bluetooth = .ok,
              läst: Bool = true, lager: Bool = false) -> ListenerAlert? {
        ListenerCheck.alert(status: s, nightCoverage: täckning, bluetooth: bt, statusRead: läst,
                            nightLacksLayers: lager, now: nu, utcOffsetSeconds: zon)
    }

    func testEnBraNattOchEnMorgonUtanFelGerIngenRad() {
        let s = status(tid(13, 22, 30), tid(14, 7, 20))
        XCTAssertNil(larm(s, nu: tid(14, 7, 30), täckning: 0.95))
        XCTAssertNotNil(s.lastK18Heard)
    }

    func testBandetHördesSist22_14OchNuÄrDet0730() throws {
        // Exemplet i S1: "Idunn har inte hört bandet sedan 22:14".
        let s = status(tid(13, 21, 0), tid(13, 22, 15))
        let sist = try XCTUnwrap(s.lastK18Heard)
        XCTAssertEqual(sist, tid(13, 22, 14))
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30)), .silent(since: sist))
    }

    func testTystnadenMätsFramTillFönstretsSlutEfterMiddagen() throws {
        // Bra natt, sista synken 07:00: på eftermiddagen är det 5 timmar till
        // klockan 12, inte 8 timmar till nu.
        let s = status(tid(13, 22, 30), tid(14, 7, 0))
        XCTAssertNil(larm(s, nu: tid(14, 15, 0)))
        XCTAssertNil(larm(s, nu: tid(14, 23, 30)))
        // Men en lyssnare som tystnade 03:00 syns hela dagen.
        let tidig = status(tid(13, 22, 30), tid(14, 3, 0))
        let sist = try XCTUnwrap(tidig.lastK18Heard)
        XCTAssertEqual(larm(tidig, nu: tid(14, 15, 0)), .silent(since: sist))
    }

    func testRadenPåMorgonÄndrasInteAvAttFönstretPåDataByterKl18() throws {
        // BESLUT B50. Stapeln på Data byter till natten som börjar kl 18; Morgon bedömer lyssnaren
        // fortfarande mot natten som slutade kl 12, hela kvällen, tills det nya fönstret pågått tio timmar.
        let tidig = status(tid(13, 22, 30), tid(14, 3, 0))
        let sist = try XCTUnwrap(tidig.lastK18Heard)
        for (h, m) in [(17, 59), (18, 0), (20, 0), (23, 59)] {
            XCTAssertEqual(larm(tidig, nu: tid(14, h, m)), .silent(since: sist), "kl \(h):\(m)")
        }
        XCTAssertNil(larm(tidig, nu: tid(15, 0, 10)), "efter midnatt som förut: fönstret har pågått sex timmar")
        XCTAssertNotNil(larm(tidig, nu: tid(15, 4, 0)))
        // En bra natt ger ingen rad på kvällen heller.
        let bra = status(tid(13, 22, 30), tid(14, 7, 0))
        XCTAssertNil(larm(bra, nu: tid(14, 20, 0)))
    }

    func testGränsenÄrÅttaTimmarFörePassagenAvKlockan12() {
        // 12:00 − 8 h = 04:00. Hörd 04:00 (minut 04:00) är exakt åtta timmar.
        let precis = status(tid(13, 22, 0), tid(14, 4, 1))
        XCTAssertNil(larm(precis, nu: tid(14, 13, 0)), "hörd 04:00 är exakt åtta timmar")
        let före = status(tid(13, 22, 0), tid(14, 3, 59))
        XCTAssertNotNil(larm(före, nu: tid(14, 13, 0)))
    }

    func testInteFörstEfterMidnattNärNattenInteHunnitBörja() {
        // Klockan 00:10 har fönstret pågått 6 timmar: tystnaden sedan i morse
        // är inget fel än.
        let s = status(tid(13, 6, 0), tid(13, 7, 30))
        XCTAssertNil(larm(s, nu: tid(14, 0, 10)))
        XCTAssertNil(larm(s, nu: tid(14, 3, 50)))
        // Från 04:00 har det pågått tio timmar.
        XCTAssertNotNil(larm(s, nu: tid(14, 4, 0)))
    }

    func testAldrigHörtOchOläsbaraFiler() {
        XCTAssertEqual(larm(ListenerStatus(), nu: tid(14, 7, 30)), .neverHeard)
        XCTAssertNil(larm(ListenerStatus(), nu: tid(14, 7, 30), läst: false),
                     "filerna är krypterade tills första upplåsningen: statusen vet ingenting")
    }

    func testLågTäckningUnderHälftenMenInteVidHälften() {
        let s = status(tid(13, 22, 30), tid(14, 7, 20))
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30), täckning: 0.41), .lowCoverage(fraction: 0.41))
        XCTAssertNil(larm(s, nu: tid(14, 7, 30), täckning: ListenerCheck.minCoverage))
        XCTAssertNil(larm(s, nu: tid(14, 7, 30), täckning: nil), "ingen natt räknad än")
    }

    func testTystnadenGårFöreLågTäckning() throws {
        let s = status(tid(13, 21, 0), tid(13, 22, 15))
        let sist = try XCTUnwrap(s.lastK18Heard)
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30), täckning: 0.1), .silent(since: sist))
    }

    func testBluetoothGårFöreAllt() {
        let s = status(tid(13, 21, 0), tid(13, 22, 15))
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30), bt: .notAllowed), .bluetoothNotAllowed)
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30), bt: .off), .bluetoothOff)
        XCTAssertEqual(larm(ListenerStatus(), nu: tid(14, 7, 30), bt: .off), .bluetoothOff)
        // Också när filerna inte gått att läsa: Bluetooth vet appen själv.
        XCTAssertEqual(larm(ListenerStatus(), nu: tid(14, 7, 30), bt: .off, läst: false), .bluetoothOff)
    }

    // MARK: Natt utan lager (E3, BESLUT B52)

    func testEnNattUtanLagerGerEnRadNärIngetAnnatÄrFel() {
        let bra = status(tid(13, 22, 30), tid(14, 7, 20))
        XCTAssertEqual(larm(bra, nu: tid(14, 7, 30), täckning: 0.95, lager: true), .missingLayers)
        XCTAssertNil(larm(bra, nu: tid(14, 7, 30), täckning: 0.95, lager: false), "natten har sina lager: ingen rad")
        // Också när tystnaden inte går att bedöma: filerna är oläsbara, eller fönstret har pågått för kort.
        XCTAssertEqual(larm(bra, nu: tid(14, 7, 30), läst: false, lager: true), .missingLayers)
        let tidig = status(tid(13, 6, 0), tid(13, 7, 30))
        XCTAssertEqual(larm(tidig, nu: tid(14, 0, 10), lager: true), .missingLayers, "fönstret har pågått sex timmar")
        XCTAssertNil(larm(tidig, nu: tid(14, 0, 10), lager: false))
    }

    func testBluetoothTystnadOchLågTäckningGårFöreNattUtanLager() throws {
        let s = status(tid(13, 21, 0), tid(13, 22, 15))
        let sist = try XCTUnwrap(s.lastK18Heard)
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30), bt: .off, lager: true), .bluetoothOff)
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30), bt: .notAllowed, lager: true), .bluetoothNotAllowed)
        XCTAssertEqual(larm(s, nu: tid(14, 7, 30), lager: true), .silent(since: sist))
        XCTAssertEqual(larm(ListenerStatus(), nu: tid(14, 7, 30), lager: true), .neverHeard)
        let bra = status(tid(13, 22, 30), tid(14, 7, 20))
        XCTAssertEqual(larm(bra, nu: tid(14, 7, 30), täckning: 0.41, lager: true), .lowCoverage(fraction: 0.41))
    }
}
