import Foundation

/// METOD M1
/// En notis från Heart Rate Measurement (2A37) i Bluetooths standardtjänst för
/// puls (0x180D), som Whoop 5 sänder när "Broadcast Heart Rate" är på. Tolkas
/// byte för byte enligt Bluetooth SIG:s *Heart Rate Service 1.0*:
///
///     byte 0   flaggor
///              bit 0    pulsen är uint16 (annars uint8)
///              bit 1–2  sensorkontakt: 0 och 1 stöds inte, 2 ingen kontakt, 3 kontakt
///              bit 3    energifält följer pulsen (uint16, kJ — hoppas över)
///              bit 4    RR-intervall följer, uint16 vardera, enhet 1/1024 s
///              bit 5–7  reserverade
///     byte 1…  puls, energi, 0–n RR — allt little-endian, i den ordningen
///
/// En trasig eller för kort notis ger `nil`, aldrig en krasch. Notiserna kommer
/// över radio hela natten, och en enda konstig får inte fälla inspelningen.
public struct HeartRateMeasurement: Equatable, Sendable {
    /// Sensorkontakt enligt bit 1–2. Saknas helt (`nil`) när bandet inte
    /// rapporterar kontakt — det är inte samma sak som "ingen kontakt".
    public enum SensorContact: String, Equatable, Codable, Sendable {
        case detected
        case notDetected
    }

    /// Slag per minut, som bandet räknat fram det.
    public var bpm: Int
    public var sensorContact: SensorContact?
    /// METOD M1. RR-intervallen i millisekunder: värdet × 1000 / 1024. Upplösningen
    /// är alltså 1000/1024 ≈ 0,977 ms, och varje värde går att räkna tillbaka
    /// exakt till bandets heltal (`rrUnits(milliseconds:)`).
    public var rrMilliseconds: [Double]
    /// METOD M15. Flaggbyten som den kom, för diagnosen: vilka fält bandet
    /// säger att notisen bär. `nil` när notisen inte är tolkad ur byte.
    public var flags: UInt8?

    /// METOD M1. Enheten för RR i 2A37: 1/1024 s.
    public static let rrUnitsPerSecond = 1024.0

    public init(bpm: Int, sensorContact: SensorContact? = nil, rrMilliseconds: [Double] = [],
                flags: UInt8? = nil) {
        self.bpm = bpm
        self.sensorContact = sensorContact
        self.rrMilliseconds = rrMilliseconds
        self.flags = flags
    }

    /// Tolkar notisens värde som CoreBluetooth lämnar det. Kopierar till en
    /// array först, så att en `Data`-skiva med startindex skilt från 0 inte
    /// kan läsas fel.
    public init?(data: Data) {
        self.init(bytes: [UInt8](data))
    }

    public init?(bytes: [UInt8]) {
        guard let flags = bytes.first else { return nil }
        self.flags = flags
        var i = 1

        func uint16() -> UInt16? {
            guard i + 1 < bytes.count else { return nil }
            defer { i += 2 }
            return UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
        }

        if flags & 0x01 != 0 {
            guard let v = uint16() else { return nil }
            bpm = Int(v)
        } else {
            guard i < bytes.count else { return nil }
            bpm = Int(bytes[i])
            i += 1
        }

        switch (flags >> 1) & 0x03 {
        case 3: sensorContact = .detected
        case 2: sensorContact = .notDetected
        default: sensorContact = nil
        }

        if flags & 0x08 != 0 {
            guard uint16() != nil else { return nil }
        }

        rrMilliseconds = []
        if flags & 0x10 != 0 {
            // Resten av notisen är RR-intervall, två byte vardera. En udda byte
            // på slutet betyder en avklippt notis, och då litar vi inte på något i den.
            guard (bytes.count - i) % 2 == 0 else { return nil }
            while i < bytes.count {
                guard let v = uint16() else { return nil }
                rrMilliseconds.append(Double(v) * 1000 / Self.rrUnitsPerSecond)
            }
        }
        // Utan RR-flaggan ignoreras byte efter de kända fälten: bit 5–7 är
        // reserverade, och en senare version av standarden kan lägga fält där.
    }

    /// METOD M1. Millisekunder tillbaka till bandets heltal i 1/1024 s.
    public static func rrUnits(milliseconds: Double) -> Int {
        Int((milliseconds * rrUnitsPerSecond / 1000).rounded())
    }
}
