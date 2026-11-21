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
/// vid Start och vid Stopp med klockslaget under i textens färg. Pulsen kan ha zonerna som svaga band bakom kurvan.
/// Ett håll på kurvan sätter en punkt som följer fingret, med värdet och tiden i hörnet och ett knäpp när punkten kommer;
/// den försvinner när fingret släpps. Färre än två punkter ger en text.
struct PassKurva: View {
    /// Ett zonband: zonens undre gräns i kurvans enhet och dess färg.
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
    /// Zonbanden bakom kurvan, i stigande ordning; tomt = inga band.
    var band: [Band] = []
    /// Texten för ett värde på skalan.
    var text: (Double) -> String
    /// Talet och enheten i hörnet när en punkt är vald, t.ex. ("124", "bpm").
    var vald: (Double) -> (tal: String, enhet: String) = { (v: Double) in (String(Int(v.rounded())), "") }
    /// Vad skärmläsaren säger om kurvan.
    var etikett: String = "Kurva"

    @State private var markerad: Date? = nil

    /// Uttrycklig, för `@State private var markerad` gör den automatiska initieraren privat (se `Pekyta`).
    init(punkter: [PassSeries.Point], längd: TimeInterval, start: Date? = nil, stopp: TimeInterval? = nil,
         lucka: TimeInterval? = nil, omvänd: Bool = false, band: [Band] = [],
         text: @escaping (Double) -> String,
         vald: @escaping (Double) -> (tal: String, enhet: String) = { (v: Double) in (String(Int(v.rounded())), "") },
         etikett: String = "Kurva") {
        self.punkter = punkter
        self.längd = längd
        self.start = start
        self.stopp = stopp
        self.lucka = lucka
        self.omvänd = omvänd
        self.band = band
        self.text = text
        self.vald = vald
        self.etikett = etikett
    }

    /// Kurvans kanter i ytan, som Nattens (B99): början och slutet syns, och skalans tal står utanför till höger.
    static let kant: (vänster: CGFloat, höger: CGFloat) = (20, 30)
    private static let ytaHöjd: CGFloat = 230
    /// Ritytan ovanför klockslagen.
    private static let topp: CGFloat = 12
    private static let botten: CGFloat = 34
    private static let linje: CGFloat = 1.6

    /// Tidsaxelns nollpunkt i sekunder sedan 1970 (passets start, eller 0 utan start).
    private var t0: TimeInterval { start?.timeIntervalSince1970 ?? 0 }
    private var xMax: TimeInterval { max(1, längd, punkter.last?.seconds ?? 0) }

    /// Skalan: jämna steg (1, 2 eller 5 gånger en tiopotens) så att det blir fyra till sju linjer.
    static func skala(_ låg: Double, _ hög: Double) -> (lo: Double, hi: Double, steg: Double) {
        let spann: Double = max(hög - låg, 1)
        let rå: Double = spann / 5
        let tio: Double = pow(10, (log10(rå)).rounded(.down))
        let steg: Double = [1, 2, 5, 10].map { (f: Double) -> Double in f * tio }
            .first { (s: Double) -> Bool in s >= rå } ?? 10 * tio
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
        guard let n = PassSeries.nearest(punkter, to: s) else { return nil }
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
            .pekMarkering($markerad, från: t0, till: t0 + xMax,
                          vänster: Self.kant.vänster, höger: Self.kant.höger)
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
        return v.seconds / xMax < 0.4 ? .topTrailing : .topLeading
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
        let vä: CGFloat = Self.kant.vänster
        let bredd: CGFloat = max(1, W - vä - Self.kant.höger)
        let xMax: TimeInterval = self.xMax
        let x = { (s: TimeInterval) -> CGFloat in vä + CGFloat(min(1, max(0, s / xMax))) * bredd }

        let värden: [Double] = punkter.map { (q: PassSeries.Point) -> Double in q.value }
        let sk: (lo: Double, hi: Double, steg: Double) = Self.skala(värden.min() ?? 0, värden.max() ?? 0)
        let vänd: Bool = omvänd
        let y = { (v: Double) -> CGFloat in
            let f: Double = (min(max(v, sk.lo), sk.hi) - sk.lo) / (sk.hi - sk.lo)
            return top + CGFloat(vänd ? f : 1 - f) * ch
        }

        // BESLUT B144. Zonerna som svaga band bakom kurvan, inom skalan.
        for (i, b) in band.enumerated() {
            let övre: Double = i + 1 < band.count ? band[i + 1].från : sk.hi
            let a: Double = max(b.från, sk.lo)
            let ö: Double = min(övre, sk.hi)
            guard ö > a else { continue }
            let y1: CGFloat = y(ö)
            let y2: CGFloat = y(a)
            ctx.fill(Path(CGRect(x: 0, y: min(y1, y2), width: W, height: abs(y2 - y1))),
                     with: .color(b.färg.opacity(0.07)))
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
        for q in punkter {
            let ärEfter: Bool = stopp.map { (s: TimeInterval) -> Bool in q.seconds > s } ?? false
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

        func rita(_ stycken: [[CGPoint]], yta ytans: Double, linje linjens: Double) {
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
                ctx.stroke(l, with: .color(Tema.pulse.opacity(linjens)),
                           style: StrokeStyle(lineWidth: Self.linje, lineCap: .round, lineJoin: .round))
            }
        }
        rita(efter, yta: 0.10, linje: 0.4)
        rita(före, yta: 0.30, linje: 1)

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

/// BESLUT B138. Tid per pulszon: en liggande remsa delad efter tiden i zon 1–5 och en rad per zon med tid.
/// Utan tid i någon zon ritas inget.
struct PassZonKort: View {
    let zoner: [PassZones.Share]

    private var med: [PassZones.Share] {
        zoner.filter { (z: PassZones.Share) -> Bool in z.zone >= 1 && z.seconds > 0 }
    }

    var body: some View {
        if !med.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PassKortRubrik(text: "Tid per pulszon")
                ZonRemsa(zoner: zoner, höjd: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(spacing: 10) {
                    ForEach(med, id: \.zone) { (z: PassZones.Share) in
                        HStack(spacing: 8) {
                            Circle().fill(PassZonTrappa.color(z.zone)).frame(width: 8, height: 8)
                            Text(PassZonText.namn(z.zone))
                                .font(.system(size: 15))
                                .foregroundStyle(Tema.text)
                            Spacer(minLength: 8)
                            Text(PassZonText.tid(z.seconds))
                                .font(.system(size: 15))
                                .monospacedDigit()
                                .foregroundStyle(Tema.text)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

/// BESLUT B138 · METOD M47. Återhämtningen efter stopp: pulsen vid stopp och efter 1, 2 och 5 minuter, med fallet från
/// stopp i en värdepille. Fallet har ingen färg: källans gränser används aldrig mot ett pass i appen.
struct PassEfterStoppKort: View {
    let pass: Pass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                PassKortRubrik(text: "Efter stopp")
                Spacer(minLength: 8)
                Text("återhämtning").font(.system(size: 12)).foregroundStyle(Tema.dim)
            }
            .padding(.bottom, 6)
            rad("Stopp", bpm: pass.pulseAtStop, fall: nil, först: true)
            ForEach(pass.recovery, id: \.seconds) { (r: PassRecoveryPoint) in
                rad(minuter(r.seconds), bpm: r.bpm, fall: r.drop, först: false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func minuter(_ sekunder: Int) -> String {
        let m: Int = sekunder / 60
        return m == 1 ? "1 minut" : "\(m) minuter"
    }

    private func rad(_ namn: String, bpm: Int?, fall: Int?, först: Bool) -> some View {
        VStack(spacing: 0) {
            if !först {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
            HStack(spacing: 8) {
                Text(namn).font(.system(size: 15)).foregroundStyle(Tema.dim)
                Spacer(minLength: 8)
                if let b = bpm {
                    Text("\(b) slag")
                        .font(.system(size: 17))
                        .monospacedDigit()
                        .foregroundStyle(Tema.text)
                } else {
                    Text("–").font(.system(size: 17)).foregroundStyle(Tema.dim)
                }
                if let f = fall {
                    Text(f >= 0 ? "\u{2212}\(f)" : "+\(-f)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Tema.text)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(Tema.card2))
                }
            }
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
    }
}
