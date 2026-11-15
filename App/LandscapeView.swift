import SwiftUI
import Night

/// METOD M22 · BESLUT B24
/// Nattlandskapet: de senaste nätternas puls som åsar på väggklockan, den
/// nyaste längst fram (nederst), så att den aldrig skyms och tiden går mot
/// betraktaren. Varje ås fylls med kortets yta och skymmer åsarna bakom; det är
/// det som gör staplarna till ett landskap. En kulör, tunna linjer. Ett tryck
/// väljer en natt: dess linje blir tjockare och datum, vilopuls och HRV står
/// överst. Räkningen ligger i IdunnKit (`NightLandscape`).
struct LandscapeView: View {
    @EnvironmentObject private var recorder: Recorder
    @State private var vald: Int?

    var body: some View {
        Group {
            if let s = NightLandscape.scene(NightSummary.preferred(recorder.summaries).compactMap(\.landscapeNight)) {
                ScrollView {
                    LandscapeStack(scene: s, vald: $vald)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                ContentUnavailableView("Inga nätter än", systemImage: "mountain.2")
            }
        }
        .navigationTitle("Landskap")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension NightSummary {
    /// METOD M22. Natten som landskapet ser den.
    var landscapeNight: NightLandscape.Night? {
        end.map {
            NightLandscape.Night(end: $0, utcOffsetSeconds: utcOffsetSeconds, validWindows: validWindows,
                                 restingHeartRate: restingHeartRate, rmssd: rmssdMean, profile: landscape)
        }
    }
}

/// Avläsningen och landskapet utan rullning, så att `ImageRenderer` kan rita
/// dem (IdunnProv).
struct LandscapeStack: View {
    let scene: NightLandscape.Scene
    @Binding var vald: Int?

    /// Den valda natten, annars den nyaste.
    private var visad: Int { min(vald ?? scene.ridges.count - 1, scene.ridges.count - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LandscapeReading(night: scene.ridges[visad])
            Ridges(scene: scene, visad: visad, vald: $vald)
                .frame(height: Ridges.height(count: scene.ridges.count))
                .padding(12)
                .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }
}

/// Den visade nattens datum, vilopuls och HRV.
private struct LandscapeReading: View {
    let night: NightLandscape.Night

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(night.end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.headline)
            Spacer(minLength: 4)
            värde(night.restingHeartRate, enhet: "bpm", symbol: "heart", namn: "Vilopuls")
            värde(night.rmssd, enhet: "ms", symbol: "waveform.path.ecg", namn: "HRV")
        }
        .padding(12)
        .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func värde(_ x: Double?, enhet: String, symbol: String, namn: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(x.map { "\(Int($0.rounded()))" } ?? "–").font(.title3.weight(.semibold))
            Text(enhet).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(namn)
    }
}

/// METOD M22. Åsarna i en Canvas: hårfina timlinjer bakom, sedan åsarna
/// bakifrån och fram, var och en fylld med ytan och dragen med en tunn linje.
/// Till vänster pulsens skala, till höger datum för den äldsta, den nyaste och
/// den visade natten, under klockslagen var tredje timme.
private struct Ridges: View {
    let scene: NightLandscape.Scene
    let visad: Int
    @Binding var vald: Int?

    static let vänster: CGFloat = 26
    static let höger: CGFloat = 44
    static let under: CGFloat = 18
    static let radavstånd: CGFloat = 13

    static func height(count: Int) -> CGFloat {
        radavstånd * CGFloat(max(0, count - 1)) + radavstånd * CGFloat(NightLandscape.overlap) + under
    }

    private func layout(_ size: CGSize) -> NightLandscape.Layout {
        NightLandscape.Layout(width: Double(max(1, size.width - Self.vänster - Self.höger)),
                              height: Double(max(1, size.height - Self.under)), scene: scene)
    }

    var body: some View {
        GeometryReader { geo in
            let l = layout(geo.size)
            Canvas { ctx, size in
                rita(&ctx, size: size, l: l)
            }
            .contentShape(Rectangle())
            .onTapGesture { p in
                vald = l.hit(x: Double(p.x - Self.vänster), y: Double(p.y), scene: scene)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Nattlandskap, \(scene.ridges.count) nätter")
        .accessibilityValue(scene.ridges[visad].end.formatted(.dateTime.day().month(.abbreviated)))
        .accessibilityAdjustableAction { riktning in
            switch riktning {
            case .increment: vald = min(scene.ridges.count - 1, visad + 1)
            case .decrement: vald = max(0, visad - 1)
            @unknown default: break
            }
        }
    }

    private func rita(_ ctx: inout GraphicsContext, size: CGSize, l: NightLandscape.Layout) {
        let x0: CGFloat = Self.vänster
        let linje = Color.secondary.opacity(0.25)

        // Timlinjerna och klockslagen var tredje timme.
        var h: Int = scene.bins.lowerBound
        while h <= scene.bins.upperBound {
            let x: CGFloat = x0 + CGFloat(l.x(bin: Double(h) - 0.5))
            let klocka: Int = NightLandscape.Scene.clockMinutes(bin: h)
            var p = Path()
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: CGFloat(l.height)))
            ctx.stroke(p, with: .color(linje), lineWidth: 0.5)
            if klocka % 180 == 0 {
                let text = Text(String(format: "%02d", klocka / 60)).font(.caption2).foregroundColor(.secondary)
                ctx.draw(text, at: CGPoint(x: x, y: size.height - Self.under / 2), anchor: .center)
            }
            h += NightLandscape.binsPerHour
        }

        // Åsarna, bakifrån och fram.
        for i in scene.ridges.indices {
            guard let profil = scene.ridges[i].profile else { continue }
            let bas: CGFloat = CGFloat(l.baseline(i))
            for del in delar(profil) {
                let punkter: [CGPoint] = del.map { (e: (Int, Double)) -> CGPoint in
                    CGPoint(x: x0 + CGFloat(l.x(bin: Double(e.0))), y: CGFloat(l.y(i, heartRate: e.1)))
                }
                guard let först = punkter.first, let sist = punkter.last else { continue }
                var kurva = Path()
                kurva.addLines(punkter)
                var yta = kurva
                yta.addLine(to: CGPoint(x: sist.x, y: bas))
                yta.addLine(to: CGPoint(x: först.x, y: bas))
                yta.closeSubpath()
                ctx.fill(yta, with: .color(TrendColor.surface))
                let visas = i == visad
                ctx.stroke(kurva, with: .color(TrendColor.idun.opacity(visas ? 1 : 0.55)),
                           style: StrokeStyle(lineWidth: visas ? 2 : 1, lineCap: .round, lineJoin: .round))
            }
        }

        // Pulsens skala vid den främsta åsen: ett hårfint streck från lägsta
        // till högsta puls.
        let främst: Int = scene.ridges.count - 1
        let lo: CGFloat = CGFloat(l.y(främst, heartRate: scene.heartRate.lowerBound))
        let hi: CGFloat = CGFloat(l.y(främst, heartRate: scene.heartRate.upperBound))
        var skala = Path()
        skala.move(to: CGPoint(x: x0 - 6, y: lo))
        skala.addLine(to: CGPoint(x: x0 - 6, y: hi))
        ctx.stroke(skala, with: .color(.secondary), lineWidth: 1)
        for (y, v) in [(lo, scene.heartRate.lowerBound), (hi, scene.heartRate.upperBound)] {
            let t = Text("\(Int(v))").font(.caption2).foregroundColor(.secondary)
            ctx.draw(t, at: CGPoint(x: x0 - 9, y: y), anchor: .trailing)
        }

        // Datum vid baslinjen: den äldsta, den nyaste och den visade.
        let xd: CGFloat = size.width - Self.höger + 4
        for i in Set([0, främst, visad]).sorted() {
            let d = scene.ridges[i].end.formatted(.dateTime.day().month(.abbreviated))
            let t = Text(d).font(.caption2).foregroundColor(i == visad ? Color.primary : Color.secondary)
            ctx.draw(t, at: CGPoint(x: xd, y: CGFloat(l.baseline(i))), anchor: .leading)
        }
    }

    /// Profilens obrutna delar: steg i följd med puls. En ensam punkt ritas inte.
    private func delar(_ p: NightLandscape.Profile) -> [[(Int, Double)]] {
        var ut: [[(Int, Double)]] = []
        var del: [(Int, Double)] = []
        for (k, v) in p.heartRate.enumerated() {
            if let v {
                del.append((p.firstBin + k, v))
            } else {
                if del.count > 1 { ut.append(del) }
                del = []
            }
        }
        if del.count > 1 { ut.append(del) }
        return ut
    }
}
