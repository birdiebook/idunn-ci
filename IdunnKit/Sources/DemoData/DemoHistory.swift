// PÅHITTADE äldre nätter ur K18 för förhandsvisningen (BESLUT B20, METOD M42). Inget kommer från ett
// riktigt band: allt räknas fram ur formler och en seedad slumpgenerator. Lägg ALDRIG in riktiga värden
// här — se CLAUDE.md §Dataregeln.
//
// Varför de finns: normalområdet (METOD M7) kräver tre nätter i var och en av de fyra veckorna före veckan
// som bedöms, och måtten som bara en natt ur K18 har (medelpuls, sömn, minuter i rörelse, regelbundenhet)
// har i provet bara de senaste fjorton nätterna: en natt ur K18 kostar tid att räkna slag för slag. Här
// ges samlade tal för de äldre dagarna, så att alla rader på Morgon och alla diagram i Över tid har sitt
// band. Talen ligger i samma trakt som de räknade demonätterna (`DemoK18Nights`): medelpuls kring 54,
// sömn kring sex timmar, insomning kring tio på kvällen.

import Foundation
import Night

public enum DemoHistory {

    /// En äldre natts samlade tal. Tiderna är sekunder sedan 1970.
    public struct Night: Equatable, Sendable {
        /// Morgnar före den sista (`DemoNights.lastWakeDayUTC`).
        public var daysBeforeLast: Int
        /// Medelpulsen över sömnperioden, slag per minut.
        public var meanHeartRate: Double
        /// Sömntiden i minuter: perioden utan vakna stunder.
        public var sleepMinutes: Double
        /// Minuter i rörelse under sömnperioden (METOD M42).
        public var movementMinutes: Int
        /// Insomning och uppvaknande (sömnperioden).
        public var onset: Int
        public var wake: Int
        /// METOD M50 · METOD M52 (D2). Antalet vakna stunder och minuterna i vaken, lätt, djup och REM. Lätt + djup
        /// + REM är sömntiden; vaken är resten av perioden. Påhittade, i samma trakt som de räknade demonätterna.
        public var wakeBouts: Int = 0
        public var awakeMinutes: Double = 0
        public var lightMinutes: Double = 0
        public var deepMinutes: Double = 0
        public var remMinutes: Double = 0

        public init(daysBeforeLast: Int, meanHeartRate: Double, sleepMinutes: Double, movementMinutes: Int,
                    onset: Int, wake: Int, wakeBouts: Int = 0, awakeMinutes: Double = 0, lightMinutes: Double = 0,
                    deepMinutes: Double = 0, remMinutes: Double = 0) {
            self.daysBeforeLast = daysBeforeLast
            self.meanHeartRate = meanHeartRate
            self.sleepMinutes = sleepMinutes
            self.movementMinutes = movementMinutes
            self.onset = onset
            self.wake = wake
            self.wakeBouts = wakeBouts
            self.awakeMinutes = awakeMinutes
            self.lightMinutes = lightMinutes
            self.deepMinutes = deepMinutes
            self.remMinutes = remMinutes
        }

        /// Uppvakningsdagen.
        public var wakeDay: WakeDay { WakeDay(daysSince1970: Int(DemoNights.lastWakeDayUTC / 86_400) - daysBeforeLast) }

        /// Sömnperiodens längd i minuter.
        public var periodMinutes: Double { Double(wake - onset) / 60 }
    }

    /// Natten som slutar `k` morgnar före den sista. Samma seed ger samma natt.
    public static func night(daysBeforeLast k: Int, seed: UInt64 = 1) -> Night {
        var r = Seeded(seed &+ UInt64(k) &* 8191 &+ 61)
        let medelpuls: Double = 54.5 + 1.5 * r.gauss()
        let sömn: Double = (365 + 22 * r.gauss()).rounded()
        let vaken: Double = (20 + 8 * r.uniform()).rounded()
        let rörelse: Int = min(14, max(1, 6 + Int((2.5 * r.gauss()).rounded())))
        // Midnatt på uppvakningsdagen i telefonens zon; insomning kring tio på kvällen, ±12 minuter.
        let midnatt: Int = Int(DemoNights.lastWakeDayUTC) - k * 86_400 - DemoNights.utcOffsetSeconds
        let onset: Int = midnatt - 120 * 60 + Int((12 * 60 * r.gauss()).rounded())
        let wake: Int = onset + Int(((sömn + vaken) * 60).rounded())
        // METOD M52 (D2). Stadierna delar sömntiden: djup kring 17 %, REM kring 21 %, resten lätt. Egna dragningar efter de
        // gamla, så att ingen äldre natt ändras av att de finns.
        let djup: Double = (sömn * (0.17 + 0.025 * r.gauss())).rounded()
        let rem: Double = (sömn * (0.21 + 0.025 * r.gauss())).rounded()
        let stunder: Int = 6 + Int((r.uniform() * 9).rounded())
        return Night(daysBeforeLast: k, meanHeartRate: medelpuls, sleepMinutes: sömn, movementMinutes: rörelse,
                     onset: onset, wake: wake, wakeBouts: stunder, awakeMinutes: vaken, lightMinutes: sömn - djup - rem,
                     deepMinutes: djup, remMinutes: rem)
    }

    /// METOD M50 · METOD M52 · BESLUT B63. Sätter K18-nattens egna tal på en natt: medelpuls, sömntid och sömnperiod
    /// (för regelbundenheten), minuter i rörelse, effektivitet, vakna stunder, stadiernas minuter och klockslagen.
    /// Snarkningen och källan sätts av anroparen.
    public static func apply(_ h: Night, to natt: inout Trends.IdunNight) {
        natt.meanHeartRate = h.meanHeartRate
        natt.sleepHours = h.sleepMinutes / 60
        natt.sleepEpisode = Trends.sleepEpisode(source: .k18, start: Date(timeIntervalSince1970: Double(h.onset)),
                                                end: Date(timeIntervalSince1970: Double(h.wake)),
                                                utcOffsetSeconds: DemoNights.utcOffsetSeconds,
                                                sleepMinutes: h.sleepMinutes, coverage: 0.95)
        natt.movementMinutes = h.movementMinutes
        natt.source = .k18
        let längd: Double = h.periodMinutes
        natt.efficiency = längd > 0 ? min(100, 100 * h.sleepMinutes / längd) : nil
        natt.wakeBouts = h.wakeBouts
        natt.awakeMinutes = h.awakeMinutes
        natt.lightMinutes = h.lightMinutes
        natt.deepMinutes = h.deepMinutes
        natt.remMinutes = h.remMinutes
        natt.onsetMinutes = Trends.clockMinutes(Date(timeIntervalSince1970: Double(h.onset)), day: h.wakeDay,
                                                utcOffsetSeconds: DemoNights.utcOffsetSeconds)
        natt.wakeMinutes = Trends.clockMinutes(Date(timeIntervalSince1970: Double(h.wake)), day: h.wakeDay,
                                               utcOffsetSeconds: DemoNights.utcOffsetSeconds)
    }

    /// METOD M51 (D2). En hel påhittad natt, bara samlade tal, för Över tids halvår: det prov som annars hade behövt
    /// 182 nätter räknade slag för slag. HRV, vilopuls, andning och hudtemperatur kring nivåerna i de räknade demonätterna,
    /// med en långsam svängning så att diagrammen inte är platta; sömn, stadier, rörelse och snarkning ur `night`.
    /// En natt av tio saknar snarkning (inget ljud).
    public static func summaryNight(daysBeforeLast k: Int, seed: UInt64 = 1) -> Trends.IdunNight {
        var r = Seeded(seed &+ UInt64(k) &* 4093 &+ 907)
        let h: Night = night(daysBeforeLast: k, seed: seed)
        let svängning: Double = sin(Double(k) / 9)
        let rmssd: Double = max(28, 56 + 3 * svängning + 8 * r.gauss())
        let vilopuls: Double = max(46, 52 + 2 * r.gauss() - (rmssd - 56) * 0.06)
        var natt = Trends.IdunNight(day: h.wakeDay, validWindows: 80, rmssd: rmssd, restingHeartRate: vilopuls,
                                    breathsPerMinute: 13.4 + 0.3 * r.gauss(),
                                    skinTemperature: 33.6 + 0.25 * r.gauss(), id: "demo-\(k)")
        apply(h, to: &natt)
        natt.snoringPerHour = r.uniform() < 0.1 ? nil : max(0, 3 + 1.5 * r.gauss())
        return natt
    }

    /// METOD M51 (D2). Natterna för `range` morgnar före den sista, äldst först.
    public static func summaryNights(daysBeforeLast range: Range<Int>, seed: UInt64 = 1) -> [Trends.IdunNight] {
        range.reversed().map { (k: Int) -> Trends.IdunNight in summaryNight(daysBeforeLast: k, seed: seed) }
    }

    /// Nätterna för `range` morgnar före den sista, äldst först.
    public static func nights(daysBeforeLast range: Range<Int>, seed: UInt64 = 1) -> [Night] {
        range.reversed().map { (k: Int) -> Night in night(daysBeforeLast: k, seed: seed) }
    }
}
