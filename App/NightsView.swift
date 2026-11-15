import SwiftUI
import Night

/// BESLUT B40 · METOD M28
/// Listan över Idunns egna nätter, en per uppvakningsdag, senaste överst: en
/// rad på sidan Data, för kontroll. Natten är sömnperioden ur bandets rörelse
/// (METOD M26), med slagen ur bandets historik; en gammal inspelning visas
/// bara de dagar K18 saknas. Ett tryck öppnar nattens kurva, och därifrån
/// Poincarémolnet. Vardagen når en natt genom pilarna och svepet på Morgon och
/// genom ett tryck i trendvyn (BESLUT B82).
struct NightsList: View {
    let summaries: [NightSummary]

    private var nätter: [NightSummary] { NightSummary.preferred(summaries) }

    var body: some View {
        Group {
            if nätter.isEmpty {
                ContentUnavailableView("Ingen natt än", systemImage: "moon.stars")
            } else {
                List {
                    Section {
                        ForEach(nätter) { s in
                            NavigationLink {
                                NightCurveView(summary: s)
                            } label: {
                                IdunNightRow(summary: s)
                            }
                        }
                    } header: {
                        Text("\(nätter.count) nätter")
                    }
                }
            }
        }
        .navigationTitle("Nätter")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// En natt i listan: uppvakningsdagen, sömntiden, och HRV och vilopuls kort.
struct IdunNightRow: View {
    let summary: NightSummary

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text((summary.titleDate ?? .now)
                        .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.headline)
                    if summary.preliminary == true {
                        Text("preliminär")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Label(Self.sleepText(summary), systemImage: "bed.double")
                    Label(Self.number(summary.rmssdMean, "ms"), systemImage: "waveform.path.ecg")
                    Label(Self.number(summary.restingHeartRate, "bpm"), systemImage: "heart")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Sömntiden som "7 h 12 min"; en gammal inspelning har ingen sömnperiod
    /// och visar tiden mellan första och sista notisen.
    static func sleepText(_ s: NightSummary) -> String {
        var sekunder: Double?
        if let m = s.sleepMinutes {
            sekunder = m * 60
        } else if let a = s.start, let b = s.end {
            sekunder = b.timeIntervalSince(a)
        }
        guard let sek = sekunder else { return "–" }
        return Duration.seconds(sek).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    static func number(_ x: Double?, _ enhet: String) -> String {
        x.map { "\(Int($0.rounded())) \(enhet)" } ?? "–"
    }
}
