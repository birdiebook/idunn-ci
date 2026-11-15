import Foundation

/// PLAN.md A3 · METOD M23
/// När Idunn själv hämtar bandets historik, med reglaget "Whoop-appen är borta" på. Av: aldrig. På: när bandet
/// ansluts och tjänsterna är klara, och sedan när en timme gått sedan förra hämtningen slutade, varje gång appen är
/// vaken (en notis från bandet, batteriets procent, förgrunden). Hämtningen själv är `HistorySession`, med samma
/// kvittensregler som knappen; det som inte kvitterats ligger kvar i bandet till nästa gång.
///
/// Regeln är ren: tiderna och lägena in, ett skäl ut eller `nil`. Appen sparar `State` mellan starter, så att en app
/// som dödats mitt i en hämtning försöker igen.
public enum AutoFetch {
    public struct Config: Equatable, Sendable {
        /// **antagande**. En timmes historik hämtades hel på 18 s (PLAN.md A3, mätt 2026-11-11).
        public var interval: TimeInterval = 3600
        /// En återanslutning hämtar bara om förra hämtningen slutade minst så här länge sedan.
        public var afterConnect: TimeInterval = 300
        /// **antagande**. Efter ett stopp (tappat band, tystnad, sparfel) försöker den igen efter så här länge.
        public var retryAfterStop: TimeInterval = 300
        /// **antagande**. Efter ett stopp för att en annan app (Whoop) pratade med bandet: vänta längre, den synkar.
        public var retryAfterOtherApp: TimeInterval = 1800
        /// En hämtning som började men aldrig slutade (appen dödades) räknas som stoppad efter så här länge.
        public var stuckAfter: TimeInterval = 600
        public init() {}
    }

    /// Varför en hämtning startar; står i sidofilens logg.
    public enum Reason: String, Equatable, Sendable {
        case first = "första"
        case connected = "anslutning"
        case interval = "timme"
        case retry = "nytt försök"
    }

    /// Det appen sparar mellan starter: när förra hämtningen började och slutade, och hur.
    public struct State: Codable, Equatable, Sendable {
        public var lastStart: Date?
        public var lastEnd: Date?
        public var lastStopped = false
        public var lastStopWasOtherApp = false
        public init() {}

        /// En hämtning började (knappen eller automatiskt).
        public mutating func started(at t: Date) { lastStart = t }

        /// En hämtning slutade.
        public mutating func ended(at t: Date, _ o: HistorySession.Outcome) {
            lastEnd = t
            switch o {
            case .complete:
                lastStopped = false
                lastStopWasOtherApp = false
            case .stopped(let r):
                lastStopped = true
                if case .otherApp = r { lastStopWasOtherApp = true } else { lastStopWasOtherApp = false }
            }
        }
    }

    /// Ska en hämtning starta nu, och varför? `nil` = nej.
    ///
    /// - `enabled`: reglaget "Whoop-appen är borta".
    /// - `bandReady`: bandet anslutet och historiken och svaren prenumererade.
    /// - `busy`: en hämtning eller ett IMU-prov pågår (BESLUT B53).
    /// - `justConnected`: tjänsterna blev klara just nu, efter en anslutning.
    public static func decide(enabled: Bool, bandReady: Bool, busy: Bool, justConnected: Bool, now: Date,
                              state: State, config: Config = Config()) -> Reason? {
        guard enabled, bandReady, !busy else { return nil }
        // En hämtning som började efter förra slutet och aldrig slutade: appen dödades mitt i.
        if let start = state.lastStart, state.lastEnd.map({ (e: Date) -> Bool in start > e }) ?? true {
            return now.timeIntervalSince(start) >= config.stuckAfter ? .retry : nil
        }
        guard let slut = state.lastEnd else { return .first }
        let sedan: TimeInterval = now.timeIntervalSince(slut)
        if state.lastStopped {
            let vänta: TimeInterval = state.lastStopWasOtherApp ? config.retryAfterOtherApp : config.retryAfterStop
            return sedan >= vänta ? .retry : nil
        }
        if justConnected && sedan >= config.afterConnect { return .connected }
        return sedan >= config.interval ? .interval : nil
    }
}
