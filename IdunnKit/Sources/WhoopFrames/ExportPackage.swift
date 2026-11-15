import Foundation
import HeartRate

/// BESLUT B22 · BESLUT B3 · METOD M20
/// En natt som en fil att dela, på användaren eget initiativ. Två val:
///
/// - **Hela natten** (`idunn-<start>.zip`): nattens `.jsonl` (2A37-pulsen,
///   zonen, batteriet, märkena) och `.t2.jsonl` (Whoops råa notiser), som de
///   ligger på telefonen.
/// - **Bara utan band** (`idunn-ejburen-<start>.zip`): bara notiser från tider
///   då användaren märkt att bandet inte satt på handleden, och ingen 2A37 alls.
///   Filerna har samma form och namn i zip-filen som hela natten, så
///   `tools/t2_analys.py` läser båda på samma sätt.
public enum ExportPackage {
    public static func fileName(stem: String, offWristOnly: Bool) -> String {
        (offWristOnly ? "idunn-ejburen-" : "idunn-") + stem + ".zip"
    }

    /// Hela natten. `frames` är `nil` om natten saknar T2-fil.
    public static func full(stem: String, pulse: Data, frames: Data?, date: Date = Date()) -> Data {
        var entries = [ZipArchive.Entry(name: stem + ".jsonl", data: pulse)]
        if let f = frames { entries.append(ZipArchive.Entry(name: stem + ".t2.jsonl", data: f)) }
        return ZipArchive.make(entries, date: date)
    }

    /// Vad urvalet utan band tog med och lämnade.
    public struct OffWristSummary: Equatable, Sendable {
        /// Intervallen utan band, krympta med marginalen; tomt = inget att dela.
        public var spans: [ClosedRange<Double>] = []
        public var framesKept = 0
        public var framesDropped = 0
        public var notificationsKept = 0
    }

    /// Bara utan band, eller `nil` om natten saknar märken utan band.
    public static func offWrist(stem: String, pulse: Data, frames: Data, date: Date = Date())
        -> (zip: Data?, summary: OffWristSummary) {
        let contents = RecordingLog.decode(pulse)
        let notes = RawFrameLog.decode(frames).frames
        let sista: Double = max(notes.last?.time.timeIntervalSince1970 ?? 0,
                                contents.recording.samples.last?.time.timeIntervalSince1970 ?? 0)
        let slut: Double = contents.stopped?.timeIntervalSince1970 ?? sista
        var summary = OffWristSummary()
        summary.spans = OffWrist.spans(markers: contents.markers.map { ($0.time.timeIntervalSince1970, $0.label) },
                                       end: slut)
        guard !summary.spans.isEmpty else { return (nil, summary) }

        let keep = OffWrist.select(notes, spans: summary.spans)
        summary.framesKept = keep.framesKept
        summary.framesDropped = keep.framesDropped
        summary.notificationsKept = keep.indices.count

        // Pulsfilen utan en enda pulsrad: zonen, märkena och stoppet.
        var log = RecordingLog.header(utcOffsetSeconds: contents.utcOffsetSeconds ?? 0)
        for m in contents.markers { log.append(RecordingLog.marker(m.label, at: m.time)) }
        if let s = contents.stopped { log.append(RecordingLog.stopped(at: s)) }
        var t2 = Data()
        for i in keep.indices { t2.append(RawFrameLog.line(notes[i])) }
        let zip = ZipArchive.make([ZipArchive.Entry(name: stem + ".jsonl", data: log),
                                   ZipArchive.Entry(name: stem + ".t2.jsonl", data: t2)], date: date)
        return (zip, summary)
    }
}

/// METOD M20 · BESLUT B3. Vilka notiser som kommer från ett band ingen bär.
public enum OffWrist {
    /// Märken som betyder att bandet inte sitter på handleden; "på" avslutar.
    public static let labels: Set<String> = ["av", "skak", "still", "kyl", "rum"]
    public static let onLabel = "på"
    /// BESLUT B53. IMU-provets märken för slag med bandet på handleden
    /// (`ImuControl.markerLabels`) avslutar också: efter "still" och "rotera"
    /// sitter bandet på igen.
    public static let wornLabels: Set<String> = [onLabel, "sving", "chip", "putt"]
    /// Sekunder närmast intervallets början och slut som inte räknas: märket
    /// trycks för hand, och bandets klocka går inte exakt som telefonens.
    /// **antagande**.
    public static let marginSeconds: Double = 30

    /// Intervallen utan band: från första märket utan band till nästa "på"
    /// (eller natten slut), krympta med marginalen i båda ändar.
    public static func spans(markers: [(Double, String)], end: Double) -> [ClosedRange<Double>] {
        var ut: [ClosedRange<Double>] = []
        var start: Double?
        func stäng(_ t: Double) {
            if let s = start, t - marginSeconds > s + marginSeconds {
                ut.append((s + marginSeconds)...(t - marginSeconds))
            }
            start = nil
        }
        for (t, ord) in markers.sorted(by: { $0.0 < $1.0 }) {
            if labels.contains(ord) {
                if start == nil { start = t }
            } else if wornLabels.contains(ord) {
                stäng(t)
            }
        }
        stäng(end)
        return ut
    }

    /// Tiderna i ramens egen post som måste ligga utan band, enligt
    /// docs/PROTOKOLL_W5.md §2–3. `nil`: typen bär ingen post med egen tid
    /// (kommandosvar, loggtext) och prövas bara på notisens tid. Tom lista:
    /// typen är okänd eller för kort, och tas inte med.
    static func recordTimes(type: Int, inner: [UInt8]) -> [Double]? {
        func t(_ o: Int) -> Double? { FrameAssembly.u32(inner, at: o).map { Double($0) } }
        switch type {
        case 40, 43, 47, 51, 52:            // posthuvudet: tid i i7
            return t(7).map { [$0] } ?? []
        case 48, 53, 54:                     // händelse: tid i i3 eller i4 (§3.5)
            return [t(3), t(4)].compactMap { $0 }
        case 49, 56:                         // metadata: tid i i3
            return t(3).map { [$0] } ?? []
        case 36, 38, 50, 55:                 // kommandosvar och loggtext
            return nil
        default:
            return []
        }
    }

    public struct Selection: Equatable, Sendable {
        /// Index i notislistan, i ordning.
        public var indices: [Int]
        public var framesKept: Int
        public var framesDropped: Int
    }

    /// En ram tas med om den är hel med giltiga summor, alla dess notiser kom
    /// inom ett intervall utan band, och — om typen bär en egen tid — den
    /// tiden också ligger där (en historikpost som skickas under provet kan
    /// vara mätt på handleden). För händelser räcker en av de två möjliga
    /// platserna. Loggtext på `…0007` tas med på notisens tid.
    public static func select(_ notes: [RawFrame], spans: [ClosedRange<Double>]) -> Selection {
        func inom(_ t: Double) -> Bool { spans.contains { $0.contains(t) } }
        let (frames, _) = FrameAssembly.assemble(notes)
        var keep = Set<Int>()
        var kept = 0
        var dropped = 0
        for f in frames {
            guard f.crc32OK, let typ = f.type,
                  f.notifications.allSatisfy({ inom(notes[$0].time.timeIntervalSince1970) }) else {
                dropped += 1
                continue
            }
            if let tider = recordTimes(type: typ, inner: f.inner), !tider.contains(where: inom) {
                dropped += 1
                continue
            }
            kept += 1
            keep.formUnion(f.notifications)
        }
        for (i, n) in notes.enumerated()
        where n.characteristic == "fd4b0007" && inom(n.time.timeIntervalSince1970) {
            keep.insert(i)
        }
        return Selection(indices: keep.sorted(), framesKept: kept, framesDropped: dropped)
    }
}
