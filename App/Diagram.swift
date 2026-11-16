import SwiftUI
import Night

/// BESLUT B63 · METOD M18 · METOD M32 · METOD M51
/// Diagrammen i skissens form, ritade i Canvas (`ImageRenderer` ritar dem): veckans och periodens staplar och linjer med
/// normalband, tomma diagram för spåret H, nattens pulskurva med stadierna under, och de små diagrammen på Natten.
/// Vyerna tar sin data som värden. Diagrammen med håll och dra (Över tid) är Swift Charts i `TrendsView`.

extension GraphicsContext {
    /// En text på en punkt: siffror i monospace, etiketter små.
    func etikett(_ text: String, _ punkt: CGPoint, storlek: CGFloat = 9, färg: Color = Tema.faint,
                 ankare: UnitPoint = .center, mono: Bool = true, vikt: Font.Weight = .regular) {
        let f: Font = mono ? Tema.mono(storlek, vikt) : Font.system(size: storlek, weight: vikt)
        self.draw(Text(text).font(f).foregroundColor(färg), at: punkt, anchor: ankare)
    }
}

/// Staplar eller en linje över dagar eller veckor, med normalband, mål, medel och värden på de sista punkterna.
struct TidDiagram: View {
    enum Typ {
        case stapel
        case linje
    }

    let värden: [Double?]
    let etiketter: [String]
    var typ: Typ = .stapel
    var färgFn: ((Double) -> Color)? = nil
    var band: [ClosedRange<Double>?]? = nil
    var mål: [Double?]? = nil
    var ymin: Double? = nil
    var ymax: Double? = nil
    var rutor: Int = 3
    var medel: Double? = nil
    var format: (Double) -> String = { (v: Double) -> String in Fmt.num(v) }
    var bra: Int = 0
    var höjd: CGFloat = 170

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            teckna(ctx, size)
        }
        .frame(height: höjd)
        .accessibilityHidden(true)
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let pl: CGFloat = 4
        let pr: CGFloat = 30
        let pt: CGFloat = 20
        let pb: CGFloat = 24
        let iw: CGFloat = W - pl - pr
        let ih: CGFloat = H - pt - pb
        let n: Int = värden.count
        guard n > 0, iw > 0, ih > 0 else { return }

        var alla: [Double] = värden.compactMap { (v: Double?) -> Double? in v }
        if let b = band {
            for r in b {
                if let r = r {
                    alla.append(r.lowerBound)
                    alla.append(r.upperBound)
                }
            }
        }
        if let m = mål { alla += m.compactMap { (v: Double?) -> Double? in v } }
        var lo: Double = ymin ?? (alla.min() ?? 0)
        var hi: Double = ymax ?? (alla.max() ?? 1)
        if ymin == nil {
            let p: Double = (hi - lo) * 0.25
            let pad: Double = p > 0 ? p : 1
            lo -= pad
            hi += pad
        }
        if hi - lo < 1e-9 { hi = lo + 1 }
        let lo2: Double = lo
        let hi2: Double = hi
        let steg: CGFloat = iw / CGFloat(n)
        let xi = { (i: Int) -> CGFloat in pl + steg * CGFloat(i) + steg / 2 }
        let yv = { (v: Double) -> CGFloat in pt + ih - CGFloat((v - lo2) / (hi2 - lo2)) * ih }

        // Rutnät och tal till höger.
        for g in 0...max(1, rutor) {
            let v: Double = lo2 + (hi2 - lo2) * Double(g) / Double(max(1, rutor))
            let y: CGFloat = yv(v)
            var linje = Path()
            linje.move(to: CGPoint(x: pl, y: y))
            linje.addLine(to: CGPoint(x: W - pr, y: y))
            ctx.stroke(linje, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
            ctx.etikett(format(v), CGPoint(x: W - pr + 4, y: y), ankare: .leading)
        }

        // Normalbandet, ett stycke per följd av dagar med band.
        if let b = band {
            var start: Int? = nil
            for i in 0...n {
                let har: Bool = i < n && i < b.count && b[i] != nil
                if har, start == nil { start = i }
                if !har, let s = start {
                    var p = Path()
                    for j in s..<i {
                        if let r = b[j] {
                            let pkt = CGPoint(x: xi(j), y: yv(r.upperBound))
                            if j == s { p.move(to: pkt) } else { p.addLine(to: pkt) }
                        }
                    }
                    for j in stride(from: i - 1, through: s, by: -1) {
                        if let r = b[j] { p.addLine(to: CGPoint(x: xi(j), y: yv(r.lowerBound))) }
                    }
                    p.closeSubpath()
                    ctx.fill(p, with: .color(Tema.band.opacity(0.6)))
                    start = nil
                }
            }
        }
        if let m = medel {
            var p = Path()
            p.move(to: CGPoint(x: pl, y: yv(m)))
            p.addLine(to: CGPoint(x: W - pr, y: yv(m)))
            ctx.stroke(p, with: .color(Tema.dim), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        // Sista punkten markerad.
        let markering = Path(roundedRect: CGRect(x: xi(n - 1) - steg / 2, y: pt - 16, width: steg, height: ih + 16),
                             cornerRadius: 3)
        ctx.fill(markering, with: .color(Color.white.opacity(0.04)))

        switch typ {
        case .stapel:
            let bw: CGFloat = max(2, min(20, steg * 0.6))
            for i in 0..<n {
                guard let v = värden[i] else { continue }
                let c: Color = färgFn?(v) ?? Tema.accent
                let y: CGFloat = yv(v)
                let r = CGRect(x: xi(i) - bw / 2, y: y, width: bw, height: max(0, pt + ih - y))
                ctx.fill(Path(roundedRect: r, cornerRadius: min(3, bw / 2)), with: .color(c))
                if n <= 8, mål == nil || i == n - 1 {
                    ctx.etikett(format(v), CGPoint(x: xi(i), y: y - 4), storlek: 10, färg: c, ankare: .bottom)
                }
            }
            if let m = mål {
                for i in 0..<min(n, m.count) {
                    guard let g = m[i] else { continue }
                    var p = Path()
                    p.move(to: CGPoint(x: xi(i) - bw / 2 - 2, y: yv(g)))
                    p.addLine(to: CGPoint(x: xi(i) + bw / 2 + 2, y: yv(g)))
                    ctx.stroke(p, with: .color(Tema.text), lineWidth: 2)
                }
            }
        case .linje:
            var p = Path()
            var pen = false
            for i in 0..<n {
                guard let v = värden[i] else {
                    pen = false
                    continue
                }
                let pkt = CGPoint(x: xi(i), y: yv(v))
                if pen { p.addLine(to: pkt) } else { p.move(to: pkt) }
                pen = true
            }
            ctx.stroke(p, with: .color(Tema.accent), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            for i in 0..<n {
                guard let v = värden[i] else { continue }
                if n > 8 && i < n - 1 { continue }
                var ute: Bool = false
                var sämre: Bool = false
                if let b = band, i < b.count, let r = b[i] {
                    ute = !r.contains(v)
                    sämre = ute && bra != 0 && ((v > r.upperBound) != (bra > 0))
                }
                let c: Color = sämre ? Tema.yellow : Tema.accent
                let ring = Path(ellipseIn: CGRect(x: xi(i) - 3.5, y: yv(v) - 3.5, width: 7, height: 7))
                ctx.fill(ring, with: .color(ute ? c : Tema.bg))
                ctx.stroke(ring, with: .color(ute ? c : Tema.accent), lineWidth: 1.6)
                if n <= 8 {
                    ctx.etikett(format(v), CGPoint(x: xi(i), y: yv(v) - 8), storlek: 10, färg: Tema.text, ankare: .bottom)
                }
            }
        }

        // Dagarna under: högst åtta etiketter, den sista tydligast.
        let var_: Int = max(1, Int((Double(n) / 8).rounded(.up)))
        for i in 0..<min(n, etiketter.count) {
            if (n - 1 - i) % var_ != 0 { continue }
            ctx.etikett(etiketter[i], CGPoint(x: xi(i), y: H - 8), färg: i == n - 1 ? Tema.text : Tema.faint)
        }
    }
}

/// BESLUT B79. Sömn mot behov som två linjer (användaren 2026-11-09): sömnen i blått och behovet i ljusgrått, varje punkt
/// med sitt tal, det högre talet ovanför sin punkt och det lägre under, och dagens kolumn markerad. Timmar.
struct SömnMotBehov: View {
    let sömn: [Double?]
    let behov: [Double?]
    let etiketter: [String]
    var höjd: CGFloat = 190

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            teckna(ctx, size)
        }
        .frame(height: höjd)
        .accessibilityHidden(true)
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let pt: CGFloat = 24
        let pb: CGFloat = 40
        let ih: CGFloat = H - pt - pb
        let n: Int = max(sömn.count, behov.count)
        guard n > 0, ih > 0 else { return }
        let alla: [Double] = (sömn + behov).compactMap { (v: Double?) -> Double? in v }
        guard let minst = alla.min(), let mest = alla.max() else { return }
        let luft: Double = max(0.5, (mest - minst) * 0.3)
        let lo: Double = minst - luft
        let hi: Double = mest + luft
        let steg: CGFloat = W / CGFloat(n)
        let xi = { (i: Int) -> CGFloat in steg * CGFloat(i) + steg / 2 }
        let yv = { (v: Double) -> CGFloat in pt + ih - CGFloat((v - lo) / (hi - lo)) * ih }

        for g in 0...3 {
            let y: CGFloat = pt + ih * CGFloat(g) / 3
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: W, y: y))
            ctx.stroke(p, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
        }
        let markering = Path(roundedRect: CGRect(x: xi(n - 1) - steg / 2 + 4, y: pt - 20, width: steg - 8,
                                                 height: ih + 20 + pb - 4), cornerRadius: 6)
        ctx.fill(markering, with: .color(Color.white.opacity(0.05)))

        func serie(_ v: [Double?], _ färg: Color, _ ovanför: (Int) -> Bool) {
            var p = Path()
            var pen = false
            for i in 0..<n {
                guard i < v.count, let x = v[i] else {
                    pen = false
                    continue
                }
                let pkt = CGPoint(x: xi(i), y: yv(x))
                if pen { p.addLine(to: pkt) } else { p.move(to: pkt) }
                pen = true
            }
            ctx.stroke(p, with: .color(färg.opacity(0.7)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            for i in 0..<n {
                guard i < v.count, let x = v[i] else { continue }
                let ring = Path(ellipseIn: CGRect(x: xi(i) - 4.5, y: yv(x) - 4.5, width: 9, height: 9))
                ctx.fill(ring, with: .color(Tema.bg))
                ctx.stroke(ring, with: .color(färg), lineWidth: 2)
                let upp: Bool = ovanför(i)
                ctx.etikett(Fmt.hm(hours: x), CGPoint(x: xi(i), y: yv(x) + (upp ? -9 : 9)), storlek: 11, färg: färg,
                            ankare: upp ? .bottom : .top)
            }
        }
        // Det högre talet står ovanför sin punkt, det lägre under, så att de aldrig krockar.
        let behovÖver = { (i: Int) -> Bool in
            guard i < behov.count, let b = behov[i] else { return true }
            guard i < sömn.count, let s = sömn[i] else { return true }
            return b >= s
        }
        serie(behov, Tema.awake, behovÖver)
        serie(sömn, Tema.accent, { (i: Int) -> Bool in !behovÖver(i) })

        for i in 0..<min(n, etiketter.count) {
            ctx.etikett(etiketter[i], CGPoint(x: xi(i), y: H - 12), färg: i == n - 1 ? Tema.text : Tema.faint)
        }
    }
}

/// BESLUT B83. Dagar per läge under ett veckodiagram: ett band delat efter antalet dagar i varje läge, och en rad per
/// läge med färg, namn, gräns och antal ("2×"). Ett läge utan dagar står kvar med 0×, så att formen står still.
struct Lägesband: View {
    struct Läge {
        var namn: String
        var gräns: String
        var färg: Color
        var antal: Int
    }

    let lägen: [Läge]

    var body: some View {
        let summa: Int = lägen.reduce(0) { (a: Int, l: Läge) -> Int in a + l.antal }
        let delar: [(Double, Color)]? = summa == 0 ? nil : lägen.filter { (l: Läge) -> Bool in l.antal > 0 }
            .map { (l: Läge) -> (Double, Color) in (Double(l.antal), l.färg) }
        return VStack(alignment: .leading, spacing: 6) {
            Fördelning(delar: delar)
            ForEach(0..<lägen.count, id: \.self) { (i: Int) in
                let l: Läge = lägen[i]
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(l.färg).frame(width: 8, height: 8)
                    Text(l.namn)
                    Text(l.gräns).foregroundStyle(Tema.faint)
                    Spacer(minLength: 4)
                    Text("\(l.antal)×")
                        .font(Tema.mono(12))
                        .foregroundStyle(l.antal == 0 ? Tema.faint : Tema.text)
                }
                .font(.system(size: 12))
                .foregroundStyle(Tema.dim)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Samma diagram utan värden (spåret H): rutnätet, dagarna och ett streck i mitten.
struct TomtDiagram: View {
    let etiketter: [String]
    var höjd: CGFloat = 150

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            teckna(ctx, size)
        }
        .frame(height: höjd)
        .accessibilityHidden(true)
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let pr: CGFloat = 30
        let pt: CGFloat = 20
        let pb: CGFloat = 24
        let ih: CGFloat = H - pt - pb
        let n: Int = etiketter.count
        guard n > 0, ih > 0 else { return }
        for g in 0...3 {
            let y: CGFloat = pt + ih * CGFloat(g) / 3
            var p = Path()
            p.move(to: CGPoint(x: 4, y: y))
            p.addLine(to: CGPoint(x: W - pr, y: y))
            ctx.stroke(p, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
        }
        ctx.etikett("–", CGPoint(x: (W - pr) / 2, y: pt + ih / 2), storlek: 12)
        let steg: CGFloat = (W - 4 - pr) / CGFloat(n)
        let var_: Int = max(1, Int((Double(n) / 8).rounded(.up)))
        for i in 0..<n {
            if (n - 1 - i) % var_ != 0 { continue }
            ctx.etikett(etiketter[i], CGPoint(x: 4 + steg * CGFloat(i) + steg / 2, y: H - 8),
                        färg: i == n - 1 ? Tema.text : Tema.faint)
        }
    }
}

/// Stapeldiagram med staplar i två lager (djup + REM, sömnstress): `delar[i]` är de staplade värdena för dag i.
struct StapelDiagram: View {
    let delar: [[Double?]]
    let färger: [Color]
    let etiketter: [String]
    let ymax: Double
    var siffra: (([Double?]) -> String?)? = nil
    var höjd: CGFloat = 150

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            teckna(ctx, size)
        }
        .frame(height: höjd)
        .accessibilityHidden(true)
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let pt: CGFloat = 18
        let pb: CGFloat = 22
        let ih: CGFloat = H - pt - pb
        let n: Int = delar.count
        guard n > 0, ih > 0, ymax > 0 else { return }
        let steg: CGFloat = (W - 10) / CGFloat(n)
        let yv = { (v: Double) -> CGFloat in pt + ih - CGFloat(min(v, ymax) / ymax) * ih }
        for i in 0..<n {
            let cx: CGFloat = steg * CGFloat(i) + steg / 2
            var botten: Double = 0
            for (j, v) in delar[i].enumerated() {
                guard let v = v, v > 0 else { continue }
                let r = CGRect(x: cx - 9, y: yv(botten + v), width: 18, height: max(0, yv(botten) - yv(botten + v)))
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(färger[min(j, färger.count - 1)]))
                botten += v
            }
            if botten > 0, let s = siffra?(delar[i]) {
                ctx.etikett(s, CGPoint(x: cx, y: yv(botten) - 4), storlek: 10, färg: Color(rgb: 0xCFD8DD), ankare: .bottom)
            }
            if i < etiketter.count {
                ctx.etikett(etiketter[i], CGPoint(x: cx, y: H - 8), färg: i == n - 1 ? Tema.text : Tema.faint)
            }
        }
    }
}

/// Ritningen som nattens diagram delar: stadierna som ett band och klockslagen under.
enum NattRitning {
    /// METOD M18 · BESLUT B96. En lucka i pulskurvan på högst så här många sekunder binds ihop med en svagare linje.
    static let broSekunder: TimeInterval = 600
    /// METOD M18 · BESLUT B97. Pulskurvans skala när nattens puls ryms i den, i slag per minut.
    static let pulsskala: ClosedRange<Double> = 40...80
    /// BESLUT B98. Pulskurvans linje, i punkter (1,6 före B98).
    static let pulslinje: CGFloat = 1.35

    static func färg(_ s: SleepStage) -> Color {
        switch s {
        case .wake: return Tema.awake
        case .light: return Tema.light
        case .deep: return Tema.deep
        case .rem: return Tema.rem
        }
    }

    /// Bandets ruta per följd av epoker; opaciteten följer hur säker modellen är (METOD M37, nivå 0–2). Med `valt`
    /// (BESLUT B83) dämpas de andra stadierna.
    static func stadier(_ ctx: GraphicsContext, spans: [NightLayers.StageSpan], t0: TimeInterval, t1: TimeInterval,
                        bredd: CGFloat, y: CGFloat, höjd: CGFloat, valt: SleepStage? = nil) {
        guard t1 > t0 else { return }
        for s in spans {
            let a: CGFloat = CGFloat((s.start - t0) / (t1 - t0)) * bredd
            let b: CGFloat = CGFloat((s.end - t0) / (t1 - t0)) * bredd
            let nivå: Int = min(2, max(0, s.certainty))
            let dämpad: Bool = valt != nil && valt != s.stage
            let opacitet: Double = [0.55, 0.78, 1.0][nivå] * (dämpad ? 0.3 : 1)
            let r = CGRect(x: a, y: y, width: max(1, b - a), height: höjd)
            ctx.fill(Path(r), with: .color(färg(s.stage).opacity(opacitet)))
        }
    }

    /// BESLUT B83. Stunderna i stadiet `s` som rutor över hela höjden, i x-led på nattens axel: kurvan klipps till dem.
    static func stunder(_ spans: [NightLayers.StageSpan], _ s: SleepStage, t0: TimeInterval, t1: TimeInterval,
                        bredd: CGFloat, höjd: CGFloat) -> Path {
        var p = Path()
        guard t1 > t0 else { return p }
        for span in spans where span.stage == s {
            let a: CGFloat = CGFloat((span.start - t0) / (t1 - t0)) * bredd
            let b: CGFloat = CGFloat((span.end - t0) / (t1 - t0)) * bredd
            p.addRect(CGRect(x: a, y: 0, width: max(1, b - a), height: höjd))
        }
        return p
    }

    /// Klockslagen: början, mitten och slutet, eller fem när `fem`. Med `ändar` (BESLUT B99, Nattens pulskurva) står
    /// början och slutet större och ljusare, mitt under nattens kant, där den streckade linjen slutar, och klockslagen
    /// däremellan är hela timmar (`helaTimmar`).
    static func klockor(_ ctx: GraphicsContext, t0: TimeInterval, t1: TimeInterval, bredd: CGFloat, y: CGFloat,
                        fem: Bool, ändar: Bool = false) {
        if ändar {
            for (f, t) in [(CGFloat(0), t0), (CGFloat(1), t1)] {
                ctx.etikett(Fmt.clock(time: t), CGPoint(x: f * bredd, y: y), storlek: 12, färg: Tema.text,
                            vikt: .semibold)
            }
            guard t1 > t0 else { return }
            for t in helaTimmar(t0, t1, bredd: bredd) {
                let x: CGFloat = CGFloat((t - t0) / (t1 - t0)) * bredd
                ctx.etikett(Fmt.clock(time: t), CGPoint(x: x, y: y), storlek: 10, färg: Tema.dim)
            }
            return
        }
        let delar: [Double] = fem ? [0, 0.25, 0.5, 0.75, 1] : [0, 0.5, 1]
        for f in delar {
            let t: TimeInterval = t0 + f * (t1 - t0)
            let x: CGFloat = CGFloat(f) * bredd + (f == 0 ? 2 : (f == 1 ? -2 : 0))
            let ankare: UnitPoint = f == 0 ? .leading : (f == 1 ? .trailing : .center)
            ctx.etikett(Fmt.clock(time: t), CGPoint(x: x, y: y), storlek: 10, färg: Tema.dim, ankare: ankare)
        }
    }

    /// BESLUT B99. Hela timmar mellan `t0` och `t1` i telefonens zon, med ett steg på en till flera timmar så att det
    /// blir högst fem (två timmar på en natt över 5 och upp till 10 timmar), på jämna timmar räknat från midnatt. En timme närmare än
    /// 44 punkter nattens början eller slut hoppas över, så att den inte krockar med deras klockslag.
    static func helaTimmar(_ t0: TimeInterval, _ t1: TimeInterval, bredd: CGFloat) -> [TimeInterval] {
        guard t1 > t0, bredd > 0 else { return [] }
        let kal: Calendar = Calendar.current
        guard var t: Date = kal.nextDate(after: Date(timeIntervalSince1970: t0),
                                         matching: DateComponents(minute: 0, second: 0),
                                         matchingPolicy: .nextTime) else { return [] }
        let steg: Int = max(1, Int(((t1 - t0) / 3600 / 5).rounded(.up)))
        var ut: [TimeInterval] = []
        while t.timeIntervalSince1970 < t1 {
            let s: TimeInterval = t.timeIntervalSince1970
            let x: CGFloat = CGFloat((s - t0) / (t1 - t0)) * bredd
            if kal.component(.hour, from: t) % steg == 0, x >= 44, bredd - x >= 44 {
                ut.append(s)
            }
            t = t.addingTimeInterval(3600)
        }
        return ut
    }
}

/// Nattens pulskurva med stadierna under (skissens `nightCurve`): pulsen minut för minut som linje och tonad yta, lägsta
/// pulsen som en ring med talet, stadierna som ett band och klockslagen. Utan stadier bara kurvan; utan kurva ett streck.
///
/// BESLUT B99 · BESLUT B98 · BESLUT B49. Med `peka` (Natten) markerar fingret en minut medan det håller: en punkt på
/// kurvan, ett streckat lodstreck och pulsen med klockslaget i hörnet, som i Whoop. Punkten kommer strax efter trycket
/// med ett knäpp, följer fingret utan fler knäppar och försvinner när fingret släpps. På Natten är kurvan indragen i
/// sidorna (`kant`), så att nattens början och slut syns och skalans tal står utanför kurvan; en streckad linje går ner
/// vid början och slutet till en prick, och klockslagen där står större och ljusare.
struct NattKurva: View {
    /// BESLUT B99. Natten börjar och slutar så här långt in från ritytans kanter (bara med `axel`), i punkter.
    static let kant: (vänster: CGFloat, höger: CGFloat) = (24, 30)

    let curve: NightCurve.Curve?
    let layers: NightLayers.Layers?
    var höjd: CGFloat = 170
    /// Axel med tre pulstal och fem klockslag (Natten); annars bara första och sista klockslaget (Morgon).
    var axel = false
    /// De tre pulstalen vid kanten utan de fem klockslagen (Morgon, användaren 2026-11-08).
    var skala = false
    /// BESLUT B83. Ett valt stadium (Natten): kurvan i stadiets färg där stadiet ligger, resten dämpad.
    var valt: SleepStage? = nil
    /// BESLUT B98. Kurvan tar emot fingret (Natten); på Morgon öppnar ett tryck Natten i stället.
    var peka = false
    @State private var markerad: Date?

    /// Den markerade minuten: närmaste minut med puls, om den ligger inom en bro (BESLUT B96) från fingret.
    struct Vald: Equatable {
        var tid: TimeInterval
        var puls: Double
        var slag: Int { Int(puls.rounded()) }
    }

    /// Nattens axel i tid, samma som ritningens.
    private var axeln: (t0: TimeInterval, t1: TimeInterval)? {
        guard let c = curve else { return nil }
        let t0: TimeInterval = layers?.start ?? c.start
        return (t0, max(layers?.end ?? c.end, t0 + 60))
    }

    private var vald: Vald? {
        guard peka, let m = markerad, let c = curve else { return nil }
        let t: TimeInterval = m.timeIntervalSince1970
        var bäst: Vald? = nil
        var avstånd: TimeInterval = .infinity
        for minut in c.minutes {
            guard let hr = minut.heartRate else { continue }
            let d: TimeInterval = abs(minut.mid - t)
            if d < avstånd {
                avstånd = d
                bäst = Vald(tid: minut.mid, puls: hr)
            }
        }
        return avstånd <= NattRitning.broSekunder ? bäst : nil
    }

    var body: some View {
        let v: Vald? = vald
        return Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            teckna(ctx, size, vald: v)
        }
        .frame(height: höjd)
        .overlay(alignment: etikettensSida(v)) {
            if let v = v { etikett(v) }
        }
        .modifier(Peka(på: peka && axeln != nil, markerad: $markerad, axeln: axeln, axel: axel))
        // BESLUT B99. Ett knäpp när punkten kommer, inget medan fingret drar.
        .sensoryFeedback(.impact(weight: .light), trigger: markerad != nil) { (före: Bool, nu: Bool) -> Bool in
            nu && !före
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nattens puls")
    }

    /// BESLUT B98. Talet står uppe till vänster, och till höger när punkten ligger i nattens vänstra del (där kurvan
    /// ofta är som högst), så att det inte täcker punkten.
    private func etikettensSida(_ v: Vald?) -> Alignment {
        guard let v = v, let a = axeln, a.t1 > a.t0 else { return .topLeading }
        return (v.tid - a.t0) / (a.t1 - a.t0) < 0.4 ? .topTrailing : .topLeading
    }

    private func etikett(_ v: Vald) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(v.slag)")
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                Text("bpm")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Tema.pulsLjus)
            Text(Fmt.clock(time: v.tid))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tema.dim)
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    /// BESLUT B99. Gesten bara på Natten, med samma kanter som ritningen.
    private struct Peka: ViewModifier {
        let på: Bool
        let markerad: Binding<Date?>
        let axeln: (t0: TimeInterval, t1: TimeInterval)?
        let axel: Bool

        func body(content: Content) -> some View {
            if på, let a = axeln {
                content.pekMarkering(markerad, från: a.t0, till: a.t1,
                                     vänster: axel ? NattKurva.kant.vänster : 0,
                                     höger: axel ? NattKurva.kant.höger : 0)
            } else {
                content
            }
        }
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize, vald: Vald?) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let top: CGFloat = 12
        let ch: CGFloat = H - 60
        guard let c = curve, ch > 10 else {
            ctx.etikett("–", CGPoint(x: W / 2, y: H / 2), storlek: 14)
            return
        }
        let t0: TimeInterval = layers?.start ?? c.start
        let t1: TimeInterval = max(layers?.end ?? c.end, t0 + 60)
        // BESLUT B99. Med axel (Natten) ritas natten mellan kanterna; skalans linjer och tal går ända ut.
        let vä: CGFloat = axel ? NattKurva.kant.vänster : 0
        let hö: CGFloat = axel ? NattKurva.kant.höger : 0
        let bredd: CGFloat = max(1, W - vä - hö)
        var natten: GraphicsContext = ctx
        natten.translateBy(x: vä, y: 0)
        let x = { (t: TimeInterval) -> CGFloat in vä + CGFloat((t - t0) / (t1 - t0)) * bredd }
        let puls: [Double] = c.minutes.compactMap { (m: NightCurve.Minute) -> Double? in m.heartRate }
        guard let lägst = puls.min(), let högst = puls.max() else {
            ctx.etikett("–", CGPoint(x: W / 2, y: top + ch / 2), storlek: 14)
            NattRitning.klockor(natten, t0: t0, t1: t1, bredd: bredd, y: H - 8, fem: axel, ändar: axel)
            return
        }
        // BESLUT B97. Skalan är 40–80 slag per minut varje natt. Går pulsen under eller över vidgas den åt det hållet,
        // till närmaste hela tiotal.
        let lo: Double = min(NattRitning.pulsskala.lowerBound, (lägst / 10).rounded(.down) * 10)
        let hi: Double = max(NattRitning.pulsskala.upperBound, (högst / 10).rounded(.up) * 10)
        let y = { (v: Double) -> CGFloat in
            top + ch - CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * ch
        }

        if axel || skala {
            // BESLUT B95 · BESLUT B97. Skalan står på vart tionde slag, och talen är ljusare än förut.
            let steg: Double = 10
            var v: Double = (lo / steg).rounded(.up) * steg
            while v <= hi {
                // Ett tal för nära överkanten skulle kapas.
                if y(v) - 7 > top - 8 {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y(v)))
                    p.addLine(to: CGPoint(x: W, y: y(v)))
                    ctx.stroke(p, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
                    ctx.etikett("\(Int(v))", CGPoint(x: W - 4, y: y(v) - 7), färg: Tema.dim, ankare: .trailing)
                }
                v += steg
            }
        }

        // BESLUT B99. Nattens början och slut (Natten): en streckad linje från överkanten ner till en prick strax över
        // klockslaget, som i Whoop. Kurvan och stadiebandet ritas över linjen.
        if axel {
            let prick: CGFloat = H - 20
            for t in [t0, t1] {
                let px: CGFloat = x(t)
                var p = Path()
                p.move(to: CGPoint(x: px, y: 2))
                p.addLine(to: CGPoint(x: px, y: prick))
                ctx.stroke(p, with: .color(Color.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ctx.fill(Path(ellipseIn: CGRect(x: px - 2.5, y: prick - 2.5, width: 5, height: 5)),
                         with: .color(Tema.text))
            }

            // BESLUT B99. Pulsen utanför sömnen: bandets puls före början och efter slutet (`Curve.outside`), en hel
            // linje, uttonad, i kanterna. Samma skala, men den får gå över den; ritytan ovanför stadiebandet klipper.
            let fri = { (v: Double) -> CGFloat in top + ch - CGFloat((v - lo) / (hi - lo)) * ch }
            var bitar: [[CGPoint]] = []
            var bit: [CGPoint] = []
            var förra: TimeInterval? = nil
            for m in c.outside where m.mid < t0 || m.mid > t1 {
                guard let hr = m.heartRate else { continue }
                if let f = förra, m.mid - f > 90 || (f < t0) != (m.mid < t0) {
                    if !bit.isEmpty { bitar.append(bit) }
                    bit = []
                }
                bit.append(CGPoint(x: x(m.mid), y: fri(hr)))
                förra = m.mid
            }
            if !bit.isEmpty { bitar.append(bit) }
            var utanför: GraphicsContext = ctx
            utanför.clip(to: Path(CGRect(x: 0, y: 0, width: W, height: top + ch)))
            for b in bitar {
                var p = Path()
                p.move(to: b[0])
                for q in b.dropFirst() { p.addLine(to: q) }
                if b.count == 1 { p.addLine(to: CGPoint(x: b[0].x + 1, y: b[0].y)) }
                utanför.stroke(p, with: .color(Tema.pulse.opacity(0.4)),
                               style: StrokeStyle(lineWidth: NattRitning.pulslinje, lineCap: .round, lineJoin: .round))
            }
        }

        // Pulsen i stycken, minut för minut: en lucka (en minut utan puls, eller ett glapp) delar kurvan i stycken.
        // BESLUT B96. En lucka på högst `NattRitning.broSekunder` binds ihop med en rak, svagare linje mellan styckena,
        // så att kurvan hänger ihop utan att luckan döljs. En längre lucka står tom.
        var stycken: [[CGPoint]] = []
        var broar: [(CGPoint, CGPoint)] = []
        var nu: [CGPoint] = []
        var förra: TimeInterval? = nil
        var sista: (CGPoint, TimeInterval)? = nil
        for m in c.minutes {
            guard let hr = m.heartRate else {
                if !nu.isEmpty { stycken.append(nu) }
                nu = []
                förra = nil
                continue
            }
            if let f = förra, m.mid - f > 150, !nu.isEmpty {
                stycken.append(nu)
                nu = []
            }
            let punkt: CGPoint = CGPoint(x: x(m.mid), y: y(hr))
            if nu.isEmpty, let s = sista, m.mid - s.1 <= NattRitning.broSekunder {
                broar.append((s.0, punkt))
            }
            nu.append(punkt)
            förra = m.mid
            sista = (punkt, m.mid)
        }
        if !nu.isEmpty { stycken.append(nu) }
        let botten: CGFloat = top + ch
        // BESLUT B83. Ett valt stadium med stunder i natten: hela kurvan dämpad, och samma kurva i stadiets färg
        // klippt till stunderna.
        let stadier: [NightLayers.StageSpan] = layers?.stages ?? []
        let färgad: SleepStage? = valt.flatMap { (s: SleepStage) -> SleepStage? in
            stadier.contains { (x: NightLayers.StageSpan) -> Bool in x.stage == s } ? s : nil
        }
        func rita(_ c: GraphicsContext, _ färg: Color, yta ytans: Double, linje linjens: Double) {
            let ton = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [färg.opacity(ytans), färg.opacity(0)]),
                startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: botten))
            for s in stycken where s.count > 1 {
                var yta = Path()
                yta.move(to: CGPoint(x: s[0].x, y: botten))
                for p in s { yta.addLine(to: p) }
                yta.addLine(to: CGPoint(x: s[s.count - 1].x, y: botten))
                yta.closeSubpath()
                c.fill(yta, with: ton)
                var linje = Path()
                linje.move(to: s[0])
                for p in s.dropFirst() { linje.addLine(to: p) }
                c.stroke(linje, with: .color(färg.opacity(linjens)),
                         style: StrokeStyle(lineWidth: NattRitning.pulslinje, lineCap: .round, lineJoin: .round))
            }
            // BESLUT B96 · BESLUT B98. Broarna över luckorna: samma yta under, och linjen i samma färg som den mätta
            // kurvan (B96 ritade den svagare).
            for b in broar {
                var yta = Path()
                yta.move(to: CGPoint(x: b.0.x, y: botten))
                yta.addLine(to: b.0)
                yta.addLine(to: b.1)
                yta.addLine(to: CGPoint(x: b.1.x, y: botten))
                yta.closeSubpath()
                c.fill(yta, with: ton)
                var linje = Path()
                linje.move(to: b.0)
                linje.addLine(to: b.1)
                c.stroke(linje, with: .color(färg.opacity(linjens)),
                         style: StrokeStyle(lineWidth: NattRitning.pulslinje, lineCap: .round, lineJoin: .round))
            }
        }
        if let s = färgad {
            rita(ctx, Tema.still, yta: 0.25, linje: 0.8)
            var klippt: GraphicsContext = ctx
            klippt.clip(to: NattRitning.stunder(stadier, s, t0: t0, t1: t1, bredd: bredd, höjd: botten)
                .offsetBy(dx: vä, dy: 0))
            rita(klippt, NattRitning.färg(s), yta: 0.45, linje: 1)
        } else {
            // BESLUT B95. Pulskurvan är blågrå, inte accentens blå.
            rita(ctx, Tema.pulse, yta: 0.35, linje: 1)
        }

        // BESLUT B98. Med en markerad minut står bara dess punkt på kurvan, inte lägsta pulsens ring.
        if vald == nil, let n = c.nadir {
            let px: CGFloat = x(n.time)
            let py: CGFloat = y(n.heartRate)
            let ring = Path(ellipseIn: CGRect(x: px - 4, y: py - 4, width: 8, height: 8))
            ctx.fill(ring, with: .color(Tema.bg))
            ctx.stroke(ring, with: .color(Color.white), lineWidth: 1.5)
            ctx.etikett("\(Int(n.heartRate.rounded()))", CGPoint(x: px, y: py + 15), storlek: 10, färg: Tema.text)
        }

        if !stadier.isEmpty {
            NattRitning.stadier(natten, spans: stadier, t0: t0, t1: t1, bredd: bredd, y: botten + 8, höjd: 14,
                                valt: färgad)
        }
        NattRitning.klockor(natten, t0: t0, t1: t1, bredd: bredd, y: H - 8, fem: axel, ändar: axel)

        // BESLUT B98. Den markerade minuten: ett streckat lodstreck genom kurvan och stadiebandet, och en punkt på kurvan.
        if let v = vald {
            let px: CGFloat = x(v.tid)
            let py: CGFloat = y(v.puls)
            var lod = Path()
            lod.move(to: CGPoint(x: px, y: 0))
            lod.addLine(to: CGPoint(x: px, y: botten + (stadier.isEmpty ? 0 : 22)))
            ctx.stroke(lod, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            let punkt = Path(ellipseIn: CGRect(x: px - 6, y: py - 6, width: 12, height: 12))
            ctx.fill(punkt, with: .color(Tema.pulse))
            ctx.stroke(punkt, with: .color(Tema.bg), lineWidth: 2)
        }
    }
}

/// Ett mått över natten på nattens tidsaxel (skissens `nightMetric`/`moveChart`): linje, staplar eller skuggade stunder, din
/// vanliga natt som band, och stadierna med klockslagen under. Glapp är tomma: linjen bryts där värdet saknas.
struct NattMatt: View {
    struct Punkt {
        var tid: TimeInterval
        var värde: Double?
    }

    struct Bandpunkt {
        var tid: TimeInterval
        var lägre: Double
        var övre: Double
    }

    let t0: TimeInterval
    let t1: TimeInterval
    let lo: Double
    let hi: Double
    let tal: [Double]
    let format: (Double) -> String
    var linje: [Punkt] = []
    var band: [Bandpunkt] = []
    /// Staplar per minut (rörelsen) med en streckad gräns.
    var staplar: [Punkt] = []
    var gräns: Double? = nil
    /// Stunder att skugga (rörelse under hudtemperaturen).
    var skuggor: [ClosedRange<TimeInterval>] = []
    var stadier: [NightLayers.StageSpan] = []
    /// Vilken tidsrymd en stapel eller en punkt täcker, sekunder.
    var bredd: TimeInterval = 60
    /// BESLUT B129 · METOD M75. Nattens mitt, som en svag streckad linje; `nil` ritar ingen.
    var mitt: TimeInterval? = nil

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            teckna(ctx, size)
        }
        .frame(height: 200)
        .accessibilityHidden(true)
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let top: CGFloat = 10
        let ch: CGFloat = 130
        guard t1 > t0, hi > lo else { return }
        let x = { (t: TimeInterval) -> CGFloat in CGFloat((t - t0) / (t1 - t0)) * W }
        let y = { (v: Double) -> CGFloat in top + ch - CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * ch }

        for s in skuggor {
            let a: CGFloat = x(s.lowerBound)
            let b: CGFloat = x(s.upperBound)
            ctx.fill(Path(CGRect(x: a, y: top, width: max(1, b - a), height: ch)), with: .color(Color.white.opacity(0.07)))
        }
        for v in tal {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y(v)))
            p.addLine(to: CGPoint(x: W, y: y(v)))
            ctx.stroke(p, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
            ctx.etikett(format(v), CGPoint(x: W - 4, y: y(v) - 7), ankare: .trailing)
        }
        if let m = mitt, m > t0, m < t1 {
            var p = Path()
            p.move(to: CGPoint(x: x(m), y: top))
            p.addLine(to: CGPoint(x: x(m), y: top + ch))
            ctx.stroke(p, with: .color(Color.white.opacity(0.16)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
        if band.count > 1 {
            var p = Path()
            for (i, b) in band.enumerated() {
                let pkt = CGPoint(x: x(b.tid), y: y(b.övre))
                if i == 0 { p.move(to: pkt) } else { p.addLine(to: pkt) }
            }
            for b in band.reversed() { p.addLine(to: CGPoint(x: x(b.tid), y: y(b.lägre))) }
            p.closeSubpath()
            ctx.fill(p, with: .color(Tema.band.opacity(0.55)))
        }
        if !staplar.isEmpty {
            let w: CGFloat = max(1, CGFloat(bredd / (t1 - t0)) * W)
            for s in staplar {
                guard let v = s.värde else { continue }
                let yy: CGFloat = y(v)
                let r = CGRect(x: x(s.tid), y: yy, width: w, height: max(0, top + ch - yy))
                let över: Bool = (gräns ?? Double.infinity) <= v
                ctx.fill(Path(r), with: .color(över ? Tema.accent : Tema.still))
            }
            if let g = gräns {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y(g)))
                p.addLine(to: CGPoint(x: W, y: y(g)))
                ctx.stroke(p, with: .color(Color.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ctx.etikett("gränsen", CGPoint(x: W - 4, y: y(g) - 6), ankare: .trailing, mono: false)
            }
        }
        if !linje.isEmpty {
            var p = Path()
            var pen = false
            var tidigare: TimeInterval? = nil
            for pt in linje {
                guard let v = pt.värde else {
                    pen = false
                    tidigare = nil
                    continue
                }
                // Ett glapp längre än tre punkter bryter linjen.
                if let f = tidigare, pt.tid - f > bredd * 3 { pen = false }
                let pkt = CGPoint(x: x(pt.tid), y: y(v))
                if pen { p.addLine(to: pkt) } else { p.move(to: pkt) }
                pen = true
                tidigare = pt.tid
            }
            ctx.stroke(p, with: .color(Tema.accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        NattRitning.stadier(ctx, spans: stadier, t0: t0, t1: t1, bredd: W, y: top + ch + 8, höjd: 12)
        NattRitning.klockor(ctx, t0: t0, t1: t1, bredd: W, y: H - 6, fem: false)
    }
}

/// Effektivitetens remsa: nattens period som en stapel, och de vakna stunderna som hack i den (BESLUT B89). Hacken
/// skärs ur stapeln (`destinationOut`), så kortets bakgrund syns igenom, och är minst 1,5 punkter breda så att ett
/// kort uppvaknande syns.
struct Effektivitetsrems: View {
    let period: ClosedRange<TimeInterval>?
    let vakna: [ClosedRange<TimeInterval>]

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let W: CGFloat = size.width
            let stapel: CGRect = CGRect(x: 0, y: 2, width: W, height: 12)
            ctx.drawLayer { (lager: inout GraphicsContext) in
                lager.fill(Path(roundedRect: stapel, cornerRadius: 3), with: .color(Tema.accent))
                guard let p = period, p.upperBound > p.lowerBound else { return }
                lager.blendMode = .destinationOut
                for v in vakna {
                    let a: CGFloat = CGFloat((v.lowerBound - p.lowerBound) / (p.upperBound - p.lowerBound)) * W
                    let b: CGFloat = CGFloat((v.upperBound - p.lowerBound) / (p.upperBound - p.lowerBound)) * W
                    let bredd: CGFloat = max(1.5, b - a)
                    lager.fill(Path(CGRect(x: a, y: stapel.minY, width: bredd, height: stapel.height)),
                               with: .color(.black))
                }
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

/// Regelbundenhet (skissens `consChart`): en stapel per natt från insomning till uppvaknande, och din vanliga insomning
/// och uppvaknande som två band. Tiderna är timmar efter midnatt dagen före.
struct Regeldiagram: View {
    struct Natt {
        var insomning: Double?
        var uppvaknande: Double?
        var etikett: String
    }

    let nätter: [Natt]
    let normalInsomning: ClosedRange<Double>?
    let normalUppvaknande: ClosedRange<Double>?

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            teckna(ctx, size)
        }
        .frame(height: 160)
        .accessibilityHidden(true)
    }

    private func teckna(_ ctx: GraphicsContext, _ size: CGSize) {
        let W: CGFloat = size.width
        let H: CGFloat = size.height
        let pt: CGFloat = 10
        let pb: CGFloat = 22
        let ih: CGFloat = H - pt - pb
        let lo: Double = 20
        let hi: Double = 33
        let y = { (v: Double) -> CGFloat in pt + CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * ih }
        let bredd: CGFloat = W - 40
        for b in [normalInsomning, normalUppvaknande] {
            if let b = b {
                ctx.fill(Path(CGRect(x: 0, y: y(b.lowerBound), width: bredd, height: max(1, y(b.upperBound) - y(b.lowerBound)))),
                         with: .color(Tema.band.opacity(0.6)))
            }
        }
        for v in [21.0, 24.0, 27.0, 30.0, 33.0] {
            ctx.etikett(Fmt.clock(hours: v), CGPoint(x: W - 36, y: y(v)), ankare: .leading)
        }
        guard !nätter.isEmpty else { return }
        let steg: CGFloat = bredd / CGFloat(nätter.count)
        for (i, n) in nätter.enumerated() {
            let cx: CGFloat = steg * CGFloat(i) + steg / 2
            let sist: Bool = i == nätter.count - 1
            if let a = n.insomning, let b = n.uppvaknande {
                let r = CGRect(x: cx - 8, y: y(a), width: 16, height: max(2, y(b) - y(a)))
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(sist ? Tema.accent : Tema.still))
            }
            ctx.etikett(n.etikett, CGPoint(x: cx, y: H - 8), färg: sist ? Tema.text : Tema.faint)
        }
    }
}

/// Sömnstressens kurva (spåret H): rutnät och linjerna vid 1 och 2; kurvan bara med huvudtal.
struct Stresskurva: View {
    let kurva: [Double]?

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let W: CGFloat = size.width
            let H: CGFloat = size.height
            let top: CGFloat = 8
            let ch: CGFloat = 96
            let y = { (v: Double) -> CGFloat in top + ch - CGFloat(min(max(v, 0), 3) / 3) * ch }
            for v in [1.0, 2.0] {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y(v)))
                p.addLine(to: CGPoint(x: W, y: y(v)))
                ctx.stroke(p, with: .color(Color.white.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            for v in [0.0, 1.0, 2.0, 3.0] {
                ctx.etikett("\(Int(v))", CGPoint(x: W - 4, y: y(v) - 7), ankare: .trailing)
            }
            if let k = kurva, k.count > 1 {
                for i in 1..<k.count {
                    let a = CGPoint(x: W * CGFloat(i - 1) / CGFloat(k.count - 1), y: y(k[i - 1]))
                    let b = CGPoint(x: W * CGFloat(i) / CGFloat(k.count - 1), y: y(k[i]))
                    var p = Path()
                    p.move(to: a)
                    p.addLine(to: b)
                    let c: Color = k[i] >= 2 ? Tema.red : (k[i] >= 1 ? Tema.yellow : Tema.accent)
                    ctx.stroke(p, with: .color(c), lineWidth: 1.8)
                }
            }
            _ = H
        }
        .frame(height: 130)
        .accessibilityHidden(true)
    }
}

/// En liten kurva i ett kort (Ikväll, Alla mått): tom och grå utan värden.
struct Minikurva: View {
    let värden: [Double?]?
    var färg: Color = Tema.accent
    var bredd: CGFloat = 90
    var höjd: CGFloat = 30

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let W: CGFloat = size.width
            let H: CGFloat = size.height
            let alla: [Double] = (värden ?? []).compactMap { (v: Double?) -> Double? in v }
            guard let lo = alla.min(), let hi = alla.max(), let v = värden, v.count > 1 else {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: H / 2))
                p.addLine(to: CGPoint(x: W, y: H / 2))
                ctx.stroke(p, with: .color(Tema.track), lineWidth: 1.5)
                return
            }
            var p = Path()
            var pen = false
            for (i, y) in v.enumerated() {
                guard let y = y else {
                    pen = false
                    continue
                }
                let d: Double = hi - lo > 0 ? (y - lo) / (hi - lo) : 0.5
                let pkt = CGPoint(x: W * CGFloat(i) / CGFloat(v.count - 1), y: H - 4 - CGFloat(d) * (H - 8))
                if pen { p.addLine(to: pkt) } else { p.move(to: pkt) }
                pen = true
            }
            ctx.stroke(p, with: .color(färg), lineWidth: 1.5)
        }
        .frame(width: bredd, height: höjd)
        .accessibilityHidden(true)
    }
}
