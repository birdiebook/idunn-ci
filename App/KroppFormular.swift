import SwiftUI
import Fitness

/// BESLUT B106 · BESLUT B111 · METOD M60
/// Kropp och träningsvanor, på fliken Profil: längd, vikt, midjemått, maxpuls och tre frågor om träningsvanor. Alla fält
/// är valfria och ett tomt fält sparas som saknat (`nil`), aldrig som 0 eller ett standardvärde. Födelseår och kön hör
/// till personen på fliken Profil (`ProfilModell.person`) och rörs inte här: profilen som lämnas tillbaka bär de
/// `birthYear` och `sex` den fick in. Sparas när ett fält ändras och när formuläret lämnas. De tre frågorna sparas
/// först när alla tre har ett svar.
struct KroppFormulär: View {
    let onÄndra: (FitnessProfile) -> Void
    /// Födelseår och kön som kom in, lämnas orörda.
    private let birthYear: Int?
    private let sex: FitnessProfile.Sex?
    @State private var längd: String
    @State private var vikt: String
    @State private var midja: String
    @State private var maxpuls: String
    @State private var ofta: TrainingHabits.Frequency?
    @State private var hårt: TrainingHabits.Intensity?
    @State private var länge: TrainingHabits.Duration?

    init(profil: FitnessProfile, onÄndra: @escaping (FitnessProfile) -> Void = { _ in }) {
        self.onÄndra = onÄndra
        birthYear = profil.birthYear
        sex = profil.sex
        _längd = State(initialValue: profil.heightCm.map { (v: Double) -> String in konditionTal(v) } ?? "")
        _vikt = State(initialValue: profil.weightKg.map { (v: Double) -> String in konditionTal(v) } ?? "")
        _midja = State(initialValue: profil.waistCm.map { (v: Double) -> String in konditionTal(v) } ?? "")
        _maxpuls = State(initialValue: profil.ownMaxPulse.map { (v: Int) -> String in String(v) } ?? "")
        _ofta = State(initialValue: profil.habits?.frequency)
        _hårt = State(initialValue: profil.habits?.intensity)
        _länge = State(initialValue: profil.habits?.duration)
    }

    /// Profilen som fälten står just nu: ett tomt eller orimligt fält är `nil`.
    private var byggd: FitnessProfile {
        var vanor: TrainingHabits?
        if let a = ofta, let b = hårt, let c = länge {
            vanor = TrainingHabits(frequency: a, intensity: b, duration: c)
        }
        return FitnessProfile(birthYear: birthYear, sex: sex,
                              heightCm: konditionDecimal(längd, 100...250), weightKg: konditionDecimal(vikt, 30...300),
                              waistCm: konditionDecimal(midja, 40...200), ownMaxPulse: konditionHeltal(maxpuls, 100...250),
                              habits: vanor)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Längd (cm)") {
                    TextField("–", text: $längd).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Vikt (kg)") {
                    TextField("–", text: $vikt).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Midjemått (cm)") {
                    TextField("–", text: $midja).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Maxpuls (slag/min)") {
                    TextField("–", text: $maxpuls).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("Alla fält är valfria. Lämnar du maxpulsen tom räknas den ur åldern.")
            }

            Section {
                Picker("", selection: $ofta) {
                    Text("Inte angivet").tag(Optional<TrainingHabits.Frequency>.none)
                    ForEach(TrainingHabits.Frequency.allCases, id: \.self) { (f: TrainingHabits.Frequency) in
                        Text(frekvensText(f)).tag(Optional<TrainingHabits.Frequency>.some(f))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Hur ofta tränar du?")
            }

            Section {
                Picker("", selection: $hårt) {
                    Text("Inte angivet").tag(Optional<TrainingHabits.Intensity>.none)
                    ForEach(TrainingHabits.Intensity.allCases, id: \.self) { (i: TrainingHabits.Intensity) in
                        Text(hårdhetText(i)).tag(Optional<TrainingHabits.Intensity>.some(i))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Hur hårt tar du i?")
            }

            Section {
                Picker("", selection: $länge) {
                    Text("Inte angivet").tag(Optional<TrainingHabits.Duration>.none)
                    ForEach(TrainingHabits.Duration.allCases, id: \.self) { (d: TrainingHabits.Duration) in
                        Text(längdText(d)).tag(Optional<TrainingHabits.Duration>.some(d))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Hur länge håller du på varje gång?")
            } footer: {
                Text("Svara på alla tre frågorna för att träningsvanorna ska räknas.")
            }
        }
        .navigationTitle("Kropp och träningsvanor")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: byggd) { _, ny in onÄndra(ny) }
        .onDisappear { onÄndra(byggd) }
    }
}

private func frekvensText(_ f: TrainingHabits.Frequency) -> String {
    switch f {
    case .never: return "Aldrig"
    case .lessThanWeekly: return "Mindre än en gång i veckan"
    case .weekly: return "En gång i veckan"
    case .twoToThree: return "2–3 gånger i veckan"
    case .almostDaily: return "Nästan varje dag"
    }
}

private func hårdhetText(_ i: TrainingHabits.Intensity) -> String {
    switch i {
    case .easy: return "Utan att bli svettig eller andfådd"
    case .sweat: return "Svettig och andfådd"
    case .exhaustion: return "Tar ut mig nästan helt"
    }
}

private func längdText(_ d: TrainingHabits.Duration) -> String {
    switch d {
    case .under15: return "Under 15 min"
    case .to30: return "15–30 min"
    case .to60: return "30–60 min"
    case .over60: return "Över 60 min"
    }
}
