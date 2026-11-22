import Foundation

/// BESLUT B147 · BESLUT B148 · METOD M84
/// Passets rörelse: bandets ramar av typ 43 layout 21 (sex axlar i 100 Hz, PROTOKOLL_W5 §8.2) från en minut före
/// passets start till en minut efter stopp, och sidofilernas rader i samma fönster (märkena, batteriet, länken),
/// som ett arkiv i dygnsarkivets form (METOD M34). Det är filen som laddas upp till hinken `rorelse` (B148).
/// Dygnsarkivet laddas upp utan de här ramarna (`withoutMotion`), så att rörelsen bara går den vägen.
///
/// Inget värde ur rörelsen läses här: ramarna flyttas som byte.
public enum PassMotion {
    /// METOD M84. **antagande**: marginalen före start och efter stopp.
    public static let margin: TimeInterval = 60

    /// En ram med rörelse i 100 Hz: typ 43 (realtid) eller 47 (historiken, mätt 2026-10-14) med layout 21.
    public static func isMotion(_ e: DayArchive.Entry) -> Bool {
        e.inner.count > 1 && (e.inner[0] == 43 || e.inner[0] == 47) && e.inner[1] == 21
    }

    /// Passets rörelse ur dygnens arkiv (byggda ur rådygnet eller lästa ur arkivet), i den ordning ramarna hördes.
    /// `nil` när fönstret inte har en enda rörelseram (ett pass utan ström, eller ett pass från före B147).
    public static func extract(_ days: [DayArchive], start: Date, stop: Date) -> DayArchive? {
        let från: Date = start.addingTimeInterval(-margin)
        let till: Date = stop.addingTimeInterval(margin)
        var ramar: [DayArchive.Entry] = []
        var sida = Data()
        var dag: DayLog.Day?
        for a in days.sorted(by: { (x: DayArchive, y: DayArchive) -> Bool in x.day.text < y.day.text }) {
            let här: [DayArchive.Entry] = a.otherFrames.filter { (e: DayArchive.Entry) -> Bool in
                isMotion(e) && e.heard >= från && e.heard <= till
            }
            if dag == nil, !här.isEmpty { dag = a.day }
            ramar += här
            sida.append(sidecarLines(a.sidecar, from: från, to: till))
        }
        guard let dag, !ramar.isEmpty else { return nil }
        var ut = DayArchive(day: dag, sidecar: sida)
        for e in ramar.sorted(by: { (x: DayArchive.Entry, y: DayArchive.Entry) -> Bool in
            x.heardMilliseconds < y.heardMilliseconds
        }) {
            ut.add(e)
        }
        ut.notifications = ramar.count
        return ut
    }

    /// Dygnsarkivet utan rörelsen i 100 Hz, för utvecklingskopian (B148). Allt annat, och räknarna, som förut.
    public static func withoutMotion(_ a: DayArchive) -> DayArchive {
        var ut = DayArchive(day: a.day, sourceFrameBytes: a.sourceFrameBytes, sourceSidecarBytes: a.sourceSidecarBytes,
                            sidecar: a.sidecar)
        for e in a.frames where !isMotion(e) { ut.add(e) }
        ut.notifications = a.notifications
        ut.badK18Checksums = a.badK18Checksums
        ut.otherBadChecksums = a.otherBadChecksums
        ut.droppedFrames = a.droppedFrames
        return ut
    }

    /// Har arkivet någon rörelseram?
    public static func hasMotion(_ a: DayArchive) -> Bool {
        a.otherFrames.contains { (e: DayArchive.Entry) -> Bool in isMotion(e) }
    }

    /// Sidofilens rader med en tid `t` i fönstret, med radslutet. Rader utan tid hoppas över.
    static func sidecarLines(_ sidecar: Data, from: Date, to: Date) -> Data {
        var ut = Data()
        let a: Double = from.timeIntervalSince1970
        let b: Double = to.timeIntervalSince1970
        for rad in sidecar.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(rad)) as? [String: Any],
                  let t = number(o["t"]), t >= a, t <= b else { continue }
            ut.append(Data(rad))
            ut.append(UInt8(ascii: "\n"))
        }
        return ut
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return (v as? NSNumber)?.doubleValue
    }
}
