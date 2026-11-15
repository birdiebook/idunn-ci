import Foundation
import WhoopImport
import SleepNeed

/// Håller den importerade exporten. Filerna kopieras in i appens egen
/// Application Support och lämnar aldrig telefonen — ingen server, inget moln.
@MainActor
final class Store: ObservableObject {
    /// BESLUT B67. Grundbehovet ur exporten går till sömnbehovet; talet lämnar aldrig telefonen.
    @Published private(set) var export: WhoopExport? {
        didSet { SömnbehovModell.shared.sätt(grundUtifrån: export.flatMap { SleepNeed.whoopBase($0) }) }
    }
    @Published var error: String?

    private let folder: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("whoop-export", isDirectory: true)

    init() {
        do { try load() } catch { self.error = "\(error)" }
        // didSet körs inte säkert under init: skicka grundbehovet en gång här också (BESLUT B67).
        SömnbehovModell.shared.sätt(grundUtifrån: export.flatMap { SleepNeed.whoopBase($0) })
    }

    /// Tar emot filerna ur den uppackade exporten. Okända filer hoppas över,
    /// så det går bra att markera allt i mappen.
    func importFiles(_ urls: [URL]) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var tagna = 0
            for url in urls where WhoopExport.knownFiles.contains(url.lastPathComponent) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let target = folder.appendingPathComponent(url.lastPathComponent)
                // Läs och tolka FÖRE kopieringen, så en trasig fil aldrig ersätter en hel.
                let text = try String(contentsOf: url, encoding: .utf8)
                try validate(text, name: url.lastPathComponent)
                try text.write(to: target, atomically: true, encoding: .utf8)
                tagna += 1
            }
            guard tagna > 0 else {
                error = "Välj filerna ur Whoop-exporten (\(WhoopExport.cyclesFile) med flera)."
                return
            }
            try load()
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }

    private func validate(_ text: String, name: String) throws {
        switch name {
        case WhoopExport.cyclesFile: _ = try WhoopExport.parseCycles(text)
        case WhoopExport.sleepsFile: _ = try WhoopExport.parseSleeps(text)
        case WhoopExport.journalFile: _ = try WhoopExport.parseJournal(text)
        default: break
        }
    }

    private func load() throws {
        export = try WhoopExport.load(directory: folder)
    }
}
