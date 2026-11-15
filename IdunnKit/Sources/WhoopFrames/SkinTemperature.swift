import Foundation

/// METOD M25 · METOD M24 · BESLUT B26
/// Nattens hudtemperatur ur K18: medianen av minuternas hudtemperatur över
/// inspelningens **stilla** minuter, och bara om K18 täcker tillräckligt av
/// inspelningen. Är täckningen för liten finns ingen temperatur för natten,
/// inte en gissad. Underlaget är sömnperiodens sömnminuter (R4, METOD M26)
/// när perioden finns, annars inspelningens stilla minuter.
public enum SkinTemperature {

    /// METOD M25. En minut är stilla när medlet av dess |Δg| ligger under så
    /// här många g. **Antagande:** PROTOKOLL_W5 §6 säger bara att rörelsen är
    /// "tydligt låg när armen var still"; något mätt tal finns inte, och
    /// ingen riktig data har lästs för det här (dataregeln).
    public static let stillMovement = 0.02

    /// METOD M25. Minsta andel av inspelningens minuter som ska ha K18.
    /// **Antagande:** hälften; BESLUT B26 kallar "under hälften av natten" för
    /// dålig täckning.
    public static let minCoverage = 0.5

    /// METOD M25. Minsta antal stilla minuter bakom medianen (en halv timme).
    /// **Antagande:** en median av några få minuter säger inget om natten.
    public static let minStillMinutes = 30

    public struct Night: Equatable, Sendable {
        /// Nattens hudtemperatur i °C; `nil` under minsta täckning eller med
        /// för få stilla minuter.
        public var celsius: Double?
        /// K18-minuter av inspelningens minuter (METOD M24); `nil` för ett
        /// tomt intervall.
        public var coverage: Double?
        /// Antal minuter som medianen togs över: stilla minuter inom
        /// inspelningen (`.recording`) eller sömnminuter (`.sleepPeriod`).
        public var stillMinutes: Int
        /// Vilket underlag natten har (METOD M25).
        public var basis: Basis = .recording
    }

    /// METOD M25. Vad medianen togs över.
    public enum Basis: Equatable, Sendable {
        /// Inspelningens stilla minuter (före R4, och reserv).
        case recording
        /// Sömnperiodens sömnminuter (METOD M26).
        case sleepPeriod
    }

    /// METOD M25. Nattens hudtemperatur för inspelningen `from`…`to`. Bara
    /// minuter inom inspelningen räknas; K18 från före eller efter är med i
    /// serien men inte här.
    public static func night(_ series: K18Series, from: Date, to: Date) -> Night {
        guard let range = K18Series.minuteRange(from: from, to: to),
              let coverage = series.coverage(from: from, to: to) else {
            return Night(celsius: nil, coverage: nil, stillMinutes: 0)
        }
        let still = series.minutes.filter { m in
            range.contains(m.minute) && (m.movement.map { $0 < stillMovement } ?? false)
        }
        let enough = coverage.fraction >= minCoverage && still.count >= minStillMinutes
        return Night(celsius: enough ? K18Series.median(still.map(\.skinTemperature)) : nil,
                     coverage: coverage.fraction,
                     stillMinutes: still.count)
    }

    /// METOD M25 · METOD M26. Nattens hudtemperatur över sömnperiodens
    /// **sömnminuter** i stället för de stilla: `asleepMinutes` är Unix-minuter
    /// som sömnmetoden räknat som sömn, och `from`…`to` är perioden (insomning
    /// till uppvaknande). Stillhetströskeln gäller inte här, för sömnmetoden
    /// har redan avgjort vilka minuter som är stilla. Täckningen räknas över
    /// perioden, och minsta täckning och minsta antal minuter är som förut.
    public static func night(_ series: K18Series, asleepMinutes: [Int],
                             from: Date, to: Date) -> Night {
        guard let range = K18Series.minuteRange(from: from, to: to),
              let coverage = series.coverage(from: from, to: to) else {
            return Night(celsius: nil, coverage: nil, stillMinutes: 0, basis: .sleepPeriod)
        }
        let asleep = Set(asleepMinutes)
        let used = series.minutes.filter { range.contains($0.minute) && asleep.contains($0.minute) }
        let enough = coverage.fraction >= minCoverage && used.count >= minStillMinutes
        return Night(celsius: enough ? K18Series.median(used.map(\.skinTemperature)) : nil,
                     coverage: coverage.fraction,
                     stillMinutes: used.count,
                     basis: .sleepPeriod)
    }
}
