import Foundation

/// METOD M38 · BESLUT B47
/// Måtten för en sekund ljud, som de ligger i `.ljud`-filen: dB som Int16 i
/// tiondels dBFS, så att en sekund läses tillbaka bit för bit lika. Nivåerna
/// är dBFS, inte kalibrerade mot ljudtryck (METOD M38). Tystnad är −120 dBFS.
public struct SoundSecond: Equatable, Sendable {
    public static let bandCount = 8
    public static let classCount = 12
    /// `onset` när ingen ram i sekunden hade ett tydligt steg.
    public static let noOnset: UInt8 = 255
    /// Tystnad, dBFS.
    public static let silence: Double = -120

    /// Sekunder sedan nattens start (filens huvud). Saknade sekunder är glapp.
    public var second: Int
    /// Leq över sekundens prov, ovägd, tiondels dBFS.
    public var level: Int16
    /// A-vägd nivå ur banden, tiondels dBFS.
    public var levelA: Int16
    /// Högsta ramnivån, ovägd, tiondels dBFS.
    public var peak: Int16
    /// Åtta oktavband (63 Hz … 8 kHz), tiondels dBFS.
    public var bands: [Int16]
    /// Ramen (0–15) där nivån steg mest, eller 255.
    public var onset: UInt8
    /// Idunns tolv klasser (`SoundClass`) som 0–100.
    public var classes: [UInt8]

    public init(second: Int, level: Int16, levelA: Int16, peak: Int16, bands: [Int16],
                onset: UInt8 = 255, classes: [UInt8] = [UInt8](repeating: 0, count: 12)) {
        self.second = second
        self.level = level
        self.levelA = levelA
        self.peak = peak
        self.bands = bands
        self.onset = onset
        self.classes = classes
    }

    public var levelDB: Double { Double(level) / 10 }
    public var levelADB: Double { Double(levelA) / 10 }
    public var peakDB: Double { Double(peak) / 10 }
    public var bandsDB: [Double] { bands.map { (b: Int16) -> Double in Double(b) / 10 } }

    /// Klassens värde 0–100; 0 om raden är kortare än klasslistan.
    public func value(of c: SoundClass) -> Int {
        c.rawValue < classes.count ? Int(classes[c.rawValue]) : 0
    }

    /// dB till tiondels dB som Int16, begränsat till −120 … +20 dBFS.
    public static func tenths(_ db: Double) -> Int16 {
        guard db.isFinite else { return Int16(silence * 10) }
        return Int16((min(20, max(silence, db)) * 10).rounded())
    }
}
