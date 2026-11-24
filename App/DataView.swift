import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Band
import Fitness
import Journal
import Night
import Sound
import WhoopFrames
import WhoopImport

/// BESLUT B38 · BESLUT B40 · BESLUT B28 · BESLUT B30 · BESLUT B25 · METOD M27 · METOD M28
/// Sidan Data (kugghjulet uppe till höger på Morgon): allt tekniskt, för
/// utvecklingen av Idunn och inte för vardagen, och allt som rör Whoop. Lyssnarens
/// läge och täckningen, listan över nätter, dygnsfilerna med Exportera, Märk,
/// T2:s räkning, Bandkontroll, jämförelsen mot Whoop (med sömnen och
/// hudtemperaturen), kontrollen av nätterna ur K18, importen av
/// Whoop-exporten med Whoops nätter, de gamla inspelningarna med nattrapportens
/// Diagnos och T2, A3:s reglage, ljudet under natten (B47: reglaget och statusen)
/// och källorna för modellerna (B36). Inga tekniska ord och inget Whoop utanför den här sidan.
struct DataView: View {
    @EnvironmentObject private var recorder: Recorder
    @EnvironmentObject private var store: Store
    @ObservedObject private var listener = SoundListener.shared
    @ObservedObject private var facit = SoundFacitStore.shared
    /// BESLUT B106. Profilen, Whoops avskrivna tal och skattningen av VO2 max.
    @ObservedObject private var kondition = KonditionModell.shared
    /// BESLUT B127. Coachen: kopplingen, reglaget och vad som skickats.
    @ObservedObject private var coach = CoachModell.shared
    /// BESLUT B143. Utvecklingskopian: reglaget och vad som laddats upp.
    @ObservedObject private var kopia = DygnskopiaModell.shared
    /// BESLUT B130. Dagboken: kvällens taggar och morgonens skattning.
    @ObservedObject private var dagbok = DagbokModell.shared
    @State private var importing = false
    /// PLAN.md A3. Reglaget "Whoop-appen är borta": av som förval.
    @AppStorage(Recorder.utanWhoopKey) private var utanWhoop = false

    var body: some View {
        DataScreen(
            link: recorder.link, battery: recorder.battery, status: recorder.status,
            unsaved: recorder.unsaved, summaries: recorder.summaries,
            cycles: store.export?.cycles ?? [], sleeps: store.export?.sleeps ?? [],
            days: recorder.days, activeDay: recorder.activeDay,
            tally: recorder.tally, listening: recorder.listening, storage: recorder.storage,
            lastMarker: recorder.lastMarker?.label, markerCount: recorder.markerCount,
            sound: listener.status, facit: facit.facit,
            onMark: { recorder.mark($0) },
            onDeleteNight: { recorder.delete($0) },
            onDeleteDay: { recorder.delete($0) },
            onImport: { importing = true },
            utanWhoop: $utanWhoop,
            onUtanWhoop: { (på: Bool) -> Void in if på { recorder.considerAutoFetch(force: true) } },
            kondition: kondition.lager, skattning: kondition.skattning,
            onWhoopTal: { (dag: Int, värde: Double) -> Void in kondition.skrivAv(dag: dag, värde: värde) },
            coach: coach.läge,
            onCoachKoppla: { () -> Void in coach.koppla(UIPasteboard.general.string ?? "") },
            onCoachPå: { (på: Bool) -> Void in coach.sätt(på: på) },
            onCoachSkicka: { () -> Void in coach.synka(tvinga: true) },
            onCoachFrån: { () -> Void in coach.kopplaFrån() },
            kopia: kopia.läge,
            onKopiaPå: { (på: Bool) -> Void in kopia.sätt(på: på) },
            dagbok: dagbok.låst ? nil : dagbok.dagbok,
            onKväll: { dagbok.öppnaKväll() },
            onMorgon: { dagbok.öppnaMorgon() },
            räknar: recorder.computingNights,
            onRäknaOm: { recorder.recomputeRecentNights() }
        )
        .onAppear { recorder.refresh() }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): store.importFiles(urls)
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .alert("Importen gick inte", isPresented: Binding(
            get: { store.error != nil },
            set: { if !$0 { store.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.error ?? "")
        }
        .alert("Data", isPresented: Binding(
            get: { recorder.problem != nil },
            set: { if !$0 { recorder.problem = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.problem ?? "")
        }
    }
}

/// Data som värden (CLAUDE.md, provet): lyssnaren och listorna tas in som
/// data, så `IdunnProv` kan rita sidan med påhittade notiser och nätter.
struct DataScreen: View {
    let link: Recorder.Link
    let battery: Int?
    let status: ListenerStatus
    var unsaved = 0
    let summaries: [NightSummary]
    let cycles: [Cycle]
    var sleeps: [Sleep] = []
    let days: [DayFile]
    let activeDay: String?
    let tally: FrameTally
    var listening: Set<String> = []
    /// BESLUT B41 · METOD M34. Lagringen i MB: råa dygn, arkiv och resultat.
    var storage: StorageUsage?
    var lastMarker: String?
    var markerCount = 0
    /// BESLUT B47. Ljudet under natten: statusen under reglaget. `nil` (provet) döljer sektionen.
    var sound: SoundListener.Status?
    /// METOD M46 · BESLUT B56. Facit för ljudets klassning: andelen fel per klass och antal lyssnade.
    var facit: SoundFacit?
    /// Fasta klockan i provet.
    var now: Date?
    var onMark: (String) -> Void = { _ in }
    var onDeleteNight: (NightSummary) -> Void = { _ in }
    var onDeleteDay: (DayFile) -> Void = { _ in }
    var onImport: () -> Void = {}
    /// PLAN.md A3. Reglaget "Whoop-appen är borta" (av i provet) och vad som händer när det slås om.
    var utanWhoop: Binding<Bool> = .constant(false)
    var onUtanWhoop: (Bool) -> Void = { _ in }
    /// BESLUT B106 · METOD M60 · METOD M64. Konditionen: profilen och de avskrivna Whoop-talen, skattningen av VO2 max
    /// (eller det som saknas), och vad som händer när profilen ändras eller ett tal skrivs av (dagnummer, tal).
    /// `nil` (förval, provet) döljer sektionen.
    var kondition: FitnessStore?
    var skattning: PassiveFitness.Outcome?
    var onWhoopTal: (Int, Double) -> Void = { _, _ in }
    /// BESLUT B127. Coachen: läget (`nil` ritar ingen sektion) och knapparna.
    var coach: CoachModell.Läge?
    var onCoachKoppla: () -> Void = {}
    var onCoachPå: (Bool) -> Void = { _ in }
    var onCoachSkicka: () -> Void = {}
    var onCoachFrån: () -> Void = {}
    /// BESLUT B143. Utvecklingskopian: läget (`nil` döljer raderna) och reglaget.
    var kopia: DygnskopiaModell.Läge?
    var onKopiaPå: (Bool) -> Void = { _ in }
    /// BESLUT B130 · METOD M75. Dagboken och vägen till kvällens blad och morgonens fråga. `nil` (förval) döljer sektionen.
    var dagbok: Journal?
    var onKväll: () -> Void = {}
    var onMorgon: () -> Void = {}
    /// BESLUT B159. Räkna om nätterna: reserven om den automatiska regeln missar något. `nil` = ingen knapp.
    var räknar = false
    var onRäknaOm: (() -> Void)? = nil

    /// METOD M28. Nätterna ur K18, för kontrollen.
    private var k18Nights: [NightSummary] {
        summaries.filter { (s: NightSummary) -> Bool in s.origin == .k18 }
    }

    /// Gamla inspelningar (BESLUT B30): kvar i listan och läses som förut.
    private var oldNights: [NightSummary] {
        summaries.filter { (s: NightSummary) -> Bool in s.origin != .k18 }
    }

    var body: some View {
        List {
            // BESLUT B106 · BESLUT B111. Kondition: överst, med VO2 max och Whoops avskrivna tal (profilen bor på fliken Profil).
            if let kondition {
                KonditionSektion(lager: kondition, skattning: skattning, idag: now ?? Date(),
                                 onWhoopTal: onWhoopTal)
            }

            // BESLUT B127. Coachen: det enda Idunn skickar av sig själv, och bara sammanfattningar.
            if let coach {
                CoachSektion(läge: coach, onKoppla: onCoachKoppla, onPå: onCoachPå, onSkicka: onCoachSkicka,
                             onFrån: onCoachFrån, kopia: kopia, onKopiaPå: onKopiaPå)
            }

            // BESLUT B130. Dagboken: hur mycket som är loggat, och vägen till att ändra ett svar.
            if let dagbok {
                DagbokSektion(dagbok: dagbok, onKväll: onKväll, onMorgon: onMorgon)
            }

            Section {
                ListenerView(link: link, battery: battery, status: status, unsaved: unsaved, now: now)
            } header: {
                Label("Lyssnaren", systemImage: "antenna.radiowaves.left.and.right")
            }

            // BESLUT B47. Ljudet under natten: reglaget (på som förval) och statusen.
            if let sound {
                SoundSection(status: sound, facit: facit)
            }

            // BESLUT B40. Listan över Idunns nätter, för kontroll: vardagen når
            // en natt genom pilarna och svepet på Morgon och ett tryck i trendvyn (BESLUT B82).
            if !summaries.isEmpty || onRäknaOm != nil {
                Section {
                    if !summaries.isEmpty {
                        NavigationLink {
                            NightsList(summaries: summaries)
                        } label: {
                            Label("Nätter", systemImage: "moon.stars")
                        }
                    }
                    // BESLUT B159. Nätterna räknas om av sig själva när ny data kommit; knappen tvingar de tre senaste.
                    if let onRäknaOm {
                        Button {
                            onRäknaOm()
                        } label: {
                            HStack {
                                Label("Räkna om nätterna", systemImage: "arrow.clockwise")
                                Spacer()
                                if räknar { ProgressView() }
                            }
                        }
                        .disabled(räknar)
                    }
                } footer: {
                    if onRäknaOm != nil {
                        Text("Nätterna räknas om av sig själva när ny data kommer från bandet. Knappen räknar om de tre senaste ändå.")
                    }
                }
            }

            if !cycles.isEmpty, !summaries.isEmpty {
                Section {
                    NavigationLink {
                        MorningView(summaries: summaries, cycles: cycles, sleeps: sleeps)
                    } label: {
                        Label("Idunn mot Whoop", systemImage: "sunrise")
                    }
                }
            }

            if !days.isEmpty {
                Section {
                    // BESLUT B66. Alla dygn och pass på en gång, för avstämningen mot Whoop.
                    AllDaysExportButton()
                    ForEach(days) { d in
                        DayRow(day: d, isActive: d.stem == activeDay)
                    }
                    .onDelete { rader in
                        for i in rader where days[i].stem != activeDay { onDeleteDay(days[i]) }
                    }
                } header: {
                    Label("Dygn", systemImage: "calendar")
                }
            }

            if let storage {
                StorageSection(usage: storage)
            }

            if !k18Nights.isEmpty {
                Section {
                    ForEach(k18Nights) { s in
                        K18CheckRow(summary: s)
                    }
                } header: {
                    Label("Nätter ur K18", systemImage: "waveform.path.ecg")
                } footer: {
                    Text("Omlagda och utelämnade kontrollerar hur stämpeln tolkas (METOD M28).")
                }
            }

            if !oldNights.isEmpty {
                Section {
                    ForEach(oldNights) { s in
                        NavigationLink {
                            NightReportView(stem: s.stem)
                        } label: {
                            SummaryRow(summary: s)
                        }
                    }
                    .onDelete { rader in
                        let valda = rader.map { oldNights[$0] }
                        for s in valda { onDeleteNight(s) }
                    }
                } header: {
                    Label("Gamla inspelningar", systemImage: "moon.stars")
                }
            }

            Section {
                Button {
                    onImport()
                } label: {
                    Label("Importera Whoop-exporten", systemImage: "square.and.arrow.down")
                }
                if !cycles.isEmpty {
                    NavigationLink {
                        NightList(cycles: cycles)
                            .navigationTitle("Whoops nätter")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Whoops nätter", systemImage: "list.bullet")
                    }
                }
            } header: {
                Label("Whoop-exporten", systemImage: "heart.text.square")
            } footer: {
                Text("Packa upp exporten i Filer och välj filerna.")
            }

            Section {
                // BESLUT B25. Bandkontrollen: hämta historiken på knapptryck.
                NavigationLink {
                    BandControlView()
                } label: {
                    Label("Bandkontroll", systemImage: "wrench.adjustable")
                }
            }

            Section {
                DisclosureGroup {
                    TallyGrid(tally: tally, listening: listening)
                } label: {
                    Label("T2", systemImage: "ant")
                }
            }

            // PLAN.md A3. På: Idunn hämtar bandets historik själv (`AutoFetch`), vid anslutning och varje timme.
            Section {
                Toggle(isOn: utanWhoop) {
                    Label("Whoop-appen är borta", systemImage: "iphone.slash")
                }
                .onChange(of: utanWhoop.wrappedValue) { _, på in onUtanWhoop(på) }
            } footer: {
                Text("Idunn hämtar bandets historik själv. Det Idunn hämtar får Whoop-appen inte.")
            }

            // BESLUT B36. Källorna för de inbyggda modellerna (sömn och vaken,
            // stadierna), lästa ur modellfilerna så att listan följer vikterna.
            Section {
                ForEach(SleepModels.sources, id: \.name) { (k: ModelSource) in
                    SourceRow(source: k)
                }
            } header: {
                Label("Källor", systemImage: "books.vertical")
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MarkMenu(lastLabel: lastMarker, count: markerCount, onMark: onMark)
            }
        }
    }
}

/// BESLUT B127 · METOD M73. Coachen på Data: innan telefonen är kopplad en knapp som klistrar in kopplingen från
/// Claude; sedan reglaget, när det senast skickades och knapparna Skicka nu och Koppla från. Tar läget som värde, så
/// att provet kan rita den.
struct CoachSektion: View {
    let läge: CoachModell.Läge
    var onKoppla: () -> Void = {}
    var onPå: (Bool) -> Void = { _ in }
    var onSkicka: () -> Void = {}
    var onFrån: () -> Void = {}
    /// BESLUT B143 · METOD M82. Utvecklingskopian: dygnens arkiv till din egen databas (`nil` döljer raderna).
    var kopia: DygnskopiaModell.Läge?
    var onKopiaPå: (Bool) -> Void = { _ in }

    var body: some View {
        Section {
            if läge.kopplad {
                Toggle(isOn: Binding(get: { () -> Bool in läge.på }, set: { (ny: Bool) -> Void in onPå(ny) })) {
                    Label("Skicka till coachen", systemImage: "paperplane")
                }
                HStack {
                    Text(status)
                    Spacer()
                    if läge.arbetar { ProgressView() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button("Skicka nu") { onSkicka() }
                    .disabled(läge.arbetar)
                Button("Koppla från", role: .destructive) { onFrån() }
                    .disabled(läge.arbetar)
                if let kopia { kopiaRader(kopia) }
            } else {
                if let kopia { kopiaRader(kopia) }
                Button {
                    onKoppla()
                } label: {
                    HStack {
                        Label("Klistra in kopplingen", systemImage: "doc.on.clipboard")
                        Spacer()
                        if läge.arbetar { ProgressView() }
                    }
                }
                .disabled(läge.arbetar)
            }
            if let fel = läge.fel {
                Text(fel)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Label("Coachen", systemImage: "figure.run")
        } footer: {
            Text(fot)
        }
    }

    /// BESLUT B143. Reglaget Utvecklingskopia och en rad om vad som laddats upp.
    @ViewBuilder
    private func kopiaRader(_ k: DygnskopiaModell.Läge) -> some View {
        Toggle(isOn: Binding(get: { () -> Bool in k.på }, set: { (ny: Bool) -> Void in onKopiaPå(ny) })) {
            Label("Utvecklingskopia", systemImage: "externaldrive.badge.icloud")
        }
        HStack {
            Text(kopiaStatus(k))
            Spacer()
            if k.arbetar { ProgressView() }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        if let fel = k.fel {
            Text(fel)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    /// BESLUT B143. "12 dygn · 24 av 500 MB" och när det senast lyckades, eller att kopplingen väntas.
    private func kopiaStatus(_ k: DygnskopiaModell.Läge) -> String {
        if !k.kopplad { return "Väntar på kopplingen" }
        if !k.på { return "Av" }
        guard let dygn = k.dygn, let mb = k.megabyte, let tak = k.tak else {
            return k.arbetar ? "Laddar upp …" : "Inget uppladdat än"
        }
        var text: String = "\(dygn) dygn · \(Int(mb.rounded())) av \(Int(tak.rounded())) MB"
        if let senast = k.senast {
            text += " · " + senast.formatted(date: .abbreviated, time: .shortened)
        }
        // BESLUT B148. Passens rörelse i sin egen hink.
        if let pass = k.pass, let pmb = k.passMegabyte, let ptak = k.passTak {
            text += "\nRörelse: \(pass) pass · \(Int(pmb.rounded())) av \(Int(ptak.rounded())) MB"
        }
        return text
    }

    private var fot: String {
        if läge.kopplad {
            return "Idunn skickar sammanfattningen av nätterna, passen och profilen till din egen databas, så att "
                + "Claude kan läsa den. Aldrig slag för slag, aldrig var du varit och aldrig ljud."
        }
        return "Be Claude om en koppling, kopiera texten och tryck här. Sedan skickar Idunn sammanfattningarna av sig själv."
    }

    private var status: String {
        if läge.arbetar { return "Skickar" }
        guard let senast = läge.senast else { return "Inget skickat än" }
        // Dag och klockslag med appens egna format, så att raden läses lika oavsett telefonens språk (BESLUT B125).
        let dag = WakeDay(senast, utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: senast))
        return "Senast skickat " + Fmt.dayMonth(dag) + " " + Fmt.clock(date: senast) + " · \(läge.skickade) sparade"
    }
}

/// BESLUT B47. Ljudet under natten: ett reglage (på som förval) och en statusrad
/// (lyssnar sedan, glapp, klipp, storlek). Idunn lyssnar när appen öppnas kl 20–04
/// och slutar när den öppnas efter 05; ljudet stannar på telefonen.
private struct SoundSection: View {
    let status: SoundListener.Status
    var facit: SoundFacit?
    @AppStorage(SoundListener.enabledKey) private var enabled = true

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label("Ljudet på natten", systemImage: "waveform")
            }
            .onChange(of: enabled) { _, på in SoundListener.shared.setEnabled(på) }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                if let d = detail {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            // METOD M46 · BESLUT B56. Facit: lyssnade klipp och andelen fel per klass.
            if let f = facit, f.heard > 0 || f.ownerTally().heard > 0 {
                SoundFacitRows(facit: f)
            }
        } header: {
            Label("Ljudet", systemImage: "mic")
        } footer: {
            Text("Klipp runt ljud raderas efter 14 dagar. Ljudet lämnar telefonen bara när du exporterar.")
        }
    }

    private var headline: String {
        if let n = status.note { return n }
        if !enabled { return "Av" }
        if status.listening, let s = status.since {
            return "Lyssnar sedan " + s.formatted(.dateTime.hour().minute())
        }
        return "Startar när appen öppnas kl 20–04"
    }

    private var detail: String? {
        guard status.seconds > 0 || status.bytes > 0 else { return nil }
        var delar: [String] = []
        if status.seconds > 0 {
            delar.append(Duration.seconds(status.seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
        }
        delar.append("\(status.gaps) glapp")
        delar.append("\(status.clips) klipp")
        delar.append(ByteCountFormatter.string(fromByteCount: Int64(status.bytes), countStyle: .file))
        return delar.joined(separator: " · ")
    }
}

/// METOD M46 · BESLUT B56
/// Facit för ljudets klassning: per klass antal lyssnade klipp och andelen fel, och för snarkningens ägare
/// (din eller annans) detsamma. Över en femtedel fel (B47 omprövas) märks med en gul triangel.
private struct SoundFacitRows: View {
    let facit: SoundFacit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(facit.heard) lyssnade", systemImage: "hand.thumbsup")
                .font(.subheadline)
            ForEach(facit.classTally(), id: \.soundClass) { (t: SoundFacit.ClassTally) in
                row(symbol: SoundLook.symbol(t.soundClass), name: SoundClass(rawValue: t.soundClass)?.label ?? "",
                    tally: t)
            }
            let ägare: SoundFacit.ClassTally = facit.ownerTally()
            if ägare.heard > 0 {
                row(symbol: "person.2.fill", name: "ägare", tally: ägare)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(symbol: String, name: String, tally t: SoundFacit.ClassTally) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
            Text(name)
            Spacer()
            Text("\(t.heard)").monospacedDigit().foregroundStyle(.secondary)
            Text(t.wrongShare.map { (x: Double) -> String in "\(Int((x * 100).rounded())) % fel" } ?? "–")
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
            Image(systemName: t.overThreshold ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundStyle(t.overThreshold ? Color.orange : Color.green)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

/// BESLUT B36. En källa: namnet, var den finns och licensen, och DOI när filen har en.
private struct SourceRow: View {
    let source: ModelSource

    private var detalj: String {
        var delar: [String] = [source.place, source.licence]
        if let d = source.doi { delar.append("doi \(d)") }
        if let d = source.articleDOI { delar.append("artikel doi \(d)") }
        return delar.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.name)
            Text(detalj)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// METOD M28 · BESLUT B3. Kontrollen av en natt ur K18: sömnperioden, hur
/// mycket av den som har K18, och hur stämpelns tolkning föll ut (omlagda
/// poster och utelämnade slag). Bara tider, andelar och antal.
private struct K18CheckRow: View {
    let summary: NightSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((summary.titleDate ?? .now)
                    .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.headline)
                if summary.preliminary == true {
                    Text("preliminär").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(summary.origin.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Period").foregroundStyle(.secondary)
                    Text(period).monospacedDigit()
                }
                GridRow {
                    Text("Täckning").foregroundStyle(.secondary)
                    Text(summary.coverage.map(pct) ?? "–").monospacedDigit()
                }
                GridRow {
                    Text("Omlagda").foregroundStyle(.secondary)
                    Text(omlagda).monospacedDigit()
                }
                GridRow {
                    Text("Utelämnade").foregroundStyle(.secondary)
                    Text(utelämnade).monospacedDigit()
                }
            }
            .font(.callout)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var period: String {
        guard let a = summary.start, let b = summary.end else { return "–" }
        return a.formatted(.dateTime.hour().minute()) + "–" + b.formatted(.dateTime.hour().minute())
    }

    private var omlagda: String {
        guard let n = summary.reanchorings, let f = summary.fractionReanchored else { return "–" }
        return "\(pct(f)) · \(n) st"
    }

    private var utelämnade: String {
        guard let n = summary.omittedBeats, let f = summary.fractionOmitted else { return "–" }
        return "\(pct(f)) · \(n) slag"
    }
}

/// BESLUT B30. Ett dygn i listan: datum, storlek, och Exportera (hela dygnet
/// eller natten 18–12 som slutar den dagen).
private struct DayRow: View {
    let day: DayFile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "dot.radiowaves.left.and.right" : "calendar")
                .foregroundStyle(isActive ? Color.green : Color.secondary)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(day.stem)).font(.headline)
                Text(ByteCountFormatter.string(fromByteCount: Int64(day.bytes), countStyle: .file))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DayExportButton(stem: day.stem)
        }
    }

    /// "tis 13 okt" för `dygn-2026-10-13`.
    static func title(_ stem: String) -> String {
        guard let d = DayLog.day(ofStem: stem) else { return stem }
        let mitt = DayLog.date(of: d, hour: 12, utcOffsetSeconds: TimeZone.current.secondsFromGMT())
        return mitt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

struct BatteryBadge: View {
    let percent: Int?

    var body: some View {
        Label(percent.map { "\($0) %" } ?? "–", systemImage: Self.symbol(percent))
            .monospacedDigit()
            .foregroundStyle(lågt ? Tema.red : Color.secondary)
    }

    /// BESLUT B123. Rött under 20 %.
    private var lågt: Bool {
        guard let p = percent else { return false }
        return BandBattery.isLow(p)
    }

    static func symbol(_ p: Int?) -> String {
        guard let p else { return "battery.0" }
        switch p {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }
}

/// En gammal inspelning i listan: dag, längd, om kontrollerna håller, och HRV.
/// En hämtning utan puls (BESLUT B25) visas med en pil i stället för märket.
private struct SummaryRow: View {
    let summary: NightSummary

    var body: some View {
        HStack(spacing: 12) {
            if summary.samples == 0 {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            } else {
                Image(systemName: summary.passes ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(summary.passes ? Color.green : Color.orange)
                    .font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text((summary.end ?? summary.start ?? summary.stopped ?? .now)
                    .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.headline)
                HStack(spacing: 12) {
                    if let s = summary.start, let e = summary.end {
                        Label(Duration.seconds(e.timeIntervalSince(s))
                            .formatted(.units(allowed: [.hours, .minutes], width: .narrow)),
                              systemImage: "bed.double")
                    }
                    if let r = summary.rmssdMean {
                        Label("\(Int(r.rounded())) ms", systemImage: "waveform.path.ecg")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// METOD M12 · BESLUT B14 · BESLUT B3
/// T2: antal ramar per karakteristik och pakettyp. Aldrig innehållet.
struct TallyGrid: View {
    let tally: FrameTally
    var listening: Set<String> = []

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(RawFrame.listened.map(RawFrame.shortName), id: \.self) { k in
                GridRow {
                    Image(systemName: listening.contains(k) ? "ear.fill" : "ear")
                        .foregroundStyle(listening.contains(k) ? Color.green : Color.secondary)
                    Text(k.suffix(4)).font(.body.monospaced())
                    Text("Σ").foregroundStyle(.secondary)
                    Text("\(tally.total(characteristic: k))").monospacedDigit()
                }
                ForEach(tally.rows.filter { $0.key.characteristic == k }) { row in
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        Color.clear.frame(width: 1, height: 1)
                        Text(row.key.packetType.map { "typ \($0)" } ?? "–")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                        Text("\(row.count)").monospacedDigit()
                    }
                }
            }
        }
        .font(.callout)
    }
}

// MARK: Kondition (BESLUT B106)

/// BESLUT B106 · METOD M60 · METOD M61 · METOD M64
/// Sektionen Kondition överst på Data: VO2 max (skattningen ur vila och profil, eller det som saknas) och Whoops
/// VO2 max (de avskrivna talen, för avstämningen). Profilen bor på fliken Profil (BESLUT B111). Tar sina värden och
/// återkopplingar som värden.
struct KonditionSektion: View {
    let lager: FitnessStore
    let skattning: PassiveFitness.Outcome?
    let idag: Date
    var onWhoopTal: (Int, Double) -> Void = { _, _ in }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Label("VO2 max", systemImage: "speedometer")
                if let h = huvudtal {
                    Text(h).font(.title3.weight(.semibold))
                }
                ForEach(underrader, id: \.self) { (rad: String) in
                    Text(rad).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            NavigationLink {
                WhoopTalVy(noter: lager.whoopNotes, idag: idag, onLäggTill: onWhoopTal)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Whoops VO2 max", systemImage: "square.and.pencil")
                    Text(senastText).font(.caption).foregroundStyle(.secondary)
                    Text("Avskrivna tal: \(lager.whoopNotes.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Kondition", systemImage: "figure.walk")
        } footer: {
            Text("Talet räknas på telefonen ur nattens vilopuls och profilen. Det är en nivå med osäkerhet, inte en mätning.")
        }
    }

    /// METOD M61. Talet avrundat till heltal med osäkerheten, eller `nil` när något saknas.
    private var huvudtal: String? {
        guard let s = skattning, case .estimate(let e) = s else { return nil }
        return "\(Int(e.value.rounded())) ± \(Int(e.uncertainty.rounded())) ml/kg/min"
    }

    /// Under talet: var det kommer ifrån, eller på vanlig svenska vad som saknas.
    private var underrader: [String] {
        guard let s = skattning else { return [] }
        switch s {
        case .estimate(let e):
            return ["Vila och profil · \(e.nights) nätter"]
        case .missing(let saknas):
            var rader: [String] = []
            let person: [String] = saknas.compactMap { (m: PassiveFitness.Missing) -> String? in
                switch m {
                case .birthYear: return "födelseår"
                case .sex: return "kön"
                default: return nil
                }
            }
            let kropp: [String] = saknas.compactMap { (m: PassiveFitness.Missing) -> String? in
                switch m {
                case .waist: return "midjemått"
                case .habits: return "träningsvanor"
                default: return nil
                }
            }
            // BESLUT B111. Födelseår och kön fylls i på fliken Profil, resten i Kropp och träningsvanor där.
            if !person.isEmpty { rader.append("Fyll i " + person.joined(separator: " och ") + " under Profil") }
            if !kropp.isEmpty {
                rader.append("Fyll i " + kropp.joined(separator: " och ") + " i Kropp och träningsvanor under Profil")
            }
            if saknas.contains(.nights) {
                rader.append("Behöver minst \(FitnessRules.restingMinNights) nätter med vilopuls de senaste \(FitnessRules.restingWindowDays) dagarna")
            }
            return rader
        }
    }

    /// METOD M64. Det senast avskrivna Whoop-talet med datum.
    private var senastText: String {
        let senast: WhoopFitnessNote? = lager.whoopNotes.max { (a: WhoopFitnessNote, b: WhoopFitnessNote) -> Bool in
            a.day < b.day
        }
        guard let n = senast else { return "Inget tal avskrivet än" }
        return "\(konditionTal(n.value)) ml/kg/min · \(konditionDatum(dag: n.day))"
    }
}

/// BESLUT B106 · METOD M64
/// Whoops VO2 max, avskrivet för hand ur Whoop-appen en gång i veckan: ett datum (idag som förval) och ett tal.
/// Facit för avstämningen så länge Whoop räknar. Ett tal för ett datum som redan har ett ersätter det.
struct WhoopTalVy: View {
    let idag: Date
    let onLäggTill: (Int, Double) -> Void
    @State private var noter: [WhoopFitnessNote]
    @State private var datum: Date
    @State private var text = ""

    init(noter: [WhoopFitnessNote], idag: Date, onLäggTill: @escaping (Int, Double) -> Void = { _, _ in }) {
        self.idag = idag
        self.onLäggTill = onLäggTill
        _noter = State(initialValue: noter.sorted { (a: WhoopFitnessNote, b: WhoopFitnessNote) -> Bool in a.day > b.day })
        _datum = State(initialValue: idag)
    }

    private var värde: Double? { konditionDecimal(text, 10...100) }

    var body: some View {
        List {
            Section {
                DatePicker("Datum", selection: $datum, in: ...idag, displayedComponents: .date)
                LabeledContent("VO2 max (ml/kg/min)") {
                    TextField("–", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Button("Lägg till") { läggTill() }
                    .disabled(värde == nil)
            } header: {
                Text("Skriv av ur Whoop-appen")
            } footer: {
                Text("Ett tal i veckan räcker. Ett nytt tal för samma datum ersätter det gamla.")
            }

            Section {
                if noter.isEmpty {
                    Text("Inga tal avskrivna än").foregroundStyle(.secondary)
                }
                ForEach(noter, id: \.day) { (n: WhoopFitnessNote) in
                    HStack {
                        Text(konditionDatum(dag: n.day))
                        Spacer()
                        Text("\(konditionTal(n.value)) ml/kg/min").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Avskrivna tal: \(noter.count)")
            }
        }
        .navigationTitle("Whoops VO2 max")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private func läggTill() {
        guard let v = värde else { return }
        let dag: Int = WakeDay(datum, utcOffsetSeconds: TimeZone.current.secondsFromGMT(for: datum)).daysSince1970
        onLäggTill(dag, v)
        var ny: [WhoopFitnessNote] = noter.filter { (n: WhoopFitnessNote) -> Bool in n.day != dag }
        ny.append(WhoopFitnessNote(day: dag, value: v))
        noter = ny.sorted { (a: WhoopFitnessNote, b: WhoopFitnessNote) -> Bool in a.day > b.day }
        text = ""
    }
}

/// Ett helt tal ur ett fält inom ett rimligt område; tomt eller orimligt är `nil`.
func konditionHeltal(_ text: String, _ område: ClosedRange<Int>) -> Int? {
    guard let v = Int(text.trimmingCharacters(in: .whitespaces)), område.contains(v) else { return nil }
    return v
}

/// Ett tal med decimalkomma eller punkt ur ett fält inom ett rimligt område; tomt eller orimligt är `nil`.
func konditionDecimal(_ text: String, _ område: ClosedRange<Double>) -> Double? {
    let rent: String = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard let v = Double(rent), område.contains(v) else { return nil }
    return v
}

/// Ett tal utan onödiga decimaler: 88 och 52,5.
func konditionTal(_ v: Double) -> String {
    if v == v.rounded() { return String(Int(v)) }
    return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
}

/// Dagnumret (dagar sedan 1970-01-01) som "12 nov. 2026".
private func konditionDatum(dag: Int) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "sv_SE")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "d MMM yyyy"
    return f.string(from: Date(timeIntervalSince1970: Double(dag) * 86_400))
}
