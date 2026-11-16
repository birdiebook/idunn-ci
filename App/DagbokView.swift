import SwiftUI
import Journal

/// BESLUT B130 · METOD M75
/// Morgonens fråga: hur utvilad, 1–5. Ligger över hela appen tills den är besvarad eller överhoppad, så att svaret
/// ges innan nattens tal har synts. Tar sina handlingar som värden, så att provet kan rita den.
struct MorgonfrågaVy: View {
    /// Skattningen som redan är given (när frågan öppnas från Data), eller `nil`.
    var vald: Int? = nil
    var välj: (Int) -> Void = { (_: Int) -> Void in }
    var hoppaÖver: () -> Void = {}

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                Text("God morgon")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tema.dim)
                Text("Hur utvilad känner du dig?")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Tema.text)
                    .multilineTextAlignment(.center)
                Text("Svara innan du ser nattens tal.")
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.faint)
            }
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(Array(Journal.restedRange), id: \.self) { (n: Int) in
                        Button {
                            välj(n)
                        } label: {
                            Text("\(n)")
                                .font(Tema.mono(24))
                                .foregroundStyle(vald == n ? Tema.bg : Tema.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .background(vald == n ? Tema.accent : Tema.card2,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(n) av 5")
                    }
                }
                HStack {
                    Text("Inte alls")
                    Spacer()
                    Text("Helt")
                }
                .font(.system(size: 13))
                .foregroundStyle(Tema.dim)
            }
            Button(action: hoppaÖver) {
                Text("Hoppa över")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tema.dim)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }
}

/// BESLUT B130 · METOD M75
/// Kvällens blad: tryck på det som gäller ikväll. En tagg med detaljer (liten eller stor måltid) visar dem när den
/// är vald; detaljen är valfri. "Inget av det" är också ett svar. Tar sina värden och handlingar utifrån.
struct KvällVy: View {
    var taggar: [JournalTag] = JournalTags.standard
    var spara: ([EveningTag]) -> Void = { (_: [EveningTag]) -> Void in }
    var inteNu: () -> Void = {}

    @State private var valda: [EveningTag]

    init(taggar: [JournalTag] = JournalTags.standard, valda: [EveningTag] = [],
         spara: @escaping ([EveningTag]) -> Void = { (_: [EveningTag]) -> Void in },
         inteNu: @escaping () -> Void = {}) {
        self.taggar = taggar
        self.spara = spara
        self.inteNu = inteNu
        _valda = State(initialValue: valda)
    }

    private func vald(_ id: String) -> EveningTag? {
        valda.first { (t: EveningTag) -> Bool in t.id == id }
    }

    private func växla(_ id: String) {
        if vald(id) != nil {
            valda.removeAll { (t: EveningTag) -> Bool in t.id == id }
        } else {
            valda.append(EveningTag(id: id))
        }
    }

    /// Sätter detaljen, eller tar bort den om samma trycks igen.
    private func sätt(detalj: String, för id: String) {
        guard let i = valda.firstIndex(where: { (t: EveningTag) -> Bool in t.id == id }) else { return }
        valda[i].detail = valda[i].detail == detalj ? nil : detalj
    }

    /// Taggarna två och två, som rader.
    private var rader: [[JournalTag]] {
        stride(from: 0, to: taggar.count, by: 2).map { (i: Int) -> [JournalTag] in
            Array(taggar[i..<min(i + 2, taggar.count)])
        }
    }

    /// De valda taggar som har detaljer att välja, i listans ordning.
    private var medDetaljer: [JournalTag] {
        taggar.filter { (t: JournalTag) -> Bool in !t.options.isEmpty && vald(t.id) != nil }
    }

    /// I listans ordning, så att filen inte beror på i vilken ordning det trycktes.
    private var svar: [EveningTag] {
        taggar.compactMap { (t: JournalTag) -> EveningTag? in vald(t.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ikväll")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Tema.text)
                Text("Något som kan påverka natten?")
                    .font(.system(size: 14))
                    .foregroundStyle(Tema.dim)
            }
            VStack(spacing: 8) {
                ForEach(rader, id: \.first?.id) { (rad: [JournalTag]) in
                    HStack(spacing: 8) {
                        ForEach(rad) { (t: JournalTag) in
                            bricka(t.title, vald: vald(t.id) != nil) { växla(t.id) }
                        }
                        if rad.count == 1 {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                        }
                    }
                }
            }
            ForEach(medDetaljer) { (t: JournalTag) in
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tema.dim)
                    HStack(spacing: 8) {
                        ForEach(t.options, id: \.self) { (o: String) in
                            bricka(o, vald: vald(t.id)?.detail == o, höjd: 38) { sätt(detalj: o, för: t.id) }
                        }
                    }
                }
            }
            VStack(spacing: 6) {
                Button {
                    spara(svar)
                } label: {
                    Text(valda.isEmpty ? "Inget av det" : "Spara")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Tema.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: inteNu) {
                    Text("Inte nu")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tema.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private func bricka(_ text: String, vald: Bool, höjd: CGFloat = 46, tryck: @escaping () -> Void) -> some View {
        Button(action: tryck) {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(vald ? Tema.bg : Tema.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: höjd)
                .background(vald ? Tema.accent : Tema.card2,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(vald ? [.isSelected] : [])
    }
}

/// BESLUT B130 · METOD M75. Dagboken på Data: hur mycket som är loggat mot det jämförelsen behöver, och vägen till
/// kvällens blad och morgonens fråga när man vill ändra ett svar.
struct DagbokSektion: View {
    let dagbok: Journal
    var onKväll: () -> Void = {}
    var onMorgon: () -> Void = {}

    /// METOD M74. Så många skattningar och så många nätter per tagg behöver jämförelsen.
    static let skattningar: Int = 15
    static let nätterPerTagg: Int = 5

    private var taggrad: String {
        let antal: [TagCount] = dagbok.nightsPerTag
        guard !antal.isEmpty else { return "Inga taggar än" }
        return antal.prefix(4).map { (t: TagCount) -> String in
            "\(JournalTags.tag(t.id)?.title ?? t.id) \(t.nights)"
        }.joined(separator: " · ")
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Label("Morgnar med skattning", systemImage: "sun.max")
                Text("\(dagbok.mornings.count) av \(Self.skattningar)").font(.title3.weight(.semibold))
                Text("Kvällar besvarade: \(dagbok.evenings.count)").font(.caption).foregroundStyle(.secondary)
                Text(taggrad).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Button(action: onKväll) { Label("Kvällens taggar", systemImage: "moon") }
            Button(action: onMorgon) { Label("Morgonens skattning", systemImage: "square.and.pencil") }
        } header: {
            Label("Dagbok", systemImage: "book")
        } footer: {
            Text("Skattningen och taggarna är facit när nattens mått jämförs. En tagg behöver \(Self.nätterPerTagg) nätter. Allt följer med Exportera alla dygn.")
        }
    }
}
