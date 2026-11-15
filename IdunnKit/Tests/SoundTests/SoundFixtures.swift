import Foundation
import DemoData
import Night
@testable import Sound

// PÅHITTAD data (DemoSound): ingen mikrofon, inget band. Natten och dess
// sammanfattning räknas en gång för alla prov i målet.

enum SoundFixtures {
    static let night: DemoSound.Night = DemoSound.night()

    static let summary: SoundNight = SoundNight.analyze(
        SoundFixtures.night.seconds, soundStart: SoundFixtures.night.start,
        series: SoundFixtures.night.series, layers: SoundFixtures.night.layers)

    /// En sekund med given A-vägd nivå; ovägd nivå 3 dB över, toppen 3 dB över den.
    static func second(_ i: Int, levelA: Double = -60, classes: [SoundClass: Int] = [:],
                       onset: UInt8 = 255) -> SoundSecond {
        var c = [UInt8](repeating: 0, count: SoundSecond.classCount)
        for (k, v) in classes { c[k.rawValue] = UInt8(v) }
        let level: Double = levelA + 3
        return SoundSecond(second: i, level: SoundSecond.tenths(level), levelA: SoundSecond.tenths(levelA),
                           peak: SoundSecond.tenths(level + 3),
                           bands: [Int16](repeating: SoundSecond.tenths(level - 6), count: SoundSecond.bandCount),
                           onset: onset, classes: c)
    }

    /// `n` tysta sekunder från `from`.
    static func quiet(_ from: Int, _ n: Int) -> [SoundSecond] {
        (from..<(from + n)).map { (i: Int) -> SoundSecond in second(i) }
    }

    /// `n` höga sekunder (20 dB över bakgrunden) från `from`, med en klass.
    static func loud(_ from: Int, _ n: Int, db: Double = 20, _ cls: SoundClass? = nil,
                     value: Int = 70) -> [SoundSecond] {
        (from..<(from + n)).map { (i: Int) -> SoundSecond in
            second(i, levelA: -60 + db, classes: cls.map { (c: SoundClass) -> [SoundClass: Int] in [c: value] } ?? [:])
        }
    }
}
