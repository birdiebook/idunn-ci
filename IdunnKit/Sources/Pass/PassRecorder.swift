import Foundation
import HeartRate

/// BESLUT B58 · METOD M47
/// Passets tillståndsmaskin, utan klocka och utan Bluetooth (klockan kommer in
/// som parameter, så att allt går att prova på Linux). Faserna:
///
///     idle ──start──▶ running ──stop──▶ after ──(600 s | finishNow)──▶ done
///
/// `running`: pulsen mäts och passet pågår. `after`: Stopp är tryckt och pulsen
/// mäts vidare i 10 minuter (`PassRules.afterSeconds`) för återhämtningen.
/// `done`: passet är färdigt och ska sparas. Appen slår på pulsen från bandet
/// i `running` och `after` (`wantsPulse`) och av annars.
public struct PassRecorder: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case idle, running, after, done
    }

    public private(set) var phase: Phase = .idle
    /// Passet som pågår eller just blivit färdigt; `nil` i `idle`.
    public private(set) var pass: Pass?

    public init() {}

    /// Ska pulsen från bandet vara på? (Prenumerationen på pulsnotisen.)
    public var wantsPulse: Bool { phase == .running || phase == .after }

    /// Passet när det är färdigt (fasen `done`), annars `nil`.
    public var finished: Pass? { phase == .done ? pass : nil }

    /// Sekunder kvar av efterperioden; `nil` utanför `after`.
    public func afterRemaining(now: Date) -> TimeInterval? {
        guard phase == .after else { return nil }
        return pass?.afterRemaining(now: now)
    }

    /// Start, bara från `idle` eller `done` (ett nytt pass efter ett färdigt).
    /// `outdoor` ger passet ett spår (BESLUT B107), `stepHeightCm` gör det till ett steptest (METOD M62), som
    /// får typen kondition direkt.
    public mutating func start(now: Date, id: UUID = UUID(), outdoor: Bool = false, stepHeightCm: Double? = nil) {
        guard phase == .idle || phase == .done else { return }
        pass = Pass(id: id, start: now, kind: stepHeightCm == nil ? nil : .kondition,
                    track: outdoor ? [] : nil, stepHeightCm: stepHeightCm)
        phase = .running
    }

    /// BESLUT B107 · METOD M63. En position från telefonen. Sparas bara medan passet pågår (inte efter
    /// stopp), bara i ett pass ute, och bara med en giltig noggrannhet.
    public mutating func add(_ point: TrackPoint) {
        guard phase == .running, pass?.track != nil, point.accuracy >= 0 else { return }
        pass?.track?.append(point)
    }

    /// Ett pulsprov. bpm 0 och prov utan sensorkontakt sparas inte. Först
    /// körs `tick`, så att ett prov efter att efterperioden gått ut aldrig
    /// läggs till i ett färdigt pass.
    public mutating func add(_ m: HeartRateMeasurement, now: Date) {
        tick(now: now)
        guard phase == .running || phase == .after, m.bpm > 0, m.sensorContact != .notDetected else { return }
        pass?.samples.append(PassSample(t: now, bpm: m.bpm))
    }

    /// Stopp: efterperioden börjar. Bara från `running`.
    public mutating func stop(now: Date) {
        guard phase == .running else { return }
        pass?.stop = now
        phase = .after
    }

    /// Passets typ, i varje fas där det finns ett pass.
    public mutating func setKind(_ kind: PassKind?) {
        pass?.kind = kind
    }

    /// Avslutar efterperioden tidigt ("Klar"). Bara från `after`.
    public mutating func finishNow(now: Date) {
        guard phase == .after, let s = pass?.stop else { return }
        pass?.afterEnd = max(s, min(now, s.addingTimeInterval(PassRules.afterSeconds)))
        phase = .done
    }

    /// Klockan går. I `after` avslutas efterperioden 600 s efter stopp. I
    /// `running` avslutas ett pass som aldrig stoppats och inte fått prov på 4
    /// timmar vid sista provet (appen dödad mitt i passet).
    public mutating func tick(now: Date) {
        switch phase {
        case .after:
            guard let s = pass?.stop else { return }
            let slut = s.addingTimeInterval(PassRules.afterSeconds)
            guard now >= slut else { return }
            // I rätt tid (timern går) slutar mätningen på sekunden. Hittas passet långt efteråt
            // (appen dödad under efterperioden) slutar den vid sista provet.
            if now.timeIntervalSince(slut) < 30 {
                pass?.afterEnd = slut
            } else {
                let sista = pass?.samples.last?.t ?? s
                pass?.afterEnd = min(slut, max(s, sista))
            }
            phase = .done
        case .running:
            guard let p = pass else { return }
            let sista = p.samples.last?.t ?? p.start
            guard now.timeIntervalSince(sista) >= PassRules.staleSeconds else { return }
            pass?.stop = sista
            pass?.afterEnd = sista
            phase = .done
        case .idle, .done:
            return
        }
    }

    /// Tillbaka till `idle` när ett färdigt pass är sparat.
    public mutating func clear() {
        guard phase == .done || phase == .idle else { return }
        pass = nil
        phase = .idle
    }

    /// Tar upp ett sparat pass igen (appen startad om). Fasen följer av vad som
    /// är satt: inget stopp = `running`, stopp utan slut = `after`, annars
    /// `done`. `tick` tillämpas direkt, så ett gammalt pass avslutas.
    public mutating func restore(_ p: Pass, now: Date) {
        pass = p
        if p.afterEnd != nil {
            phase = .done
        } else if p.stop != nil {
            phase = .after
        } else {
            phase = .running
        }
        tick(now: now)
    }
}
