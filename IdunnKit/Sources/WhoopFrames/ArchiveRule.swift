import Foundation

/// METOD M34 · BESLUT B41 · METOD M28 · BESLUT B30
/// När ett dygn arkiveras och när dess rådygn får raderas (PLAN.md L1). Bara
/// värden in och ett ja eller nej ut: appen läser filerna, frågar här och gör
/// det svaret säger, så att regeln går att pröva på Linux.
///
/// - **Färdigt dygn:** arkivet skrivs när dygnet slutat och `closeMarginHours`
///   gått. Dygnsfilen heter efter datumet notisen hördes (METOD M27), så en
///   senare synk hamnar i ett senare dygn och rör aldrig ett färdigt arkiv. Natten
///   som Whoop synkar sent "sätter sig" 24 timmar efter fönstrets slut
///   (`NightLedger.settleHours`); den läser samma poster ur arkivet som ur
///   rådygnet, så arkivet behöver inte vänta in den.
/// - **Rådygnet raderas** först när (1) det är äldre än `keepRawDays`, (2)
///   arkivet finns, går att läsa tillbaka från disken, och (3) täcker allt
///   rådygnet innehåller (`DayArchive.covers`). Saknas något av tre, kvarstår
///   rådygnet.
public enum ArchiveRule {
    /// Timmar efter midnatt innan ett dygn anses färdigt. **Antagande**: filen
    /// skrivs bara medan datumet gäller, så marginalen täcker det som hinner
    /// ske vid dygnsbytet (sista skrivningen, en tidszon som flyttar datumet).
    public static let closeMarginHours: Double = 3

    /// Dagar efter dygnets slut som rådygnet ligger kvar. användaren val
    /// 2026-10-13 (PLAN.md L1): 14.
    public static let keepRawDays = 14

    /// Dygnets slut: midnatt efter datumet i zonen `utcOffsetSeconds`.
    public static func end(of day: DayLog.Day, utcOffsetSeconds: Int) -> Date {
        DayLog.date(of: DayLog.shifted(day, by: 1), utcOffsetSeconds: utcOffsetSeconds)
    }

    /// Har dygnet slutat, med marginalen?
    public static func isClosed(_ day: DayLog.Day, now: Date, utcOffsetSeconds: Int) -> Bool {
        now >= end(of: day, utcOffsetSeconds: utcOffsetSeconds).addingTimeInterval(closeMarginHours * 3600)
    }

    /// Är rådygnet äldre än `keepRawDays`, räknat från dygnets slut?
    public static func isRawExpired(_ day: DayLog.Day, now: Date, utcOffsetSeconds: Int) -> Bool {
        now >= end(of: day, utcOffsetSeconds: utcOffsetSeconds).addingTimeInterval(Double(keepRawDays) * 86_400)
    }

    /// Ska arkivet skrivas (om)? Sant för ett färdigt dygn som har ett rådygn och
    /// antingen inget arkiv, ett arkiv av annan version, eller ett arkiv byggt
    /// ur ett rådygn av annan storlek (det har vuxit). `rawFrameBytes` och
    /// `rawSidecarBytes` är `nil` när filen saknas; `header` är arkivets huvud om
    /// det finns och går att läsa.
    public static func needsArchive(day: DayLog.Day, now: Date, utcOffsetSeconds: Int,
                                    rawFrameBytes: Int?, rawSidecarBytes: Int?,
                                    header: DayArchive.Header?) -> Bool {
        guard isClosed(day, now: now, utcOffsetSeconds: utcOffsetSeconds) else { return false }
        guard rawFrameBytes != nil || rawSidecarBytes != nil else { return false }
        guard let h = header, h.version == DayArchive.version else { return true }
        return h.sourceFrameBytes != (rawFrameBytes ?? 0) || h.sourceSidecarBytes != (rawSidecarBytes ?? 0)
    }

    /// Får rådygnet raderas? `archive` är arkivfilens byte, **inlästa från
    /// disken efter att den skrivits**; `rawFrames` och `rawSidecar` är
    /// rådygnets filer. Nej om dygnet är yngre än `keepRawDays`, om arkivet
    /// saknas eller inte går att läsa, eller om det inte täcker allt rådygnet
    /// innehåller.
    public static func mayDeleteRaw(day: DayLog.Day, now: Date, utcOffsetSeconds: Int,
                                    archive: Data?, rawFrames: Data?, rawSidecar: Data?) -> Bool {
        guard isRawExpired(day, now: now, utcOffsetSeconds: utcOffsetSeconds) else { return false }
        guard let archive, let stored = try? DayArchive.decode(archive) else { return false }
        let raw = DayArchive.build(day: day, sidecar: rawSidecar, frames: rawFrames)
        return stored.covers(raw)
    }

    /// Är arkivfilen, läst tillbaka från disken, det som skulle skrivas?
    public static func isWrittenCorrectly(readBack: Data?, expected: DayArchive) -> Bool {
        guard let readBack, let stored = try? DayArchive.decode(readBack) else { return false }
        return stored == expected
    }
}
