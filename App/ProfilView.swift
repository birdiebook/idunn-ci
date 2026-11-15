import SwiftUI
import Fitness
import Markers

/// BESLUT B104 · BESLUT B105 · METOD M59
/// Fliken Profil: var användaren ligger, markör för markör. Överst det han mäter själv (VO2 max, greppstyrka och egna
/// markörer), med platsen bland jämnåriga och motsvarande ålder där en normtabell finns; under det vad Idunn mäter
/// (HRV, vilopuls, regelbundenhet, pulsens återhämtning, maxpuls) som kvartalets nivå mot kvartalet före och året
/// före. `ProfilScreen` och `ProfilStack` tar sin data som värden, så att provet ritar dem; `ProfilView` kopplar dem
/// till `ProfilModell`. Texterna kommer färdiga ur IdunnKit (`MarkerText`).
struct ProfilView: View {
    @ObservedObject private var modell = ProfilModell.shared
    /// BESLUT B111. Kroppen och träningsvanorna sparas i konditionens lager.
    @ObservedObject private var kondition = KonditionModell.shared

    var body: some View {
        ProfilScreen(kort: modell.kort, person: modell.person, logg: modell.logg, låst: modell.låst,
                     idag: Väcktidsval.idag(),
                     kropp: kondition.lager.profile,
                     sättKropp: { (p: FitnessProfile) -> Void in kondition.sätt(profil: p) },
                     handlingar: ProfilHandlingar(
                        läggTill: { (m: MarkerID, dag: Int, värde: Double, not: String?) -> Void in
                            _ = modell.läggTill(markör: m, dag: dag, värde: värde, not: not)
                        },
                        taBortMätning: { (id: String) -> Void in modell.taBort(mätning: id) },
                        nyMarkör: { (namn: String, enhet: String, bättre: MarkerDefinition.Direction) -> Void in
                            _ = modell.nyMarkör(namn: namn, enhet: enhet, bättre: bättre)
                        },
                        taBortMarkör: { (id: MarkerID) -> Void in modell.taBort(markör: id) },
                        sättPerson: { (p: Person?) -> Void in modell.sätt(person: p) }))
    }
}

/// Det som knapparna gör. Standardvärdena gör ingenting, så att provet kan rita vyn utan modellen.
struct ProfilHandlingar {
    var läggTill: (MarkerID, Int, Double, String?) -> Void = { (_: MarkerID, _: Int, _: Double, _: String?) -> Void in }
    var taBortMätning: (String) -> Void = { (_: String) -> Void in }
    var nyMarkör: (String, String, MarkerDefinition.Direction) -> Void = {
        (_: String, _: String, _: MarkerDefinition.Direction) -> Void in
    }
    var taBortMarkör: (MarkerID) -> Void = { (_: MarkerID) -> Void in }
    var sättPerson: (Person?) -> Void = { (_: Person?) -> Void in }
}

/// Hela fliken som värden: listan, och bladen för en mätning, för födelseår och kön och för en egen markör.
struct ProfilScreen: View {
    let kort: [MarkerCard]
    let person: Person?
    let logg: MeasurementLog
    var låst: Bool = false
    let idag: Int
    /// BESLUT B111. Längd, vikt, midjemått, maxpuls och träningsvanor, och vad som händer när de ändras.
    var kropp: FitnessProfile = FitnessProfile()
    var sättKropp: (FitnessProfile) -> Void = { (_: FitnessProfile) -> Void in }
    var handlingar = ProfilHandlingar()

    @State private var mäter: MarkerDefinition?
    @State private var visarPerson: Bool = false
    @State private var visarNyMarkör: Bool = false
    @State private var visarKropp: Bool = false

    /// Egen init, så att `@State private` inte kan göra den osynlig för andra filer.
    init(kort: [MarkerCard], person: Person?, logg: MeasurementLog, låst: Bool = false, idag: Int,
         kropp: FitnessProfile = FitnessProfile(),
         sättKropp: @escaping (FitnessProfile) -> Void = { (_: FitnessProfile) -> Void in },
         handlingar: ProfilHandlingar = ProfilHandlingar()) {
        self.kort = kort
        self.person = person
        self.logg = logg
        self.låst = låst
        self.idag = idag
        self.kropp = kropp
        self.sättKropp = sättKropp
        self.handlingar = handlingar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ProfilStack(kort: kort, person: person, kropp: kropp, låst: låst,
                            mät: { (d: MarkerDefinition) -> Void in mäter = d },
                            öppnaPerson: { visarPerson = true },
                            öppnaKropp: { visarKropp = true },
                            nyMarkör: { visarNyMarkör = true })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Tema.bg)
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            // BESLUT B111. Kropp och träningsvanor öppnas som en sida under Profil och sparar medan fälten ändras.
            .navigationDestination(isPresented: $visarKropp) {
                KroppFormulär(profil: kropp, onÄndra: sättKropp)
            }
        }
        .sheet(item: $mäter) { (d: MarkerDefinition) in
            MätningBlad(markör: d, tidigare: logg.series(d.id), idag: idag, låst: låst,
                        egen: logg.custom.contains(where: { (c: MarkerDefinition) -> Bool in c.id == d.id }),
                        spara: { (dag: Int, värde: Double, not: String?) -> Void in
                            handlingar.läggTill(d.id, dag, värde, not)
                            mäter = nil
                        },
                        taBort: handlingar.taBortMätning,
                        taBortMarkör: {
                            handlingar.taBortMarkör(d.id)
                            mäter = nil
                        },
                        stäng: { mäter = nil })
                .presentationBackground(Tema.bg)
        }
        .sheet(isPresented: $visarPerson) {
            PersonBlad(person: person, iÅr: MarkerText.civil(day: idag).year,
                       spara: { (p: Person?) -> Void in
                           handlingar.sättPerson(p)
                           visarPerson = false
                       },
                       stäng: { visarPerson = false })
                .presentationDetents([.medium])
                .presentationBackground(Tema.bg)
        }
        .sheet(isPresented: $visarNyMarkör) {
            MarkörBlad(spara: { (namn: String, enhet: String, bättre: MarkerDefinition.Direction) -> Void in
                           handlingar.nyMarkör(namn, enhet, bättre)
                           visarNyMarkör = false
                       },
                       stäng: { visarNyMarkör = false })
                .presentationDetents([.medium])
                .presentationBackground(Tema.bg)
        }
    }
}

/// Profilens innehåll utan rullvy och blad, så att provet ritar det: raden med födelseår och kön, det användaren mäter
/// och det Idunn mäter.
struct ProfilStack: View {
    let kort: [MarkerCard]
    let person: Person?
    /// BESLUT B111. Kroppen och träningsvanorna, för raden under födelseår och kön.
    var kropp: FitnessProfile = FitnessProfile()
    var låst: Bool = false
    var mät: (MarkerDefinition) -> Void = { (_: MarkerDefinition) -> Void in }
    var öppnaPerson: () -> Void = {}
    var öppnaKropp: () -> Void = {}
    var nyMarkör: () -> Void = {}

    private var inskrivna: [MarkerCard] {
        kort.filter { (k: MarkerCard) -> Bool in k.definition.source == .manual }
    }
    private var mätta: [MarkerCard] {
        kort.filter { (k: MarkerCard) -> Bool in k.definition.source != .manual }
    }

    private var personrubrik: String {
        guard let p = person else { return "Lägg in födelseår och kön" }
        return "Född \(String(p.birthYear)) · \(p.sex == .male ? "man" : "kvinna")"
    }
    private var persontext: String {
        person == nil ? "Då visas var du ligger bland jämnåriga." : "Jämnåriga är de i din ålder och av ditt kön."
    }

    private var kroppIfylld: Bool {
        kropp.heightCm != nil || kropp.weightKg != nil || kropp.waistCm != nil || kropp.ownMaxPulse != nil
            || kropp.habits != nil
    }
    private var kroppstext: String {
        kroppIfylld ? "Längd, vikt, midjemått, maxpuls och hur du tränar."
                    : "Fyll i för att konditionen ska kunna räknas."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: öppnaPerson) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: personrubrik)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(person == nil ? Tema.accent : Tema.text)
                        Text(verbatim: persontext)
                            .font(.system(size: 12))
                            .foregroundStyle(Tema.dim)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.faint)
                }
                .kort()
            }
            .buttonStyle(Tryckyta())

            // BESLUT B111. Kropp och träningsvanor, direkt under födelseår och kön.
            Button(action: öppnaKropp) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "Kropp och träningsvanor")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(kroppIfylld ? Tema.text : Tema.accent)
                        Text(verbatim: kroppstext)
                            .font(.system(size: 12))
                            .foregroundStyle(Tema.dim)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.faint)
                }
                .kort()
            }
            .buttonStyle(Tryckyta())

            if låst {
                Text(verbatim: "Mätningarna är sparade av en nyare version av appen och går inte att ändra här.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.yellow)
                    .kort()
            }

            Sektion(text: "Du mäter")
            ForEach(inskrivna) { (k: MarkerCard) in
                Button {
                    mät(k.definition)
                } label: {
                    ProfilRad(kort: k)
                }
                .buttonStyle(Tryckyta())
            }
            Button(action: nyMarkör) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text(verbatim: "Ny markör")
                    Spacer(minLength: 4)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tema.accent)
                .kort()
            }
            .buttonStyle(Tryckyta())

            Sektion(text: "Idunn mäter")
            ForEach(mätta) { (k: MarkerCard) in
                ProfilRad(kort: k)
            }
        }
    }
}

/// En markör: namnet och värdet, platsen bland jämnåriga och motsvarande ålder där en normtabell finns, ändringen
/// i färg efter om den är åt det bättre hållet, och vad värdet bygger på.
struct ProfilRad: View {
    let kort: MarkerCard

    private func färg(_ bättre: Bool?) -> Color {
        guard let b = bättre else { return Tema.dim }
        return b ? Tema.green : Tema.red
    }

    /// Raden under talen: bästa värdet och vad värdet bygger på, eller vad som saknas.
    private var fot: String {
        if kort.value == nil {
            switch kort.definition.source {
            case .manual: return "Tryck för att lägga in en mätning"
            case .night: return "Visas efter 20 nätter"
            case .pass: return kort.definition.id == .heartRateRecovery ? "Visas efter ett konditionspass"
                                                                         : "Visas efter ett pass"
            }
        }
        let delar: [String?] = [MarkerText.best(kort), MarkerText.basis(kort)]
        return delar.compactMap { (s: String?) -> String? in s }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: kort.definition.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.text)
                Spacer(minLength: 8)
                Text(verbatim: MarkerText.value(kort))
                    .font(Tema.mono(22))
                    .foregroundStyle(kort.value == nil ? Tema.faint : Tema.text)
                if !kort.definition.unit.isEmpty {
                    Text(verbatim: kort.definition.unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Tema.dim)
                }
            }
            if let n = kort.norm {
                ProfilNorm(norm: n)
            }
            if let ändring = MarkerText.change(kort) {
                Text(verbatim: ändring)
                    .font(.system(size: 12))
                    .foregroundStyle(färg(kort.improved(kort.change)))
            }
            if let året = MarkerText.overYear(kort) {
                Text(verbatim: året)
                    .font(.system(size: 12))
                    .foregroundStyle(färg(kort.improved(kort.changeOverYear)))
            }
            if !fot.isEmpty {
                Text(verbatim: fot)
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.faint)
            }
        }
        .kort()
    }
}

/// Platsen bland jämnåriga: motsvarande ålder, en stapel för andelen med ett sämre värde, och källan.
struct ProfilNorm: View {
    let norm: NormStanding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let ålder = MarkerText.equivalentAge(norm) {
                Text(verbatim: ålder)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.accent)
            }
            if let plats = MarkerText.standing(norm), let andel = norm.betterThan {
                GeometryReader { (g: GeometryProxy) in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tema.track)
                        Capsule().fill(Tema.accent)
                            .frame(width: max(6, g.size.width * CGFloat(min(100, max(0, andel)) / 100)))
                    }
                }
                .frame(height: 6)
                Text(verbatim: plats)
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
            }
            Text(verbatim: "Jämfört med \(norm.source)")
                .font(.system(size: 10))
                .foregroundStyle(Tema.faint)
        }
    }
}

/// Bladet för en markör som skrivs in: en ny mätning (värde, dag, hur det mättes), de tidigare mätningarna med
/// svep för att ta bort, och för en egen markör knappen som tar bort den. Värdet skrivs med komma eller punkt.
struct MätningBlad: View {
    let markör: MarkerDefinition
    let tidigare: [MarkerReading]
    let idag: Int
    var låst: Bool = false
    var egen: Bool = false
    var spara: (Int, Double, String?) -> Void = { (_: Int, _: Double, _: String?) -> Void in }
    var taBort: (String) -> Void = { (_: String) -> Void in }
    var taBortMarkör: () -> Void = {}
    var stäng: () -> Void = {}

    @State private var text: String = ""
    @State private var datum: Date = Date()
    @State private var not: String = ""
    @State private var frågar: Bool = false

    init(markör: MarkerDefinition, tidigare: [MarkerReading], idag: Int, låst: Bool = false, egen: Bool = false,
         spara: @escaping (Int, Double, String?) -> Void = { (_: Int, _: Double, _: String?) -> Void in },
         taBort: @escaping (String) -> Void = { (_: String) -> Void in },
         taBortMarkör: @escaping () -> Void = {},
         stäng: @escaping () -> Void = {}) {
        self.markör = markör
        self.tidigare = tidigare
        self.idag = idag
        self.låst = låst
        self.egen = egen
        self.spara = spara
        self.taBort = taBort
        self.taBortMarkör = taBortMarkör
        self.stäng = stäng
    }

    /// Det inskrivna som tal: komma eller punkt, ändligt och över noll. Annars `nil`.
    static func tal(_ text: String) -> Double? {
        let rent: String = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(rent), v.isFinite, v > 0 else { return nil }
        return v
    }

    private var senastFörst: [MarkerReading] { Array(tidigare.reversed()) }
    private var rubrik: String {
        markör.unit.isEmpty ? "Ny mätning" : "Ny mätning, \(markör.unit)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Värde", text: $text)
                        .keyboardType(.decimalPad)
                    DatePicker("Dag", selection: $datum, in: ...Date(), displayedComponents: .date)
                    TextField("Hur mättes det? (valfritt)", text: $not)
                } header: {
                    Text(verbatim: rubrik)
                }
                if !senastFörst.isEmpty {
                    Section {
                        ForEach(senastFörst) { (m: MarkerReading) in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: MarkerText.date(day: m.day))
                                    if let n = m.note, !n.isEmpty {
                                        Text(verbatim: n)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(verbatim: MarkerText.number(m.value, decimals: markör.decimals))
                                    .font(Tema.mono(15))
                            }
                        }
                        .onDelete { (index: IndexSet) -> Void in
                            let rader: [MarkerReading] = senastFörst
                            for i in index where i < rader.count { taBort(rader[i].id) }
                        }
                    } header: {
                        Text(verbatim: "Tidigare")
                    }
                }
                if egen {
                    Section {
                        Button("Ta bort markören", role: .destructive) { frågar = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.bg)
            .navigationTitle(markör.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng", action: stäng)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        if let v = MätningBlad.tal(text) {
                            spara(Väcktidsval.idag(datum), v, not)
                        }
                    }
                    .disabled(låst || MätningBlad.tal(text) == nil)
                }
            }
            .confirmationDialog("Ta bort markören och alla dess mätningar?", isPresented: $frågar,
                                titleVisibility: .visible) {
                Button("Ta bort", role: .destructive, action: taBortMarkör)
                Button("Avbryt", role: .cancel) {}
            }
        }
    }
}

/// Bladet för födelseår och kön: det normtabellerna behöver, och inget annat.
struct PersonBlad: View {
    let person: Person?
    let iÅr: Int
    var spara: (Person?) -> Void = { (_: Person?) -> Void in }
    var stäng: () -> Void = {}

    @State private var år: Int
    @State private var kön: Sex

    init(person: Person?, iÅr: Int, spara: @escaping (Person?) -> Void = { (_: Person?) -> Void in },
         stäng: @escaping () -> Void = {}) {
        self.person = person
        self.iÅr = iÅr
        self.spara = spara
        self.stäng = stäng
        // Hjulet börjar mitt i spannet när inget år är satt; det är ingen gissning om användaren.
        _år = State(initialValue: person?.birthYear ?? iÅr - 40)
        _kön = State(initialValue: person?.sex ?? .male)
    }

    private var årtal: [Int] { Array((iÅr - 100)...(iÅr - 10)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Född", selection: $år) {
                        ForEach(årtal, id: \.self) { (y: Int) in
                            Text(verbatim: String(y)).tag(y)
                        }
                    }
                    Picker("Kön", selection: $kön) {
                        Text(verbatim: "Man").tag(Sex.male)
                        Text(verbatim: "Kvinna").tag(Sex.female)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(verbatim: "Används bara för att jämföra med jämnåriga. Uppgifterna stannar på telefonen.")
                }
                if person != nil {
                    Section {
                        Button("Ta bort", role: .destructive) { spara(nil) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.bg)
            .navigationTitle("Födelseår och kön")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng", action: stäng)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") { spara(Person(birthYear: år, sex: kön)) }
                }
            }
        }
    }
}

/// Bladet för en egen markör: namn, enhet och åt vilket håll värdet är bättre.
struct MarkörBlad: View {
    var spara: (String, String, MarkerDefinition.Direction) -> Void = {
        (_: String, _: String, _: MarkerDefinition.Direction) -> Void in
    }
    var stäng: () -> Void = {}

    @State private var namn: String = ""
    @State private var enhet: String = ""
    @State private var bättre: MarkerDefinition.Direction = .higher

    init(spara: @escaping (String, String, MarkerDefinition.Direction) -> Void = {
             (_: String, _: String, _: MarkerDefinition.Direction) -> Void in
         },
         stäng: @escaping () -> Void = {}) {
        self.spara = spara
        self.stäng = stäng
    }

    private var harNamn: Bool { !namn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Namn, till exempel Marklyft", text: $namn)
                    TextField("Enhet, till exempel kg", text: $enhet)
                        .textInputAutocapitalization(.never)
                    Picker("Bättre", selection: $bättre) {
                        Text(verbatim: "Högre är bättre").tag(MarkerDefinition.Direction.higher)
                        Text(verbatim: "Lägre är bättre").tag(MarkerDefinition.Direction.lower)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(verbatim: "En egen markör jämförs med dina tidigare mätningar, inte med jämnåriga.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.bg)
            .navigationTitle("Ny markör")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng", action: stäng)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") { spara(namn, enhet, bättre) }
                        .disabled(!harNamn)
                }
            }
        }
    }
}
