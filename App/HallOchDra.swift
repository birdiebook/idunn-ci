import SwiftUI
import Charts
import UIKit

/// BESLUT B49 · BESLUT B40
/// Håll, sedan dra: gesten i alla diagram med val (Nattens kurva och Över
/// tid). Ett svep över ett diagram rullar alltid sidan. Ett val av tid börjar
/// först när fingret hållits still en kort stund, och följer sedan fingret
/// tills det släpps; markeringen ligger kvar efteråt. Ett kort tryck öppnar en
/// natt (`öppna` får tidpunkten och svarar sant om den tog den), annars
/// markerar trycket tidpunkten. Bara diagrammets rityta, mellan axlarna, tar
/// emot fingret; rubriker, värden och axlarnas tal gör det aldrig.
extension View {
    func tryckMarkering(_ markerad: Binding<Date?>, öppna: @escaping (Date) -> Bool = { _ in false }) -> some View {
        modifier(HallOchDra(markerad: markerad, öppna: öppna))
    }

    /// BESLUT B99 · BESLUT B98. Nattens pulskurva (en `Canvas`): hela ytan tar emot fingret, och tiden räknas ur
    /// fingrets läge mellan `vänster` och `höger` kant av ytan, där natten börjar och slutar i ritningen. Punkten kommer
    /// efter `HallOchDra.pekTid`, följer fingret och försvinner när det släpps; ett kort tryck gör ingenting.
    func pekMarkering(_ markerad: Binding<Date?>, från t0: TimeInterval, till t1: TimeInterval,
                      vänster: CGFloat = 0, höger: CGFloat = 0) -> some View {
        overlay {
            GeometryReader { (geo: GeometryProxy) in
                let bredd: CGFloat = geo.size.width - vänster - höger
                Pekyta(storlek: geo.size, tid: { (x: CGFloat) -> Date? in
                    guard t1 > t0, bredd > 0 else { return nil }
                    let andel: Double = Double(min(max(x - vänster, 0), bredd) / bredd)
                    return Date(timeIntervalSince1970: t0 + andel * (t1 - t0))
                }, markerad: markerad, öppna: { (_: Date) -> Bool in true }, medanHåller: true)
            }
            .accessibilityHidden(true)
        }
    }
}

/// BESLUT B49. Gesten bärs av en genomskinlig yta exakt över diagrammets
/// rityta (`ChartProxy.plotFrame`), så att ytans egna punkter är ritytans och
/// `ChartProxy.value(atX:)` får dem som de är.
///
/// Hållet är UIKit:s långtryck (`UILongPressGestureRecognizer`) genom
/// `UIGestureRecognizerRepresentable`: det misslyckas om fingret rör sig mer
/// än `rörelse` innan `hållTid` gått, och då tar rullningens svep över. När
/// det väl börjat spårar det fingret och utesluter svepet. SwiftUI:s egen
/// LongPress följd av Drag tog svepet i en ScrollView. Bryggan är ingen vy,
/// så `ImageRenderer` ritar diagrammen som förut (ett UIKit-lager ritas som
/// en gul ruta, som periodväljaren i provets bilder).
struct HallOchDra: ViewModifier {
    let markerad: Binding<Date?>
    let öppna: (Date) -> Bool

    /// Hur länge fingret hålls still innan valet börjar (UIKit:s förval är 0,5 s).
    static let hållTid: TimeInterval = 0.3
    /// BESLUT B99. Nattens pulskurva: punkten kommer en kort stund efter trycket, och ett svep hinner ändå rulla sidan.
    static let pekTid: TimeInterval = 0.12
    /// Hur långt fingret får glida under tiden, i punkter (UIKit:s förval); längre är ett svep.
    static let rörelse: CGFloat = 10

    init(markerad: Binding<Date?>, öppna: @escaping (Date) -> Bool) {
        self.markerad = markerad
        self.öppna = öppna
    }

    func body(content: Content) -> some View {
        content.chartOverlay(alignment: .topLeading) { (proxy: ChartProxy) in
            GeometryReader { (geo: GeometryProxy) in
                if let plot: Anchor<CGRect> = proxy.plotFrame {
                    let ram: CGRect = geo[plot]
                    // Fingret utanför ritytan (under ett drag) ger tiden vid kanten.
                    Pekyta(storlek: ram.size, tid: { (x: CGFloat) -> Date? in
                        proxy.value(atX: min(max(x, 0), ram.width), as: Date.self)
                    }, markerad: markerad, öppna: öppna)
                    .position(x: ram.midX, y: ram.midY)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// BESLUT B49. Den genomskinliga ytan med hållet och trycket, i ytans egna punkter; `tid` gör fingrets x till en
/// tidpunkt. Trycket läggs bredvid hållet (`simultaneousGesture`), så att inget av dem väntar på det andra; att ett
/// håll aldrig blir ett tryck sköter `minne`.
private struct Pekyta: View {
    let storlek: CGSize
    let tid: (CGFloat) -> Date?
    let markerad: Binding<Date?>
    let öppna: (Date) -> Bool
    /// BESLUT B99. Markeringen finns bara medan fingret håller (Nattens pulskurva): hållet börjar efter
    /// `HallOchDra.pekTid`, släppet tar bort markeringen och ett kort tryck gör ingenting.
    let medanHåller: Bool
    @State private var minne = Hållminne()

    /// Uttrycklig, för `@State private var minne` gör den automatiska initieraren privat, och den nås då inte från
    /// `HallOchDra` eller `pekMarkering(_:från:till:)`. Namnet är inte Tryckyta: det heter knappstilen i Tema.swift,
    /// och krocken fällde två TestFlight-byggen 2026-11-10 (vakten: tools/tests/test_typnamn.py).
    init(storlek: CGSize, tid: @escaping (CGFloat) -> Date?, markerad: Binding<Date?>,
         öppna: @escaping (Date) -> Bool, medanHåller: Bool = false) {
        self.storlek = storlek
        self.tid = tid
        self.markerad = markerad
        self.öppna = öppna
        self.medanHåller = medanHåller
    }

    var body: some View {
        Color.clear
            .frame(width: storlek.width, height: storlek.height)
            .contentShape(Rectangle())
            .gesture(Långtryck(
                hållTid: medanHåller ? HallOchDra.pekTid : HallOchDra.hållTid,
                följ: { (x: CGFloat) in
                    minne.håller = true
                    if let t = tid(x) { markerad.wrappedValue = t }
                },
                släpp: {
                    if minne.håller { minne.släppt = Date() }
                    minne.håller = false
                    if medanHåller { markerad.wrappedValue = nil }
                }))
            .simultaneousGesture(SpatialTapGesture().onEnded { (e: SpatialTapGesture.Value) in
                // Ett håll i samma beröring är inget tryck, vilken av dem som
                // än hörs först när fingret lyfts: pågår hållet räknas trycket
                // inte (och hållet glöms, om dess slut aldrig kom), och strax
                // efter ett släppt håll inte heller.
                if minne.håller {
                    minne.håller = false
                    return
                }
                if Date().timeIntervalSince(minne.släppt) < HallOchDra.hållTid { return }
                guard let t = tid(e.location.x) else { return }
                if öppna(t) { return }
                markerad.wrappedValue = t
            }, including: medanHåller ? .none : .all)
    }
}

/// Om ett håll pågår och när det senaste släpptes. En klass, så att en ändring
/// inte ritar om diagrammet.
final class Hållminne {
    var håller = false
    var släppt = Date.distantPast
}

/// BESLUT B49. UIKit:s långtryck i SwiftUI. `följ` får fingrets läge i ytans
/// egna punkter (från ritytans vänstra kant) när hållet börjar och när fingret
/// flyttas; `släpp` när fingret lyfts eller gesten avbryts.
private struct Långtryck: UIGestureRecognizerRepresentable {
    let hållTid: TimeInterval
    let följ: (CGFloat) -> Void
    let släpp: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = hållTid
        g.allowableMovement = HallOchDra.rörelse
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            följ(context.converter.location(in: .local).x)
        case .ended, .cancelled, .failed:
            släpp()
        default:
            break
        }
    }
}
