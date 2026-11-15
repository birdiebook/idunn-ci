import Foundation

/// METOD M55 · BESLUT B70
/// användaren ändring av en natts sömnperiod: när han somnade och vaknade, i stället för perioden som hittades ur
/// rörelsen (METOD M26). Natten räknas då om för den givna perioden (`K18Night.analyze(…, edit:)`): vakna stunder,
/// stadier, HRV, vilopuls, andning, kurvan och lagren räknas inom den som vanligt. Bandets data ändras aldrig, så
/// en ändring går att ångra (`SleepEdits.removing`).
///
/// Tiderna är Unix-sekunder. Appen ställer dem i hela minuter som klockslag på uppvakningsdagen (`make`).
public struct SleepEdit: Codable, Equatable, Sendable {
    /// Uppvakningsdagen som dagar sedan 1970 (`WakeDay.daysSince1970`, METOD M14).
    public var wakeDayNumber: Int
    /// Somnade och vaknade, Unix-sekunder.
    public var onset: Int
    public var wake: Int
    /// Perioden som hittades när ändringen sparades (METOD M26 med bygget då), för avstämningen: hur långt ifrån
    /// den automatiska perioden låg. `nil` när natten inte hade någon hittad period.
    public var foundOnset: Int?
    public var foundWake: Int?

    public init(wakeDay: WakeDay, onset: Int, wake: Int, foundOnset: Int? = nil, foundWake: Int? = nil) {
        wakeDayNumber = wakeDay.daysSince1970
        self.onset = onset
        self.wake = wake
        self.foundOnset = foundOnset
        self.foundWake = foundWake
    }

    public var wakeDay: WakeDay { WakeDay(daysSince1970: wakeDayNumber) }

    /// METOD M55. Den kortaste sömnperiod en ändring får ge: lika lång som det kortaste block HDCZA kan hitta
    /// (`SleepDetection.minBlockSeconds`, METOD M26). **Antagande.**
    public static let minimumSeconds: Int = SleepDetection.minBlockSeconds

    /// Varför en ändring avvisas.
    public enum Problem: Error, Equatable, Sendable {
        /// Vaknade är inte efter somnade.
        case wakeNotAfterOnset
        /// Kortare än `minimumSeconds`.
        case tooShort
        /// Utanför dygnsfönstret kl 12–12 (METOD M26).
        case outsideWindow
    }

    /// METOD M55. Avvisar en period där vaknade inte är efter somnade, som är kortare än `minimumSeconds`, eller
    /// som inte ligger inom dygnsfönstret `from`…`to` (kl 12–12, `SleepDetection.dayWindow`). I den ordningen.
    public func check(window from: Date, to: Date) throws {
        guard wake > onset else { throw Problem.wakeNotAfterOnset }
        guard wake - onset >= Self.minimumSeconds else { throw Problem.tooShort }
        let a: Int = Int(from.timeIntervalSince1970.rounded(.up))
        let b: Int = Int(to.timeIntervalSince1970.rounded(.down))
        guard onset >= a, wake <= b else { throw Problem.outsideWindow }
    }

    /// METOD M55. Klockslaget för en Unix-sekund som hela minuter efter midnatt på uppvakningsdagen, i zonen
    /// `utcOffsetSeconds` (negativt kvällen före): 23:10 kvällen före är −50, 06:45 är 405. Avrundas nedåt.
    public static func clockMinutes(_ unix: Int, wakeDay: WakeDay, utcOffsetSeconds: Int) -> Int {
        let sekunder: Int = unix + utcOffsetSeconds - wakeDay.daysSince1970 * 86_400
        return Int((Double(sekunder) / 60).rounded(.down))
    }

    /// METOD M55. Unix-sekunden för klockslaget `minutes` efter midnatt på uppvakningsdagen i zonen `utcOffsetSeconds`.
    public static func unix(minutes: Int, wakeDay: WakeDay, utcOffsetSeconds: Int) -> Int {
        wakeDay.daysSince1970 * 86_400 + minutes * 60 - utcOffsetSeconds
    }

    /// METOD M55. Ändringen som appens blad ställer den: somnade och vaknade som minuter efter midnatt på
    /// uppvakningsdagen i nattens zon. Avvisas (`Problem`) som i `check`, mot dygnsfönstret i samma zon.
    public static func make(wakeDay: WakeDay, onsetMinutes: Int, wakeMinutes: Int, utcOffsetSeconds: Int,
                            foundOnset: Int? = nil, foundWake: Int? = nil) throws -> SleepEdit {
        let e = SleepEdit(wakeDay: wakeDay,
                          onset: unix(minutes: onsetMinutes, wakeDay: wakeDay, utcOffsetSeconds: utcOffsetSeconds),
                          wake: unix(minutes: wakeMinutes, wakeDay: wakeDay, utcOffsetSeconds: utcOffsetSeconds),
                          foundOnset: foundOnset, foundWake: foundWake)
        let w = SleepDetection.dayWindow(wakeDay: wakeDay, startOffsetSeconds: utcOffsetSeconds,
                                         endOffsetSeconds: utcOffsetSeconds)
        try e.check(window: w.from, to: w.to)
        return e
    }
}

/// METOD M55 · BESLUT B70
/// Alla ändrade nätter, en per uppvakningsdag: appens fil `somn-andringar.json` bredvid nätterna (samma mapp och
/// skyddsklass), och med i "Exportera alla dygn" så att avstämningen kan läsa den.
public struct SleepEdits: Codable, Equatable, Sendable {
    /// Filens namn i appens mapp och i exporten.
    public static let fileName = "somn-andringar.json"

    /// Filens form; höjs om den ändras.
    public var version: Int = 1
    /// En ändring per uppvakningsdag, äldst först.
    public private(set) var nights: [SleepEdit] = []

    public init(_ nights: [SleepEdit] = []) {
        var perDag: [Int: SleepEdit] = [:]
        for e in nights { perDag[e.wakeDayNumber] = e }
        self.nights = perDag.keys.sorted().compactMap { (d: Int) -> SleepEdit? in perDag[d] }
    }

    /// Ändringen för uppvakningsdagen, eller `nil` (natten är som den hittades).
    public subscript(day: WakeDay) -> SleepEdit? {
        nights.first { (e: SleepEdit) -> Bool in e.wakeDayNumber == day.daysSince1970 }
    }

    /// Med ändringen, i stället för en tidigare samma dag.
    public func setting(_ edit: SleepEdit) -> SleepEdits {
        SleepEdits(nights.filter { (e: SleepEdit) -> Bool in e.wakeDayNumber != edit.wakeDayNumber } + [edit])
    }

    /// Utan ändringen för dagen: Återställ. Natten räknas då med den hittade perioden igen.
    public func removing(_ day: WakeDay) -> SleepEdits {
        SleepEdits(nights.filter { (e: SleepEdit) -> Bool in e.wakeDayNumber != day.daysSince1970 })
    }

    public var isEmpty: Bool { nights.isEmpty }

    /// Filens innehåll: JSON med sorterade nycklar.
    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try e.encode(self)
    }

    /// Läser filen; kastar om den inte går att läsa.
    public static func decode(_ data: Data) throws -> SleepEdits {
        let läst: SleepEdits = try JSONDecoder().decode(SleepEdits.self, from: data)
        return SleepEdits(läst.nights)
    }
}
