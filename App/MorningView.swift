import SwiftUI
import Night
import WhoopImport

/// METOD M14 · METOD M25 · BESLUT B8 · BESLUT B3 · BESLUT B40
/// Idunn mot Whoop (sidan Data): följer Idunn Whoop natt för natt? Idunns nätter
/// och den importerade exporten paras på uppvakningsdagen, och bara de samlade
/// talen visas — antal nätter, rangkorrelation (ρ), medelavvikelse (±) och
/// medelskillnad (Δ, Idunn − Whoop; nivåskillnaden, kalibreringen) — så att en
/// skärmbild kan skickas vidare. Här, och bara här, möts de två källorna.
struct MorningView: View {
    let summaries: [NightSummary]
    let cycles: [Cycle]
    /// METOD M26. Whoops sömnpass, för sömnjämförelsen (R4). Tom = ingen jämförelse.
    var sleeps: [Sleep] = []

    /// METOD M14. En inspelning med färre giltiga 5-minutersfönster än så
    /// (3 timmar) är ett prov, ingen natt, och jämförs inte.
    static let minValidWindows = Trends.minValidWindows

    /// METOD M14 · METOD M28. En natt per uppvakningsdag: K18 före en gammal
    /// inspelning, och bland flera från samma källa den med flest giltiga fönster.
    private var nights: [WakeDay: Trends.IdunNight] {
        let alla: [Trends.IdunNight] = summaries.compactMap { (s: NightSummary) -> Trends.IdunNight? in s.idunNight }
        return Trends.idunPerDay(alla)
    }

    private func idun(_ v: (Trends.IdunNight) -> Double?) -> [WakeDay: Double] {
        nights.compactMapValues(v)
    }

    private func whoop(_ v: (Cycle) -> Double?) -> [WakeDay: Double] {
        WhoopReference.byWakeDay(cycles, v)
    }

    private var hrv: Comparison.Summary {
        Comparison.summary(idun: idun { $0.rmssd }, whoop: whoop { c in c.hrv.map { Double($0) } })
    }
    private var hrvWhoopLike: Comparison.Summary {
        Comparison.summary(idun: idun { $0.rmssdWhoopLike }, whoop: whoop { c in c.hrv.map { Double($0) } })
    }
    private var restingHeartRate: Comparison.Summary {
        Comparison.summary(idun: idun { $0.restingHeartRate }, whoop: whoop { c in c.restingHeartRate.map { Double($0) } })
    }
    private var breathing: Comparison.Summary {
        Comparison.summary(idun: idun { $0.breathsPerMinute }, whoop: whoop { c in c.respiratoryRate })
    }
    /// METOD M25. Hudtemperaturen i °C: Δ är nivåskillnaden Idunn − Whoop.
    private var skinTemperature: Comparison.Summary {
        Comparison.summary(idun: idun { $0.skinTemperature }, whoop: whoop { c in c.skinTempCelsius })
    }

    /// METOD M26. Idunns sömnperiod mot Whoops pass, natt för natt.
    private var sleep: SleepComparison.Summary {
        let perioder: [SleepComparison.NightSleep] = NightSummary.preferred(summaries)
            .compactMap { (s: NightSummary) -> SleepComparison.NightSleep? in s.sleepPeriod }
        return SleepComparison.summary(nights: perioder, whoop: sleeps)
    }

    var body: some View {
        List {
            Section {
                ComparisonRow(symbol: "waveform.path.ecg", title: "HRV", summary: hrv)
                ComparisonRow(symbol: "waveform.path.ecg", title: "HRV, Whoop-lik", summary: hrvWhoopLike)
                ComparisonRow(symbol: "heart", title: "Vilopuls", summary: restingHeartRate)
                ComparisonRow(symbol: "lungs", title: "Andning", summary: breathing)
                ComparisonRow(symbol: "thermometer.medium", title: "Hudtemp, °C", summary: skinTemperature)
            } header: {
                Label("Idunn mot Whoop", systemImage: "sunrise")
            }

            Section {
                SleepComparisonRows(summary: sleep)
            } header: {
                Label("Sömn, minuter", systemImage: "bed.double")
            } footer: {
                Text("Idunn minus Whoop. Plus = Idunn senare (insomning, uppvaknande) eller mer sömn.")
            }
        }
        .navigationTitle("Idunn mot Whoop")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// METOD M26 · METOD M14 · BESLUT B3. Sömnperioden mot Whoops pass: insomning,
/// uppvaknande och sömntid, med antal nätter, medelavvikelse (±) och
/// medelskillnad (Δ) i minuter. Färre än tre nätter visas inte (som M14).
private struct SleepComparisonRows: View {
    let summary: SleepComparison.Summary

    var body: some View {
        if summary.isEnough {
            row("Insomning", summary.onset)
            row("Uppvaknande", summary.wake)
            row("Sömntid", summary.sleep)
        } else {
            Label("\(summary.nights) av \(Comparison.minNights) nätter", systemImage: "moon")
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ m: SleepComparison.Measure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            HStack(spacing: 16) {
                Label("\(m.nights)", systemImage: "moon")
                Label(tal(m.meanAbsoluteDeviation), systemImage: "plusminus")
                Text("Δ \(tal(m.meanDifference, tecken: true))")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
    }

    private func tal(_ x: Double?, tecken: Bool = false) -> String {
        guard let x else { return "–" }
        let s = String(format: "%.1f", x)
        return tecken && x > 0 ? "+" + s : s
    }
}

private struct ComparisonRow: View {
    let symbol: String
    let title: String
    let summary: Comparison.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            HStack(spacing: 16) {
                Label("\(summary.nights)", systemImage: "moon")
                Text("ρ \(tal(summary.spearman))")
                Label(tal(summary.meanAbsoluteDeviation), systemImage: "plusminus")
                Text("Δ \(tal(summary.meanDifference, tecken: true))")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            // En rad: ett brett tal bröts mitt i (provet 2026-10-12, "30.7 / 6").
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 2)
    }

    private func tal(_ x: Double?, tecken: Bool = false) -> String {
        guard let x else { return "–" }
        let s = String(format: "%.2f", x)
        return tecken && x > 0 ? "+" + s : s
    }
}
