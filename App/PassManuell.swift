import SwiftUI
import Pass

/// BESLUT B158 · METOD M85
/// Bladet för ett pass som läggs till för hand i efterhand: typen (samma rutnät, egna ord och anteckning som förslagsbladet,
/// B150), dagen med pilar som i "‹ Idag ›" på Morgon, Start och Stopp i nattens tidshjul (`Tidshjul`), och "Lägg till".
/// Stopp är klockslaget inom ett dygn efter Start (`PassManual.stopDate`). Reglerna (`PassManual.problem`) bor i
/// IdunnKit; här visas bara raden som förklarar varför knappen är grå. Vyn tar sin data som värden.
struct PassManuellBlad: View {
    /// Klockan; `nil` är telefonens klocka varje gång (bladet kan stå öppet en stund), ett värde bara i provet.
    var nu: Date?
    /// Passen som finns (sparade), för överlappningen.
    let finns: [Pass]
    let läggTill: (PassLabel, Date, Date) -> Void
    let avbryt: () -> Void

    @State private var val: PassMarkningsval
    @State private var start: Date
    /// Stopps klockslag som hjulet håller det (`PassClock`).
    @State private var stoppMinuter: Int

    /// `förval` och `tider` bara för provet: bladet som det ser ut när något redan valts.
    init(nu: Date? = nil, finns: [Pass], läggTill: @escaping (PassLabel, Date, Date) -> Void,
         avbryt: @escaping () -> Void, förval: PassMarkningsval? = nil, tider: (start: Date, stopp: Date)? = nil) {
        self.nu = nu
        self.finns = finns
        self.läggTill = läggTill
        self.avbryt = avbryt
        let standard: (start: Date, stop: Date) = PassManual.defaults(now: nu ?? Date())
        _val = State(initialValue: förval ?? PassMarkningsval())
        _start = State(initialValue: tider?.start ?? standard.start)
        _stoppMinuter = State(initialValue: PassClock.wheelMinutes(tider?.stopp ?? standard.stop))
    }

    private var klockan: Date { nu ?? Date() }
    private var stopp: Date { PassManual.stopDate(start: start, wheelMinutes: stoppMinuter) }

    private var fel: PassManual.Problem? {
        PassManual.problem(start: start, stop: stopp, now: klockan, existing: finns)
    }
    private var kanLäggas: Bool { val.harTyp && fel == nil }

    /// Raden under hjulen: felet, eller längden och var pulsen kommer ifrån. Egen egenskap, så att typkontrollen
    /// inte får ett långt uttryck i vyn.
    private var förklaring: String {
        if let f: PassManual.Problem = fel { return f.message }
        let längd: String = PassFormat.short(stopp.timeIntervalSince(start))
        return "Längd " + längd + ". Pulsen fylls ur bandets historik, nu eller när bandet har lämnat den."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lägg till i efterhand").font(.title3.weight(.semibold)).foregroundStyle(Tema.text)

                Text("Typ").font(.headline).foregroundStyle(Tema.text)
                PassMarkningVy(val: $val)

                Text("Tider").font(.headline).foregroundStyle(Tema.text)
                PassDagväljare(dag: $start, nu: klockan)
                // BESLUT B81. Hjulen under varandra, som i Natten.
                VStack(spacing: 12) {
                    Tidshjul(rubrik: "Start", minuter: Binding<Int>(
                        get: { PassClock.wheelMinutes(start) },
                        set: { (m: Int) -> Void in start = PassClock.date(wheelMinutes: m, near: start) }))
                    Tidshjul(rubrik: Calendar.current.isDate(stopp, inSameDayAs: start) ? "Stopp" : "Stopp, dagen efter",
                             minuter: $stoppMinuter)
                }

                Text(förklaring)
                    .font(.footnote)
                    .foregroundStyle(Tema.dim)

                Button {
                    läggTill(val.label, start, stopp)
                } label: {
                    Text("Lägg till")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.bg)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(Tema.text))
                        .opacity(kanLäggas ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!kanLäggas)

                Button(action: avbryt) {
                    Text("Avbryt")
                        .font(.system(size: 15))
                        .foregroundStyle(Tema.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Tema.bg)
    }
}

/// BESLUT B158. Dagen för Start med pilar åt var sida, som "‹ Idag ›" på Morgon (`MorningCardView`, B82): pilen åt höger
/// är grå från idag, pilen åt vänster från 14 dagar bakåt (`PassManual.maxAgeSeconds`). Klockslaget lämnas som det är.
struct PassDagväljare: View {
    @Binding var dag: Date
    let nu: Date

    private func flyttad(_ d: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: d, to: dag) ?? dag
    }

    private var text: String {
        let k: Calendar = Calendar.current
        if k.isDate(dag, inSameDayAs: nu) { return "Idag" }
        if let igår = k.date(byAdding: .day, value: -1, to: nu), k.isDate(dag, inSameDayAs: igår) { return "Igår" }
        return dag.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "sv_SE")))
    }

    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            pil("chevron.left", "Dagen före", flyttad(-1) >= nu.addingTimeInterval(-PassManual.maxAgeSeconds) ? -1 : nil)
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Tema.text)
                .lineLimit(1)
                .frame(minWidth: 96)
            pil("chevron.right", "Dagen efter", flyttad(1) <= nu ? 1 : nil)
            Spacer(minLength: 0)
        }
    }

    private func pil(_ symbol: String, _ namn: String, _ steg: Int?) -> some View {
        Button {
            if let d = steg { dag = flyttad(d) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(steg == nil ? Tema.track : Tema.text)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(steg == nil)
        .accessibilityLabel(namn)
    }
}
