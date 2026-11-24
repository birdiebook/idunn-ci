import Foundation

/// BESLUT B158 · METOD M85
/// Adaptern mellan en tid (`Date`) och nattens tidshjul (`Tidshjul` i appen, METOD M55), som räknar i minuter efter
/// en midnatt, −720 (12:00 dagen före) till 719 (11:59): ett klockslag från 12:00 räknas till kvällen före. Hjulet
/// vet inget om dagen, så ett valt klockslag blir den `Date` med det klockslaget som ligger närmast en referenstid.
public enum PassClock {
    public static let lowest: Int = -720
    public static let highest: Int = 719

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = timeZone
        return k
    }

    /// Hjulets minuter för tiden: klockslaget i `timeZone`, och från 12:00 minus ett dygn.
    public static func wheelMinutes(_ t: Date, timeZone: TimeZone = TimeZone.current) -> Int {
        let c: DateComponents = calendar(timeZone).dateComponents([.hour, .minute], from: t)
        let m: Int = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return m >= 720 ? m - 1_440 : m
    }

    /// Tiden med hjulets klockslag (dagen före, samma dag eller dagen efter referensen i `timeZone`) som ligger
    /// närmast `reference`. Ett klockslag som inte finns den dagen (sommartidens hopp) blir närmast efter hoppet.
    public static func date(wheelMinutes m: Int, near reference: Date, timeZone: TimeZone = TimeZone.current) -> Date {
        let k: Calendar = calendar(timeZone)
        let klocka: Int = ((m % 1_440) + 1_440) % 1_440
        let dagStart: Date = k.startOfDay(for: reference)
        var bäst: Date = reference
        var närmast: TimeInterval = Double.greatestFiniteMagnitude
        for d in -1...1 {
            guard let dag: Date = k.date(byAdding: .day, value: d, to: dagStart),
                  let t: Date = k.date(bySettingHour: klocka / 60, minute: klocka % 60, second: 0, of: dag) else { continue }
            let avstånd: TimeInterval = abs(t.timeIntervalSince(reference))
            if avstånd < närmast {
                närmast = avstånd
                bäst = t
            }
        }
        return bäst
    }
}
