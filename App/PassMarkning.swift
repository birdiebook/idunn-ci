import SwiftUI
import Pass

/// BESLUT B150 · METOD M85
/// Märkningen av ett pass och dess tider, delad av bladet efter Stopp, förslagsbladet och bladet Ändra på ett sparat
/// pass: de sex typerna och "Annat…" med egna ord, en valfri anteckning, och start och slut i minutsteg. Allt i ren
/// SwiftUI (utom textfälten), så att provet ritar det.

/// Det som är valt i typrutnätet.
enum PassTypval: Hashable {
    case typ(PassKind)
    case annat

    /// Valet som passet bär det: egna ord ger Annat.
    init?(_ label: PassLabel) {
        if label.customKind != nil {
            self = .annat
        } else if let k = label.kind {
            self = .typ(k)
        } else {
            return nil
        }
    }
}

/// Märkningen som vyerna håller den medan den skrivs.
struct PassMarkningsval: Equatable {
    var typ: PassTypval?
    var egna: String = ""
    var anteckning: String = ""

    init(typ: PassTypval? = nil, egna: String = "", anteckning: String = "") {
        self.typ = typ
        self.egna = egna
        self.anteckning = anteckning
    }

    init(_ label: PassLabel) {
        self.init(typ: PassTypval(label), egna: label.customKind ?? "", anteckning: label.note ?? "")
    }

    var label: PassLabel {
        switch typ {
        case .typ(let k): return PassLabel(kind: k, note: anteckning)
        case .annat: return PassLabel(customKind: egna, note: anteckning)
        case nil: return PassLabel(note: anteckning)
        }
    }

    /// Något är valt: en fast typ, eller Annat med egna ord.
    var harTyp: Bool {
        switch typ {
        case .typ: return true
        case .annat: return PassEdit.clean(egna, max: PassEdit.customKindMaxLength) != nil
        case nil: return false
        }
    }
}

/// Typerna i ett rutnät med Annat… sist, textfältet för egna ord när Annat är valt, och anteckningen.
struct PassMarkningVy: View {
    @Binding var val: PassMarkningsval
    /// Anteckningen visas inte där den inte hör hemma (ett steptest har bara anteckningen).
    var medTyp: Bool = true

    private let kolumner: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if medTyp {
                LazyVGrid(columns: kolumner, spacing: 8) {
                    ForEach(PassKind.allCases, id: \.self) { (k: PassKind) in
                        ruta(PassFormat.symbol(k), k.displayName, valt: val.typ == .typ(k)) { val.typ = .typ(k) }
                    }
                    ruta("tag", "Annat…", valt: val.typ == .annat) { val.typ = .annat }
                }
                if val.typ == .annat {
                    TextField("", text: $val.egna, prompt: Text("Vad gjorde du?").foregroundColor(Tema.dim))
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .foregroundStyle(Tema.text)
                        .padding(12)
                        .background(Tema.card, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Vad gjorde du?")
                }
            }
            TextField("", text: $val.anteckning, prompt: Text("Anteckning (valfri)").foregroundColor(Tema.dim),
                      axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
                .foregroundStyle(Tema.text)
                .padding(12)
                .background(Tema.card, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Anteckning")
        }
    }

    private func ruta(_ symbol: String, _ namn: String, valt: Bool, _ välj: @escaping () -> Void) -> some View {
        Button(action: välj) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(namn).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(valt ? Tema.bg : Tema.text)
            .background(RoundedRectangle(cornerRadius: 12).fill(valt ? Tema.text : Tema.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(namn)
        .accessibilityAddTraits(valt ? .isSelected : [])
    }
}

/// BESLUT B150 · BESLUT B158. Start och slut i nattens tidshjul (`Tidshjul`, METOD M55), ett under det andra som i
/// bladet Ändra på Natten. Hjulet ger ett klockslag; `PassClock` gör det till den tid med det klockslaget som ligger
/// närmast tiden som var, och `PassEdit.set` håller den inom gränserna (högst en timme utanför, aldrig efter nu,
/// minst en minut). Allt i ren SwiftUI utom hjulen, som provet fångar ur ett riktigt fönster.
struct PassTiderVy: View {
    @Binding var start: Date
    @Binding var stopp: Date
    let gränser: PassEdit.Limits
    /// Förslagets eller passets tider när bladet öppnades: en flyttad tid visar varifrån den kom.
    var ursprung: (start: Date, stopp: Date)?

    private func hjul(_ kant: PassEdit.Edge) -> Binding<Int> {
        Binding<Int>(
            get: { PassClock.wheelMinutes(kant == .start ? start : stopp) },
            set: { (m: Int) -> Void in
                let ny: Date = PassClock.date(wheelMinutes: m, near: kant == .start ? start : stopp)
                let t = PassEdit.set(start: start, stop: stopp, edge: kant, to: ny, limits: gränser)
                start = t.start
                stopp = t.stop
            })
    }

    var body: some View {
        VStack(spacing: 12) {
            Tidshjul(rubrik: "Start", minuter: hjul(.start))
            Tidshjul(rubrik: "Slut", minuter: hjul(.stop))
            if let u = ursprung, abs(u.start.timeIntervalSince(start)) >= 30 || abs(u.stopp.timeIntervalSince(stopp)) >= 30 {
                Text("Var " + PassMarkningText.klockslag(u.start) + "–" + PassMarkningText.klockslag(u.stopp))
                    .font(Font.system(size: 12).monospacedDigit())
                    .foregroundStyle(Tema.dim)
            }
        }
    }
}

/// Talen för ett pass med de valda tiderna: längden, snittet och högsta, räknade om ur proven i fönstret.
struct PassForhandsTal: View {
    let pass: Pass?

    var body: some View {
        HStack(spacing: 8) {
            tal("Tid", pass.map { PassFormat.short($0.duration) } ?? "–")
            tal("Snitt", PassFormat.bpm(pass?.averageBpm))
            tal("Högst", PassFormat.bpm(pass?.maxBpm))
        }
    }

    private func tal(_ namn: String, _ värde: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(namn).font(.system(size: 12)).foregroundStyle(Tema.dim)
            Text(värde)
                .font(Font.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(Tema.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Klockslagen i bladen: rena funktioner, så att provet ger samma text.
enum PassMarkningText {
    /// "17:05" i `zon`.
    static func klockslag(_ t: Date, zon: TimeZone = .current) -> String {
        var kal = Calendar(identifier: .gregorian)
        kal.timeZone = zon
        let c = kal.dateComponents([.hour, .minute], from: t)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// BESLUT B150. Bladet Ändra på ett sparat pass: typen eller egna ord, anteckningen, och start och slut. Talen
/// räknas om medan tiderna flyttas; pulsen som saknas i det nya fönstret fylls ur bandets historik när det sparas.
struct PassAndraBlad: View {
    let pass: Pass
    var nu: Date = Date()
    let spara: (PassLabel, Date, Date) -> Void
    let avbryt: () -> Void

    @State private var val: PassMarkningsval
    @State private var start: Date
    @State private var stopp: Date
    private let gränser: PassEdit.Limits

    init(pass: Pass, nu: Date = Date(), spara: @escaping (PassLabel, Date, Date) -> Void,
         avbryt: @escaping () -> Void = {}) {
        self.pass = pass
        self.nu = nu
        self.spara = spara
        self.avbryt = avbryt
        let s: Date = pass.stop ?? pass.start
        _val = State(initialValue: PassMarkningsval(PassLabel(pass)))
        _start = State(initialValue: pass.start)
        _stopp = State(initialValue: s)
        gränser = PassEdit.Limits(start: pass.start, stop: s, now: nu)
    }

    private var förhand: Pass { PassEdit.retimed(pass, start: start, stop: stopp) }

    /// Den nya tiden går utanför proven som finns: de minuterna fylls ur historiken när det sparas.
    private var fylls: Bool {
        guard let första = pass.samples.first?.t, let sista = pass.activeSamples.last?.t else { return true }
        return start < första.addingTimeInterval(-60) || stopp > sista.addingTimeInterval(60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("Avbryt", action: avbryt).foregroundStyle(Tema.dim)
                    Spacer()
                    Button("Spara") { spara(val.label, start, stopp) }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.text)
                }
                Text("Ändra passet").font(.title3.weight(.semibold)).foregroundStyle(Tema.text)
                PassMarkningVy(val: $val, medTyp: !pass.isStepTest)
                if pass.stop != nil {
                    Text("Tider").font(.headline).foregroundStyle(Tema.text)
                    PassTiderVy(start: $start, stopp: $stopp, gränser: gränser,
                                ursprung: pass.suggested.map { (o: PassOrigin) -> (start: Date, stopp: Date) in (o.start, o.end) })
                    PassForhandsTal(pass: förhand)
                    if fylls {
                        Text("Pulsen för de nya minuterna fylls ur bandets historik.")
                            .font(.footnote)
                            .foregroundStyle(Tema.dim)
                    }
                }
            }
            .padding(20)
        }
        .background(Tema.bg)
    }
}
