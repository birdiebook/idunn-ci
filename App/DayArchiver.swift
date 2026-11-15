import Foundation
import WhoopFrames

/// METOD M34 · BESLUT B41 · BESLUT B30 · PLAN.md L1
/// Lagringen i appen: arkiverar färdiga dygn och raderar gamla rådygn. Allt
/// som är ett beslut ligger i IdunnKit (`ArchiveRule`, `DayArchive`, provat på
/// Linux); här läses och skrivs filerna.
///
/// För varje dygn med ett rådygn, utom det som skrivs just nu:
///
/// 1. Färdigt dygn utan arkiv (eller med ett arkiv byggt ur ett rådygn av annan
///    storlek): bygg arkivet, skriv det, **läs tillbaka det från disken** och
///    kontrollera att det är det som skulle skrivas (`isWrittenCorrectly`).
///    Ett arkiv som redan finns slås ihop med rådygnet i stället för att
///    ersättas (`DayArchive.updated`), så inget som stod där försvinner.
/// 2. Rådygn äldre än 14 dagar: läs arkivet och rådygnet igen och radera
///    rådygnet bara om arkivet täcker allt i det (`mayDeleteRaw`).
///
/// Rådygnen sätts utanför iCloud-säkerhetskopian när de skapas (`AppendFile`)
/// och en gång till här för dem som fanns före BESLUT B41. Documents-kopior
/// rörs aldrig. Körs på en bakgrundskö, ett varv i taget.
enum DayArchiver {

    struct Outcome: Equatable {
        /// Dygn vars arkiv skrevs och lästes tillbaka.
        var written: [String] = []
        /// Dygn vars rådygn raderades.
        var deleted: [String] = []
        /// Dygn där skrivningen eller kontrollen fallerade. Rådygnet ligger kvar.
        var failed: [String] = []
    }

    /// Ett varv i taget: ett andra anrop väntar in det första och hittar då
    /// inget kvar att göra.
    private static let serial = DispatchQueue(label: "se.birdiebook.idun.arkiv", qos: .utility)

    /// `skip`: dygnen som skrivs just nu (öppna filer, dagens datum).
    @discardableResult
    static func run(now: Date = Date(), skip: Set<String> = []) -> Outcome {
        serial.sync { sweep(now: now, skip: skip) }
    }

    private static func sweep(now: Date, skip: Set<String>) -> Outcome {
        var ut = Outcome()
        let zon: Int = TimeZone.current.secondsFromGMT(for: now)
        for stem in NightFiles.dayStems() where !skip.contains(stem) {
            guard let dag = DayLog.day(ofStem: stem) else { continue }
            let ramarURL = NightFiles.frames(stem)
            let sidaURL = NightFiles.pulse(stem)
            let finnsRamar = FileManager.default.fileExists(atPath: ramarURL.path)
            let finnsSida = FileManager.default.fileExists(atPath: sidaURL.path)
            guard finnsRamar || finnsSida else { continue }
            if finnsRamar && !NightFiles.isExcludedFromBackup(ramarURL) { NightFiles.excludeFromBackup(ramarURL) }
            if finnsSida && !NightFiles.isExcludedFromBackup(sidaURL) { NightFiles.excludeFromBackup(sidaURL) }

            let arkivURL = NightFiles.archive(stem)
            let huvud: DayArchive.Header? = (try? Data(contentsOf: arkivURL, options: .mappedIfSafe))
                .flatMap { (d: Data) -> DayArchive.Header? in try? DayArchive.Header.read(d) }
            let behövs: Bool = ArchiveRule.needsArchive(
                day: dag, now: now, utcOffsetSeconds: zon,
                rawFrameBytes: finnsRamar ? NightFiles.fileSize(ramarURL) : nil,
                rawSidecarBytes: finnsSida ? NightFiles.fileSize(sidaURL) : nil,
                header: huvud)
            if behövs {
                if write(day: dag, sidecar: sidaURL, frames: ramarURL, archive: arkivURL) {
                    ut.written.append(stem)
                } else {
                    ut.failed.append(stem)
                    continue
                }
            }

            guard ArchiveRule.isRawExpired(dag, now: now, utcOffsetSeconds: zon) else { continue }
            let arkiv: Data? = try? Data(contentsOf: arkivURL)
            let sida: Data? = try? Data(contentsOf: sidaURL)
            let ramar: Data? = try? Data(contentsOf: ramarURL, options: .mappedIfSafe)
            guard ArchiveRule.mayDeleteRaw(day: dag, now: now, utcOffsetSeconds: zon,
                                           archive: arkiv, rawFrames: ramar, rawSidecar: sida) else {
                ut.failed.append(stem)
                continue
            }
            try? FileManager.default.removeItem(at: ramarURL)
            try? FileManager.default.removeItem(at: sidaURL)
            ut.deleted.append(stem)
        }
        return ut
    }

    /// Bygger arkivet ur rådygnet, slår ihop det med ett som redan finns, skriver
    /// det och läser tillbaka det. Sant bara om det som lästs är det som skulle skrivas.
    private static func write(day: DayLog.Day, sidecar: URL, frames: URL, archive: URL) -> Bool {
        let sida: Data? = try? Data(contentsOf: sidecar)
        let ramar: Data? = try? Data(contentsOf: frames, options: .mappedIfSafe)
        var nytt: DayArchive = DayArchive.build(day: day, sidecar: sida, frames: ramar)
        if let gammalt = try? Data(contentsOf: archive, options: .mappedIfSafe),
           let gammal = try? DayArchive.decode(gammalt) {
            nytt = gammal.updated(with: nytt)
        }
        do {
            try NightFiles.prepareFolder()
            try nytt.encode().write(to: archive, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return false
        }
        let tillbaka: Data? = try? Data(contentsOf: archive)
        return ArchiveRule.isWrittenCorrectly(readBack: tillbaka, expected: nytt)
    }
}

/// METOD M34 · BESLUT B41. Vad lagringen väger, i byte, för sidan Data.
struct StorageUsage: Equatable {
    /// Rådygn: sidofilerna och notiserna, och antal dygn.
    var rawBytes = 0
    var rawDays = 0
    /// Arkiv, och antal dygn.
    var archiveBytes = 0
    var archiveDays = 0
    /// Nätternas resultat: `natt-….k18.json` och gamla sammanfattningar.
    var resultBytes = 0
    var resultNights = 0
    /// Gamla inspelningar (före lyssnaren).
    var oldBytes = 0
    /// Kopior i Documents/recordings (Filer), från före BESLUT B41.
    var copyBytes = 0

    var totalBytes: Int { rawBytes + archiveBytes + resultBytes + oldBytes }

    /// Medelstorlek per arkiverat dygn, eller `nil` utan arkiv.
    var archiveBytesPerDay: Int? { archiveDays > 0 ? archiveBytes / archiveDays : nil }

    /// Mäter mappen. Bara filstorlekar; läser inget innehåll.
    static func measure() -> StorageUsage {
        var u = StorageUsage()
        let namn: [String] = (try? FileManager.default.contentsOfDirectory(atPath: NightFiles.folder.path)) ?? []
        for n in namn {
            let bytes = NightFiles.fileSize(NightFiles.folder.appendingPathComponent(n))
            if n.hasSuffix(".arkiv") {
                u.archiveBytes += bytes
                u.archiveDays += 1
            } else if n.hasPrefix(DayLog.prefix), n.hasSuffix(".jsonl") {
                u.rawBytes += bytes
                if n.hasSuffix(".t2.jsonl") { u.rawDays += 1 }
            } else if n.hasSuffix(".k18.json") || n.hasSuffix(".summary.json") {
                u.resultBytes += bytes
                if n.hasSuffix(".k18.json") { u.resultNights += 1 }
            } else if n.hasSuffix(".jsonl") {
                u.oldBytes += bytes
            }
        }
        let kopior: [String] = (try? FileManager.default.contentsOfDirectory(atPath: NightExport.folder.path)) ?? []
        for n in kopior { u.copyBytes += NightFiles.fileSize(NightExport.folder.appendingPathComponent(n)) }
        return u
    }
}
