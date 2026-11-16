import SwiftUI
import Pass
import SleepNeed

/// BESLUT B126 · METOD M72
/// Veckan i fliken Pass: tid, sträcka och belastning hittills i veckan mot snittet för de fyra veckorna före.
enum PassVecka {
    /// Översikten för veckan `idag` ligger i. Utan maxpuls räknas ingen belastning och inga zoner.
    static func oversikt(_ pass: [Pass], maxpuls: Double?, idag: Int = KonditionModell.idag()) -> PassWeek.Overview {
        let klass: ((Int) -> Int)? = maxpuls.map { (m: Double) -> ((Int) -> Int) in
            { (bpm: Int) -> Int in PassLoad.zone(bpm: bpm, maxPulse: m) }
        }
        return PassWeek.overview(pass, day: idag,
                                 dayOf: { (p: Pass) -> Int in KonditionModell.dag(för: p) },
                                 load: { (p: Pass) -> Double in
                                     maxpuls.map { (m: Double) -> Double in PassLoad.load(p, maxPulse: m) } ?? 0
                                 },
                                 classify: klass)
    }

    static func snitt(_ text: String) -> String { "snitt " + text }
}

/// Kortet "Den här veckan": stora tal med snittet under, tid per pulszon och fem staplar med veckornas tid.
struct VeckaKort: View {
    let oversikt: PassWeek.Overview
    let harMaxpuls: Bool

    private static let högstStapel: CGFloat = 56
    private static let lägstStapel: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Den här veckan").font(.headline)
                Spacer()
                Text("\(oversikt.current.passes) pass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                stort(PassFormat.short(oversikt.current.seconds), "tid",
                      PassVecka.snitt(PassFormat.short(oversikt.averageSeconds)))
                if oversikt.current.meters > 0 || oversikt.averageMeters > 0 {
                    stort(PassRuttFormat.km(oversikt.current.meters), "sträcka",
                          PassVecka.snitt(PassRuttFormat.km(oversikt.averageMeters)))
                }
                if harMaxpuls {
                    stort(String(Int(oversikt.current.load.rounded())), "belastning",
                          PassVecka.snitt(String(Int(oversikt.averageLoad.rounded()))))
                }
            }
            Text("Snittet är de fyra veckorna före.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if harMaxpuls && !oversikt.current.zones.isEmpty {
                Text("Tid per pulszon").font(.subheadline.weight(.semibold))
                ZonRader(zoner: oversikt.current.zones)
            }
            Text("Tid per vecka").font(.subheadline.weight(.semibold))
            staplar
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stort(_ värde: String, _ etikett: String, _ snitt: String) -> some View {
        VStack(spacing: 2) {
            Text(värde)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(etikett).font(.caption).foregroundStyle(.secondary)
            Text(snitt)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var staplar: some View {
        let veckor: [PassWeek.Summary] = oversikt.previous + [oversikt.current]
        let störst: TimeInterval = max(1, veckor.map { (w: PassWeek.Summary) -> TimeInterval in w.seconds }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(veckor.enumerated()), id: \.offset) { (e: (offset: Int, element: PassWeek.Summary)) in
                let i: Int = e.offset
                let w: PassWeek.Summary = e.element
                let sista: Bool = i == veckor.count - 1
                let höjd: CGFloat = max(Self.lägstStapel, Self.högstStapel * CGFloat(w.seconds / störst))
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(sista ? Tema.accent : Color.secondary.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: höjd)
                    Text(w.seconds > 0 ? PassFormat.short(w.seconds) : "–")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(sista ? "nu" : " ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tid per vecka, de fyra veckorna före och den här")
    }
}
