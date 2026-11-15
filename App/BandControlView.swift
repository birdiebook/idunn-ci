import SwiftUI
import WhoopFrames

/// BESLUT B25 · METOD M23 · BESLUT B3 · BESLUT B53 · METOD M43
/// Bandkontroll (en rad på sidan Data): en knapp som hämtar bandets historik
/// och kvitterar den. Aldrig automatiskt. Visar bara antal och tider — bitar,
/// K18-sekunder och tidsspannet — aldrig ett värde ur posterna. Under den
/// IMU-provet: rörelse i 100 Hz en begränsad stund, med märken för provets
/// delar; bara antal, tid och bandets svar visas.
struct BandControlView: View {
    @EnvironmentObject private var recorder: Recorder
    @State private var confirming = false
    @State private var confirmingImu = false

    var body: some View {
        List {
            Section {
                Button {
                    confirming = true
                } label: {
                    Label("Hämta historik från bandet", systemImage: "arrow.down.circle")
                }
                .disabled(recorder.fetching || recorder.imuPhase != .off)
            } footer: {
                Text("Kör direkt efter en Whoop-synk — det som hämtas här får Whoop inte.")
            }

            Section {
                Label("Stäng Whoop-appen först (svep bort den). Annars kvitterar båda.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            if recorder.fetching || recorder.fetchOutcome != nil {
                Section {
                    FetchStatus(state: recorder.fetchState, progress: recorder.fetchProgress,
                                outcome: recorder.fetchOutcome)
                }
            }

            // BESLUT B53 · METOD M43. IMU-provet.
            Section {
                if recorder.imuPhase == .off {
                    Button {
                        confirmingImu = true
                    } label: {
                        Label("Starta IMU-prov", systemImage: "gyroscope")
                    }
                    .disabled(recorder.fetching)
                } else {
                    Button(role: .destructive) {
                        recorder.stopImu()
                    } label: {
                        Label("Stoppa", systemImage: "stop.circle")
                    }
                    .disabled(!ImuStatus.running(recorder.imuPhase))
                }
                if recorder.imuPhase != .off || recorder.imuProgress.startedAt != nil
                    || recorder.imuFailsafeStops > 0 {
                    ImuStatus(phase: recorder.imuPhase, progress: recorder.imuProgress,
                              failsafeStops: recorder.imuFailsafeStops)
                }
                if ImuStatus.running(recorder.imuPhase) {
                    ImuMarks(last: recorder.lastMarker?.label, count: recorder.markerCount) { recorder.mark($0) }
                }
            } header: {
                Label("IMU-prov", systemImage: "gyroscope")
            } footer: {
                Text("Stannar efter \(Int(ImuControl.Config().hardTimeout / 60)) min.")
            }
        }
        .navigationTitle("Bandkontroll")
        .confirmationDialog("Starta IMU-prov?", isPresented: $confirmingImu, titleVisibility: .visible) {
            Button("Starta") { recorder.startImu() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Bandet skickar rörelse 100 gånger i sekunden. Det drar batteri, och historiken väntar så länge.")
        }
        .confirmationDialog("Hämta och kvittera?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Hämta") { recorder.startFetch() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Bandet glömmer det som kvitteras.")
        }
    }
}

/// Hur långt hämtningen kommit, i antal, och hur den slutade.
private struct FetchStatus: View {
    let state: HistorySession.State?
    let progress: HistorySession.Progress
    let outcome: HistorySession.Outcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if outcome == nil { ProgressView() }
                Text(rubrik).font(.headline)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Bitar").foregroundStyle(.secondary)
                    Text("\(progress.chunks)").monospacedDigit()
                }
                GridRow {
                    Text("K18-sekunder").foregroundStyle(.secondary)
                    Text("\(progress.k18Seconds)").monospacedDigit()
                }
                GridRow {
                    Text("Poster").foregroundStyle(.secondary)
                    Text("\(progress.records)").monospacedDigit()
                }
                if let a = progress.first, let b = progress.last {
                    GridRow {
                        Text("Tid").foregroundStyle(.secondary)
                        Text("\(a.formatted(date: .abbreviated, time: .shortened)) – \(b.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                    }
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    private var rubrik: String {
        if let o = outcome { return Self.text(o) }
        guard let state else { return "Ansluter till bandet …" }
        switch state {
        case .waitingForBand: return "Ansluter till bandet …"
        case .hello: return "Hälsar …"
        case .requesting: return "Begär historiken …"
        case .receiving, .saving, .acking: return "Hämtar …"
        case .finished: return "Klar"
        }
    }

    static func text(_ o: HistorySession.Outcome) -> String {
        switch o {
        case .complete: return "Klar: allt bandet skickade är sparat och kvitterat."
        case .stopped(let r):
            switch r {
            case .unexpectedResponse(let c, let res): return "Stoppad: bandet svarade \(res) på kommando \(c)."
            case .noResponse(let c): return "Stoppad: inget svar på kommando \(c)."
            case .otherApp(let c): return "Stoppad: en annan app skickade kommando \(c). Stäng Whoop-appen och försök igen."
            case .idle: return "Stoppad: bandet tystnade."
            case .notConnected: return "Stoppad: hittade inte bandet."
            case .countMismatch(let e, let fick): return "Stoppad: biten hade \(e) poster men \(fick) kom fram. Den kvitterades inte."
            case .corruptFrame: return "Stoppad: en ram hade fel kontrollsumma. Biten kvitterades inte."
            case .unexpectedEnd: return "Stoppad: bandet avslutade en ny bit innan den förra var kvitterad."
            case .saveFailed: return "Stoppad: kunde inte spara. Biten kvitterades inte."
            case .writeFailed: return "Stoppad: bandet tog inte emot kommandot."
            case .disconnected: return "Stoppad: bandet tappades."
            case .cancelled: return "Avbruten."
            }
        }
    }
}

/// BESLUT B53 · METOD M43 · BESLUT B3. IMU-provets läge: tid, antal ramar och
/// byte, och bandets svar på kommandona. Aldrig ett värde ur rörelsen.
private struct ImuStatus: View {
    let phase: ImuControl.Phase
    let progress: ImuControl.Progress
    let failsafeStops: Int

    static func running(_ p: ImuControl.Phase) -> Bool { p == .starting || p == .on }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Läge").foregroundStyle(.secondary)
                    Text(läge)
                }
                if let s = progress.startedAt {
                    GridRow {
                        Text("Tid").foregroundStyle(.secondary)
                        Text(Duration.seconds((progress.stoppedAt ?? ctx.date).timeIntervalSince(s))
                            .formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Ramar").foregroundStyle(.secondary)
                        Text("\(progress.imuFrames)").monospacedDigit()
                    }
                    GridRow {
                        Text("Mängd").foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(progress.imuBytes), countStyle: .file))
                            .monospacedDigit()
                    }
                }
                if !progress.responses.isEmpty {
                    GridRow {
                        Text("Svar").foregroundStyle(.secondary)
                        Text(svar).font(.callout.monospaced())
                    }
                }
                if failsafeStops > 0 {
                    GridRow {
                        Text("Skydd").foregroundStyle(.secondary)
                        Text("\(failsafeStops) stopp").monospacedDigit()
                    }
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 2)
    }

    private var läge: String {
        switch phase {
        case .off: return progress.stopReason.map { "Av (\($0.rawValue))" } ?? "Av"
        case .starting: return "Startar …"
        case .on: return "På"
        case .stopping: return "Stoppar …"
        }
    }

    /// "81:1 106↑:1 82:1 106↓:–" — kommandot, på/av för 106, och resultatet.
    private var svar: String {
        progress.responses.map { (r: ImuControl.Response) -> String in
            let pil: String = r.on.map { $0 ? "↑" : "↓" } ?? ""
            return "\(r.command)\(pil):" + (r.result.map { "\($0)" } ?? "–")
        }.joined(separator: " ")
    }
}

/// BESLUT B53. Märken för provets delar: ett märke gäller till nästa
/// (`tools/imu_analys.py`). Skrivs i dygnets sidofil som de andra märkena.
private struct ImuMarks: View {
    let last: String?
    let count: Int
    let onMark: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(ImuControl.markerLabels, id: \.self) { ord in
                    Button(ord) { onMark(ord) }
                        .buttonStyle(.bordered)
                        .tint(ord == last ? Color.accentColor : Color.secondary)
                }
            }
            .sensoryFeedback(.selection, trigger: count)
        }
        .padding(.vertical, 4)
    }
}
