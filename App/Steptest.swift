import SwiftUI
import AudioToolbox
import UIKit
import Fitness
import Pass

/// BESLUT B110 · METOD M62
/// Metronomen i steptestet: ett kort klick och en lätt vibration i takten som nivån kräver (`StepTest.metronome`), och
/// en ny takt när nivån byts. Rör inte `AVAudioSession`: appen spelar in ljud på natten med den, och ett systemljud
/// behöver ingen egen session. Timern ligger i `RunLoop.main` i läget `.common`, som `PassController`s, så att den går
/// också medan en lista rullas.
final class Metronom {
    private var timer: Timer?
    private var nivå: Int?
    private let hapt = UIImpactFeedbackGenerator(style: .light)
    /// BESLUT B111. Slagen som klickats på nivån: 0 vid första klicket, ett mer för varje, och tillbaka på 0 när nivån byts.
    private var slag: Int = 0
    /// BESLUT B111. Får numret på varje klick, så att bilden av takten går i takt med ljudet.
    var påSlag: ((Int) -> Void)?

    /// Slå på takten för en nivå (0 är den första), byt takt när nivån byts, eller stäng av med `nil`.
    func sätt(nivå ny: Int?) {
        guard ny != nivå else { return }
        timer?.invalidate()
        timer = nil
        nivå = ny
        slag = 0
        guard let n = ny, let slagPerMinut = StepTest.metronome(level: n), slagPerMinut > 0 else {
            påSlag?(0)
            return
        }
        hapt.prepare()
        slå()
        let t = Timer(timeInterval: 60 / slagPerMinut, repeats: true) { [weak self] _ in self?.slå() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func slå() {
        AudioServicesPlaySystemSound(1104)
        hapt.impactOccurred()
        påSlag?(slag)
        slag += 1
    }
}

/// Texterna i steptestet, så att pågår, resultat och bladet säger samma sak.
enum SteptestText {
    /// "Maxpuls 185, ur din ålder" eller "Maxpuls 185, din egen".
    static func maxpuls(_ m: MaxPulse) -> String {
        "Maxpuls \(Int(m.bpm.rounded())), " + (m.source == .own ? "din egen" : "ur din ålder")
    }

    /// Pulsen där testet stannar: 80 % av maxpulsen, avrundat.
    static func gräns(_ maxpuls: Double) -> Int {
        Int((StepTest.stopFraction * maxpuls).rounded())
    }

    /// Varför testet tog slut; `nil` när det stoppades för hand.
    static func skäl(_ r: StepTest.Reason?) -> String? {
        switch r {
        case .reachedLimit?: return "Pulsen nådde gränsen. Testet är klart."
        case .tooHigh?: return "Pulsen blev för hög. Testet stoppades."
        case .completed?: return "Alla fem nivåerna är klara."
        case nil: return nil
        }
    }

    /// Stegets höjd ur ett fält: 10–50 cm, komma eller punkt; annars `nil`.
    static func höjd(_ text: String) -> Double? {
        let rent: String = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(rent), (10.0...50.0).contains(v) else { return nil }
        return v
    }

    /// 30 och 27,5.
    static func tal(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

/// BESLUT B110 · METOD M62
/// Bladet före steptestet: tre korta punkter, stegets höjd, maxpulsen som används och en stor Starta. Saknas maxpulsen
/// står en länk till profilen i stället. Tar sina värden och återkopplingar som värden, så att provet kan rita det.
struct SteptestStart: View {
    let maxpuls: MaxPulse?
    let profil: FitnessProfile
    let onProfil: (FitnessProfile) -> Void
    let onStarta: (Double) -> Void

    @State private var höjdText: String

    init(höjdCm: Double?, maxpuls: MaxPulse?, profil: FitnessProfile = FitnessProfile(),
         onProfil: @escaping (FitnessProfile) -> Void = { _ in }, onStarta: @escaping (Double) -> Void = { _ in }) {
        self.maxpuls = maxpuls
        self.profil = profil
        self.onProfil = onProfil
        self.onStarta = onStarta
        _höjdText = State(initialValue: höjdCm.map { (v: Double) -> String in SteptestText.tal(v) } ?? "")
    }

    private var höjd: Double? { SteptestText.höjd(höjdText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    punkt("figure.stairs", "Kliv upp och ner i takt med klicket.")
                    punkt("metronome", "Fem nivåer om två minuter. Takten ökar för varje nivå.")
                    punkt("heart", "Testet stannar av sig självt när pulsen når \(Int((StepTest.stopFraction * 100).rounded())) % av maxpulsen.")

                    HStack(spacing: 10) {
                        Text("Stegets höjd").font(.headline)
                        Spacer()
                        TextField("30", text: $höjdText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title2.weight(.semibold))
                            .frame(width: 80)
                        Text("cm").font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))

                    if let m = maxpuls {
                        Text(SteptestText.maxpuls(m)).font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            if let h = höjd { onStarta(h) }
                        } label: {
                            Text("Starta")
                                .font(.title2.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Tema.red)
                        .disabled(höjd == nil)
                        if höjd == nil {
                            Text("Skriv stegets höjd, mellan 10 och 50 cm.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // BESLUT B111. Födelseår fylls i på fliken Profil; maxpulsen står i Kropp och träningsvanor.
                        Text("Fyll i födelseår under Profil, eller din maxpuls här").font(.headline)
                        NavigationLink {
                            KroppFormulär(profil: profil, onÄndra: onProfil)
                        } label: {
                            Label("Öppna Kropp och träningsvanor", systemImage: "person.crop.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.bordered)
                        .tint(Tema.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Steptest")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func punkt(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Tema.dim)
            Text(text).font(.body)
        }
    }
}

/// BESLUT B110 · METOD M62
/// Resultatet av ett steptest: konditionen stort med spannet under, och nivåerna med takt och puls under. Kan testet inte räknas (färre än
/// tre nivåer med puls, eller ingen maxpuls) står en mening om det i stället.
struct SteptestResultat: View {
    let pass: Pass
    let maxpuls: Double?
    var slut: StepTest.Reason?

    init(pass: Pass, maxpuls: Double?, slut: StepTest.Reason? = nil) {
        self.pass = pass
        self.maxpuls = maxpuls
        self.slut = slut
    }

    private var resultat: StepTest.Result? {
        guard let m = maxpuls else { return nil }
        return StepTest.estimate(pass, maxPulse: m)
    }

    var body: some View {
        VStack(spacing: 14) {
            if let s = SteptestText.skäl(slut) {
                Text(s).font(.subheadline).foregroundStyle(.secondary)
            }
            if let r = resultat {
                VStack(spacing: 2) {
                    Text("Kondition").font(.subheadline).foregroundStyle(.secondary)
                    Text(KonditionText.tal(r.value))
                        .font(.system(size: 56, weight: .light))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    // BESLUT B111. Ett spann i stället för ±.
                    Text(KonditionText.spann(r.value, r.uncertainty))
                        .font(.subheadline)
                        .foregroundStyle(Tema.dim)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Testet blev för kort för ett tal: minst tre nivåer behövs.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            tabell
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var tabell: some View {
        let nivåer: [StepTest.Level] = StepTest.levels(pass)
        if !nivåer.isEmpty {
            VStack(spacing: 6) {
                rad("Nivå", "Steg/min", "Puls", dämpad: true)
                ForEach(nivåer, id: \.index) { (n: StepTest.Level) in
                    rad(String(n.index + 1), String(Int(n.cadence)), PassFormat.bpm(n.pulse), dämpad: false)
                }
            }
            .padding(16)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func rad(_ a: String, _ b: String, _ c: String, dämpad: Bool) -> some View {
        HStack {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(maxWidth: .infinity)
            Text(c).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(dämpad ? Font.caption : Font.title3.weight(.light).monospacedDigit())
        .foregroundStyle(dämpad ? Tema.dim : Tema.text)
    }
}
