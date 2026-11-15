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

    /// Dagnumret som ett klockslag mitt på dagen, för diagrammens x-axel.
    static func datum(_ dag: Int) -> Date { Date(timeIntervalSince1970: Double(dag) * 86_400 + 43_200) }
}

/// BESLUT B110
/// Kortet överst på Pass i vila: talet stort med spannet, och vad det bygger på. Ett tryck öppnar `KonditionSkärm`.
struct KonditionKort: View {
    let visat: FitnessSummary.Shown
    var öppna: () -> Void = {}

    var body: some View {
        Button(action: öppna) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kondition").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(KonditionText.tal(visat.value))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(KonditionText.spann(visat.value, visat.uncertainty))
                            .font(.callout)
                            .foregroundStyle(Tema.dim)
                    }
                    Text(KonditionText.underlag(visat.basis)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kondition")
    }
}

/// BESLUT B110 · METOD M64
/// Konditionen i sin helhet: talet, referensen för kön och ålder, mätningarna över tid och pulsen på samma nivå i
/// steptesten. Allt som värden.
struct KonditionSkärm: View {
    let visat: FitnessSummary.Shown
    var mätningar: [FitnessMeasurement] = []
    var nivåpuls: [KonditionNivåpuls] = []
    var referens: KonditionReferens? = nil
    /// BESLUT B114 · METOD M66. Pulsen vid samma tempo över passen ute.
    var tempopuls: SteadyPulse.Series? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                huvud
                if let r = referens { referensDel(r) }
                if !mätningar.isEmpty { mätDel }
                if antalSteptest >= 2 { pulsDel }
                if let t = tempopuls { tempoDel(t) }
                Text("Talet är en skattning. Utan labbtest är det osäkert med några enheter, men förändringen över tid går att lita på.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Kondition")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var antalSteptest: Int {
        Set(nivåpuls.map { (n: KonditionNivåpuls) -> UUID in n.test }).count
    }

    // MARK: Talet

    private var huvud: some View {
        VStack(spacing: 4) {
            Text(KonditionText.tal(visat.value))
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(KonditionText.spann(visat.value, visat.uncertainty) + " · ml/kg/min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(KonditionText.underlag(visat.basis)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Referensen

    private func referensDel(_ r: KonditionReferens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(KonditionText.motMedel(visat.value, r)).font(.headline)
            ReferensStapel(band: r.band, värde: visat.value, osäkerhet: visat.uncertainty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Mätningarna

    private struct Mätpunkt: Identifiable {
        let id: Int
        let datum: Date
        let värde: Double
        let slag: String
    }

    private var mätpunkter: [Mätpunkt] {
        mätningar.indices.map { (i: Int) -> Mätpunkt in
            let m: FitnessMeasurement = mätningar[i]
            return Mätpunkt(id: i, datum: KonditionText.datum(m.day), värde: m.value,
                            slag: m.kind == .stepTest ? "Steptest" : "Pass ute")
        }
    }

    private var mätDomän: ClosedRange<Double> {
        let v: [Double] = mätningar.map { (m: FitnessMeasurement) -> Double in m.value }
        guard let lo = v.min(), let hi = v.max() else { return 20...60 }
        return (lo - 6).rounded(.down)...(hi + 6).rounded(.up)
    }

    private var mätDel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dina mätningar").font(.headline)
            Chart {
                // BESLUT B111. En tunn linje mellan punkterna i dagordning, bakom dem.
                ForEach(mätpunkter.sorted { (a: Mätpunkt, b: Mätpunkt) -> Bool in a.datum < b.datum }) { (p: Mätpunkt) in
                    LineMark(x: .value("Dag", p.datum, unit: .day), y: .value("Kondition", p.värde))
                        .foregroundStyle(Tema.accent.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                ForEach(mätpunkter) { (p: Mätpunkt) in
                    PointMark(x: .value("Dag", p.datum, unit: .day), y: .value("Kondition", p.värde))
                        .symbol(by: .value("Typ", p.slag))
                        .symbolSize(90)
                        .foregroundStyle(Tema.accent)
                }
            }
            .chartYScale(domain: mätDomän)
            .frame(height: 200)
            .accessibilityLabel("Mätningar över tid")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
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
            Text("Pulsen på samma nivå").font(.headline)
            Chart {
                ForEach(nivåpuls.indices, id: \.self) { (i: Int) in
                    // BESLUT B111. Alla linjer i accentfärgen, nivå 1 starkast.
                    LineMark(x: .value("Dag", KonditionText.datum(nivåpuls[i].dag), unit: .day),
                             y: .value("Puls", nivåpuls[i].puls),
                             series: .value("Serie", "Nivå \(nivåpuls[i].nivå)"))
                        .foregroundStyle(Tema.accent.opacity(Self.nivåopacitet(nivåpuls[i].nivå)))
                        .symbol(by: .value("Nivå", "Nivå \(nivåpuls[i].nivå)"))
                }
            }
            .chartYScale(domain: pulsDomän)
            .frame(height: 200)
            .accessibilityLabel("Puls på samma nivå över tid")
            Text("Lägre puls på samma nivå betyder bättre kondition.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
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
            Text("Puls vid samma tempo").font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text("Vid \(KonditionText.tempo(s.paceSeconds))/km" + (s.running ? "" : " gång"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let sist = s.latest {
                    Text(KonditionText.tal(sist.pulse) + " slag/min")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
            if let ändring = s.change {
                Text(KonditionText.tempoÄndring(ändring))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if s.points.count >= 2 {
                Chart {
                    ForEach(tempopunkter(s)) { (p: Tempopunkt) in
                        LineMark(x: .value("Dag", p.datum, unit: .day), y: .value("Puls", p.puls))
                            .foregroundStyle(Tema.accent.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Dag", p.datum, unit: .day), y: .value("Puls", p.puls))
                            .symbolSize(90)
                            .foregroundStyle(Tema.accent)
                    }
                }
                .chartYScale(domain: tempoDomän(s))
                .frame(height: 200)
                .accessibilityLabel("Puls vid samma tempo över tid")
            }
            Text("Lägre puls vid samma tempo betyder bättre kondition.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
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
                        Rectangle().fill(Tema.accent.opacity(0.35))
                            .frame(width: geo.size.width * (b - a), height: 10)
                            .offset(x: geo.size.width * a)
                    }
                    Rectangle().fill(Tema.dim)
                        .frame(width: 2, height: 22)
                        .offset(x: geo.size.width * läge(band.mean) - 1)
                    Circle().fill(Tema.accent)
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
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jämfört med andra i samma ålder")
    }
}
