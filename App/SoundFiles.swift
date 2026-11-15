import Foundation
import Night
import Sound

/// METOD M44 · BESLUT B54
/// Ljudfilerna som nätterna läser när de räknas. Lyssnaren (`SoundListener`) skriver
/// `ljud/ljud-<start>.ljud` med `.markningar` bredvid; vilka filer en natt hör till,
/// och vad som räknas ur dem, avgör IdunnKit (`SoundNights`, `NightSoundMaker`, provat på
/// Linux). Här läses bara filerna. Inget lämnar telefonen.
enum SoundFiles {
    static var folder: URL {
        SoundListener.defaultRoot.appendingPathComponent("ljud", isDirectory: true)
    }

    /// Alla ljudfilers stammar (`ljud-2026-10-14T21-03-00Z`), äldst först.
    static func stems() -> [String] {
        let namn: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return namn.filter { (n: String) -> Bool in n.hasSuffix(".ljud") }
            .map { (n: String) -> String in String(n.dropLast(".ljud".count)) }
            .sorted()
    }

    /// Måtten och märkena för en stam; `nil` när måtten saknas.
    static func load(_ stem: String) -> SoundNights.Raw? {
        guard let mått = try? Data(contentsOf: folder.appendingPathComponent(stem + ".ljud")) else { return nil }
        let märken: Data? = try? Data(contentsOf: folder.appendingPathComponent(stem + ".markningar"))
        return SoundNights.Raw(measures: mått, marks: märken)
    }

    /// METOD M45 · BESLUT B55. Nattens tal för datorn, bredvid `.ljud`-filen: `ljud-<start>.sammanfattning.json`.
    /// Skrivs atomärt, och följer med Exportera (`SoundExport`).
    static func saveSummary(_ stem: String, _ data: Data) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NightFiles.write(data, to: folder.appendingPathComponent(SoundSummary.fileName(stem: stem)))
    }

    /// Analysen en natt kör med sina filer när den räknas (`K18Days`, `NightLedger`). Med `writeSummary` skriver den
    /// också sammanfattningen för exporten; telefonen gör det när nätterna räknas, inte när kurvan öppnas.
    static func analyzer(writeSummary: Bool = false) -> NightSound.Analyzer {
        SoundNights.analyzer(stems: stems(), load: { (s: String) -> SoundNights.Raw? in load(s) },
                             saveSummary: writeSummary ? { (s: String, d: Data) -> Void in saveSummary(s, d) } : nil)
    }
}
