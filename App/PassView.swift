import SwiftUI
import Charts
import UIKit
import Fitness
import Pass
import SleepNeed

/// BESLUT B58 · METOD M47
/// Fliken Pass: en knapp startar ett pass med puls (bastu, dusch, styrka, kondition,
/// promenad), vyn visar tid, stor puls och kurvan, och efter Stopp mäts pulsen vidare i 10
/// minuter så att återhämtningen syns. Lite text, stora siffror. `PassScreen` tar all sin
/// data som värden (som `MorningCardScreen`), så att den går att rita i provet; `PassView`
/// kopplar den till `PassController`.
struct PassView: View {
    @ObservedObject private var controller = PassController.shared
    /// BESLUT B110. Konditionen: kortet, skärmen och steptestets värden.
    @ObservedObject private var kondition = KonditionModell.shared

    /// BESLUT B126. Maxpulsen för veckans belastning och zoner, som för sidorna.
    private var veckaMaxpuls: Double? {
        kondition.maxpuls ?? PassLoad.maxPulse(from: controller.saved)
    }

    var body: some View {
        PassScreen(phase: controller.state.phase, pass: controller.state.pass, now: controller.now,
                   saved: controller.saved,
                   actions: PassActions(start: { controller.start() },
                                        stop: { controller.stop() },
                                        setKind: { controller.setKind($0) },
                                        finish: { controller.finish() },
                                        delete: { controller.delete($0) },
                                        export: { controller.exportFile($0) },
                                        startUte: { controller.startUte() },
                                        exportMedSpår: { controller.exportFile($0, medSpår: true) },
                                        startSteptest: { controller.startSteptest(höjdCm: $0) },
                                        sättProfil: { kondition.sätt(profil: $0) },
                                        läggTillFörslag: { controller.läggTill($0, typ: $1) },
                                        taBortFörslag: { controller.taBortFörslag($0) }),
                   kondition: PassKondition(modell: kondition, slut: controller.steptestSlut,
                                          slag: controller.steptestSlag),
                   förslag: controller.förslag,
                   vecka: PassVecka.oversikt(controller.saved, maxpuls: veckaMaxpuls),
                   veckaMedMaxpuls: veckaMaxpuls != nil)
        .alert("Pass", isPresented: Binding(
            get: { controller.problem != nil },
            set: { if !$0 { controller.problem = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.problem ?? "")
        }
    }
}

/// Det som knapparna gör. Standardvärdena gör ingenting, så att provet kan rita en vy utan passet.
struct PassActions {
    var start: () -> Void = {}
    var stop: () -> Void = {}
    var setKind: (PassKind) -> Void = { _ in }
    var finish: () -> Void = {}
    var delete: (Pass) -> Void = { _ in }
    /// Passets zip i en tillfällig mapp, för delningsbladet; `nil` när den inte gick att skriva.
    var export: (Pass) -> URL? = { _ in nil }
    /// BESLUT B107 · BESLUT B110. Start ute: passet läser också telefonens plats.
    var startUte: () -> Void = {}
    /// BESLUT B107 · BESLUT B110. Som `export`, men med spåret (positionerna) i filen.
    var exportMedSpår: (Pass) -> URL? = { _ in nil }
    /// BESLUT B110 · METOD M62. Start av ett steptest på ett steg med den här höjden (cm).
    var startSteptest: (Double) -> Void = { _ in }
    /// BESLUT B110. Profilen ändrades i formuläret som bladet före steptestet länkar till.
    var sättProfil: (FitnessProfile) -> Void = { _ in }
    /// BESLUT B121. Lägger ett förslag till som ett pass av vald typ.
    var läggTillFörslag: (PassDetection.Candidate, PassKind) -> Void = { _, _ in }
    /// BESLUT B121. Tar bort ett förslag för gott.
    var taBortFörslag: (PassDetection.Candidate) -> Void = { _ in }
}

/// Formen på passets siffror: samma överallt, så att en tid alltid läses likadant.
enum PassFormat {
    /// BESLUT B117 · METOD M68. Raden i ett pass där bandet inte hörs, och i ett sparat pass med luckor.
    static let väntarPåHistoriken = "Pulsen fylls i när bandet har lämnat sin historik"

    /// `hh:mm:ss`.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// `mm:ss`, för nedräkningen.
    static func minutes(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "18 min" eller "1 h 05 min", för listan.
    static func short(_ seconds: TimeInterval) -> String {
        let m = max(0, Int((seconds / 60).rounded()))
        return m < 60 ? "\(m) min" : String(format: "%d h %02d min", m / 60, m % 60)
    }

    static func bpm(_ v: Double?) -> String { v.map { String(Int($0.rounded())) } ?? "–" }
    static func bpm(_ v: Int?) -> String { v.map { String($0) } ?? "–" }

    static func symbol(_ kind: PassKind?) -> String {
        switch kind {
        case .bastu: return "flame"
        case .dusch: return "shower"
        case .styrka: return "dumbbell"
        case .kondition: return "figure.run"
        case .promenad: return "figure.walk"
        case nil: return "heart"
        }
    }
}

/// Hela fliken som värden. Fasen styr vilket läge som visas: vila, pågår, efter stopp.
struct PassScreen: View {
    let phase: PassRecorder.Phase
    let pass: Pass?
    let now: Date
    let saved: [Pass]
    var actions = PassActions()
    /// BESLUT B110. Konditionen och steptestets värden.
    var kondition = PassKondition()
    /// BESLUT B121 · METOD M69. Förslag ur bandets historik, senaste först.
    let förslag: [PassDetection.Candidate]
    /// BESLUT B126 · METOD M72. Veckan hittills och de fyra före; `nil` ger inget kort.
    let vecka: PassWeek.Overview?
    let veckaMedMaxpuls: Bool

    @State private var openedID: UUID?
    @State private var valtFörslag: Förslagsval?
    @State private var steptestBlad = false
    @State private var konditionÖppen = false
    @State private var startBlad = false
    @State private var traningÖppen = false
    @State private var visaAlla = false

    /// Egen init, så att `@State private` inte kan göra den osynlig för andra filer.
    init(phase: PassRecorder.Phase, pass: Pass?, now: Date, saved: [Pass], actions: PassActions = PassActions(),
         kondition: PassKondition = PassKondition(), förslag: [PassDetection.Candidate] = [],
         vecka: PassWeek.Overview? = nil, veckaMedMaxpuls: Bool = false) {
        self.phase = phase
        self.pass = pass
        self.now = now
        self.saved = saved
        self.actions = actions
        self.kondition = kondition
        self.förslag = förslag
        self.vecka = vecka
        self.veckaMedMaxpuls = veckaMedMaxpuls
    }

    private struct Förslagsval: Identifiable {
        let id: Int
        let förslag: PassDetection.Candidate
    }

    /// Så länge utan pulsprov som visar raden "Bandet hörs inte".
    static let silentSeconds: TimeInterval = 10

    var body: some View {
        NavigationStack {
            Group {
                // BESLUT B124. Medan ett pass pågår tar sidorna hela höjden; Stopp ligger fast under dem.
                if phase == .running, let p = pass {
                    PassPågårSidor(pass: p, now: now,
                                   maxpuls: kondition.maxpuls?.bpm ?? PassLoad.maxPulse(from: saved),
                                   nu: p.isStepTest ? AnyView(steptestNu(p)) : nil,
                                   stopp: actions.stop)
                } else {
                    ScrollView {
                        VStack(spacing: vila ? 14 : 20) {
                            switch phase {
                            case .idle, .done:
                                restView
                            case .running:
                                EmptyView()
                            case .after:
                                if let p = pass { afterView(p) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(vila ? Tema.bg : Color.clear)
                    // BESLUT B133. Start ligger fast ovanför flikarna och öppnar bladet Vad ska du göra?
                    .safeAreaInset(edge: .bottom) {
                        if vila {
                            Button { startBlad = true } label: {
                                Text("Starta pass")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Tema.bg)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(RoundedRectangle(cornerRadius: 18).fill(Tema.text))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Starta pass")
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity)
                            .background(Tema.bg)
                        }
                    }
                }
            }
            .navigationTitle("Pass")
            .navigationBarTitleDisplayMode(.inline)
            // BESLUT B133. I vila har fliken ett eget huvud; under ett pass och efteråt står rubriken kvar.
            .toolbar(vila ? .hidden : .automatic, for: .navigationBar)
            .navigationDestination(item: $openedID) { id in
                if let p = saved.first(where: { $0.id == id }) {
                    PassDetail(pass: p, actions: actions, maxPulse: PassLoad.maxPulse(from: saved),
                               konditionMaxpuls: kondition.maxpuls?.bpm, close: { openedID = nil })
                }
            }
            // BESLUT B134. Veckokortet öppnar veckans sida.
            .navigationDestination(isPresented: $traningÖppen) {
                TraningSida(pass: saved,
                            maxpuls: kondition.maxpuls?.bpm ?? PassLoad.maxPulse(from: saved),
                            idag: KonditionModell.idag(nu: now))
            }
            // BESLUT B110. Kortet Kondition öppnar skärmen med referensen och mätningarna.
            .navigationDestination(isPresented: $konditionÖppen) {
                if let v = kondition.visat {
                    KonditionSkärm(visat: v, mätningar: kondition.mätningar, nivåpuls: kondition.nivåpuls,
                                   referens: kondition.referens, tempopuls: kondition.tempopuls)
                }
            }
        }
        // BESLUT B133. Bladet Vad ska du göra?
        .sheet(isPresented: $startBlad) {
            StartBlad(starta: { (v: StartBlad.Val) -> Void in
                startBlad = false
                switch v {
                case .ute:
                    actions.startUte()
                case .inne:
                    actions.start()
                case .steptest:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { steptestBlad = true }
                }
            })
        }
        // BESLUT B110 · METOD M62. Bladet före steptestet.
        .sheet(isPresented: $steptestBlad) {
            SteptestStart(höjdCm: kondition.steghöjd, maxpuls: kondition.maxpuls, profil: kondition.profil,
                          onProfil: actions.sättProfil,
                          onStarta: { (höjd: Double) -> Void in
                              steptestBlad = false
                              actions.startSteptest(höjd)
                          })
                .presentationDetents([.large])
                .presentationBackground(Tema.bg)
        }
        // BESLUT B121. Bladet för ett förslag: välj typ och lägg till, eller ta bort.
        .sheet(item: $valtFörslag) { (val: Förslagsval) in
            FörslagBlad(förslag: val.förslag, nu: now,
                        läggTill: { (typ: PassKind) -> Void in
                            actions.läggTillFörslag(val.förslag, typ)
                            valtFörslag = nil
                        },
                        taBort: {
                            actions.taBortFörslag(val.förslag)
                            valtFörslag = nil
                        })
                .presentationDetents([.medium])
                .presentationBackground(Tema.bg)
        }
        .sensoryFeedback(.impact, trigger: phase)
    }

    // MARK: Vila

    private var vila: Bool { phase == .idle || phase == .done }

    private var passIdag: Int { KonditionModell.idag(nu: now) }

    private var restView: some View {
        VStack(spacing: 14) {
            PassHuvud(idag: passIdag,
                      ute: actions.startUte,
                      steptest: { steptestBlad = true })

            // BESLUT B126 · BESLUT B133. Veckan hittills i två rutor; hela kortet öppnar veckans sida.
            if let v = vecka, v.hasTraining {
                VeckaRutor(oversikt: v, harMaxpuls: veckaMedMaxpuls, öppna: { traningÖppen = true })
            }

            // BESLUT B110. Konditionen som ett kort när ett tal finns.
            if let v = kondition.visat {
                KonditionKort(visat: v, öppna: { konditionÖppen = true })
            }

            // BESLUT B121 · METOD M69 · BESLUT B133. Förslag ur bandets historik som ett streckat kort.
            if !förslag.isEmpty {
                PassForslagKort(förslag: förslag, nu: now,
                                läggTill: { (f: PassDetection.Candidate) -> Void in
                                    if let typ = f.kind {
                                        actions.läggTillFörslag(f, typ)
                                    } else {
                                        valtFörslag = Förslagsval(id: f.startMinute, förslag: f)
                                    }
                                },
                                inteEtt: { (f: PassDetection.Candidate) -> Void in actions.taBortFörslag(f) })
            }

            if !saved.isEmpty {
                let synliga: [Pass] = visaAlla ? saved : Array(saved.prefix(5))
                let mp: Double? = kondition.maxpuls?.bpm ?? PassLoad.maxPulse(from: saved)
                HStack {
                    Text("Senaste passen").font(.headline).foregroundStyle(Tema.text)
                    Spacer(minLength: 0)
                    if saved.count > 5 {
                        Button { visaAlla.toggle() } label: {
                            Text(visaAlla ? "Färre" : "Alla")
                                .font(.system(size: 13))
                                .foregroundStyle(Tema.dim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
                VStack(spacing: 8) {
                    ForEach(synliga) { (p: Pass) in
                        Button { openedID = p.id } label: {
                            PassRow(pass: p, maxpuls: kondition.maxpuls?.bpm, zonMaxpuls: mp, idag: passIdag)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Pågår

    /// Orden i takten: två steg upp och två ner, i takt med klicket.
    private static let takt: [String] = ["upp", "upp", "ner", "ner"]

    /// BESLUT B111 · METOD M62. Medan steptestet pågår: fem streck för nivåerna, nivån och tiden till nästa, den stora
    /// pulsen, gränsen där testet stannar, ett kort med takten (ordet som gäller just nu markerat, i takt med
    /// metronomen). Kurvan ligger på sidan Översikt och Stopp under sidorna (BESLUT B124).
    private func steptestNu(_ p: Pass) -> some View {
        let sek: TimeInterval = now.timeIntervalSince(p.start)
        let sista: Int = StepTest.cadences.count - 1
        let nivå: Int = min(StepTest.level(at: sek) ?? sista, sista)
        let kvar: TimeInterval = StepTest.levelSeconds * Double(nivå + 1) - sek
        let tid: String = PassRuttFormat.minutes(max(0, kvar.rounded(.up)))
        let nästa: String = nivå == sista ? "klart om " : "nästa nivå om "
        return VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<StepTest.cadences.count, id: \.self) { (i: Int) in
                    Capsule()
                        .fill(i < nivå ? Tema.text : (i == nivå ? Tema.accent : Tema.track))
                        .frame(height: 8)
                }
            }
            VStack(spacing: 2) {
                Text("Nivå \(nivå + 1) av \(StepTest.cadences.count)")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 0) {
                    Text(nästa).foregroundStyle(Tema.dim)
                    Text(tid).font(Tema.mono(17)).foregroundStyle(Tema.text)
                }
                .font(.subheadline)
            }
            bigPulse(p)
            silentRow(p)
            if let m = kondition.maxpuls {
                Text("stannar vid \(SteptestText.gräns(m.bpm))")
                    .font(.subheadline)
                    .foregroundStyle(Tema.dim)
            }
            taktkort(nivå)
        }
    }

    /// BESLUT B111. Kortet med takten: orden upp upp ner ner med det som gäller just nu i accent, fyra streck som följer
    /// samma slag, och stegen per minut. Slaget kommer ur metronomen (`kondition.slag`).
    private func taktkort(_ nivå: Int) -> some View {
        let nu: Int = ((kondition.slag % 4) + 4) % 4
        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { (i: Int) in
                    Text(Self.takt[i])
                        .font(.title3.weight(i == nu ? .bold : .regular))
                        .foregroundStyle(i == nu ? Tema.accent : Tema.faint)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { (i: Int) in
                    Capsule()
                        .fill(i == nu ? Tema.accent : Tema.track)
                        .frame(height: 8)
                }
            }
            Text("\(Int(StepTest.cadences[nivå])) steg per minut")
                .font(.caption)
                .foregroundStyle(Tema.dim)
        }
        .frame(maxWidth: .infinity)
        .kort(16)
        .accessibilityElement(children: .combine)
    }

    // MARK: Efter stopp

    private func afterView(_ p: Pass) -> some View {
        VStack(spacing: 16) {
            // BESLUT B110 · METOD M62. Efter ett steptest står resultatet överst.
            if p.isStepTest {
                SteptestResultat(pass: p, maxpuls: kondition.maxpuls?.bpm, slut: kondition.slut)
            }
            HStack(spacing: 8) {
                Image(systemName: "timer")
                Text(PassFormat.minutes(p.afterRemaining(now: now) ?? 0))
                    .monospacedDigit()
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(.secondary)
            bigPulse(p)
            silentRow(p)
            PassChart(pass: p, now: now)
                .frame(height: 200)
            PassRecovery(pass: p)
            // Ett steptest har redan sin typ.
            if !p.isStepTest {
                KindPicker(selected: p.kind, onSelect: actions.setKind)
            }
            Button(action: actions.finish) {
                Label("Klar", systemImage: "checkmark")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Delar

    /// Pulsen just nu: sista provet om det är färskt, annars ett streck.
    private func bigPulse(_ p: Pass) -> some View {
        let senaste = p.samples.last
        let färskt = senaste.map { now.timeIntervalSince($0.t) <= Self.silentSeconds } ?? false
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "heart.fill").font(.title).foregroundStyle(Tema.red)
            Text(färskt ? PassFormat.bpm(senaste?.bpm) : "–")
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Puls")
    }

    /// "Bandet hörs inte": ingen puls har kommit på 10 sekunder.
    @ViewBuilder
    private func silentRow(_ p: Pass) -> some View {
        let sist = p.samples.last?.t ?? p.start
        if now.timeIntervalSince(sist) > Self.silentSeconds {
            VStack(spacing: 4) {
                Label("Bandet hörs inte", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                // BESLUT B117. Bandet mäter vidare själv: passet fylls när telefonen fått dess historik.
                Text(PassFormat.väntarPåHistoriken)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Sparade pass

/// BESLUT B133. En rad i listan över de senaste passen: ikon, titel, dag, zonremsa, tid och snittpuls.
private struct PassRow: View {
    let pass: Pass
    /// BESLUT B111. Maxpulsen, för konditionstalet i ett steptest; `nil` ger snittet som för andra pass.
    var maxpuls: Double? = nil
    /// BESLUT B133. Maxpulsen för zonremsan; `nil` ger ingen remsa.
    var zonMaxpuls: Double? = nil
    /// Dagen i dag (dagar sedan 1970-01-01), för "Idag", "Igår" och veckodagen.
    var idag: Int = KonditionModell.idag()

    /// Konditionen ur ett steptest, avrundad; `nil` för andra pass, utan maxpuls och när testet var för kort.
    private var konditionstal: Int? {
        guard pass.isStepTest, let m = maxpuls, let r = StepTest.estimate(pass, maxPulse: m) else { return nil }
        return Int(r.value.rounded())
    }

    private var titel: String {
        if pass.isStepTest { return "Steptest" }
        return (pass.kind?.displayName ?? "Pass") + (pass.isOutdoor ? " ute" : "")
    }

    private var undertext: String {
        var t: String = PassFlikText.veckodag(KonditionModell.dag(för: pass), idag: idag)
        if pass.isOutdoor, let sträcka = PassRuttFormat.distanceText(pass) { t += " · " + sträcka }
        return t
    }

    private var zoner: [PassZones.Share] {
        guard let m = zonMaxpuls, !pass.isStepTest else { return [] }
        return PassZones.time(pass.activeSamples, classify: { (bpm: Int) -> Int in PassLoad.zone(bpm: bpm, maxPulse: m) })
    }

    var body: some View {
        HStack(spacing: 12) {
            PassIkonruta(symbol: pass.isStepTest ? "figure.stairs" : PassFormat.symbol(pass.kind))
            VStack(alignment: .leading, spacing: 2) {
                Text(titel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tema.text)
                Text(undertext)
                    .font(.system(size: 12))
                    .foregroundStyle(Tema.dim)
                if zonMaxpuls != nil && !pass.isStepTest {
                    ZonRemsa(zoner: zoner, höjd: 4)
                        .frame(width: 84)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let tal = konditionstal {
                    Text(String(tal))
                        .font(Font.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Tema.text)
                    Text("kondition").font(.system(size: 12)).foregroundStyle(Tema.dim)
                } else {
                    Text("\(Int((pass.duration / 60).rounded())) min")
                        .font(Font.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Tema.text)
                    Text("snitt " + PassFormat.bpm(pass.averageBpm))
                        .font(Font.system(size: 12).monospacedDigit())
                        .foregroundStyle(Tema.dim)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Tema.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Ett sparat pass: kurvan och talen, med Exportera och Ta bort.
struct PassDetail: View {
    let pass: Pass
    var actions = PassActions()
    /// BESLUT B107. Maxpulsen ur de sparade passen, för färgen på rutten; `nil` ger en grå rutt.
    var maxPulse: Double?
    /// BESLUT B110 · METOD M62. Profilens maxpuls, för resultatet av ett steptest; `nil` ger ingen skattning.
    var konditionMaxpuls: Double?
    var close: () -> Void = {}

    @State private var shared: SharedPassFile?
    @State private var confirmDelete = false
    @State private var problem: String?

    init(pass: Pass, actions: PassActions = PassActions(), maxPulse: Double? = nil,
         konditionMaxpuls: Double? = nil, close: @escaping () -> Void = {}) {
        self.pass = pass
        self.actions = actions
        self.maxPulse = maxPulse
        self.konditionMaxpuls = konditionMaxpuls
        self.close = close
    }

    /// Exportera. Ett pass ute har en meny med två val (BESLUT B110): utan spår, och med spår. Ett pass inne en knapp.
    @ViewBuilder
    private var exportKnapp: some View {
        if pass.isOutdoor {
            Menu {
                Button { exportera(medSpår: false) } label: {
                    Label("Exportera", systemImage: "square.and.arrow.up")
                }
                Button { exportera(medSpår: true) } label: {
                    Label("Exportera med spår", systemImage: "location")
                }
            } label: {
                Label("Exportera", systemImage: "square.and.arrow.up")
            }
        } else {
            Button { exportera(medSpår: false) } label: {
                Label("Exportera", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func exportera(medSpår: Bool) {
        let url: URL? = medSpår ? actions.exportMedSpår(pass) : actions.export(pass)
        if let u = url { shared = SharedPassFile(url: u) } else {
            problem = "Passet gick inte att exportera."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: PassFormat.symbol(pass.kind)).font(.title).foregroundStyle(Tema.dim)
                    Text(pass.kind?.displayName ?? "Pass").font(.title.weight(.semibold))
                    Spacer()
                    Text(PassFormat.short(pass.duration)).font(.title3).foregroundStyle(.secondary)
                }
                Text(pass.start, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // BESLUT B110 · METOD M62. Ett steptest visar sitt resultat överst.
                if pass.isStepTest { SteptestResultat(pass: pass, maxpuls: konditionMaxpuls) }
                // BESLUT B107 · BESLUT B110. Kartan överst när passet har en rutt.
                if PassKarta.harRutt(pass) { PassKarta(pass: pass, maxPulse: maxPulse) }
                PassChart(pass: pass, now: pass.afterEnd ?? pass.stop ?? pass.start)
                    .frame(height: 220)
                // BESLUT B117 · METOD M68. Passet har luckor och bandets historik för tiden har inte kommit än.
                if PassHistory.awaitsHistory(pass, now: Date()) {
                    Label(PassFormat.väntarPåHistoriken, systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PassStats(pass: pass)
                if pass.stop != nil { PassRecovery(pass: pass) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                exportKnapp
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Ta bort", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Ta bort passet?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Ta bort", role: .destructive) {
                actions.delete(pass)
                close()
            }
            Button("Avbryt", role: .cancel) {}
        }
        .sheet(item: $shared) { f in
            PassShareSheet(items: [f.url])
                .presentationDetents([.medium, .large])
        }
        .alert("Exportera", isPresented: Binding(
            get: { problem != nil },
            set: { if !$0 { problem = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }
}

private struct SharedPassFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// UIActivityViewController med filen som den är (som i RawExport).
private struct PassShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Kurvan och talen

/// Lägsta, snitt och högsta under den aktiva delen (METOD M47), som stora tal.
struct PassStats: View {
    let pass: Pass

    var body: some View {
        HStack(spacing: 0) {
            stat("lägst", PassFormat.bpm(pass.minBpm))
            stat("snitt", PassFormat.bpm(pass.averageBpm))
            stat("högst", PassFormat.bpm(pass.maxBpm))
        }
    }

    private func stat(_ namn: String, _ värde: String) -> some View {
        VStack(spacing: 2) {
            Text(värde)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(namn).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Pulsen under hela passet som en kurva, med en markering vid stopp. X-axeln är minuter från
/// Start. Där bandet varit tyst i mer än 10 sekunder bryts linjen i stället för att dras rakt över.
/// Efter stopp har kurvan en annan färg.
struct PassChart: View {
    let pass: Pass
    /// Klockan: kurvans högra kant medan passet pågår.
    let now: Date

    private struct Point: Identifiable {
        let id: Int
        let minutes: Double
        let bpm: Int
        let segment: Int
        let after: Bool
    }

    /// Mer än så här många punkter ritas inte; fler glesas ut (en var n:te).
    private static let maxPoints = 1200
    private static let gapSeconds: TimeInterval = 10

    private var points: [Point] {
        let alla = pass.samples
        let steg = max(1, alla.count / Self.maxPoints)
        var ut: [Point] = []
        var segment = 0
        var förra: Date?
        var förraEfter = false
        for (i, s) in alla.enumerated() where i % steg == 0 || i == alla.count - 1 {
            let efter = pass.stop.map { s.t > $0 } ?? false
            if let f = förra, s.t.timeIntervalSince(f) > Self.gapSeconds || efter != förraEfter { segment += 1 }
            ut.append(Point(id: i, minutes: s.t.timeIntervalSince(pass.start) / 60, bpm: s.bpm, segment: segment,
                            after: efter))
            förra = s.t
            förraEfter = efter
        }
        return ut
    }

    private var xMax: Double {
        let slut = max(now, pass.samples.last?.t ?? pass.start)
        return max(1, slut.timeIntervalSince(pass.start) / 60)
    }

    private var yDomain: ClosedRange<Int> {
        let b = pass.samples.map(\.bpm)
        guard let lo = b.min(), let hi = b.max() else { return 40...120 }
        return (lo - 5)...(hi + 5)
    }

    var body: some View {
        let punkter = points
        Chart {
            ForEach(punkter) { p in
                LineMark(x: .value("Minuter", p.minutes), y: .value("Puls", p.bpm),
                         series: .value("Serie", p.segment))
                    .foregroundStyle(p.after ? Color.teal : Tema.red)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let stopp = pass.stop {
                RuleMark(x: .value("Stopp", stopp.timeIntervalSince(pass.start) / 60))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Image(systemName: "stop.fill").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: yDomain)
        .accessibilityLabel("Pulskurva")
    }
}

/// Återhämtningen: pulsen vid stopp och efter 1, 2 och 5 minuter, med fallet från stopp
/// (METOD M47). Det som ännu inte mätts, eller saknar prov, står som ett streck.
private struct PassRecovery: View {
    let pass: Pass

    var body: some View {
        VStack(spacing: 6) {
            rad("Stopp", bpm: pass.pulseAtStop, fall: nil)
            ForEach(pass.recovery, id: \.seconds) { r in
                rad("\(r.seconds / 60) min", bpm: r.bpm, fall: r.drop)
            }
        }
    }

    private func rad(_ namn: String, bpm: Int?, fall: Int?) -> some View {
        HStack {
            Text(namn).font(.headline).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(PassFormat.bpm(bpm))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(bpm == nil ? Color.secondary.opacity(0.5) : Color.primary)
            Spacer()
            if let f = fall {
                let tecken: String = f >= 0 ? "−\(f)" : "+\(-f)"
                Label(tecken, systemImage: f >= 0 ? "arrow.down" : "arrow.up")
                    .font(Font.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(f >= 0 ? Color.teal : Color.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// De fem typerna som knappar; den valda är fylld.
private struct KindPicker: View {
    let selected: PassKind?
    let onSelect: (PassKind) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PassKind.allCases, id: \.self) { k in
                Button { onSelect(k) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: PassFormat.symbol(k)).font(.title2)
                        Text(k.displayName).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .foregroundStyle(selected == k ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(selected == k ? Tema.red : Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Förslag (BESLUT B121 · METOD M69)

/// Texterna i förslagen: rena funktioner, så att provet kan ge en fast tid.
enum PassForslagText {
    private static let månader: [String] = ["jan", "feb", "mar", "apr", "maj", "jun",
                                            "jul", "aug", "sep", "okt", "nov", "dec"]

    /// "Bastu · 22 min", eller "Pass · 41 min" när typen inte gissats.
    static func rubrik(_ f: PassDetection.Candidate) -> String {
        "\(f.kind?.displayName ?? "Pass") · \(f.minutes) min"
    }

    /// "Idag 17:05–17:46", "Igår 17:05–17:46" eller "13 nov 17:05–17:46", räknat i `zon`.
    static func tid(_ f: PassDetection.Candidate, zon: TimeZone = .current, nu: Date = Date()) -> String {
        var kal = Calendar(identifier: .gregorian)
        kal.timeZone = zon
        let dag: Date = kal.startOfDay(for: f.start)
        let idag: Date = kal.startOfDay(for: nu)
        let skillnad: Int = kal.dateComponents([.day], from: dag, to: idag).day ?? 0
        let prefix: String
        if skillnad == 0 {
            prefix = "Idag"
        } else if skillnad == 1 {
            prefix = "Igår"
        } else {
            let c = kal.dateComponents([.day, .month], from: f.start)
            prefix = "\(c.day ?? 1) \(månader[max(0, min(11, (c.month ?? 1) - 1))])"
        }
        return "\(prefix) \(klockslag(f.start, kal))–\(klockslag(f.end, kal))"
    }

    private static func klockslag(_ t: Date, _ kal: Calendar) -> String {
        let c = kal.dateComponents([.hour, .minute], from: t)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// En rad i listan Förslag: ikon, typ och längd, tid, och en pil.
struct FörslagRad: View {
    let förslag: PassDetection.Candidate
    var nu: Date = Date()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(Tema.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(PassForslagText.rubrik(förslag)).font(.body)
                Text(PassForslagText.tid(förslag, nu: nu))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Bladet för ett förslag: typen väljs (den gissade är förvald), och förslaget läggs till eller tas bort.
struct FörslagBlad: View {
    let förslag: PassDetection.Candidate
    var nu: Date = Date()
    let läggTill: (PassKind) -> Void
    let taBort: () -> Void

    @State private var typ: PassKind?

    init(förslag: PassDetection.Candidate, nu: Date = Date(), läggTill: @escaping (PassKind) -> Void,
         taBort: @escaping () -> Void) {
        self.förslag = förslag
        self.nu = nu
        self.läggTill = läggTill
        self.taBort = taBort
        _typ = State(initialValue: förslag.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lägg till passet?").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(PassForslagText.rubrik(förslag))
                Text(PassForslagText.tid(förslag, nu: nu))
            }
            .foregroundStyle(.secondary)

            Text("Typ").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(PassKind.allCases, id: \.self) { (k: PassKind) in
                    Button { typ = k } label: {
                        Text(k.displayName)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(typ == k ? Color.white : Tema.text)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(typ == k ? Tema.accent : Tema.card))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Pulsen fylls ur bandets historik.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                if let t = typ { läggTill(t) }
            } label: {
                Text("Lägg till").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(typ == nil)

            Button(role: .destructive, action: taBort) {
                Text("Ta bort förslaget").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}
