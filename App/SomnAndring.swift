import SwiftUI
import Night

/// METOD M55 · BESLUT B70
/// Bladet "Ändra" i Natten: två tidshjul, Somnade och Vaknade, med Spara och Återställ. Bara de två klockslagen går att
/// ändra; resten av natten räknas om ur bandet. Hjulen är systemets egna (B81); provet fångar bladet ur ett riktigt
/// fönster. Bladet tar sina värden och handlingar som värden (provets regel).
struct SömnÄndringBlad: View {
    let dag: WakeDay
    /// Nattens zon (sekunder öster om Greenwich): klockslagen ställs i den.
    let zon: Int
    /// Klockslagen bladet öppnar med, minuter efter midnatt på uppvakningsdagen (negativa kvällen före).
    let frånSomnade: Int
    let frånVaknade: Int
    /// Natten är redan ändrad: då finns Återställ.
    let ändrad: Bool
    /// Perioden som hittades ur rörelsen (Unix-sekunder), som följer med ändringen till avstämningen.
    var hittad: SleepInterval? = nil
    var spara: (SleepEdit) -> Void = { (_: SleepEdit) -> Void in }
    var återställ: () -> Void = {}
    var avbryt: () -> Void = {}

    @State private var somnade: Int
    @State private var vaknade: Int

    init(dag: WakeDay, zon: Int, frånSomnade: Int, frånVaknade: Int, ändrad: Bool, hittad: SleepInterval? = nil,
         spara: @escaping (SleepEdit) -> Void = { (_: SleepEdit) -> Void in }, återställ: @escaping () -> Void = {},
         avbryt: @escaping () -> Void = {}) {
        self.dag = dag
        self.zon = zon
        self.frånSomnade = frånSomnade
        self.frånVaknade = frånVaknade
        self.ändrad = ändrad
        self.hittad = hittad
        self.spara = spara
        self.återställ = återställ
        self.avbryt = avbryt
        _somnade = State(initialValue: Tidshjul.inom(frånSomnade))
        _vaknade = State(initialValue: Tidshjul.inom(frånVaknade))
    }

    /// METOD M55. Klockslagen bladet öppnar med: ändringen om natten har en, annars nattens period.
    static func startvärden(_ s: NightSummary, ändring: SleepEdit?) -> (somnade: Int, vaknade: Int)? {
        guard let dag = s.wakeDay else { return nil }
        if let e = ändring {
            return (SleepEdit.clockMinutes(e.onset, wakeDay: dag, utcOffsetSeconds: s.utcOffsetSeconds),
                    SleepEdit.clockMinutes(e.wake, wakeDay: dag, utcOffsetSeconds: s.utcOffsetSeconds))
        }
        guard let a = s.start, let b = s.end else { return nil }
        return (SleepEdit.clockMinutes(Int(a.timeIntervalSince1970), wakeDay: dag, utcOffsetSeconds: s.utcOffsetSeconds),
                SleepEdit.clockMinutes(Int(b.timeIntervalSince1970), wakeDay: dag, utcOffsetSeconds: s.utcOffsetSeconds))
    }

    /// METOD M55. Perioden som hittades: den sparade bredvid en ändrad natt, annars nattens egen.
    static func hittadPeriod(_ s: NightSummary) -> SleepInterval? {
        let början: Date? = s.isEdited ? s.foundStart : s.start
        let slut: Date? = s.isEdited ? s.foundEnd : s.end
        guard let a = början, let b = slut else { return nil }
        return SleepInterval(start: Int(a.timeIntervalSince1970), end: Int(b.timeIntervalSince1970))
    }

    private func pröva() throws -> SleepEdit {
        try SleepEdit.make(wakeDay: dag, onsetMinutes: somnade, wakeMinutes: vaknade, utcOffsetSeconds: zon,
                           foundOnset: hittad?.start, foundWake: hittad?.end)
    }

    private var ändring: SleepEdit? { try? pröva() }

    private var problem: SleepEdit.Problem? {
        do {
            _ = try pröva()
            return nil
        } catch {
            return (error as? SleepEdit.Problem) ?? .outsideWindow
        }
    }

    private var flyttad: Bool { somnade != frånSomnade || vaknade != frånVaknade }
    private var kanSpara: Bool { ändring != nil && flyttad }

    private var rad: String {
        switch problem {
        case .some(.wakeNotAfterOnset): return "Vaknade måste vara efter somnade"
        case .some(.tooShort): return "Minst en halvtimme"
        case .some(.outsideWindow): return "Mellan klockan 12 och 12"
        case .none: return "Sömnperiod " + Fmt.hm(minutes: Double(vaknade - somnade))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Avbryt") { avbryt() }
                    .font(.system(size: 15))
                    .foregroundStyle(Tema.dim)
                Spacer()
                Text("Sömnen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.text)
                Spacer()
                Button("Spara") {
                    if let e = ändring { spara(e) }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(kanSpara ? Tema.accent : Tema.faint)
                .disabled(!kanSpara)
            }
            .padding(.top, 18)
            .padding(.bottom, 20)
            // BESLUT B81. Systemets hjul får inte plats två i bredd: under varandra.
            VStack(spacing: 12) {
                Tidshjul(rubrik: "Somnade", minuter: $somnade)
                Tidshjul(rubrik: "Vaknade", minuter: $vaknade)
            }
            Text(rad)
                .font(.system(size: 13))
                .foregroundStyle(problem == nil ? Tema.dim : Tema.yellow)
                .padding(.top, 14)
            if ändrad {
                Button {
                    återställ()
                } label: {
                    Text("Återställ")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tema.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Tema.card2, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Tema.bg)
    }
}

/// METOD M55 · BESLUT B81. Ett klockslag i dygnsfönstret kl 12–12 (METOD M26) i systemets eget tidshjul (DatePicker),
/// som känns som Klockan. `minuter` är minuter efter midnatt på uppvakningsdagen, −720 (12:00 dagen före) till 719
/// (11:59): hjulet visar bara timme och minut, och ett klockslag från 12:00 räknas till kvällen före. Provet fångar
/// bladet ur ett riktigt fönster, eftersom `ImageRenderer` inte ritar systemhjul.
struct Tidshjul: View {
    let rubrik: String
    @Binding var minuter: Int

    static let lägst: Int = -720
    static let högst: Int = 719

    /// Klockslaget hållet inom fönstret.
    static func inom(_ m: Int) -> Int { min(högst, max(lägst, m)) }

    /// Hjulet räknar i UTC på en fast dag, så att varken zon eller sommartid flyttar klockslaget.
    private static let zon: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current
    private static let dag: Date = Date(timeIntervalSince1970: 86_400 * 11_000)

    private var tid: Binding<Date> {
        Binding<Date>(
            get: { Self.dag.addingTimeInterval(Double(((minuter % 1_440) + 1_440) % 1_440) * 60) },
            set: { (d: Date) -> Void in
                var kalender = Calendar(identifier: .gregorian)
                kalender.timeZone = Self.zon
                let c: DateComponents = kalender.dateComponents([.hour, .minute], from: d)
                let m: Int = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                minuter = Self.inom(m >= 720 ? m - 1_440 : m)
            })
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(rubrik.uppercased())
                .font(.system(size: 10))
                .tracking(1)
                .foregroundStyle(Tema.faint)
            DatePicker(rubrik, selection: tid, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.timeZone, Self.zon)
                .environment(\.locale, Locale(identifier: "sv_SE"))
                .colorScheme(.dark)
                .frame(maxHeight: 130)
                .clipped()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// METOD M55 · BESLUT B98. Knappen uppe till höger i Natten är en diskret penna, inte ordet "Ändra"; medan en ändrad
/// natt räknas om står ett hjul där i stället.
struct ÄndraKnapp: View {
    var arbetar: Bool = false
    var handling: () -> Void = {}

    var body: some View {
        if arbetar {
            ProgressView()
        } else {
            Button { handling() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Tema.dim)
            .accessibilityLabel("Ändra")
        }
    }
}
