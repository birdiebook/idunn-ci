import SwiftUI
import Charts
import UIKit
import Night

/// METOD M16 · METOD M33 · METOD M51 · BESLUT B40 · BESLUT B62 · BESLUT B63 · BESLUT B82 · METOD M7
/// Trendvyn: ett mått över tid, öppnad från Morgon (BESLUT B82: ett tryck på en rad mot ditt normala, eller veckoremsans
/// ›, som öppnar Återhämtning). Överst valet av mått (en rullgardin i ren SwiftUI, så att alla mått nås) och perioden V,
/// M eller 6M; under dem "‹ datum – datum ›", som bläddrar en hel period bakåt eller framåt, periodens medel och
/// ändringen mot perioden före, och diagrammet i Whoops form och Idunns färger: V med varje dags tal och normalbandet,
/// M med linjen, bandet och senaste värdet, 6M med dagarna som en svag linje och ett streck per månad med månadens medel
/// och ändringen mot månaden före. Måtten ur spåret H finns i valet bara när deras serie finns (BESLUT B65): Sömnbrist
/// sedan H1 (METOD M53), Sömnpoäng sedan H2 (METOD M56) och Återhämtning sedan H3 (METOD M57).
/// Bara Idunns nätter (BESLUT B40). Ett tryck på en natt (V och M) öppnar nattens kort; håll och dra markerar en dag.
/// Serierna, perioderna och månaderna räknas i IdunnKit (`Trends`); här ritas de.
struct TrendsView: View {
    @EnvironmentObject private var recorder: Recorder
    /// BESLUT B65. Sömnbehovet: serierna Sömnbrist (och behovet) och nattens kort.
    @ObservedObject private var behov = SömnbehovModell.shared
    @State private var serier: [Trends.Series] = []
    @State private var dagar: [MorningCard.Day] = []
    @State private var öppnad: WakeDay?
    @State private var mått: TidMått
    @State private var period: Trends.Span
    /// Periodens slut; `nil` är senaste natten.
    @State private var slut: WakeDay?
    @State private var markerad: Date?
    @State private var valÖppet = false

    /// `slut`: morgonen vyn öppnades från, så att perioden slutar där (en äldre morgon ger en äldre period).
    init(mått: TidMått = .hrv, period: Trends.Span = .week, slut: WakeDay? = nil) {
        _mått = State(initialValue: mått)
        _period = State(initialValue: period)
        _slut = State(initialValue: slut)
    }

    var body: some View {
        Group {
            if serier.contains(where: { (s: Trends.Series) -> Bool in !s.points.isEmpty }) {
                ScrollView {
                    TrendStack(serier: serier, huvudtal: behov.huvudtal, mått: $mått, period: $period, slut: $slut,
                               markerad: $markerad, valÖppet: $valÖppet, öppna: { (d: WakeDay) in öppnad = d })
                }
                .background(Tema.bg)
            } else {
                ContentUnavailableView("Ingen data än", systemImage: "chart.xyaxis.line")
            }
        }
        .background(Tema.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Tema.bg, for: .navigationBar)
        .toolbar {
            // METOD M22. Nattlandskapet.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { LandscapeView() } label: { Image(systemName: "mountain.2") }
                    .accessibilityLabel("Landskap")
            }
        }
        // Nattens kort, med svepet och pilarna kvar: en natt i taget bakåt eller framåt.
        .navigationDestination(item: $öppnad) { dag in
            MorningCardScreen(days: dagar, summaries: MorningCardView.nights(recorder.summaries),
                              start: dag, showsData: false, huvudtal: behov.huvudtal,
                              idag: MorningCardView.idag(now: Date()),
                              läge: MorningCardView.läge(recorder, now: Date()))
        }
        .onChange(of: recorder.summaries, initial: true) { räkna() }
        .onChange(of: period) { markerad = nil }
        .onChange(of: mått) { markerad = nil }
        .onChange(of: slut) { markerad = nil }
    }

    /// Räknas bara när nätterna ändras, inte när en dag markeras.
    private func räkna() {
        serier = Self.series(summaries: recorder.summaries)
        dagar = MorningCardView.days(summaries: recorder.summaries)
    }

    /// METOD M16 · BESLUT B40. Serierna ur Idunns nätter.
    static func series(summaries: [NightSummary]) -> [Trends.Series] {
        Trends.series(idun: Trends.idunValues(summaries.compactMap(\.idunNight)), whoop: [:])
    }
}

/// Måtten i valet, i skissens ordning. Platserna för spåret H (Återhämtning, Sömnpoäng, Sömnbrist) har inget
/// `measure`: deras serier räknas i appen (`Huvudtal`).
enum TidMått: String, CaseIterable, Identifiable {
    case recovery
    case sleepScore
    case hrv
    case resting
    case meanHr
    case breathing
    case skin
    case sleep
    case debt
    case efficiency
    case deep
    case regularity
    case movement
    case snoring

    var id: String { rawValue }

    /// Måttet i IdunnKit; `nil` för Återhämtning, Sömnpoäng och Sömnbrist (spåret H, serierna i `Huvudtal`).
    var measure: Trends.Measure? {
        switch self {
        case .recovery, .sleepScore, .debt: return nil
        case .hrv: return .hrv
        case .resting: return .restingHeartRate
        case .meanHr: return .meanHeartRate
        case .breathing: return .breathing
        case .skin: return .skinTemperature
        case .sleep: return .sleep
        case .efficiency: return .efficiency
        case .deep: return .deepSleep
        case .regularity: return .regularity
        case .movement: return .movement
        case .snoring: return .snoring
        }
    }

    /// Nyckeln i `Huvudtal.series` för en plats i spåret H.
    var huvudNyckel: String? {
        switch self {
        case .recovery: return "recovery"
        case .sleepScore: return "sleepScore"
        case .debt: return "debt"
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .recovery: return "Återhämtning"
        case .sleepScore: return "Sömnpoäng"
        case .hrv: return "HRV"
        case .resting: return "Vilopuls"
        case .meanHr: return "Medelpuls"
        case .breathing: return "Andning"
        case .skin: return "Hudtemp"
        case .sleep: return "Sömn"
        case .debt: return "Sömnbrist"
        case .efficiency: return "Effektivitet"
        case .deep: return "Djupsömn"
        case .regularity: return "Regelbundenhet"
        case .movement: return "Rörelse"
        case .snoring: return "Snarkning"
        }
    }

    var unit: String {
        switch self {
        case .hrv: return " ms"
        case .movement: return " min"
        case .snoring: return " min/h"
        default: return ""
        }
    }

    /// Staplar för det som är en mängd per natt, annars en linje med normalbandet (V och M; 6M är alltid en linje).
    var stapel: Bool {
        switch self {
        case .recovery, .sleepScore, .sleep, .debt, .regularity: return true
        default: return false
        }
    }

    /// 1 när högre är bättre, −1 när lägre är bättre, 0 när ingen riktning är bättre.
    var bra: Int {
        switch self {
        case .recovery, .sleepScore, .hrv, .sleep, .efficiency, .deep, .regularity: return 1
        case .resting, .meanHr, .debt, .movement, .snoring: return -1
        case .breathing, .skin: return 0
        }
    }

    /// Staplarnas högsta värde (axeln börjar på noll); `nil` för en linje.
    var tak: Double? {
        switch self {
        case .recovery, .sleepScore, .regularity: return 100
        case .sleep: return 10
        case .debt: return 2
        default: return nil
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .recovery, .sleepScore, .efficiency, .regularity: return "\(Int(v.rounded()))%"
        case .hrv, .resting, .meanHr, .movement: return Fmt.num(v)
        case .breathing: return Fmt.num(v, 1)
        case .skin: return Fmt.num(v, 1) + "°"
        case .sleep, .debt: return Fmt.hm(hours: v)
        case .deep: return Fmt.hm(minutes: v)
        case .snoring: return Fmt.num(v, 1)
        }
    }

    /// Stapelns färg: Återhämtning och Sömnpoäng i trafikljus (spåret H), Sömnbrist efter läge (BESLUT B83, METOD M58:
    /// låg, måttlig, hög), annars Idunns blå.
    func färg(_ v: Double) -> Color {
        switch self {
        case .recovery: return Tema.recovery(v)
        case .sleepScore: return Tema.score(v)
        case .debt: return Tema.skuld(v)
        default: return Tema.accent
        }
    }

    /// METOD M51 · BESLUT B82. En ändring som blivit sämre för måttet: orange som i Whoop, aldrig röd; samma orange som
    /// Sömn mot behov använder för dåligt (BESLUT B83).
    static let sämre: Color = Behovsläge.dålig.färg

    /// METOD M51 · BESLUT B82. Ändringens färg: grön när den är bra för måttet, orange när den är dålig, grå för ett mått
    /// utan riktning (andning, hudtemp) och för en ändring under en procent.
    func ändringsfärg(_ d: Double) -> Color {
        guard bra != 0, abs(d * 100) >= 1 else { return Tema.dim }
        return (d > 0) == (bra > 0) ? Tema.green : Self.sämre
    }

    /// "▲ 4 %" eller "▼ 4 %".
    static func ändringstext(_ d: Double) -> String {
        (d > 0 ? "▲ " : "▼ ") + Fmt.num(abs(d * 100)) + " %"
    }
}

/// Valet, bläddringen, medlet och diagrammet utan rullning, så att `ImageRenderer` kan rita dem (IdunnProv). Alla
/// knappar är ren SwiftUI.
struct TrendStack: View {
    let serier: [Trends.Series]
    var huvudtal: Huvudtal = .tom
    @Binding var mått: TidMått
    @Binding var period: Trends.Span
    /// Periodens slut; `nil` är senaste natten.
    @Binding var slut: WakeDay?
    @Binding var markerad: Date?
    /// Rullgardinen med alla mått är öppen.
    @Binding var valÖppet: Bool
    var öppna: (WakeDay) -> Void

    init(serier: [Trends.Series], huvudtal: Huvudtal = .tom, mått: Binding<TidMått>, period: Binding<Trends.Span>,
         slut: Binding<WakeDay?> = .constant(nil), markerad: Binding<Date?>, valÖppet: Binding<Bool> = .constant(false),
         öppna: @escaping (WakeDay) -> Void = { (_: WakeDay) in }) {
        self.serier = serier
        self.huvudtal = huvudtal
        _mått = mått
        _period = period
        _slut = slut
        _markerad = markerad
        _valÖppet = valÖppet
        self.öppna = öppna
    }

    /// Sista och första natten i något mått: bläddringens gränser.
    private var senaste: WakeDay { Trends.lastDay(serier) ?? WakeDay(daysSince1970: 0) }
    private var första: WakeDay { Trends.firstDay(serier) ?? senaste }

    /// Periodens slut: det valda, högst senaste natten.
    private var periodslut: WakeDay { min(slut ?? senaste, senaste) }

    /// Måttets serie: Idunns, eller för en plats i spåret H dess serie ur `Huvudtal` (Sömnbrist ur sömnbehovet, B65;
    /// Sömnpoäng och Återhämtning ur H2 och H3, B71 och B72).
    private func serie(_ m: TidMått) -> Trends.Series? {
        if let mm = m.measure { return serier.first { (s: Trends.Series) -> Bool in s.measure == mm } }
        guard let n = m.huvudNyckel else { return nil }
        return Trends.series(.sleep, idun: huvudtal.series[n] ?? [:], whoop: [:])
    }

    var body: some View {
        let ov: Trends.Overview? = serie(mått).map { (s: Trends.Series) -> Trends.Overview in
            Trends.overview(s, span: period, end: periodslut)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                måttval
                Spacer(minLength: 8)
                periodväljare
            }
            if valÖppet {
                måttlista
            }
            bläddring
            sammanfattning(ov)
            diagram(ov)
            if mått == .recovery || mått == .sleepScore {
                lägen(ov)
            }
            if mått == .debt {
                skuldlägen(ov)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    // MARK: Valet av mått och perioden

    /// BESLUT B65. Idunns mått, och ett mått ur spåret H bara när dess serie har något tal.
    private var synliga: [TidMått] {
        TidMått.allCases.filter { (m: TidMått) -> Bool in
            if m.measure != nil { return true }
            guard let n = m.huvudNyckel else { return false }
            return !(huvudtal.series[n] ?? [:]).isEmpty
        }
    }

    /// BESLUT B82. Måttets namn med en pil, som Whoops rullgardin; ett tryck öppnar listan med alla mått.
    private var måttval: some View {
        Button {
            valÖppet.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(mått.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Tema.text)
                Image(systemName: valÖppet ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tema.dim)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Välj mått")
        .accessibilityValue(mått.title)
    }

    private var måttlista: some View {
        let alla: [TidMått] = synliga
        return VStack(spacing: 0) {
            ForEach(alla) { (m: TidMått) in
                Button {
                    mått = m
                    valÖppet = false
                } label: {
                    HStack {
                        Text(m.title)
                            .font(.system(size: 14, weight: m == mått ? .semibold : .regular))
                            .foregroundStyle(m == mått ? Tema.text : Tema.dim)
                        Spacer(minLength: 8)
                        if m == mått {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Tema.accent)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if m != alla.last {
                    Rectangle().fill(Tema.line).frame(height: 1)
                }
            }
        }
        .radkort()
    }

    private func spann(_ s: Trends.Span) -> String {
        switch s {
        case .week: return "V"
        case .month: return "M"
        case .halfYear: return "6M"
        }
    }

    private var periodväljare: some View {
        HStack(spacing: 0) {
            ForEach(Trends.Span.allCases, id: \.self) { (s: Trends.Span) in
                Button {
                    period = s
                } label: {
                    Text(spann(s))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(s == period ? Tema.text : Tema.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(s == period ? Color(rgb: 0x323C42) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Bläddringen

    /// "4 nov", med året när perioden ligger ett annat år än senaste natten.
    private func datum(_ d: WakeDay) -> String {
        let år: Int = d.civil.year
        return år == senaste.civil.year ? Fmt.dayMonth(d) : Fmt.dayMonth(d) + " \(år)"
    }

    /// METOD M51 · BESLUT B82. "‹ 3 nov – 9 nov ›": pilarna flyttar perioden ett helt steg bakåt eller framåt
    /// (`Trends.stepped`), inte förbi senaste natten och inte till en period före den första.
    private var bläddring: some View {
        let från: WakeDay = periodslut - (period.days - 1)
        let bakåt: WakeDay? = Trends.stepped(end: periodslut, span: period, by: -1, first: första, last: senaste)
        let framåt: WakeDay? = Trends.stepped(end: periodslut, span: period, by: 1, first: första, last: senaste)
        return HStack(spacing: 0) {
            pil("chevron.left", "Föregående period", bakåt)
            Spacer(minLength: 4)
            Text(datum(från) + " – " + datum(periodslut))
                .font(Tema.mono(13))
                .foregroundStyle(Tema.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            pil("chevron.right", "Nästa period", framåt)
        }
        .padding(.vertical, 2)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func pil(_ symbol: String, _ namn: String, _ mål: WakeDay?) -> some View {
        Button {
            guard let m = mål else { return }
            slut = m >= senaste ? nil : m
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(mål == nil ? Tema.track : Tema.text)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(mål == nil)
        .accessibilityLabel(namn)
    }

    // MARK: Medlet och ändringen

    /// Den markerade dagens värde, om en dag är markerad.
    private func markerat(_ ov: Trends.Overview) -> (WakeDay, Double?)? {
        guard let t = markerad else { return nil }
        let d: WakeDay = WakeDay(nearest: t)
        let b: Trends.Bucket? = ov.buckets.first { (x: Trends.Bucket) -> Bool in x.day == d }
        return (d, b?.value)
    }

    private func sammanfattning(_ ov: Trends.Overview?) -> some View {
        let m: (WakeDay, Double?)? = ov.flatMap { (o: Trends.Overview) -> (WakeDay, Double?)? in markerat(o) }
        let rubrik: String = {
            if let x = m { return (Fmt.weekday(x.0) + " " + Fmt.dayMonth(x.0)).uppercased() }
            return "MEDEL"
        }()
        let tal: Double?
        if let x = m {
            tal = x.1
        } else {
            tal = ov?.mean
        }
        let ändring: Double? = m == nil ? ov?.change : nil
        let ändringsfärg: Color = ändring.map { (d: Double) -> Color in mått.ändringsfärg(d) } ?? Tema.dim
        let ändringstext: String = ändring.map { (d: Double) -> String in
            TidMått.ändringstext(d) + " mot perioden före"
        } ?? " "
        return VStack(alignment: .leading, spacing: 2) {
            Text(rubrik)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Tema.dim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(tal.map { (v: Double) -> String in mått.format(v) } ?? "–")
                    .font(Tema.mono(32, .bold))
                    .foregroundStyle(tal == nil ? Tema.faint : Tema.text)
                if tal != nil && mått.unit != "" {
                    Text(mått.unit).font(.system(size: 14)).foregroundStyle(Tema.dim)
                }
            }
            Text(ändringstext)
                .font(Tema.mono(11, .regular))
                .foregroundStyle(ändringsfärg)
        }
        .padding(.top, 4)
    }

    // MARK: Diagrammet

    private var etiketter: [String] {
        (0..<period.days).map { (k: Int) -> String in
            let d: WakeDay = periodslut - (period.days - 1 - k)
            return period == .week ? Fmt.weekday(d) : Fmt.dayMonth(d)
        }
    }

    @ViewBuilder private func diagram(_ ov: Trends.Overview?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let o = ov, o.buckets.contains(where: { (b: Trends.Bucket) -> Bool in b.value != nil }) {
                PeriodChart(mått: mått, översikt: o, markerad: $markerad, öppna: öppna)
                if o.span == .halfYear {
                    HStack(spacing: 12) {
                        Tecken(färg: Tema.text, text: "månadens medel", smal: true)
                        Tecken(färg: Tema.accent.opacity(0.4), text: "varje natt", smal: true)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.dim)
                } else if o.buckets.contains(where: { (b: Trends.Bucket) -> Bool in b.lower != nil }) {
                    Tecken(färg: Tema.band, text: "ditt normalområde")
                        .font(.system(size: 10))
                        .foregroundStyle(Tema.dim)
                }
            } else {
                TomtDiagram(etiketter: etiketter, höjd: 220)
            }
        }
        .kort()
    }

    /// Dagar per läge (Återhämtning och Sömnpoäng, spåret H); visas bara när måttet har en serie.
    private func lägen(_ ov: Trends.Overview?) -> some View {
        let gräns: [Double] = mått == .recovery ? [67, 34] : [85, 70]
        let värden: [Double] = (ov?.buckets ?? []).compactMap { (b: Trends.Bucket) -> Double? in b.value }
        let har: Bool = !värden.isEmpty
        let grönt: Int = värden.filter { (v: Double) -> Bool in v >= gräns[0] }.count
        let gult: Int = värden.filter { (v: Double) -> Bool in v < gräns[0] && v >= gräns[1] }.count
        let rött: Int = värden.count - grönt - gult
        let delar: [(Double, Color)]? = har ? [(Double(grönt), Tema.green), (Double(gult), Tema.yellow), (Double(rött), Tema.red)] : nil
        return VStack(alignment: .leading, spacing: 6) {
            Kortrubrik(text: "Dagar per läge")
            Fördelning(delar: delar)
            Nyckelrad(namn: "≥ \(Int(gräns[0])) %", värde: har ? "\(grönt)" : "–", färg: Tema.green)
            Nyckelrad(namn: "\(Int(gräns[1]))–\(Int(gräns[0]) - 1) %", värde: har ? "\(gult)" : "–", färg: Tema.yellow)
            Nyckelrad(namn: "< \(Int(gräns[1])) %", värde: har ? "\(rött)" : "–", färg: Tema.red)
        }
        .kort()
    }
}

extension TrendStack {
    /// BESLUT B83. Sömnbristens dagar per läge i perioden (låg, måttlig, hög), samma band som under Veckan i Natten.
    func skuldlägen(_ ov: Trends.Overview?) -> some View {
        let antal: [Int] = Lägesräkning.antal((ov?.buckets ?? []).map { (b: Trends.Bucket) -> Double? in b.value },
                                              { (v: Double) -> Skuldläge in Skuldläge(v) })
        let lägen: [Lägesband.Läge] = Skuldläge.allCases.map { (l: Skuldläge) -> Lägesband.Läge in
            Lägesband.Läge(namn: l.namn, gräns: l.gräns, färg: l.färg, antal: antal[l.rawValue])
        }
        return VStack(alignment: .leading, spacing: 6) {
            Kortrubrik(text: "Dagar per läge")
            Lägesband(lägen: lägen)
        }
        .kort()
    }
}

/// En punkt med ett värde och dess följd.
/// BESLUT B90. En punkt i normalbandet.
private struct Bandpunkt: Identifiable {
    var id: Int
    var tid: Date
    var lägre: Double
    var övre: Double
    var segment: Int
}

private struct PeriodPunkt: Identifiable {
    var bucket: Trends.Bucket
    var segment: Int
    var id: Int { bucket.day.daysSince1970 }
}

/// METOD M51 · BESLUT B82. Periodens diagram i Swift Charts, så att håll och dra och trycket på en natt fungerar som
/// förut (`tryckMarkering`). V: staplarna eller linjen med varje dags tal, och normalbandet. M: staplarna eller linjen
/// med bandet och senaste värdet utskrivet. 6M: dagarna som en svag linje och ett streck per kalendermånad med
/// månadens medel och ändringen mot månaden före (grön när den är bra för måttet, orange när den är dålig).
private struct PeriodChart: View {
    let mått: TidMått
    let översikt: Trends.Overview
    @Binding var markerad: Date?
    let öppna: (WakeDay) -> Void

    private var span: Trends.Span { översikt.span }

    private func start(_ b: Trends.Bucket) -> Date { b.day.startUTC }
    private func slut(_ b: Trends.Bucket) -> Date { (b.day + 1).startUTC }

    /// Punkterna med ett värde, och ett segment per följd (en lucka bryter linjen).
    private var punkter: [PeriodPunkt] {
        var ut: [PeriodPunkt] = []
        var segment = 0
        var förra = false
        for b in översikt.buckets {
            if b.value == nil {
                förra = false
                continue
            }
            if !förra { segment += 1 }
            ut.append(PeriodPunkt(bucket: b, segment: segment))
            förra = true
        }
        return ut
    }

    /// BESLUT B90. Normalbandets punkter: en i varje dags mitt, och bandets första och sista värde utdraget till dagens
    /// kant så att bandet når lika långt som rutorna gjorde. En dag utan band bryter bandet (ett nytt segment).
    private var bandpunkter: [Bandpunkt] {
        var ut: [Bandpunkt] = []
        var segment = 0
        var förra: Trends.Bucket? = nil
        func avsluta() {
            if let f = förra, let l = f.lower, let u = f.upper {
                ut.append(Bandpunkt(id: ut.count, tid: slut(f), lägre: l, övre: u, segment: segment))
            }
            förra = nil
        }
        for b in översikt.buckets {
            guard let l = b.lower, let u = b.upper else {
                avsluta()
                continue
            }
            if förra == nil {
                segment += 1
                ut.append(Bandpunkt(id: ut.count, tid: start(b), lägre: l, övre: u, segment: segment))
            }
            ut.append(Bandpunkt(id: ut.count, tid: b.day.noonUTC, lägre: l, övre: u, segment: segment))
            förra = b
        }
        avsluta()
        return ut
    }

    /// Månaderna med ett medel; i 6M.
    private var månader: [Trends.MonthMean] {
        översikt.months.filter { (m: Trends.MonthMean) -> Bool in m.mean != nil }
    }

    /// Staplar i V och M för en mängd per natt; 6M är alltid en linje.
    private var staplar: Bool { mått.stapel && span != .halfYear }

    /// Talen ovanför punkterna behöver luft överst.
    private var yDomän: ClosedRange<Double> {
        if staplar, let t = mått.tak {
            // BESLUT B65. Taket växer med datan (sömnbristen kan bli flera timmar), annars går staplarna ut ur rutan.
            let högst: Double = översikt.buckets.compactMap { (b: Trends.Bucket) -> Double? in b.value }.max() ?? 0
            return 0...(max(t, högst.rounded(.up)) * 1.15)
        }
        var alla: [Double] = []
        for b in översikt.buckets {
            if let v = b.value { alla.append(v) }
            if span != .halfYear {
                if let l = b.lower { alla.append(l) }
                if let u = b.upper { alla.append(u) }
            }
        }
        guard let lo = alla.min(), let hi = alla.max() else { return 0...1 }
        let luft: Double = hi - lo > 0 ? (hi - lo) : 1
        let upp: Double = span == .month ? 0.3 : 0.45
        return (lo - luft * 0.2)...(hi + luft * upp)
    }

    /// Natten närmast ett tryck, högst två dagar bort: bara V och M.
    private func nattNära(_ t: Date) -> WakeDay? {
        guard span != .halfYear else { return nil }
        let mitt: WakeDay = WakeDay(nearest: t)
        let nätter: [WakeDay] = översikt.buckets.compactMap { (b: Trends.Bucket) -> WakeDay? in b.value == nil ? nil : b.day }
        let närmast: WakeDay? = nätter.min { (a: WakeDay, b: WakeDay) -> Bool in
            abs(a.daysSince1970 - mitt.daysSince1970) < abs(b.daysSince1970 - mitt.daysSince1970)
        }
        guard let d = närmast, abs(d.daysSince1970 - mitt.daysSince1970) <= 2 else { return nil }
        return d
    }

    /// Axelns steg: en dag i V, en vecka i M och en månad i 6M.
    private var axelsteg: Calendar.Component { span == .halfYear ? .month : .day }

    private var axelformat: Date.FormatStyle {
        switch span {
        case .week: return Date.FormatStyle().weekday(.abbreviated)
        case .month: return Date.FormatStyle().day().month(.abbreviated)
        case .halfYear: return Date.FormatStyle().month(.abbreviated)
        }
    }

    /// Talet skrivs ut för varje dag i V, och för den sista i M.
    private func visaTal(_ p: PeriodPunkt) -> Bool {
        span == .week || p.id == punkter.last?.id
    }

    private func tal(_ v: Double) -> some View {
        Text(mått.format(v))
            .font(Tema.mono(10, .semibold))
            .foregroundStyle(Tema.text)
            .lineLimit(1)
            .fixedSize()
    }

    /// Månadens medel och ändringen mot månaden före; bara när månaden syns minst tio dagar, annars står strecket ensamt.
    @ViewBuilder private func månadstext(_ m: Trends.MonthMean, _ v: Double) -> some View {
        if m.last.daysSince1970 - m.first.daysSince1970 >= 9 {
            VStack(spacing: 1) {
                Text(mått.format(v))
                    .font(Tema.mono(10, .bold))
                    .foregroundStyle(Tema.text)
                if let c = m.change {
                    Text(TidMått.ändringstext(c))
                        .font(Tema.mono(9, .semibold))
                        .foregroundStyle(mått.ändringsfärg(c))
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    var body: some View {
        let dom: ClosedRange<Date> = översikt.first.startUTC ... (översikt.end + 1).startUTC
        let y: ClosedRange<Double> = yDomän
        Chart {
            if span != .halfYear {
                // BESLUT B90. Ett mjukt band genom dagarnas mitt i stället för en ruta per dag (som gav trappsteg).
                ForEach(bandpunkter) { (p: Bandpunkt) in
                    AreaMark(x: .value("Dag", p.tid), yStart: .value("Värde", p.lägre), yEnd: .value("Värde", p.övre),
                             series: .value("Band", p.segment))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Tema.band.opacity(0.6))
                }
            }
            if span == .halfYear {
                ForEach(punkter) { (p: PeriodPunkt) in
                    LineMark(x: .value("Dag", p.bucket.day.noonUTC), y: .value("Värde", p.bucket.value ?? 0),
                             series: .value("Linje", p.segment))
                        .foregroundStyle(Tema.accent.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
                ForEach(månader, id: \.monthStart) { (m: Trends.MonthMean) in
                    let v: Double = m.mean ?? 0
                    RuleMark(xStart: .value("Dag", m.first.startUTC), xEnd: .value("Dag", (m.last + 1).startUTC),
                             y: .value("Medel", v))
                        .foregroundStyle(Tema.text)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .annotation(position: .top, spacing: 4) { månadstext(m, v) }
                }
            } else if staplar {
                ForEach(punkter) { (p: PeriodPunkt) in
                    let v: Double = p.bucket.value ?? 0
                    let inskjut: TimeInterval = slut(p.bucket).timeIntervalSince(start(p.bucket)) * 0.2
                    RectangleMark(xStart: .value("Dag", start(p.bucket).addingTimeInterval(inskjut)),
                                  xEnd: .value("Dag", slut(p.bucket).addingTimeInterval(-inskjut)),
                                  yStart: .value("Värde", 0.0), yEnd: .value("Värde", v))
                        .foregroundStyle(mått.färg(v))
                        .annotation(position: .top, spacing: 3) {
                            if visaTal(p) { tal(v) }
                        }
                }
            } else {
                ForEach(punkter) { (p: PeriodPunkt) in
                    LineMark(x: .value("Dag", p.bucket.day.noonUTC), y: .value("Värde", p.bucket.value ?? 0),
                             series: .value("Linje", p.segment))
                        .foregroundStyle(Tema.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                }
                ForEach(punkter.filter { (p: PeriodPunkt) -> Bool in visaTal(p) }) { (p: PeriodPunkt) in
                    PointMark(x: .value("Dag", p.bucket.day.noonUTC), y: .value("Värde", p.bucket.value ?? 0))
                        .symbol { Circle().fill(Tema.accent).frame(width: 7, height: 7) }
                        .annotation(position: .top, spacing: 4) { tal(p.bucket.value ?? 0) }
                }
            }
            if let t = markerad {
                RuleMark(x: .value("Dag", t))
                    .foregroundStyle(Tema.dim)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: dom)
        .chartYScale(domain: y)
        .chartXAxis {
            AxisMarks(values: .stride(by: axelsteg, count: span == .month ? 7 : 1)) { (_: AxisValue) in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel(format: axelformat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { (v: AxisValue) in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(mått.format(d))
                            .font(Tema.mono(9, .regular))
                            .foregroundStyle(Tema.faint)
                    }
                }
            }
        }
        .tryckMarkering($markerad) { (t: Date) -> Bool in
            guard let d = nattNära(t) else { return false }
            öppna(d)
            return true
        }
        .frame(height: 220)
    }
}

/// METOD M7. Läget med symbol och ord; färgen bara på symbolen.
struct StatusBadge: View {
    let status: Baseline.Status

    var body: some View {
        Label {
            Text(status.label)
        } icon: {
            Image(systemName: status.symbol).foregroundStyle(status.color)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
    }
}

/// Förklaringen, en gång för alla diagram: bandet är det egna normala.
struct NormalLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 20, height: 10)
            Text("normalt")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Nattens punkt, fylld i källans färg. Med `ring` får den en kant i
/// ytans färg, så att den syns där den korsar en linje.
struct NightSymbol: View {
    let source: NightPoint.Source
    var size: CGFloat = 6
    var ring = false

    var body: some View {
        let färg = TrendColor.series(source)
        ZStack {
            if ring {
                Circle().fill(TrendColor.surface).frame(width: size + 4, height: size + 4)
            }
            if source == .idun {
                Circle().fill(färg).frame(width: size, height: size)
            } else {
                Circle()
                    .fill(TrendColor.surface)
                    .overlay(Circle().strokeBorder(färg, lineWidth: max(1.5, size / 5)))
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Färgerna (BESLUT B63): skissens tema (`Tema`) i hela appen. Idunns egna nätter är accentfärgen; Whoops färg används
/// bara på sidan Data. Lägena har egna, reserverade färger och står alltid med symbol och ord.
enum TrendColor {
    static let idun = Tema.accent
    static let whoop = Color.adaptive(light: 0xEB6834, dark: 0xD95926)
    static let good = Tema.green
    static let warning = Tema.yellow
    static let surface = Tema.card

    static func series(_ s: NightPoint.Source) -> Color {
        s == .idun ? idun : whoop
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
    }

    /// Eget steg för mörkt läge, inte en automatisk omvändning.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { t in UIColor(rgb: t.userInterfaceStyle == .dark ? dark : light) })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Trends.Period {
    var label: String {
        switch self {
        case .days30: return "30 d"
        case .days90: return "90 d"
        case .all: return "Allt"
        }
    }
}

extension Baseline.Status {
    var label: String {
        switch self {
        case .below: return "under"
        case .within: return "inom"
        case .above: return "över"
        }
    }

    var symbol: String {
        switch self {
        case .below: return "arrow.down.circle.fill"
        case .within: return "checkmark.circle.fill"
        case .above: return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        self == .within ? TrendColor.good : TrendColor.warning
    }
}

extension Trends.Measure {
    var title: String {
        switch self {
        case .hrv: return "HRV"
        case .restingHeartRate: return "Vilopuls"
        case .meanHeartRate: return "Medelpuls"
        case .sleep: return "Sömn"
        case .movement: return "Rörelse"
        case .snoring: return "Snarkning"
        case .regularity: return "Regelbundenhet"
        case .breathing: return "Andning"
        case .skinTemperature: return "Hudtemp"
        case .efficiency: return "Effektivitet"
        case .awakeTime: return "Vaken"
        case .lightSleep: return "Lätt sömn"
        case .deepSleep: return "Djupsömn"
        case .remSleep: return "REM"
        case .sleepOnset: return "Insomning"
        case .sleepWake: return "Uppvaknande"
        }
    }

    var symbol: String {
        switch self {
        case .hrv: return "waveform.path.ecg"
        case .restingHeartRate: return "heart"
        case .meanHeartRate: return "heart.circle"
        case .sleep: return "bed.double"
        case .movement: return "figure.walk"
        case .snoring: return "zzz"
        case .regularity: return "clock.arrow.circlepath"
        case .breathing: return "lungs"
        case .skinTemperature: return "thermometer.medium"
        case .efficiency: return "percent"
        case .awakeTime, .lightSleep, .deepSleep, .remSleep: return "bed.double"
        case .sleepOnset, .sleepWake: return "clock"
        }
    }

    var unit: String {
        switch self {
        case .hrv: return "ms"
        case .restingHeartRate: return "bpm"
        case .meanHeartRate: return "bpm"
        case .sleep: return "h"
        case .movement: return "min"
        case .snoring: return "min/h"
        case .regularity: return "SRI"
        case .breathing: return "/min"
        case .skinTemperature: return "°C"
        case .efficiency: return "%"
        case .awakeTime, .lightSleep, .deepSleep, .remSleep: return "min"
        case .sleepOnset, .sleepWake: return ""
        }
    }

    /// Talet med lagom många decimaler, i telefonens språk (decimalkomma).
    func text(_ x: Double) -> String {
        let heltal: Bool
        switch self {
        case .breathing, .skinTemperature, .sleep, .snoring: heltal = false
        default: heltal = true
        }
        let decimaler: Int = heltal ? 0 : 1
        return x.formatted(.number.precision(.fractionLength(decimaler)))
    }

    /// METOD M25. En avvikelse med tecken (+0,3), för hudtemperaturens rad.
    func signedText(_ x: Double) -> String {
        x.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
    }
}
