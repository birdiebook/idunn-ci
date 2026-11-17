import SwiftUI

/// BESLUT B136 · BESLUT B140. Dra ner för att läsa om, i Idunns form: en kula som andas in medan fingret drar och
/// fylls när det räcker att släppa, och som andas ut i tre ringar efter släppet. Rullningen är en vanlig `ScrollView`;
/// utan `ladda` (förhandsvisningen) finns inget att dra i.
///
/// `laddar` är arbetet som pågår hos den som äger datan. Utandningen är en kort kvittens på draget (BESLUT B139):
/// minst `minst` sekunder, så att den hinner andas ut, och högst `längst`. En hämtning från bandet kan ta minuter, och
/// hur långt den kommit står på sidan, inte i kulan.
struct DraNer<Innehåll: View>: View {
    let laddar: Bool
    let ladda: (() -> Void)?
    let innehåll: () -> Innehåll

    init(laddar: Bool, ladda: (() -> Void)?, @ViewBuilder innehåll: @escaping () -> Innehåll) {
        self.laddar = laddar
        self.ladda = ladda
        self.innehåll = innehåll
    }

    /// Hur långt sidan måste dras för att släppet ska läsa om, i punkter.
    static var tröskel: CGFloat { 76 }
    /// Luckans höjd medan kulan andas ut.
    static var rad: CGFloat { 64 }
    // BESLUT B139 · BESLUT B140. Kort: minst en utandning (`Andning.utandning`), högst 1,5 s.
    static var minst: Double { Andning.utandning }
    static var längst: Double { 1.5 }

    /// Hur långt innehållet är draget under sin överkant (0 i vila).
    @State private var drag: CGFloat = 0
    @State private var fingret = false
    /// Fingret har dragit förbi tröskeln och inte tillbaka.
    @State private var nådd = false
    /// Utandningen visas: från släppet tills kvittensen är slut.
    @State private var visar = false
    /// När utandningen började.
    @State private var släppt = Date.distantPast
    /// `laddar` som det är just nu, läsbart inifrån väntan.
    @State private var pågår = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if visar {
                    Color.clear
                        .frame(height: Self.rad)
                        .transition(.opacity)
                }
                innehåll()
            }
        }
        .overlay(alignment: .top) {
            if ladda != nil, visar || drag > 2 {
                luckan
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { (g: ScrollGeometry) -> CGFloat in
            -(g.contentOffset.y + g.contentInsets.top)
        } action: { (_: CGFloat, ny: CGFloat) -> Void in
            drag = max(0, ny)
            if fingret { nådd = drag >= Self.tröskel }
        }
        .onScrollPhaseChange { (förr: ScrollPhase, nu: ScrollPhase) -> Void in
            fingret = nu == .interacting
            if förr == .interacting, nu != .interacting {
                if nådd, !visar, let ladda {
                    släppt = Date()
                    withAnimation(.easeOut(duration: 0.2)) { visar = true }
                    ladda()
                }
                nådd = false
            }
        }
        .onChange(of: laddar, initial: true) { (_: Bool, ny: Bool) -> Void in pågår = ny }
        .sensoryFeedback(.impact(weight: .light), trigger: nådd) { (_: Bool, ny: Bool) -> Bool in ny }
        .task(id: visar) {
            guard visar else { return }
            try? await Task.sleep(for: .seconds(Self.minst))
            var kvar: Double = Self.längst - Self.minst
            while pågår, kvar > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.1))
                kvar -= 0.1
            }
            withAnimation(.easeInOut(duration: 0.25)) { visar = false }
        }
    }

    /// Luckan ovanför innehållet: inandningen följer draget, utandningen sin klocka.
    @ViewBuilder
    private var luckan: some View {
        if visar {
            TimelineView(.animation) { tid in
                let fas: Double = min(1, max(0, tid.date.timeIntervalSince(släppt) / Andning.utandning))
                Andning(andel: 1, ut: fas)
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(Self.rad, drag))
            .clipped()
            .allowsHitTesting(false)
            .accessibilityLabel("Läser om")
        } else {
            Andning(andel: Double(min(1, drag / Self.tröskel)), ut: nil)
                .frame(maxWidth: .infinity)
                .frame(height: drag)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// BESLUT B140. Kulan som andas: in medan fingret drar (`andel` 0–1), ut efter släppet (`ut` 0–1), med tre ringar som
/// vågar ut. Mitt i luckan, i Idunns accentfärg.
struct Andning: View {
    let andel: Double
    let ut: Double?

    /// Utandningens längd i sekunder.
    static var utandning: Double { 1.1 }

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            let mitt: CGPoint = CGPoint(x: size.width / 2, y: size.height / 2)
            let e: Double = 1 - pow(1 - min(1, max(0, andel)), 3)
            var r: Double = 4 + 20 * e
            if let fas = ut {
                r = 24 + 8 * sin(fas * .pi) - 10 * fas * fas
                for k in 0..<3 {
                    let p: Double = min(1, max(0, fas * 1.4 - Double(k) * 0.18))
                    guard p > 0 else { continue }
                    let rr: Double = 24 + p * 46
                    ctx.stroke(Path(ellipseIn: CGRect(x: mitt.x - rr, y: mitt.y - rr, width: 2 * rr, height: 2 * rr)),
                               with: .color(Tema.accent.opacity(0.35 * (1 - p))), lineWidth: 1.2)
                }
            }
            let sken: Double = r * 1.8
            ctx.fill(Path(ellipseIn: CGRect(x: mitt.x - sken, y: mitt.y - sken, width: 2 * sken, height: 2 * sken)),
                     with: .radialGradient(Gradient(colors: [Tema.accent.opacity(0.55), Tema.accent.opacity(0.18),
                                                             Tema.accent.opacity(0)]),
                                           center: mitt, startRadius: 0, endRadius: sken))
            let kärna: Double = max(2, r * 0.42)
            let full: Bool = andel >= 1 || ut != nil
            ctx.fill(Path(ellipseIn: CGRect(x: mitt.x - kärna, y: mitt.y - kärna, width: 2 * kärna, height: 2 * kärna)),
                     with: .color(Tema.accent.opacity(full ? 0.95 : 0.55)))
        }
    }
}
