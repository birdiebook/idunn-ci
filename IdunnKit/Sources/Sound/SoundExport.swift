import Foundation
import HeartRate
import WhoopFrames

/// METOD M45 · BESLUT B55 · BESLUT B47
/// Ljudet i en export. När en natt eller ett dygn exporteras följer ljudfilerna
/// som överlappar tidsspannet med, och bara när användaren själv trycker
/// Exportera (dataregeln):
///
///     ljud/ljud-<start>.ljud                måtten per sekund (METOD M38)
///     ljud/ljud-<start>.markningar          start, stopp och avbrott, om filen finns
///     ljud/ljud-<start>.sammanfattning.json nattens tal (`SoundSummary`), om den finns
///     ljudklipp/ljud-<start>/<id>.m4a       klippen, **bara med "Med ljudklipp"**
///
/// Sökvägarna är samma som på telefonen (Application Support), så att
/// `tools/ljud_analys.py` läser både en zip och en mapp som är utpackad ur den.
/// Klippen är röster, också den som sover bredvid (BESLUT B47): utan det
/// uttryckliga valet läses ingen klippfil ens.
///
/// Appen ger bara rotmappen och tidsspannet; vilka filer som följer med, och
/// hur de läggs i zip-filen, avgörs här och provas på Linux.
public enum SoundExport {
    public static let measureFolder = "ljud"
    public static let clipFolder = "ljudklipp"
    static let measureExtension = "ljud"
    static let marksExtension = "markningar"
    static let clipExtension = "m4a"
    static let stemPrefix = "ljud-"

    /// Så långt före intervallets början en fil kan ha startat och ändå nå in i
    /// det (lyssnaren startar kl 20 och slutar senast kl 12), och så länge en
    /// natt antas vara när inspelningen saknar stopp. **Antagande.**
    static let longestFileSeconds = 24 * 3_600
    static let openNightSeconds = 14 * 3_600

    /// Det som följer med: filerna som zip-poster och hur många nätter och klipp det är.
    public struct Collected: Sendable {
        public var entries: [ZipArchive.Entry] = []
        public var nights = 0
        public var clips = 0

        public init() {}
    }

    // MARK: Tidsspannet

    /// Unix-sekunden för `2026-10-12T20-00-00Z` (UTC, kolon som streck så som
    /// filnamn skrivs); `nil` för allt annat.
    public static func utcStart(ofIsoStem s: String) -> Int? {
        let c: [Character] = Array(s)
        guard c.count == 20, c[4] == "-", c[7] == "-", c[10] == "T", c[13] == "-", c[16] == "-",
              c[19] == "Z" else { return nil }
        func number(_ from: Int, _ count: Int) -> Int? { Int(String(c[from..<(from + count)])) }
        guard let y = number(0, 4), let mo = number(5, 2), let d = number(8, 2),
              let h = number(11, 2), let mi = number(14, 2), let se = number(17, 2),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, se < 60 else { return nil }
        let days: Int = DayLog.Day(year: y, month: mo, day: d).daysSince1970
        return days * 86_400 + h * 3_600 + mi * 60 + se
    }

    /// Unix-sekunden i en ljudfils stam (`ljud-2026-10-14T21-03-00Z`).
    public static func startOfStem(_ stem: String) -> Int? {
        guard stem.hasPrefix(stemPrefix) else { return nil }
        return utcStart(ofIsoStem: String(stem.dropFirst(stemPrefix.count)))
    }

    /// Tidsspannet en export av `stem` täcker: ett dygn (`dygn-yyyy-MM-dd`) är
    /// det lokala datumet, en inspelning (`2026-10-12T20-00-00Z`) är från dess
    /// start till stoppet (annars sista pulsen, annars 14 timmar). `nil` när
    /// stammen är något annat.
    public static func exportSpan(stem: String, pulse: Data, utcOffsetSeconds: Int) -> (from: Date, to: Date)? {
        if let day = DayLog.day(ofStem: stem) {
            let from: Date = DayLog.date(of: day, utcOffsetSeconds: utcOffsetSeconds)
            return (from, from.addingTimeInterval(86_400))
        }
        guard let start = utcStart(ofIsoStem: stem) else { return nil }
        let from = Date(timeIntervalSince1970: Double(start))
        let contents = RecordingLog.decode(pulse)
        let last: Date? = contents.stopped ?? contents.recording.samples.last?.time
        let to: Date = max(last ?? from.addingTimeInterval(Double(openNightSeconds)), from)
        return (from, to)
    }

    /// Filens tid i Unix-sekunder: huvudets start till sista hela postens sekund.
    /// `nil` när huvudet inte är en `.ljud`-fils.
    public static func span(of measure: Data) -> ClosedRange<Int>? {
        let head: [UInt8] = [UInt8](measure.prefix(SoundFile.headerBytes))
        guard head.count == SoundFile.headerBytes, Array(head[0..<4]) == SoundFile.magic,
              head[4] == SoundFile.version else { return nil }
        var raw: UInt64 = 0
        for k in 0..<8 { raw |= UInt64(head[5 + k]) << UInt64(8 * k) }
        let start: Int = Int(Int64(bitPattern: raw))
        let whole: Int = (measure.count - SoundFile.headerBytes) / SoundFile.recordBytes
        var last = 0
        if whole > 0 {
            let at: Int = SoundFile.headerBytes + (whole - 1) * SoundFile.recordBytes
            let tail: [UInt8] = [UInt8](measure.dropFirst(at).prefix(4))
            if tail.count == 4 {
                var t: UInt32 = 0
                for k in 0..<4 { t |= UInt32(tail[k]) << UInt32(8 * k) }
                last = Int(t)
            }
        }
        return start...(start + last)
    }

    // MARK: Urvalet

    /// Ljudfilerna i `root` (appens Application Support) som överlappar `[from, to]`,
    /// och med `withClips` klippen i dem vars tid ligger i intervallet. Utan
    /// `withClips` öppnas ingen klippfil.
    public static func collect(root: URL, from: Date, to: Date, withClips: Bool) -> Collected {
        let fm = FileManager.default
        let lo: Int = Int(from.timeIntervalSince1970.rounded(.down))
        let hi: Int = Int(to.timeIntervalSince1970.rounded(.up))
        let folder: URL = root.appendingPathComponent(measureFolder, isDirectory: true)
        let names: [String] = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        var out = Collected()
        for name in names where name.hasSuffix("." + measureExtension) {
            let stem: String = String(name.dropLast(measureExtension.count + 1))
            let named: Int? = startOfStem(stem)
            // En fil som startade efter intervallet, eller för länge före det, behöver inte läsas.
            if let s = named, s > hi || s + longestFileSeconds < lo { continue }
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { continue }
            // Går huvudet inte att läsa är filens tid den som namnet säger.
            let known: ClosedRange<Int>? = span(of: data) ?? named.map { (s: Int) -> ClosedRange<Int> in s...s }
            guard let time = known else { continue }
            guard time.lowerBound <= hi, time.upperBound >= lo else { continue }

            out.entries.append(ZipArchive.Entry(name: measureFolder + "/" + name, data: data))
            out.nights += 1
            let beside: [String] = [stem + "." + marksExtension, SoundSummary.fileName(stem: stem)]
            for other in beside {
                if let d = try? Data(contentsOf: folder.appendingPathComponent(other)) {
                    out.entries.append(ZipArchive.Entry(name: measureFolder + "/" + other, data: d))
                }
            }
            guard withClips else { continue }
            let dir: URL = root.appendingPathComponent(clipFolder, isDirectory: true)
                .appendingPathComponent(stem, isDirectory: true)
            let clipNames: [String] = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            for clip in clipNames where clip.hasSuffix("." + clipExtension) {
                // Klippets namn är händelsens första sekund i filen.
                guard let id = Int(clip.dropLast(clipExtension.count + 1)) else { continue }
                let at: Int = time.lowerBound + id
                guard at >= lo, at <= hi else { continue }
                guard let d = try? Data(contentsOf: dir.appendingPathComponent(clip)) else { continue }
                out.entries.append(ZipArchive.Entry(name: clipFolder + "/" + stem + "/" + clip, data: d))
                out.clips += 1
            }
        }
        return out
    }

    /// `zip` med ljudet efter de filer som fanns. Finns inget ljud i spannet
    /// lämnas `zip` som den är; `nil` bara om `zip` inte går att bygga vidare på.
    public static func extend(_ zip: Data, root: URL, from: Date, to: Date, withClips: Bool,
                              date: Date = Date(), compress: Bool = true) -> Data? {
        let found: Collected = collect(root: root, from: from, to: to, withClips: withClips)
        return ZipAppend.append(found.entries, to: zip, date: date, compress: compress)
    }

    /// Filnamnet för en export med klippen: `idunn-….zip` blir `idunn-…-ljudklipp.zip`,
    /// så att en zip med röster går att skilja från en utan.
    public static func clipFileName(_ name: String) -> String {
        guard name.hasSuffix(".zip") else { return name + "-ljudklipp" }
        return String(name.dropLast(".zip".count)) + "-ljudklipp.zip"
    }
}
