import SwiftUI
import MapKit
import Pass
import SleepNeed

/// BESLUT B124 · METOD M71
/// Ordet för en pulszon, i den ordning PassLoad räknar dem (METOD M53): 0 är vila, 5 är maximal.
enum PassZonText {
    static func namn(_ zon: Int) -> String {
        switch zon {
        case 1: return "Mycket lätt"
        case 2: return "Lätt"
        case 3: return "Måttlig"
        case 4: return "Hård"
        case 5: return "Maximal"
        default: return "Vila"
        }
    }
}

/// BESLUT B124. Sidan Nu: tiden, pulsen stort, zonen som färg och ord, och för ett pass ute sträcka och tempo.
/// Inga kurvor och inga lägst/snitt/högst här (de ligger på Översikt).
struct PassNuSida: View {
    let pass: Pass
    let now: Date
    let maxpuls: Double?

    var body: some View {
        let senaste: PassSample? = pass.samples.last
        let färskt: Bool = senaste.map { (s: PassSample) -> Bool in
            now.timeIntervalSince(s.t) <= PassScreen.silentSeconds
        } ?? false
        let zon: Int? = zonNu
        return VStack(spacing: 16) {
            Text(PassFormat.clock(now.timeIntervalSince(pass.start)))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "heart.fill").font(.title).foregroundStyle(Tema.red)
                Text(färskt ? PassFormat.bpm(senaste?.bpm) : "–")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Puls")
            if let z = zon {
                Text(PassZonText.namn(z))
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(PassZonFarg.color(z).opacity(0.25)))
            }
            tystRad(senaste)
            if pass.isOutdoor {
                PassUteStats(pass: pass, seconds: now.timeIntervalSince(pass.start)).kort(16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Zonen just nu; `nil` utan maxpuls och när bandet inte hörs.
    private var zonNu: Int? {
        guard let m = maxpuls else { return nil }
        return PassZones.current(pass.samples, now: now) { (bpm: Int) -> Int in
            PassLoad.zone(bpm: bpm, maxPulse: m)
        }
    }

    /// "Bandet hörs inte": ingen puls har kommit på 10 sekunder.
    @ViewBuilder
    private func tystRad(_ senaste: PassSample?) -> some View {
        let sist: Date = senaste?.t ?? pass.start
        if now.timeIntervalSince(sist) > PassScreen.silentSeconds {
            VStack(spacing: 4) {
                Label("Bandet hörs inte", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text(PassFormat.väntarPåHistoriken)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// BESLUT B124 · METOD M71. Sidan Översikt: kurvan, lägst/snitt/högst, tid per pulszon och för ett pass ute
/// snittempo och kilometertider.
struct PassOversiktSida: View {
    let pass: Pass
    let now: Date
    let maxpuls: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PassChart(pass: pass, now: now)
                .frame(height: 200)
            PassStats(pass: pass)
            Text("Tid per pulszon").font(.headline)
            zoner
            if pass.isOutdoor {
                ute
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var zoner: some View {
        if let m = maxpuls {
            let delar: [PassZones.Share] = PassZones.time(pass.activeSamples) { (bpm: Int) -> Int in
                PassLoad.zone(bpm: bpm, maxPulse: m)
            }
            if delar.isEmpty {
                Text("Ingen puls än.").font(.footnote).foregroundStyle(.secondary)
            } else {
                let längst: TimeInterval = max(1, delar.map { (d: PassZones.Share) -> TimeInterval in d.seconds }.max() ?? 1)
                VStack(spacing: 8) {
                    ForEach(delar, id: \.zone) { (d: PassZones.Share) in
                        HStack(spacing: 8) {
                            Circle().fill(PassZonFarg.color(d.zone)).frame(width: 10, height: 10)
                            Text(PassZonText.namn(d.zone))
                                .font(.subheadline)
                                .frame(width: 96, alignment: .leading)
                            GeometryReader { (g: GeometryProxy) in
                                Capsule()
                                    .fill(PassZonFarg.color(d.zone))
                                    .frame(width: max(4, g.size.width * CGFloat(d.seconds / längst)), height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 12)
                            Text(PassFormat.clock(d.seconds))
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                    }
                }
            }
        } else {
            Text("Pulszonerna visas när maxpulsen är känd.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var ute: some View {
        let spår: [TrackPoint] = pass.track ?? []
        let tempo: Double? = PassRoute.pace(distance: PassRoute.distance(spår), seconds: now.timeIntervalSince(pass.start))
        let tider: [PassRoute.Split] = PassRoute.splits(spår)
        VStack(spacing: 0) {
            HStack {
                Text("Snittempo").foregroundStyle(.secondary)
                Spacer()
                Text(PassRuttFormat.pace(tempo) + " /km").monospacedDigit().fontWeight(.semibold)
            }
            .padding(.vertical, 6)
            Divider()
            ForEach(tider, id: \.kilometer) { (t: PassRoute.Split) in
                HStack {
                    Text("\(t.kilometer) km").foregroundStyle(.secondary)
                    Spacer()
                    Text(PassRuttFormat.minutes(t.seconds)).monospacedDigit().fontWeight(.semibold)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}

/// BESLUT B124 · METOD M71. Sidan Karta (bara för ett pass ute): spåret hittills färgat efter pulsen, var man är
/// nu och sträckan. Kartan går inte att dra i (`interactionModes: []`), den följer positionen, så ett svep över
/// den byter sida.
struct PassKartSida: View {
    let pass: Pass
    let maxpuls: Double?

    private struct Bit: Identifiable {
        let id: Int
        let zon: Int
        let koordinater: [CLLocationCoordinate2D]
    }

    private var spår: [TrackPoint] { pass.track ?? [] }

    private var bitar: [Bit] {
        let mp: Double? = maxpuls
        let delar: [PassRoute.Run] = PassRoute.runs(spår, samples: pass.samples) { (bpm: Int) -> Int in
            if let m = mp { return PassLoad.zone(bpm: bpm, maxPulse: m) }
            return 0
        }
        var ut: [Bit] = []
        for (i, d) in delar.enumerated() {
            let k: [CLLocationCoordinate2D] = d.points.map { (p: TrackPoint) -> CLLocationCoordinate2D in
                CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            }
            ut.append(Bit(id: i, zon: d.klass, koordinater: k))
        }
        return ut
    }

    var body: some View {
        VStack(spacing: 16) {
            if let sist = PassRoute.usable(spår).last {
                karta(CLLocationCoordinate2D(latitude: sist.lat, longitude: sist.lon))
            } else {
                Text("Väntar på första positionen")
                    .font(.subheadline)
                    .foregroundStyle(Tema.dim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
            }
            stort("sträcka", PassRuttFormat.km(PassRoute.distance(spår)))
        }
        .frame(maxWidth: .infinity)
    }

    private func karta(_ här: CLLocationCoordinate2D) -> some View {
        let utsnitt: MKCoordinateRegion = MKCoordinateRegion(center: här, latitudinalMeters: 600,
                                                             longitudinalMeters: 600)
        return Map(position: .constant(MapCameraPosition.region(utsnitt)), interactionModes: []) {
            ForEach(bitar) { (b: Bit) in
                MapPolyline(coordinates: b.koordinater).stroke(PassZonFarg.color(b.zon), lineWidth: 5)
            }
            Annotation("", coordinate: här) {
                Circle()
                    .fill(Tema.accent)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
        .mapStyle(.standard)
        .frame(height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Karta över rutten")
    }

    private func stort(_ namn: String, _ värde: String) -> some View {
        VStack(spacing: 2) {
            Text(värde)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(namn).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// BESLUT B124. Sidorna medan ett pass pågår: Nu, Översikt och (ute) Karta, med sidprickar. Stopp ligger fast under
/// sidorna. `nu` är en egen vy för sidan Nu (steptestet); `nil` ger `PassNuSida`.
struct PassPågårSidor: View {
    let pass: Pass
    let now: Date
    let maxpuls: Double?
    let nu: AnyView?
    let stopp: () -> Void

    @State private var sida: Int = 0

    init(pass: Pass, now: Date, maxpuls: Double?, nu: AnyView? = nil, stopp: @escaping () -> Void) {
        self.pass = pass
        self.now = now
        self.maxpuls = maxpuls
        self.nu = nu
        self.stopp = stopp
    }

    static func namn(_ sida: Int) -> String {
        switch sida {
        case 1: return "Översikt"
        case 2: return "Karta"
        default: return "Nu"
        }
    }

    private var antal: Int { pass.isOutdoor ? 3 : 2 }

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $sida) {
                ScrollView {
                    (nu ?? AnyView(PassNuSida(pass: pass, now: now, maxpuls: maxpuls)))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .tag(0)
                ScrollView {
                    PassOversiktSida(pass: pass, now: now, maxpuls: maxpuls)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .tag(1)
                if pass.isOutdoor {
                    ScrollView {
                        PassKartSida(pass: pass, maxpuls: maxpuls)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            sidprickar
            Button(action: stopp) {
                Label("Stopp", systemImage: "stop.fill")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Tema.red)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var sidprickar: some View {
        VStack(spacing: 6) {
            Text(Self.namn(sida))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(0..<antal, id: \.self) { (i: Int) in
                    Circle()
                        .fill(i == sida ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sida \(sida + 1) av \(antal)")
        }
    }
}
