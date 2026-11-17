import SwiftUI
import Charts
import Fitness
import Night
import Pass

/// BESLUT B110 · METOD M62
/// Pulsen på en nivå (1–3) i ett steptest: samma belastning i varje test, så att pulsen kan jämföras över tid.
struct KonditionNivåpuls: Equatable {
    let test: UUID
    /// Dagar sedan 1970-01-01 i telefonens zon.
    let dag: Int
    let nivå: Int
    let puls: Double
}

/// BESLUT B110 · METOD M64
/// Referensen för profilens kön: åldersgruppens medel och spridning.
struct KonditionReferens: Equatable {
    let band: FitnessReference.Band
    let kön: FitnessProfile.Sex
}

/// BESLUT B110
/// Allt som passfliken behöver veta om konditionen och steptestet, som värden (`PassScreen` tar sin data så, för
/// provets skull). `PassView` fyller det ur `KonditionModell` och `PassController`.
struct PassKondition {
    var visat: FitnessSummary.Shown? = nil
    var mätningar: [FitnessMeasurement] = []
    var nivåpuls: [KonditionNivåpuls] = []
    var referens: KonditionReferens? = nil
    /// Maxpulsen testet räknas mot, med var den kommer ifrån; `nil` utan egen maxpuls och födelseår.
    var maxpuls: MaxPulse? = nil
    /// Stegets höjd i cm som skrevs in senast.
    var steghöjd: Double? = nil
    var profil: FitnessProfile = FitnessProfile()
    /// Varför det senaste steptestet tog slut; `nil` när det stoppades för hand.
    var slut: StepTest.Reason? = nil
    /// BESLUT B111. Metronomens senaste slag i steptestet (ord nummer `slag % 4` i takten markeras).
    var slag: Int = 0
    /// BESLUT B114 · METOD M66. Pulsen vid samma tempo över passen ute.
    var tempopuls: SteadyPulse.Series? = nil
}

extension PassKondition {
    /// Värdena ur modellen. `slut` kommer ur `PassController`.
    init(modell: KonditionModell, slut: StepTest.Reason? = nil, slag: Int = 0) {
        self.init(visat: modell.visat, mätningar: modell.mätningar, nivåpuls: modell.nivåpuls,
                  referens: modell.referens, maxpuls: modell.maxpulsUnderlag, steghöjd: modell.lager.stepHeightCm,
                  profil: modell.lager.profile, slut: slut, slag: slag, tempopuls: modell.tempopuls)
    }
}

/// Texterna om talet, så att kortet och skärmen säger samma sak.
enum KonditionText {
    static func tal(_ v: Double) -> String { String(Int(v.rounded())) }

    /// "1 steptest och 2 pass · senast 3 nov" eller "Vila och profil · 12 nätter".
    static func underlag(_ b: FitnessSummary.Shown.Basis) -> String {
        switch b {
        case .measurements(let steg, let pass, let senast):
            var delar: [String] = []
            if steg > 0 { delar.append("\(steg) steptest") }
            if pass > 0 { delar.append("\(pass) pass") }
            return delar.joined(separator: " och ") + " · senast " + Fmt.dayMonth(WakeDay(daysSince1970: senast))
        case .passive(let nätter):
            return "Vila och profil · \(nätter) nätter"
        }
    }

    /// BESLUT B111. Talet med osäkerheten som ett spann: "troligen 41–49" (talet minus och plus osäkerheten, avrundat).
    static func spann(_ värde: Double, _ osäkerhet: Double) -> String {
        let nedre: Int = Int((värde - osäkerhet).rounded())
        let övre: Int = Int((värde + osäkerhet).rounded())
        return "troligen \(nedre)–\(övre)"
    }

    /// BESLUT B111 · METOD M64. Var talet ligger mot medel för kön och ålder: "2 under medel för män 40–49 år",
    /// "3 över medel för kvinnor 30–39 år" eller "På medel för män 40–49 år". Skillnaden är talet avrundat minus
    /// medlet avrundat.
    static func motMedel(_ värde: Double, _ r: KonditionReferens) -> String {
        let grupp: String = r.kön == .man ? "män" : "kvinnor"
        let vilka: String = "\(grupp) \(r.band.fromAge)–\(r.band.toAge) år"
        let skillnad: Int = Int(värde.rounded()) - Int(r.band.mean.rounded())
        if skillnad == 0 { return "På medel för \(vilka)" }
        let håll: String = skillnad < 0 ? "under" : "över"
        return "\(abs(skillnad)) \(håll) medel för \(vilka)"
    }

    /// BESLUT B114. Tempot som minuter och sekunder per km: "5:30" (hela sekunder, sekunderna alltid två siffror).
    static func tempo(_ sekunder: Double) -> String {
        let hela: Int = Int(sekunder.rounded())
        let sek: Int = hela % 60
        return "\(hela / 60):" + (sek < 10 ? "0" : "") + String(sek)
    }

    /// BESLUT B114. Det senaste passets puls mot passen före: "3 slag lägre än passen före".
    static func tempoÄndring(_ ändring: Double) -> String {
        let n: Int = Int(ändring.rounded())
        if n < 0 { return "\(-n) slag lägre än passen före" }
        if n > 0 { return "\(n) slag högre än passen före" }
        return "Samma som passen före"
    }

    /// BESLUT B138 · METOD M80. Ändringen över perioden: "↑ 2 sedan 12 jun", "↓ 3 sedan 4 nov" eller "Oförändrat sedan
    /// 12 jun". Talet är ändringen avrundad till hela tal.
    static func ändring(_ delta: Double, frånDag: Int) -> String {
        let n: Int = Int(delta.rounded())
        let datum: String = Fmt.dayMonth(WakeDay(daysSince1970: frånDag))
        if n > 0 { return "↑ \(n) sedan \(datum)" }
        if n < 0 { return "↓ \(-n) sedan \(datum)" }
        return "Oförändrat sedan \(datum)"
    }

    /// Dagnumret som ett klockslag mitt på dagen, för diagrammens x-axel.
    static func datum(_ dag: Int) -> Date { Date(timeIntervalSince1970: Double(dag) * 86_400 + 43_200) }
}

/// BESLUT B110 · BESLUT B138
/// Kortet överst på Pass i vila, i skissens form: talet stort med spannet, och vad det bygger på. Ett tryck öppnar
/// `KonditionSkärm`.
struct KonditionKort: View {
    let visat: FitnessSummary.Shown
    var öppna: () -> Void = {}

    var body: some View {
        Button(action: öppna) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kondition").font(.system(size: 13)).foregroundStyle(Tema.dim)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(KonditionText.tal(visat.value))
                            .font(.system(size: 52, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(Tema.text)
                        Text("ml/kg/min").font(.system(size: 13)).foregroundStyle(Tema.dim)
                    }
                    Text(KonditionText.spann(visat.value, visat.uncertainty))
                        .font(.system(size: 14))
                        .foregroundStyle(Tema.text)
                    Text(KonditionText.underlag(visat.basis)).font(.system(size: 12)).foregroundStyle(Tema.dim)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Tema.dim)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kondition")
    }
}

/// BESLUT B138 · METOD M80
/// Mätningarna över en period som en kurva i ren SwiftUI: tre rutnätslinjer med värden, en linje mellan mätningarna i
/// dagordning, en ring vid varje mätning och den sista fylld, och första och sista datumet under. `mätningar` är i dagordning
/// (som ur `FitnessTrend.within`). Färre än två mätningar ritas inte.
struct KonditionKurva: View {
    let mätningar: [FitnessMeasurement]

    private static let marginal: CGFloat = 34
    private static let ytaHöjd: CGFloat = 180

    var body: some View {
        if mätningar.count >= 2 {
            VStack(spacing: 6) {
                GeometryReader { (g: GeometryProxy) in
                    ritning(g.size)
                }
                .frame(height: Self.ytaHöjd)
                HStack {
                    Text(Fmt.dayMonth(WakeDay(daysSince1970: mätningar[0].day)))
                    Spacer(minLength: 8)
                    Text(Fmt.dayMonth(WakeDay(daysSince1970: mätningar[mätningar.count - 1].day)))
                }
                .font(.system(size: 11))
                .foregroundStyle(Tema.dim)
                .padding(.trailing, Self.marginal)
            }
        }
    }

    private func ritning(_ yta: CGSize) -> some View {
        let värden: [Double] = mätningar.map { (m: FitnessMeasurement) -> Double in m.value }
        let låg: Double = värden.min() ?? 0
        let hög: Double = värden.max() ?? 0
        let bredd: CGFloat = max(1, yta.width - Self.marginal)
        let höjd: CGFloat = yta.height
        let första: Int = mätningar[0].day
        let spann: Double = Double(max(1, mätningar[mätningar.count - 1].day - första))
        let xAv: (Int) -> CGFloat = { (dag: Int) -> CGFloat in
            CGFloat(min(1, max(0, Double(dag - första) / spann))) * bredd
        }
        let yAv: (Double) -> CGFloat = { (v: Double) -> CGFloat in
            let f: Double = hög > låg ? (v - låg) / (hög - låg) : 0.5
            return höjd * CGFloat(0.1 + 0.8 * (1 - f))
        }
        var linje: Path = Path()
        for (i, m) in mätningar.enumerated() {
            let p: CGPoint = CGPoint(x: xAv(m.day), y: yAv(m.value))
            if i == 0 { linje.move(to: p) } else { linje.addLine(to: p) }
        }
        let nivåer: [Double] = hög > låg ? [hög, (hög + låg) / 2, låg] : [hög]
        let marginal: CGFloat = Self.marginal
        let sista: Int = mätningar.count - 1

        return ZStack(alignment: .topLeading) {
            ForEach(Array(nivåer.enumerated()), id: \.offset) { (e: (offset: Int, element: Double)) in
                let y: CGFloat = yAv(e.element)
                Path { (v: inout Path) -> Void in
                    v.move(to: CGPoint(x: 0, y: y))
                    v.addLine(to: CGPoint(x: bredd, y: y))
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                Text(KonditionText.tal(e.element))
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.dim)
                    .frame(width: marginal, alignment: .trailing)
                    .position(x: bredd + marginal / 2, y: y - 8)
            }
            linje.stroke(Tema.text, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ForEach(Array(mätningar.enumerated()), id: \.offset) { (e: (offset: Int, element: FitnessMeasurement)) in
                let p: CGPoint = CGPoint(x: xAv(e.element.day), y: yAv(e.element.value))
                if e.offset == sista {
                    Circle().fill(Tema.text).frame(width: 10, height: 10).position(x: p.x, y: p.y)
                } else {
                    Circle()
                        .fill(Tema.card)
                        .overlay(Circle().stroke(Tema.text, lineWidth: 2))
                        .frame(width: 8, height: 8)
                        .position(x: p.x, y: p.y)
                }
            }
        }
        .frame(width: yta.width, height: yta.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kondition över tid")
    }
}

/// BESLUT B110 · METOD M64 · BESLUT B138 · METOD M80
/// Konditionen i sin helhet, i skissens form: perioden M, 6M, Å eller Allt, talet och ändringen över perioden, kurvan,
/// mätningarna, referensen för kön och ålder och pulsen på samma nivå i steptesten. Allt som värden.
struct KonditionSkärm: View {
    let visat: FitnessSummary.Shown
    var mätningar: [FitnessMeasurement] = []
    var nivåpuls: [KonditionNivåpuls] = []
    var referens: KonditionReferens? = nil
    /// BESLUT B114 · METOD M66. Pulsen vid samma tempo över passen ute.
    var tempopuls: SteadyPulse.Series? = nil
    /// BESLUT B138. Dagen i dag (dagar sedan 1970-01-01); `nil` räknar telefonens.
    var idag: Int? = nil

    /// BESLUT B138. Perioden som visas.
    @State private var period: FitnessTrend.Span

    init(visat: FitnessSummary.Shown, mätningar: [FitnessMeasurement] = [], nivåpuls: [KonditionNivåpuls] = [],
         referens: KonditionReferens? = nil, tempopuls: SteadyPulse.Series? = nil,
         period: FitnessTrend.Span = .halfYear, idag: Int? = nil) {
        self.visat = visat
        self.mätningar = mätningar
        self.nivåpuls = nivåpuls
        self.referens = referens
        self.tempopuls = tempopuls
        self.idag = idag
        _period = State(initialValue: period)
    }

    private var dagNu: Int { idag ?? KonditionModell.idag() }

    var body: some View {
        let inom: [FitnessMeasurement] = FitnessTrend.within(mätningar, span: period, today: dagNu)
        let ändring: FitnessTrend.Change? = FitnessTrend.change(inom)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer(minLength: 0)
                    PassPiller(val: [(FitnessTrend.Span.month, "M"), (FitnessTrend.Span.halfYear, "6M"),
                                     (FitnessTrend.Span.year, "Å"), (FitnessTrend.Span.all, "Allt")],
                               valt: period, välj: { (s: FitnessTrend.Span) -> Void in period = s })
                    Spacer(minLength: 0)
                }
                talrad
                ändringsrad(ändring)
                Text(KonditionText.underlag(visat.basis)).font(.system(size: 12)).foregroundStyle(Tema.dim)
                kurvdel(inom)
                if !inom.isEmpty { mätlista(inom) }
                if let r = referens { referensDel(r) }
                if antalSteptest >= 2 { pulsDel }
                if let t = tempopuls { tempoDel(t) }
                Text("Talet är en skattning. Utan labbtest är det osäkert med några enheter, men förändringen över tid går att lita på.")
                    .font(.footnote)
                    .foregroundStyle(Tema.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Tema.bg)
        .navigationTitle("Kondition")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var antalSteptest: Int {
        Set(nivåpuls.map { (n: KonditionNivåpuls) -> UUID in n.test }).count
    }

    // MARK: Talet

    private var talrad: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(KonditionText.tal(visat.value))
                .font(.system(size: 72, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
            Text("ml/kg/min").font(.system(size: 15)).foregroundStyle(Tema.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// BESLUT B138. Ändringen över perioden och spannet: ändringen grön eller röd när den är större än testets spridning.
    private func ändringsrad(_ ändring: FitnessTrend.Change?) -> some View {
        let spann: String = KonditionText.spann(visat.value, visat.uncertainty)
        return HStack(spacing: 0) {
            if let ä = ändring {
                let färg: Color = ä.isNoticeable ? (ä.delta > 0 ? Tema.green : Tema.red) : Tema.text
                Text(KonditionText.ändring(ä.delta, frånDag: ä.fromDay)).foregroundStyle(färg)
                Text(" · " + spann).foregroundStyle(Tema.dim)
            } else {
                Text(spann).foregroundStyle(Tema.dim)
            }
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Kurvan och mätningarna

    @ViewBuilder
    private func kurvdel(_ inom: [FitnessMeasurement]) -> some View {
        if inom.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                KonditionKurva(mätningar: inom)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        } else if inom.isEmpty {
            Text("Inga mätningar i perioden.").font(.system(size: 13)).foregroundStyle(Tema.dim)
        }
    }

    private func mätlista(_ inom: [FitnessMeasurement]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PassKortRubrik(text: "Mätningarna").padding(.bottom, 6)
            ForEach(Array(inom.reversed().enumerated()), id: \.offset) { (e: (offset: Int, element: FitnessMeasurement)) in
                let m: FitnessMeasurement = e.element
                VStack(spacing: 0) {
                    if e.offset > 0 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
                    HStack(spacing: 12) {
                        PassIkonruta(symbol: m.kind == .stepTest ? "figure.stairs" : "figure.run", ljus: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.kind == .stepTest ? "Steptest" : "Pass ute")
                                .font(.system(size: 16))
                                .foregroundStyle(Tema.text)
                            Text(Fmt.dayMonth(WakeDay(daysSince1970: m.day)))
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.dim)
                        }
                        Spacer(minLength: 8)
                        Text(KonditionText.tal(m.value))
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Tema.text)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 12)
                            .background(Capsule().fill(Tema.card2))
                    }
                    .padding(.vertical, 10)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Referensen

    private func referensDel(_ r: KonditionReferens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(KonditionText.motMedel(visat.value, r)).font(.headline).foregroundStyle(Tema.text)
            ReferensStapel(band: r.band, värde: visat.value, osäkerhet: visat.uncertainty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Pulsen på samma nivå

    private var pulsDomän: ClosedRange<Double> {
        let v: [Double] = nivåpuls.map { (n: KonditionNivåpuls) -> Double in n.puls }
        guard let lo = v.min(), let hi = v.max() else { return 60...160 }
        return (lo - 5).rounded(.down)...(hi + 5).rounded(.up)
    }

    /// Nivå 1 starkast, sedan svagare.
    private static func nivåopacitet(_ nivå: Int) -> Double {
        nivå <= 1 ? 1.0 : (nivå == 2 ? 0.65 : 0.35)
    }

    private var pulsDel: some View {
        VStack(alignment: .leading, spacing: 10) {
            PassKortRubrik(text: "Pulsen på samma nivå")
            Chart {
                ForEach(nivåpuls.indices, id: \.self) { (i: Int) in
                    // BESLUT B111 · BESLUT B138. Alla linjer i `Tema.text`, nivå 1 starkast.
                    LineMark(x: .value("Dag", KonditionText.datum(nivåpuls[i].dag), unit: .day),
                             y: .value("Puls", nivåpuls[i].puls),
                             series: .value("Serie", "Nivå \(nivåpuls[i].nivå)"))
                        .foregroundStyle(Tema.text.opacity(Self.nivåopacitet(nivåpuls[i].nivå)))
                        .symbol(by: .value("Nivå", "Nivå \(nivåpuls[i].nivå)"))
                }
            }
            .chartYScale(domain: pulsDomän)
            .frame(height: 200)
            .accessibilityLabel("Puls på samma nivå över tid")
            Text("Lägre puls på samma nivå betyder bättre kondition.")
                .font(.footnote)
                .foregroundStyle(Tema.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Pulsen vid samma tempo (BESLUT B114 · METOD M66)

    private struct Tempopunkt: Identifiable {
        let id: Int
        let datum: Date
        let puls: Double
    }

    private func tempopunkter(_ s: SteadyPulse.Series) -> [Tempopunkt] {
        s.points.indices.map { (i: Int) -> Tempopunkt in
            Tempopunkt(id: i, datum: KonditionText.datum(s.points[i].day), puls: s.points[i].pulse)
        }
    }

    private func tempoDomän(_ s: SteadyPulse.Series) -> ClosedRange<Double> {
        let v: [Double] = s.points.map { (p: SteadyPulse.Point) -> Double in p.pulse }
        guard let lo = v.min(), let hi = v.max() else { return 60...160 }
        return (lo - 5)...(hi + 5)
    }

    private func tempoDel(_ s: SteadyPulse.Series) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PassKortRubrik(text: "Puls vid samma tempo")
            HStack(alignment: .firstTextBaseline) {
                Text("Vid \(KonditionText.tempo(s.paceSeconds))/km" + (s.running ? "" : " gång"))
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.dim)
                Spacer(minLength: 8)
                if let sist = s.latest {
                    Text(KonditionText.tal(sist.pulse) + " slag/min")
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .foregroundStyle(Tema.text)
                }
            }
            if let ändring = s.change {
                Text(KonditionText.tempoÄndring(ändring))
                    .font(.footnote)
                    .foregroundStyle(Tema.dim)
            }
            if s.points.count >= 2 {
                Chart {
                    ForEach(tempopunkter(s)) { (p: Tempopunkt) in
                        LineMark(x: .value("Dag", p.datum, unit: .day), y: .value("Puls", p.puls))
                            .foregroundStyle(Tema.text.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Dag", p.datum, unit: .day), y: .value("Puls", p.puls))
                            .symbolSize(90)
                            .foregroundStyle(Tema.text)
                    }
                }
                .chartYScale(domain: tempoDomän(s))
                .frame(height: 200)
                .accessibilityLabel("Puls vid samma tempo över tid")
            }
            Text("Lägre puls vid samma tempo betyder bättre kondition.")
                .font(.footnote)
                .foregroundStyle(Tema.dim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

/// BESLUT B110 · METOD M64
/// En liggande stapel från medel − 2 SD till medel + 2 SD med medlet markerat och talet som en prick. Ett tal utanför
/// stapeln ritas vid den närmaste änden.
struct ReferensStapel: View {
    let band: FitnessReference.Band
    let värde: Double
    /// BESLUT B111. Osäkerheten på talet: spannet ritas som ett ljust fält bakom pricken. 0 ritar inget fält.
    var osäkerhet: Double = 0

    private var från: Double { band.mean - 2 * band.sd }
    private var till: Double { band.mean + 2 * band.sd }

    private func läge(_ v: Double) -> CGFloat {
        CGFloat(max(0, min(1, (v - från) / (till - från))))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { (geo: GeometryProxy) in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.track).frame(height: 10)
                    if osäkerhet > 0 {
                        let a: CGFloat = läge(värde - osäkerhet)
                        let b: CGFloat = läge(värde + osäkerhet)
                        Rectangle().fill(Tema.text.opacity(0.35))
                            .frame(width: geo.size.width * (b - a), height: 10)
                            .offset(x: geo.size.width * a)
                    }
                    Rectangle().fill(Tema.dim)
                        .frame(width: 2, height: 22)
                        .offset(x: geo.size.width * läge(band.mean) - 1)
                    Circle().fill(Tema.text)
                        .frame(width: 22, height: 22)
                        .offset(x: geo.size.width * läge(värde) - 11)
                }
                .frame(height: 24)
            }
            .frame(height: 24)
            HStack {
                Text(String(Int(från.rounded())))
                Spacer()
                Text("medel \(Int(band.mean.rounded()))")
                Spacer()
                Text(String(Int(till.rounded())))
            }
            .font(.caption2)
            .foregroundStyle(Tema.dim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jämfört med andra i samma ålder")
    }
}
