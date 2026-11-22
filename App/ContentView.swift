import SwiftUI
import Combine
import Journal
import Markers
import Pass
import SleepNeed

/// Tre flikar för användaren (BESLUT B40, B58, B82 och B105): Morgon (METOD M19, M33),
/// Pass (METOD M47, ett pass med puls för bastu, dusch, träning eller
/// promenad) och Profil (METOD M59, markörerna mot jämnåriga). En äldre morgon nås med pilarna i "‹ Idag ›" eller svepet på
/// Morgon; måttens trender (METOD M16, M51) öppnas med ett tryck på en rad på
/// Morgon eller på veckoremsan (BESLUT B82); listan över nätter ligger på Data.
/// Allt tekniskt och allt som rör Whoop bor på sidan Data, bakom bandet uppe
/// till höger på Morgon.
struct ContentView: View {
    @EnvironmentObject private var recorder: Recorder
    @Environment(\.scenePhase) private var scenePhase
    @State private var flik = 0
    /// BESLUT B74. Bladet Upp i morgon, öppet när kortet Ikväll trycks.
    @State private var väcktidsval: Väcktidsval?
    /// BESLUT B103. Påminnelsen före läggdags: av eller på, och om notiser är nekade.
    @ObservedObject private var påminnelse = Läggdagspåminnelse.shared
    /// BESLUT B130. Dagboken: morgonens fråga över hela appen, och kvällens blad.
    @ObservedObject private var dagbok = DagbokModell.shared

    /// BESLUT B130. Uppvakningsdagen morgonens fråga gäller, eller `nil` när den inte visas.
    private var morgonfråga: Int? {
        if case .morgon(let dag)? = dagbok.fråga { return dag }
        return nil
    }

    /// BESLUT B130. Kvällens blad; dras det ner är det "Inte nu".
    private var kvällsfråga: Binding<Kvällsfråga?> {
        Binding<Kvällsfråga?>(
            get: { () -> Kvällsfråga? in
                if case .kväll(let dag)? = dagbok.fråga { return Kvällsfråga(dag: dag) }
                return nil
            },
            set: { (ny: Kvällsfråga?) -> Void in
                if ny == nil, case .kväll(let dag)? = dagbok.fråga { dagbok.inteNu(kväll: dag) }
            })
    }

    var body: some View {
        TabView(selection: $flik) {
            MorningCardView()
                .tabItem { Label("Morgon", systemImage: "sunrise") }
                .tag(0)
            PassView()
                .tabItem { Label("Pass", systemImage: "heart") }
                .tag(1)
            // BESLUT B105. Profilen: var användaren ligger, markör för markör.
            ProfilView()
                .tabItem { Label("Profil", systemImage: "leaf") }
                .tag(2)
        }
        .environment(\.öppnaVäcktid, { (val: Väcktidsval) in väcktidsval = val })
        // BESLUT B136. Ingen rullningslist i någon vy: listen till höger störde mer än den visade.
        .scrollIndicators(.hidden)
        .sheet(item: $väcktidsval) { (val: Väcktidsval) in
            // BESLUT B102 · BESLUT B103. Bladet ger hela det nya schemat, och reglaget för påminnelsen före läggdags.
            VäcktidBlad(val: val, påminnelse: påminnelse.på, nekad: påminnelse.nekad,
                        spara: { (schema: WakeSchedule) -> Void in
                            SömnbehovModell.shared.sätt(schema: schema)
                            väcktidsval = nil
                        },
                        sättPåminnelse: { (på: Bool) -> Void in påminnelse.sätt(på: på) },
                        avbryt: { väcktidsval = nil })
                // BESLUT B101. Bladet i sitt innehålls höjd, så att rubrikraden och hela uträkningen syns direkt.
                .modifier(IInnehålletsHöjd())
                .presentationBackground(Tema.bg)
        }
        // BESLUT B130 · BESLUT B136 · METOD M75. Kvällens taggar: bladet öppnas bara från Data, aldrig av sig självt.
        .sheet(item: kvällsfråga) { (k: Kvällsfråga) in
            KvällVy(valda: dagbok.dagbok.evening(k.dag)?.tags ?? [],
                    spara: { (taggar: [EveningTag]) -> Void in dagbok.svara(kväll: k.dag, taggar: taggar) },
                    inteNu: { dagbok.inteNu(kväll: k.dag) })
                .modifier(IInnehålletsHöjd())
                .presentationBackground(Tema.bg)
        }
        // BESLUT B130 · BESLUT B136 · METOD M75. Morgonens skattning: frågan öppnas bara från Data, aldrig av sig själv.
        .overlay {
            if let dag = morgonfråga {
                MorgonfrågaVy(vald: dagbok.dagbok.morning(dag)?.rested,
                              välj: { (n: Int) -> Void in dagbok.svara(morgon: dag, utvilad: n) },
                              hoppaÖver: { dagbok.hoppaÖver(morgon: dag) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tema.bg.ignoresSafeArea())
            }
        }
        // BESLUT B65. Sömnbehovet räknas om när nätterna ändras.
        .onChange(of: recorder.summaries, initial: true) {
            SömnbehovModell.shared.sätt(nätter: recorder.summaries.compactMap(\.idunNight))
            // BESLUT B106 · METOD M61. Skattningen av VO2 max räknas om ur samma nätter.
            KonditionModell.shared.sätt(nätter: recorder.summaries.compactMap(\.idunNight))
            // BESLUT B105. Profilens nattmarkörer räknas ur samma nätter.
            ProfilModell.shared.sätt(nätter: recorder.summaries.compactMap(\.idunNight))
            // BESLUT B117 · METOD M68. Nätterna lästes om, alltså har dygnens filer ändrats: pass som väntar på
            // bandets historik fylls.
            PassController.shared.fillFromHistory()
            // BESLUT B121. Förslagen letas om ur samma historik.
            PassController.shared.hittaFörslag()
            // BESLUT B127. Modellerna har nätterna: coachen får skicka dem med huvudtalen.
            CoachModell.shared.vyernaMatade()
        }
        // BESLUT B117 · METOD M68. En hämtning från bandet är slut: dess historik kan fylla ett pass som väntar.
        .onReceive(recorder.$fetching) { (pågår: Bool) -> Void in
            if !pågår {
                PassController.shared.fillFromHistory()
                // BESLUT B121. Ny historik kan ge nya förslag.
                PassController.shared.hittaFörslag()
            }
        }
        // BESLUT B110 · METOD M62. Mätningarna av VO2 max räknas om ur de sparade passen när de ändras.
        .onReceive(PassController.shared.$saved) { (pass: [Pass]) -> Void in
            KonditionModell.shared.sätt(pass: pass)
        }
        // BESLUT B111. Födelseår och kön finns på fliken Profil; konditionen räknar med dem.
        .onReceive(ProfilModell.shared.$person) { (person: Person?) -> Void in
            KonditionModell.shared.sätt(person: person)
        }
        // BESLUT B111 · METOD M64. Det Idunn räknat för kondition fyller raden på Profil. `$visat` skickar värdet innan
        // egenskapen är satt, så serien läses först när modellen räknat klart.
        .onReceive(KonditionModell.shared.$visat.receive(on: RunLoop.main)) { _ in
            ProfilModell.shared.sätt(kondition: KonditionModell.shared.konditionsserie)
        }
        .toolbarBackground(Tema.bg, for: .tabBar)
        // METOD M28. Appen öppnas, på morgonen eller när som helst: läs listorna
        // och räkna de nätter som blivit klara sedan sist.
        .onChange(of: scenePhase) { _, fas in
            // PLAN.md A3. Förgrund och bakgrund i dygnets sidofil.
            if fas == .active { recorder.logEvent(.foreground) }
            if fas == .background { recorder.logEvent(.background) }
            if fas == .active {
                recorder.refresh()
                // BESLUT B47. Ljudet startar när appen öppnas kl 20–04 och slutar när den öppnas efter 05.
                SoundListener.shared.appBecameActive()
            }
        }
        .onAppear { SoundListener.shared.appBecameActive() }
    }
}
