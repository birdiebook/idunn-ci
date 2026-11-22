import SwiftUI
import Band
import Night
import Sound
import WhoopFrames

/// BESLUT B125. "Idag" skrivs bara när sidans dag är dagens uppvakningsdag, och en rad överst säger vad som händer
/// när dagens natt inte finns än (Morgonläge). Ändrar B82 och B83.
/// METOD M19 · METOD M25 · METOD M33 · BESLUT B19 · BESLUT B40 · BESLUT B52 · BESLUT B62 · BESLUT B63
/// Morgon, appens första vy, i skissens form (design/skiss.html, läget Nu): nattens pulskurva med stadierna under (ett
/// tryck öppnar Natten; sedan B77 står kurvan bara i Natten, och sedan B78 står sömnen med tiderna under ringarna), huvudtalen Återhämtning och Sömn i sina ringar (Återhämtning öppnar
/// Återhämtning, Sömn öppnar Natten), och ett mått per rad som en prick på det egna bandet. Bara Idunns nätter (BESLUT
/// B40): baslinjen byggs av dem, och innan normalområdet finns står hur långt den kommit. Svep åt höger för föregående
/// morgon, åt vänster tillbaka, eller pilarna i "‹ Idag ›" överst (BESLUT B82). Ett tryck på en rad mot ditt normala öppnar
/// måttets trend, och veckoremsan öppnar Återhämtnings (BESLUT B82). Uppe till höger bandets batteri och om det är
/// anslutet, som öppnar Data (BESLUT B38, B82). Det som hänger på spåret H ritas när talen finns (`Huvudtal`, BESLUT B65): Behov och
/// Ikväll med grundbehov och sömnbrist från första natten (H1), Sömn-ringen från första natten (H2, BESLUT B71) och
/// Återhämtnings-ringen och veckoremsan från andra (H3, BESLUT B72). Raderna räknas i IdunnKit (`MorningCard`).
struct MorningCardView: View {
    @EnvironmentObject private var recorder: Recorder
    /// BESLUT B65. Sömnbehovet och veckan utan klocka.
    @ObservedObject private var behov = SömnbehovModell.shared
    @State private var dagar: [MorningCard.Day] = []
    /// BESLUT B52. Senaste morgonens natt kommer ur K18 men dess kurva går inte att räkna fram (och
    /// därmed inte lagren); `kontrollerad` är sammanfattningen som sist prövades, så att en flik som visas
    /// igen inte räknar om natten.
    @State private var utanLager = false
    @State private var kontrollerad: NightSummary?

    var body: some View {
        NavigationStack {
            MorningCardScreen(days: dagar, summaries: Self.nights(recorder.summaries),
                              alert: Self.alert(status: recorder.status, statusRead: recorder.statusRead,
                                                link: recorder.link, summaries: recorder.summaries, now: Date(),
                                                lacksLayers: utanLager),
                              huvudtal: behov.huvudtal,
                              band: Bandstatus(batteri: recorder.battery, ansluten: recorder.link == .connected),
                              idag: Self.idag(now: Date()), läge: Self.läge(recorder, now: Date()),
                              // BESLUT B136. Dra ner på Morgon: samma omläsning som när appen kommer fram.
                              laddar: recorder.fetching || recorder.computingNights,
                              laddaOm: { recorder.refresh() })
        }
        .onChange(of: recorder.summaries, initial: true) { dagar = Self.days(summaries: recorder.summaries) }
        .task(id: senasteNatt) {
            // BESLUT B52. Samma uträkning som Nattens kurva öppnar med, på en bakgrundskö och en gång per
            // sammanfattning, och delad med kurvan (`NightLoader.sharedBundle`): öppnas natten medan den räknas
            // väntar kurvan på samma svar i stället för att räkna natten en gång till. Går kurvan inte att räkna
            // fram säger Morgon det som en felrad i stället för att visa en tunnare natt utan att något sägs.
            guard let s = senasteNatt, s.origin == .k18 else {
                utanLager = false
                kontrollerad = nil
                return
            }
            if kontrollerad == s { return }
            utanLager = false
            let b: NightLoader.CurveBundle? = await NightLoader.sharedBundle(for: s, priority: .utility)
            // En natt som hunnit bytas under uträkningen (en ny sammanfattning) lämnar sitt svar åt den nya.
            guard !Task.isCancelled, senasteNatt == s else { return }
            utanLager = NightChoice.lacksLayers(source: s.origin, layers: b?.layers)
            kontrollerad = s
        }
    }

    /// BESLUT B125. Dagens uppvakningsdag: väggklockans dag nu i telefonens zon, samma dagbegrepp som felraden
    /// (`alert`) och `NightLedger` använder för vilken dag en natt hör till.
    static func idag(now: Date) -> WakeDay {
        WakeDay(now, utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: now))
    }

    /// BESLUT B125. Vad som pågår för dagens natt: bandet anslutet, hämtningen och räkningen. "Data till" är klockslaget
    /// för bandets nyaste post som telefonen har (`ListenerStatus.lastK18Record`), bara om den ligger i dagens
    /// dygnsfönster (från kl 12 dagen före); hur långt hämtningen kommit är dess nyaste post (`fetchProgress.last`).
    static func läge(_ recorder: Recorder, now: Date) -> Morgonläge {
        let zon: Int = TimeZone.current.secondsFromGMT(for: now)
        let fönsterStart: Date = NightLedger.windowEnd(idag(now: now) - 1, utcOffsetSeconds: zon)
        let till: Date? = recorder.status.lastK18Record.flatMap { (d: Date) -> Date? in d > fönsterStart ? d : nil }
        let hämtat: Date? = recorder.fetchProgress.last.flatMap { (d: Date) -> Date? in d > fönsterStart ? d : nil }
        // BESLUT B149. Den längsta luckan i natten, så att en natt som saknas kan förklaras.
        let lucka: ClosedRange<Date>? = Morgonläge.lucka(minuter: recorder.status.k18Minutes, från: fönsterStart, nu: now)
        return Morgonläge.nu(ansluten: recorder.link == .connected, hämtar: recorder.fetching,
                             räknar: recorder.computingNights, dataTill: till, hämtatTill: hämtat, lucka: lucka)
    }

    /// BESLUT B52. Natten på senaste morgonen, om den kommer ur K18 (en gammal inspelning har inga lager
    /// att sakna).
    private var senasteNatt: NightSummary? {
        guard let dag = dagar.last?.day else { return nil }
        return Self.nights(recorder.summaries)[dag]
    }

    /// METOD M33. Morgnarna ur Idunns nätter, äldsta först.
    static func days(summaries: [NightSummary]) -> [MorningCard.Day] {
        MorningCard.days(idun: Trends.idunValues(summaries.compactMap(\.idunNight)))
    }

    /// METOD M14 · METOD M28. Nattens sammanfattning per uppvakningsdag (K18
    /// före en gammal inspelning), för kurvan och hudtemperaturens täckning.
    static func nights(_ summaries: [NightSummary]) -> [WakeDay: NightSummary] {
        var ut: [WakeDay: NightSummary] = [:]
        for s in NightSummary.preferred(summaries) {
            if let d = s.wakeDay { ut[d] = s }
        }
        return ut
    }

    /// METOD M29 · BESLUT B38 · BESLUT B52. Det som är fel med lyssnaren just nu, om något:
    /// Bluetooth, tystnad eller en natt med låg täckning. Täckningen är den
    /// färdiga K18-nattens som slutar idag. `lacksLayers`: senaste morgonens natt
    /// ur K18 saknar lager (`NightChoice.lacksLayers`).
    static func alert(status: ListenerStatus, statusRead: Bool, link: Recorder.Link,
                      summaries: [NightSummary], now: Date, lacksLayers: Bool = false) -> ListenerAlert? {
        let zon: Int = TimeZone.current.secondsFromGMT(for: now)
        let idag = WakeDay(now, utcOffsetSeconds: zon)
        let natt: NightSummary? = summaries.first { (s: NightSummary) -> Bool in
            s.origin == .k18 && s.preliminary != true && s.wakeDay == idag
        }
        return ListenerCheck.alert(status: status, nightCoverage: natt?.coverage, bluetooth: link.bluetooth,
                                   statusRead: statusRead, nightLacksLayers: lacksLayers, now: now,
                                   utcOffsetSeconds: zon)
    }
}

/// BESLUT B82. Bandets läge uppe till höger på Morgon, som värden: senast lästa batteriet i procent (bandets
/// batteritjänst, `Recorder.battery`) och om bandet är anslutet just nu.
struct Bandstatus: Equatable {
    var batteri: Int?
    var ansluten: Bool

    static let okänd = Bandstatus(batteri: nil, ansluten: false)
}

/// BESLUT B82. Bandet som i Whoop: en grön punkt när det är anslutet (grå annars), batteriets symbol och procent. Utan
/// känt batteri bara symbolen och punkten.
struct BandstatusVy: View {
    let status: Bandstatus

    private var symbol: String {
        guard let b = status.batteri else { return "battery.100percent" }
        if b >= 88 { return "battery.100percent" }
        if b >= 63 { return "battery.75percent" }
        if b >= 38 { return "battery.50percent" }
        if b >= 13 { return "battery.25percent" }
        return "battery.0percent"
    }

    /// BESLUT B123. Rött under 20 %.
    private var lågt: Bool {
        guard let b = status.batteri else { return false }
        return BandBattery.isLow(b)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.ansluten ? Tema.green : Tema.faint)
                .frame(width: 7, height: 7)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(status.batteri == nil ? Tema.faint : (lågt ? Tema.red : Tema.text))
            if let b = status.batteri {
                Text("\(b)%")
                    .font(Tema.mono(12))
                    .foregroundStyle(lågt ? Tema.red : Tema.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bandet")
        .accessibilityValue((status.batteri.map { (b: Int) -> String in "\(b) procent, " } ?? "")
            + (status.ansluten ? "anslutet" : "inte anslutet"))
    }
}

/// Morgnarna som värden; förhandsvisningen (IdunnProv) ritar samma vy. En sida
/// per morgon i en sidvisning: svep åt höger visar föregående morgon, åt
/// vänster tillbaka mot senaste, och pilarna i "‹ Idag ›" överst gör detsamma
/// (BESLUT B82). `start` är morgonen som visas först (en natt som öppnats ur
/// trendvyn); utan den visas senaste. Uppe till höger bandets läge, som öppnar
/// Data (BESLUT B38, B82), utom när kortet öppnats ur trendvyn.
/// `bundles` är nätternas kurvor när de redan är räknade (förhandsvisningen); annars räknar varje sida sin natts kurva
/// när den visas (`loadsCurves`).
struct MorningCardScreen: View {
    /// Äldsta först.
    let days: [MorningCard.Day]
    /// Nattens sammanfattning per dag, för kurvan och länkarna.
    var summaries: [WakeDay: NightSummary] = [:]
    /// METOD M29. Felraden; `nil` när lyssnaren mår bra. Står på senaste morgonen.
    var alert: ListenerAlert?
    var showsData = true
    var bundles: [WakeDay: NightLoader.CurveBundle] = [:]
    var huvudtal: Huvudtal = .tom
    var loadsCurves = true
    /// BESLUT B82. Bandets batteri och anslutning uppe till höger.
    var band: Bandstatus = .okänd
    /// BESLUT B125. Dagens uppvakningsdag; "Idag" skrivs bara för den. `nil` = senaste morgonen (förhandsvisningen).
    var idag: WakeDay?
    /// BESLUT B125. Vad som pågår på den tomma sidan Idag (när dagens natt inte finns än).
    var läge: Morgonläge?
    /// BESLUT B136. Dra ner för att läsa om: `laddar` håller snurran kvar, `laddaOm` startar. Utan `laddaOm`
    /// (förhandsvisningen) finns inget att dra i.
    var laddar: Bool = false
    var laddaOm: (() -> Void)? = nil
    @State private var vald: WakeDay?

    init(days: [MorningCard.Day], summaries: [WakeDay: NightSummary] = [:], alert: ListenerAlert? = nil,
         start: WakeDay? = nil, showsData: Bool = true, bundles: [WakeDay: NightLoader.CurveBundle] = [:],
         huvudtal: Huvudtal = .tom, loadsCurves: Bool = true, band: Bandstatus = .okänd,
         idag: WakeDay? = nil, läge: Morgonläge? = nil, laddar: Bool = false, laddaOm: (() -> Void)? = nil) {
        self.days = days
        self.summaries = summaries
        self.alert = alert
        self.showsData = showsData
        self.bundles = bundles
        self.huvudtal = huvudtal
        self.loadsCurves = loadsCurves
        self.band = band
        self.idag = idag
        self.läge = läge
        self.laddar = laddar
        self.laddaOm = laddaOm
        _vald = State(initialValue: start)
    }

    /// BESLUT B125. Sidorna, äldsta först: morgnarna med natt, och när `idag` är senare än den senaste natten en tom
    /// sida för dagens dag. Utan `idag` (förhandsvisningen) bara morgnarna.
    private var sidor: [WakeDay] {
        var d: [WakeDay] = days.map { (k: MorningCard.Day) -> WakeDay in k.day }
        if let i = idag, (d.last.map { (l: WakeDay) -> Bool in l < i } ?? true) { d.append(i) }
        return d
    }

    private var senaste: WakeDay? { sidor.last }

    /// BESLUT B125. Dagen som rubriken kallar Idag.
    private var idagsida: WakeDay? { idag ?? days.last?.day }

    /// Morgonen som visas: den valda om den finns, annars senaste.
    private var aktuell: WakeDay? {
        if let v = vald, sidor.contains(v) { return v }
        return senaste
    }

    /// Sidan som visas. Senaste morgonen är "ingen vald", så att en ny natt som
    /// räknas färdigt tar över kortet för den som inte har svept bakåt.
    private var sida: Binding<WakeDay> {
        Binding(get: { aktuell ?? WakeDay(daysSince1970: 0) },
                set: { (ny: WakeDay) in vald = ny == senaste ? nil : ny })
    }

    var body: some View {
        if showsData {
            // BESLUT B88. Eget huvud i stället för navigeringsfältet, så att "‹ Idag ›" står mitt på skärmen: fältet
            // lade dagväljaren åt vänster bredvid bandet.
            VStack(spacing: 0) {
                huvud
                innehåll
            }
            .background(Tema.bg)
            .navigationTitle("Morgon")
            .toolbar(.hidden, for: .navigationBar)
        } else {
            // Öppnad ur trendvyn: navigeringsfältet står kvar för bakåtknappen och svepet tillbaka.
            innehåll
                .navigationTitle("Morgon")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Tema.bg, for: .navigationBar)
                .toolbar {
                    if let dag = aktuell {
                        ToolbarItem(placement: .principal) { dagväljare(dag) }
                    }
                }
        }
    }

    /// BESLUT B82, B88. "‹ Idag ›" i mitten och bandet uppe till höger, som öppnar Data (BESLUT B38).
    private var huvud: some View {
        ZStack {
            if let dag = aktuell { dagväljare(dag) }
            HStack {
                Spacer(minLength: 0)
                NavigationLink { DataView() } label: {
                    BandstatusVy(status: band)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Tema.card))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Data")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    @ViewBuilder
    private var innehåll: some View {
        if aktuell != nil {
            TabView(selection: sida) {
                ForEach(sidor, id: \.self) { (dag: WakeDay) in
                    Group {
                        if let kort = days.first(where: { (k: MorningCard.Day) -> Bool in k.day == dag }) {
                            MorningPage(card: kort, summary: summaries[kort.day], preloaded: bundles[kort.day],
                                        alert: kort.day == senaste ? alert : nil, huvudtal: huvudtal,
                                        load: loadsCurves, laddar: laddar, laddaOm: laddaOm)
                        } else {
                            // BESLUT B125 · BESLUT B136. Dagens sida utan natt: samma sida som en morgon, tom på tal,
                            // med ett kort som säger vad som pågår.
                            MorningPage(card: MorningCard.day(dag, idun: [:]), summary: nil, preloaded: nil,
                                        alert: alert, huvudtal: huvudtal, load: false,
                                        läge: läge ?? Morgonläge.nu(ansluten: false, hämtar: false, räknar: false,
                                                                    dataTill: nil, hämtatTill: nil),
                                        laddar: laddar, laddaOm: laddaOm)
                        }
                    }
                    .tag(dag)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Tema.bg)
        } else {
            VStack(spacing: 12) {
                if let a = alert {
                    ListenerAlertRow(alert: a)
                        .padding(.horizontal)
                        .padding(.top)
                }
                ContentUnavailableView("Ingen natt än", systemImage: "sunrise")
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Tema.bg)
        }
    }

    /// BESLUT B82. "‹ Idag ›" som i Whoop: pilarna går en morgon med natt bakåt eller framåt (`MorningCard.step`), och
    /// mitten säger Idag för senaste morgonen och annars datumet. Svepet gör detsamma.
    private func dagväljare(_ dag: WakeDay) -> some View {
        let dagarna: [WakeDay] = sidor
        return HStack(spacing: 2) {
            dagpil("chevron.left", "Föregående morgon", MorningCard.step(dagarna, from: dag, by: -1))
            Text(dag == idagsida ? "Idag" : Fmt.weekday(dag) + " " + Fmt.dayMonth(dag))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Tema.text)
                .lineLimit(1)
                .frame(minWidth: 96)
            dagpil("chevron.right", "Nästa morgon", MorningCard.step(dagarna, from: dag, by: 1))
        }
    }

    private func dagpil(_ symbol: String, _ namn: String, _ mål: WakeDay?) -> some View {
        Button {
            guard let m = mål else { return }
            withAnimation { vald = m == senaste ? nil : m }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(mål == nil ? Tema.track : Tema.text)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(mål == nil)
        .accessibilityLabel(namn)
    }
}

/// BESLUT B125. Vad som pågår medan dagens natt inte finns än, som ett värde: de tre stegen (bandet, hämtningen,
/// räkningen) med var sitt läge, klockslaget för bandets nyaste post som telefonen har, och hur långt hämtningen kommit.
struct Morgonläge: Equatable {
    enum Läge: Equatable {
        case klart
        case pågår
        case väntar
    }

    var band: Läge
    var hämtar: Läge
    var räknar: Läge
    /// Klockslaget för nyaste posten från bandet som telefonen har, när det finns data för dygnet.
    var dataTill: Date?
    /// Hur långt hämtningen kommit (nyaste posten den fått hem), medan den pågår.
    var hämtatTill: Date?
    /// BESLUT B149. Den längsta tiden under natten utan data från bandet, om den är minst `minstaLucka`.
    var lucka: ClosedRange<Date>? = nil

    /// BESLUT B149. **antagande**. Kortare glapp än så här förklarar inte en natt som saknas.
    static let minstaLucka: TimeInterval = 20 * 60
    /// BESLUT B149. Glapp som slutar före så här långt efter dygnsfönstrets början (kl 12 + 6 h = kl 18) räknas inte:
    /// en eftermiddag utan band förklarar inte natten.
    static let nattBörjar: TimeInterval = 6 * 3600

    /// BESLUT B149. Den längsta luckan i bandets minuter (`ListenerStatus.k18Minutes`) mellan `från` och `nu`, med
    /// tiden från sista minuten till nu: minst `minstaLucka` lång och slutar efter `från + nattBörjar`. nil utan
    /// minuter i fönstret (då finns ingen data alls) eller utan en sådan lucka.
    static func lucka(minuter: Set<Int>, från: Date, nu: Date) -> ClosedRange<Date>? {
        let a: Int = Int(från.timeIntervalSince1970 / 60)
        let b: Int = Int(nu.timeIntervalSince1970 / 60)
        let m: [Int] = minuter.filter { (x: Int) -> Bool in x >= a && x <= b }.sorted()
        guard !m.isEmpty else { return nil }
        let natt: Date = från.addingTimeInterval(nattBörjar)
        var bäst: ClosedRange<Date>? = nil
        func pröva(_ start: Date, _ slut: Date) {
            guard slut.timeIntervalSince(start) >= minstaLucka, slut > natt else { return }
            let längd: TimeInterval = slut.timeIntervalSince(start)
            if bäst.map({ (l: ClosedRange<Date>) -> Bool in längd > l.upperBound.timeIntervalSince(l.lowerBound) }) ?? true {
                bäst = start...slut
            }
        }
        func tid(_ minut: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(minut * 60)) }
        for (x, y) in zip(m, m.dropFirst()) where y - x > 1 { pröva(tid(x + 1), tid(y)) }
        if let sista = m.last { pröva(tid(sista + 1), nu) }
        return bäst
    }

    /// Inget pågår (varken hämtning eller räkning) och ändå finns ingen natt: bandet har inte burits, eller natten
    /// har inte börjat.
    var ingenNatt: Bool { hämtar != .pågår && räknar != .pågår }

    var bandText: String { band == .pågår ? "Söker bandet" : "Bandet" }

    /// Pågår eller väntar: "Hämtar natten från bandet". Klart: "Hämtat från bandet". Med klockslaget för nyaste posten.
    var hämtarText: String {
        var t: String = hämtar == .klart ? "Hämtat från bandet" : "Hämtar natten från bandet"
        if let d = dataTill { t += " · data till " + Fmt.clock(date: d) }
        return t
    }

    var framstegText: String? {
        guard hämtar == .pågår, let d = hämtatTill else { return nil }
        return "hämtat till " + Fmt.clock(date: d)
    }

    /// Klockslaget står redan på hämtningens rad.
    var ingenNattText: String { "Ingen natt för idag än" }

    /// BESLUT B136. Kortets rubrik på den tomma sidan Idag: det som pågår just nu, räkningen före hämtningen.
    var rubrik: String {
        if räknar == .pågår { return "Natten räknas" }
        if hämtar == .pågår { return "Natten hämtas" }
        if band == .pågår { return "Söker bandet" }
        // BESLUT B149.
        if dataTill == nil { return "Ingen data från bandet" }
        if lucka != nil { return "Natten saknas" }
        return "Ingen sömn hittad"
    }

    /// BESLUT B136. Kortets text under rubriken, med vanliga ord.
    var brödtext: String {
        if räknar == .pågår {
            return "Natten är hämtad och räknas nu. Sömn och återhämtning står här om en stund."
        }
        if hämtar == .pågår {
            return "Idunn hämtar natten från bandet. Sömn och återhämtning står här när natten är räknad."
        }
        if band == .pågår {
            return "Idunn letar efter bandet. Natten hämtas när bandet är i närheten."
        }
        // BESLUT B149. Inget pågår och ingen natt: säg varför, ur det telefonen har.
        guard dataTill != nil else {
            return "Telefonen har ingen data från bandet sedan i går eftermiddag, så det finns ingen natt att räkna."
        }
        if let l = lucka {
            return "Bandet var inte anslutet " + Fmt.clock(date: l.lowerBound) + "–" + Fmt.clock(date: l.upperBound)
                + ", så natten går inte att räkna."
        }
        return "Datan från bandet täcker natten, men Idunn hittade ingen sömn i den."
    }

    /// BESLUT B136. Den lilla raden under texten: hur långt datan når och hur långt hämtningen kommit.
    var detalj: String? {
        let delar: [String] = [dataTill.map { (d: Date) -> String in "data till " + Fmt.clock(date: d) },
                               framstegText].compactMap { (t: String?) -> String? in t }
        return delar.isEmpty ? nil : delar.joined(separator: " · ")
    }

    /// Läget ur det telefonen vet. Hämtningen är klar när den inte pågår och data finns.
    static func nu(ansluten: Bool, hämtar: Bool, räknar: Bool, dataTill: Date?, hämtatTill: Date?,
                   lucka: ClosedRange<Date>? = nil) -> Morgonläge {
        let h: Läge = hämtar ? .pågår : (dataTill != nil ? .klart : .väntar)
        return Morgonläge(band: ansluten ? .klart : .pågår, hämtar: h, räknar: räknar ? .pågår : .väntar,
                          dataTill: dataTill, hämtatTill: hämtatTill, lucka: lucka)
    }
}

/// En morgon som en sida: rullningen och nattens kurva, som räknas när sidan visas.
private struct MorningPage: View {
    let card: MorningCard.Day
    let summary: NightSummary?
    let preloaded: NightLoader.CurveBundle?
    let alert: ListenerAlert?
    let huvudtal: Huvudtal
    let load: Bool
    /// BESLUT B136. Satt på den tomma sidan Idag: vad som pågår medan natten inte finns.
    var läge: Morgonläge? = nil
    var laddar: Bool = false
    var laddaOm: (() -> Void)? = nil
    @State private var bundle: NightLoader.CurveBundle?

    var body: some View {
        // BESLUT B136. Dra ner för att läsa om, med Idunns egen pil och ring i stället för systemets snurra.
        DraNer(laddar: laddar, ladda: laddaOm) {
            MorningCardStack(card: card, summary: summary, bundle: bundle ?? preloaded, alert: alert, huvudtal: huvudtal,
                             läge: läge)
        }
        .background(Tema.bg)
        .task(id: summary) {
            guard load, bundle == nil, let s = summary else { return }
            bundle = await NightLoader.sharedBundle(for: s, priority: .utility)
        }
    }
}

/// En morgon utan rullning, så att `ImageRenderer` kan rita den (IdunnProv).
struct MorningCardStack: View {
    let card: MorningCard.Day
    var summary: NightSummary?
    /// Nattens kurva och lager; `nil` medan den räknas, för en natt som saknar den, och i en bild utan den.
    var bundle: NightLoader.CurveBundle? = nil
    var alert: ListenerAlert?
    var huvudtal: Huvudtal = .tom
    /// BESLUT B136. Dagens sida innan natten finns: ringarna och raderna står tomma, och ett kort säger vad som pågår.
    var läge: Morgonläge? = nil
    @Environment(\.öppnaVäcktid) private var öppnaVäcktid

    /// BESLUT B65. Huvudtalen med morgonens sömnbehov (Behov, Ikväll och veckans fråga).
    private var h: Huvudtal { huvudtal.för(card.day) }

    private func rad(_ m: Trends.Measure) -> MorningCard.Row? {
        card.rows.first { (r: MorningCard.Row) -> Bool in r.measure == m }
    }

    /// Radens namn, med datum när raden visar en äldre natt än kortets.
    private func namn(_ bas: String, _ r: MorningCard.Row?) -> String {
        guard let r = r, r.day != card.day else { return bas }
        return bas + " " + Fmt.dayMonth(r.day)
    }

    private var sömn: String { summary?.sleepMinutes.map { (m: Double) -> String in Fmt.hm(minutes: m) } ?? "–" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let a = alert {
                ListenerAlertRow(alert: a).padding(.bottom, 12)
            }
            // BESLUT B77 · BESLUT B78. Ringarna först (B65: bara när ett tal finns), sedan sömnen med tiderna; kurvan finns i
            // Natten, som kortet öppnar.
            if let l = läge {
                // BESLUT B136. Tomma ringar, och under dem vad som pågår.
                tommaRingar.padding(.bottom, 12)
                lägeskort(l).padding(.bottom, 12)
            } else if h.recovery != nil || h.sleepScore != nil {
                ringar.padding(.bottom, 12)
            }
            sovkort.padding(.bottom, 12)
            if let n = card.baselineBuilding {
                BaselineBuildingRow(nights: n).padding(.bottom, 12)
            }
            mått
            if läge == nil {
                HStack(spacing: 12) {
                    Tecken(färg: Tema.band, text: "ditt normalområde")
                    Tecken(färg: Tema.text, text: "i natt", rund: true)
                }
                .font(.system(size: 10))
                .foregroundStyle(Tema.dim)
                .padding(.vertical, 8)
            } else {
                Color.clear.frame(height: 12)
            }
            if läge == nil, h.bedtime != nil {
                ikväll.padding(.bottom, 12)
            }
            if h.last("recovery", days: 7, ending: card.day).contains(where: { (v: Double?) -> Bool in v != nil }) {
                veckan
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: Sömnen

    /// BESLUT B78. Hur länge du sov och mellan vilka tider, under ringarna; ett tryck öppnar Natten med kurvan.
    @ViewBuilder private var sovkort: some View {
        if let s = summary {
            NavigationLink {
                NightScreen(summary: s, huvudtal: h)
            } label: {
                sovrad
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Natten")
        } else {
            sovrad
        }
    }

    /// Insomning och uppvaknande som klockslag (METOD M52), annars ur sömnperioden.
    private var sovtider: String? {
        guard let s = summary else { return nil }
        if let a = s.onsetMinutes, let b = s.wakeMinutes {
            return Fmt.clock(minutes: a) + "–" + Fmt.clock(minutes: b)
        }
        guard let a = s.start, let b = s.end, let d = s.wakeDay else { return nil }
        let från: Double = Trends.clockMinutes(a, day: d, utcOffsetSeconds: s.utcOffsetSeconds)
        let till: Double = Trends.clockMinutes(b, day: d, utcOffsetSeconds: s.utcOffsetSeconds)
        return Fmt.clock(minutes: från) + "–" + Fmt.clock(minutes: till)
    }

    private var sovrad: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Kortrubrik(text: "Sömn")
                Text(sömn)
                    .font(Tema.mono(22, .bold))
                    .foregroundStyle(sömn == "–" ? Tema.faint : Tema.text)
            }
            Spacer(minLength: 8)
            if let t = sovtider {
                Text(t)
                    .font(Tema.mono(15))
                    .foregroundStyle(Tema.dim)
            }
            if summary != nil {
                Text("›").foregroundStyle(Tema.faint)
            }
        }
        .kort()
        .contentShape(Rectangle())
    }

    // MARK: Innan natten finns

    /// BESLUT B136. Ringarna utan tal: samma kort som en morgon, med ett streck i stället för siffran.
    private var tommaRingar: some View {
        HStack(spacing: 12) {
            huvudkort("Återhämtning", nil, Tema.ringTrack)
            huvudkort("Sömn", nil, Tema.ringTrack)
        }
    }

    /// BESLUT B125 · BESLUT B136. Vad som pågår medan dagens natt inte finns: en rubrik, en mening och hur långt det kommit.
    private func lägeskort(_ l: Morgonläge) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.rubrik)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tema.text)
            Text(l.brödtext)
                .font(.subheadline)
                .foregroundStyle(Tema.dim)
                .fixedSize(horizontal: false, vertical: true)
            if let d = l.detalj {
                Text(d)
                    .font(Tema.mono(11, .regular))
                    .foregroundStyle(Tema.faint)
                    .padding(.top, 2)
            }
        }
        .kort(16)
        .accessibilityElement(children: .combine)
    }

    // MARK: Huvudtalen (spåret H)

    private var ringar: some View {
        HStack(spacing: 12) {
            if let v = h.recovery {
                if summary != nil {
                    NavigationLink {
                        RecoveryScreen(day: card.day, huvudtal: h)
                    } label: {
                        huvudkort("Återhämtning", v, Tema.recovery(Double(v)))
                    }
                    .buttonStyle(.plain)
                } else {
                    huvudkort("Återhämtning", v, Tema.recovery(Double(v)))
                }
            }
            if let v = h.sleepScore {
                if let s = summary {
                    NavigationLink {
                        NightScreen(summary: s, huvudtal: h)
                    } label: {
                        huvudkort("Sömn", v, Tema.score(Double(v)))
                    }
                    .buttonStyle(.plain)
                } else {
                    huvudkort("Sömn", v, Tema.score(Double(v)))
                }
            }
        }
    }

    private func huvudkort(_ rubrik: String, _ värde: Int?, _ färg: Color) -> some View {
        VStack(spacing: 2) {
            HuvudRing(värde: värde, färg: färg)
            Text(rubrik.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Tema.dim)
                .padding(.top, 8)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }

    // MARK: Måtten, en rad var

    /// HRV, vilopuls, andning, hudtemperatur och sovtid; snarkning och det som väckte dig bara när de inträffar. BESLUT
    /// B82: ett tryck på ett mått öppnar dess trend med perioden som slutar kortets morgon; måttet över natten nås från
    /// Natten (kortet Över natten). Det som väckte dig öppnar ljudet över natten som förut.
    private var mått: some View {
        let hrv: MorningCard.Row? = rad(.hrv)
        let vilo: MorningCard.Row? = rad(.restingHeartRate)
        let andning: MorningCard.Row? = rad(.breathing)
        let hud: MorningCard.Row? = rad(.skinTemperature)
        let sov: MorningCard.Row? = rad(.sleep)
        let väckt: [NightSoundDigest.Waker] = card.day == summary?.wakeDay ? (summary?.sound?.wakers ?? []) : []
        let snarkar: MorningCard.Row? = card.snoring
        let visaMått: Bool = summary != nil
        let slutrad: Int = snarkar != nil || !väckt.isEmpty ? 0 : 1
        return VStack(spacing: 0) {
            trend(.hrv) {
                BandRad(namn: namn("HRV", hrv), text: hrv.map { (r: MorningCard.Row) -> String in Fmt.num(r.value) + " ms" },
                        värde: hrv?.value, område: hrv?.range, axel: hrv?.track, bra: 1, vidare: true,
                        bygger: hrv?.rangeBuilding ?? false)
            }
            trend(.resting) {
                BandRad(namn: namn("Vilopuls", vilo), text: vilo.map { (r: MorningCard.Row) -> String in Fmt.num(r.value) },
                        värde: vilo?.value, område: vilo?.range, axel: vilo?.track, bra: -1, vidare: true,
                        bygger: vilo?.rangeBuilding ?? false)
            }
            trend(.breathing) {
                BandRad(namn: namn("Andning", andning),
                        text: andning.map { (r: MorningCard.Row) -> String in Fmt.num(r.value, 1) },
                        värde: andning?.value, område: andning?.range, axel: andning?.track, vidare: true,
                        bygger: andning?.rangeBuilding ?? false)
            }
            trend(.skin) {
                hudrad(hud, sista: false, vidare: true)
            }
            trend(.sleep) {
                BandRad(namn: namn("Sovtid", sov), text: sov.map { (r: MorningCard.Row) -> String in Fmt.hm(hours: r.value) },
                        värde: sov?.value, område: sov?.range, axel: sov?.track, bra: 1, vidare: true, sista: slutrad == 1,
                        bygger: sov?.rangeBuilding ?? false)
            }
            if let r = snarkar {
                trend(.snoring) {
                    BandRad(namn: namn("Snarkning", r), text: Fmt.num(r.value, 1), värde: r.value, område: r.range,
                            axel: r.track, bra: -1, vidare: true, sista: väckt.isEmpty)
                }
            }
            if !väckt.isEmpty {
                länk(.ljud, visaMått) {
                    VäckteRad(wakers: väckt, vidare: visaMått)
                }
            }
        }
        .radkort()
    }

    /// Hudtemperaturen som avvikelse mot normalområdets medel (METOD M25); utan område graderna.
    @ViewBuilder private func hudrad(_ r: MorningCard.Row?, sista: Bool, vidare: Bool) -> some View {
        if let r = r, let a = r.deviation, let ref = r.reference {
            let o: ClosedRange<Double>? = r.range.map { (x: ClosedRange<Double>) -> ClosedRange<Double> in
                (x.lowerBound - ref)...(x.upperBound - ref)
            }
            BandRad(namn: namn("Hudtemp", r), text: Fmt.signedDegrees(a), värde: a, område: o, bra: 0, vidare: vidare,
                    sista: sista, bygger: r.rangeBuilding)
        } else if let r = r {
            BandRad(namn: namn("Hudtemp", r), text: Fmt.num(r.value, 1) + "°", värde: r.value, område: r.range,
                    axel: r.track, vidare: vidare, sista: sista)
        } else {
            BandRad(namn: "Hudtemp", vidare: vidare, sista: sista)
        }
    }

    /// BESLUT B82. Raden som en länk till måttets trend, med perioden som slutar kortets morgon.
    private func trend<Inre: View>(_ m: TidMått, @ViewBuilder _ inre: () -> Inre) -> some View {
        NavigationLink {
            TrendsView(mått: m, slut: card.day)
        } label: {
            inre()
        }
        .buttonStyle(.plain)
    }

    /// Raden som en länk till måttet över natten, när nattens sammanfattning finns (det som väckte dig).
    @ViewBuilder private func länk<Inre: View>(_ m: NightMetric, _ aktiv: Bool,
                                               @ViewBuilder _ inre: () -> Inre) -> some View {
        let innehåll: Inre = inre()
        if aktiv, let s = summary {
            NavigationLink {
                NightMetricScreen(metric: m, summary: s)
            } label: {
                innehåll
            }
            .buttonStyle(.plain)
        } else {
            innehåll
        }
    }

    // MARK: Ikväll och veckan (spåret H)

    /// BESLUT B65 · BESLUT B75 · METOD M53. Läggdags ikväll för bästa förväntade sömnpoäng, och vad behovet vilar på:
    /// grundbehovet med sin osäkerhet (lärt ur nätterna, även den senaste) och sömnbristen efter natten.
    private var ikväll: some View {
        Button {
            // BESLUT B74 · BESLUT B102. Ett tryck öppnar bladet Upp i morgon för morgonen efter kortets natt, med den
            // satta tiden eller det vanliga uppvaknandet på hjulet.
            if let start = h.wakeSet ?? h.wake {
                let uppdag: Int = card.day.daysSince1970 + 1
                öppnaVäcktid(Väcktidsval(start: Int(start.rounded()), schema: h.schema, uppdag: uppdag,
                                         engångGår: uppdag >= Väcktidsval.idag(), uträkning: h.kväll))
            }
        } label: {
            ikvällInnehåll
        }
        .buttonStyle(.plain)
    }

    /// BESLUT B74 · BESLUT B75. Den lilla raden: väcktiden när den är satt, och sovtiden som läggdags ger (läggdags för
    /// bästa förväntade sömnpoäng, M53). BESLUT B93: "sömn 7:46", utan "läggdags för"; utan tal står bara väcktiden.
    private var ikvällsText: String {
        let upp: String? = h.wakeSet.map { (w: Double) -> String in "upp " + Fmt.clock(minutes: w) }
        let sömn: String? = (h.tonightAsleep ?? h.tonightHours ?? h.needHours).map { (t: Double) -> String in
            "sömn " + Fmt.hm(hours: t)
        }
        let delar: [String] = [upp, sömn].compactMap { (s: String?) -> String? in s }
        return delar.joined(separator: " · ")
    }

    private var ikvällInnehåll: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Kortrubrik(text: "Ikväll")
                Text(h.bedtime.map { (m: Double) -> String in Fmt.clock(minutes: m) } ?? "–")
                    .font(Tema.mono(22, .bold))
                    .foregroundStyle(Tema.text)
                Text(ikvällsText)
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let g = h.tonightBase {
                    // BESLUT B81. Utan ±: osäkerheten krymper inte med dina nätter förrän grundbehovet har en egen källa.
                    ikvällsrad("Grundbehov", Fmt.hm(hours: g))
                }
                if let d = h.debtHours {
                    ikvällsrad("Sömnbrist", Fmt.hm(hours: d))
                }
            }
            .padding(.top, 2)
        }
        .kort()
    }

    private func ikvällsrad(_ namn: String, _ värde: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(namn.uppercased())
                .font(.system(size: 9))
                .tracking(1)
                .foregroundStyle(Tema.faint)
            Text(värde)
                .font(Tema.mono(13))
                .foregroundStyle(Tema.text)
        }
    }

    private var veckan: some View {
        let dagar: [WakeDay] = (0..<7).map { (k: Int) -> WakeDay in card.day - (6 - k) }
        let tal: [Double?] = h.last("recovery", days: 7, ending: card.day)
        // BESLUT B82. Veckoremsan öppnar Återhämtnings trend för veckan som slutar kortets morgon.
        return NavigationLink {
            TrendsView(mått: .recovery, period: .week, slut: card.day)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Kortrubrik(text: "Veckan", höger: "›", högerFärg: Tema.dim)
                HStack(alignment: .bottom) {
                    ForEach(0..<7, id: \.self) { (i: Int) in
                        let v: Double? = tal[i]
                        let c: Color = v.map { (x: Double) -> Color in Tema.recovery(x) } ?? Tema.track
                        VStack(spacing: 3) {
                            Text(v.map { (x: Double) -> String in "\(Int(x.rounded()))" } ?? "–")
                                .font(Tema.mono(10, .regular))
                                .foregroundStyle(v == nil ? Tema.faint : c)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(c)
                                .frame(width: 12, height: v.map { (x: Double) -> CGFloat in CGFloat(x * 0.38) } ?? 4)
                            Text(Fmt.weekday(dagar[i]))
                                .font(.system(size: 9))
                                .foregroundStyle(i == 6 ? Tema.text : Tema.faint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 64, alignment: .bottom)
            }
            .kort()
        }
        .buttonStyle(.plain)
    }
}

/// METOD M33 · BESLUT B40 · BESLUT B69. Innan normalområdet finns (färre än 7 nätter): hur långt det
/// kommit, som ett streck och en rad. Värdena står under utan band.
struct BaselineBuildingRow: View {
    let nights: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("baslinjen byggs: \(nights) av \(Baseline.minNightsForRange) nätter")
                .font(.footnote)
                .foregroundStyle(Tema.dim)
            ProgressView(value: Double(min(nights, Baseline.minNightsForRange)), total: Double(Baseline.minNightsForRange))
                .tint(Tema.accent)
        }
        .padding(12)
        .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// METOD M29 · BESLUT B38. Felraden på Morgon: vad som är fel och vad användaren
/// kan göra, med vanliga ord. Bara när något är fel; allt annat om lyssnaren
/// står på Data.
struct ListenerAlertRow: View {
    let alert: ListenerAlert
    var now = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Tema.yellow)
            Text(Self.text(alert, now: now))
                .font(.footnote)
                .foregroundStyle(Tema.dim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    static func text(_ alert: ListenerAlert, now: Date) -> String {
        switch alert {
        case .bluetoothNotAllowed:
            return "Idunn får inte använda Bluetooth – tillåt det i Inställningar."
        case .bluetoothOff:
            return "Bluetooth är av – slå på det, så kan Idunn höra bandet."
        case .neverHeard:
            return "Idunn har inte hört bandet än – öppna Idunn i kväll med bandet på handleden."
        case .silent(let since):
            return "Idunn har inte hört bandet sedan \(clock(since, now: now)) – öppna Idunn i kväll."
        case .lowCoverage(let fraction):
            return "Idunn hörde bara \(pct(fraction)) av natten – öppna Idunn i kväll."
        case .missingLayers:
            // BESLUT B52. Vardagsord, och det som faktiskt saknas: nattens kurva. Kortets rader (rörelse och
            // temperatur med) kommer ur den sparade sammanfattningen och står kvar.
            return "Nattens kurva går inte att visa – Idunn kunde inte läsa bandets data för natten."
        }
    }

    /// "22:14", eller "mån 22:14" när det var en annan dag.
    static func clock(_ d: Date, now: Date) -> String {
        if Calendar.current.isDate(d, inSameDayAs: now) { return d.formatted(.dateTime.hour().minute()) }
        return d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// METOD M44 · BESLUT B54 · BESLUT B63
/// Det som väckte dig: en symbol och ett klockslag per händelse (METOD M40: ett vaket pass började inom en
/// minut efter ljudet, och ljudet var inte följden av en rörelse). Raden finns bara när något väckte dig;
/// de första tre visas, resten som ett antal.
struct VäckteRad: View {
    let wakers: [NightSoundDigest.Waker]
    var vidare = false
    private static let visas = 3

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("Väckte dig")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
                if vidare {
                    Text("›").foregroundStyle(Tema.faint)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            ForEach(Array(wakers.prefix(Self.visas).indices), id: \.self) { (i: Int) in
                HStack(spacing: 4) {
                    SoundGlyph(soundClass: wakers[i].soundClass, owner: wakers[i].owner, woke: true, size: 10)
                    Text(SoundLook.clock(wakers[i].time)).font(Tema.mono(12)).foregroundStyle(Tema.text)
                }
            }
            if wakers.count > Self.visas {
                Text("+\(wakers.count - Self.visas)").font(Tema.mono(12)).foregroundStyle(Tema.dim)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Väckte dig")
        .accessibilityValue(wakers.map { SoundLook.word($0.soundClass) + " " + SoundLook.clock($0.time) }
            .joined(separator: ", "))
    }
}
