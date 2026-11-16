import SwiftUI
import UIKit
import HeartRate
import Pass
import Sound
import WhoopFrames

/// BESLUT B22 · BESLUT B23 · BESLUT B3 · METOD M20 · BESLUT B55
/// En natt ut från telefonen, bara när användaren själv trycker. Inget skickas
/// automatiskt, och appen har ingen nätverkskod.
///
/// - **Exportera** på en natt packar den till en zip-fil och öppnar
///   delningsbladet: hela natten (`idunn-<start>.zip`, puls, märken och Whoops
///   råa notiser) eller bara tiden utan band (`idunn-ejburen-<start>.zip`,
///   ingen puls). Vart filen går väljer användaren.
/// - Gamla inspelningars `.jsonl` och `.t2.jsonl` kopieras dessutom till appens
///   Documents/recordings, som syns i Filer och i Apple Devices över kabel
///   (`UIFileSharingEnabled` i project.yml). Originalen ligger kvar i
///   Application Support, där appen läser dem. En natt som tas bort i appen
///   tas bort även här; en kopia som tas bort i Filer kommer tillbaka nästa gång
///   listan läses om, så länge natten finns. **Dygn kopieras inte** (BESLUT B41,
///   som ersätter den här delen av B22): kopior från före B41 ligger kvar orörda.
/// - **Exportera** på ett dygn (BESLUT B30) packar dygnets filer (`idunn-dygn-<datum>.zip`),
///   eller natten 18–12 som slutar den dagen ur dygnet och dygnet före
///   (`idunn-dygn-<från>-<till>.zip`, notiser och märken i tidsordning).
/// - **Ljudet** (BESLUT B47, B55): en export av hela natten, ett dygn eller natten
///   18–12 tar med ljudfilerna som överlappar tiden (`ljud/…`, mått, märken och
///   nattens tal om de finns). Klippen följer bara med valet "Med ljudklipp"
///   (`idunn-…-ljudklipp.zip`); utan det öppnas ingen klippfil. "Bara utan band"
///   är ett prov på bandet och tar inget ljud. Vilka filer och hur de läggs i
///   zip-filen avgör IdunnKits `SoundExport`; här anropas det bara.
enum NightExport {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings", isDirectory: true)
    }

    /// Nattens filer i Application Support som finns: puls och T2-notiser.
    static func files(_ stem: String) -> [URL] {
        [NightFiles.pulse(stem), NightFiles.frames(stem)]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Kopierar varje färdig gammal inspelning vars kopia saknas eller har annan
    /// storlek. **Dygn kopieras inte längre** (BESLUT B41): Exportera ersätter
    /// kopian, och rådygnen raderas efter 14 dagar. Kopior som redan ligger i
    /// Documents lämnas orörda; användaren tar bort dem själv i Filer. Körs i
    /// bakgrunden när listan läses om (start och dygnsbyte).
    static func mirror() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: NightFiles.protection])
        } catch {
            return
        }
        for stem in NightFiles.stems() {
            for src in files(stem) {
                let dst = folder.appendingPathComponent(src.lastPathComponent)
                if size(src) == size(dst) { continue }
                try? fm.removeItem(at: dst)
                do {
                    try fm.copyItem(at: src, to: dst)
                    try fm.setAttributes([.protectionKey: NightFiles.protection], ofItemAtPath: dst.path)
                } catch {
                    continue
                }
            }
        }
    }

    static func remove(_ stem: String) {
        for name in [stem + ".jsonl", stem + ".t2.jsonl"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// BESLUT B55. Ljudets rotmapp: samma Application Support som lyssnaren skriver i.
    static var soundRoot: URL { SoundListener.defaultRoot }

    /// BESLUT B55. `zip` med ljudet som överlappar `[from, to]` efter de filer som fanns,
    /// och med `withClips` klippen. `nil` när zip-filen inte gick att bygga vidare på.
    private static func withSound(_ zip: Data, from: Date, to: Date, withClips: Bool) -> Data? {
        SoundExport.extend(zip, root: soundRoot, from: from, to: to, withClips: withClips)
    }

    /// Filnamnet: med klippen får zip-filen `-ljudklipp` i namnet.
    private static func named(_ name: String, withClips: Bool) -> String {
        withClips ? SoundExport.clipFileName(name) : name
    }

    enum PackageError: Error {
        case unreadable
        case nothingOffWrist
        case nothingInInterval
    }

    /// Nattens zip i en tillfällig mapp, för delningsbladet. Ett dygn vars rådygn
    /// är raderat packas ur arkivet (BESLUT B41): K18, K26, händelser och
    /// synkmärken som en notis per ram. Det som inte sparas i arkivet saknas i
    /// zip-filen (loggtext, kommandosvar, notisernas uppdelning).
    static func package(stem: String, offWristOnly: Bool, withClips: Bool = false) -> Result<URL, PackageError> {
        guard let delar = NightFiles.dayData(stem) else { return .failure(.unreadable) }
        let pulse = delar.pulse
        let frames = delar.frames
        let zip: Data
        if offWristOnly {
            guard let z = ExportPackage.offWrist(stem: stem, pulse: pulse, frames: frames ?? Data()).zip else {
                return .failure(.nothingOffWrist)
            }
            zip = z
        } else {
            let natt = ExportPackage.full(stem: stem, pulse: pulse, frames: frames)
            let zon = TimeZone.current.secondsFromGMT()
            if let tid = SoundExport.exportSpan(stem: stem, pulse: pulse, utcOffsetSeconds: zon) {
                guard let med = withSound(natt, from: tid.from, to: tid.to, withClips: withClips) else {
                    return .failure(.unreadable)
                }
                zip = med
            } else {
                zip = natt
            }
        }
        return writeTemporary(zip, name: named(ExportPackage.fileName(stem: stem, offWristOnly: offWristOnly),
                                               withClips: withClips && !offWristOnly))
    }

    /// BESLUT B30 · METOD M27. Natten 18–12 som slutar 12:00 på dygnet `stem`:
    /// notiser och märken ur det dygnet och dygnet före.
    static func packageNight(endingOn stem: String, withClips: Bool = false) -> Result<URL, PackageError> {
        guard let dag = DayLog.day(ofStem: stem) else { return .failure(.unreadable) }
        let zon = TimeZone.current.secondsFromGMT()
        let w = NightWindow.ending(on: dag, utcOffsetSeconds: zon)
        return package(from: w.start, to: w.end, utcOffsetSeconds: zon, withClips: withClips)
    }

    /// BESLUT B30. Ett tidsintervall (gärna över midnatt) ur dygnsfilerna.
    static func package(from: Date, to: Date, utcOffsetSeconds zon: Int,
                        withClips: Bool = false) -> Result<URL, PackageError> {
        var delar: [ExportPackage.DayPart] = []
        for stem in DayLog.stems(touching: from, to: to, utcOffsetSeconds: zon) {
            guard let dygn = NightFiles.dayData(stem) else { continue }
            delar.append(ExportPackage.DayPart(stem: stem, pulse: dygn.pulse, frames: dygn.frames))
        }
        let r = ExportPackage.interval(parts: delar, from: from, to: to, utcOffsetSeconds: zon)
        guard let natt = r.zip else { return .failure(.nothingInInterval) }
        guard let zip = withSound(natt, from: from, to: to, withClips: withClips) else {
            return .failure(.unreadable)
        }
        return writeTemporary(zip, name: named(r.name, withClips: withClips))
    }

    private static func writeTemporary(_ zip: Data, name: String) -> Result<URL, PackageError> {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let url = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try zip.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return .failure(.unreadable)
        }
        return .success(url)
    }

    private static func size(_ url: URL) -> Int? {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attr[.size] as? NSNumber)?.intValue
    }
}

extension NightExport {
    /// BESLUT B66 · BESLUT B41. Alla dygn och alla pass till avstämningen mot Whoop (`tools/avstamning.py`): en zip
    /// per dygn, som "Hela dygnet" (ur rådygnet eller arkivet), passens filer, ändringarna av sömnen (B70) och konditionen (B106), i en mapp
    /// för delningsbladet. Ett dygn i taget, så att minnet räcker. Ljudet följer inte med. `nil` när inget gick att skriva.
    static func packageAll() -> [URL]? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("export-alla", isDirectory: true)
        try? fm.removeItem(at: dir)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        var ut: [URL] = []
        for stem in NightFiles.dayStems() {
            autoreleasepool {
                guard let d = NightFiles.dayData(stem) else { return }
                let zip: Data = ExportPackage.full(stem: stem, pulse: d.pulse, frames: d.frames)
                let url = dir.appendingPathComponent(ExportPackage.fileName(stem: stem, offWristOnly: false))
                if (try? zip.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil {
                    ut.append(url)
                }
            }
        }
        let pass: [URL] = (try? fm.contentsOfDirectory(at: PassController.folder, includingPropertiesForKeys: nil)) ?? []
        // BESLUT B107 · BESLUT B110. Passen skrivs UTAN spår: positionerna visar var användaren bor och rör sig och
        // lämnar telefonen bara med "Exportera med spår" på ett enskilt pass, aldrig med Exportera alla dygn.
        for f in pass where f.pathExtension == "json" {
            let mål = dir.appendingPathComponent(f.lastPathComponent)
            guard let data = try? Data(contentsOf: f), let p = try? PassFile.decode(data),
                  let utan = try? PassFile.encode(p.withoutTrack()) else { continue }
            if (try? utan.write(to: mål, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil {
                ut.append(mål)
            }
        }
        // METOD M55 · BESLUT B70. användaren ändringar av sömnperioden (`somn-andringar.json`), för avstämningen.
        if fm.fileExists(atPath: SleepEditFile.url.path) {
            let mål = dir.appendingPathComponent(SleepEditFile.url.lastPathComponent)
            if (try? fm.copyItem(at: SleepEditFile.url, to: mål)) != nil { ut.append(mål) }
        }
        // BESLUT B106 · METOD M60 · METOD M64. Profilen och Whoops avskrivna VO2 max-tal (`kondition.json`).
        if fm.fileExists(atPath: KonditionModell.standardfil.path) {
            let mål = dir.appendingPathComponent(KonditionModell.standardfil.lastPathComponent)
            if (try? fm.copyItem(at: KonditionModell.standardfil, to: mål)) != nil { ut.append(mål) }
        }
        // METOD M59 · BESLUT B105. Det användaren skrivit in i profilen (`markorer.json`): mätningarna och de egna markörerna.
        if fm.fileExists(atPath: ProfilModell.fil.path) {
            let mål = dir.appendingPathComponent(ProfilModell.fil.lastPathComponent)
            if (try? fm.copyItem(at: ProfilModell.fil, to: mål)) != nil { ut.append(mål) }
        }
        return ut.isEmpty ? nil : ut
    }
}

/// BESLUT B66. "Exportera alla dygn" på Data: alla dygn och pass som filer i delningsbladet, för avstämningen mot
/// Whoop. Packningen läser ett dygn i taget och körs bort från huvudtråden.
struct AllDaysExportButton: View {
    @State private var delade: SharedFiles?
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        Button {
            working = true
            Task.detached {
                let urls: [URL]? = NightExport.packageAll()
                await MainActor.run {
                    working = false
                    if let u = urls { delade = SharedFiles(urls: u) } else { problem = "Inga dygn gick att läsa." }
                }
            }
        } label: {
            HStack {
                Label("Exportera alla dygn", systemImage: "square.and.arrow.up.on.square")
                Spacer()
                if working { ProgressView() }
            }
        }
        .disabled(working)
        .sheet(item: $delade) { f in
            ActivitySheet(items: f.urls)
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

private struct SharedFiles: Identifiable {
    let urls: [URL]
    var id: String { urls.first?.path ?? "" }
}

/// BESLUT B22 · BESLUT B23. "Exportera" på en natt: hela natten, eller bara
/// tiden utan band på handleden, som en zip i delningsbladet.
struct RawExportButton: View {
    let stem: String
    @State private var shared: SharedFile?
    @State private var problem: String?

    var body: some View {
        Menu {
            Button {
                share(offWristOnly: false)
            } label: {
                Label("Hela natten", systemImage: "doc.zipper")
            }
            Button {
                share(offWristOnly: true)
            } label: {
                Label("Bara utan band", systemImage: "hand.raised.slash")
            }
            Button {
                share(offWristOnly: false, withClips: true)
            } label: {
                Label("Med ljudklipp", systemImage: "waveform")
            }
        } label: {
            Label("Exportera", systemImage: "square.and.arrow.up")
        }
        .disabled(NightExport.files(stem).isEmpty)
        .sheet(item: $shared) { f in
            ActivitySheet(items: [f.url])
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

    private func share(offWristOnly: Bool, withClips: Bool = false) {
        switch NightExport.package(stem: stem, offWristOnly: offWristOnly, withClips: withClips) {
        case .success(let url):
            shared = SharedFile(url: url)
        case .failure(.nothingOffWrist):
            problem = "Natten har inga märken utan band (av, skak, still, kyl, rum)."
        case .failure(.nothingInInterval):
            problem = "Inga notiser i intervallet."
        case .failure(.unreadable):
            problem = "Natten gick inte att läsa."
        }
    }
}

/// BESLUT B30 · BESLUT B22 · BESLUT B23. "Exportera" på ett dygn: hela
/// dygnet, eller natten 18–12 som slutar den dagen (över midnatt), som en zip
/// i delningsbladet. Packningen läser tiotals MB och körs bort från huvudtråden.
struct DayExportButton: View {
    let stem: String
    @State private var shared: SharedFile?
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        Menu {
            Button {
                run { NightExport.package(stem: stem, offWristOnly: false) }
            } label: {
                Label("Hela dygnet", systemImage: "doc.zipper")
            }
            Button {
                run { NightExport.packageNight(endingOn: stem) }
            } label: {
                Label("Natten till den här dagen (18–12)", systemImage: "moon.zzz")
            }
            Button {
                run { NightExport.package(stem: stem, offWristOnly: false, withClips: true) }
            } label: {
                Label("Hela dygnet med ljudklipp", systemImage: "waveform")
            }
            Button {
                run { NightExport.packageNight(endingOn: stem, withClips: true) }
            } label: {
                Label("Natten med ljudklipp (18–12)", systemImage: "waveform")
            }
        } label: {
            if working {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(working)
        .accessibilityLabel("Exportera")
        .sheet(item: $shared) { f in
            ActivitySheet(items: [f.url])
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

    private func run(_ jobb: @escaping @Sendable () -> Result<URL, NightExport.PackageError>) {
        working = true
        Task.detached {
            let r = jobb()
            await MainActor.run {
                working = false
                switch r {
                case .success(let url): shared = SharedFile(url: url)
                case .failure(.nothingInInterval): problem = "Inga notiser i intervallet."
                case .failure(.nothingOffWrist): problem = "Inga märken utan band."
                case .failure(.unreadable): problem = "Dygnet gick inte att läsa."
                }
            }
        }
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// UIActivityViewController med filen som den är.
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// METOD M20. "Märk": ett ord med telefonens tid i dygnets sidofil, så att
/// proven utan band på handleden (av, skak, still, kyl, rum, och på när bandet
/// sitter igen) kan läggas mot ramarna efteråt (`tools/t2_analys.py`). Alltid
/// tillgänglig, eftersom lyssnaren alltid skriver; visar senaste ordet.
struct MarkMenu: View {
    let lastLabel: String?
    let count: Int
    let onMark: (String) -> Void

    var body: some View {
        Menu {
            ForEach(RecordingLog.markerLabels, id: \.self) { ord in
                Button(ord) { onMark(ord) }
            }
        } label: {
            Label(lastLabel ?? "Märk", systemImage: "flag")
                .labelStyle(.titleAndIcon)
        }
        .sensoryFeedback(.selection, trigger: count)
        .accessibilityLabel("Märk")
    }
}
