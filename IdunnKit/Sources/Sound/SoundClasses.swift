import Foundation

/// METOD M38 · BESLUT B47
/// Idunns tolv ljudklasser, i den ordning de ligger i `.ljud`-filen och i
/// `SoundSecond.classes`. Ordningen och namnen ändras aldrig utan att
/// `SoundClasses.version` stiger: filerna bär bara index.
public enum SoundClass: Int, CaseIterable, Codable, Sendable {
    case snoring = 0, breathing, speech, cough, child, traffic, alarm, door, animal, weather, music, other

    /// Namnet som visas (J3) och som `tools/ljud_analys.py` skriver.
    public var label: String {
        switch self {
        case .snoring: return "snarkning"
        case .breathing: return "andning"
        case .speech: return "tal"
        case .cough: return "hosta"
        case .child: return "barn"
        case .traffic: return "trafik"
        case .alarm: return "larm"
        case .door: return "dörr"
        case .animal: return "djur"
        case .weather: return "väder"
        case .music: return "musik"
        case .other: return "övrigt"
        }
    }
}

/// METOD M38 · BESLUT B47
/// Tabellen från Apples identifierare (`SNClassifierIdentifier.version1`, 303
/// klasser) till Idunns tolv, som data. `group` tar ett svar från SoundAnalysis
/// som `[identifierare: sannolikhet]` och ger tolv värden 0–100: högsta
/// sannolikheten bland klassens identifierare. `övrigt` är högsta av allt som
/// inte står i någon annan klass, utom `silence`.
///
/// Listan är hämtad ur en sammanställning av klassificerarens klasser, inte ur
/// Apples egen lista; provet i appen (J2) jämför varje identifierare med
/// `SNClassifySoundRequest.knownClassifications`.
public enum SoundClasses {
    /// Klasslistans version, i `.ljud`-huvudet. Stiger om tabellen eller ordningen ändras.
    public static let version: UInt8 = 1
    public static let count = 12

    static let snoring: [String] = ["snoring"]
    static let breathing: [String] = ["breathing", "gasp", "sigh"]
    static let speech: [String] = [
        "speech", "whispering", "shout", "yell", "screaming", "laughter", "giggling",
        "crying_sobbing", "singing",
    ]
    static let cough: [String] = ["cough", "sneeze", "hiccup"]
    static let child: [String] = ["baby_crying", "baby_laughter"]
    static let traffic: [String] = [
        "traffic_noise", "car_passing_by", "car_horn", "truck", "motorcycle", "bus", "race_car",
        "vehicle_skidding", "train", "train_horn", "train_whistle", "airplane", "helicopter", "engine",
        "engine_idling", "engine_starting", "engine_accelerating_revving", "engine_knocking",
        "air_horn", "reverse_beeps",
    ]
    static let alarm: [String] = [
        "alarm_clock", "ringtone", "telephone", "telephone_bell_ringing", "smoke_detector", "siren",
        "civil_defense_siren", "police_siren", "ambulance_siren", "fire_engine_siren",
        "emergency_vehicle", "beep",
    ]
    static let door: [String] = ["door", "door_slam", "door_sliding", "door_bell", "knock"]
    static let animal: [String] = [
        "dog", "dog_bark", "dog_howl", "cat", "cat_meow", "cat_purr", "bird", "bird_chirp_tweet",
        "bird_squawk",
    ]
    static let weather: [String] = ["rain", "raindrop", "wind", "thunder", "thunderstorm"]
    static let music: [String] = ["music", "guitar", "piano", "drum", "trumpet", "violin_fiddle"]

    /// Identifierarna per klass i klassernas ordning. `övrigt` har ingen lista.
    public static let table: [[String]] = [
        snoring, breathing, speech, cough, child, traffic, alarm, door, animal, weather, music, [],
    ]

    /// Identifierarna i klassen.
    public static func identifiers(of c: SoundClass) -> [String] { table[c.rawValue] }

    /// Alla identifierare som tabellen nämner, för jämförelsen mot `knownClassifications`.
    public static let allIdentifiers: [String] = table.flatMap { (l: [String]) -> [String] in l }

    private static let listed: Set<String> = Set(allIdentifiers)

    /// Klassen en identifierare hör till; `nil` för `silence`.
    public static func soundClass(of identifier: String) -> SoundClass? {
        if identifier == "silence" { return nil }
        for c in SoundClass.allCases where c != .other {
            if table[c.rawValue].contains(identifier) { return c }
        }
        return .other
    }

    /// Apples svar till Idunns tolv klasser, 0–100.
    public static func group(_ apple: [String: Double]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        for c in 0..<(count - 1) {
            var best: Double = 0
            for id in table[c] {
                if let v = apple[id], v > best { best = v }
            }
            out[c] = scaled(best)
        }
        var rest: Double = 0
        for (id, v) in apple where id != "silence" && !listed.contains(id) {
            if v > rest { rest = v }
        }
        out[count - 1] = scaled(rest)
        return out
    }

    static func scaled(_ p: Double) -> UInt8 {
        guard p.isFinite else { return 0 }
        return UInt8(min(100, max(0, (p * 100).rounded())))
    }
}
