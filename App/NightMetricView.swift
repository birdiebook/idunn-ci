import SwiftUI
import Night
import Sound

/// BESLUT B63 · METOD M18 · METOD M25 · METOD M32 · METOD M44
/// Måttet över natten, en vy för HRV, hudtemperatur, andning, rörelse och ljud (Slag för slag öppnar `PoincareView`):
/// värdet mot ditt normala, natten på samma tidsaxel som stadierna med din vanliga natt som band där den finns och
/// glappen tomma, hudtemperaturen som avvikelse (METOD M49) med rörelsen skuggad, ljudet med det som väckte dig och
/// raden till klippet, och veckan.
enum NightMetric: String, CaseIterable, Identifiable {
    case hrv
    case temp
    case resp
    case move
    case ljud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: return "HRV"
        case .temp: return "Hudtemp"
        case .resp: return "Andning"
        case .move: return "Rörelse"
        case .ljud: return "Ljud"
        }
    }

    var symbol: String {
        switch self {
        case .hrv: return "waveform.path.ecg"
        case .temp: return "thermometer.medium"
        case .resp: return "lungs"
        case .move: return "figure.walk"
        case .ljud: return "waveform"
        }
    }

    /// Måttet i IdunnKit som raden och veckan räknas på.
    var measure: Trends.Measure {
        switch self {
        case .hrv: return .hrv
        case .temp: return .skinTemperature
        case .resp: return .breathing
        case .move: return .movement
        case .ljud: return .snoring
        }
    }
}

/// Laddar nattens kurva och de tidigare nätterna och ritar måttet.
struct NightMetricScreen: View {
    let metric: NightMetric
    let summary: NightSummary
    @EnvironmentObject private var recorder: Recorder
    @State private var bundle: NightLoader.CurveBundle?
    @State private var klar = false

    var body: some View {
        ScrollView {
            NightMetricStack(metric: metric, summary: summary, bundle: bundle,
                             typical: bundle.flatMap { (b: NightLoader.CurveBundle) -> NightCurve.Typical? in
                                 NightCurveView.typical(b.curve, stem: summary.stem, summaries: recorder.summaries)
                             },
                             values: Trends.idunValues(recorder.summaries.compactMap(\.idunNight)), laddad: klar,
                             halvor: metric == .hrv ? Natthalvor(recorder.summaries) : Natthalvor(),
                             taggar: metric == .hrv ? DagbokModell.shared.taggar(dag: summary.wakeDay?.daysSince1970) : [])
        }
        .background(Tema.bg)
        .navigationTitle(metric.title + " i natt")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: summary) {
            bundle = await NightLoader.sharedBundle(for: summary, priority: .userInitiated)
            klar = true
        }
    }
}

/// Måttet utan rullning, så att `ImageRenderer` kan rita det (IdunnProv).
struct NightMetricStack: View {
    let metric: NightMetric
    let summary: NightSummary
    var bundle: NightLoader.CurveBundle? = nil
    var typical: NightCurve.Typical? = nil
    var values: Trends.Values = [:]
    /// Falskt medan kurvan räknas: då står ingen "saknas"-text.
    var laddad = true
    /// BESLUT B129 · METOD M75. Nattens två halvor per uppvakningsdag (bara HRV), och kvällens taggar för natten.
    var halvor: Natthalvor = Natthalvor()
    var taggar: [String] = []

    private var day: WakeDay { summary.wakeDay ?? WakeDay(daysSince1970: 0) }
    private var curve: NightCurve.Curve? { bundle?.curve }
    private var layers: NightLayers.Layers? { bundle?.layers }
    private var stages: [NightLayers.StageSpan] { layers?.stages ?? [] }
    private var t0: TimeInterval { layers?.start ?? curve?.start ?? 0 }
    private var t1: TimeInterval { max(layers?.end ?? curve?.end ?? 0, t0 + 60) }

    private func nr(_ m: Trends.Measure, _ d: WakeDay? = nil) -> MorningCard.Row? {
        MorningCard.nightRow(m, day: d ?? day, idun: values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rad
            diagram
            extra
            Sektion(text: "Veckan")
            vecka
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    // MARK: Värdet mot ditt normala

    @ViewBuilder private var rad: some View {
        let r: MorningCard.Row? = nr(metric.measure)
        VStack(spacing: 0) {
            switch metric {
            case .hrv:
                hrvRader(r)
            case .temp:
                hudrad(r)
            case .resp:
                BandRad(namn: "Nattens andning", text: r.map { (x: MorningCard.Row) -> String in Fmt.num(x.value, 1) },
                        värde: r?.value, område: r?.range, axel: r?.track, sista: true)
            case .move:
                BandRad(namn: "Minuter i rörelse", text: r.map { (x: MorningCard.Row) -> String in Fmt.num(x.value) + " min" },
                        värde: r?.value, område: r?.range, axel: r?.track, bra: -1, sista: true)
            case .ljud:
                BandRad(namn: "Snarkning", text: r.map { (x: MorningCard.Row) -> String in Fmt.num(x.value, 1) + " min/h" },
                        värde: r?.value, område: r?.range, axel: r?.track, bra: -1, sista: true)
            }
        }
        .radkort()
    }

    /// BESLUT B129 · METOD M75. Nattens HRV, och under den nattens två halvor mot sina egna normalområden när natten
    /// har dem. Raden under säger när någon halva ligger under sitt normala.
    @ViewBuilder private func hrvRader(_ r: MorningCard.Row?) -> some View {
        let a: MorningCard.Row? = halvor.rad(halvor.första, dag: day)
        let b: MorningCard.Row? = halvor.rad(halvor.andra, dag: day)
        let not: String? = halvor.text(dag: day, taggar: taggar)
        if let a, let b {
            BandRad(namn: "Nattens HRV", text: r.map { (x: MorningCard.Row) -> String in Fmt.num(x.value) + " ms" },
                    värde: r?.value, område: r?.range, axel: r?.track, bra: 1)
            BandRad(namn: "Första halvan", text: Fmt.num(a.value) + " ms",
                    värde: a.value, område: a.range, axel: a.track, bra: 1)
            BandRad(namn: "Andra halvan", text: Fmt.num(b.value) + " ms",
                    värde: b.value, område: b.range, axel: b.track, bra: 1, sista: not == nil)
            if let not {
                Text(not)
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
        } else {
            BandRad(namn: "Nattens HRV", text: r.map { (x: MorningCard.Row) -> String in Fmt.num(x.value) + " ms" },
                    värde: r?.value, område: r?.range, axel: r?.track, bra: 1, sista: true)
        }
    }

    @ViewBuilder private func hudrad(_ r: MorningCard.Row?) -> some View {
        if let r = r, let a = r.deviation, let ref = r.reference {
            let o: ClosedRange<Double>? = r.range.map { (x: ClosedRange<Double>) -> ClosedRange<Double> in
                (x.lowerBound - ref)...(x.upperBound - ref)
            }
            BandRad(namn: "Nattens hudtemp", text: Fmt.signedDegrees(a), värde: a, område: o, sista: true)
        } else if let r = r {
            BandRad(namn: "Nattens hudtemp", text: Fmt.num(r.value, 1) + "°", värde: r.value, område: r.range,
                    axel: r.track, sista: true)
        } else {
            BandRad(namn: "Nattens hudtemp", sista: true)
        }
    }

    // MARK: Natten

    @ViewBuilder private var diagram: some View {
        if curve == nil && layers == nil {
            Text(laddad ? "Natten gick inte att läsa." : " ")
                .font(.system(size: 13))
                .foregroundStyle(Tema.dim)
                .kort()
        } else {
            switch metric {
            case .hrv: hrvDiagram
            case .temp: hudDiagram
            case .resp: andningsDiagram
            case .move: rörelseDiagram
            case .ljud: ljudDiagram
            }
        }
    }

    private func rutor(_ lo: Double, _ hi: Double, _ steg: Double) -> [Double] {
        var ut: [Double] = []
        var v: Double = (lo / steg).rounded(.up) * steg
        while v < hi && ut.count < 12 {
            ut.append(v)
            v += steg
        }
        return ut
    }

    private func bandpunkter(_ band: [NightCurve.Band], minus: Double = 0) -> [NattMatt.Bandpunkt] {
        guard let c = curve else { return [] }
        return band.map { (b: NightCurve.Band) -> NattMatt.Bandpunkt in
            NattMatt.Bandpunkt(tid: c.time(atFraction: b.fraction), lägre: b.lower - minus, övre: b.upper - minus)
        }
    }

    private func diagramkort<Inre: View>(@ViewBuilder _ inre: () -> Inre) -> some View {
        VStack(alignment: .leading, spacing: 8) { inre() }
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.horizontal, 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tecken(_ delar: [(Color, String)]) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<delar.count, id: \.self) { (i: Int) in
                Tecken(färg: delar[i].0, text: delar[i].1)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Tema.dim)
        .padding(.horizontal, 14)
    }

    private var hrvDiagram: some View {
        let punkter: [NattMatt.Punkt] = (curve?.windows ?? []).map { (w: NightCurve.WindowPoint) -> NattMatt.Punkt in
            NattMatt.Punkt(tid: w.mid, värde: w.rmssd)
        }
        let band: [NattMatt.Bandpunkt] = bandpunkter(typical?.rmssd ?? [])
        var alla: [Double] = punkter.compactMap { (p: NattMatt.Punkt) -> Double? in p.värde }
        for b in band {
            alla.append(b.lägre)
            alla.append(b.övre)
        }
        let lo: Double = max(0, ((alla.min() ?? 20) - 5).rounded(.down))
        let hi: Double = max(lo + 10, ((alla.max() ?? 80) + 5).rounded(.up))
        return diagramkort {
            NattMatt(t0: t0, t1: t1, lo: lo, hi: hi, tal: rutor(lo, hi, 20), format: { (v: Double) -> String in Fmt.num(v) },
                     linje: punkter, band: band, stadier: stages, bredd: NightAnalysis.windowSeconds,
                     mitt: halvor.första[day] != nil ? curve.map { (c: NightCurve.Curve) -> TimeInterval in (c.start + c.end) / 2 } : nil)
                .padding(.horizontal, 14)
            tecken(band.isEmpty ? [(Tema.accent, "i natt")] : [(Tema.accent, "i natt"), (Tema.band, "din vanliga natt")])
            if !stages.isEmpty { StadieTecken().padding(.horizontal, 14).font(.system(size: 10)) }
            Text("Högre i djupsömn, lägre i REM och vid uppvak.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.dim)
                .padding(.horizontal, 14)
        }
    }

    /// Nattens medel av hudtemperaturen: referensen när normalområdet saknas (METOD M49).
    private var hudMedel: Double? {
        let v: [Double] = (layers?.minutes ?? []).compactMap { (m: NightLayers.Minute) -> Double? in m.skinTemperature }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private var hudDiagram: some View {
        let områdesmedel: Double? = nr(.skinTemperature)?.reference
        let ref: Double = områdesmedel ?? hudMedel ?? 0
        let min_: [NightLayers.Minute] = layers?.minutes ?? []
        let punkter: [NattMatt.Punkt] = min_.map { (m: NightLayers.Minute) -> NattMatt.Punkt in
            NattMatt.Punkt(tid: m.mid, värde: m.skinTemperature.map { (t: Double) -> Double in t - ref })
        }
        let band: [NattMatt.Bandpunkt] = områdesmedel == nil ? [] : bandpunkter(typical?.skin ?? [], minus: ref)
        // Rörelsen skuggad: följder av minuter över gränsen för rörelse (METOD M32).
        var skuggor: [ClosedRange<TimeInterval>] = []
        for m in min_ {
            guard let r = m.movement, r >= NightLayers.movementThreshold else { continue }
            if let sist = skuggor.last, sist.upperBound >= m.start {
                skuggor[skuggor.count - 1] = sist.lowerBound...(m.start + NightCurve.minuteSeconds)
            } else {
                skuggor.append(m.start...(m.start + NightCurve.minuteSeconds))
            }
        }
        var alla: [Double] = punkter.compactMap { (p: NattMatt.Punkt) -> Double? in p.värde }
        for b in band {
            alla.append(b.lägre)
            alla.append(b.övre)
        }
        let lo: Double = (min(-0.6, (alla.min() ?? -0.6) - 0.2) * 2).rounded(.down) / 2
        let hi: Double = (max(0.6, (alla.max() ?? 0.6) + 0.2) * 2).rounded(.up) / 2
        var förklaring: [(Color, String)] = [(Tema.accent, "i natt")]
        if !band.isEmpty { förklaring.append((Tema.band, "din vanliga natt")) }
        if !skuggor.isEmpty { förklaring.append((Color.white.opacity(0.2), "rörelse")) }
        let fk: [(Color, String)] = förklaring
        return diagramkort {
            NattMatt(t0: t0, t1: t1, lo: lo, hi: hi, tal: rutor(lo, hi, 0.5), format: { (v: Double) -> String in
                Fmt.signedDegrees(v)
            }, linje: punkter, band: band, skuggor: skuggor, stadier: stages, bredd: 60)
                .padding(.horizontal, 14)
            tecken(fk)
            if !stages.isEmpty { StadieTecken().padding(.horizontal, 14).font(.system(size: 10)) }
            Text("Mot din vanliga natt, inte grader. Stiger vid insomning.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.dim)
                .padding(.horizontal, 14)
        }
    }

    private var andningsDiagram: some View {
        let punkter: [NattMatt.Punkt] = (curve?.windows ?? []).map { (w: NightCurve.WindowPoint) -> NattMatt.Punkt in
            NattMatt.Punkt(tid: w.mid, värde: w.breathsPerMinute)
        }
        let alla: [Double] = punkter.compactMap { (p: NattMatt.Punkt) -> Double? in p.värde }
        let lo: Double = ((alla.min() ?? 12) - 0.5).rounded(.down)
        let hi: Double = max(lo + 3, ((alla.max() ?? 15) + 0.5).rounded(.up))
        // Andningen räknas inte mot någon vanlig natt, så här är det bara linjen (METOD M10).
        return diagramkort {
            NattMatt(t0: t0, t1: t1, lo: lo, hi: hi, tal: rutor(lo, hi, 1), format: { (v: Double) -> String in Fmt.num(v) },
                     linje: punkter, stadier: stages, bredd: NightAnalysis.windowSeconds)
                .padding(.horizontal, 14)
            tecken([(Tema.accent, "andetag per minut")])
            if !stages.isEmpty { StadieTecken().padding(.horizontal, 14).font(.system(size: 10)) }
        }
    }

    private var rörelseDiagram: some View {
        let staplar: [NattMatt.Punkt] = (layers?.minutes ?? []).compactMap { (m: NightLayers.Minute) -> NattMatt.Punkt? in
            m.movement.map { (v: Double) -> NattMatt.Punkt in NattMatt.Punkt(tid: m.start, värde: v) }
        }
        let störst: Double = staplar.compactMap { (p: NattMatt.Punkt) -> Double? in p.värde }.max() ?? 0
        let hi: Double = max(störst, NightLayers.movementThreshold * 2)
        return diagramkort {
            NattMatt(t0: t0, t1: t1, lo: 0, hi: hi, tal: [], format: { (v: Double) -> String in Fmt.num(v, 2) },
                     staplar: staplar, gräns: NightLayers.movementThreshold, stadier: stages, bredd: 60)
                .padding(.horizontal, 14)
            tecken([(Tema.accent, "rörelse"), (Tema.still, "still")])
            if !stages.isEmpty { StadieTecken().padding(.horizontal, 14).font(.system(size: 10)) }
        }
    }

    @ViewBuilder private var ljudDiagram: some View {
        if let s = bundle?.sound, let c = curve {
            SoundLayerView(sound: s, curve: c, layers: layers)
            Stadiebana(t0: t0, t1: t1, stadier: stages)
        } else {
            Text(laddad ? "Inget ljud i natt." : " ")
                .font(.system(size: 13))
                .foregroundStyle(Tema.dim)
                .kort()
        }
    }

    /// Ljudet: det som väckte dig, med raden till klippet, och länken till alla klipp.
    @ViewBuilder private var extra: some View {
        if metric == .ljud, let s = bundle?.sound {
            VäckteKort(sound: s)
        }
    }

    // MARK: Veckan

    private var vecka: some View {
        let dagar: [WakeDay] = (0..<7).map { (k: Int) -> WakeDay in day - (6 - k) }
        let rader: [MorningCard.Row?] = dagar.map { (d: WakeDay) -> MorningCard.Row? in nr(metric.measure, d) }
        let temp: Bool = metric == .temp
        let tal: [Double?] = rader.map { (r: MorningCard.Row?) -> Double? in temp ? r?.deviation : r?.value }
        let band: [ClosedRange<Double>?] = rader.map { (r: MorningCard.Row?) -> ClosedRange<Double>? in
            guard let r = r, let o = r.range else { return nil }
            if temp, let ref = r.reference { return (o.lowerBound - ref)...(o.upperBound - ref) }
            return temp ? nil : o
        }
        let bra: Int = metric == .hrv ? 1 : (metric == .move || metric == .ljud ? -1 : 0)
        let format: (Double) -> String = { (v: Double) -> String in
            switch metric {
            case .hrv: return Fmt.num(v)
            case .temp: return Fmt.signedDegrees(v)
            case .resp: return Fmt.num(v, 1)
            case .move: return Fmt.num(v)
            case .ljud: return Fmt.num(v, 1)
            }
        }
        return TidDiagram(värden: tal, etiketter: dagar.map { (d: WakeDay) -> String in Fmt.weekday(d) }, typ: .linje,
                          band: band, format: format, bra: bra)
            .kort()
    }
}

/// Stadierna och klockslagen utan något diagram över dem (ljudet har sitt eget diagram).
struct Stadiebana: View {
    let t0: TimeInterval
    let t1: TimeInterval
    let stadier: [NightLayers.StageSpan]

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            NattRitning.stadier(ctx, spans: stadier, t0: t0, t1: t1, bredd: size.width, y: 2, höjd: 12)
            NattRitning.klockor(ctx, t0: t0, t1: t1, bredd: size.width, y: 28, fem: false)
        }
        .frame(height: 36)
        .accessibilityHidden(true)
    }
}

/// METOD M44 · BESLUT B54 · BESLUT B63. Det som väckte dig: ett ljud per rad med klockslaget och en knapp till klippet
/// (om det finns kvar, 14 dagar), och länken till alla klipp med facit.
struct VäckteKort: View {
    let sound: NightSound
    @Environment(\.clipExists) private var clipExists
    @ObservedObject private var spelare = ClipPlayer.shared

    private var väckare: [NightSound.Event] {
        sound.events.filter { (e: NightSound.Event) -> Bool in e.woke }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kortrubrik(text: "Det som väckte dig")
            if väckare.isEmpty {
                Text("Inget väckte dig.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
            }
            ForEach(väckare) { (e: NightSound.Event) in
                HStack(spacing: 8) {
                    SoundGlyph(soundClass: e.soundClass, owner: e.owner, woke: true, size: 10)
                    Text(SoundLook.word(e.soundClass))
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.text)
                    Spacer(minLength: 4)
                    Text(SoundLook.clock(e.time)).font(Tema.mono(12)).foregroundStyle(Tema.text)
                    if clipExists(e.clip) {
                        Button {
                            spelare.toggle(e.clip)
                        } label: {
                            Image(systemName: spelare.playing == e.clip.key ? "stop.fill" : "play.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.accent)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Spela \(SoundLook.word(e.soundClass)) \(SoundLook.clock(e.time))")
                    }
                }
            }
            NavigationLink {
                ScrollView {
                    SoundReport(sound: sound).padding()
                }
                .background(Tema.bg)
                .navigationTitle("Klipp")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text("Alla klipp, rätt eller fel")
                    Spacer(minLength: 4)
                    Text("\(sound.events.count) ›").font(Tema.mono(12)).foregroundStyle(Tema.text)
                }
                .font(.system(size: 12))
                .foregroundStyle(Tema.dim)
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Tema.line).frame(height: 1) }
            }
            .buttonStyle(.plain)
        }
        .kort()
    }
}
