import SwiftUI
import WhoopImport

// BESLUT B40. Whoops nätter ur exporten är en lista på sidan Data (för
// jämförelsen med Idunn), inte en vy i vardagen. Filen hör till Data.

/// Whoops nätter ur exporten, senaste överst: återhämtning, HRV och vilopuls
/// (sidan Data).
struct NightList: View {
    let cycles: [Cycle]

    var body: some View {
        List {
            Section {
                ForEach(cycles.reversed(), id: \.start) { cycle in
                    NightRow(cycle: cycle)
                }
            } header: {
                Text("\(cycles.count) dygn")
            }
        }
    }
}

struct NightRow: View {
    let cycle: Cycle

    var body: some View {
        HStack(spacing: 14) {
            RecoveryRing(score: cycle.recoveryScore)
            VStack(alignment: .leading, spacing: 2) {
                Text((cycle.wakeOnset ?? cycle.start).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.headline)
                HStack(spacing: 12) {
                    Metric(value: cycle.hrv, unit: "ms", symbol: "waveform.path.ecg")
                    Metric(value: cycle.restingHeartRate, unit: "bpm", symbol: "heart")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct Metric: View {
    let value: Int?
    let unit: String
    let symbol: String

    var body: some View {
        Label(value.map { "\($0) \(unit)" } ?? "–", systemImage: symbol)
            .labelStyle(.titleAndIcon)
    }
}

/// Whoops tre band: grön från 67, gul 34–66, röd under.
struct RecoveryRing: View {
    let score: Int?

    private var color: Color {
        guard let s = score else { return .gray }
        return s >= 67 ? .green : s >= 34 ? .yellow : .red
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(score.map(String.init) ?? "–")
                .font(.system(.callout, design: .rounded).weight(.semibold))
        }
        .frame(width: 46, height: 46)
    }
}
