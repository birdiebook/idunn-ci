import SwiftUI
import WhoopFrames

/// METOD M27 · BESLUT B28 · BESLUT B30 · BESLUT B3
/// Lyssnarens läge överst på sidan Data (PLAN.md A1, BESLUT B38): ansluten eller inte, när K18
/// senast hördes, när Whoop senast synkade klart, och hur mycket av senaste
/// natten K18 täcker. Allt är värden in (`ListenerStatus` räknas av
/// lyssnaren), så provet kan rita vyn med påhittade notiser. Bara tider och en
/// andel, aldrig ett mätvärde.
struct ListenerView: View {
    let link: Recorder.Link
    let battery: Int?
    let status: ListenerStatus
    var unsaved = 0
    /// Fasta klockan i provet; annars tickar vyn varje halvminut.
    var now: Date?

    var body: some View {
        if let now {
            innehåll(now)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in innehåll(ctx.date) }
        }
    }

    private func innehåll(_ now: Date) -> some View {
        // BESLUT B50. Fönstret byts kl 18, när det nya börjar, och gränserna följer zonen vid dem (sommartid).
        let fönster = NightWindow.latest(now: now, offsetAt: { (d: Date) -> Int in TimeZone.current.secondsFromGMT(for: d) })
        let täckning = status.coverage(fönster)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                LinkBadge(link: link)
                Spacer()
                if unsaved > 0 {
                    Label("\(unsaved)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("\(unsaved) rader väntar på att sparas")
                }
                BatteryBadge(percent: battery)
            }
            tidsrad("waveform.path.ecg", "K18", status.lastK18Heard, now)
            tidsrad("arrow.triangle.2.circlepath", "Whoop-synk", status.lastSync, now)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: fönster.inProgress ? "moon.stars" : "moon.zzz")
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    ProgressView(value: täckning?.fraction ?? 0)
                        .tint(Self.färg(täckning?.fraction))
                    Text(täckning.map { Self.procent($0.fraction) } ?? "–")
                        .monospacedDigit()
                        .frame(minWidth: 48, alignment: .trailing)
                }
                // METOD M27. Fönstret är ett antagande tills R4 mäter sömnperioden.
                Text("18–12")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("K18-täckning natten kl 18 till 12: \(täckning.map { Self.procent($0.fraction) } ?? "ingen")")
        }
        .padding(.vertical, 8)
    }

    private func tidsrad(_ symbol: String, _ namn: String, _ tid: Date?, _ now: Date) -> some View {
        HStack {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(namn)
            Spacer()
            Text(Self.när(tid, now: now))
                .monospacedDigit()
                .foregroundStyle(tid == nil ? Color.secondary : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Tiden som en människa läser den: "nyss", "12 min", "07:12", "mån 07:12".
    static func när(_ d: Date?, now: Date) -> String {
        guard let d else { return "–" }
        let s = now.timeIntervalSince(d)
        if s < 60 { return "nyss" }
        if s < 3600 { return "\(Int(s / 60)) min" }
        if Calendar.current.isDate(d, inSameDayAs: now) { return d.formatted(.dateTime.hour().minute()) }
        return d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func procent(_ f: Double) -> String { "\(Int((f * 100).rounded())) %" }

    /// Under hälften av natten (BESLUT B28 omprövar då strömmen) är orange.
    static func färg(_ f: Double?) -> Color {
        guard let f else { return .secondary }
        return f < 0.5 ? .orange : .green
    }
}

/// Bandets läge som en symbol. Grön: ansluten. Orange: letar eller ansluter.
struct LinkBadge: View {
    let link: Recorder.Link

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: link == .searching || link == .connecting)
            .font(.title3)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch link {
        case .idle: return "antenna.radiowaves.left.and.right.slash"
        case .bluetoothOff: return "antenna.radiowaves.left.and.right.slash"
        case .unauthorized: return "exclamationmark.triangle"
        case .searching: return "magnifyingglass"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .connected: return "antenna.radiowaves.left.and.right"
        }
    }

    private var color: Color {
        switch link {
        case .idle: return .secondary
        case .bluetoothOff, .unauthorized: return .red
        case .searching, .connecting: return .orange
        case .connected: return .green
        }
    }

    private var label: String {
        switch link {
        case .idle: return "Inte ansluten"
        case .bluetoothOff: return "Bluetooth är av"
        case .unauthorized: return "Bluetooth är inte tillåtet"
        case .searching: return "Letar efter bandet"
        case .connecting: return "Ansluter"
        case .connected: return "Ansluten"
        }
    }
}
