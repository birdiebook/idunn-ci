import SwiftUI
import Charts
import UIKit
import Fitness
import Pass
import SleepNeed

/// BESLUT B58 · METOD M47
/// Fliken Pass: en knapp startar ett pass med puls (bastu, dusch, styrka, kondition,
/// promenad, golf), vyn visar tid, stor puls och kurvan, och efter Stopp mäts pulsen vidare i 10
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
                                        setLabel: { controller.setLabel($0) },
                                        finish: { controller.finish() },
                                        delete: { controller.delete($0) },
                                        export: { controller.exportFile($0) },
                                        startUte: { controller.startUte() },
                                        exportMedSpår: { controller.exportFile($0, medSpår: true) },
                                        startSteptest: { controller.startSteptest(höjdCm: $0) },
                                        sättProfil: { kondition.sätt(profil: $0) },
                                        läggTillFörslag: { controller.läggTill($0, val: $1) },
                                        taBortFörslag: { controller.taBortFörslag($0) },
                                        förhandsFörslag: { controller.förhandsvisa($0, val: $1) },
                                        ändra: { controller.ändra($0, label: $1, start: $2, stopp: $3) }),
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
    /// BESLUT B150. Märkningen av passet som pågår eller just stoppats: typ eller egna ord, och anteckningen.
    var setLabel: (PassLabel) -> Void = { _ in }
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
    /// BESLUT B121 · BESLUT B150. Lägger ett förslag till som ett pass med vald märkning och valda tider.
    var läggTillFörslag: (PassDetection.Candidate, PassForslagsval) -> Void = { _, _ in }
    /// BESLUT B121. Tar bort ett förslag för gott.
    var taBortFörslag: (PassDetection.Candidate) -> Void = { _ in }
    /// BESLUT B150. Förslaget som pass med valda tider, för talen i bladet; `nil` utan bandets poster.
    var förhandsFörslag: (PassDetection.Candidate, PassForslagsval) -> Pass? = { _, _ in nil }
    /// BESLUT B150. Ändrar ett sparat pass: märkningen och tiderna.
    var ändra: (Pass, PassLabel, Date, Date) -> Void = { _, _, _, _ in }
}

/// BESLUT B150. Det som valts i förslagsbladet: märkningen och tiderna.
struct PassForslagsval: Equatable {
    var label: PassLabel
    var start: Date
    var stopp: Date
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
        case .golf: return "figure.golf"
        case nil: return "heart"
        }
    }

    /// BESLUT B150. Ikonen för ett pass: egna ord har en etikett.
    static func symbol(_ p: Pass) -> String {
        p.customKind != nil ? "tag" : symbol(p.kind)
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
                                   stopp: actions.stop,
                                   steptest: p.isStepTest)
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
                               konditionMaxpuls: kondition.maxpuls?.bpm,
                               zonMaxpuls: kondition.maxpuls?.bpm ?? PassLoad.maxPulse(from: saved),
                               close: { openedID = nil })
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
                        läggTill: { (v: PassForslagsval) -> Void in
                            actions.läggTillFörslag(val.förslag, v)
                            valtFörslag = nil
                        },
                        taBort: {
                            actions.taBortFörslag(val.förslag)
                            valtFörslag = nil
                        },
                        förhand: { (v: PassForslagsval) -> Pass? in actions.förhandsFörslag(val.förslag, v) })
                .presentationDetents([.large])
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
                                        actions.läggTillFörslag(f, PassForslagsval(label: PassLabel(kind: typ),
                                                                                   start: f.start, stopp: f.end))
                                    } else {
                                        valtFörslag = Förslagsval(id: f.startMinute, förslag: f)
                                    }
                                },
                                // BESLUT B150. Raden öppnar bladet: typ, egna ord, anteckning och tider.
                                öppna: { (f: PassDetection.Candidate) -> Void in
                                    valtFörslag = Förslagsval(id: f.startMinute, förslag: f)
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

    /// BESLUT B111 · METOD M62 · BESLUT B133 · BESLUT B135. Medan steptestet pågår, i skissens form: ett kort med nivån och
    /// tiden till nästa, en stor ring som fylls under nivån med takten i mitten, och orden upp upp ner ner med det som
    /// gäller just nu markerat (i takt med metronomen); under det två rutor, pulsen och gränsen där testet stannar.
    /// Kurvan ligger på sidan Översikt och Stopp under sidorna (BESLUT B124).
    private func steptestNu(_ p: Pass) -> some View {
        let sek: TimeInterval = now.timeIntervalSince(p.start)
        let sista: Int = StepTest.cadences.count - 1
        let nivå: Int = min(StepTest.level(at: sek) ?? sista, sista)
        let kvar: TimeInterval = StepTest.levelSeconds * Double(nivå + 1) - sek
        let tid: String = PassRuttFormat.minutes(max(0, kvar.rounded(.up)))
        let nästa: String = nivå == sista ? "klart om " : "nästa nivå om "
        let andel: Double = min(1, max(0, (sek - StepTest.levelSeconds * Double(nivå)) / StepTest.levelSeconds))
        let slag: Int = ((kondition.slag % 4) + 4) % 4
        let senaste: PassSample? = p.samples.last
        let färskt: Bool = senaste.map { (s: PassSample) -> Bool in
            now.timeIntervalSince(s.t) <= Self.silentSeconds
        } ?? false
        let gräns: String = kondition.maxpuls.map { (m: MaxPulse) -> String in String(SteptestText.gräns(m.bpm)) } ?? "–"
        return VStack(spacing: 8) {
            VStack(spacing: 14) {
                HStack {
                    Text("Nivå \(nivå + 1) av \(StepTest.cadences.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.dim)
                    Spacer(minLength: 8)
                    HStack(spacing: 0) {
                        Text(nästa)
                        Text(tid).monospacedDigit()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Tema.dim)
                }
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(andel))
                        .stroke(Tema.text, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(String(Int(StepTest.cadences[nivå])))
                            .font(.system(size: 56, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(Tema.text)
                        Text("steg per minut").font(.system(size: 13)).foregroundStyle(Tema.dim)
                    }
                }
                .frame(width: 190, height: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Int(StepTest.cadences[nivå])) steg per minut")
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { (i: Int) in
                        let på: Bool = i == slag
                        HStack(spacing: 5) {
                            if på { Circle().fill(Tema.text).frame(width: 5, height: 5) }
                            Text(Self.takt[i])
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(på ? Tema.text : Tema.dim)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(Tema.card2))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
            HStack(spacing: 8) {
                steptestRuta("Puls", färskt ? PassFormat.bpm(senaste?.bpm) : "–")
                steptestRuta("Stannar vid", gräns)
            }
            silentRow(p, dämpad: true)
                .padding(.top, 6)
        }
    }

    private func steptestRuta(_ titel: String, _ värde: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titel).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.text)
            Spacer(minLength: 0)
            Text(värde)
                .font(.system(size: 30, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Tema.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .topLeading)
        .background(Tema.card, in: RoundedRectangle(cornerRadius: 24))
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
            // BESLUT B150. Typen, egna ord och anteckningen; ett steptest har redan sin typ och får bara anteckningen.
            PassEfterMarkning(pass: p, setLabel: actions.setLabel)
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
    private func silentRow(_ p: Pass, dämpad: Bool = false) -> some View {
        let sist = p.samples.last?.t ?? p.start
        if now.timeIntervalSince(sist) > Self.silentSeconds {
            VStack(spacing: 4) {
                Label("Bandet hörs inte", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundStyle(dämpad ? Tema.dim : Color.orange)
                // BESLUT B117. Bandet mäter vidare själv: passet fylls när telefonen fått dess historik.
                Text(PassFormat.väntarPåHistoriken)
                    .font(.footnote)
                    .foregroundStyle(dämpad ? Tema.dim : Color.secondary)
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
        return pass.kindName + (pass.isOutdoor ? " ute" : "")
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
            PassIkonruta(symbol: pass.isStepTest ? "figure.stairs" : PassFormat.symbol(pass))
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

/// BESLUT B138 · METOD M79. Ett sparat pass i skissens form (Efteråt): tid, snittpuls och högst, för ett pass ute sträcka och
/// tempo, pillren Puls · Tempo · Höjd · Karta med kurvan under, tid per pulszon och återhämtningen efter stopp. Exportera och
/// Ta bort ligger kvar i verktygsraden.
struct PassDetail: View {
    let pass: Pass
    var actions = PassActions()
    /// BESLUT B107. Maxpulsen ur de sparade passen, för färgen på rutten; `nil` ger en grå rutt.
    var maxPulse: Double?
    /// BESLUT B110 · METOD M62. Profilens maxpuls, för resultatet av ett steptest; `nil` ger ingen skattning.
    var konditionMaxpuls: Double?
    /// BESLUT B138. Maxpulsen som zonerna räknas mot; `nil` ger inget zonkort.
    var zonMaxpuls: Double?
    var close: () -> Void = {}

    @State private var shared: SharedPassFile?
    @State private var confirmDelete = false
    /// BESLUT B150. Bladet Ändra.
    @State private var ändraÖppet = false
    @State private var problem: String?
    /// BESLUT B138. Vilken kurva som visas.
    @State private var kurva: PassKurvVal
    /// BESLUT B153 · METOD M86. Bandets puls strax före och efter passet, läst ur dygnens filer när passet öppnas.
    @State private var omkring: [PassHistory.Reading]
    /// BESLUT B154. Zonen som kurvan färgar; nil = kurvan blågrå.
    @State private var valdZon: Int?

    init(pass: Pass, actions: PassActions = PassActions(), maxPulse: Double? = nil,
         konditionMaxpuls: Double? = nil, zonMaxpuls: Double? = nil, kurva: PassKurvVal = .puls,
         ändraÖppet: Bool = false, omkring: [PassHistory.Reading] = [], valdZon: Int? = nil,
         close: @escaping () -> Void = {}) {
        self.pass = pass
        self.actions = actions
        self.maxPulse = maxPulse
        self.konditionMaxpuls = konditionMaxpuls
        self.zonMaxpuls = zonMaxpuls
        _kurva = State(initialValue: kurva)
        _ändraÖppet = State(initialValue: ändraÖppet)
        _omkring = State(initialValue: omkring)
        _valdZon = State(initialValue: valdZon)
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

    /// BESLUT B138. Tempot per minut av passet ur spåret.
    private var tempoPunkter: [PassSeries.Point] { PassSeries.pace(pass.track ?? [], start: pass.start) }

    /// BESLUT B138. Höjden över passet ur spåret.
    private var höjdPunkter: [PassSeries.Point] { PassSeries.altitude(pass.track ?? [], start: pass.start) }

    /// BESLUT B138. Tid per pulszon ur den aktiva delen; tom utan maxpuls.
    private var zoner: [PassZones.Share] {
        guard let m = zonMaxpuls else { return [] }
        return PassZones.time(pass.activeSamples) { (bpm: Int) -> Int in PassLoad.zone(bpm: bpm, maxPulse: m) }
    }

    /// BESLUT B144 · BESLUT B154 · METOD M53. Zonernas undre gränser i slag per minut; bara den valda zonen har sin
    /// färg, de andra kurvans blågrå. Tomt utan maxpuls eller utan vald zon: då är hela linjen blågrå.
    private var zonband: [PassKurva.Band] {
        guard let m = zonMaxpuls, let vald = valdZon else { return [] }
        return SleepNeedRules.zoneLowerBounds.enumerated().map { (e: (offset: Int, element: Double)) -> PassKurva.Band in
            let zon: Int = e.offset + 1
            return PassKurva.Band(från: e.element * m, färg: zon == vald ? PassZonTrappa.color(zon) : Tema.pulse)
        }
    }

    /// BESLUT B138. Kurvan som visas: den valda när den finns för passet, annars Puls.
    private func aktiv(tempo: [PassSeries.Point], höjd: [PassSeries.Point]) -> PassKurvVal {
        switch kurva {
        case .tempo: return tempo.count >= 2 ? .tempo : .puls
        case .höjd: return höjd.count >= 2 ? .höjd : .puls
        case .karta: return PassKarta.harRutt(pass) ? .karta : .puls
        case .puls: return .puls
        }
    }

    private func val(tempo: [PassSeries.Point], höjd: [PassSeries.Point]) -> [(PassKurvVal, String)] {
        var v: [(PassKurvVal, String)] = [(PassKurvVal.puls, "Puls")]
        if tempo.count >= 2 { v.append((PassKurvVal.tempo, "Tempo")) }
        if höjd.count >= 2 { v.append((PassKurvVal.höjd, "Höjd")) }
        if PassKarta.harRutt(pass) { v.append((PassKurvVal.karta, "Karta")) }
        return v
    }

    private func kurvkort(_ vald: PassKurvVal, tempo: [PassSeries.Point], höjd: [PassSeries.Point]) -> some View {
        let slutPuls: TimeInterval = (pass.afterEnd ?? pass.stop ?? pass.start).timeIntervalSince(pass.start)
        let stopp: TimeInterval? = pass.stop.map { (s: Date) -> TimeInterval in s.timeIntervalSince(pass.start) }
        return VStack(alignment: .leading, spacing: 8) {
            switch vald {
            case .tempo:
                PassKortRubrik(text: "Tempo").padding(.horizontal, 16)
                PassKurva(punkter: tempo, längd: pass.duration, start: pass.start, stopp: stopp, omvänd: true,
                          stegval: [15, 30, 60, 120, 300],
                          text: { (v: Double) -> String in KonditionText.tempo(v) },
                          vald: { (v: Double) in (KonditionText.tempo(v), "/km") }, etikett: "Tempokurva")
                Text("per km, per minut av passet").font(.system(size: 12)).foregroundStyle(Tema.dim)
                    .padding(.horizontal, 16)
            case .höjd:
                PassKortRubrik(text: "Höjd").padding(.horizontal, 16)
                PassKurva(punkter: höjd, längd: pass.duration, start: pass.start,
                          text: { (v: Double) -> String in "\(Int(v.rounded())) m" },
                          vald: { (v: Double) in (String(Int(v.rounded())), "m") }, etikett: "Höjdkurva")
                Text("meter över havet").font(.system(size: 12)).foregroundStyle(Tema.dim)
                    .padding(.horizontal, 16)
            default:
                // BESLUT B144 · METOD M83. Pulsen som medel över fönster, och linjen i zonernas färg.
                let fönster: TimeInterval = PassSeries.window(length: slutPuls)
                // BESLUT B153 · METOD M86. Pulsen utanför passet, uttonad ut till kanterna, när dygnens filer har den.
                let marginal: TimeInterval = PassSeries.margin(length: slutPuls)
                let utanför: [PassSeries.Point] = PassSeries.outside(omkring, start: pass.start, end: slutPuls,
                                                                      margin: marginal, window: fönster)
                PassKortRubrik(text: "Puls").padding(.horizontal, 16)
                PassKurva(punkter: PassSeries.averaged(PassSeries.pulse(pass), window: fönster, split: stopp),
                          längd: slutPuls, start: pass.start, stopp: stopp, lucka: 2 * fönster + 10,
                          band: zonband,
                          text: { (v: Double) -> String in String(Int(v.rounded())) },
                          vald: { (v: Double) in (String(Int(v.rounded())), "bpm") },
                          etikett: "Pulskurva", utanför: utanför, marginal: utanför.isEmpty ? 0 : marginal)
                Text("lägst " + PassFormat.bpm(pass.minBpm)).font(.system(size: 12)).foregroundStyle(Tema.dim)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        let tempo: [PassSeries.Point] = tempoPunkter
        let höjd: [PassSeries.Point] = höjdPunkter
        let vald: PassKurvVal = aktiv(tempo: tempo, höjd: höjd)
        let alternativ: [(PassKurvVal, String)] = val(tempo: tempo, höjd: höjd)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pass.kindName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Tema.text)
                    Text(pass.start, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                        .font(.system(size: 14))
                        .foregroundStyle(Tema.dim)
                    // BESLUT B150. Anteckningen under rubriken.
                    if let n = pass.note {
                        Text(n)
                            .font(.system(size: 14))
                            .foregroundStyle(Tema.text)
                            .padding(.top, 6)
                    }
                }
                PassTreTal(pass: pass)
                // BESLUT B138. Ett pass ute: sträckan och tempot.
                if !PassRoute.usable(pass.track ?? []).isEmpty { PassUteRutor(pass: pass) }
                // BESLUT B110 · METOD M62. Ett steptest visar sitt resultat.
                if pass.isStepTest { SteptestResultat(pass: pass, maxpuls: konditionMaxpuls) }
                if alternativ.count > 1 {
                    HStack {
                        Spacer(minLength: 0)
                        PassPiller(val: alternativ, valt: vald, välj: { (v: PassKurvVal) -> Void in kurva = v })
                        Spacer(minLength: 0)
                    }
                }
                // BESLUT B107 · BESLUT B110. Kartan har sin egen form och ligger utan kort.
                if vald == .karta {
                    PassKarta(pass: pass, maxPulse: maxPulse)
                } else {
                    // BESLUT B153. Kurvan utan kort och kant till kant, som Whoops: rubriken och raden under
                    // står kvar i sidans marginal, kurvan går ut över den.
                    kurvkort(vald, tempo: tempo, höjd: höjd)
                        .padding(.horizontal, -16)
                }
                // BESLUT B117 · METOD M68. Passet har luckor och bandets historik för tiden har inte kommit än.
                if PassHistory.awaitsHistory(pass, now: Date()) {
                    Label(PassFormat.väntarPåHistoriken, systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PassZonKort(zoner: zoner, vald: valdZon) { (z: Int) in
                    withAnimation(.easeInOut(duration: 0.2)) { valdZon = valdZon == z ? nil : z }
                }
                // BESLUT B155. Kortet Efter stopp är borttaget tills vidare.
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Tema.bg)
        // BESLUT B153 · METOD M86. Pulsen omkring passet ur dygnens filer, utanför huvudkön (en dygnsfil kan vara tiotals MB).
        .task(id: pass.id) {
            guard omkring.isEmpty, pass.stop != nil else { return }
            let p: Pass = pass
            let marginal: TimeInterval = PassSeries.margin(
                length: (p.afterEnd ?? p.stop ?? p.start).timeIntervalSince(p.start))
            let läst: [PassHistory.Reading] = await Task.detached(priority: .userInitiated) {
                PassHistorik.omkring(p, marginal: marginal, now: Date())
            }.value
            omkring = läst
        }
        // BESLUT B133. Ingen accentfärg: knapparna i fältet är vita.
        .tint(Tema.text)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // BESLUT B150. Ändra: typ, egna ord, anteckning och tider.
            ToolbarItem(placement: .topBarTrailing) {
                Button { ändraÖppet = true } label: {
                    Label("Ändra", systemImage: "pencil")
                }
                .tint(Tema.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                exportKnapp.tint(Tema.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { confirmDelete = true } label: {
                    Label("Ta bort", systemImage: "trash")
                }
                .tint(Tema.text)
            }
        }
        .confirmationDialog("Ta bort passet?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Ta bort", role: .destructive) {
                actions.delete(pass)
                close()
            }
            Button("Avbryt", role: .cancel) {}
        }
        .sheet(isPresented: $ändraÖppet) {
            PassAndraBlad(pass: pass,
                          spara: { (l: PassLabel, start: Date, stopp: Date) -> Void in
                              actions.ändra(pass, l, start, stopp)
                              ändraÖppet = false
                          },
                          avbryt: { ändraÖppet = false })
                .presentationDetents([.large])
                .presentationBackground(Tema.bg)
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

/// BESLUT B150. Märkningen i bladet efter Stopp: vald typ eller egna ord och anteckningen går till passet medan de
/// skrivs, så att en dödad app inte tappar dem.
private struct PassEfterMarkning: View {
    let pass: Pass
    let setLabel: (PassLabel) -> Void
    @State private var val: PassMarkningsval

    init(pass: Pass, setLabel: @escaping (PassLabel) -> Void) {
        self.pass = pass
        self.setLabel = setLabel
        _val = State(initialValue: PassMarkningsval(PassLabel(pass)))
    }

    var body: some View {
        PassMarkningVy(val: $val, medTyp: !pass.isStepTest)
            .onChange(of: val) { (_: PassMarkningsval, ny: PassMarkningsval) in
                var l: PassLabel = ny.label
                // Ett steptest behåller sin typ.
                if pass.isStepTest { l.kind = pass.kind }
                setLabel(l)
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

/// BESLUT B121 · BESLUT B150. Bladet för ett förslag: typen väljs (den gissade är förvald) eller skrivs med egna ord,
/// en anteckning, och start och slut flyttas i minutsteg innan förslaget läggs till. Talen räknas om ur bandets
/// historik för de valda tiderna. Förslaget som det var sparas i passet (`Pass.suggested`).
struct FörslagBlad: View {
    let förslag: PassDetection.Candidate
    var nu: Date = Date()
    let läggTill: (PassForslagsval) -> Void
    let taBort: () -> Void
    /// Passet som det blir med valda tider, för talen; `nil` ger streck.
    var förhand: (PassForslagsval) -> Pass? = { _ in nil }

    @State private var val: PassMarkningsval
    @State private var start: Date
    @State private var stopp: Date
    private let gränser: PassEdit.Limits

    init(förslag: PassDetection.Candidate, nu: Date = Date(), läggTill: @escaping (PassForslagsval) -> Void,
         taBort: @escaping () -> Void, förhand: @escaping (PassForslagsval) -> Pass? = { _ in nil },
         förval: PassMarkningsval? = nil, tider: (start: Date, stopp: Date)? = nil) {
        self.förslag = förslag
        self.nu = nu
        self.läggTill = läggTill
        self.taBort = taBort
        self.förhand = förhand
        // `förval` och `tider` bara för provet: bladet som det ser ut när något redan valts.
        _val = State(initialValue: förval
            ?? PassMarkningsval(typ: förslag.kind.map { (k: PassKind) -> PassTypval in .typ(k) }))
        _start = State(initialValue: tider?.start ?? förslag.start)
        _stopp = State(initialValue: tider?.stopp ?? förslag.end)
        gränser = PassEdit.Limits(start: förslag.start, stop: förslag.end, now: nu)
    }

    private var valt: PassForslagsval { PassForslagsval(label: val.label, start: start, stopp: stopp) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lägg till passet?").font(.title3.weight(.semibold)).foregroundStyle(Tema.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PassForslagText.rubrik(förslag))
                    Text(PassForslagText.tid(förslag, nu: nu))
                }
                .foregroundStyle(Tema.dim)

                Text("Typ").font(.headline).foregroundStyle(Tema.text)
                PassMarkningVy(val: $val)

                Text("Tider").font(.headline).foregroundStyle(Tema.text)
                PassTiderVy(start: $start, stopp: $stopp, gränser: gränser, ursprung: (förslag.start, förslag.end))
                PassForhandsTal(pass: förhand(valt))

                Text("Pulsen fylls ur bandets historik.")
                    .font(.footnote)
                    .foregroundStyle(Tema.dim)

                Button {
                    läggTill(valt)
                } label: {
                    Text("Lägg till")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tema.bg)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(Tema.text))
                        .opacity(val.harTyp ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!val.harTyp)

                Button(action: taBort) {
                    Text("Inte ett pass")
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
