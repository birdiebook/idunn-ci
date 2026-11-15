import Foundation
import WhoopFrames

/// METOD M29 · BESLUT B38 · BESLUT B28 · BESLUT B52
/// När lyssnaren ska säga till på Morgon: bara när något är fel, och med vad
/// användaren kan göra. Allt annat om lyssnaren (läget, tiderna, täckningen) bor
/// på Data. Räknas ur `ListenerStatus` (tider och minuter, aldrig ett värde,
/// B3), nattens egen täckning, om nattens kurva går att räkna fram och
/// Bluetooths läge; appen skriver texten.
public enum ListenerAlert: Equatable, Sendable {
    /// Appen får inte använda Bluetooth (Inställningar).
    case bluetoothNotAllowed
    /// Bluetooth är av.
    case bluetoothOff
    /// Inget K18 har hörts alls sedan lyssnaren började.
    case neverHeard
    /// Inget K18 har hörts sedan `since`: fönstret slutar mer än `silenceHours` senare.
    case silent(since: Date)
    /// Natten fick bara `fraction` (0…1) av sina minuter med K18.
    case lowCoverage(fraction: Double)
    /// BESLUT B52. Morgons natt kommer ur K18 men saknar lager (rörelse och temperatur på kurvans
    /// tidsaxel): filerna den bygger på går inte att räkna om (`NightChoice.lacksLayers`).
    case missingLayers
}

public enum ListenerCheck {

    /// Hur Bluetooth mår, så som appen ser det.
    public enum Bluetooth: Equatable, Sendable {
        case ok
        case off
        case notAllowed
    }

    /// METOD M29. Tystnad längre än så här (timmar) fram till nattfönstrets
    /// slut är ett fel. **Antagande**: Whoop-appen synkar oftast vid
    /// uppvaknandet, och en natt som hörs hela vägen ger då en tystnad på några
    /// timmar fram till klockan 12; åtta timmar fångar en lyssnare som dog på
    /// kvällen eller natten. Inte mätt: A1:s första natter kalibrerar det.
    public static let silenceHours: Double = 8

    /// METOD M29. Under så här stor andel av sömnperiodens minuter med K18 är
    /// täckningen låg. **Antagande**: samma gräns som lyssnaren hade för den
    /// orange täckningen (B28), och som hudtemperaturen kräver (M25).
    public static let minCoverage: Double = 0.5

    /// METOD M29. Tystnad bedöms först när fönstret pågått så här många
    /// timmar (kvällen 18 till 04), så att ingen larmar vid midnatt innan
    /// natten börjat synkas. **Antagande**.
    public static let minWindowHours: Double = 10

    /// Det som är fel just nu, det viktigaste först, eller `nil` när allt är bra.
    ///
    /// - Parameters:
    ///   - nightCoverage: K18-täckningen över sömnperioden för natten som slutar
    ///     fönstrets dag (`NightDigest.coverage`), eller `nil` om den natten
    ///     saknas eller inte räknats.
    ///   - heard: `false` så länge lyssnarens dygnsfiler inte kunnat läsas (en
    ///     låst telefon efter omstart): då vet statusen ingenting och
    ///     tystnad räknas inte.
    ///   - nightLacksLayers: BESLUT B52. Natten Morgon visar är en natt ur K18 utan lager
    ///     (`NightChoice.lacksLayers`). Sägs sist: Bluetooth, tystnad och låg täckning går före,
    ///     eftersom de säger vad användaren kan göra. Sägs också när tystnaden inte kan bedömas.
    public static func alert(status: ListenerStatus, nightCoverage: Double?, bluetooth: Bluetooth,
                             statusRead: Bool = true, nightLacksLayers: Bool = false, now: Date,
                             utcOffsetSeconds: Int) -> ListenerAlert? {
        switch bluetooth {
        case .notAllowed: return .bluetoothNotAllowed
        case .off: return .bluetoothOff
        case .ok: break
        }
        let lager: ListenerAlert? = nightLacksLayers ? ListenerAlert.missingLayers : nil
        guard statusRead else { return lager }
        guard let heard = status.lastK18Heard else { return .neverHeard }
        // BESLUT B50. Natten som slutar idag, hela dygnet. Inte `latest`, som från kl 18 byter till natten
        // som börjar: Morgon bedömer lyssnaren mot natten kortet visar, och den ändras inte på kvällen.
        let w = NightWindow.endingToday(now: now, utcOffsetSeconds: utcOffsetSeconds)
        guard w.until.timeIntervalSince(w.start) >= minWindowHours * 3600 else { return lager }
        // Tystnaden mäts fram till fönstrets slut (eller nu, om natten pågår),
        // så att den inte växer under eftermiddagen efter en bra natt.
        if w.until.timeIntervalSince(heard) > silenceHours * 3600 {
            return .silent(since: heard)
        }
        if let c = nightCoverage, c < minCoverage { return .lowCoverage(fraction: c) }
        return lager
    }
}
