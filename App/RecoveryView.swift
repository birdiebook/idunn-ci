import SwiftUI
import Night

/// BESLUT B62 · BESLUT B63 · BESLUT B65 · BESLUT B72 · METOD M57 · PLAN.md spåret H
/// Återhämtning (tryck på Återhämtnings-ringen på Morgon): ringen, Vad som drog, måtten mot ditt normala och veckan.
/// Ringen, Vad som drog (HRV, Vilopuls och Sömn i poäng, och andningen när den ligger högt) och Återhämtnings- och
/// Sömnpoängsstaplarna ritas när talen finns (`Huvudtal`, BESLUT B65): återhämtningen från andra natten. Vilopuls i Vad
/// som drog är medelpulsen under sömnen (BESLUT B72). HRV, vilopuls och andning mot ditt normala och deras veckor är
/// det Idunn redan räknar (METOD M7, M19).
struct RecoveryScreen: View {
    let day: WakeDay
    var huvudtal: Huvudtal = .tom
    @EnvironmentObject private var recorder: Recorder

    var body: some View {
        ScrollView {
            RecoveryStack(day: day, values: Trends.idunValues(recorder.summaries.compactMap(\.idunNight)),
                          summary: MorningCardView.nights(recorder.summaries)[day], huvudtal: huvudtal)
        }
        .background(Tema.bg)
        .navigationTitle("Återhämtning")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Återhämtning utan rullning, så att `ImageRenderer` kan rita den (IdunnProv).
struct RecoveryStack: View {
    let day: WakeDay
    var values: Trends.Values = [:]
    /// Nattens sammanfattning, för länken från HRV till måttet över natten.
    var summary: NightSummary? = nil
    var huvudtal: Huvudtal = .tom

    /// BESLUT B72. Bidragen i `Huvudtal.drags` ordning.
    private static let dragNamn: [String] = ["HRV", "Vilopuls", "Sömn"]

    private func nr(_ m: Trends.Measure, _ d: WakeDay? = nil) -> MorningCard.Row? {
        MorningCard.nightRow(m, day: d ?? day, idun: values)
    }

    private var dagar7: [WakeDay] { (0..<7).map { (k: Int) -> WakeDay in day - (6 - k) } }
    private var etiketter7: [String] { dagar7.map { (d: WakeDay) -> String in Fmt.weekday(d) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // BESLUT B65. Ringen och Vad som drog (H3) ritas bara när talen finns.
            if huvudtal.recovery != nil {
                ring
            }
            if !dragMedTal.isEmpty {
                Sektion(text: "Vad som drog")
                drog.padding(.top, 10)
            }
            Sektion(text: "Mot ditt normala")
            normalt.padding(.top, 10)
            Sektion(text: "Veckan")
            veckan.padding(.top, 10)
            HStack(spacing: 12) {
                Tecken(färg: Tema.band, text: "ditt normalområde")
                Tecken(färg: Tema.accent, text: "bättre än vanligt", rund: true)
                Tecken(färg: Tema.yellow, text: "sämre", rund: true)
            }
            .font(.system(size: 10))
            .foregroundStyle(Tema.dim)
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private var ring: some View {
        HuvudRing(värde: huvudtal.recovery,
                  färg: huvudtal.recovery.map { (v: Int) -> Color in Tema.recovery(Double(v)) } ?? Tema.faint,
                  storlek: 150, linje: 12, siffra: 44)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    // MARK: Vad som drog (spåret H)

    /// Bidragen som har ett tal, störst först (BESLUT B65: utan medelpuls eller sovtid ritas raden inte).
    private var dragMedTal: [(String, Double)] {
        let rader: [(String, Double)] = (0..<Self.dragNamn.count).compactMap { (i: Int) -> (String, Double)? in
            guard let d = huvudtal.drags, i < d.count, let v = d[i] else { return nil }
            return (Self.dragNamn[i], v)
        }
        return rader.sorted { (a: (String, Double), b: (String, Double)) -> Bool in abs(a.1) > abs(b.1) }
    }

    private var drog: some View {
        let rader: [(String, Double)] = dragMedTal
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rader.count, id: \.self) { (i: Int) in
                dragrad(rader[i].0, rader[i].1)
            }
            // BESLUT B72. Andningen vägs inte in; den syns när den ligger högt mot ditt normala.
            if huvudtal.breathingHigh {
                HStack(spacing: 8) {
                    Circle().fill(Tema.yellow).frame(width: 7, height: 7)
                    Text("Andningen högre än vanligt")
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.dim)
                }
                .padding(.vertical, 7)
            }
        }
        .kort()
    }

    private func dragrad(_ namn: String, _ v: Double?) -> some View {
        let c: Color = v.map { (x: Double) -> Color in x < 0 ? Tema.yellow : Tema.green } ?? Tema.faint
        return HStack(spacing: 10) {
            Text(namn)
                .font(.system(size: 12))
                .foregroundStyle(Tema.dim)
                .frame(width: 80, alignment: .leading)
            GeometryReader { (g: GeometryProxy) in
                let w: CGFloat = g.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 18).offset(x: w / 2)
                    if let x = v {
                        let bredd: CGFloat = min(w / 2, abs(CGFloat(x)) * 2.5 / 100 * w)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(c)
                            .frame(width: bredd, height: 12)
                            .offset(x: x < 0 ? w / 2 - bredd : w / 2)
                    }
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            Text(v.map { (x: Double) -> String in (x > 0 ? "+" : "") + "\(Int(x.rounded()))" } ?? "–")
                .font(Tema.mono(13))
                .foregroundStyle(c)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    // MARK: Måtten mot ditt normala

    private var normalt: some View {
        let hrv: MorningCard.Row? = nr(.hrv)
        let vilo: MorningCard.Row? = nr(.restingHeartRate)
        let andning: MorningCard.Row? = nr(.breathing)
        return VStack(spacing: 0) {
            hrvrad(hrv)
            BandRad(namn: "Vilopuls", text: vilo.map { (r: MorningCard.Row) -> String in Fmt.num(r.value) },
                    värde: vilo?.value, område: vilo?.range, axel: vilo?.track, bra: -1)
            BandRad(namn: "Andning", text: andning.map { (r: MorningCard.Row) -> String in Fmt.num(r.value, 1) },
                    värde: andning?.value, område: andning?.range, axel: andning?.track,
                    sista: huvudtal.sleepVsNeed == nil || huvudtal.sleepVsNeedRange == nil)
            if let s = huvudtal.sleepVsNeed, let o = huvudtal.sleepVsNeedRange {
                BandRad(namn: "Sömn", text: "\(Int(s.rounded()))%", värde: s, område: o, bra: 1, sista: true)
            }
        }
        .radkort()
    }

    @ViewBuilder private func hrvrad(_ r: MorningCard.Row?) -> some View {
        let rad: BandRad = BandRad(namn: "HRV", text: r.map { (x: MorningCard.Row) -> String in Fmt.num(x.value) + " ms" },
                                   värde: r?.value, område: r?.range, axel: r?.track, bra: 1, vidare: summary != nil)
        if let s = summary {
            NavigationLink {
                NightMetricScreen(metric: .hrv, summary: s)
            } label: {
                rad
            }
            .buttonStyle(.plain)
        } else {
            rad
        }
    }

    // MARK: Veckan

    private func vecka(_ m: Trends.Measure, linjeFormat: @escaping (Double) -> String, bra: Int) -> some View {
        let rader: [MorningCard.Row?] = dagar7.map { (d: WakeDay) -> MorningCard.Row? in nr(m, d) }
        let tal: [Double?] = rader.map { (r: MorningCard.Row?) -> Double? in r?.value }
        let band: [ClosedRange<Double>?] = rader.map { (r: MorningCard.Row?) -> ClosedRange<Double>? in r?.range }
        return TidDiagram(värden: tal, etiketter: etiketter7, typ: .linje, band: band, format: linjeFormat, bra: bra)
    }

    private var veckan: some View {
        let rec: [Double?] = huvudtal.last("recovery", days: 7, ending: day)
        let harRec: Bool = rec.contains { (v: Double?) -> Bool in v != nil }
        let poäng: [Double?] = huvudtal.last("sleepScore", days: 7, ending: day)
        let harPoäng: Bool = poäng.contains { (v: Double?) -> Bool in v != nil }
        return VStack(alignment: .leading, spacing: 12) {
            if harRec {
                VStack(alignment: .leading, spacing: 6) {
                    Kortrubrik(text: "Återhämtning")
                    TidDiagram(värden: rec, etiketter: etiketter7, färgFn: { (v: Double) -> Color in Tema.recovery(v) },
                               ymin: 0, ymax: 100, rutor: 4, format: { (v: Double) -> String in "\(Int(v.rounded()))%" },
                               höjd: 170)
                }
                .kort()
            }
            VStack(alignment: .leading, spacing: 6) {
                Kortrubrik(text: "HRV")
                vecka(.hrv, linjeFormat: { (v: Double) -> String in Fmt.num(v) }, bra: 1)
            }
            .kort()
            VStack(alignment: .leading, spacing: 6) {
                Kortrubrik(text: "Vilopuls")
                vecka(.restingHeartRate, linjeFormat: { (v: Double) -> String in Fmt.num(v) }, bra: -1)
            }
            .kort()
            VStack(alignment: .leading, spacing: 6) {
                Kortrubrik(text: "Andning")
                vecka(.breathing, linjeFormat: { (v: Double) -> String in Fmt.num(v, 1) }, bra: 0)
            }
            .kort()
            if harPoäng {
                VStack(alignment: .leading, spacing: 6) {
                    Kortrubrik(text: "Sömnpoäng")
                    TidDiagram(värden: poäng, etiketter: etiketter7, färgFn: { (v: Double) -> Color in Tema.score(v) },
                               ymin: 0, ymax: 100, rutor: 4, format: { (v: Double) -> String in "\(Int(v.rounded()))%" },
                               höjd: 170)
                }
                .kort()
            }
        }
    }
}
