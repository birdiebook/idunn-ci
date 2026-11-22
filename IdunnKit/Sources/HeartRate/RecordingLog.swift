import Foundation

/// BESLUT B15 · BESLUT B3
/// En natt på disk: en JSON-rad per händelse (JSONL), som appen lägger till
/// medan natten pågår. Kraschar appen eller stänger iOS den mitt i natten
/// förloras högst raden som skrevs just då — allt före ligger redan på disk.
///
/// Raderna är korta och har bara de fält som hör till händelsen:
///
///     {"zon":7200}                                  natten börjar, telefonens zon
///     {"t":1760300000.5,"bpm":52,"rr":[1152.34],"kontakt":"detected","f":22}
///     {"t":1760300001.5,"trasig":true}              en notis som inte gick att tolka
///     {"batteriStart":81}                           0x180F vid start
///     {"batteriSlut":74}                            0x180F vid stopp
///     {"stopp":1760330000}                          natten avslutad
///     {"t":1760300100,"marke":"skak"}               användaren märke (METOD M20)
///     {"t":1760300200,"zon":3600}                   zonen ändrades under dygnet (METOD M27)
///     {"t":1760300300,"lank":"frånkopplad","fel":6,"text":"…"}   länken (METOD M43)
///
/// Rena funktioner, så att formatet provas på Linux. Filen och skyddsklassen
/// ligger i appen.
public enum RecordingLog {

    /// Det som gick att läsa ur en fil. `skippedLines` räknar rader som inte
    /// gick att tolka, typiskt en halvskriven sista rad efter en krasch.
    public struct Contents: Equatable, Sendable {
        public var recording: NightRecording
        /// Telefonens zon när natten startade, sekunder öster om Greenwich.
        public var utcOffsetSeconds: Int?
        public var stopped: Date?
        public var skippedLines: Int
        /// METOD M15. Notiser från bandet som inte gick att tolka som 2A37
        /// (`HeartRateMeasurement` gav `nil`). Bara antalet sparas, inga byte.
        public var unreadableNotifications: Int = 0
        /// METOD M20. användaren märken i den ordning de skrevs.
        public var markers: [Marker] = []
        /// METOD M27. Zonbyten under ett dygn (resa, sommartid): rader med både
        /// tid och zon. Den första zonen utan tid står i `utcOffsetSeconds`.
        public var zoneChanges: [ZoneChange] = []
        /// METOD M43. Länkens händelser, i den ordning de skrevs.
        public var links: [LinkEntry] = []
    }

    /// METOD M43. En händelse på länken till bandet: anslutningen, och
    /// IMU-provets tystnad. Inga mätvärden; ordet, systemets felkod och dess
    /// text. Skrivs bredvid märkena men är inget märke (segmenten i
    /// `tools/imu_analys.py` och M20 bryts inte av dem).
    public enum Link: String, CaseIterable, Sendable {
        /// `didConnect`.
        case connected = "ansluten"
        /// Alla Whoop-karakteristiker som begärdes har notiser på.
        case servicesReady = "tjänster klara"
        /// `didDisconnectPeripheral`, med felet (`nil` = appen kopplade själv ner).
        case disconnected = "frånkopplad"
        /// `didFailToConnect`, med felet.
        case failedToConnect = "anslutning misslyckades"
        /// Under ett IMU-prov: länken uppe men ingen rörelseram på en stund.
        case imuSilent = "imu tyst"
        /// Första rörelseramen efter `imuSilent`.
        case imuResumed = "imu igen"
        /// PLAN.md A3. Appen startade (texten säger om det var i bakgrunden, väckt för bandet).
        case appStarted = "appen startad"
        /// PLAN.md A3. iOS återställde Bluetooth-centralen (`willRestoreState`): appen väcktes för bandet.
        case restored = "väckt av iOS"
        /// PLAN.md A3. Appen kom i förgrunden.
        case foreground = "i förgrunden"
        /// PLAN.md A3. Appen gick i bakgrunden.
        case background = "i bakgrunden"
        /// PLAN.md A3 · METOD M23. En hämtning slutade "Klar"; texten bär antal bitar och K18-sekunder.
        case fetchComplete = "hämtning klar"
        /// PLAN.md A3 · METOD M23. En hämtning stoppades; texten bär orsaken.
        case fetchStopped = "hämtning stoppad"
        /// PLAN.md A3. Nätterna räknades och minst en sparades.
        case nightsComputed = "nätter räknade"
        /// BESLUT B149. Bluetooth i telefonen bytte läge; texten säger vilket (på, av, återställs, nekad, okänt).
        case bluetooth = "bluetooth"
        /// BESLUT B149. Appen lade en väntande anslutning på bandet; texten säger varför (start, tappat, misslyckat).
        case connecting = "ansluter"
        /// BESLUT B149. iOS varnade för att minnet tar slut; en app i bakgrunden kan stängas strax efter.
        case memoryWarning = "minnesvarning"
        /// BESLUT B149. iOS sa till att appen avslutas (kommer inte när en app i bakgrunden stängs tyst).
        case terminating = "avslutas"
    }

    /// PLAN.md A3. Orden för en hämtnings slut, som `NightLedger` räknar om nätter efter.
    public static let fetchEnds: Set<String> = [Link.fetchComplete.rawValue, Link.fetchStopped.rawValue]

    public struct LinkEntry: Equatable, Sendable {
        public var time: Date
        /// `Link.rawValue`; ett okänt ord läses också (en nyare app).
        public var word: String
        /// `NSError.code` (för CoreBluetooth `CBError.Code`), om ett fel fanns.
        public var code: Int?
        public var text: String?

        public init(time: Date, word: String, code: Int? = nil, text: String? = nil) {
            self.time = time
            self.word = word
            self.code = code
            self.text = text
        }
    }

    /// METOD M27. Telefonens zon ändrades vid `time` till `utcOffsetSeconds`.
    public struct ZoneChange: Equatable, Sendable {
        public var time: Date
        public var utcOffsetSeconds: Int

        public init(time: Date, utcOffsetSeconds: Int) {
            self.time = time
            self.utcOffsetSeconds = utcOffsetSeconds
        }
    }

    /// METOD M20. Ett märke: telefonens tid och ett ord ("av", "skak", "still",
    /// "kyl", "rum", "på"). Gäller från sin tid till nästa märke eller stopp,
    /// så att ramarna i ett prov utan band på handleden kan pekas ut efteråt.
    public struct Marker: Equatable, Sendable {
        public var time: Date
        public var label: String

        public init(time: Date, label: String) {
            self.time = time
            self.label = label
        }
    }

    /// METOD M20. Orden Märk-knappen erbjuder. Alla utom "på" betyder att
    /// bandet inte sitter på handleden.
    public static let markerLabels: [String] = ["av", "skak", "still", "kyl", "rum", "på"]

    /// En rad. Fält som saknas skrivs inte (synthesized `encodeIfPresent`).
    struct Line: Codable {
        var t: Double?
        var bpm: Int?
        var rr: [Double]?
        var kontakt: HeartRateMeasurement.SensorContact?
        /// METOD M15. Flaggbyten.
        var f: Int?
        var zon: Int?
        var batteriStart: Int?
        var batteriSlut: Int?
        var stopp: Double?
        var trasig: Bool?
        /// METOD M20. användaren märke.
        var marke: String?
        /// METOD M43. Länkens händelse, felkoden och feltexten.
        var lank: String?
        var fel: Int?
        var text: String?
    }

    // MARK: Skriva

    public static func header(utcOffsetSeconds: Int) -> Data {
        encode(Line(zon: utcOffsetSeconds))
    }

    /// METOD M1. Tiden är telefonens, i sekunder sedan 1970.
    public static func line(_ s: HeartRateSample) -> Data {
        encode(Line(t: s.time.timeIntervalSince1970, bpm: s.bpm,
                    rr: s.rrMilliseconds.isEmpty ? nil : s.rrMilliseconds,
                    kontakt: s.sensorContact, f: s.flags.map { Int($0) }))
    }

    /// METOD M15. En notis som inte gick att tolka: bara tiden, inga byte.
    public static func unreadable(at date: Date) -> Data {
        encode(Line(t: date.timeIntervalSince1970, trasig: true))
    }

    /// METOD M27. Zonen ändrades under dygnet. Till skillnad från `header` bär
    /// raden en tid, så att läsaren vet från när den gäller.
    public static func zoneChange(utcOffsetSeconds: Int, at date: Date) -> Data {
        encode(Line(t: date.timeIntervalSince1970, zon: utcOffsetSeconds))
    }

    public static func batteryAtStart(_ percent: Int) -> Data {
        encode(Line(batteriStart: percent))
    }

    public static func batteryAtEnd(_ percent: Int) -> Data {
        encode(Line(batteriSlut: percent))
    }

    public static func stopped(at date: Date) -> Data {
        encode(Line(stopp: date.timeIntervalSince1970))
    }

    /// METOD M20. Ett märke med telefonens tid. Ordet kortas till 32 tecken;
    /// det är användaren eget ord, inget mätvärde.
    public static func marker(_ label: String, at date: Date) -> Data {
        encode(Line(t: date.timeIntervalSince1970, marke: String(label.prefix(32))))
    }

    /// METOD M43. En händelse på länken. Texten (systemets feltext) kortas
    /// till 120 tecken; saknas felet skrivs varken `fel` eller `text`.
    public static func link(_ l: Link, code: Int? = nil, text: String? = nil, at date: Date) -> Data {
        link(LinkEntry(time: date, word: l.rawValue, code: code, text: text))
    }

    /// METOD M43. En läst länkrad tillbaka till en rad (exporten av ett intervall).
    public static func link(_ e: LinkEntry) -> Data {
        encode(Line(t: e.time.timeIntervalSince1970, lank: String(e.word.prefix(32)), fel: e.code,
                    text: e.text.map { String($0.prefix(120)) }))
    }

    /// En rad med radbrytning. Kan inte fälla inspelningen: ett värde som inte
    /// går att skriva som JSON (inte ändligt) ger en tom rad i stället.
    static func encode(_ line: Line) -> Data {
        guard var d = try? JSONEncoder().encode(line) else { return Data() }
        d.append(0x0A)
        return d
    }

    // MARK: Läsa

    /// Läser en hel fil. Rader som inte går att tolka hoppas över och räknas.
    /// Batteriet vid start är det första som skrevs, vid slut det sista, så
    /// att en natt som återupptagits efter att iOS stängt appen behåller båda.
    public static func decode(_ data: Data) -> Contents {
        let decoder = JSONDecoder()
        var samples: [HeartRateSample] = []
        var zon: Int?
        var start: Int?
        var slut: Int?
        var stopp: Date?
        var skipped = 0
        var unreadable = 0
        var markers: [Marker] = []
        var zoneChanges: [ZoneChange] = []
        var links: [LinkEntry] = []

        for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let l = try? decoder.decode(Line.self, from: Data(slice)) else {
                skipped += 1
                continue
            }
            if let t = l.t, let bpm = l.bpm {
                let flags: UInt8? = l.f.flatMap { UInt8(exactly: $0) }
                samples.append(HeartRateSample(time: Date(timeIntervalSince1970: t), bpm: bpm,
                                               rrMilliseconds: l.rr ?? [], sensorContact: l.kontakt,
                                               flags: flags))
            }
            if l.trasig == true { unreadable += 1 }
            if let t = l.t, let m = l.marke {
                markers.append(Marker(time: Date(timeIntervalSince1970: t), label: m))
            }
            if let t = l.t, let w = l.lank {
                links.append(LinkEntry(time: Date(timeIntervalSince1970: t), word: w, code: l.fel, text: l.text))
            }
            if let t = l.t, let z = l.zon {
                zoneChanges.append(ZoneChange(time: Date(timeIntervalSince1970: t), utcOffsetSeconds: z))
            } else if let z = l.zon, zon == nil {
                zon = z
            }
            if let b = l.batteriStart, start == nil { start = b }
            if let b = l.batteriSlut { slut = b }
            if let s = l.stopp { stopp = Date(timeIntervalSince1970: s) }
        }
        return Contents(recording: NightRecording(samples: samples, batteryAtStart: start, batteryAtEnd: slut),
                        utcOffsetSeconds: zon, stopped: stopp, skippedLines: skipped,
                        unreadableNotifications: unreadable, markers: markers,
                        zoneChanges: zoneChanges, links: links)
    }
}
