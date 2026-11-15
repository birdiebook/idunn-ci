import Foundation
import Night

/// METOD M46 · BESLUT B56
/// Facit för ljudets klassning (PLAN.md J5): användaren lyssnar på ett klipp och
/// trycker rätt eller fel på klassen, och för en snarkning också på om "din"
/// (eller "annans") stämmer. Det sparas på telefonen, i en egen fil och inte i
/// klippmappen: klippen raderas efter 14 dagar (METOD M38) men facit ska överleva dem.
/// Bara klassen, ägaren och omdömet sparas, med klippets nyckel
/// (`NightSound.Clip.key`); aldrig ljudet.
///
/// B47 omprövas om klassningen av snarkning eller tal är fel i mer än var femte
/// lyssnat klipp: `ClassTally.overThreshold` säger det per klass, när minst
/// `minHeard` klipp lyssnats på (färre är för litet för att säga något).
public struct SoundFacit: Codable, Equatable, Sendable {

    /// METOD M46. Fel i mer än var femte lyssnat klipp ger en omprövning (BESLUT B47).
    public static let reviewShare: Double = 0.2
    /// METOD M46. Så här många lyssnade klipp i en klass krävs innan andelen fel jämförs med gränsen. **Antagande.**
    public static let minHeard = 5

    /// Omdömet om ett klipp.
    public struct Entry: Codable, Equatable, Sendable {
        /// `NightSound.Clip.key`.
        public var clip: String
        /// Klassen som Idunn satte (index i `SoundClass`).
        public var soundClass: Int
        /// Stämde klassen? `nil` = inte bedömd.
        public var classRight: Bool?
        /// Ägaren Idunn satte (bara för snarkning), och om den stämde.
        public var owner: NightSound.Owner?
        public var ownerRight: Bool?
        /// När senast bedömd, Unix-sekunder.
        public var at: Int

        public init(clip: String, soundClass: Int, classRight: Bool? = nil, owner: NightSound.Owner? = nil,
                    ownerRight: Bool? = nil, at: Int = 0) {
            self.clip = clip
            self.soundClass = soundClass
            self.classRight = classRight
            self.owner = owner
            self.ownerRight = ownerRight
            self.at = at
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public func entry(for clip: NightSound.Clip) -> Entry? {
        entries.first { (e: Entry) -> Bool in e.clip == clip.key }
    }

    /// Sätter omdömet om klassen för ett klipp (`nil` tar bort det). Ett omdöme på samma knapp en gång till
    /// tar bort det: knapparna är av och på.
    public mutating func rateClass(_ clip: NightSound.Clip, soundClass: Int, owner: NightSound.Owner?,
                                   right: Bool?, at: Int) {
        update(clip, soundClass: soundClass, owner: owner, at: at) { (e: inout Entry) -> Void in
            e.classRight = right
        }
    }

    /// Sätter omdömet om ägaren för en snarkning (`nil` tar bort det).
    public mutating func rateOwner(_ clip: NightSound.Clip, soundClass: Int, owner: NightSound.Owner?,
                                   right: Bool?, at: Int) {
        update(clip, soundClass: soundClass, owner: owner, at: at) { (e: inout Entry) -> Void in
            e.ownerRight = right
        }
    }

    private mutating func update(_ clip: NightSound.Clip, soundClass: Int, owner: NightSound.Owner?, at: Int,
                                 _ change: (inout Entry) -> Void) {
        let i: Int? = entries.firstIndex { (e: Entry) -> Bool in e.clip == clip.key }
        var e: Entry = i.map { (k: Int) -> Entry in entries[k] }
            ?? Entry(clip: clip.key, soundClass: soundClass, owner: owner)
        change(&e)
        e.at = at
        if e.classRight == nil && e.ownerRight == nil {
            if let k = i { entries.remove(at: k) }
            return
        }
        if let k = i { entries[k] = e } else { entries.append(e) }
    }

    // MARK: Sammanräkningen

    /// Lyssnade och felaktiga klipp i en klass.
    public struct ClassTally: Equatable, Sendable {
        public var soundClass: Int
        public var heard: Int
        public var wrong: Int

        /// Andelen fel av de lyssnade; `nil` utan något lyssnat.
        public var wrongShare: Double? { heard > 0 ? Double(wrong) / Double(heard) : nil }

        /// B47: över en femtedel fel, när tillräckligt många klipp lyssnats på för att det ska säga något.
        public var overThreshold: Bool {
            heard >= SoundFacit.minHeard && Double(wrong) / Double(heard) > SoundFacit.reviewShare
        }
    }

    /// Per klass (bara klasserna med något lyssnat), i klassernas ordning. Klassen är den Idunn satte.
    public func classTally() -> [ClassTally] {
        var heard = [Int](repeating: 0, count: SoundClasses.count)
        var wrong = [Int](repeating: 0, count: SoundClasses.count)
        for e in entries {
            guard let right = e.classRight, e.soundClass >= 0, e.soundClass < SoundClasses.count else { continue }
            heard[e.soundClass] += 1
            if !right { wrong[e.soundClass] += 1 }
        }
        return (0..<SoundClasses.count).compactMap { (c: Int) -> ClassTally? in
            heard[c] > 0 ? ClassTally(soundClass: c, heard: heard[c], wrong: wrong[c]) : nil
        }
    }

    /// Antal klipp där klassen bedömts, och hur många av dem som var fel.
    public var heard: Int { entries.filter { (e: Entry) -> Bool in e.classRight != nil }.count }
    public var wrong: Int { entries.filter { (e: Entry) -> Bool in e.classRight == false }.count }

    /// Snarkningens ägare: lyssnade och felaktiga omdömen om "din" eller "annans".
    public func ownerTally() -> ClassTally {
        let rated: [Entry] = entries.filter { (e: Entry) -> Bool in e.ownerRight != nil }
        return ClassTally(soundClass: SoundClass.snoring.rawValue, heard: rated.count,
                          wrong: rated.filter { (e: Entry) -> Bool in e.ownerRight == false }.count)
    }

    // MARK: Filen

    public func encode() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(self)) ?? Data()
    }

    /// Facit ur filen; en fil som inte går att läsa ger ett tomt facit (och skrivs över först vid nästa omdöme).
    public static func decode(_ data: Data) -> SoundFacit {
        (try? JSONDecoder().decode(SoundFacit.self, from: data)) ?? SoundFacit()
    }
}
