import SwiftUI
import HeartRate
import Night

/// METOD M21 · BESLUT B24 · BESLUT B32
/// Poincarémolnet för en natt: varje rensat intervall mot nästa, som rutor med
/// antal par i Idunns blå ramp (ljusare = fler), identitetslinjen, och
/// ellipsen med SD1 tvärs och SD2 längs linjen. Axlarna står i puls och
/// växer åt höger och uppåt, och måtten heter "slag till slag" och "nattens
/// svängning", så att bilden läses utan förkunskap (B32). Ett reglage spelar
/// natten: paren de senaste 5 minuterna som prickar ovanpå, äldre svagare.
/// Räkningen ligger i IdunnKit (`Poincare`); vyn visar nattens värden (BESLUT B19).
struct PoincareView: View {
    let summary: NightSummary
    @State private var modell: PoincareModel?
    @State private var loaded = false
    @State private var läge: TimeInterval?

    var body: some View {
        Group {
            if let m = modell {
                ScrollView {
                    PoincareStack(model: m, läge: $läge)
                }
                .background(Color(.systemGroupedBackground))
            } else if loaded {
                ContentUnavailableView("För få slag", systemImage: "chart.dots.scatter")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Slag för slag")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let s = summary
            modell = await Task.detached(priority: .userInitiated) { NightLoader.poincare(for: s) }.value
            loaded = true
        }
    }
}

/// Allt molnet behöver, räknat en gång.
struct PoincareModel: Sendable {
    var pairs: [Poincare.Pair]
    var descriptors: Poincare.Descriptors
    var histogram: Poincare.Histogram
    var start: TimeInterval
    var end: TimeInterval

    static func make(stem: String) -> PoincareModel? {
        guard let data = try? Data(contentsOf: NightFiles.pulse(stem)) else { return nil }
        return make(RecordingLog.decode(data).recording)
    }

    /// METOD M3 · METOD M21. Samma rensning som rapporten och kurvan.
    static func make(_ night: NightRecording) -> PoincareModel? {
        make(pairs: Poincare.pairs(RRCleaning.clean(night)))
    }

    /// METOD M28 · METOD M21. En natt ur K18: paren ur samma rensade slag som
    /// kurvan och sammanfattningen (`NightResult.poincarePairs`).
    static func make(result: NightResult) -> PoincareModel? {
        make(pairs: result.poincarePairs)
    }

    static func make(pairs par: [Poincare.Pair]) -> PoincareModel? {
        guard let d = Poincare.descriptors(par), let axel = Poincare.axis(par),
              let först = par.first?.time, let sist = par.last?.time else { return nil }
        return PoincareModel(pairs: par, descriptors: d, histogram: Poincare.histogram(par, axis: axel),
                             start: först, end: sist)
    }
}

/// Avläsningen, molnet och reglaget utan rullning, så att `ImageRenderer` kan
/// rita dem (IdunnProv). Reglaget är UIKit och syns inte i en sådan bild.
struct PoincareStack: View {
    let model: PoincareModel
    @Binding var läge: TimeInterval?
    @State private var spelar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PoincareReading(d: model.descriptors)
            VStack(alignment: .leading, spacing: 10) {
                PoincareCanvas(model: model, läge: läge)
                    .aspectRatio(1, contentMode: .fit)
                DensityLegend(max: model.histogram.maxCount)
            }
            .padding(12)
            .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
            Scrubber(model: model, läge: $läge, spelar: $spelar)
                .padding(12)
                .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .task(id: spelar) {
            // Hela natten på ungefär 20 s, 30 steg i sekunden.
            let steg: TimeInterval = max(1, (model.end - model.start) / 600)
            while spelar && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                let nu: TimeInterval = (läge ?? model.start) + steg
                if nu >= model.end {
                    läge = model.end
                    spelar = false
                } else {
                    läge = nu
                }
            }
        }
    }
}

/// BESLUT B32. SD1 och SD2 i ms under vardagsnamnen; ett tryck visar
/// fackorden och antalet par.
private struct PoincareReading: View {
    let d: Poincare.Descriptors
    @State private var fackord = false

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            mått(fackord ? "SD1" : "Slag till slag", d.sd1)
            mått(fackord ? "SD2" : "Nattens svängning", d.sd2)
            Spacer(minLength: 4)
            if fackord {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Poincaré")
                    Text("\(d.count) par").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { fackord.toggle() }
        .accessibilityAddTraits(.isButton)
    }

    private func mått(_ namn: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(namn).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(v.rounded()))").font(.title3.weight(.semibold))
                Text("ms").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// METOD M21 · BESLUT B32. Molnet i en Canvas. Rutorna i fem klasser,
/// identitetslinjen och rutnätet hårfina, ellipsen och dess halvaxlar i textens
/// färg. Axlarna står i puls: intervallen ritas baklänges, så att kort
/// intervall (hög puls) hamnar till höger och uppe. Molnet vrids då ett halvt
/// varv och behåller sin form. Med ett läge i natten tonas rutorna ner och
/// fönstrets par ritas som prickar.
private struct PoincareCanvas: View {
    let model: PoincareModel
    let läge: TimeInterval?

    static let vänster: CGFloat = 44
    static let under: CGFloat = 34

    var body: some View {
        Canvas { ctx, size in
            rita(&ctx, size: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Två slag i rad, pulsen i det ena mot pulsen i nästa")
        .accessibilityValue("Slag till slag \(Int(model.descriptors.sd1.rounded())) ms, nattens svängning \(Int(model.descriptors.sd2.rounded())) ms")
    }

    private func rita(_ ctx: inout GraphicsContext, size: CGSize) {
        let h = model.histogram
        let sida: CGFloat = max(1, min(size.width - Self.vänster, size.height - Self.under))
        let x0: CGFloat = Self.vänster
        let spann: Double = h.upper - h.lower
        func px(_ ms: Double) -> CGFloat { x0 + CGFloat((h.upper - ms) / spann) * sida }
        func py(_ ms: Double) -> CGFloat { CGFloat((ms - h.lower) / spann) * sida }
        let ram = CGRect(x: x0, y: 0, width: sida, height: sida)
        let linje = Color.secondary.opacity(0.25)

        // Rutnätet vid hela pulstal, med talen.
        for slag in Poincare.pulseTicks(h.lower...h.upper) {
            let v: Double = Poincare.pulse(slag)
            var p = Path()
            p.move(to: CGPoint(x: px(v), y: 0))
            p.addLine(to: CGPoint(x: px(v), y: sida))
            p.move(to: CGPoint(x: x0, y: py(v)))
            p.addLine(to: CGPoint(x: x0 + sida, y: py(v)))
            ctx.stroke(p, with: .color(linje), lineWidth: 0.5)
            let t = Text("\(Int(slag))").font(.caption2).foregroundColor(.secondary)
            ctx.draw(t, at: CGPoint(x: px(v), y: sida + 9), anchor: .center)
            ctx.draw(t, at: CGPoint(x: x0 - 4, y: py(v)), anchor: .trailing)
        }

        // Axlarnas namn; pilen pekar mot högre puls.
        let namnX = Text("puls i ett slag →").font(.caption2).foregroundColor(.secondary)
        ctx.draw(namnX, at: CGPoint(x: x0 + sida / 2, y: sida + Self.under), anchor: .bottom)
        var stående = ctx
        stående.translateBy(x: 0, y: sida / 2)
        stående.rotate(by: .degrees(-90))
        let namnY = Text("puls i nästa slag →").font(.caption2).foregroundColor(.secondary)
        stående.draw(namnY, at: .zero, anchor: .top)

        // Rutorna. Ruta i har intervallen från lower + i·bredd, och ritas
        // baklänges i x.
        let ruta: CGFloat = sida / CGFloat(h.bins)
        let tonad = läge != nil
        for j in 0..<h.bins {
            for i in 0..<h.bins {
                let n = h.count(x: i, y: j)
                let klass = Poincare.densityClass(n, max: h.maxCount, classes: DensityColor.steps.count)
                guard klass > 0 else { continue }
                let r = CGRect(x: x0 + CGFloat(h.bins - 1 - i) * ruta, y: CGFloat(j) * ruta, width: ruta, height: ruta)
                ctx.fill(Path(r), with: .color(DensityColor.steps[klass - 1].opacity(tonad ? 0.35 : 1)))
            }
        }

        // Identitetslinjen, med vad den betyder nära änden med hög puls.
        var id = Path()
        id.move(to: CGPoint(x: px(h.lower), y: py(h.lower)))
        id.addLine(to: CGPoint(x: px(h.upper), y: py(h.upper)))
        ctx.stroke(id, with: .color(Color.secondary.opacity(0.6)), lineWidth: 1)
        let påLinjen: Double = h.upper - 0.85 * spann
        var längsLinjen = ctx
        längsLinjen.translateBy(x: px(påLinjen), y: py(påLinjen))
        längsLinjen.rotate(by: .degrees(-45))
        etikett(&längsLinjen, "lika snabba", at: CGPoint(x: 0, y: 6), anchor: .top)

        // Ellipsen och halvaxlarna, med sina namn utanför ändarna.
        let d = model.descriptors
        let e = Poincare.ellipse(d)
        var ellips = Path()
        ellips.addLines(e.map { (p: Poincare.Point) -> CGPoint in CGPoint(x: px(p.x), y: py(p.y)) })
        ctx.stroke(ellips, with: .color(.primary), lineWidth: 1.5)
        let a = Poincare.axes(d)
        var axlar = Path()
        let mitt = CGPoint(x: px(d.meanX), y: py(d.meanY))
        let ände1 = CGPoint(x: px(a.sd1.x), y: py(a.sd1.y))
        let ände2 = CGPoint(x: px(a.sd2.x), y: py(a.sd2.y))
        axlar.move(to: mitt)
        axlar.addLine(to: ände1)
        axlar.move(to: mitt)
        axlar.addLine(to: ände2)
        ctx.stroke(axlar, with: .color(.primary), lineWidth: 1)

        // Fönstrets par, äldre svagare, det senaste med en ring i ytans färg.
        if let t = läge {
            let fönster = Poincare.window(model.pairs, endingAt: t)
            for k in fönster {
                let p = model.pairs[k]
                let ålder: Double = (t - p.time) / Poincare.windowSeconds
                let c = CGPoint(x: px(p.x), y: py(p.y))
                let r: CGFloat = 2.5
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(DensityColor.point.opacity(max(0.15, 1 - ålder))))
            }
            if let sist = fönster.last {
                let p = model.pairs[sist]
                let c = CGPoint(x: px(p.x), y: py(p.y))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                         with: .color(TrendColor.surface))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                         with: .color(DensityColor.point))
            }
        }

        // Halvaxlarnas namn sist, så att fönstrets prickar inte ritas över dem.
        utanför(&ctx, "slag till slag", från: mitt, ände: ände1, ram: ram)
        utanför(&ctx, "nattens svängning", från: mitt, ände: ände2, ram: ram)
    }

    /// En halvaxels namn strax utanför dess ände, i axelns riktning från mitten.
    private func utanför(_ ctx: inout GraphicsContext, _ s: String, från mitt: CGPoint,
                         ände: CGPoint, ram: CGRect) {
        let dx: CGFloat = ände.x - mitt.x
        let dy: CGFloat = ände.y - mitt.y
        let l: CGFloat = (dx * dx + dy * dy).squareRoot()
        let ux: CGFloat = l > 0.5 ? dx / l : 0
        let uy: CGFloat = l > 0.5 ? dy / l : -1
        let punkt = CGPoint(x: ände.x + 4 * ux, y: ände.y + 4 * uy)
        etikett(&ctx, s, at: punkt, anchor: UnitPoint(x: 0.5 - 0.5 * ux, y: 0.5 - 0.5 * uy), inom: ram)
    }

    /// En etikett med ytan bakom, så att den syns mot molnet. `anchor` är den
    /// punkt på etiketten som läggs på `punkt`; med `ram` hålls den inom den.
    private func etikett(_ ctx: inout GraphicsContext, _ s: String, at punkt: CGPoint,
                         anchor: UnitPoint, inom ram: CGRect? = nil) {
        let text = ctx.resolve(Text(s).font(.caption2).foregroundColor(.primary))
        let storlek: CGSize = text.measure(in: CGSize(width: 400, height: 100))
        let pad: CGFloat = 3
        let b: CGFloat = storlek.width + 2 * pad
        let h: CGFloat = storlek.height + 2 * pad
        var r = CGRect(x: punkt.x - anchor.x * b, y: punkt.y - anchor.y * h, width: b, height: h)
        if let ram {
            r.origin.x = min(max(r.minX, ram.minX), ram.maxX - b)
            r.origin.y = min(max(r.minY, ram.minY), ram.maxY - h)
        }
        ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(TrendColor.surface.opacity(0.85)))
        ctx.draw(text, in: r.insetBy(dx: pad, dy: pad))
    }
}

/// BESLUT B32. Vad en ruta är, och klassernas färger från sällan till ofta.
private struct DensityLegend: View {
    let max: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("ruta = två slag i rad")
            Spacer(minLength: 8)
            Text("sällan")
            HStack(spacing: 2) {
                ForEach(DensityColor.steps.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(DensityColor.steps[i]).frame(width: 14, height: 8)
                }
            }
            Text("ofta")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("En ruta är två slag i rad. Färgen visar hur ofta, från 1 till \(max) gånger")
    }
}

/// Spela, reglaget genom natten och klockslaget. Krysset visar hela natten igen.
private struct Scrubber: View {
    let model: PoincareModel
    @Binding var läge: TimeInterval?
    @Binding var spelar: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if !spelar, let l = läge, l >= model.end { läge = model.start }
                spelar.toggle()
            } label: {
                Image(systemName: spelar ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(spelar ? "Pausa" : "Spela natten")
            Slider(value: Binding(get: { läge ?? model.end }, set: { läge = $0 }),
                   in: model.start...max(model.end, model.start + 1))
            Text(läge.map { Date(timeIntervalSince1970: $0).formatted(.dateTime.hour().minute()) } ?? "natten")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            if läge != nil {
                Button {
                    spelar = false
                    läge = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Hela natten")
            }
        }
        .buttonStyle(.plain)
        .tint(TrendColor.idun)
    }
}

/// Dataviz-skillens blå ramp, prövad med `validate_palette.js --ordinal` mot
/// ytan (mörk #1c1c1e: steg 600, 450, 350, 250, 100; ljus #ffffff: steg 250,
/// 350, 450, 550, 650). Fem klasser, för att stegen ska skiljas åt (ΔL ≥ 0,06)
/// och den svagaste klara 2:1 mot ytan.
enum DensityColor {
    static let steps: [Color] = [
        Color.adaptive(light: 0x86B6EF, dark: 0x184F95),
        Color.adaptive(light: 0x5598E7, dark: 0x2A78D6),
        Color.adaptive(light: 0x2A78D6, dark: 0x5598E7),
        Color.adaptive(light: 0x1C5CAB, dark: 0x86B6EF),
        Color.adaptive(light: 0x104281, dark: 0xCDE2FB),
    ]
    /// Uppspelningens prickar i textens färg, så att de syns mot de nertonade rutorna.
    static let point = Color.primary
}
