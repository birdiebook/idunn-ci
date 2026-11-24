import Foundation

/// METOD M27 · BESLUT B28 · BESLUT B30
/// Det lyssnaren vet om sig själv, räknat ur notiserna den sparar: när den
/// senast hörde K18, när Whoop senast synkade klart, och vilka minuter K18
/// täcker. Appen matar in varje notis; vyn ritar resultatet. Inga värden ur
/// posterna sparas här, bara tider och minuter (BESLUT B3).
public struct ListenerStatus: Equatable, Sendable {
    /// Telefonens tid när en hel K18-ram senast blev hel.
    public private(set) var lastK18Heard: Date?
    /// Den nyaste K18-postens egen tid (i7, bandets klocka), ur de poster som
    /// inte ligger i framtiden.
    public private(set) var lastK18Record: Date?
    /// Telefonens tid när Whoops senaste synk avslutades: HISTORY_COMPLETE
    /// (typ 49, i2 = 3) på `…0005`, PROTOKOLL_W5 §7.1.
    public private(set) var lastSync: Date?
    /// BESLUT B158. Telefonens tid när en synk som kom ikapp blev klar: en färdig synk där någon K18-post hördes
    /// minst `catchUpLag` efter att den mättes. Bandet hade då inte synkat på en stund, och nattens data kan ha kommit
    /// efter att natten räknades.
    public private(set) var lastCatchUp: Date?
    /// BESLUT B158. K18-poster i den synken och den största eftersläpningen (sekunder): tider och antal, inga värden.
    public private(set) var lastCatchUpRecords = 0
    public private(set) var lastCatchUpLag: Double = 0
    /// Unix-minuter (`tid / 60`) som har minst en K18-post.
    public private(set) var k18Minutes: Set<Int> = []
    /// Ramar vars CRC32 inte stämde. De räknas inte med.
    public private(set) var badChecksums = 0

    private var stream = FrameAssembly.Stream()
    /// BESLUT B158. Sedan förra färdiga synken: K18-poster och den största eftersläpningen.
    private var syncRecords = 0
    private var syncLag: Double = 0

    /// BESLUT B158 · METOD M87. En synk är ikapp när en post hörs så här långt (sekunder) efter att den mättes. Mätt
    /// 2026-11-24 i ett dygn: Whoop-appen synkar var 10:e minut och den största eftersläpningen i en vanlig synk var
    /// 10,3 minuter; efter en natt utan anslutning 8,5 timmar.
    public static let catchUpLag: Double = 30 * 60

    /// En post med en tid längre fram än så här (sekunder efter notisen) är
    /// ett fel i bandets klocka och räknas inte. **antagande**.
    static let futureSlack: Double = 86_400

    /// Minuter äldre än så här (sekunder före den nyaste) glöms, så att
    /// mängden inte växer för alltid. Den längsta natten (kväll 18 till
    /// förmiddag 12) ryms med god marginal.
    static let keepSeconds: Double = 4 * 86_400

    public init() {}

    /// Strömmens halvfärdiga ramar räknas inte som skillnad.
    public static func == (a: ListenerStatus, b: ListenerStatus) -> Bool {
        a.lastK18Heard == b.lastK18Heard && a.lastK18Record == b.lastK18Record
            && a.lastSync == b.lastSync && a.lastCatchUp == b.lastCatchUp && a.k18Minutes == b.k18Minutes
            && a.badChecksums == b.badChecksums
    }

    /// Matas med varje notis i den ordning den kom. Bara `…0005` bär K18 och
    /// synkens markeringar; övriga karakteristiker hoppas över.
    public mutating func add(_ n: RawFrame) {
        guard n.characteristic == "fd4b0005", let frame = stream.add(n) else { return }
        guard let type = frame.type else { return }
        switch type {
        case K18Record.packetType:
            guard frame.inner.count > 1, Int(frame.inner[1]) == K18Record.family else { return }
            guard frame.crc32OK else {
                badChecksums += 1
                return
            }
            guard let r = K18Record.decode(inner: frame.inner) else { return }
            note(record: r, heard: frame.time)
        case Int(HistoryMeta.packetType):
            if frame.crc32OK, HistoryMeta(inner: frame.inner) == .complete {
                lastSync = max(lastSync ?? frame.time, frame.time)
                if syncLag >= Self.catchUpLag {
                    lastCatchUp = max(lastCatchUp ?? frame.time, frame.time)
                    lastCatchUpRecords = syncRecords
                    lastCatchUpLag = syncLag
                }
                syncRecords = 0
                syncLag = 0
            }
        default:
            break
        }
    }

    private mutating func note(record r: K18Record, heard: Date) {
        lastK18Heard = max(lastK18Heard ?? heard, heard)
        let t = Double(r.time)
        guard t <= heard.timeIntervalSince1970 + Self.futureSlack else { return }
        k18Minutes.insert(r.time / 60)
        syncRecords += 1
        syncLag = max(syncLag, heard.timeIntervalSince1970 - t)
        let at = Date(timeIntervalSince1970: t)
        lastK18Record = max(lastK18Record ?? at, at)
        if k18Minutes.count > 8000, let nyaste = lastK18Record {
            let golv = Int((nyaste.timeIntervalSince1970 - Self.keepSeconds) / 60)
            k18Minutes = k18Minutes.filter { $0 >= golv }
        }
    }

    /// Slår ihop en status läst ur dygnsfilerna vid start med den som
    /// lyssnaren byggt sedan dess. Mängden och de senaste tiderna är idempotenta,
    /// så en notis som finns i båda räknas inte dubbelt.
    public mutating func merge(_ o: ListenerStatus) {
        lastK18Heard = Self.later(lastK18Heard, o.lastK18Heard)
        lastK18Record = Self.later(lastK18Record, o.lastK18Record)
        lastSync = Self.later(lastSync, o.lastSync)
        lastCatchUp = Self.later(lastCatchUp, o.lastCatchUp)
        k18Minutes.formUnion(o.k18Minutes)
        badChecksums += o.badChecksums
    }

    private static func later(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (x?, y?): return max(x, y)
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }

    /// Statusen ur en hel dygnsfils notiser (vid start).
    public static func read(_ notes: [RawFrame]) -> ListenerStatus {
        var s = ListenerStatus()
        for n in notes { s.add(n) }
        return s
    }

    /// Matar in en dygnsfils innehåll (`.t2.jsonl`) notis för notis.
    public mutating func read(log data: Data) {
        RawFrameLog.forEach(data) { add($0) }
    }

    /// METOD M24. Andelen av fönstrets minuter (fram till `until`) som har K18.
    /// `nil` för ett tomt fönster.
    public func coverage(_ w: NightWindow.Window) -> K18Series.Coverage? {
        guard let range = K18Series.minuteRange(from: w.start, to: w.until) else { return nil }
        return K18Series.Coverage(coveredMinutes: range.filter { k18Minutes.contains($0) }.count,
                                  totalMinutes: range.count)
    }
}

/// METOD M27 · BESLUT B50. Natten innan R4 ger sömnperioden: kvällen 18 till
/// förmiddagen 12 på väggklockan i telefonens zon. **Antagande** (användaren
/// vanor, inte mätt); R4 ersätter fönstret med den uppmätta sömnperioden.
public enum NightWindow {
    public static let eveningHour = 18
    public static let morningHour = 12

    public struct Window: Equatable, Sendable {
        /// 18:00 kvällen före.
        public var start: Date
        /// 12:00, fönstrets slut.
        public var end: Date
        /// `end`, eller `now` om natten inte är slut.
        public var until: Date
        public var inProgress: Bool { until < end }

        public init(start: Date, end: Date, until: Date) {
            self.start = start
            self.end = end
            self.until = until
        }
    }

    /// Fönstret som slutar 12:00 på den lokala dagen `day`.
    public static func ending(on day: DayLog.Day, utcOffsetSeconds: Int, now: Date? = nil) -> Window {
        let start = DayLog.date(of: DayLog.shifted(day, by: -1), hour: eveningHour, utcOffsetSeconds: utcOffsetSeconds)
        let end = DayLog.date(of: day, hour: morningHour, utcOffsetSeconds: utcOffsetSeconds)
        return Window(start: start, end: end, until: min(end, now ?? end))
    }

    /// BESLUT B50. Fönstret som slutar 12:00 på `day`, med zonen vid varje
    /// gräns: 18:00 kvällen före i zonen som gällde då, och 12:00 i zonen som
    /// gäller då. En natt över omställningen till eller från sommartid är
    /// 19 eller 17 timmar, inte 18. `offsetAt` ger telefonens zon (sekunder
    /// öster om Greenwich) vid ett ögonblick.
    public static func ending(on day: DayLog.Day, offsetAt: (Date) -> Int, now: Date? = nil) -> Window {
        let start: Date = instant(of: DayLog.shifted(day, by: -1), hour: eveningHour, offsetAt: offsetAt)
        let end: Date = instant(of: day, hour: morningHour, offsetAt: offsetAt)
        return Window(start: start, end: end, until: min(end, now ?? end))
    }

    /// Ögonblicket då väggklockan visar `hour`:00 på `d`. Zonen beror på
    /// ögonblicket och ögonblicket på zonen, så den prövas två gånger från zonen
    /// vid samma klockslag i UTC (omställningen sker natten, långt från 12 och 18).
    private static func instant(of d: DayLog.Day, hour: Int, offsetAt: (Date) -> Int) -> Date {
        var zon: Int = offsetAt(DayLog.date(of: d, hour: hour, utcOffsetSeconds: 0))
        var tid: Date = DayLog.date(of: d, hour: hour, utcOffsetSeconds: zon)
        for _ in 0..<2 {
            zon = offsetAt(tid)
            tid = DayLog.date(of: d, hour: hour, utcOffsetSeconds: zon)
        }
        return tid
    }

    /// BESLUT B50. Dagen som den aktuella natten slutar på: den lokala dagen
    /// före klockan 18:00, annars dagen efter. Klockan är väggklockan i zonen
    /// `utcOffsetSeconds`.
    public static func endingDay(now: Date, utcOffsetSeconds: Int) -> DayLog.Day {
        let idag: DayLog.Day = DayLog.localDay(now, utcOffsetSeconds: utcOffsetSeconds)
        let lokal: Int = Int(now.timeIntervalSince1970.rounded(.down)) + utcOffsetSeconds
        let sekunderIDygnet: Int = ((lokal % 86_400) + 86_400) % 86_400
        return sekunderIDygnet >= eveningHour * 3600 ? DayLog.shifted(idag, by: 1) : idag
    }

    /// BESLUT B50. Natten som pågår eller just slutat: fönstret som slutar
    /// 12:00 på den lokala dagen (`endingDay`). Före 12 pågår natten och räknas
    /// fram till `now`; från 12 till 17:59 är den slut och står kvar; kl 18:00
    /// byter det till natten som börjar, som slutar i morgon och räknas fram
    /// till `now`. Fönstret byts när det nya börjar, inte vid midnatt.
    public static func latest(now: Date, utcOffsetSeconds: Int) -> Window {
        ending(on: endingDay(now: now, utcOffsetSeconds: utcOffsetSeconds),
               utcOffsetSeconds: utcOffsetSeconds, now: now)
    }

    /// BESLUT B50. Som `latest`, men med zonen vid varje gräns
    /// (`ending(on:offsetAt:now:)`): klockan 18 bedöms i zonen nu, fönstrets
    /// början och slut i zonen som gäller vid dem. Det här är vad appen visar.
    public static func latest(now: Date, offsetAt: (Date) -> Int) -> Window {
        ending(on: endingDay(now: now, utcOffsetSeconds: offsetAt(now)), offsetAt: offsetAt, now: now)
    }

    /// METOD M27 · BESLUT B50. Fönstret som slutar 12:00 på dagens lokala
    /// datum, hela dygnet, också på kvällen: det gamla beteendet hos `latest`.
    /// Morgon bedömer lyssnaren mot natten som slutar idag (METOD M29,
    /// `ListenerCheck`), och den natten är densamma hela eftermiddagen och
    /// kvällen tills klockan slår midnatt.
    public static func endingToday(now: Date, utcOffsetSeconds: Int) -> Window {
        ending(on: DayLog.localDay(now, utcOffsetSeconds: utcOffsetSeconds),
               utcOffsetSeconds: utcOffsetSeconds, now: now)
    }
}
