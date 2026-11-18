import SwiftUI
import Night
import Sound

/// BESLUT B62 · BESLUT B63 · BESLUT B71 · METOD M18 · METOD M32 · METOD M37 · METOD M50 · METOD M52 · METOD M56
/// Natten (tryck på kurvan eller på Sömn-ringen): Sömn, sömnperiodens längd och effektiviteten över kurvan, nattens kurva med axel, stadierna
/// som fyra brickor mot ditt normala (BESLUT B141), kortet Över natten (HRV, Hudtemp, Andning, Rörelse, Ljud och Slag
/// för slag), Sömnpoängen med sina tre delar, medelpuls, rörelse och snarkning mot ditt normala, Sömnbehov, Effektivitet med uppvak, Sömnstress,
/// Regelbundenhet och veckan. Det som hör till spåret H ritas när dess tal finns (BESLUT B65): sömnbehovet och
/// sömnbristen sedan H1, poängen sedan H2, stressen när H4 landar. Kortet "Ditt fönster" visas inte (BESLUT B71).
/// Nattens detaljerade kurva med puls, HRV och andning var för sig nås från listan Nätter på Data (`NightCurveView`).
///
/// METOD M55 · BESLUT B70. "Ändra" uppe till höger öppnar bladet med Somnade och Vaknade (`SömnÄndringBlad`); natten
/// räknas då om och visas som den blev, med ett märke vid Sömnperiod.
struct NightScreen: View {
    let summary: NightSummary
    var huvudtal: Huvudtal = .tom
    @EnvironmentObject private var recorder: Recorder
    @State private var bundle: NightLoader.CurveBundle?
    @State private var visaÄndra = false

    /// METOD M55. Natten som den är nu: efter en ändring räknas den om och listan publiceras på nytt, med samma id.
    private var natt: NightSummary {
        recorder.summaries.first { (s: NightSummary) -> Bool in s.id == summary.id } ?? summary
    }

    var body: some View {
        ScrollView {
            NightStack(summary: natt, bundle: bundle,
                       values: Trends.idunValues(recorder.summaries.compactMap(\.idunNight)), huvudtal: huvudtal)
        }
        .background(Tema.bg)
        .navigationTitle(natt.wakeDay.map { (d: WakeDay) -> String in Fmt.weekday(d) + " " + Fmt.dayMonth(d) } ?? "Natten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if natt.canEditSleep {
                    ÄndraKnapp(arbetar: recorder.recomputingEdit) { visaÄndra = true }
                }
            }
        }
        .sheet(isPresented: $visaÄndra) {
            blad
        }
        .task(id: natt) {
            bundle = await NightLoader.sharedBundle(for: natt, priority: .userInitiated)
        }
    }

    /// METOD M55 · BESLUT B70. Bladet för nattens sömnperiod: öppnar med ändringen om den finns, annars med perioden.
    @ViewBuilder private var blad: some View {
        let s: NightSummary = natt
        if let dag = s.wakeDay,
           let från = SömnÄndringBlad.startvärden(s, ändring: recorder.sleepEdits[dag]) {
            SömnÄndringBlad(dag: dag, zon: s.utcOffsetSeconds, frånSomnade: från.somnade, frånVaknade: från.vaknade,
                            ändrad: s.isEdited || recorder.sleepEdits[dag] != nil,
                            hittad: SömnÄndringBlad.hittadPeriod(s),
                            spara: { (e: SleepEdit) -> Void in
                                recorder.setSleepEdit(e, day: dag)
                                visaÄndra = false
                            },
                            återställ: {
                                recorder.setSleepEdit(nil, day: dag)
                                visaÄndra = false
                            },
                            avbryt: { visaÄndra = false })
                .presentationDetents([.large])
                .presentationBackground(Tema.bg)
        }
    }
}

/// Natten utan rullning, så att `ImageRenderer` kan rita den (IdunnProv). `values` är Idunns nätter (`Trends.idunValues`),
/// som ger varje mått dess normalområde och veckans staplar.
///
/// BESLUT B83. Ett tryck på ett stadium i förklaringen färgar kurvan där stadiet ligger; `stadium` är det valda när vyn
/// ritas första gången (provet ritar Natten med ett valt stadium).
struct NightStack: View {
    let summary: NightSummary
    var bundle: NightLoader.CurveBundle?
    var values: Trends.Values
    var huvudtal: Huvudtal
    @State private var valt: SleepStage?

    init(summary: NightSummary, bundle: NightLoader.CurveBundle? = nil, values: Trends.Values = [:],
         huvudtal: Huvudtal = .tom, stadium: SleepStage? = nil) {
        self.summary = summary
        self.bundle = bundle
        self.values = values
        self.huvudtal = huvudtal
        _valt = State(initialValue: stadium)
    }

    private var day: WakeDay { summary.wakeDay ?? WakeDay(daysSince1970: 0) }
    /// BESLUT B65. Sömnstressen (H4) ritas bara när den finns.
    private var harStress: Bool { h.stressHigh != nil || h.stressCurve != nil }
    /// BESLUT B65. Huvudtalen med nattens sömnbehov.
    private var h: Huvudtal { huvudtal.för(day) }
    private var layers: NightLayers.Layers? { bundle?.layers }
    private var hasStages: Bool { !(layers?.stages.isEmpty ?? true) }

    private func nr(_ m: Trends.Measure) -> MorningCard.Row? {
        MorningCard.nightRow(m, day: day, idun: values)
    }

    private var dagar7: [WakeDay] { (0..<7).map { (k: Int) -> WakeDay in day - (6 - k) } }
    private var etiketter7: [String] { dagar7.map { (d: WakeDay) -> String in Fmt.weekday(d) } }

    /// Måttets sju senaste nätter, äldst först; en natt utan tal är `nil`.
    private func vecka(_ m: Trends.Measure, _ skala: Double = 1) -> [Double?] {
        let v: [WakeDay: Double] = values[m] ?? [:]
        return dagar7.map { (d: WakeDay) -> Double? in v[d].map { (x: Double) -> Double in x * skala } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // BESLUT B141. Sömnen står över kurvan; ett valt stadium tar dess plats.
            nattHuvud
                .padding(.top, 10)
            NattKurva(curve: bundle?.curve, layers: layers, höjd: 220, axel: true, valt: valt, peka: true)
                .padding(.horizontal, -16)
                .padding(.top, 6)
            if harStadietal {
                brickor.padding(.top, 8)
                stunderRad.padding(.top, 8)
            }
            lagerkort.padding(.top, 10).padding(.bottom, 12)
            // BESLUT B65. Poängen (H2) ritas bara när talet finns.
            if h.sleepScore != nil {
                Sektion(text: "Sömnpoäng")
                poäng.padding(.top, 10).padding(.bottom, 12)
            }
            Sektion(text: "Puls, rörelse och ljud")
            pulsRörelseLjud.padding(.top, 10)
            if h.needHours != nil {
                Sektion(text: "Sömnbehov")
                behov.padding(.top, 10)
            }
            Sektion(text: "Effektivitet")
            effektivitet.padding(.top, 10)
            if harStress {
                Sektion(text: "Sömnstress")
                stress.padding(.top, 10)
            }
            Sektion(text: "Regelbundenhet")
            regelbundenhet.padding(.top, 10)
            Sektion(text: "Veckan")
            veckan.padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    // MARK: Överst

    private var periodMinuter: Double? {
        if let l = layers { return (l.period.upperBound - l.period.lowerBound) / 60 }
        if let a = summary.start, let b = summary.end { return b.timeIntervalSince(a) / 60 }
        return nil
    }

    /// BESLUT B83 · BESLUT B73. Början eller slutet av natten saknas i bandets data: några ord under Sömnperiod, så att
    /// det syns varför tiden kan vara fel. En ändrad period är användaren egen och märks inte.
    ///
    /// BESLUT B125. Bara en färdig natt får varningen. En preliminär natt med ett slutglapp säger i stället hur långt
    /// datan når ("hämtat till", periodens slut); början saknas säger den inget om.
    private var saknas: String? {
        guard !summary.isEdited else { return nil }
        if summary.preliminary == true {
            guard summary.incompleteEnd == true else { return nil }
            guard let slut = summary.end else { return "hämtas från bandet" }
            return "hämtat till " + Fmt.clock(date: slut)
        }
        switch (summary.incompleteStart == true, summary.incompleteEnd == true) {
        case (true, true): return "början och slutet saknas"
        case (true, false): return "början saknas"
        case (false, true): return "slutet saknas"
        case (false, false): return nil
        }
    }

    /// BESLUT B141. Toppen över kurvan. Utan valt stadium: Sömn stort, och till höger sömnperiodens längd och
    /// effektiviteten; klockslagen står bara vid strecken under kurvan. Med ett valt stadium: stadiets tid stort,
    /// andelen av natten och ditt normala.
    @ViewBuilder private var nattHuvud: some View {
        if let s = valt, let r = stadierad(s) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    etikett(r.namn, färg: r.färg)
                    Text(r.minuter.map { (m: Double) -> String in Fmt.hm(minutes: m) } ?? "–")
                        .font(Tema.mono(34, .bold))
                        .foregroundStyle(Tema.text)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(r.andel.map { (a: Double) -> String in "\(Int((a * 100).rounded())) % av natten" } ?? " ")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tema.text)
                    Text(normaltText(r))
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.dim)
                }
                .lineLimit(1)
            }
            .frame(minHeight: 62, alignment: .bottom)
        } else {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    etikett("Sömn", färg: nil)
                    Text(summary.sleepMinutes.map { (m: Double) -> String in Fmt.hm(minutes: m) } ?? "–")
                        .font(Tema.mono(34, .bold))
                        .foregroundStyle(summary.sleepMinutes == nil ? Tema.faint : Tema.text)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        // METOD M55 · BESLUT B70. Märket: sömnperioden är användaren ändring.
                        if summary.isEdited {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Tema.accent)
                                .accessibilityLabel("Ändrad")
                        }
                        Text(periodMinuter.map { (m: Double) -> String in "period " + Fmt.hm(minutes: m) }
                             ?? "period –")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Tema.text)
                    }
                    Text(summary.efficiency.map { (e: Double) -> String in "\(Int(e.rounded())) % effektiv" } ?? " ")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.dim)
                    if let u = saknas {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 9, weight: .bold))
                            Text(u)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Tema.yellow)
                    }
                }
                .lineLimit(1)
            }
            .frame(minHeight: 62, alignment: .bottom)
        }
    }

    private func etikett(_ namn: String, färg: Color?) -> some View {
        HStack(spacing: 6) {
            if let f = färg {
                RoundedRectangle(cornerRadius: 2).fill(f).frame(width: 9, height: 9)
            }
            Text(namn.uppercased())
                .font(.system(size: 10.5))
                .tracking(1.4)
                .foregroundStyle(Tema.faint)
        }
    }

    // MARK: Över natten

    private var lagerkort: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kortrubrik(text: "Över natten")
            HStack(spacing: 8) {
                lagerlänk(.hrv)
                lagerlänk(.temp)
                lagerlänk(.resp)
            }
            HStack(spacing: 8) {
                lagerlänk(.move)
                lagerlänk(.ljud)
                NavigationLink {
                    PoincareView(summary: summary)
                } label: {
                    lagerknapp("Slag för slag", "chart.dots.scatter")
                }
                .buttonStyle(.plain)
            }
        }
        .kort()
    }

    private func lagerlänk(_ m: NightMetric) -> some View {
        NavigationLink {
            NightMetricScreen(metric: m, summary: summary)
        } label: {
            lagerknapp(m.title, m.symbol)
        }
        .buttonStyle(.plain)
    }

    private func lagerknapp(_ namn: String, _ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Tema.accent)
                .frame(height: 20)
            Text(namn)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tema.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Tema.card2, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    // MARK: Sömnpoäng (spåret H, H2)

    /// BESLUT B71 · METOD M56. De tre delarna med lika vikt, i `Huvudtal.scoreParts` ordning.
    private static let poängDelar: [(String, String)] = [
        ("Mängd", "sömn mot behov"), ("Kontinuitet", "få uppvak"), ("Regelbundenhet", "som dina nätter"),
    ]

    /// Delarna som har ett tal (BESLUT B65: regelbundenheten saknas första natten).
    private var delarMedTal: [(String, String, Double)] {
        (0..<Self.poängDelar.count).compactMap { (i: Int) -> (String, String, Double)? in
            guard let delar = h.scoreParts, i < delar.count, let v = delar[i] else { return nil }
            return (Self.poängDelar[i].0, Self.poängDelar[i].1, v)
        }
    }

    private var poäng: some View {
        let delar: [(String, String, Double)] = delarMedTal
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                HuvudRing(värde: h.sleepScore, färg: h.sleepScore.map { (v: Int) -> Color in
                    Tema.score(Double(v))
                } ?? Tema.faint, storlek: 84, linje: 7, siffra: 24)
                Text("Tre delar som väger lika. Grön från 85.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 4)
            ForEach(0..<delar.count, id: \.self) { (i: Int) in
                poängrad(delar[i].0, delar[i].1, delar[i].2, sista: i == delar.count - 1)
            }
        }
        .kort()
    }

    private func poängrad(_ namn: String, _ under: String, _ x: Double, sista: Bool) -> some View {
        let c: Color = Tema.score(x)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(namn).font(.system(size: 12)).foregroundStyle(Tema.dim)
                Text(under).font(.system(size: 10)).foregroundStyle(Tema.faint)
            }
            Spacer(minLength: 4)
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.track)
                Capsule().fill(c).frame(width: 92 * CGFloat(min(max(x, 0), 100) / 100))
            }
            .frame(width: 92, height: 6)
            Text("\(Int(x.rounded()))")
                .font(Tema.mono(14))
                .foregroundStyle(c)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !sista { Rectangle().fill(Tema.line).frame(height: 1) }
        }
    }

    // MARK: Stadierna, puls, rörelse och ljud mot ditt normala

    /// Ett stadium med nattens minuter, andelen av stadiernas summa och ditt normala (områdets mitt och området).
    /// `bra` är 1 när mer är bättre (sömnens stadier) och −1 när mindre är bättre (vaken).
    struct Stadierad {
        var stadium: SleepStage
        var namn: String
        var färg: Color
        var minuter: Double?
        var andel: Double?
        var område: ClosedRange<Double>?
        var bra: Int

        var normalt: Double? { område.map { (o: ClosedRange<Double>) -> Double in (o.lowerBound + o.upperBound) / 2 } }
        /// Skillnaden mot det normala i minuter.
        var skillnad: Double? {
            guard let v = minuter, let n = normalt else { return nil }
            return v - n
        }
        /// −1 sämre än området, 0 inom, 1 bättre än området; `nil` utan område.
        var läge: Int? {
            guard let v = minuter, let o = område else { return nil }
            if o.contains(v) { return 0 }
            return (v > o.upperBound) == (bra > 0) ? 1 : -1
        }
    }

    private static let stadieordning: [(SleepStage, String, Trends.Measure, Int)] = [
        (.wake, "Vaken", .awakeTime, -1), (.light, "Lätt", .lightSleep, 1), (.deep, "Djup", .deepSleep, 1),
        (.rem, "REM", .remSleep, 1),
    ]

    private func minuter(_ s: SleepStage) -> Double? {
        switch s {
        case .wake: return summary.awakeMinutes
        case .light: return summary.lightMinutes
        case .deep: return summary.deepMinutes
        case .rem: return summary.remMinutes
        }
    }

    private var stadierader: [Stadierad] {
        let total: Double = Self.stadieordning.reduce(0) { (t: Double, r: (SleepStage, String, Trends.Measure, Int))
            -> Double in
            t + (minuter(r.0) ?? 0)
        }
        return Self.stadieordning.map { (r: (SleepStage, String, Trends.Measure, Int)) -> Stadierad in
            let v: Double? = minuter(r.0)
            return Stadierad(stadium: r.0, namn: r.1, färg: NattRitning.färg(r.0), minuter: v,
                             andel: v.flatMap { (m: Double) -> Double? in total > 0 ? m / total : nil },
                             område: v == nil ? nil : nr(r.2)?.range, bra: r.3)
        }
    }

    private func stadierad(_ s: SleepStage) -> Stadierad? {
        stadierader.first { (r: Stadierad) -> Bool in r.stadium == s }
    }

    private var harStadietal: Bool {
        stadierader.contains { (r: Stadierad) -> Bool in r.minuter != nil }
    }

    /// "normalt 1:32 (+0:12)", eller "inget normalt än" innan området finns.
    private func normaltText(_ r: Stadierad) -> String {
        guard let n = r.normalt else { return "inget normalt än" }
        guard let d = r.skillnad else { return "normalt " + Fmt.hm(minutes: n) }
        return "normalt " + Fmt.hm(minutes: n) + " (" + Self.medTecken(d) + ")"
    }

    /// "+0:12", "−0:08", eller "±0" när skillnaden är under en halv minut.
    static func medTecken(_ minuter: Double) -> String {
        let m: Double = minuter.rounded()
        if m == 0 { return "±0" }
        return (m > 0 ? "+" : "−") + Fmt.hm(minutes: abs(m))
    }

    static func lägesfärg(_ läge: Int?) -> Color {
        switch läge {
        case .some(1): return Tema.accent
        case .some(-1): return Tema.yellow
        default: return Tema.faint
        }
    }

    /// BESLUT B141. Fyra brickor under kurvan: stadiet, nattens tid, en remsa med ditt normala område och en
    /// markering för natten, och skillnaden mot det normala. Skillnaden får färg bara utanför området (gul sämre,
    /// blå bättre, som bandraden). Ett tryck väljer stadiet (BESLUT B83); samma igen släcker.
    private var brickor: some View {
        HStack(spacing: 8) {
            ForEach(stadierader, id: \.stadium) { (r: Stadierad) in
                Button {
                    valt = valt == r.stadium ? nil : r.stadium
                } label: {
                    bricka(r)
                }
                .buttonStyle(Tryckyta())
                .disabled(!hasStages)
                .accessibilityAddTraits(valt == r.stadium ? .isSelected : [])
            }
        }
    }

    private func bricka(_ r: Stadierad) -> some View {
        let vald: Bool = valt == r.stadium
        let under: String = r.skillnad.map { (d: Double) -> String in Self.medTecken(d) }
            ?? r.andel.map { (a: Double) -> String in "\(Int((a * 100).rounded())) %" } ?? " "
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(r.färg).frame(width: 8, height: 8)
                Text(r.namn)
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
            }
            Text(r.minuter.map { (m: Double) -> String in Fmt.hm(minutes: m) } ?? "–")
                .font(Tema.mono(18, .bold))
                .foregroundStyle(r.minuter == nil ? Tema.faint : Tema.text)
            Normalremsa(värde: r.minuter, område: r.område, färg: r.färg)
                .frame(height: 5)
                .padding(.vertical, 2)
            Text(under)
                .font(Tema.mono(11))
                .foregroundStyle(r.skillnad == nil ? Tema.faint : Self.lägesfärg(r.läge))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(vald ? r.färg : Color.clear, lineWidth: 1.5)
        }
        .opacity(valt == nil || vald ? 1 : 0.4)
        .contentShape(Rectangle())
    }

    /// BESLUT B141. Under brickorna när ett stadium är valt: hur många stunder, den längsta och snittet.
    private var stunderRad: some View {
        var text: String = " "
        if let s = valt, let t = layers?.stunder(s) {
            text = "\(t.antal) \(t.antal == 1 ? "stund" : "stunder") · längsta \(Int((t.längst / 60).rounded())) min"
            if let m = minuter(s) { text += " · snitt \(Int((m / Double(t.antal)).rounded())) min" }
        }
        return Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Tema.dim)
            .lineLimit(1)
    }

    private var pulsRörelseLjud: some View {
        let medel: MorningCard.Row? = nr(.meanHeartRate)
        let rörelse: MorningCard.Row? = nr(.movement)
        let snark: MorningCard.Row? = nr(.snoring)
        return VStack(spacing: 0) {
            BandRad(namn: "Medelpuls", text: medel.map { (r: MorningCard.Row) -> String in Fmt.num(r.value) },
                    värde: medel?.value, område: medel?.range, axel: medel?.track, bra: -1)
            länk(.move) {
                BandRad(namn: "Rörelse", text: rörelse.map { (r: MorningCard.Row) -> String in Fmt.num(r.value) + " min" },
                        värde: rörelse?.value, område: rörelse?.range, axel: rörelse?.track, bra: -1, vidare: true)
            }
            länk(.ljud) {
                BandRad(namn: "Snarkning", text: snark.map { (r: MorningCard.Row) -> String in Fmt.num(r.value, 1) },
                        värde: snark?.value, område: snark?.range, axel: snark?.track, bra: -1, vidare: true, sista: true)
            }
        }
        .radkort()
    }

    @ViewBuilder private func länk<Inre: View>(_ m: NightMetric, @ViewBuilder _ inre: () -> Inre) -> some View {
        let innehåll: Inre = inre()
        NavigationLink {
            NightMetricScreen(metric: m, summary: summary)
        } label: {
            innehåll
        }
        .buttonStyle(.plain)
    }

    // MARK: Sömnbehov (spåret H)

    private var behov: some View {
        let sömn: Double? = summary.sleepMinutes.map { (m: Double) -> Double in m / 60 }
        let andel: String = {
            guard let b = h.needHours, b > 0, let s = sömn else { return "–" }
            return "\(Int((s / b * 100).rounded()))%"
        }()
        // BESLUT B94. Sömnen och behovet som två staplar på samma skala, med talet för varje stapels längd till höger.
        // Staplarna tonar in från vänster, så att blicken landar i änden. Behovets delar står som tecken under; en del
        // som är noll ritas inte.
        let behovet: Double? = h.needHours
        let skala: Double = max(behovet ?? 0, sömn ?? 0)
        let behovsdelar: [(Double, Color, String, String)] = {
            guard let a = h.needBase, let b = h.needStrain, let c = h.needDebt else { return [] }
            let alla: [(Double, Color, String, String)] = [
                (a, Tema.still, "Grund", ""), (b, Tema.rem, "Pass", "+"), (c, Tema.yellow, "Brist", "+"),
            ]
            // Under en halv minut skrivs delen som 0:00, och då ritas den inte.
            return alla.filter { (d: (Double, Color, String, String)) -> Bool in (d.0 * 60).rounded() >= 1 }
        }()
        let behovsstapel: [(Double, Color)] = {
            if !behovsdelar.isEmpty {
                return behovsdelar.map { (d: (Double, Color, String, String)) -> (Double, Color) in (d.0, d.1) }
            }
            return behovet.map { (b: Double) -> [(Double, Color)] in [(b, Tema.still)] } ?? []
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(andel).font(Tema.mono(26, .bold)).foregroundStyle(andel == "–" ? Tema.faint : Tema.text)
            stapelrad(sömn.map { (s: Double) -> [(Double, Color)] in [(s, Tema.accent)] } ?? [],
                      andel: skala > 0 ? (sömn ?? skala) / skala : 1,
                      tal: sömn.map { (s: Double) -> String in Fmt.hm(hours: s) })
                .padding(.top, 4)
            stapelrad(behovsstapel, andel: skala > 0 ? (behovet ?? skala) / skala : 1,
                      tal: behovet.map { (b: Double) -> String in Fmt.hm(hours: b) })
            if !behovsdelar.isEmpty {
                HStack(spacing: 12) {
                    ForEach(0..<behovsdelar.count, id: \.self) { (i: Int) in
                        let d: (Double, Color, String, String) = behovsdelar[i]
                        HStack(spacing: 4) {
                            Tecken(färg: d.1, text: d.2).foregroundStyle(Tema.dim)
                            Text(d.3 + Fmt.hm(hours: d.0)).font(Tema.mono(10)).foregroundStyle(Tema.text)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10))
                .lineLimit(1)
                .padding(.top, 2)
            }
        }
        .kort()
    }

    /// BESLUT B94. En stapel som fyller `andel` av bredden och tonar in från vänster, med sitt tal till höger.
    private func stapelrad(_ delar: [(Double, Color)], andel: Double, tal: String?) -> some View {
        HStack(spacing: 10) {
            GeometryReader { (g: GeometryProxy) in
                Delstapel(delar: delar, höjd: 10)
                    .frame(width: g.size.width * CGFloat(min(max(andel, 0), 1)))
                    .mask(LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0.1), location: 0),
                                                 Gradient.Stop(color: Color.black, location: 0.62)],
                                         startPoint: .leading, endPoint: .trailing))
            }
            .frame(height: 10)
            Text(tal ?? "–")
                .font(Tema.mono(15))
                .foregroundStyle(tal == nil ? Tema.faint : Tema.text)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    private func behovsrad(_ c: Color, _ namn: String, _ v: Double?, _ tecken: String, sd: Double? = nil) -> some View {
        HStack {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
                Text(namn)
            }
            Spacer(minLength: 4)
            // BESLUT B81. Grundbehovet utan ±.
            Text(v.map { (h: Double) -> String in tecken + Fmt.hm(hours: h) }
                 ?? "–")
                .font(Tema.mono(12))
                .foregroundStyle(v == nil ? Tema.faint : Tema.text)
        }
        .font(.system(size: 12))
        .foregroundStyle(Tema.dim)
    }

    // MARK: Effektivitet

    private var effektivitet: some View {
        let sov: Double? = summary.sleepMinutes
        let vaken: Double? = {
            guard let p = periodMinuter, let s = sov else { return nil }
            return max(0, p - s)
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.efficiency.map { (e: Double) -> String in "\(Int(e.rounded()))%" } ?? "–")
                    .font(Tema.mono(26, .bold))
                    .foregroundStyle(summary.efficiency == nil ? Tema.faint : Tema.text)
                Spacer()
                Text(summary.wakeBouts.map { (n: Int) -> String in "\(n) uppvak" } ?? "–")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
            }
            Effektivitetsrems(period: layers?.period, vakna: layers?.awake ?? [])
            behovsrad(Tema.accent, "Sovande", sov.map { (m: Double) -> Double in m / 60 }, "")
            behovsrad(Tema.awake, "Vaken", vaken.map { (m: Double) -> Double in m / 60 }, "")
        }
        .kort()
    }

    // MARK: Sömnstress (spåret H)

    private var stress: some View {
        let hög: Double? = h.stressHigh
        let andel: String = {
            guard let h = hög, let s = summary.sleepMinutes, s > 0 else { return "–" }
            return "\(Int((h * 60 / s * 100).rounded()))%"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(andel).font(Tema.mono(26, .bold)).foregroundStyle(andel == "–" ? Tema.faint : Tema.text)
                Spacer()
                Text("av natten med hög stress").font(.system(size: 12)).foregroundStyle(Tema.dim)
            }
            Stresskurva(kurva: h.stressCurve)
            stressrad(Tema.red, "Hög", "≥ 2", h.stressHigh)
            stressrad(Tema.yellow, "Mellan", "1–2", h.stressMid)
            stressrad(Color(rgb: 0x4A6F8A), "Låg", "< 1", h.stressLow)
        }
        .kort()
    }

    private func stressrad(_ c: Color, _ namn: String, _ gräns: String, _ v: Double?) -> some View {
        HStack {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
                Text(namn)
                Text(gräns).foregroundStyle(Tema.faint)
            }
            Spacer(minLength: 4)
            Text(v.map { (h: Double) -> String in Fmt.hm(hours: h) } ?? "–")
                .font(Tema.mono(12))
                .foregroundStyle(v == nil ? Tema.faint : Tema.text)
        }
        .font(.system(size: 12))
        .foregroundStyle(Tema.dim)
    }

    // MARK: Regelbundenhet

    private var regelbundenhet: some View {
        let sri: Double? = (values[.regularity] ?? [:])[day]
        let onset: [Double?] = vecka(.sleepOnset, 1.0 / 60)
        let wake: [Double?] = vecka(.sleepWake, 1.0 / 60)
        let nätter: [Regeldiagram.Natt] = (0..<7).map { (i: Int) -> Regeldiagram.Natt in
            Regeldiagram.Natt(insomning: onset[i].map { (h: Double) -> Double in h + 24 },
                              uppvaknande: wake[i].map { (h: Double) -> Double in h + 24 }, etikett: etiketter7[i])
        }
        let normalA: ClosedRange<Double>? = nr(.sleepOnset)?.range.map { (r: ClosedRange<Double>) -> ClosedRange<Double> in
            (r.lowerBound / 60 + 24)...(r.upperBound / 60 + 24)
        }
        let normalB: ClosedRange<Double>? = nr(.sleepWake)?.range.map { (r: ClosedRange<Double>) -> ClosedRange<Double> in
            (r.lowerBound / 60 + 24)...(r.upperBound / 60 + 24)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(sri.map { (v: Double) -> String in "\(Int(v.rounded()))%" } ?? "–")
                    .font(Tema.mono(26, .bold))
                    .foregroundStyle(sri == nil ? Tema.faint : Tema.text)
                Spacer()
                Text("senaste veckan").font(.system(size: 12)).foregroundStyle(Tema.dim)
            }
            Regeldiagram(nätter: nätter, normalInsomning: normalA, normalUppvaknande: normalB)
            Tecken(färg: Tema.band, text: "din vanliga insomning och uppvakning")
                .font(.system(size: 10))
                .foregroundStyle(Tema.dim)
        }
        .kort()
    }

    // MARK: Veckan

    private var veckan: some View {
        let sömn: [Double?] = vecka(.sleep)
        let behovet: [Double?] = h.last("need", days: 7, ending: day)
        let harBehov: Bool = behovet.contains { (v: Double?) -> Bool in v != nil }
        let brist: [Double?] = h.last("debt", days: 7, ending: day)
        let harBrist: Bool = brist.contains { (v: Double?) -> Bool in v != nil }
        let stressD: [Double?] = h.last("stress", days: 7, ending: day)
        let harStressVecka: Bool = stressD.contains { (v: Double?) -> Bool in v != nil }
        let djup: [Double?] = vecka(.deepSleep, 1.0 / 60)
        let rem: [Double?] = vecka(.remSleep, 1.0 / 60)
        let delar: [[Double?]] = (0..<7).map { (i: Int) -> [Double?] in [djup[i], rem[i]] }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Kortrubrik(text: harBehov ? "Sömn mot behov" : "Sömn")
                if harBehov {
                    // BESLUT B79. Två linjer med talen utskrivna, så att gapet syns direkt.
                    SömnMotBehov(sömn: sömn, behov: behovet, etiketter: etiketter7)
                } else {
                    TidDiagram(värden: sömn, etiketter: etiketter7, ymin: 0, ymax: 10, rutor: 5,
                               format: { (v: Double) -> String in Fmt.hm(hours: v) })
                }
                HStack(spacing: 12) {
                    Tecken(färg: Tema.accent, text: "sömn", rund: harBehov)
                    if harBehov { Tecken(färg: Tema.awake, text: "behov", rund: true) }
                }
                .font(.system(size: 10))
                .foregroundStyle(Tema.dim)
                if harBehov {
                    // BESLUT B83 · METOD M58. Dagar per läge: sömnen i procent av nattens behov.
                    Lägesband(lägen: Self.lägen(
                        Lägesräkning.antal(Self.andelar(sömn, behovet)) { (p: Double) -> Behovsläge in Behovsläge(p) },
                        Behovsläge.allCases.map { (l: Behovsläge) -> (String, String, Color) in (l.namn, l.gräns, l.färg) }))
                        .padding(.top, 6)
                }
            }
            .kort()
            if harBrist {
                // BESLUT B65. Hela skulden efter varje natt; skalan växer med den.
                let tak: Double = max(1.5, (brist.compactMap { (v: Double?) -> Double? in v }.max() ?? 0).rounded(.up))
                VStack(alignment: .leading, spacing: 6) {
                    Kortrubrik(text: "Sömnbrist")
                    // BESLUT B83 · METOD M58. Stapeln i lägets färg: låg, måttlig eller hög.
                    TidDiagram(värden: brist, etiketter: etiketter7, färgFn: { (v: Double) -> Color in Tema.skuld(v) },
                               ymin: 0, ymax: tak, rutor: 3, format: { (v: Double) -> String in Fmt.hm(hours: v) })
                    Lägesband(lägen: Self.lägen(
                        Lägesräkning.antal(brist) { (v: Double) -> Skuldläge in Skuldläge(v) },
                        Skuldläge.allCases.map { (l: Skuldläge) -> (String, String, Color) in (l.namn, l.gräns, l.färg) }))
                        .padding(.top, 6)
                }
                .kort()
            }
            VStack(alignment: .leading, spacing: 6) {
                Kortrubrik(text: "Effektivitet")
                TidDiagram(värden: vecka(.efficiency), etiketter: etiketter7, typ: .linje, ymin: 70, ymax: 100, rutor: 3,
                           format: { (v: Double) -> String in "\(Int(v.rounded()))%" })
            }
            .kort()
            if harStressVecka {
                VStack(alignment: .leading, spacing: 6) {
                    Kortrubrik(text: "Sömnstress")
                    TidDiagram(värden: stressD, etiketter: etiketter7, färgFn: { (_: Double) -> Color in Tema.yellow },
                               ymin: 0, ymax: 3, rutor: 3, format: { (v: Double) -> String in Fmt.hm(hours: v) })
                    HStack(spacing: 12) {
                        Tecken(färg: Color(rgb: 0x4A6F8A), text: "låg")
                        Tecken(färg: Tema.yellow, text: "mellan")
                        Tecken(färg: Tema.red, text: "hög")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.dim)
                }
                .kort()
            }
            VStack(alignment: .leading, spacing: 6) {
                Kortrubrik(text: "Djup + REM")
                StapelDiagram(delar: delar, färger: [Tema.deep, Tema.rem], etiketter: etiketter7, ymax: 4.5,
                              siffra: { (d: [Double?]) -> String? in
                                  let summa: Double = d.reduce(0) { (a: Double, v: Double?) -> Double in a + (v ?? 0) }
                                  return summa > 0 ? Fmt.hm(hours: summa) : nil
                              })
                HStack(spacing: 12) {
                    Tecken(färg: Tema.deep, text: "djup")
                    Tecken(färg: Tema.rem, text: "REM")
                }
                .font(.system(size: 10))
                .foregroundStyle(Tema.dim)
            }
            .kort()
        }
    }
}

extension NightStack {
    /// BESLUT B83. Sömnen i procent av behovet per dag; en dag utan sömn eller behov är `nil`.
    static func andelar(_ sömn: [Double?], _ behov: [Double?]) -> [Double?] {
        (0..<min(sömn.count, behov.count)).map { (i: Int) -> Double? in
            guard let s = sömn[i], let b = behov[i], b > 0 else { return nil }
            return s / b * 100
        }
    }

    /// Lägesbandets rader: namn, gräns och färg per läge med antalet dagar.
    static func lägen(_ antal: [Int], _ lägen: [(String, String, Color)]) -> [Lägesband.Läge] {
        (0..<min(antal.count, lägen.count)).map { (i: Int) -> Lägesband.Läge in
            Lägesband.Läge(namn: lägen[i].0, gräns: lägen[i].1, färg: lägen[i].2, antal: antal[i])
        }
    }
}

/// Ett sömnbehov delat i sina delar, eller ett tomt spår (spåret H): remsor med luft emellan, bredd efter värde.
struct Fördelning: View {
    let delar: [(Double, Color)]?

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            if let d = delar, !d.isEmpty {
                let summa: Double = d.reduce(0) { (a: Double, x: (Double, Color)) -> Double in a + x.0 }
                let luft: CGFloat = 2
                let rum: CGFloat = max(0, g.size.width - luft * CGFloat(d.count - 1))
                HStack(spacing: luft) {
                    ForEach(0..<d.count, id: \.self) { (i: Int) in
                        Rectangle()
                            .fill(d[i].1)
                            .frame(width: summa > 0 ? rum * CGFloat(d[i].0 / summa) : 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Tema.track)
            }
        }
        .frame(height: 10)
    }
}

/// BESLUT B141. En tunn remsa för ett stadium: ditt normala område som ett ljusare fält och natten som ett streck i
/// stadiets färg. Skalan går från noll till det största av områdets övre kant gånger 1,5 och natten gånger 1,1, så att
/// området hamnar ungefär mitt i och natten alltid syns. Utan område ritas bara spåret och strecket.
struct Normalremsa: View {
    let värde: Double?
    let område: ClosedRange<Double>?
    let färg: Color

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let topp: Double = max((område?.upperBound ?? 0) * 1.5, (värde ?? 0) * 1.1, 1)
            let x: (Double) -> CGFloat = { (v: Double) -> CGFloat in g.size.width * CGFloat(min(max(v / topp, 0), 1)) }
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.track.opacity(0.6))
                if let o = område {
                    Capsule()
                        .fill(Tema.dim.opacity(0.45))
                        .frame(width: max(x(o.upperBound) - x(o.lowerBound), 3))
                        .offset(x: x(o.lowerBound))
                }
                if let v = värde {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(färg)
                        .frame(width: 3, height: g.size.height + 4)
                        .offset(x: min(max(x(v) - 1.5, 0), g.size.width - 3))
                }
            }
            .frame(height: g.size.height)
        }
        .accessibilityHidden(true)
    }
}
