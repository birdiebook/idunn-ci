import SwiftUI
import Pass

/// BESLUT B138
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

/// BESLUT B138 · METOD M79
/// En kurva över passets tid utan Charts: tre rutnätslinjer med värden, linjen fram till stopp i `Tema.text` och delen efter
/// stopp dämpad, en streckad linje och en prick vid stopp och på tiden under ytan. y-axeln går från lägsta till högsta
/// värdet med 10 % luft uppe och nere; alla värden lika ger en linje mitt i. Färre än två punkter ger en text.
struct PassKurva: View {
    let punkter: [PassSeries.Point]
    /// Passets längd i sekunder (x-axelns högra kant är max av den och sista punkten).
    let längd: TimeInterval
    /// Sekunder från Start till Stopp; delen efter ritas dämpad. nil = inget stopp på kurvan.
    var stopp: TimeInterval? = nil
    /// Större lucka än så här (sekunder) mellan två punkter bryter linjen; nil = bryts aldrig.
    var lucka: TimeInterval? = nil
    /// true = lägre värde ritas högre upp (tempo).
    var omvänd: Bool = false
    /// Texten för ett värde på y-axeln och i markören.
    var text: (Double) -> String
    /// Markörens text vid stopp, t.ex. "168 · stopp"; nil = ingen markör.
    var markör: String? = nil
    /// Vad skärmläsaren säger om kurvan.
    var etikett: String = "Kurva"

    /// Utrymmet till höger om kurvan för värdena.
    private static let marginal: CGFloat = 34
    private static let ytaHöjd: CGFloat = 200
    /// Fler punkter än så här ritas inte.
    private static let flest: Int = 600

    /// Glesar ut till högst `flest` punkter (var n:te, den sista alltid med) och säger hur glest.
    private static func glesa(_ p: [PassSeries.Point]) -> (punkter: [PassSeries.Point], steg: Int) {
        guard p.count > flest else { return (p, 1) }
        let steg: Int = (p.count + flest - 1) / flest
        var ut: [PassSeries.Point] = []
        for (i, q) in p.enumerated() where i % steg == 0 || i == p.count - 1 {
            ut.append(q)
        }
        return (ut, steg)
    }

    var body: some View {
        let glest: (punkter: [PassSeries.Point], steg: Int) = Self.glesa(punkter)
        if glest.punkter.count < 2 {
            Text("Ingen kurva för det här passet.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.dim)
                .frame(maxWidth: .infinity, minHeight: Self.ytaHöjd, alignment: .center)
        } else {
            VStack(spacing: 6) {
                GeometryReader { (g: GeometryProxy) in
                    ritning(glest.punkter, steg: glest.steg, yta: g.size)
                }
                .frame(height: Self.ytaHöjd)
                HStack {
                    Text("0")
                    Spacer(minLength: 8)
                    Text(PassFormat.short(längd))
                }
                .font(.system(size: 11))
                .foregroundStyle(Tema.dim)
                .padding(.trailing, Self.marginal)
            }
        }
    }

    private func ritning(_ p: [PassSeries.Point], steg: Int, yta: CGSize) -> some View {
        let värden: [Double] = punkter.map { (q: PassSeries.Point) -> Double in q.value }
        let låg: Double = värden.min() ?? 0
        let hög: Double = värden.max() ?? 0
        let bredd: CGFloat = max(1, yta.width - Self.marginal)
        let höjd: CGFloat = yta.height
        let xMax: Double = max(1, längd, punkter.last?.seconds ?? 0)
        let vänd: Bool = omvänd
        let xAv: (Double) -> CGFloat = { (s: Double) -> CGFloat in
            CGFloat(min(1, max(0, s / xMax))) * bredd
        }
        let yAv: (Double) -> CGFloat = { (v: Double) -> CGFloat in
            let f: Double = hög > låg ? (v - låg) / (hög - låg) : 0.5
            let fy: Double = vänd ? f : 1 - f
            return höjd * CGFloat(0.1 + 0.8 * fy)
        }

        var före: Path = Path()
        var efter: Path = Path()
        var sistFöre: Int = -2
        var sistEfter: Int = -2
        let gräns: Double? = lucka.map { (l: TimeInterval) -> Double in l * Double(max(1, steg)) }
        for i in 1..<p.count {
            let a: PassSeries.Point = p[i - 1]
            let b: PassSeries.Point = p[i]
            if let g = gräns, b.seconds - a.seconds > g { continue }
            let pa: CGPoint = CGPoint(x: xAv(a.seconds), y: yAv(a.value))
            let pb: CGPoint = CGPoint(x: xAv(b.seconds), y: yAv(b.value))
            let dämpad: Bool = stopp.map { (s: TimeInterval) -> Bool in b.seconds > s } ?? false
            if dämpad {
                if sistEfter != i - 1 { efter.move(to: pa) }
                efter.addLine(to: pb)
                sistEfter = i
            } else {
                if sistFöre != i - 1 { före.move(to: pa) }
                före.addLine(to: pb)
                sistFöre = i
            }
        }

        let nivåer: [Double] = hög > låg ? [hög, (hög + låg) / 2, låg] : [hög]
        let stoppX: CGFloat? = stopp.flatMap { (s: TimeInterval) -> CGFloat? in
            (s > 0 && s < xMax) ? xAv(s) : nil
        }
        let närmast: PassSeries.Point? = stopp.flatMap { (s: TimeInterval) -> PassSeries.Point? in
            PassSeries.nearest(punkter, to: s)
        }
        let marginal: CGFloat = Self.marginal

        return ZStack(alignment: .topLeading) {
            ForEach(Array(nivåer.enumerated()), id: \.offset) { (e: (offset: Int, element: Double)) in
                let y: CGFloat = yAv(e.element)
                Path { (v: inout Path) -> Void in
                    v.move(to: CGPoint(x: 0, y: y))
                    v.addLine(to: CGPoint(x: bredd, y: y))
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                Text(text(e.element))
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: marginal, alignment: .trailing)
                    .position(x: bredd + marginal / 2, y: y - 8)
            }
            efter.stroke(Tema.dim.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            före.stroke(Tema.text, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let sx = stoppX {
                Path { (v: inout Path) -> Void in
                    v.move(to: CGPoint(x: sx, y: 0))
                    v.addLine(to: CGPoint(x: sx, y: höjd))
                }
                .stroke(Tema.dim, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let n = närmast {
                    let py: CGFloat = yAv(n.value)
                    Circle()
                        .fill(Tema.text)
                        .frame(width: 8, height: 8)
                        .position(x: sx, y: py)
                    if let m = markör {
                        let halv: CGFloat = CGFloat(m.count) * 3.6 + 10
                        let px: CGFloat = min(max(sx, halv), max(halv, bredd + marginal - halv))
                        Text(m)
                            .font(.system(size: 11))
                            .foregroundStyle(Tema.text)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Tema.card2))
                            .position(x: px, y: max(10, py - 20))
                    }
                }
            }
        }
        .frame(width: yta.width, height: yta.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etikett)
    }
}

// MARK: - Delkorten

/// BESLUT B138. Raden med tre tal överst i det sparade passet: tid, snittpuls och högsta puls.
struct PassTreTal: View {
    let pass: Pass

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            tal(PassFormat.short(pass.duration), "tid")
            tal(PassFormat.bpm(pass.averageBpm), "snittpuls")
            tal(PassFormat.bpm(pass.maxBpm), "högst")
        }
    }

    private func tal(_ värde: String, _ etikett: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(värde)
                .font(.system(size: 40, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(etikett).font(.system(size: 12)).foregroundStyle(Tema.dim)
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
                            Text("Zon \(z.zone)")
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
