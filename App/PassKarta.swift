import MapKit
import SwiftUI
import Pass
import SleepNeed

/// BESLUT B107 · METOD M65
/// Formen på rutten: samma överallt, så att en sträcka och ett tempo alltid läses likadant.
enum PassRuttFormat {
    /// Kilometer med två decimaler och komma: "5,32 km".
    static func km(_ meters: Double) -> String {
        let hundradelar: Int = Int((max(0, meters) / 10).rounded())
        return "\(hundradelar / 100),\(String(format: "%02d", hundradelar % 100)) km"
    }

    /// Minuter och sekunder per kilometer: "5:32"; ett streck när tempot saknas.
    static func pace(_ secondsPerKm: Double?) -> String {
        guard let s = secondsPerKm else { return "–" }
        return minutes(s)
    }

    /// BESLUT B132 · METOD M77. Stigningen i hela meter: "85 m".
    static func höjdmeter(_ meter: Double) -> String {
        "\(Int(max(0, meter).rounded())) m"
    }

    /// `m:ss`, för tempot och kilometertiderna.
    static func minutes(_ seconds: Double) -> String {
        let s: Int = max(0, Int(seconds.rounded()))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    /// Sträckan på en rad i listan över pass; `nil` för ett pass inne eller innan första positionen kommit.
    static func distanceText(_ pass: Pass) -> String? {
        guard let spår = pass.track, !PassRoute.usable(spår).isEmpty else { return nil }
        return km(PassRoute.distance(spår))
    }
}

/// BESLUT B107 · METOD M53 · METOD M65
/// Färgen för en pulszon på rutten: grått för zon 0 (och när maxpulsen saknas), sedan en skala från blått över
/// grönt och gult till rött för zon 1–5.
enum PassZonFarg {
    static func color(_ zon: Int) -> Color {
        switch zon {
        case 1: return Color.blue
        case 2: return Color.green
        case 3: return Color.yellow
        case 4: return Color.orange
        case 5: return Color.red
        default: return Color.gray
        }
    }
}

/// BESLUT B110 · METOD M65
/// Sträcka och tempo som stora tal, i samma stil som `PassStats`: medan ett pass ute pågår (`seconds` är tiden
/// sedan Start) och i ett sparat pass. Före första positionen står strecken.
struct PassUteStats: View {
    let pass: Pass
    /// Tiden som tempot räknas över.
    let seconds: TimeInterval

    var body: some View {
        let spår: [TrackPoint] = pass.track ?? []
        let harPosition: Bool = !PassRoute.usable(spår).isEmpty
        let meter: Double = PassRoute.distance(spår)
        HStack(spacing: 0) {
            stat("sträcka", harPosition ? PassRuttFormat.km(meter) : "–")
            stat("tempo per km", PassRuttFormat.pace(PassRoute.pace(distance: meter, seconds: seconds)))
        }
    }

    private func stat(_ namn: String, _ värde: String) -> some View {
        VStack(spacing: 2) {
            Text(värde)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(namn).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// BESLUT B107 · BESLUT B108 · BESLUT B110 · METOD M65
/// Kartdelen i ett sparat pass ute: rutten på Apples karta, en bit per pulszon, start och mål markerade,
/// och under kartan sträcka, tid och tempo, en förklaring av färgerna och kilometertiderna. Tar passet och
/// maxpulsen som värden (utan maxpuls är hela rutten grå), så att provet kan rita den.
struct PassKarta: View {
    let pass: Pass
    /// Maxpulsen ur de sparade passen (`PassLoad.maxPulse(from:)`); `nil` när den inte går att ta ur dem.
    let maxPulse: Double?

    /// Det minsta som behövs för en rutt: två användbara positioner.
    static func harRutt(_ pass: Pass) -> Bool {
        PassRoute.usable(pass.track ?? []).count >= 2
    }

    /// En bit av rutten med sin färg, med ett löpnummer för `ForEach`.
    private struct Bit: Identifiable {
        let id: Int
        let zon: Int
        let koordinater: [CLLocationCoordinate2D]
    }

    private var spår: [TrackPoint] { pass.track ?? [] }

    private var bitar: [Bit] {
        let mp: Double? = maxPulse
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

    /// Utsnittet ur ytterkanterna, med en femtedel marginal på varje sida.
    private var utsnitt: MKCoordinateRegion {
        guard let b = PassRoute.bounds(spår) else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                      span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360))
        }
        let mitt = CLLocationCoordinate2D(latitude: (b.minLat + b.maxLat) / 2, longitude: (b.minLon + b.maxLon) / 2)
        let dLat: Double = max(0.002, (b.maxLat - b.minLat) * 1.4)
        let dLon: Double = max(0.002, (b.maxLon - b.minLon) * 1.4)
        return MKCoordinateRegion(center: mitt, span: MKCoordinateSpan(latitudeDelta: dLat, longitudeDelta: dLon))
    }

    var body: some View {
        let användbara: [TrackPoint] = PassRoute.usable(spår)
        let meter: Double = PassRoute.distance(spår)
        let tider: [PassRoute.Split] = PassRoute.splits(spår)
        // BESLUT B132 · METOD M77. Tempot räknas på tiden i rörelse, och stigningen ur spårets höjder.
        let rörelse: PassTerrain.Movement = PassTerrain.movement(spår)
        let stigning: PassTerrain.Climb? = PassTerrain.climb(spår)
        VStack(spacing: 16) {
            karta(användbara)
            HStack(spacing: 0) {
                stort("sträcka", PassRuttFormat.km(meter))
                stort("tid", PassFormat.short(pass.duration))
                stort("tempo per km", PassRuttFormat.pace(rörelse.pace))
            }
            if stigning != nil || rörelse.pausedSeconds > 0 {
                VStack(spacing: 0) {
                    if let s = stigning {
                        detalj("Stigning", PassRuttFormat.höjdmeter(s.ascent))
                    }
                    if rörelse.pausedSeconds > 0 {
                        detalj("I rörelse", PassRuttFormat.minutes(rörelse.movingSeconds))
                        detalj("Paus", PassRuttFormat.minutes(rörelse.pausedSeconds))
                    }
                }
            }
            förklaring
            if !tider.isEmpty {
                VStack(spacing: 0) {
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
    }

    // MARK: Delar

    private func karta(_ punkter: [TrackPoint]) -> some View {
        let start: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: punkter.first?.lat ?? 0,
                                                                   longitude: punkter.first?.lon ?? 0)
        let mål: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: punkter.last?.lat ?? 0,
                                                                 longitude: punkter.last?.lon ?? 0)
        return Map(initialPosition: MapCameraPosition.region(utsnitt), interactionModes: []) {
            ForEach(bitar) { (b: Bit) in
                MapPolyline(coordinates: b.koordinater).stroke(PassZonFarg.color(b.zon), lineWidth: 5)
            }
            Marker("Start", systemImage: "flag.fill", coordinate: start).tint(Color.green)
            Marker("Mål", systemImage: "flag.checkered", coordinate: mål).tint(Tema.red)
        }
        .mapStyle(.standard)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Karta över rutten")
    }

    /// BESLUT B132. En rad med namn och värde, som kilometertiderna.
    private func detalj(_ namn: String, _ värde: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(namn).foregroundStyle(.secondary)
                Spacer()
                Text(värde).monospacedDigit().fontWeight(.semibold)
            }
            .padding(.vertical, 6)
            Divider()
        }
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

    /// BESLUT B111. Förklaringen av färgerna i ord: ett tonat streck i rutten färger, med "lugnt" till "hårt". Saknas
    /// maxpulsen är rutten grå, och en rad säger varför.
    private var förklaring: some View {
        let färger: [Color] = (1...5).map { (z: Int) -> Color in PassZonFarg.color(z) }
        return VStack(spacing: 6) {
            if maxPulse == nil {
                Text("Rutten blir grå tills maxpulsen går att räkna ur dina pass.")
                    .font(.caption)
                    .foregroundStyle(Tema.dim)
                    .multilineTextAlignment(.center)
            } else {
                LinearGradient(colors: färger, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 6)
                    .clipShape(Capsule())
                HStack {
                    Text("lugnt")
                    Spacer()
                    Text("pulsen längs rutten")
                    Spacer()
                    Text("hårt")
                }
                .font(.caption)
                .foregroundStyle(Tema.dim)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
