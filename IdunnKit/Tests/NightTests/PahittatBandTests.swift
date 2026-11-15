import Foundation
import XCTest
import DemoData
import HeartRate
@testable import WhoopFrames
@testable import Night

// PLAN.md A3 · METOD M23 · BESLUT B25. Idunn utan Whoop-appen, provat utan att sova en natt: ett påhittat band
// håller en hel natts historik och lämnar ut den i bitar som det riktiga (START, poster, END; nästa bit först efter
// kvittensen; COMPLETE när minnet är tomt), och telefonen sparar allt den hör rått i dygnsfilerna som `Recorder`.
// Natten ur filerna ska vara exakt natten ur posterna i ett svep, också när hämtningen avbryts (tappat band, appen
// dödad, sparfel, Whoop-appen samtidigt) och tas upp igen: det som inte kvitterats ligger kvar i bandet och kommer
// nästa gång. Inga värden kommer från ett riktigt band (DemoK18Nights).

/// Ett påhittat Whoop 5 med historik i minnet. Det svarar på 145, 22 och 23 som bandet gör (PROTOKOLL_W5 §7, METOD
/// M23): 145 svarar 2 och sedan 1, 22 svarar 1 och skickar första biten, 23 med rätt END glömmer biten och skickar
/// nästa, eller COMPLETE när minnet är tomt. En bit som inte kvitterats skickas igen vid nästa 22.
struct PåhittatBand {
    static let t0: UInt32 = 1_760_000_000

    /// Bitarna som inte kvitterats, äldst först.
    private(set) var minne: [[K18Record]]
    private var trim: UInt32 = 1000
    /// Bitar som kvitterats, av vem som helst.
    private(set) var kvitterade = 0

    init(poster: [K18Record], perBit: Int) {
        var bitar: [[K18Record]] = []
        var i = 0
        while i < poster.count {
            bitar.append(Array(poster[i..<min(poster.count, i + perBit)]))
            i += perBit
        }
        minne = bitar
    }

    var tomt: Bool { minne.isEmpty }

    /// Bandets svar på ett kommando, som (karakteristik, inre del) i den ordning de skickas.
    mutating func ta(_ c: WhoopCommand) -> [(String, [UInt8])] {
        switch c.number {
        case .clientHello:
            return [("fd4b0003", Self.svar(145, c.sequence, 2)), ("fd4b0003", Self.svar(145, c.sequence, 1))]
        case .sendHistoricalData:
            return [("fd4b0003", Self.svar(22, c.sequence, 1))] + nästaBit()
        case .historicalDataResult:
            if !minne.isEmpty, Array(c.payload.dropFirst()) == Self.endData(trim: trim) {
                minne.removeFirst()
                trim += 1
                kvitterade += 1
            }
            return [("fd4b0003", Self.svar(23, c.sequence, 1))] + nästaBit()
        default:
            return []
        }
    }

    /// Whoop-appen synkar `antal` bitar (eller allt): bandet skickar dem och Whoop kvitterar. Telefonen hör samma
    /// notiser (iOS delar länken) och sparar dem rått.
    mutating func whoopSynkar(bitar antal: Int = .max) -> [(String, [UInt8])] {
        var ut: [(String, [UInt8])] = []
        var k = 0
        while !minne.isEmpty && k < antal {
            ut += nästaBit()
            minne.removeFirst()
            trim += 1
            kvitterade += 1
            k += 1
        }
        if minne.isEmpty { ut.append(("fd4b0005", Self.complete())) }
        return ut
    }

    private func nästaBit() -> [(String, [UInt8])] {
        guard let bit = minne.first else { return [("fd4b0005", Self.complete())] }
        var ut: [(String, [UInt8])] = [("fd4b0005", Self.start())]
        for r in bit { ut.append(("fd4b0005", DemoK18Frames.inner(r))) }
        ut.append(("fd4b0005", Self.end(records: UInt32(bit.count), trim: trim)))
        return ut
    }

    // MARK: Ramarnas inre delar (samma form som i HistorySessionTests)

    static func u32(_ v: UInt32) -> [UInt8] { [0, 8, 16, 24].map { UInt8((v >> UInt32($0)) & 0xFF) } }
    static func pad(_ b: [UInt8], _ n: Int) -> [UInt8] { b + [UInt8](repeating: 0, count: max(0, n - b.count)) }
    static func svar(_ cmd: UInt8, _ seq: UInt8, _ result: UInt8) -> [UInt8] { [36, 0x40, cmd, seq, result, 0, 0, 0] }
    static func start() -> [UInt8] { pad([49, 0x10, 1] + u32(t0), 40) }
    static func endData(trim: UInt32) -> [UInt8] { u32(trim) + u32(12) }
    static func end(records: UInt32, trim: UInt32) -> [UInt8] {
        pad([49, 0x11, 2] + u32(t0) + [0, 0] + u32(records) + endData(trim: trim), 24)
    }
    static func complete() -> [UInt8] { pad([49, 0x13, 3] + u32(t0), 12) }

    /// En hel ram med båda summorna, som bandet skickar den.
    static func ram(_ inner: [UInt8]) -> [UInt8] {
        let length = inner.count + 4
        var b: [UInt8] = [0xAA, 0x01, UInt8(length & 0xFF), UInt8(length >> 8), 0x00, 0x01]
        let h = FrameAssembly.crc16Modbus(b)
        b += [UInt8(h & 0xFF), UInt8(h >> 8)] + inner + u32(FrameAssembly.crc32(inner))
        return b
    }
}

/// Telefonen: en hämtning i taget (`HistorySession`, som appen kör den), och allt som hörs sparat rått i ordning
/// (`disk`), som `Recorder` skriver dygnsfilerna.
struct Telefon {
    var now: Date
    private(set) var disk: [RawFrame] = []

    init(now: Date) { self.now = now }

    /// Hur en hämtning slutar i provet.
    enum Avbrott {
        /// Bandet tappas efter så många notiser.
        case tappatEfter(Int)
        /// Appen dödas efter så många notiser: sessionen får aldrig veta något.
        case dödadEfter(Int)
        /// Whoop-appen svarar på sitt eget 22 efter så många notiser.
        case whoopEfter(Int)
    }

    /// En hämtning med en ny session mot bandet. `sparaOK` är svaret när sessionen ber om varaktigt sparande.
    @discardableResult
    mutating func hämta(_ band: inout PåhittatBand, avbrott: Avbrott? = nil, sparaOK: Bool = true)
        -> HistorySession.Outcome? {
        var session = HistorySession(now: now)
        var stream = FrameAssembly.Stream()
        var kö: [(String, [UInt8])] = []
        var utfall: HistorySession.Outcome?
        var notiser = 0

        func utför(_ actions: [HistorySession.Action]) {
            for a in actions {
                switch a {
                case .write(let c): kö += band.ta(c)
                case .saveThenAck: utför(session.saved(ok: sparaOK, now: now))
                case .finish(let o): utfall = o
                }
            }
        }

        utför(session.start(now: now))
        while !kö.isEmpty && utfall == nil {
            switch avbrott {
            case .tappatEfter(let n) where notiser >= n:
                utför(session.disconnected())
                return utfall
            case .dödadEfter(let n) where notiser >= n:
                return nil
            case .whoopEfter(let n) where notiser == n:
                kö.insert(("fd4b0003", PåhittatBand.svar(22, 200, 1)), at: 0)
            default:
                break
            }
            let (k, inner) = kö.removeFirst()
            hör(k, inner)
            notiser += 1
            if let f = stream.add(disk[disk.count - 1]) { utför(session.receive(f, now: now)) }
        }
        return utfall
    }

    /// Notiser som bara hörs (Whoop-appens synk på samma länk).
    mutating func hör(_ notiser: [(String, [UInt8])]) {
        for (k, inner) in notiser { hör(k, inner) }
    }

    private mutating func hör(_ k: String, _ inner: [UInt8]) {
        now += 0.005
        disk.append(RawFrame(time: now, characteristic: k, bytes: PåhittatBand.ram(inner)))
    }

    /// Dygnsfilerna som `Recorder` skulle ha skrivit: varje notis i filen för det lokala datum den hördes.
    func dygnsfiler(zon: Int) -> [K18Days.File] {
        var perDag: [String: [RawFrame]] = [:]
        for f in disk { perDag[DayLog.stem(for: f.time, utcOffsetSeconds: zon), default: []].append(f) }
        return perDag.keys.sorted().map { (stem: String) -> K18Days.File in
            K18Days.File(stem: stem, sidecar: RecordingLog.header(utcOffsetSeconds: zon),
                         frames: DemoK18Frames.log(perDag[stem] ?? []))
        }
    }
}

final class PahittatBandTests: XCTestCase {

    /// Bandets bitar: användaren enda riktiga hämtning gav 130 poster i 3 bitar (PLAN.md T4), alltså runt 40 per bit.
    static let perBit = 43

    let natt = DemoK18Nights.night(daysBeforeLast: 0, shortGaps: false)
    var zon: Int { natt.utcOffsetSeconds }
    var dag: WakeDay { WakeDay(Date(timeIntervalSince1970: Double(natt.wake)), utcOffsetSeconds: zon) }
    /// Morgonen: en halvtimme efter uppvaknandet.
    var morgon: Date { Date(timeIntervalSince1970: Double(natt.wake) + 1800) }

    func facit() throws -> NightResult {
        try XCTUnwrap(K18Night.analyze(K18Series(notifications: DemoK18Frames.notifications(natt.records)),
                                       wakeDay: dag, startOffsetSeconds: zon, endOffsetSeconds: zon))
    }

    /// Natten som appen räknar den ur dygnsfilerna, med dygnet efter när `nästa`.
    func nattenUr(_ telefon: Telefon, nästa: Bool = false) throws -> NightResult {
        try XCTUnwrap(nattenOm(telefon, nästa: nästa))
    }

    /// Natten om den finns (`XCTUnwrap` registrerar själv ett fel, så en natt som inte ska finnas prövas här).
    func nattenOm(_ telefon: Telefon, nästa: Bool) -> NightResult? {
        let behövs = Set(K18Days.stems(wakeDay: dag, includeNext: nästa))
        let filer = telefon.dygnsfiler(zon: zon).filter { behövs.contains($0.stem) }
        // Reservzonen är telefonens, som appen ger den: när bara dygnet efter finns kommer nattens zon därifrån.
        return K18Days.compute(wakeDay: dag, files: filer, fallbackOffsetSeconds: zon)
    }

    /// K18-sekunderna telefonen har, var och en en gång.
    func sekunder(_ telefon: Telefon) -> Set<Int> {
        Set(K18Series(notifications: telefon.disk).records.map(\.time))
    }

    // MARK: En hel natt

    func testEnHelNattHämtasPåMorgonenOchBlirSammaNattSomFacit() throws {
        var band = PåhittatBand(poster: natt.records, perBit: Self.perBit)
        let bitar = band.minne.count
        XCTAssertGreaterThan(natt.records.count, 6 * 3600, "en hel natt, inte ett utdrag")
        var telefon = Telefon(now: morgon)
        XCTAssertEqual(telefon.hämta(&band), .complete)
        XCTAssertTrue(band.tomt, "allt kvitterat: bandets minne är tomt")
        XCTAssertEqual(band.kvitterade, bitar)
        XCTAssertEqual(sekunder(telefon), Set(natt.records.map(\.time)), "varje sekund en gång")
        XCTAssertTrue(try nattenUr(telefon) == facit(), "natten ur hämtningen skiljer sig från facit")
    }

    // MARK: Avbrott som tas upp igen

    func testTappatBandMittIEnBitTasUppNästaGångUtanEnFörloradSekund() throws {
        var band = PåhittatBand(poster: natt.records, perBit: Self.perBit)
        var telefon = Telefon(now: morgon)
        // Mitt i en bit: varken början eller slutet av den.
        XCTAssertEqual(telefon.hämta(&band, avbrott: .tappatEfter(10 * (Self.perBit + 3) + 17)),
                       .stopped(.disconnected))
        XCTAssertFalse(band.tomt, "den avbrutna biten är inte kvitterad och ligger kvar")
        XCTAssertEqual(band.kvitterade, 10)
        telefon.now += 600
        XCTAssertEqual(telefon.hämta(&band), .complete)
        XCTAssertTrue(band.tomt)
        XCTAssertEqual(sekunder(telefon), Set(natt.records.map(\.time)))
        XCTAssertTrue(try nattenUr(telefon) == facit(), "halva biten två gånger ändrar inte natten")
    }

    func testAppenDödadMittIHämtningenTasUppNästaGång() throws {
        var band = PåhittatBand(poster: natt.records, perBit: Self.perBit)
        var telefon = Telefon(now: morgon)
        XCTAssertNil(telefon.hämta(&band, avbrott: .dödadEfter(5 * (Self.perBit + 3) + 2)))
        XCTAssertEqual(band.kvitterade, 5)
        telefon.now += 3600
        XCTAssertEqual(telefon.hämta(&band), .complete)
        XCTAssertTrue(band.tomt)
        XCTAssertTrue(try nattenUr(telefon) == facit())
    }

    func testSparfelKvitterarIngentingOchNästaHämtningFårAllt() throws {
        var band = PåhittatBand(poster: natt.records, perBit: Self.perBit)
        var telefon = Telefon(now: morgon)
        XCTAssertEqual(telefon.hämta(&band, sparaOK: false), .stopped(.saveFailed))
        XCTAssertEqual(band.kvitterade, 0, "inget kvitteras när sparandet misslyckas")
        XCTAssertEqual(telefon.hämta(&band), .complete)
        XCTAssertTrue(band.tomt)
        XCTAssertTrue(try nattenUr(telefon) == facit())
    }

    func testMångaAvbrottIRadTarÄndåHemHelaNatten() throws {
        var band = PåhittatBand(poster: natt.records, perBit: Self.perBit)
        var telefon = Telefon(now: morgon)
        var omgångar = 0
        // Bandet tappas efter vart 1 000:e notis, gång på gång, tills allt är hämtat.
        while !band.tomt && omgångar < 1000 {
            telefon.hämta(&band, avbrott: .tappatEfter(1000))
            telefon.now += 30
            omgångar += 1
        }
        XCTAssertTrue(band.tomt, "varje omgång kommer en bit längre")
        XCTAssertGreaterThan(omgångar, 10)
        XCTAssertTrue(try nattenUr(telefon) == facit())
    }

    // MARK: Whoop-appen samtidigt

    func testWhoopAppenSynkarSamtidigtIdunnStopparOchFårÄndåHelaNatten() throws {
        var band = PåhittatBand(poster: natt.records, perBit: Self.perBit)
        var telefon = Telefon(now: morgon)
        XCTAssertEqual(telefon.hämta(&band, avbrott: .whoopEfter(3 * (Self.perBit + 3) + 5)),
                       .stopped(.otherApp(command: 22)), "två som kvitterar samma bit: Idunn backar")
        // Whoop-appen tar 20 bitar och kvitterar dem; telefonen hör dem på samma länk.
        telefon.hör(band.whoopSynkar(bitar: 20))
        XCTAssertEqual(telefon.hämta(&band), .complete)
        XCTAssertTrue(band.tomt)
        XCTAssertEqual(sekunder(telefon), Set(natt.records.map(\.time)), "det Whoop kvitterade hördes ändå")
        XCTAssertTrue(try nattenUr(telefon) == facit())
    }

    // MARK: När på dygnet hämtningen hörs

    func testHämtningDagenEfterFinnsMedNärNattenSattSig() throws {
        var band = PåhittatBand(poster: natt.records, perBit: Self.perBit)
        // Telefonen var borta från bandet till nästa morgon.
        var telefon = Telefon(now: morgon.addingTimeInterval(24 * 3600))
        XCTAssertEqual(telefon.hämta(&band), .complete)
        XCTAssertNil(nattenOm(telefon, nästa: false), "före kl 12 dagen efter läses inte dygnet efter")
        XCTAssertTrue(try nattenUr(telefon, nästa: true) == facit())
    }
}
