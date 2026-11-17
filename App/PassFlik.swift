import SwiftUI
import Pass
import SleepNeed

/// BESLUT B133 · BESLUT B134
/// Fliken Pass i skissens form (design/skiss-pass-minimal.html, läget Mörkt, Full grå): de delade delarna
/// (zonernas grå trappa, remsan, ringen, pillren, ikonrutan, texterna), fliken i vila och veckans egen sida.
/// Ingen accentfärg: det man trycker på och det valda är `Tema.text` med `Tema.bg` som textfärg, allt annat grått.
/// Vyerna tar sin data som värden, så att provet ritar dem.

// MARK: - Zonerna som en grå trappa

/// BESLUT B133. Zonerna som en grå trappa från mörkt (zon 1) till ljust (zon 5), aldrig färger.
enum PassZonTrappa {
    static func color(_ zon: Int) -> Color {
        switch zon {
        // BESLUT B137. Zonerna har färg (lånat ur stilen Lugn), och bara zonerna; vila är grå.
        case 1: return Color(rgb: 0x5E7FC9)
        case 2: return Color(rgb: 0x35C9B0)
        case 3: return Color(rgb: 0xE9C645)
        case 4: return Color(rgb: 0xF07F3C)
        case 5: return Color(rgb: 0xE5407A)
        default: return Color(rgb: 0x1F262A)
        }
    }
}

/// BESLUT B133. Tid per pulszon som en liggande remsa: en kapsel per zon med tid, bredd efter andelen.
struct ZonRemsa: View {
    let zoner: [PassZones.Share]
    var höjd: CGFloat = 6

    private var delar: [PassZones.Share] {
        zoner.filter { (z: PassZones.Share) -> Bool in z.zone >= 1 && z.seconds > 0 }
    }

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            if delar.isEmpty {
                Capsule().fill(Tema.card2)
            } else {
                let summa: Double = max(1, delar.reduce(0) { (s: Double, z: PassZones.Share) -> Double in s + z.seconds })
                let rum: CGFloat = max(0, g.size.width - CGFloat(delar.count - 1) * 2)
                HStack(spacing: 2) {
                    ForEach(delar, id: \.zone) { (z: PassZones.Share) in
                        Capsule()
                            .fill(PassZonTrappa.color(z.zone))
                            .frame(width: max(3, rum * CGFloat(z.seconds / summa)))
                    }
                }
                .frame(width: g.size.width, alignment: .leading)
            }
        }
        .frame(height: höjd)
        .accessibilityHidden(true)
    }
}

/// BESLUT B133. En ring: spåret svagt, bågen i `Tema.text`, från klockan tolv.
struct PassRing: View {
    let andel: Double
    var storlek: CGFloat = 26
    /// BESLUT B137. Bågens färg: vit, eller zonens färg när ringen visar en zon.
    var färg: Color = Tema.text

    var body: some View {
        let a: Double = andel.isFinite ? min(1, max(0, andel)) : 0
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(a))
                .stroke(färg, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: storlek, height: storlek)
        .accessibilityHidden(true)
    }
}

/// BESLUT B133. Val som piller i en kapsel: det valda fyllt med `Tema.text`, övriga i `Tema.dim`.
struct PassPiller<T: Hashable>: View {
    let val: [(T, String)]
    let valt: T
    let välj: (T) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(val.enumerated()), id: \.offset) { (e: (offset: Int, element: (T, String))) in
                let värde: T = e.element.0
                let text: String = e.element.1
                let på: Bool = värde == valt
                Button { välj(värde) } label: {
                    Text(text)
                        .font(.system(size: 13, weight: på ? .semibold : .regular))
                        .foregroundStyle(på ? Tema.bg : Tema.dim)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(på ? Tema.text : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Tema.card))
    }
}

/// BESLUT B133. Ikonen för en passtyp i en ruta: ljus (vit med mörk ikon) eller grå.
struct PassIkonruta: View {
    let symbol: String
    var ljus: Bool = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(ljus ? Tema.bg : Tema.text)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 12).fill(ljus ? Tema.text : Tema.card2))
    }
}

// MARK: - Texterna

/// BESLUT B133 · BESLUT B134. Texterna i fliken och på veckans sida: rena funktioner.
enum PassFlikText {
    private static let månader: [String] = ["jan", "feb", "mar", "apr", "maj", "jun",
                                            "jul", "aug", "sep", "okt", "nov", "dec"]
    private static let dagar: [String] = ["Måndag", "Tisdag", "Onsdag", "Torsdag", "Fredag", "Lördag", "Söndag"]
    private static let dagarKort: [String] = ["må", "ti", "on", "to", "fr", "lö", "sö"]

    /// Veckodagens plats, 0 är måndag (1970-01-01 var en torsdag).
    private static func plats(_ dag: Int) -> Int { ((dag + 3) % 7 + 7) % 7 }

    private static func månad(_ dag: Int) -> String {
        let m: Int = PassPeriod.civil(day: dag).month
        return månader[max(0, min(11, m - 1))]
    }

    /// "vecka 47".
    static func vecka(_ dag: Int) -> String { "vecka \(PassPeriod.isoWeek(day: dag))" }

    /// BESLUT B135. Passets tid i statusraden: "24:10" under en timme, "1:05:09" från en timme.
    static func passtid(_ sekunder: TimeInterval) -> String {
        let s: Int = max(0, Int(sekunder.rounded(.down)))
        if s < 3_600 { return String(format: "%d:%02d", s / 60, s % 60) }
        return String(format: "%d:%02d:%02d", s / 3_600, (s % 3_600) / 60, s % 60)
    }

    /// Timmar:minuter, hela minuter: "1:40".
    static func timmar(_ sekunder: TimeInterval) -> String {
        let m: Int = max(0, Int((sekunder / 60).rounded()))
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// "Idag", "Igår", veckodagen under en vecka, annars "12 nov".
    static func veckodag(_ dag: Int, idag: Int) -> String {
        let skillnad: Int = idag - dag
        if skillnad == 0 { return "Idag" }
        if skillnad == 1 { return "Igår" }
        if skillnad >= 2 && skillnad <= 6 { return dagar[plats(dag)] }
        return "\(PassPeriod.civil(day: dag).day) \(månad(dag))"
    }

    /// Texten under en stapel: veckodag (V), veckonummer (M) eller månad (6M, Å).
    static func stapel(_ b: PassPeriod.Bucket, period: PassPeriod) -> String {
        switch period {
        case .week: return dagarKort[plats(b.startDay)]
        case .month: return "v \(PassPeriod.isoWeek(day: b.startDay))"
        case .halfYear, .year: return månad(b.startDay)
        }
    }

    static func rubrik(_ ö: PassPeriod.Overview) -> String {
        switch ö.period {
        case .week: return "Den här veckan"
        case .month: return "Fyra veckor"
        case .halfYear: return "Sex månader"
        case .year: return "Tolv månader"
        }
    }

    static func underrad(_ ö: PassPeriod.Overview) -> String {
        var t: String = "\(ö.passes) pass"
        if ö.period != .week { t += " · snitt per vecka " + PassFormat.short(ö.secondsPerWeek) }
        return t
    }
}

// MARK: - Fliken i vila

/// BESLUT B133. Huvudet: "Pass" och veckan till vänster, kartan och steptestet som runda knappar till höger.
struct PassHuvud: View {
    let idag: Int
    let ute: () -> Void
    let steptest: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pass").font(.system(size: 28, weight: .semibold)).foregroundStyle(Tema.text)
                Text(PassFlikText.vecka(idag)).font(.system(size: 28, weight: .semibold)).foregroundStyle(Tema.dim)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button(action: ute) {
                    Image(systemName: "map")
                        .font(.system(size: 16))
                        .foregroundStyle(Tema.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Tema.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Starta pass ute")
                Button(action: steptest) {
                    Image(systemName: "figure.stairs")
                        .font(.system(size: 16))
                        .foregroundStyle(Tema.bg)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Tema.text))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Starta steptest")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// BESLUT B133. Veckokortet: tiden mot snittet och belastningen (eller sträckan) i två rutor, zonerna som en remsa.
/// Hela kortet och pilen öppnar veckans sida.
struct VeckaRutor: View {
    let oversikt: PassWeek.Overview
    let harMaxpuls: Bool
    let öppna: () -> Void

    private func andel(_ nu: Double, _ snitt: Double) -> Double { snitt > 0 ? nu / snitt : 0 }

    var body: some View {
        let nu: PassWeek.Summary = oversikt.current
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Den här veckan").font(.headline).foregroundStyle(Tema.text)
                Text("\(nu.passes) pass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.dim)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 9)
                    .background(Capsule().fill(Tema.card2))
                Spacer(minLength: 0)
                Button(action: öppna) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.text)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Öppna veckan")
            }
            HStack(spacing: 8) {
                ruta("Tid mot ditt snitt", ring: andel(nu.seconds, oversikt.averageSeconds),
                     värde: PassFlikText.timmar(nu.seconds), enhet: "h")
                if harMaxpuls {
                    ruta("Belastning", ring: andel(nu.load, oversikt.averageLoad),
                         värde: String(Int(nu.load.rounded())), enhet: nil)
                } else {
                    ruta("Sträcka", ring: nil, värde: PassRuttFormat.km(nu.meters), enhet: nil)
                }
            }
            if harMaxpuls {
                ZonRemsa(zoner: nu.zones)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture(perform: öppna)
    }

    private func ruta(_ titel: String, ring: Double?, värde: String, enhet: String?) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(titel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tema.text)
                    .padding(.trailing, ring == nil ? 0 : 32)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(värde)
                        .font(.system(size: 26, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Tema.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let e = enhet {
                        Text(e).font(.system(size: 12)).foregroundStyle(Tema.dim)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let r = ring {
                PassRing(andel: r)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Tema.card2, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// BESLUT B133 · BESLUT B121. Ett hittat pass som ett kort med streckad kant: titel, tid och längd, Lägg till och Inte ett pass.
struct PassForslagKort: View {
    let förslag: [PassDetection.Candidate]
    let nu: Date
    let läggTill: (PassDetection.Candidate) -> Void
    let inteEtt: (PassDetection.Candidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Hittat i bandet").font(.headline).foregroundStyle(Tema.text)
                Spacer(minLength: 0)
                Text("\(förslag.count) förslag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tema.dim)
            }
            ForEach(förslag, id: \.startMinute) { (f: PassDetection.Candidate) in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        PassIkonruta(symbol: f.kind.map { (k: PassKind) -> String in PassFormat.symbol(k) } ?? "questionmark")
                        VStack(alignment: .leading, spacing: 2) {
                            Text((f.kind?.displayName ?? "Pass") + "?")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Tema.text)
                            Text(PassForslagText.tid(f, nu: nu))
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.dim)
                        }
                        Spacer(minLength: 8)
                        Text("\(f.minutes) min")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tema.text)
                    }
                    HStack(spacing: 8) {
                        Button { läggTill(f) } label: {
                            Text("Lägg till")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Tema.bg)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(Capsule().fill(Tema.text))
                        }
                        .buttonStyle(.plain)
                        Button { inteEtt(f) } label: {
                            Text("Inte ett pass")
                                .font(.system(size: 14))
                                .foregroundStyle(Tema.text)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Tema.dim, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// BESLUT B133. Bladet "Vad ska du göra?": Ute, Inne eller Steptest, och Starta.
struct StartBlad: View {
    enum Val { case ute, inne, steptest }

    let starta: (StartBlad.Val) -> Void
    @State private var val: Val = .inne

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vad ska du göra?").font(.system(size: 22, weight: .semibold)).foregroundStyle(Tema.text)
            HStack(spacing: 8) {
                ruta(.ute, "figure.run", "Ute", "med karta")
                ruta(.inne, "dumbbell", "Inne", nil)
                ruta(.steptest, "figure.stairs", "Steptest", "10 min")
            }
            Text("Typen väljs när passet sparas, som i dag. Här väljs bara om kartan ska med.")
                .font(.footnote)
                .foregroundStyle(Tema.dim)
            Button { starta(val) } label: {
                Text("Starta")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tema.bg)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Tema.text))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.medium])
        .presentationBackground(Tema.card)
    }

    private func ruta(_ v: Val, _ symbol: String, _ namn: String, _ rad: String?) -> some View {
        let på: Bool = val == v
        return Button { val = v } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol).font(.system(size: 18))
                Spacer(minLength: 0)
                Text(namn).font(.system(size: 15, weight: .semibold))
                Text(rad ?? " ").font(.system(size: 11)).opacity(på ? 0.7 : 1)
            }
            .foregroundStyle(på ? Tema.bg : Tema.text)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(på ? Tema.text : Tema.card2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Veckans sida

/// BESLUT B134 · METOD M78. Träningen över tid: V, M, 6M eller Å, med staplar delade i zoner och tid per pulszon.
struct TraningSida: View {
    let pass: [Pass]
    let maxpuls: Double?
    let idag: Int
    @State private var vald: PassPeriod

    init(pass: [Pass], maxpuls: Double?, idag: Int, period: PassPeriod = .month) {
        self.pass = pass
        self.maxpuls = maxpuls
        self.idag = idag
        _vald = State(initialValue: period)
    }

    var body: some View {
        let ö: PassPeriod.Overview = PassVecka.period(pass, period: vald, maxpuls: maxpuls, idag: idag)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer(minLength: 0)
                    PassPiller(val: [(PassPeriod.week, "V"), (PassPeriod.month, "M"),
                                     (PassPeriod.halfYear, "6M"), (PassPeriod.year, "Å")],
                               valt: vald, välj: { (p: PassPeriod) -> Void in vald = p })
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(PassFlikText.rubrik(ö)).font(.system(size: 14)).foregroundStyle(Tema.dim)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(PassFlikText.timmar(ö.seconds))
                            .font(.system(size: 52, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(Tema.text)
                        Text("h").font(.system(size: 18)).foregroundStyle(Tema.dim)
                    }
                    Text(PassFlikText.underrad(ö)).font(.system(size: 13)).foregroundStyle(Tema.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

                TraningStaplar(oversikt: ö)
                    .padding(.top, 10)

                zonkort(ö)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Tema.bg)
        .navigationTitle("Träningen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func zonkort(_ ö: PassPeriod.Overview) -> some View {
        let med: [PassZones.Share] = ö.zones.filter { (z: PassZones.Share) -> Bool in z.zone >= 1 && z.seconds > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Tid per pulszon").font(.headline).foregroundStyle(Tema.text)
            if maxpuls == nil {
                Text("Pulszonerna visas när maxpulsen är känd.")
                    .font(.footnote)
                    .foregroundStyle(Tema.dim)
            } else {
                ZonRemsa(zoner: ö.zones, höjd: 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(med, id: \.zone) { (z: PassZones.Share) in
                        HStack(spacing: 5) {
                            Circle().fill(PassZonTrappa.color(z.zone)).frame(width: 8, height: 8)
                            Text(PassZonText.namn(z.zone) + " " + PassFlikText.timmar(z.seconds))
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.dim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

/// En vågrät linje, för snittet.
private struct Snittlinje: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// BESLUT B134. Staplarna för en period: delade i zoner (zon 1 underst), snittet streckat, den sista med en ring.
struct TraningStaplar: View {
    let oversikt: PassPeriod.Overview

    private let höjd: CGFloat = 130

    var body: some View {
        let staplar: [PassPeriod.Bucket] = oversikt.buckets
        let störst: Double = max(1, staplar.map { (b: PassPeriod.Bucket) -> Double in b.summary.seconds }.max() ?? 1)
        let snittY: CGFloat = höjd - höjd * CGFloat(oversikt.averageSeconds / störst)
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(staplar.enumerated()), id: \.offset) { (e: (offset: Int, element: PassPeriod.Bucket)) in
                    let sista: Bool = e.offset == staplar.count - 1
                    VStack(spacing: 6) {
                        stapel(e.element, störst: störst, sista: sista)
                            .frame(height: höjd, alignment: .bottom)
                        Text(PassFlikText.stapel(e.element, period: oversikt.period))
                            .font(.system(size: 11, weight: sista ? .semibold : .regular))
                            .foregroundStyle(sista ? Tema.text : Tema.dim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if oversikt.averageSeconds > 0 {
                Snittlinje()
                    .stroke(Tema.text, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                    .offset(y: snittY)
                Text("snitt")
                    .font(.system(size: 10))
                    .foregroundStyle(Tema.dim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: snittY - 14)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stapel(_ b: PassPeriod.Bucket, störst: Double, sista: Bool) -> some View {
        let s: Double = b.summary.seconds
        let h: CGFloat = s > 0 ? max(4, höjd * CGFloat(s / störst)) : 4
        let zoner: [PassZones.Share] = b.summary.zones.filter { (z: PassZones.Share) -> Bool in z.seconds > 0 }
        let zonsumma: Double = max(1, zoner.reduce(0) { (a: Double, z: PassZones.Share) -> Double in a + z.seconds })
        return Group {
            if s <= 0 {
                Tema.card2
            } else if zoner.isEmpty {
                Color(rgb: 0x4A565D)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(zoner.reversed()), id: \.zone) { (z: PassZones.Share) in
                        PassZonTrappa.color(z.zone)
                            .frame(height: h * CGFloat(z.seconds / zonsumma))
                    }
                }
            }
        }
        .frame(maxWidth: 34)
        .frame(height: h)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Tema.text, lineWidth: sista ? 2 : 0)
                .padding(-3)
        )
    }
}
