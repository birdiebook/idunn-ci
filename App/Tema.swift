import SwiftUI
import Night

/// BESLUT B63 · BESLUT B62
/// Skissens färger (design/skiss.html, :root) som ett tema för hela appen, och de små delarna som vyerna delar:
/// kort, ring, band med prick, teckenförklaring och formaten. Appen är mörk överallt (`.preferredColorScheme(.dark)`
/// vid roten). Siffrorna har fast bredd (`Tema.mono`, BESLUT B93), så att layouten står still när talen byter.
enum Tema {
    static let bg = Color(rgb: 0x0F1214)
    static let card = Color(rgb: 0x171C1F)
    static let card2 = Color(rgb: 0x1F262A)
    static let line = Color.white.opacity(0.05)
    static let track = Color(rgb: 0x2C3438)
    static let ringTrack = Color(rgb: 0x252C30)
    static let band = Color(rgb: 0x3A474E)
    static let still = Color(rgb: 0x4A565D)
    static let text = Color(rgb: 0xE9EEF0)
    static let dim = Color(rgb: 0x9AA5AB)
    static let faint = Color(rgb: 0x5F6A70)
    static let accent = Color(rgb: 0x5FD3FF)
    /// BESLUT B95. Nattens pulskurva: blågrå, lugnare än accenten.
    static let pulse = Color(rgb: 0x8FB6CC)
    /// BESLUT B99. Pulsen i talet vid en markerad minut: samma ton, ljusare, så att talet syns över kurvan.
    static let pulsLjus = Color(rgb: 0xCDE3F0)
    static let green = Color(rgb: 0x36D67A)
    static let yellow = Color(rgb: 0xF0C23B)
    static let red = Color(rgb: 0xEF5B5B)
    static let awake = Color(rgb: 0xC9D1D6)
    static let light = Color(rgb: 0x6C8FD6)
    /// BESLUT B97. Ljusare och mättare än förut (3A4FB8), som syntes dåligt mot bakgrunden och kurvan.
    static let deep = Color(rgb: 0x4A6CF7)
    static let rem = Color(rgb: 0x9B6BFF)

    /// BESLUT B93. Siffror i rundat typsnitt med fast sifferbredd: layouten står still när talen byter, utan
    /// skrivmaskinsutseendet. Namnet står kvar från monospace-tiden.
    static func mono(_ size: CGFloat, _ vikt: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: vikt, design: .rounded).monospacedDigit()
    }

    /// BESLUT B72 · METOD M57. Återhämtningens färg: grön från 67, gul från 34, röd under.
    static func recovery(_ v: Double) -> Color {
        v >= 67 ? green : (v >= 34 ? yellow : red)
    }

    /// BESLUT B71 · METOD M56. Sömnpoängens färg: grön från 85, gul från 70, röd under.
    static func score(_ v: Double) -> Color {
        v >= 85 ? green : (v >= 70 ? yellow : red)
    }

    /// BESLUT B83 · BESLUT B91 · METOD M58. Sömnbristens färg efter läge: grön under 0:45, gul 0:45–1:30, röd över 1:30. Skulden i
    /// timmar; läget räknas på hela minuter, så att färgen följer talet som står utskrivet.
    static func skuld(_ timmar: Double) -> Color { Skuldläge(timmar).färg }

    /// BESLUT B83 · METOD M58. Sömn mot behov efter läge: grön från 85 %, grå från 70 %, orange under.
    static func motBehov(_ procent: Double) -> Color { Behovsläge(procent).färg }
}

/// BESLUT B83 · BESLUT B91 · METOD M58. Sömnbristens tre lägen, bäst först: låg under 0:45, måttlig 0:45–1:30, hög över 1:30.
enum Skuldläge: Int, CaseIterable {
    case låg, måttlig, hög

    /// Skulden i timmar, avrundad till hela minuter som `Fmt.hm`.
    init(_ timmar: Double) {
        let minuter: Double = (timmar * 60).rounded()
        self = minuter < 45 ? .låg : (minuter <= 90 ? .måttlig : .hög)
    }

    var namn: String {
        switch self {
        case .låg: return "Låg"
        case .måttlig: return "Måttlig"
        case .hög: return "Hög"
        }
    }

    var gräns: String {
        switch self {
        case .låg: return "under 0:45"
        case .måttlig: return "0:45–1:30"
        case .hög: return "över 1:30"
        }
    }

    var färg: Color {
        switch self {
        case .låg: return Tema.green
        case .måttlig: return Tema.yellow
        case .hög: return Tema.red
        }
    }
}

/// BESLUT B83 · METOD M58. Sömn mot behov i tre lägen, bäst först: optimal från 85 %, tillräcklig 70–85 %, dålig under
/// 70 %. Procent av nattens behov, avrundat till hela procent.
enum Behovsläge: Int, CaseIterable {
    case optimal, tillräcklig, dålig

    init(_ procent: Double) {
        let p: Double = procent.rounded()
        self = p >= 85 ? .optimal : (p >= 70 ? .tillräcklig : .dålig)
    }

    var namn: String {
        switch self {
        case .optimal: return "Optimal"
        case .tillräcklig: return "Tillräcklig"
        case .dålig: return "Dålig"
        }
    }

    var gräns: String {
        switch self {
        case .optimal: return "85–100 %"
        case .tillräcklig: return "70–85 %"
        case .dålig: return "under 70 %"
        }
    }

    var färg: Color {
        switch self {
        case .optimal: return Tema.green
        case .tillräcklig: return Tema.dim
        // Orange: ingen annan färg i temat, och varken gul (sömnbristen) eller röd (larm).
        case .dålig: return Color(rgb: 0xF08A3C)
        }
    }
}

/// BESLUT B83. Dagar per läge: antalet dagar med värde i varje läge, i lägenas ordning. Dagar utan värde räknas inte.
enum Lägesräkning {
    static func antal<L: CaseIterable & RawRepresentable>(_ värden: [Double?], _ läge: (Double) -> L) -> [Int]
        where L.RawValue == Int {
        var ut: [Int] = Array(repeating: 0, count: L.allCases.count)
        for v in värden {
            guard let v = v else { continue }
            let i: Int = läge(v).rawValue
            if i >= 0 && i < ut.count { ut[i] += 1 }
        }
        return ut
    }
}

extension View {
    /// Ett kort i skissens form: rundade hörn 16, ytan `Tema.card`.
    func kort(_ luft: CGFloat = 14) -> some View {
        self.padding(luft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Ett kort med rader: tätt i sidled, raderna har egen luft.
    func radkort() -> some View {
        self.padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Formaten: decimalkomma och klockslag räknade för hand, så att telefonens språk inte spelar in.
enum Fmt {
    static func num(_ v: Double, _ decimaler: Int = 0) -> String {
        var f: Double = 1
        for _ in 0..<decimaler { f *= 10 }
        var r: Double = (v * f).rounded() / f
        if r == 0 { r = 0 }
        let text: String = String(format: "%.\(decimaler)f", r)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// 472 minuter blir "7:52".
    static func hm(minutes: Double) -> String {
        let t: Int = Int(minutes.rounded())
        let a: Int = abs(t)
        return (t < 0 ? "-" : "") + "\(a / 60):" + pad2(a % 60)
    }

    static func hm(hours: Double) -> String { hm(minutes: hours * 60) }

    /// BESLUT B65. En osäkerhet i timmar som " ± 20 min".
    static func plusMinus(hours: Double) -> String { " ± \(Int((hours * 60).rounded())) min" }

    /// Minuter efter midnatt (negativa före) som klockslag: 418 blir "06:58", −63 blir "22:57".
    static func clock(minutes: Double) -> String {
        let t: Int = Int(minutes.rounded())
        let m: Int = ((t % 1_440) + 1_440) % 1_440
        return pad2(m / 60) + ":" + pad2(m % 60)
    }

    /// Timmar efter midnatt som klockslag.
    static func clock(hours: Double) -> String { clock(minutes: hours * 60) }

    /// Ett värde med tecken och en decimal, och gradtecken: "+0,1°".
    static func signedDegrees(_ v: Double) -> String {
        let r: Double = (v * 10).rounded() / 10
        let tecken: String = r > 0 ? "+" : ""
        return tecken + num(r, 1) + "°"
    }

    static func weekday(_ d: WakeDay) -> String {
        let namn: [String] = ["sön", "mån", "tis", "ons", "tor", "fre", "lör"]
        return namn[((d.daysSince1970 % 7) + 7 + 4) % 7]
    }

    private static let månader: [String] = ["jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov",
                                            "dec"]

    /// "4 nov".
    static func dayMonth(_ d: WakeDay) -> String {
        var kal: Calendar = Calendar(identifier: .gregorian)
        kal.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let c: DateComponents = kal.dateComponents([.day, .month], from: d.noonUTC)
        let m: Int = max(0, min(11, (c.month ?? 1) - 1))
        return "\(c.day ?? 1) \(månader[m])"
    }

    /// Klockslaget för ett ögonblick, i telefonens zon.
    static func clock(time: TimeInterval) -> String {
        Date(timeIntervalSince1970: time).formatted(.dateTime.hour().minute())
    }
}

/// En liten rubrik över ett avsnitt: versaler, glesa bokstäver.
struct Sektion: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Tema.dim)
            .padding(.top, 14)
            .padding(.horizontal, 2)
    }
}

/// Rubriken i ett kort: versaler, med ett värde till höger om det finns.
struct Kortrubrik: View {
    let text: String
    var höger: String? = nil
    var högerFärg: Color = Tema.text

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Tema.dim)
            Spacer(minLength: 4)
            if let h = höger {
                Text(h)
                    .font(Tema.mono(11))
                    .foregroundStyle(högerFärg)
            }
        }
    }
}

/// Teckenförklaring: en ruta (eller prick) och ett ord.
struct Tecken: View {
    let färg: Color
    let text: String
    var rund = false
    var smal = false

    var body: some View {
        HStack(spacing: 4) {
            if rund {
                Circle().fill(färg).frame(width: 8, height: 8)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(färg).frame(width: 8, height: smal ? 2 : 8)
            }
            Text(text)
        }
    }
}

/// Stadiernas teckenförklaring: vaken, lätt, djup, REM.
///
/// BESLUT B83. Med `välj` är varje stadium en knapp (Natten): ett tryck färgar kurvan där stadiet ligger, samma igen
/// släcker, ett annat byter. Det valda står i en ruta, de andra dämpas.
struct StadieTecken: View {
    var valt: SleepStage? = nil
    var välj: ((SleepStage) -> Void)? = nil

    private static let stadier: [(SleepStage, String)] = [(.wake, "vaken"), (.light, "lätt"), (.deep, "djup"),
                                                          (.rem, "REM")]

    var body: some View {
        HStack(spacing: välj == nil ? 12 : 4) {
            ForEach(0..<Self.stadier.count, id: \.self) { (i: Int) in
                let s: (SleepStage, String) = Self.stadier[i]
                if let välj = välj {
                    Button {
                        välj(s.0)
                    } label: {
                        Tecken(färg: NattRitning.färg(s.0), text: s.1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(valt == s.0 ? Tema.card2 : Color.clear, in: Capsule())
                            .foregroundStyle(valt == s.0 ? Tema.text : Tema.dim)
                            .opacity(valt == nil || valt == s.0 ? 1 : 0.45)
                            // användaren 2026-11-10: knapparna jämnt utspridda över bredden, inte samlade till vänster.
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(Tryckyta())
                    .accessibilityAddTraits(valt == s.0 ? .isSelected : [])
                } else {
                    Tecken(färg: NattRitning.färg(s.0), text: s.1)
                }
            }
            if välj == nil { Spacer(minLength: 0) }
        }
        .font(.system(size: 10))
        .foregroundStyle(Tema.dim)
    }
}

/// BESLUT B93. En stapel delad i delar efter storlek, med en smal springa mellan dem. Utan något värde står spåret tomt.
struct Delstapel: View {
    let delar: [(Double, Color)]
    var höjd: CGFloat = 16

    var body: some View {
        let ritade: [(Double, Color)] = delar.filter { (d: (Double, Color)) -> Bool in d.0 > 0 }
        let total: Double = ritade.reduce(0) { (s: Double, d: (Double, Color)) -> Double in s + d.0 }
        return GeometryReader { (g: GeometryProxy) in
            let springa: CGFloat = 2
            let bredd: CGFloat = max(0, g.size.width - springa * CGFloat(max(0, ritade.count - 1)))
            if total > 0 {
                HStack(spacing: springa) {
                    ForEach(0..<ritade.count, id: \.self) { (i: Int) in
                        Rectangle()
                            .fill(ritade[i].1)
                            .frame(width: bredd * CGFloat(ritade[i].0 / total))
                    }
                }
            } else {
                Rectangle().fill(Tema.track)
            }
        }
        .frame(height: höjd)
        .clipShape(Capsule())
    }
}

/// En ring med en båge: tom (bara spåret) när värdet saknas.
struct Ring: View {
    let procent: Double?
    let färg: Color
    var storlek: CGFloat = 96
    var linje: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Tema.ringTrack, lineWidth: linje)
            if let p = procent {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(p, 0), 100) / 100))
                    .stroke(färg, style: StrokeStyle(lineWidth: linje, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(linje / 2)
        .frame(width: storlek, height: storlek)
    }
}

/// Ett huvudtal i sin ring (spåret H): med ett streck och en tom ring när talet saknas, lika stor ändå.
struct HuvudRing: View {
    let värde: Int?
    let färg: Color
    var storlek: CGFloat = 96
    var linje: CGFloat = 8
    var siffra: CGFloat = 28

    var body: some View {
        ZStack {
            Ring(procent: värde.map { (v: Int) -> Double in Double(v) }, färg: färg, storlek: storlek, linje: linje)
            Text(värde.map { (v: Int) -> String in "\(v)" } ?? "–")
                .font(Tema.mono(siffra, .bold))
                // BESLUT B77. Siffran är alltid ljusgrå; ringen bär färgen.
                .foregroundStyle(värde == nil ? Tema.faint : Tema.awake)
        }
    }
}

/// Ett mått som en prick på sitt eget band (METOD M19): namn, band med prick, värde. Utan värde står axeln tom och
/// ett streck. Utan område (baslinjen byggs) hamnar pricken på axeln som Morgon räknat den.
struct BandRad: View {
    let namn: String
    var text: String? = nil
    var värde: Double? = nil
    var område: ClosedRange<Double>? = nil
    var axel: ClosedRange<Double>? = nil
    /// 1 när högre är bättre, −1 när lägre är bättre, 0 när ingen riktning är bättre.
    var bra: Int = 0
    var luft: Double = 1.6
    var vidare = false
    /// Sista raden i ett kort har ingen skiljelinje.
    var sista = false
    /// BESLUT B69. Området bygger på få nätter: bandet ritas som ett utkast (ljusare, streckad kant), utan text.
    var bygger = false

    private func plats(_ v: Double) -> Double {
        if let o = område {
            let bredd: Double = o.upperBound - o.lowerBound > 0 ? o.upperBound - o.lowerBound : 1
            let a: Double = o.lowerBound - bredd * luft
            let b: Double = o.upperBound + bredd * luft
            return min(0.98, max(0.02, (v - a) / (b - a)))
        }
        if let t = axel, t.upperBound > t.lowerBound {
            return min(0.98, max(0.02, (v - t.lowerBound) / (t.upperBound - t.lowerBound)))
        }
        return 0.5
    }

    private var inom: Bool {
        guard let v = värde, let o = område else { return true }
        return o.contains(v)
    }

    private var sämre: Bool {
        guard let v = värde, let o = område, !o.contains(v), bra != 0 else { return false }
        return (v > o.upperBound) != (bra > 0)
    }

    private var pricken: Color {
        if inom { return Tema.text }
        return sämre ? Tema.yellow : Tema.accent
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(namn)
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
                    .minimumScaleFactor(0.8)
                if vidare {
                    Text("›").foregroundStyle(Tema.faint)
                }
            }
            .lineLimit(1)
            .frame(width: 96, alignment: .leading)
            GeometryReader { (g: GeometryProxy) in
                let w: CGFloat = g.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Tema.track).frame(height: 2)
                    if let o = område {
                        let x0: CGFloat = CGFloat(plats(o.lowerBound)) * w
                        let x1: CGFloat = CGFloat(plats(o.upperBound)) * w
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Tema.band.opacity(bygger ? 0.45 : 1))
                            .overlay {
                                if bygger {
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(Tema.dim, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                }
                            }
                            .frame(width: max(2, x1 - x0), height: 10)
                            .offset(x: x0)
                    }
                    if let v = värde {
                        ZStack {
                            Circle().fill(Tema.card).frame(width: 18, height: 18)
                            Circle().fill(pricken).frame(width: 12, height: 12)
                        }
                        .offset(x: CGFloat(plats(v)) * w - 9)
                    }
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            Text(text ?? "–")
                .font(Tema.mono(15))
                .foregroundStyle(text == nil ? Tema.faint : (inom ? Tema.text : pricken))
                .lineLimit(1)
                // "14,0 min/h" kapades i en ruta på 62 pt (provet 2026-11-07): talet tar den plats det behöver,
                // och bandet krymper.
                .fixedSize()
                .frame(minWidth: 62, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !sista { Rectangle().fill(Tema.line).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }
}

/// En kolumn av två: namn till vänster, tal till höger (skissens `kv`).
struct Nyckelrad: View {
    let namn: String
    let värde: String
    var färg: Color? = nil
    /// En linje ovanför och luft under, för summan längst ner.
    var delare = false

    var body: some View {
        HStack {
            Text(namn)
            Spacer(minLength: 4)
            Text(värde)
                .font(Tema.mono(12))
                .foregroundStyle(värde == "–" ? Tema.faint : (färg ?? Tema.text))
        }
        .font(.system(size: 12))
        .foregroundStyle(Tema.dim)
        .padding(.top, delare ? 8 : 0)
        .overlay(alignment: .top) {
            if delare { Rectangle().fill(Tema.line).frame(height: 1) }
        }
    }
}

/// Ett tryckbart kort: hela ytan svarar, utan knappens egen färg.
struct Tryckyta: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
