import SwiftUI

/// BESLUT B41 · METOD M34 · PLAN.md L1
/// Lagringen som en sektion på sidan Data: vad råa dygn, arkiv och nätternas
/// resultat väger. Siffrorna är det som PLAN.md L1 ber om: den verkliga
/// storleken per dygn, mätt på telefonen. Värden in (`StorageUsage`), så att
/// provet kan rita sektionen med påhittade tal; mätningen görs i `Recorder`.
///
/// Läggs in i `DataScreen`s `List`, där lagringen hör hemma bland dygnen:
/// `StorageSection(usage: storage)`.
struct StorageSection: View {
    let usage: StorageUsage

    var body: some View {
        Section {
            row("Råa dygn", usage.rawBytes, detail: dagar(usage.rawDays))
            row("Arkiv", usage.archiveBytes, detail: dagar(usage.archiveDays) + snitt)
            row("Nätternas resultat", usage.resultBytes, detail: nätter(usage.resultNights))
            if usage.oldBytes > 0 {
                row("Gamla inspelningar", usage.oldBytes, detail: nil)
            }
            LabeledContent("Totalt i appen") {
                Text(Self.size(usage.totalBytes)).font(.body.weight(.semibold)).monospacedDigit()
            }
            if usage.copyBytes > 0 {
                row("Kopior i Filer", usage.copyBytes, detail: "från före arkivet, tas bort i Filer")
            }
        } header: {
            Label("Lagring", systemImage: "internaldrive")
        } footer: {
            Text("Råa dygn sparas i 14 dagar och raderas när arkivet är kontrollerat. Arkiv och resultat sparas för alltid och följer med säkerhetskopian; råa dygn gör det inte.")
        }
    }

    private func row(_ title: String, _ bytes: Int, detail: String?) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.size(bytes)).monospacedDigit()
                if let d = detail { Text(d).font(.caption).foregroundStyle(.secondary) }
            }
        } label: {
            Text(title)
        }
    }

    private var snitt: String {
        usage.archiveBytesPerDay.map { " · " + Self.size($0) + " per dygn" } ?? ""
    }

    private func dagar(_ n: Int) -> String { n == 1 ? "1 dygn" : "\(n) dygn" }

    private func nätter(_ n: Int) -> String { n == 1 ? "1 natt" : "\(n) nätter" }

    /// "12,3 MB".
    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

extension StorageUsage {
    /// Påhittade tal för provet (`IdunnProv`): två veckors råa dygn, tre månader arkiv.
    static let demo = StorageUsage(rawBytes: 268_000_000, rawDays: 14, archiveBytes: 190_000_000,
                                   archiveDays: 90, resultBytes: 410_000, resultNights: 90,
                                   oldBytes: 0, copyBytes: 0)
}
