import Foundation

/// En pulsnotis som den sparas: telefonens tid när den kom, och vad den bar.
/// Bandets egen klocka följer inte med i 2A37, så telefonens tid är den enda.
public struct HeartRateSample: Equatable, Codable, Sendable {
    public var time: Date
    public var bpm: Int
    /// METOD M1. 0–n intervall per notis, i millisekunder.
    public var rrMilliseconds: [Double]
    public var sensorContact: HeartRateMeasurement.SensorContact?
    /// METOD M15. Notisens flaggbyte (2A37), för diagnosen. Inget hälsovärde.
    public var flags: UInt8?

    public init(time: Date, bpm: Int, rrMilliseconds: [Double] = [],
                sensorContact: HeartRateMeasurement.SensorContact? = nil, flags: UInt8? = nil) {
        self.time = time
        self.bpm = bpm
        self.rrMilliseconds = rrMilliseconds
        self.sensorContact = sensorContact
        self.flags = flags
    }

    public init(_ measurement: HeartRateMeasurement, at time: Date) {
        self.init(time: time, bpm: measurement.bpm, rrMilliseconds: measurement.rrMilliseconds,
                  sensorContact: measurement.sensorContact, flags: measurement.flags)
    }
}

/// En natts inspelning (PLAN.md I2): alla notiser i tidsordning, och bandets
/// batteri i procent vid start och slut (0x180F), så att förbrukningen per
/// natt går att mäta. Rena värdetyper — lagringen ligger i appen.
public struct NightRecording: Equatable, Codable, Sendable {
    /// I tidsordning. `init` sorterar och `append` lägger in på rätt plats,
    /// så en klocka som ställs om mitt i natten ger ingen baklänges serie.
    public var samples: [HeartRateSample]
    public var batteryAtStart: Int?
    public var batteryAtEnd: Int?

    public init(samples: [HeartRateSample] = [], batteryAtStart: Int? = nil, batteryAtEnd: Int? = nil) {
        self.samples = samples.sorted { $0.time < $1.time }
        self.batteryAtStart = batteryAtStart
        self.batteryAtEnd = batteryAtEnd
    }

    public mutating func append(_ sample: HeartRateSample) {
        if let last = samples.last, sample.time < last.time {
            let i = samples.firstIndex { $0.time > sample.time } ?? samples.endIndex
            samples.insert(sample, at: i)
        } else {
            samples.append(sample)
        }
    }

    public mutating func append(_ measurement: HeartRateMeasurement, at time: Date) {
        append(HeartRateSample(measurement, at: time))
    }

    public var start: Date? { samples.first?.time }
    public var end: Date? { samples.last?.time }

    /// Från första till sista notisen, glappen inräknade.
    public var span: TimeInterval {
        guard let s = start, let e = end else { return 0 }
        return e.timeIntervalSince(s)
    }
}
