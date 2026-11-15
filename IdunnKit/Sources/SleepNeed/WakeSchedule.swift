import Foundation

/// BESLUT B102 · METOD M53
/// Schemat för när användaren går upp: en tid per veckodag och en tid som bara gäller en morgon. Tiderna är minuter
/// efter midnatt på uppvakningsdagen, och `nil` är det vanliga uppvaknandet (medianen, M53). Dagen är alltid morgonen
/// han går upp: måndagens tid styr läggdags söndag kväll.
public struct WakeSchedule: Equatable, Sendable, Codable {
    /// En tid per veckodag, måndag först (0) till söndag (6).
    public var weekdays: [Double?]
    /// Uppvakningsdagen (dagar sedan 1970-01-01) som engångstiden gäller, och tiden. Båda eller ingen.
    public var onceDay: Int?
    public var onceMinute: Double?

    /// Ett tomt schema: det vanliga uppvaknandet alla dagar.
    public init() {
        weekdays = Array(repeating: nil, count: 7)
    }

    /// Samma tid alla dagar (BESLUT B74:s enda väcktid), eller ett tomt schema för `nil`.
    public init(every minute: Double?) {
        weekdays = Array(repeating: minute, count: 7)
    }

    public init(weekdays: [Double?], onceDay: Int? = nil, onceMinute: Double? = nil) {
        var w: [Double?] = Array(weekdays.prefix(7))
        while w.count < 7 { w.append(nil) }
        self.weekdays = w
        if let d = onceDay, let m = onceMinute {
            self.onceDay = d
            self.onceMinute = m
        }
    }

    /// Veckodagen för en dag (dagar sedan 1970-01-01, som var en torsdag): 0 måndag … 6 söndag.
    public static func weekday(ofDay day: Int) -> Int {
        (((day + 3) % 7) + 7) % 7
    }

    /// Engångstiden för uppvakningsdagen `day`, om den gäller just den dagen.
    public func once(wakeDay day: Int) -> Double? {
        guard let d = onceDay, d == day else { return nil }
        return onceMinute
    }

    /// Veckodagens tid för uppvakningsdagen `day`, utan engångstiden.
    public func weekdayMinute(wakeDay day: Int) -> Double? {
        let i = Self.weekday(ofDay: day)
        return i < weekdays.count ? weekdays[i] : nil
    }

    /// Tiden som gäller uppvakningsdagen `day`: engångstiden om den är satt för dagen, annars veckodagens. `nil` är
    /// det vanliga uppvaknandet.
    public func minute(wakeDay day: Int) -> Double? {
        once(wakeDay: day) ?? weekdayMinute(wakeDay: day)
    }

    /// Inget är satt: varje dag räknas från det vanliga uppvaknandet.
    public var isEmpty: Bool {
        onceDay == nil && !weekdays.contains { (m: Double?) -> Bool in m != nil }
    }

    /// Veckodagarna `days` (0–6) får tiden `minute`; `nil` återställer dem till det vanliga uppvaknandet. En
    /// engångstid ändras inte.
    public func setting(_ minute: Double?, weekdays days: Set<Int>) -> WakeSchedule {
        var s = self
        while s.weekdays.count < 7 { s.weekdays.append(nil) }
        for i in days where (0..<7).contains(i) { s.weekdays[i] = minute }
        return s
    }

    /// Engångstiden `minute` för uppvakningsdagen `day`; `nil` tar bort engångstiden. Veckodagarna ändras inte.
    public func settingOnce(_ minute: Double?, wakeDay day: Int) -> WakeSchedule {
        var s = self
        if let m = minute {
            s.onceDay = day
            s.onceMinute = m
        } else {
            s.onceDay = nil
            s.onceMinute = nil
        }
        return s
    }

    /// Veckodagarna som delar tid med veckodagen `index`: samma tid, eller också utan tid. Det bladet väljer när det
    /// öppnas, så att ett schema med en tid för alla dagar ändras som den enda väcktiden förut.
    public func group(of index: Int) -> Set<Int> {
        guard (0..<7).contains(index), weekdays.count == 7 else { return [] }
        let m: Double? = weekdays[index]
        return Set((0..<7).filter { (i: Int) -> Bool in weekdays[i] == m })
    }
}

/// BESLUT B103 · METOD M53
/// En påminnelse före läggdags: natten den gäller (uppvakningsdagen), läggdags och tiden påminnelsen kommer. Minuterna
/// räknas från uppvakningsdagens midnatt i telefonens väggklocka, så läggdags 22.48 är −72 och påminnelsen −87.
public struct BedtimeReminder: Equatable, Sendable {
    public var wakeDay: Int
    public var bedtimeMinute: Double
    public var fireMinute: Double

    public init(wakeDay: Int, bedtimeMinute: Double, fireMinute: Double) {
        self.wakeDay = wakeDay
        self.bedtimeMinute = bedtimeMinute
        self.fireMinute = fireMinute
    }

    /// Dagen och minuten på dygnet (0–1439) för ett klockslag räknat från uppvakningsdagens midnatt: −87 dagen `d`
    /// är 22.33 dagen `d − 1`.
    public static func wallClock(day: Int, minute: Double) -> (day: Int, minuteOfDay: Int) {
        let hel: Int = Int(minute.rounded())
        let dagar: Int = Int((Double(hel) / 1440).rounded(.down))
        return (day + dagar, hel - dagar * 1440)
    }

    /// Dagen och minuten på dygnet påminnelsen kommer.
    public var fire: (day: Int, minuteOfDay: Int) { Self.wallClock(day: wakeDay, minute: fireMinute) }
}

extension SleepNeed {
    /// METOD M53 · BESLUT B102. Dag för dag som `days(nights:passes:whoopBase:wakeMinute:)`, med kvällens läggdags
    /// räknad från schemats tid för morgonen efter (`schedule.minute(wakeDay:)`); en dag utan tid räknas från det
    /// vanliga uppvaknandet. Behovet och skulden ändras inte av schemat.
    public static func days(nights: [SleepNight], passes: [PassDay], whoopBase: Double? = nil,
                            schedule: WakeSchedule) -> [NeedDay] {
        days(nights: nights, passes: passes, whoopBase: whoopBase) { (wakeDay: Int) -> Double? in
            schedule.minute(wakeDay: wakeDay)
        }
    }

    /// METOD M53 · BESLUT B103. Påminnelserna före läggdags som ligger framför `now`: natten som slutar i dag (när
    /// läggdags inte har passerat) och de `bedtimeReminderNights` nätterna efter. Varje natts läggdags är kvällens
    /// plan (`tonight`, läggdags för bästa förväntade sömnpoäng) med schemats tid för morgonen och skulden efter den
    /// senaste natten; påminnelsen kommer `bedtimeReminderLeadMinutes` före. Nätterna efter den första är en reserv
    /// som räknas om när en ny natt finns. En natt utan plan (inga nätter före) ger ingen påminnelse.
    public static func reminders(nights: [SleepNight], passes: [PassDay], whoopBase: Double? = nil,
                                 schedule: WakeSchedule, now: Date, timeZone: TimeZone) -> [BedtimeReminder] {
        let base = baseNeed(whoopBase: whoopBase).minutes
        let nu = LocalClock(now, timeZone)
        var ut: [BedtimeReminder] = []
        for dag in nu.day...(nu.day + SleepNeedRules.bedtimeReminderNights) {
            guard let plan = tonight(nights: nights, passes: passes, base: base, day: dag,
                                     wakeMinute: schedule.minute(wakeDay: dag)) else { continue }
            let tid = plan.bestBedtimeMinute - SleepNeedRules.bedtimeReminderLeadMinutes
            guard tid > nu.minutes(from: dag) else { continue }
            ut.append(BedtimeReminder(wakeDay: dag, bedtimeMinute: plan.bestBedtimeMinute, fireMinute: tid))
        }
        return ut
    }
}
