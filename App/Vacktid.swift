import SwiftUI
import SleepNeed

/// BESLUT B74 · BESLUT B102 · METOD M53
/// Det kortet Ikväll ber ContentView öppna: bladet Upp i morgon för morgonen efter kortets natt, med klockslaget
/// hjulet öppnar på (minuter efter midnatt), schemat som gäller och kvällens uträkning.
struct Väcktidsval: Identifiable, Equatable {
    var start: Int
    /// BESLUT B102. Schemat som gäller: en tid per veckodag och en tid för bara en morgon.
    var schema: WakeSchedule = WakeSchedule()
    /// Morgonen bladet gäller (uppvakningsdagen, dagar sedan 1970-01-01): dagen efter kortets morgon.
    var uppdag: Int = 0
    /// Morgonen ligger framför oss, så en tid för bara den går att sätta. En äldre morgons kort ändrar bara schemat.
    var engångGår: Bool = false
    /// BESLUT B80. Kvällens uträkning, som bladet visar under hjulet.
    var uträkning: Huvudtal.Kvällsuträkning? = nil
    var id: Int { uppdag }

    /// Dagen i dag i telefonens zon, som dagar sedan 1970-01-01.
    static func idag(_ nu: Date = Date(), zon: TimeZone = .current) -> Int {
        Int(((nu.timeIntervalSince1970 + Double(zon.secondsFromGMT(for: nu))) / 86_400).rounded(.down))
    }
}

private struct ÖppnaVäcktidNyckel: EnvironmentKey {
    static let defaultValue: (Väcktidsval) -> Void = { (_: Väcktidsval) in }
}

extension EnvironmentValues {
    /// Kortet Ikväll ber om bladet Upp i morgon.
    var öppnaVäcktid: (Väcktidsval) -> Void {
        get { self[ÖppnaVäcktidNyckel.self] }
        set { self[ÖppnaVäcktidNyckel.self] = newValue }
    }
}

/// BESLUT B74 · BESLUT B102 · BESLUT B103 · METOD M53
/// Bladet "Upp i morgon": sju dagknappar, valet Bara i morgon, ett tidshjul (samma som Ändra i Natten), Spara och
/// Återställ, reglaget för påminnelsen före läggdags och uträkningen. De markerade dagarna får hjulets tid; dagen är
/// morgonen användaren går upp. Bladet öppnar med morgondagen och de dagar som delar dess tid markerade, så ett schema
/// med en tid för alla dagar ändras som förut. Bara i morgon sätter en tid för den morgonen utan att ändra schemat.
/// Återställ tar de markerade dagarna (eller engångstiden) tillbaka till det vanliga uppvaknandet. Bladet tar sina
/// värden och handlingar som värden (provets regel): `spara` får hela det nya schemat.
struct VäcktidBlad: View {
    let val: Väcktidsval
    /// BESLUT B103. Påminnelsen före läggdags är på, och notiser är nekade för appen i telefonens inställningar.
    var påminnelse: Bool = false
    var nekad: Bool = false
    var spara: (WakeSchedule) -> Void = { (_: WakeSchedule) -> Void in }
    var sättPåminnelse: (Bool) -> Void = { (_: Bool) -> Void in }
    var avbryt: () -> Void = {}

    @State private var minuter: Int
    @State private var valda: Set<Int>
    @State private var baraIMorgon: Bool

    init(val: Väcktidsval, påminnelse: Bool = false, nekad: Bool = false,
         spara: @escaping (WakeSchedule) -> Void = { (_: WakeSchedule) -> Void in },
         sättPåminnelse: @escaping (Bool) -> Void = { (_: Bool) -> Void in },
         avbryt: @escaping () -> Void = {}) {
        self.val = val
        self.påminnelse = påminnelse
        self.nekad = nekad
        self.spara = spara
        self.sättPåminnelse = sättPåminnelse
        self.avbryt = avbryt
        _minuter = State(initialValue: Tidshjul.inom(val.start))
        _valda = State(initialValue: val.schema.group(of: WakeSchedule.weekday(ofDay: val.uppdag)))
        _baraIMorgon = State(initialValue: val.engångGår && val.schema.once(wakeDay: val.uppdag) != nil)
    }

    private static let bokstäver: [String] = ["M", "T", "O", "T", "F", "L", "S"]
    private static let namn: [String] = ["mån", "tis", "ons", "tors", "fre", "lör", "sön"]

    private var schema: WakeSchedule { val.schema }
    /// Veckodagen för morgonen bladet gäller, 0 måndag … 6 söndag.
    private var morgondag: Int { WakeSchedule.weekday(ofDay: val.uppdag) }
    private var engång: Double? { schema.once(wakeDay: val.uppdag) }

    /// Hjulet går kl 12–12; en väcktid ligger mellan midnatt och middag.
    private var giltig: Bool { (0...719).contains(minuter) }

    private func tid(_ dag: Int) -> Double? {
        dag < schema.weekdays.count ? schema.weekdays[dag] : nil
    }

    /// Något ändras av Spara: engångstiden är ny eller en annan, eller någon markerad dag har en annan tid.
    private var kanSpara: Bool {
        guard giltig else { return false }
        if baraIMorgon { return engång != Double(minuter) }
        return valda.contains { (d: Int) -> Bool in tid(d) != Double(minuter) }
    }

    /// Återställ finns när något är satt för det som är markerat.
    private var kanÅterställa: Bool {
        if baraIMorgon { return engång != nil }
        return valda.contains { (d: Int) -> Bool in tid(d) != nil }
    }

    /// Hjulets tid gäller morgonen bladet öppnades för: då räknas läggdags om med den.
    private var rörMorgonen: Bool { baraIMorgon || valda.contains(morgondag) }

    private var rad: String {
        if !giltig { return "Mellan midnatt och 12" }
        if baraIMorgon { return "Gäller bara i morgon, " + Self.namn[morgondag] }
        if valda.isEmpty { return "Välj dagar" }
        return "Gäller " + Self.dagtext(valda)
    }

    /// De markerade dagarna i ord: "alla dagar", "mån–fre", "mån, ons, lör–sön".
    static func dagtext(_ dagar: Set<Int>) -> String {
        let d: [Int] = dagar.filter { (i: Int) -> Bool in (0..<7).contains(i) }.sorted()
        if d.count == 7 { return "alla dagar" }
        var delar: [String] = []
        var i: Int = 0
        while i < d.count {
            var j: Int = i
            while j + 1 < d.count && d[j + 1] == d[j] + 1 { j += 1 }
            delar.append(j > i ? namn[d[i]] + "–" + namn[d[j]] : namn[d[i]])
            i = j + 1
        }
        return delar.joined(separator: ", ")
    }

    private func sparaValet() {
        guard giltig else { return }
        let ny: Double = Double(minuter)
        if baraIMorgon {
            spara(schema.settingOnce(ny, wakeDay: val.uppdag))
            return
        }
        var s: WakeSchedule = schema.setting(ny, weekdays: valda)
        // En engångstid för morgonen skulle skymma dagens nya tid.
        if valda.contains(morgondag), engång != nil { s = s.settingOnce(nil, wakeDay: val.uppdag) }
        spara(s)
    }

    private func återställValet() {
        if baraIMorgon {
            spara(schema.settingOnce(nil, wakeDay: val.uppdag))
            return
        }
        var s: WakeSchedule = schema.setting(nil, weekdays: valda)
        if valda.contains(morgondag), engång != nil { s = s.settingOnce(nil, wakeDay: val.uppdag) }
        spara(s)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Avbryt") { avbryt() }
                    .font(.system(size: 15))
                    .foregroundStyle(Tema.dim)
                Spacer()
                Text("Upp i morgon")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.text)
                Spacer()
                Button("Spara") { sparaValet() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(kanSpara ? Tema.accent : Tema.faint)
                    .disabled(!kanSpara)
            }
            .padding(.top, 18)
            .padding(.bottom, 18)
            dagrad
            if val.engångGår {
                baraIMorgonKnapp
                    .padding(.top, 14)
            }
            Tidshjul(rubrik: "Upp", minuter: $minuter)
                .frame(maxWidth: 200)
                .padding(.top, 16)
            Text(rad)
                .font(.system(size: 13))
                .foregroundStyle(giltig && (baraIMorgon || !valda.isEmpty) ? Tema.dim : Tema.yellow)
                .padding(.top, 14)
            if kanÅterställa {
                Button {
                    återställValet()
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
            påminnelserad
                .padding(.top, 20)
            if let u = val.uträkning, giltig {
                Läggdagsuträkning(u: u, upp: rörMorgonen ? Double(minuter) : u.upp)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Tema.bg)
    }

    /// BESLUT B102. Veckans sju dagar, måndag först: en knapp per dag med dagens tid under ("–" utan satt tid). Ett
    /// tryck markerar eller avmarkerar dagen och lämnar Bara i morgon.
    private var dagrad: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { (d: Int) in
                let vald: Bool = !baraIMorgon && valda.contains(d)
                let imorgon: Bool = baraIMorgon && d == morgondag
                Button {
                    if baraIMorgon {
                        baraIMorgon = false
                        valda = [d]
                    } else if valda.contains(d) {
                        valda.remove(d)
                    } else {
                        valda.insert(d)
                    }
                } label: {
                    VStack(spacing: 5) {
                        Text(Self.bokstäver[d])
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(vald ? Tema.bg : (imorgon ? Tema.accent : Tema.dim))
                            .frame(width: 36, height: 36)
                            .background(vald ? Tema.accent : Tema.card2, in: Circle())
                            .overlay {
                                if imorgon { Circle().stroke(Tema.accent, lineWidth: 1.5) }
                            }
                        Text(tid(d).map { (m: Double) -> String in Fmt.clock(minutes: m) } ?? "–")
                            .font(Tema.mono(10))
                            .foregroundStyle(vald || imorgon ? Tema.text : Tema.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// BESLUT B102. Valet Bara i morgon: hjulets tid gäller bara morgonen efter, och schemat står kvar.
    private var baraIMorgonKnapp: some View {
        Button {
            baraIMorgon.toggle()
            if !baraIMorgon, valda.isEmpty { valda = schema.group(of: morgondag) }
        } label: {
            Text("Bara i morgon")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(baraIMorgon ? Tema.bg : Tema.dim)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(baraIMorgon ? Tema.accent : Tema.card2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// BESLUT B103. Påminnelsen före läggdags: ett reglage, och en rad om notiser är avstängda för appen.
    private var påminnelserad: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Påminnelse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tema.text)
                Text(nekad ? "Notiser är avstängda för Idunn i Inställningar"
                           : "\(Int(SleepNeedRules.bedtimeReminderLeadMinutes)) min före läggdags")
                    .font(.system(size: 12))
                    .foregroundStyle(nekad ? Tema.yellow : Tema.dim)
            }
            Spacer(minLength: 8)
            Toggle("Påminnelse", isOn: Binding<Bool>(
                get: { påminnelse },
                set: { (ny: Bool) -> Void in sättPåminnelse(ny) }))
                .labelsHidden()
                .tint(Tema.accent)
        }
        .kort()
    }
}

/// BESLUT B101
/// Ett blad i sitt innehålls höjd. Innehållet mäts och bladet får den höjden, så att allt syns när bladet öppnas:
/// halvhöjden klippte rubrikraden på Upp i morgon sedan uträkningen kom till (B80). Höjden växer bara medan bladet är
/// öppet, så att bladet inte krymper under fingret när hjulet går till en tid utan uträkning. Innehållet ligger i en
/// rullvy från toppen: får det inte plats på skärmen går det att rulla i stället för att klippas.
struct IInnehålletsHöjd: ViewModifier {
    @State private var höjd: CGFloat = 0

    func body(content: Content) -> some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { (g: GeometryProxy) -> CGFloat in
                    g.size.height
                } action: { (ny: CGFloat) -> Void in
                    if ny > höjd { höjd = ny }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(höjd > 0 ? [.height(höjd)] : [.medium])
    }
}

/// BESLUT B80 · METOD M53. Så räknas läggdags, steg för steg och med hjulets väcktid: behovet ur sina delar, tiden i
/// sängen genom effektiviteten, tiden att somna, och flytten för regelbundenheten när bästa sömnpoäng ger en annan tid
/// än full sömn (B75).
struct Läggdagsuträkning: View {
    let u: Huvudtal.Kvällsuträkning
    let upp: Double

    var body: some View {
        let tider = u.tider(upp: upp)
        let iSängen: Double = u.behov * 60 / u.effektivitet
        let flytt: Double = tider.bästa - tider.full
        VStack(alignment: .leading, spacing: 0) {
            Kortrubrik(text: "Så räknas läggdags")
            rad("Grundbehov", Fmt.hm(hours: u.grund))
            rad("Sömnbrist", "+" + Fmt.hm(hours: u.skuld))
            if u.pass > 0 { rad("Gårdagens pass", "+" + Fmt.hm(hours: u.pass)) }
            rad("Behov i natt", Fmt.hm(hours: u.behov), linje: true)
            rad("Effektivitet \(Int((u.effektivitet * 100).rounded())) %", "i sängen " + Fmt.hm(minutes: iSängen))
            rad("Att somna", "+" + Fmt.hm(minutes: u.somna))
            rad("Upp " + Fmt.clock(minutes: upp), "−" + Fmt.hm(minutes: iSängen + u.somna), linje: true)
            if abs(flytt) >= 5 {
                rad("Regelbundenhet", (flytt > 0 ? "+" : "−") + Fmt.hm(minutes: abs(flytt)))
            }
            rad("Läggdags", Fmt.clock(minutes: tider.bästa), linje: true, stark: true)
        }
        .kort()
    }

    private func rad(_ namn: String, _ värde: String, linje: Bool = false, stark: Bool = false) -> some View {
        HStack {
            Text(namn)
                .font(.system(size: 13))
                .foregroundStyle(stark ? Tema.text : Tema.dim)
            Spacer(minLength: 8)
            Text(värde)
                .font(Tema.mono(stark ? 15 : 13, stark ? .bold : .regular))
                .foregroundStyle(Tema.text)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            if linje { Rectangle().fill(Tema.line).frame(height: 1) }
        }
    }
}
