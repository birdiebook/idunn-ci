import SwiftUI
import HeartRate
import Night

/// METOD M13 · BESLUT B3
/// En natts rapport: bilden av natten med glappen, de tre kontrollerna, och
/// natten i siffror. användaren tar skärmbilder av den, så den visar bara
/// samlade tal — andelar, kvoter, antal och nattens värden — aldrig en
/// enskild puls, ett intervall eller ett klockslag.
struct NightReportView: View {
    let stem: String
    @State private var report: NightReport?
    @State private var loaded = false

    var body: some View {
        Group {
            if let r = report {
                ReportList(report: r)
            } else if loaded {
                ContentUnavailableView("Natten gick inte att läsa", systemImage: "moon.zzz")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(report?.contents.recording.end?
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RawExportButton(stem: stem) } }
        .task {
            let s = stem
            report = await Task.detached(priority: .userInitiated) { NightReport.make(stem: s) }.value
            loaded = true
        }
    }
}

struct ReportList: View {
    let report: NightReport

    private var night: NightRecording { report.contents.recording }
    private var q: RecordingQuality.Report { report.quality }
    private var a: NightAnalysis.Report { report.analysis }

    var body: some View {
        List {
            // METOD M18 · BESLUT B19: kurvan i en egen vy, rapporten förblir delbar.
            if report.curve != nil {
                Section {
                    NavigationLink {
                        NightCurveView(summary: NightSummary(report))
                    } label: {
                        Label("Kurvan", systemImage: "chart.xyaxis.line")
                    }
                }
            }

            Section {
                NightBar(gaps: report.gaps)
                    .frame(height: 22)
                HStack {
                    Label(Duration.seconds(night.span)
                        .formatted(.units(allowed: [.hours, .minutes], width: .narrow)),
                          systemImage: "bed.double")
                    Spacer()
                    Label("\(night.samples.count)", systemImage: "waveform.path.ecg")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            // METOD M13: glappen och RR-intervallens tre kontroller.
            Section {
                CheckRow(symbol: "pause.circle", title: "Glapp",
                         value: q.gaps.map { "\($0.count) · \(pct($0.fraction))" },
                         passes: q.gaps?.passes)
                CheckRow(symbol: "1.circle", title: "Varje slag",
                         value: q.coverage.map { pct($0.fractionComplete) },
                         passes: q.coverage?.passes)
                CheckRow(symbol: "2.circle", title: "Uträknade",
                         value: q.computed.map { "\(pct($0.fractionEqualToBpm)) · \(pct($0.fractionIdentical))" },
                         passes: q.computed?.passes)
                CheckRow(symbol: "3.circle", title: "Utjämnade",
                         value: q.smoothing.map { String(format: "%.2f", $0.ratio) },
                         passes: q.smoothing?.passes)
            } header: {
                Label(q.passes ? "Natten duger" : "Misstänkt",
                      systemImage: q.passes ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(q.passes ? Color.green : Color.orange)
            }

            // METOD M4 · BESLUT B13: kandidaterna, nattmedlet först (förvalet).
            Section {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(.secondary)
                        Text("HRV").gridColumnAlignment(.leading)
                        Spacer()
                        Text(ms(a.rmssd.mean)).font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    candidate("median", a.rmssd.median)
                    candidate("sen, lugn", a.rmssd.lateQuiet)
                    candidate("Whoop-lik", a.rmssd.whoopLike)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    value("heart", "Vilopuls", a.restingHeartRate.map { "\(Int($0.rounded())) bpm" })
                    value("lungs", "Andning", a.breathsPerMinute.map { String(format: "%.1f /min", $0) })
                    value("scissors", "Kastade", pct(a.cleaning.fractionDropped))
                    value("square.grid.3x3", "Fönster", "\(a.validWindows)/\(a.windows.count)")
                }
            }

            // METOD M15: varför en kontroll fäller. Bara andelar och kvoter.
            Section {
                DiagnosisGrid(d: report.diagnostics, cleaning: a.cleaning,
                              unreadable: report.contents.unreadableNotifications)
            } header: {
                Label("Diagnos", systemImage: "stethoscope")
            }

            if night.batteryAtStart != nil || night.batteryAtEnd != nil {
                Section {
                    HStack {
                        BatteryBadge(percent: night.batteryAtStart)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        BatteryBadge(percent: night.batteryAtEnd)
                        Spacer()
                        if let s = night.batteryAtStart, let e = night.batteryAtEnd {
                            Text("\(e - s) %").monospacedDigit().font(.headline)
                        }
                    }
                }
            }

            if report.tally.total > 0 {
                Section {
                    DisclosureGroup {
                        TallyGrid(tally: report.tally)
                    } label: {
                        Label("T2 · \(report.tally.total)", systemImage: "ant")
                    }
                }
            }
        }
    }

    private func candidate(_ namn: String, _ x: Double?) -> some View {
        GridRow {
            Color.clear.frame(width: 1, height: 1)
            Text(namn).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(ms(x)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func value(_ symbol: String, _ namn: String, _ text: String?) -> some View {
        GridRow {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(namn)
            Spacer()
            Text(text ?? "–").monospacedDigit()
        }
    }

    private func ms(_ x: Double?) -> String { x.map { "\(Int($0.rounded())) ms" } ?? "–" }
}

func pct(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }

/// METOD M15 · BESLUT B3. Diagnosen av RR-strömmen, mest symboler: andelar och
/// kvoter, aldrig en puls, ett intervall eller en tid. Kvoterna är 1,00 när
/// allt stämmer.
struct DiagnosisGrid: View {
    let d: RecordingQuality.Diagnostics
    let cleaning: RRCleaning.Summary
    let unreadable: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            // Notiserna: hur RR kommer.
            Group {
                row("tray.full", "RR/notis 0·1·2·3+", perNotification)
                row("repeat", "Upprepat →·←·⇈·∗", repeats)
                row("flag", "Flaggor", flags)
                row("number", "RR/puls ▼·▲",
                    "\(k(d.countToBpm)) · \(p(d.minutesBelow))·\(p(d.minutesAbove)) %")
                row("heart.text.square", "Puls ur RR/puls", k(d.rrRateToBpm))
                row("bell", "Notiser/puls", k(d.notificationsToBpm))
                row("timer", "RR-tid/klocka", "\(k(d.rrTimeToElapsed)) · \(k(d.rrTimeToElapsedMedian))")
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            // Rensningen: varför slag kastades, och klockan av intervall.
            Group {
                row("scissors", "Kastade <300·>2000",
                    "\(p(cleaning.share(cleaning.outOfRangeShort)))·\(p(cleaning.share(cleaning.outOfRangeLong))) %")
                row("scissors", "Kastade −20·+20",
                    "\(p(cleaning.share(cleaning.deviatingShort)))·\(p(cleaning.share(cleaning.deviatingLong))) %")
                // METOD M3: slag som bandet hoppade över, ur notisernas tider.
                // Ingen skillnad räknas över dem.
                row("eye.slash", "Utelämnade", pct(cleaning.fractionOmitted))
                row("arrow.uturn.backward", "Omlagda % · st · avsnitt",
                    "\(p(cleaning.fractionReanchored)) · \(cleaning.reanchorings) · \(cleaning.segments)")
                row("exclamationmark.bubble", "Otolkade", pct(unreadableShare))
            }
        }
        .font(.callout)
    }

    private var perNotification: String {
        d.rrPerNotification.map(p).joined(separator: "·") + " %"
    }

    /// → första = förra sista · ← sista = förra första · ⇈ första = förra första · ∗ något gemensamt.
    private var repeats: String {
        let delar: [Double] = [d.firstRepeatsPreviousLast, d.lastRepeatsPreviousFirst,
                               d.firstRepeatsPreviousFirst, d.sharesAnyWithPrevious]
        return delar.map(p).joined(separator: "·") + " %"
    }

    /// De två vanligaste flaggbytena i hex med sin andel, t.ex. "16 98 % · 10 2 %".
    private var flags: String {
        let delar: [String] = d.flags.prefix(2).map { (f: RecordingQuality.Diagnostics.FlagShare) -> String in
            String(f.flags, radix: 16) + " " + pct(f.share)
        }
        return delar.isEmpty ? "–" : delar.joined(separator: " · ")
    }

    private var unreadableShare: Double {
        let alla = unreadable + d.notifications
        return alla > 0 ? Double(unreadable) / Double(alla) : 0
    }

    private func row(_ symbol: String, _ namn: String, _ text: String) -> some View {
        GridRow {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(namn)
            Spacer()
            Text(text).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    /// Procent utan tecken, för rader med flera andelar.
    private func p(_ x: Double) -> String { "\(Int((x * 100).rounded()))" }
    private func k(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "–" }
}

/// En kontroll: symbol, namn, nyckeltalet och om den håller. Utan underlag ett frågetecken.
struct CheckRow: View {
    let symbol: String
    let title: String
    let value: String?
    let passes: Bool?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            Text(title)
            Spacer()
            Text(value ?? "–").monospacedDigit().foregroundStyle(.secondary)
            Image(systemName: passes == nil ? "questionmark.circle" : passes! ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passes == nil ? Color.secondary : passes! ? Color.green : Color.orange)
        }
    }
}

/// METOD M13. Natten som ett band från första till sista notisen; glappen
/// (över 60 s utan notis) är röda.
struct NightBar: View {
    let gaps: [ClosedRange<Double>]

    var body: some View {
        Canvas { ctx, size in
            let hela = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            ctx.fill(hela, with: .color(.green.opacity(0.7)))
            ctx.clip(to: hela)
            for g in gaps {
                // Minst en punkt bred, så att ett kort glapp ändå syns.
                let x = size.width * g.lowerBound
                let w = max(1, size.width * (g.upperBound - g.lowerBound))
                ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(.red))
            }
        }
        .accessibilityLabel("\(gaps.count) glapp")
    }
}
