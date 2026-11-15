import Foundation
import HeartRate

/// BESLUT B22 · BESLUT B30 · METOD M27
/// Ett dygn, eller ett tidsintervall över midnatt, som en zip (användaren eget
/// initiativ, BESLUT B23). Ett helt dygn är dygnsfilerna som de ligger
/// (`ExportPackage.full`, filnamnet `idunn-dygn-<datum>.zip`). Ett intervall
/// plockar notiserna och märkena inom det ur en eller flera dygnsfiler och
/// packar dem i en `.t2.jsonl` och en `.jsonl` med samma form, så att
/// `tools/t2_analys.py` läser den som en natt.
extension ExportPackage {
    /// En dygnsfil som lästs in: sidofilen (zon, märken) och notiserna.
    public struct DayPart: Sendable {
        public var stem: String
        public var pulse: Data
        public var frames: Data?

        public init(stem: String, pulse: Data, frames: Data?) {
            self.stem = stem
            self.pulse = pulse
            self.frames = frames
        }
    }

    public struct IntervalSummary: Equatable, Sendable {
        public var notifications = 0
        public var markers = 0
    }

    /// Stammen för ett intervall: lokal tid för start och slut, utan kolon.
    /// `dygn-2026-10-12-1800-2026-10-13-1200`.
    public static func intervalStem(from: Date, to: Date, utcOffsetSeconds: Int) -> String {
        func del(_ d: Date) -> String {
            let day = DayLog.localDay(d, utcOffsetSeconds: utcOffsetSeconds)
            let sek = Int(d.timeIntervalSince1970.rounded(.down)) + utcOffsetSeconds
            let minut = DayLog.floorDiv(sek, 60)
            let dygnMin = minut - DayLog.days(day) * 1440
            return day.text + "-" + DayLog.Day.pad(dygnMin / 60, 2) + DayLog.Day.pad(dygnMin % 60, 2)
        }
        return DayLog.prefix + del(from) + "-" + del(to)
    }

    /// Notiser och märken i `[from, to)` ur dygnsfilerna, i tidsordning.
    /// `zip` är `nil` om intervallet inte har en enda notis. Tiden är telefonens
    /// (den notisen sparades med), inte bandets. `utcOffsetSeconds` skrivs som
    /// sidofilens zon och ger intervallets namn.
    /// `compress: false` lagrar filerna opackade, som Linux alltid gör; proven
    /// läser dem så på båda plattformarna.
    public static func interval(parts: [DayPart], from: Date, to: Date, utcOffsetSeconds: Int,
                                date: Date = Date(), compress: Bool = true)
        -> (zip: Data?, name: String, summary: IntervalSummary) {
        let stem = intervalStem(from: from, to: to, utcOffsetSeconds: utcOffsetSeconds)
        var summary = IntervalSummary()
        guard to > from else { return (nil, "idunn-" + stem + ".zip", summary) }

        var notes: [RawFrame] = []
        var markers: [RecordingLog.Marker] = []
        var links: [RecordingLog.LinkEntry] = []
        for p in parts {
            if let f = p.frames {
                RawFrameLog.forEach(f) { if $0.time >= from && $0.time < to { notes.append($0) } }
            }
            let sida = RecordingLog.decode(p.pulse)
            markers += sida.markers.filter { $0.time >= from && $0.time < to }
            // METOD M43. Länkens rader följer med, så att imu_analys ser dem.
            links += sida.links.filter { $0.time >= from && $0.time < to }
        }
        // Stabil sortering: notiser med samma tid behåller sin ordning.
        let ordnade = notes.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
        markers.sort { $0.time < $1.time }
        summary.notifications = ordnade.count
        summary.markers = markers.count

        let name = "idunn-" + stem + ".zip"
        guard !ordnade.isEmpty else { return (nil, name, summary) }

        var log = RecordingLog.header(utcOffsetSeconds: utcOffsetSeconds)
        var rader: [(time: Date, line: Data)] = markers.map { ($0.time, RecordingLog.marker($0.label, at: $0.time)) }
        rader += links.map { ($0.time, RecordingLog.link($0)) }
        // Stabil sortering på tiden: märket före länkraden vid samma tid.
        let iOrdning = rader.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
        for r in iOrdning { log.append(r.element.line) }
        var t2 = Data()
        for n in ordnade { t2.append(RawFrameLog.line(n)) }
        let zip = ZipArchive.make([ZipArchive.Entry(name: stem + ".jsonl", data: log),
                                   ZipArchive.Entry(name: stem + ".t2.jsonl", data: t2)], date: date,
                                  compress: compress)
        return (zip, name, summary)
    }
}
