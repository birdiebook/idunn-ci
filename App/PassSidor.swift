import SwiftUI
import MapKit
import Pass
import SleepNeed

/// BESLUT B124 · METOD M71 · BESLUT B133 · BESLUT B135
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

    /// BESLUT B126. Tiden i en zon: "7:36" under en timme, "1:05:00" från en timme.
    static func tid(_ sekunder: TimeInterval) -> String {
        let s: Int = max(0, Int(sekunder.rounded()))
        if s < 3_600 { return String(format: "%d:%02d", s / 60, s % 60) }
        return String(format: "%d:%02d:%02d", s / 3_600, (s % 3_600) / 60, s % 60)
    }
}

// MARK: - Gemensamt

/// BESLUT B133 · BESLUT B135. Överst på varje sida: ett piller med läget och passets tid till höger.
struct PassStatusrad: View {
    let text: String
    let tid: String

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(Tema.text).frame(width: 6, height: 6)
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tema.text)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Capsule().fill(Tema.card))
            Spacer(minLength: 8)
            Text(tid)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// BESLUT B133 · BESLUT B135. Fem korta streck: det som motsvarar zonen just nu i `Tema.text`, övriga svaga.
struct ZonStreck: View {
    let zon: Int?

    var body: some View {
        let nu: Int = zon ?? 0
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { (i: Int) in
                Capsule()
                    .fill(i == nu ? Tema.text : Color.white.opacity(0.10))
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// BESLUT B133 · BESLUT B135. Pulskurvan som en vit linje utan axlar. x är tiden sedan `start` över tiden till
/// `slut`, y är pulsen mellan lägsta och högsta provet med 10 % luft. Färre än två prov ger ett tomt kort.
struct PulsLinje: View {
    let prov: [PassSample]
    let start: Date
    let slut: Date

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            if prov.count >= 2 {
                linje(g.size)
                    .stroke(Tema.text, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func linje(_ yta: CGSize) -> Path {
        let längd: Double = max(1, slut.timeIntervalSince(start))
        let värden: [Int] = prov.map { (s: PassSample) -> Int in s.bpm }
        let låg: Double = Double(värden.min() ?? 0)
        let spann: Double = max(1, Double(värden.max() ?? 0) - låg)
        var väg: Path = Path()
        for (i, s) in prov.enumerated() {
            let fx: Double = min(1, max(0, s.t.timeIntervalSince(start) / längd))
            let fy: Double = 0.1 + 0.8 * (1 - (Double(s.bpm) - låg) / spann)
            let punkt: CGPoint = CGPoint(x: yta.width * CGFloat(fx), y: yta.height * CGFloat(fy))
            if i == 0 {
                väg.move(to: punkt)
            } else {
                väg.addLine(to: punkt)
            }
        }
        return väg
    }
}

/// BESLUT B133 · BESLUT B135. Tre rutor bredvid varandra: lägsta, snittet och högsta pulsen.
struct PassLagstSnittHogst: View {
    let pass: Pass

    var body: some View {
        HStack(spacing: 8) {
            ruta("lägst", PassFormat.bpm(pass.minBpm))
            ruta("snitt", PassFormat.bpm(pass.averageBpm))
            ruta("högst", PassFormat.bpm(pass.maxBpm))
        }
    }

    private func ruta(_ etikett: String, _ värde: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(värde)
                .font(.system(size: 22, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
            Text(etikett).font(.system(size: 11)).foregroundStyle(Tema.dim)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(Tema.card2, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// BESLUT B133 · BESLUT B135. "Bandet hörs inte" med förklaringen under, i grått.
private struct PassTystRad: View {
    let pass: Pass
    let now: Date

    var body: some View {
        let sist: Date = pass.samples.last?.t ?? pass.start
        if now.timeIntervalSince(sist) > PassScreen.silentSeconds {
            VStack(spacing: 4) {
                Label("Bandet hörs inte", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundStyle(Tema.dim)
                Text(PassFormat.väntarPåHistoriken)
                    .font(.footnote)
                    .foregroundStyle(Tema.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Nu

/// BESLUT B124 · BESLUT B133 · BESLUT B135. Sidan Nu. Pass inne: zonen som ord, pulsen stort, zonstreck, kurvan som en
/// linje och lägst/snitt/högst. Pass ute: fyra rutor (puls, sträcka, tempo, stigning) och ett kort om zonen.
struct PassNuSida: View {
    let pass: Pass
    let now: Date
    let maxpuls: Double?

    private var senaste: PassSample? { pass.samples.last }

    private var färskt: Bool {
        guard let s = senaste else { return false }
        return now.timeIntervalSince(s.t) <= PassScreen.silentSeconds
    }

    /// Zonen just nu; `nil` utan maxpuls och när bandet inte hörs.
    private var zonNu: Int? {
        guard let m = maxpuls else { return nil }
        return PassZones.current(pass.samples, now: now) { (bpm: Int) -> Int in
            PassLoad.zone(bpm: bpm, maxPulse: m)
        }
    }

    /// Zonen 1–5 när den finns, annars `nil` (vila räknas inte som en zon i skissen).
    private var zon: Int? {
        guard let z = zonNu, z >= 1 else { return nil }
        return z
    }

    var body: some View {
        if pass.isOutdoor {
            ute
        } else {
            inne
        }
    }

    // MARK: Inne

    private var inne: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(Tema.text)
                Text(zonRad).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.text)
            }
            Text(färskt ? PassFormat.bpm(senaste?.bpm) : "–")
                .font(.system(size: 96, weight: .thin))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Tema.text)
                .accessibilityLabel("Puls")
            Text("slag per minut").font(.system(size: 13)).foregroundStyle(Tema.dim)
            ZonStreck(zon: zon)
                .padding(.horizontal, 8)
            PassTystRad(pass: pass, now: now)
            PulsLinje(prov: pass.samples, start: pass.start, slut: now)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110)
                .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
            PassLagstSnittHogst(pass: pass)
        }
        .frame(maxWidth: .infinity)
    }

    private var zonRad: String {
        if let z = zon { return PassZonText.namn(z) + " · zon \(z)" }
        return "Puls"
    }

    // MARK: Ute

    private var ute: some View {
        let spår: [TrackPoint] = pass.track ?? []
        let tempo: Double? = PassTerrain.movement(spår).pace
        let stigning: Double? = PassTerrain.climb(spår)?.ascent
        let kilometer: String = PassRuttFormat.km(PassRoute.distance(spår))
            .replacingOccurrences(of: " km", with: "")
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ruta("Puls", värde: färskt ? PassFormat.bpm(senaste?.bpm) : "–", enhet: nil,
                     piller: zon.map { (z: Int) -> String in "zon \(z)" })
                ruta("Sträcka", värde: kilometer, enhet: "km", piller: nil)
            }
            HStack(spacing: 8) {
                ruta("Tempo", värde: PassRuttFormat.pace(tempo), enhet: "/km", piller: nil)
                ruta("Stigning", värde: stigning.map { (m: Double) -> String in String(Int(m.rounded())) } ?? "–",
                     enhet: stigning == nil ? nil : "m", piller: nil)
            }
            zonkort(spår)
            PassTystRad(pass: pass, now: now)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func ruta(_ titel: String, värde: String, enhet: String?, piller: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(titel).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.text)
                Spacer(minLength: 4)
                if let p = piller {
                    Text(p)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tema.text)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Tema.card2))
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(värde)
                    .font(.system(size: 34, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Tema.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let e = enhet {
                    Text(e).font(.system(size: 11)).foregroundStyle(Tema.dim)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .topLeading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    /// Kortet under rutorna: ringen och tiden i zonen just nu, och senaste kilometern.
    @ViewBuilder
    private func zonkort(_ spår: [TrackPoint]) -> some View {
        if let m = maxpuls {
            let delar: [PassZones.Share] = PassZones.time(pass.activeSamples) { (bpm: Int) -> Int in
                PassLoad.zone(bpm: bpm, maxPulse: m)
            }
            let tider: [PassRoute.Split] = PassRoute.splits(spår)
            let km: String = tider.last.map { (t: PassRoute.Split) -> String in
                "senaste kilometern " + PassRuttFormat.minutes(t.seconds)
            } ?? "första kilometern pågår"
            if let z = zon {
                let sek: TimeInterval = delar.first(where: { (d: PassZones.Share) -> Bool in d.zone == z })?.seconds ?? 0
                let tot: TimeInterval = max(1, now.timeIntervalSince(pass.start))
                HStack(spacing: 14) {
                    PassRing(andel: sek / tot, storlek: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int((sek / 60).rounded(.down))) min i " + PassZonText.namn(z).lowercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tema.text)
                        Text(km).font(.system(size: 13)).foregroundStyle(Tema.dim)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
            } else {
                kortText(km)
            }
        } else {
            kortText("Zonerna visas när maxpulsen är känd.")
        }
    }

    private func kortText(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 13)).foregroundStyle(Tema.dim)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Översikt

/// BESLUT B124 · BESLUT B133 · BESLUT B135 · METOD M71. Sidan Översikt: kurvan som en linje, lägst/snitt/högst, tid per
/// pulszon och för ett pass ute snittempo och kilometertider.
struct PassOversiktSida: View {
    let pass: Pass
    let now: Date
    let maxpuls: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PulsLinje(prov: pass.samples, start: pass.start, slut: now)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
            PassLagstSnittHogst(pass: pass)
            zonkort
            if pass.isOutdoor {
                ute
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var zonkort: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tid per pulszon").font(.headline).foregroundStyle(Tema.text)
            zoner
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var zoner: some View {
        if let m = maxpuls {
            let delar: [PassZones.Share] = PassZones.time(pass.activeSamples) { (bpm: Int) -> Int in
                PassLoad.zone(bpm: bpm, maxPulse: m)
            }
            let med: [PassZones.Share] = delar.filter { (d: PassZones.Share) -> Bool in d.zone >= 1 && d.seconds > 0 }
            if delar.isEmpty {
                Text("Ingen puls än.").font(.footnote).foregroundStyle(Tema.dim)
            } else {
                ZonRemsa(zoner: delar, höjd: 10)
                VStack(spacing: 8) {
                    ForEach(med, id: \.zone) { (d: PassZones.Share) in
                        HStack(spacing: 8) {
                            Circle().fill(PassZonTrappa.color(d.zone)).frame(width: 8, height: 8)
                            Text(PassZonText.namn(d.zone))
                                .font(.system(size: 14))
                                .foregroundStyle(Tema.text)
                            Spacer(minLength: 8)
                            Text(PassZonText.tid(d.seconds))
                                .font(.system(size: 14))
                                .monospacedDigit()
                                .foregroundStyle(Tema.text)
                        }
                    }
                }
            }
        } else {
            Text("Pulszonerna visas när maxpulsen är känd.")
                .font(.footnote)
                .foregroundStyle(Tema.dim)
        }
    }

    @ViewBuilder
    private var ute: some View {
        let spår: [TrackPoint] = pass.track ?? []
        // BESLUT B132 · METOD M77. Tempot i rörelse: stillastående räknas inte in.
        let tempo: Double? = PassTerrain.movement(spår).pace
        let tider: [PassRoute.Split] = PassRoute.splits(spår)
        VStack(spacing: 8) {
            rad("Snittempo", PassRuttFormat.pace(tempo) + " /km")
            ForEach(tider, id: \.kilometer) { (t: PassRoute.Split) in
                rad("\(t.kilometer) km", PassRuttFormat.minutes(t.seconds))
            }
        }
    }

    private func rad(_ namn: String, _ värde: String) -> some View {
        HStack {
            Text(namn).font(.system(size: 14)).foregroundStyle(Tema.dim)
            Spacer(minLength: 8)
            Text(värde)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Tema.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Karta

/// BESLUT B124 · BESLUT B133 · BESLUT B135 · METOD M71. Sidan Karta (bara för ett pass ute): en mörk, nedtonad karta
/// med spåret hittills i vitt, var man är nu, och sträckan och pulsen i ett kort över nederkanten. Kartan går inte
/// att dra i (`interactionModes: []`), den följer positionen, så ett svep över den byter sida.
struct PassKartSida: View {
    let pass: Pass
    let now: Date
    let maxpuls: Double?

    private var spår: [TrackPoint] { pass.track ?? [] }

    private var pulsText: String {
        guard let s = pass.samples.last, now.timeIntervalSince(s.t) <= PassScreen.silentSeconds else { return "–" }
        return PassFormat.bpm(s.bpm)
    }

    var body: some View {
        if let sist = PassRoute.usable(spår).last {
            karta(CLLocationCoordinate2D(latitude: sist.lat, longitude: sist.lon))
        } else {
            Text("Väntar på första positionen")
                .font(.subheadline)
                .foregroundStyle(Tema.dim)
                .frame(maxWidth: .infinity, minHeight: 460)
                .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func karta(_ här: CLLocationCoordinate2D) -> some View {
        let utsnitt: MKCoordinateRegion = MKCoordinateRegion(center: här, latitudinalMeters: 600,
                                                             longitudinalMeters: 600)
        let linje: [CLLocationCoordinate2D] = PassRoute.usable(spår).map { (p: TrackPoint) -> CLLocationCoordinate2D in
            CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        }
        return Map(position: .constant(MapCameraPosition.region(utsnitt)), interactionModes: []) {
            MapPolyline(coordinates: linje).stroke(Tema.text, lineWidth: 4)
            Annotation("", coordinate: här) {
                Circle()
                    .fill(Tema.text)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Tema.bg, lineWidth: 2))
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        // BESLUT B135. Kartans eget märke och länk ska synas hela: kartans säkra yta slutar ovanför kortet.
        .safeAreaPadding(.bottom, Self.korthöjd)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, minHeight: 460)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .bottom) { tal }
        .accessibilityLabel("Karta över rutten")
    }

    /// BESLUT B135. Kortets höjd med marginalen under det; kartans märke läggs ovanför.
    static let korthöjd: CGFloat = 96

    private var tal: some View {
        let kilometer: String = PassRuttFormat.km(PassRoute.distance(spår)).replacingOccurrences(of: " km", with: "")
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sträcka").font(.system(size: 11)).foregroundStyle(Tema.dim)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(kilometer)
                        .font(.system(size: 30, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Tema.text)
                    Text("km").font(.system(size: 12)).foregroundStyle(Tema.dim)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Puls").font(.system(size: 11)).foregroundStyle(Tema.dim)
                Text(pulsText)
                    .font(.system(size: 30, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Tema.text)
            }
        }
        .padding(14)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        .padding(12)
    }
}

// MARK: - Ramen

/// BESLUT B124 · BESLUT B133 · BESLUT B135. Sidorna medan ett pass pågår: statusraden, piller för Nu, Översikt och (ute)
/// Karta, sidorna och Stopp fast under. `nu` är en egen vy för sidan Nu (steptestet); `nil` ger `PassNuSida`. Ett
/// steptest har en sida, inga piller och knappen "Avbryt testet".
struct PassPågårSidor: View {
    let pass: Pass
    let now: Date
    let maxpuls: Double?
    let nu: AnyView?
    let steptest: Bool
    let stopp: () -> Void

    @State private var sida: Int = 0

    init(pass: Pass, now: Date, maxpuls: Double?, nu: AnyView? = nil, stopp: @escaping () -> Void,
         steptest: Bool = false) {
        self.pass = pass
        self.now = now
        self.maxpuls = maxpuls
        self.nu = nu
        self.stopp = stopp
        self.steptest = steptest
    }

    static func namn(_ sida: Int) -> String {
        switch sida {
        case 1: return "Översikt"
        case 2: return "Karta"
        default: return "Nu"
        }
    }

    private var läge: String {
        if steptest { return "Steptest" }
        return pass.isOutdoor ? "Ute" : "Pass pågår"
    }

    private var val: [(Int, String)] {
        var v: [(Int, String)] = [(0, Self.namn(0)), (1, Self.namn(1))]
        if pass.isOutdoor { v.append((2, Self.namn(2))) }
        return v
    }

    var body: some View {
        VStack(spacing: 12) {
            PassStatusrad(text: läge, tid: PassFlikText.passtid(now.timeIntervalSince(pass.start)))
                .padding(.horizontal, 16)
                .padding(.top, 16)
            if !steptest {
                PassPiller(val: val, valt: sida, välj: { (i: Int) -> Void in
                    withAnimation { sida = i }
                })
            }
            TabView(selection: $sida) {
                ScrollView {
                    (nu ?? AnyView(PassNuSida(pass: pass, now: now, maxpuls: maxpuls)))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .tag(0)
                if !steptest {
                    ScrollView {
                        PassOversiktSida(pass: pass, now: now, maxpuls: maxpuls)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .tag(1)
                    if pass.isOutdoor {
                        ScrollView {
                            PassKartSida(pass: pass, now: now, maxpuls: maxpuls)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .tag(2)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            knapp
        }
        .background(Tema.bg.ignoresSafeArea())
    }

    private var knapp: some View {
        Button(action: stopp) {
            Text(steptest ? "Avbryt testet" : "Stopp")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(steptest ? Tema.text : Tema.bg)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 18).fill(steptest ? Tema.card : Tema.text))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(steptest ? 0.12 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
