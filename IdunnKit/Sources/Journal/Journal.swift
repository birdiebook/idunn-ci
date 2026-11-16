import Foundation

/// BESLUT B127 · METOD M73
/// En tagg som går att sätta på en kväll: något som kan påverka natten som följer. Listan är en inställning
/// (`JournalTags.standard`); filen sparar bara taggens id, så en ny tagg kräver ingen ny filform.
public struct JournalTag: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Valfri detalj, ett av de här orden (till exempel "liten" eller "stor"); tom = ingen detalj att välja.
    public var options: [String]

    public init(id: String, title: String, options: [String] = []) {
        self.id = id
        self.title = title
        self.options = options
    }
}

/// BESLUT B127 · METOD M73. Kvällens taggar som de visas, i den här ordningen.
public enum JournalTags {
    public static let standard: [JournalTag] = [
        JournalTag(id: "styrka", title: "Styrkepass", options: ["lätt", "tungt"]),
        JournalTag(id: "kondition", title: "Kondition eller golf"),
        JournalTag(id: "bastu", title: "Bastu"),
        JournalTag(id: "sen-maltid", title: "Sen måltid", options: ["liten", "stor"]),
        JournalTag(id: "alkohol", title: "Alkohol", options: ["1 glas", "2 glas", "3 eller fler"]),
        JournalTag(id: "koffein", title: "Koffein sent"),
        JournalTag(id: "magnesium", title: "Magnesium"),
        JournalTag(id: "stress", title: "Stress"),
        JournalTag(id: "sjuk", title: "Sjukdomskänsla"),
        JournalTag(id: "varmt", title: "Varmt sovrum"),
    ]

    /// Taggen med det här id:t, eller `nil` (en tagg som tagits ur listan står kvar i filen).
    public static func tag(_ id: String, in tags: [JournalTag] = standard) -> JournalTag? {
        tags.first { (t: JournalTag) -> Bool in t.id == id }
    }
}

/// BESLUT B127. En vald tagg på en kväll.
public struct EveningTag: Codable, Equatable, Sendable {
    public var id: String
    public var detail: String?

    public init(id: String, detail: String? = nil) {
        self.id = id
        self.detail = detail
    }
}

/// BESLUT B127 · METOD M73. En besvarad kväll: taggarna för natten som slutar på `wakeDayNumber` (dagar sedan
/// 1970). En kväll utan taggar är också ett svar: "inget av det".
public struct JournalEvening: Codable, Equatable, Sendable {
    public var wakeDayNumber: Int
    public var tags: [EveningTag]
    /// När svaret gavs, Unix-sekunder.
    public var recordedAt: Int

    public init(wakeDayNumber: Int, tags: [EveningTag], recordedAt: Int) {
        self.wakeDayNumber = wakeDayNumber
        self.tags = tags
        self.recordedAt = recordedAt
    }
}

/// BESLUT B127 · METOD M73. Morgonens skattning: hur utvilad, 1–5, given innan nattens tal visats.
public struct JournalMorning: Codable, Equatable, Sendable {
    public var wakeDayNumber: Int
    public var rested: Int
    public var recordedAt: Int

    public init(wakeDayNumber: Int, rested: Int, recordedAt: Int) {
        self.wakeDayNumber = wakeDayNumber
        self.rested = rested
        self.recordedAt = recordedAt
    }
}

/// BESLUT B127 · METOD M73
/// Dagboken: appens fil `dagbok.json` bredvid nätterna (samma mapp och skyddsklass), och med i "Exportera alla
/// dygn" så att `tools/hrv_varianter.py` kan läsa den. En kväll och en morgon per uppvakningsdag.
public struct Journal: Codable, Equatable, Sendable {
    /// Filens namn i appens mapp och i exporten.
    public static let fileName = "dagbok.json"
    /// METOD M73. Skattningens skala.
    public static let restedRange: ClosedRange<Int> = 1...5

    /// Filens form; höjs om den ändras.
    public var version: Int = 1
    /// Äldst först.
    public private(set) var evenings: [JournalEvening] = []
    public private(set) var mornings: [JournalMorning] = []
    /// Morgnar där frågan hoppades över: de frågas inte igen, och har ingen skattning.
    public private(set) var skippedMornings: [Int] = []

    public init(evenings: [JournalEvening] = [], mornings: [JournalMorning] = [], skippedMornings: [Int] = []) {
        var kvällar: [Int: JournalEvening] = [:]
        for e in evenings { kvällar[e.wakeDayNumber] = e }
        self.evenings = kvällar.keys.sorted().compactMap { (d: Int) -> JournalEvening? in kvällar[d] }
        var morgnar: [Int: JournalMorning] = [:]
        for m in mornings where Journal.restedRange.contains(m.rested) { morgnar[m.wakeDayNumber] = m }
        self.mornings = morgnar.keys.sorted().compactMap { (d: Int) -> JournalMorning? in morgnar[d] }
        self.skippedMornings = Set(skippedMornings).subtracting(morgnar.keys).sorted()
    }

    public func evening(_ wakeDayNumber: Int) -> JournalEvening? {
        evenings.first { (e: JournalEvening) -> Bool in e.wakeDayNumber == wakeDayNumber }
    }

    public func morning(_ wakeDayNumber: Int) -> JournalMorning? {
        mornings.first { (m: JournalMorning) -> Bool in m.wakeDayNumber == wakeDayNumber }
    }

    /// Morgonen är besvarad eller överhoppad: frågan ställs inte igen.
    public func morningHandled(_ wakeDayNumber: Int) -> Bool {
        morning(wakeDayNumber) != nil || skippedMornings.contains(wakeDayNumber)
    }

    /// Med kvällen, i stället för en tidigare för samma natt.
    public func setting(_ evening: JournalEvening) -> Journal {
        Journal(evenings: evenings + [evening], mornings: mornings, skippedMornings: skippedMornings)
    }

    /// Med skattningen, i stället för en tidigare samma morgon. En skattning utanför 1–5 ändrar ingenting.
    public func setting(_ morning: JournalMorning) -> Journal {
        guard Journal.restedRange.contains(morning.rested) else { return self }
        return Journal(evenings: evenings, mornings: mornings + [morning], skippedMornings: skippedMornings)
    }

    /// Med morgonen överhoppad. En morgon som redan har en skattning behåller den.
    public func skippingMorning(_ wakeDayNumber: Int) -> Journal {
        Journal(evenings: evenings, mornings: mornings, skippedMornings: skippedMornings + [wakeDayNumber])
    }

    public var isEmpty: Bool { evenings.isEmpty && mornings.isEmpty && skippedMornings.isEmpty }

    /// METOD M73. Nätter per tagg, flest först och vid lika i bokstavsordning: det utvärderingen behöver fem av.
    public var nightsPerTag: [TagCount] {
        var antal: [String: Int] = [:]
        for e in evenings {
            for id in Set(e.tags.map { (t: EveningTag) -> String in t.id }) { antal[id, default: 0] += 1 }
        }
        let ordnade: [String] = antal.keys.sorted { (a: String, b: String) -> Bool in
            let x: Int = antal[a] ?? 0
            let y: Int = antal[b] ?? 0
            return x != y ? x > y : a < b
        }
        return ordnade.map { (id: String) -> TagCount in TagCount(id: id, nights: antal[id] ?? 0) }
    }

    /// Filens innehåll: JSON med sorterade nycklar.
    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try e.encode(self)
    }

    /// Läser filen; kastar om den inte går att läsa eller har en annan version.
    public static func decode(_ data: Data) throws -> Journal {
        let läst: Journal = try JSONDecoder().decode(Journal.self, from: data)
        guard läst.version == 1 else { throw JournalError.unknownVersion }
        return Journal(evenings: läst.evenings, mornings: läst.mornings, skippedMornings: läst.skippedMornings)
    }
}

/// METOD M73. Antalet nätter med en tagg.
public struct TagCount: Equatable, Sendable {
    public var id: String
    public var nights: Int

    public init(id: String, nights: Int) {
        self.id = id
        self.nights = nights
    }
}

public enum JournalError: Error, Equatable {
    /// Filen är skriven av ett nyare bygge. Felet bär inget värde ur filen.
    case unknownVersion
}

/// BESLUT B127 · METOD M73
/// När dagboken frågar, och vilken natt ett svar hör till. Dagen är väggklockans, i telefonens zon.
public enum JournalClock {
    /// METOD M73. Morgonens fråga ställs när appen öppnas från och med den här timmen och före `morningEnd`.
    public static let morningStart: Int = 3
    public static let morningEnd: Int = 14
    /// METOD M73. Kvällens fråga ställs från och med den här timmen och fram till `morningStart` nästa dygn.
    public static let eveningStart: Int = 18
    /// METOD M73. En kväll som loggas före den här timmen hör till natten som just varit på väg (efter midnatt);
    /// från och med den hör den till natten som kommer. Samma gräns som dygnsfönstret (METOD M26).
    public static let noon: Int = 12

    public enum Prompt: Equatable, Sendable {
        /// Fråga hur utvilad, för uppvakningsdagen.
        case morning(wakeDayNumber: Int)
        /// Fråga efter kvällens taggar, för natten som slutar på uppvakningsdagen.
        case evening(wakeDayNumber: Int)
    }

    /// Väggklockans dag (dagar sedan 1970) och timme.
    static func local(_ date: Date, utcOffsetSeconds: Int) -> (day: Int, hour: Int) {
        let t: Double = date.timeIntervalSince1970 + Double(utcOffsetSeconds)
        let dag: Int = Int((t / 86_400).rounded(.down))
        let timme: Int = Int(((t - Double(dag) * 86_400) / 3_600).rounded(.down))
        return (dag, min(23, max(0, timme)))
    }

    /// Uppvakningsdagen för en morgon: väggklockans dag.
    public static func morningDay(_ date: Date, utcOffsetSeconds: Int) -> Int {
        local(date, utcOffsetSeconds: utcOffsetSeconds).day
    }

    /// Uppvakningsdagen för natten en kväll hör till: nästa dag från kl 12, samma dag före.
    public static func eveningDay(_ date: Date, utcOffsetSeconds: Int) -> Int {
        let nu = local(date, utcOffsetSeconds: utcOffsetSeconds)
        return nu.hour >= noon ? nu.day + 1 : nu.day
    }

    /// Vad appen ska fråga när den öppnas, eller `nil`. På morgonen (3–14) skattningen, om den varken är given eller
    /// överhoppad. På kvällen (från 18, och efter midnatt till 3) taggarna, om kvällen inte är besvarad.
    public static func prompt(at date: Date, utcOffsetSeconds: Int, journal: Journal) -> Prompt? {
        let nu = local(date, utcOffsetSeconds: utcOffsetSeconds)
        if nu.hour >= morningStart && nu.hour < morningEnd {
            return journal.morningHandled(nu.day) ? nil : .morning(wakeDayNumber: nu.day)
        }
        if nu.hour >= eveningStart || nu.hour < morningStart {
            let dag: Int = eveningDay(date, utcOffsetSeconds: utcOffsetSeconds)
            return journal.evening(dag) == nil ? .evening(wakeDayNumber: dag) : nil
        }
        return nil
    }
}
