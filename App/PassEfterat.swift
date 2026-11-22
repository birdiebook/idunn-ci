import SwiftUI
import Pass

/// BESLUT B138 · BESLUT B144
/// Det sparade passet i skissens form (mörkt, grått): vilken kurva som visas, kurvan själv och delkorten under den.
/// Vyerna tar sin data som värden, så att provet ritar dem. Färg bara ur `Tema`, och zonernas färg bara för zoner.

/// BESLUT B138. Vilken kurva det sparade passet visar: puls, tempo, höjd eller kartan.
enum PassKurvVal: Hashable {
    case puls, tempo, höjd, karta
}

/// BESLUT B138. Rubriken i ett kort: liten och grå.
struct PassKortRubrik: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Tema.dim)
    }
}

// MARK: - Kurvan

/// BESLUT B144 · BESLUT B138 · METOD M79 · METOD M83
/// En kurva över passets tid i Nattens form (B95–B99): en blågrå linje med en yta under som tonar ut, skalan på jämna
/// tal med linjer ända ut och talen till höger, tiden före stopp i full ton och efter stopp uttonad, en streckad linje
/// vid Start och vid Stopp med klockslaget under i textens färg. Pulslinjen före stopp kan färgas efter zonen den går i.
/// Ett håll på kurvan sätter en punkt som följer fingret, med värdet och tiden i hörnet och ett knäpp när punkten kommer;
/// den försvinner när fingret släpps. Färre än två punkter ger en text.
struct PassKurva: View {
    /// En zon: dess undre gräns i kurvans enhet och dess färg.
    struct Band: Equatable {
        var från: Double
        var färg: Color
    }

    let punkter: [PassSeries.Point]
    /// Passets längd i sekunder (x-axelns högra kant är max av den och sista punkten).
    let längd: TimeInterval
    /// Passets start: klockslagen under kurvan. nil = minuter sedan Start.
    var start: Date? = nil
    /// Sekunder från Start till Stopp; delen efter ritas uttonad. nil = inget stopp på kurvan.
    var stopp: TimeInterval? = nil
    /// Större lucka än så här (sekunder) mellan två punkter bryter linjen; nil = bryts aldrig.
    var lucka: TimeInterval? = nil
    /// true = lägre värde ritas högre upp (tempo).
    var omvänd: Bool = false
    /// Zonerna som färgar linjen, i stigande ordning; tomt = blågrå linje.
    var band: [Band] = []
    /// Skalans tillåtna steg; nil = 1, 2 eller 5 gånger en tiopotens.
    var stegval: [Double]? = nil
    /// Texten för ett värde på skalan.
    var text: (Double) -> String
    /// Talet och enheten i hörnet när en punkt är vald, t.ex. ("124", "bpm").
    var vald: (Double) -> (tal: String, enhet: String) = { (v: Double) in (String(Int(v.rounded())), "") }
    /// Vad skärmläsaren säger om kurvan.
    var etikett: String = "Kurva"
    /// BESLUT B153 · METOD M86. Punkter före Start och efter slutet (sekunder från Start), ritade uttonade.
    var utanför: [PassSeries.Point] = []
    /// BESLUT B153. Sekunder som visas på var sida om passet; med en marginal går kurvan ända ut till kanterna.
    var marginal: TimeInterval = 0

    @State private var markerad: Date? = nil

    /// Uttrycklig, för `@State private var markerad` gör den automatiska initieraren privat (se `Pekyta`).
    init(punkter: [PassSeries.Point], längd: TimeInterval, start: Date? = nil, stopp: TimeInterval? = nil,
         lucka: TimeInterval? = nil, omvänd: Bool = false, band: [Band] = [],
         stegval: [Double]? = nil, text: @escaping (Double) -> String,
         vald: @escaping (Double) -> (tal: String, enhet: String) = { (v: Double) in (String(Int(v.rounded())), "") },
         etikett: String = "Kurva", utanför: [PassSeries.Point] = [], marginal: TimeInterval = 0) {
        self.punkter = punkter
        self.längd = längd
        self.start = start
        self.stopp = stopp
        self.lucka = lucka
        self.omvänd = omvänd
        self.band = band
        self.stegval = stegval
        self.text = text
        self.vald = vald
        self.etikett = etikett
        self.utanför = utanför
        self.marginal = max(0, marginal)
    }

    /// Kurvans kanter i ytan, som Nattens (B99): början och slutet syns, och skalans tal står utanför till höger.
    /// BESLUT B153. Kurvan ligger kant till kant på skärmen: till vänster plats för halva klockslaget under Start, till höger för skalans tal.
    static let kant: (vänster: CGFloat, höger: CGFloat) = (26, 34)
    private static let ytaHöjd: CGFloat = 300
    /// Ritytan ovanför klockslagen.
    private static let topp: CGFloat = 12
    private static let botten: CGFloat = 34
    private static let linje: CGFloat = 1.6

    /// Tidsaxelns nollpunkt i sekunder sedan 1970 (passets start, eller 0 utan start).
    private var t0: TimeInterval { start?.timeIntervalSince1970 ?? 0 }
    private var xMax: TimeInterval { max(1, längd, punkter.last?.seconds ?? 0) }
    /// Kanterna i ytan: med en marginal går kurvan ända ut, och skalans tal står ovanpå den uttonade delen.
    private var kanter: (vänster: CGFloat, höger: CGFloat) { marginal > 0 ? (0, 0) : Self.kant }
    /// Alla punkter i tidsordning, de utanför passet med.
    private var alla: [PassSeries.Point] {
        utanför.isEmpty ? punkter : (utanför + punkter).sorted { (a: PassSeries.Point, b: PassSeries.Point) -> Bool in
            a.seconds < b.seconds
        }
    }

    /// Skalan: jämna steg (1, 2 eller 5 gånger en tiopotens) så att det blir fyra till sju linjer.
    /// Med `stegval` (t.ex. tempots 15, 30, 60 s) väljs det minsta av dem som räcker.
    static func skala(_ låg: Double, _ hög: Double, stegval: [Double]? = nil) -> (lo: Double, hi: Double, steg: Double) {
        let spann: Double = max(hög - låg, 1)
        let rå: Double = spann / 5
        let tio: Double = pow(10, (log10(rå)).rounded(.down))
        let kandidater: [Double] = stegval ?? [1, 2, 5, 10].map { (f: Double) -> Double in f * tio }
        let steg: Double = kandidater.first { (s: Double) -> Bool in s >= rå } ?? (kandidater.last ?? 10 * tio)
        var lo: Double = (låg / steg).rounded(.down) * steg
        var hi: Double = (hög / steg).rounded(.up) * steg
        if hi - lo < steg {
            lo -= steg / 2
            hi += steg / 2
        }
        return (lo, hi, steg)
    }

    /// Den valda punkten: närmast fingret, inom en lucka.
    private var valdPunkt: PassSeries.Point? {
        guard let m = markerad else { return nil }
        let s: TimeInterval = m.timeIntervalSince1970 - t0
        guard let n = PassSeries.nearest(alla, to: s) else { return nil }
        return abs(n.seconds - s) <= (lucka ?? .infinity) ? n : nil
    }

    var body: some View {
        if punkter.count < 2 {
            Text("Ingen kurva för det här passet.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.dim)
                .frame(maxWidth: .infinity, minHeight: Self.ytaHöjd, alignment: .center)
        } else {
            let v: PassSeries.Point? = valdPunkt
            Canvas { (ctx: inout GraphicsContext, size: CGSize) in
                teckna(ctx, size, vald: v)
            }
            .frame(height: Self.ytaHöjd)
            .overlay(alignment: hörn(v)) {
                if let v = v { hörnetikett(v) }
            }
            .pekMarkering($markerad, från: t0 - marginal, till: t0 + xMax + marginal,
                          vänster: kanter.vänster, höger: kanter.höger)
            // BESLUT B99. Ett knäpp när punkten kommer, inget medan fingret drar.
            .sensoryFeedback(.impact(weight: .light), trigger: markerad != nil) { (före: Bool, nu: Bool) -> Bool in
                nu && !före
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(etikett)
        }
    }

    /// BESLUT B98. Talet uppe till vänster, och till höger när punkten ligger i kurvans vänstra del.
    private func hörn(_ v: PassSeries.Point?) -> Alignment {
        guard let v = v else { return .topLeading }
        return (v.seconds + marginal) / (xMax + 2 * marginal) < 0.4 ? .topTrailing : .topLeading
    }

    private func tidstext(_ sekunder: TimeInterval) -> String {
        if start != nil { return Fmt.clock(time: t0 + sekunder) }
        return PassFormat.short(sekunder)
    }

    private func hörnetikett(_ v: PassSeries.Point) -> some View {
        let t: (tal: String, enhet: String) = vald(v.value)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(t.tal)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                if !t.enhet.isEmpty {
                    Text(t.enhet).font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(Tema.pulsLjus)
            Text(tidstext(v.seconds))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tema.dim)
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize, vald: PassSeries.Point?) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let top: CGFloat = Self.topp
        let ch: CGFloat = H - Self.topp - Self.botten
        let bas: CGFloat = top + ch
        let vä: CGFloat = kanter.vänster
        let bredd: CGFloat = max(1, W - vä - kanter.höger)
        let xMax: TimeInterval = self.xMax
        let m: TimeInterval = marginal
        let x = { (s: TimeInterval) -> CGFloat in vä + CGFloat(min(1, max(0, (s + m) / (xMax + 2 * m)))) * bredd }
        let alla: [PassSeries.Point] = self.alla
        // Före Start, efter Stopp och efter slutet ritas uttonat.
        let inneTill: TimeInterval = stopp ?? xMax

        let värden: [Double] = alla.map { (q: PassSeries.Point) -> Double in q.value }
        let sk: (lo: Double, hi: Double, steg: Double) = Self.skala(värden.min() ?? 0, värden.max() ?? 0, stegval: stegval)
        let vänd: Bool = omvänd
        let y = { (v: Double) -> CGFloat in
            let f: Double = (min(max(v, sk.lo), sk.hi) - sk.lo) / (sk.hi - sk.lo)
            return top + CGFloat(vänd ? f : 1 - f) * ch
        }

        // BESLUT B95 · BESLUT B97. Skalan på jämna steg, linjerna ända ut och talen till höger ovanför linjen.
        var v: Double = sk.lo
        while v <= sk.hi + sk.steg / 1000 {
            let yy: CGFloat = y(v)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: yy))
            p.addLine(to: CGPoint(x: W, y: yy))
            ctx.stroke(p, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
            if yy - 7 > top - 8 {
                ctx.etikett(text(v), CGPoint(x: W - 4, y: yy - 7), storlek: 10, färg: Tema.dim, ankare: .trailing)
            }
            v += sk.steg
        }

        // BESLUT B99. Start och Stopp: en streckad linje från överkanten ner till en prick strax över klockslaget.
        let prick: CGFloat = H - 20
        var ändar: [TimeInterval] = [0]
        if let s = stopp, s > 0, s < xMax { ändar.append(s) }
        for t in ändar {
            let px: CGFloat = x(t)
            var p = Path()
            p.move(to: CGPoint(x: px, y: 2))
            p.addLine(to: CGPoint(x: px, y: prick))
            ctx.stroke(p, with: .color(Color.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 2.5, y: prick - 2.5, width: 5, height: 5)), with: .color(Tema.text))
            ctx.etikett(tidstext(t), CGPoint(x: px, y: H - 8), storlek: 12, färg: Tema.text, vikt: .semibold)
        }
        // Slutet av kurvan, dämpat, när det inte krockar med Stopp.
        let slutX: CGFloat = x(xMax)
        if ändar.allSatisfy({ (t: TimeInterval) -> Bool in abs(x(t) - slutX) >= 48 }) {
            ctx.etikett(tidstext(xMax), CGPoint(x: slutX, y: H - 8), storlek: 10, färg: Tema.dim)
        }

        // Linjen i stycken: en lucka bryter den, och stopp delar den i före och efter.
        var före: [[CGPoint]] = []
        var efter: [[CGPoint]] = []
        var nu: [CGPoint] = []
        var nuEfter: Bool = false
        var förra: PassSeries.Point? = nil
        for q in alla where q.seconds >= -m && q.seconds <= xMax + m {
            let ärEfter: Bool = q.seconds < 0 || q.seconds > inneTill
            let pt: CGPoint = CGPoint(x: x(q.seconds), y: y(q.value))
            let bryt: Bool = förra.map { (f: PassSeries.Point) -> Bool in
                lucka.map { (l: TimeInterval) -> Bool in q.seconds - f.seconds > l } ?? false
            } ?? true
            if bryt || ärEfter != nuEfter {
                if nu.count > 0 { if nuEfter { efter.append(nu) } else { före.append(nu) } }
                // Före och efter stopp hänger ihop i en punkt, utan lucka.
                nu = (!bryt && ärEfter != nuEfter) ? [nu.last ?? pt, pt] : [pt]
                nuEfter = ärEfter
            } else {
                nu.append(pt)
            }
            förra = q
        }
        if nu.count > 0 { if nuEfter { efter.append(nu) } else { före.append(nu) } }

        // BESLUT B144. Linjen före stopp i zonens färg där den går: en lodrät toning med skarpa skiften vid zonernas
        // gränser, så att varje bit av linjen får färgen för sin höjd. Under zon 1 är den blågrå som utan zoner (B154:
        // vyn skickar bara den valda zonens färg, de andra som blågrå).
        let zonfärg: GraphicsContext.Shading? = {
            guard !band.isEmpty else { return nil }
            let span: CGFloat = max(1, bas - top)
            func andel(_ v: Double) -> CGFloat { min(1, max(0, (y(v) - top) / span)) }
            // Varje nivå har sin färg mellan sin undre gräns och nästa nivås.
            var stopp: [Gradient.Stop] = []
            var nivåer: [(från: Double, färg: Color)] = [(-Double.infinity, Tema.pulse)]
            nivåer += band.map { (b: Band) -> (från: Double, färg: Color) in (b.från, b.färg) }
            // Uppifrån och ner, så att platserna stiger och varje skifte blir skarpt.
            for i in nivåer.indices.reversed() {
                let n: (från: Double, färg: Color) = nivåer[i]
                let övre: CGFloat = i + 1 < nivåer.count ? andel(nivåer[i + 1].från) : 0
                let undre: CGFloat = n.från.isFinite ? andel(n.från) : 1
                stopp.append(Gradient.Stop(color: n.färg, location: övre))
                stopp.append(Gradient.Stop(color: n.färg, location: undre))
            }
            return .linearGradient(Gradient(stops: stopp), startPoint: CGPoint(x: 0, y: top),
                                   endPoint: CGPoint(x: 0, y: bas))
        }()

        func rita(_ stycken: [[CGPoint]], yta ytans: Double, linje linjens: Double, färg: GraphicsContext.Shading? = nil) {
            let ton = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Tema.pulse.opacity(ytans), Tema.pulse.opacity(0)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bas))
            for s in stycken where s.count > 1 {
                var yta = Path()
                yta.move(to: CGPoint(x: s[0].x, y: bas))
                for p in s { yta.addLine(to: p) }
                yta.addLine(to: CGPoint(x: s[s.count - 1].x, y: bas))
                yta.closeSubpath()
                ctx.fill(yta, with: ton)
                var l = Path()
                l.move(to: s[0])
                for p in s.dropFirst() { l.addLine(to: p) }
                ctx.stroke(l, with: färg ?? .color(Tema.pulse.opacity(linjens)),
                           style: StrokeStyle(lineWidth: Self.linje, lineCap: .round, lineJoin: .round))
            }
        }
        rita(efter, yta: 0.10, linje: 0.4)
        rita(före, yta: 0.30, linje: 1, färg: zonfärg)

        // BESLUT B98. Den valda punkten: ett streckat lodstreck och en punkt på kurvan.
        if let v = vald {
            let px: CGFloat = x(v.seconds)
            let py: CGFloat = y(v.value)
            var p = Path()
            p.move(to: CGPoint(x: px, y: top))
            p.addLine(to: CGPoint(x: px, y: bas))
            ctx.stroke(p, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 5, y: py - 5, width: 10, height: 10)), with: .color(Tema.bg))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 3.5, y: py - 3.5, width: 7, height: 7)), with: .color(Tema.pulsLjus))
        }
    }
}

// MARK: - Delkorten

/// BESLUT B138. Raden med tre tal överst i det sparade passet: tid, snittpuls och högsta puls.
struct PassTreTal: View {
    let pass: Pass

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            tal(PassFormat.short(pass.duration), "tid")
            tal(PassFormat.bpm(pass.averageBpm), "snittpuls")
            tal(PassFormat.bpm(pass.maxBpm), "högst")
        }
    }

    private func tal(_ värde: String, _ etikett: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(värde)
                .font(.system(size: 32, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(etikett)
                .font(.system(size: 12))
                .foregroundStyle(Tema.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// BESLUT B138. Sträckan och tempot för ett pass ute i två rutor. Tempot är det i rörelse (som kartdelen visar).
struct PassUteRutor: View {
    let pass: Pass

    var body: some View {
        let spår: [TrackPoint] = pass.track ?? []
        let tempo: Double? = PassTerrain.movement(spår).pace
        HStack(spacing: 8) {
            ruta("sträcka", PassRuttFormat.km(PassRoute.distance(spår)))
            ruta("tempo per km", PassRuttFormat.pace(tempo))
        }
    }

    private func ruta(_ etikett: String, _ värde: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(värde)
                .font(.system(size: 22, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(etikett).font(.system(size: 11)).foregroundStyle(Tema.dim)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(Tema.card2, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// BESLUT B138 · BESLUT B156. Tid per pulszon: en rad per zon, Zon 5 överst som i kurvan (hög puls högt upp), med en
/// stapel i zonens färg vars längd är tiden i zonen mot den största zonen, och tiden och andelen av passet till höger.
/// Alla fem zoner står alltid på sin plats, också utan tid. Utan tid i någon zon ritas inget. En rad trycks för att
/// färga zonen i kurvan, en gång till för att släppa (B154).
struct PassZonKort: View {
    let zoner: [PassZones.Share]
    /// BESLUT B154. Den valda zonen, som kurvan färgar; nil = ingen.
    var vald: Int? = nil
    /// BESLUT B154. En rad trycktes: zonens nummer.
    var välj: (Int) -> Void = { (_: Int) in }

    private func sekunder(_ zon: Int) -> TimeInterval {
        zoner.first { (z: PassZones.Share) -> Bool in z.zone == zon }?.seconds ?? 0
    }

    /// BESLUT B156. Andelen av passet: tiden i zonen mot all uppmätt tid, också den under zon 1.
    private var summa: TimeInterval {
        zoner.reduce(0) { (s: TimeInterval, z: PassZones.Share) -> TimeInterval in s + z.seconds }
    }

    var body: some View {
        let störst: TimeInterval = (1...5).map(sekunder).max() ?? 0
        if störst > 0 {
            VStack(alignment: .leading, spacing: 10) {
                PassKortRubrik(text: "Tid per pulszon")
                VStack(spacing: 2) {
                    ForEach([5, 4, 3, 2, 1], id: \.self) { (zon: Int) in
                        rad(zon, sek: sekunder(zon), störst: störst)
                    }
                }
                .padding(.horizontal, -10)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func rad(_ zon: Int, sek: TimeInterval, störst: TimeInterval) -> some View {
        let ärVald: Bool = vald == zon
        let full: Bool = vald == nil || ärVald
        let procent: Int = summa > 0 ? Int((100 * sek / summa).rounded()) : 0
        return Button { if sek > 0 { välj(zon) } } label: {
            HStack(spacing: 10) {
                Text(PassZonText.namn(zon))
                    .font(.system(size: 15, weight: ärVald ? .semibold : .regular))
                    .foregroundStyle(full ? Tema.text : Tema.dim)
                    .frame(width: 52, alignment: .leading)
                GeometryReader { (g: GeometryProxy) in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tema.card2)
                        if sek > 0 {
                            Capsule()
                                .fill(PassZonTrappa.color(zon))
                                .opacity(full ? 1 : 0.3)
                                .frame(width: max(6, g.size.width * CGFloat(sek / störst)))
                        }
                    }
                }
                .frame(height: 10)
                Text(PassZonText.tid(sek))
                    .font(.system(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(full && sek > 0 ? Tema.text : Tema.dim)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 52, alignment: .trailing)
                Text("\(procent) %")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Tema.dim)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(ärVald ? Tema.card2.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(PassZonText.namn(zon) + ", " + PassZonText.tid(sek) + ", \(procent) procent")
        .accessibilityAddTraits(ärVald ? .isSelected : [])
    }
}

