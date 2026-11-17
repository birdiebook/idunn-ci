import SwiftUI

/// BESLUT B136. Dra ner för att läsa om, i Idunns form: en pil som följer fingret och vänder när det räcker att
/// släppa, och sedan en ring som snurrar överst medan omläsningen pågår. Rullningen är en vanlig `ScrollView`;
/// utan `ladda` (förhandsvisningen) finns inget att dra i.
///
/// `laddar` är arbetet som pågår hos den som äger datan. Ringen står kvar minst `minst` sekunder, så att den hinner
/// synas, och högst `längst`: en hämtning från bandet kan ta minuter, och hur långt den kommit står på sidan.
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
    /// Radens höjd medan ringen snurrar.
    static var rad: CGFloat { 56 }
    static var minst: Double { 0.9 }
    static var längst: Double { 12 }

    /// Hur långt innehållet är draget under sin överkant (0 i vila).
    @State private var drag: CGFloat = 0
    @State private var fingret = false
    /// Fingret har dragit förbi tröskeln och inte tillbaka.
    @State private var nådd = false
    /// Ringen visas: från släppet tills omläsningen är klar.
    @State private var visar = false
    /// `laddar` som det är just nu, läsbart inifrån väntan.
    @State private var pågår = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if visar {
                    Snurra()
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.rad)
                        .transition(.opacity)
                }
                innehåll()
            }
        }
        .overlay(alignment: .top) {
            if ladda != nil, !visar, drag > 12 {
                pil
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
                try? await Task.sleep(for: .seconds(0.3))
                kvar -= 0.3
            }
            withAnimation(.easeInOut(duration: 0.3)) { visar = false }
        }
    }

    /// Pilen i luckan ovanför innehållet: tonar in med draget och vänder uppåt när det räcker att släppa.
    private var pil: some View {
        let andel: Double = Double(min(1, drag / Self.tröskel))
        return Image(systemName: "arrow.down")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(nådd ? Tema.text : Tema.dim)
            .rotationEffect(.degrees(nådd ? 180 : 0))
            .animation(.spring(duration: 0.25), value: nådd)
            .opacity(andel)
            .frame(height: 24)
            .offset(y: max(4, drag / 2 - 12))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// BESLUT B136. Ringen som snurrar medan Morgon läses om: en båge i Idunns accentfärg på ringarnas spår.
private struct Snurra: View {
    @State private var varv = false

    var body: some View {
        ZStack {
            Circle().stroke(Tema.ringTrack, lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Tema.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(varv ? 360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: varv)
        }
        .frame(width: 24, height: 24)
        .onAppear { varv = true }
        .accessibilityLabel("Läser om")
    }
}
