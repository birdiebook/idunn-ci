import Foundation
import Combine
import UIKit
import UserNotifications
import Band

/// BESLUT B123 · METOD M70
/// Påminnelsen om att ladda bandet: en lokal notis när batteriet går under 20, 10 och 5 %, en gång per gräns och
/// urladdning (räkningen är `BandBattery.step`). Notisen läggs av telefonen själv (som Läggdagspåminnelse, B103), och
/// ingenting skickas någonstans. Nivån läses över Bluetooth, så en påminnelse kan bara komma när telefonen hör bandet;
/// batteriets procent väcker appen i bakgrunden ungefär var 20–30 minut (se `Recorder.received(battery:)`).
/// Tillståndet (lägsta gräns som redan påmint) ligger i UserDefaults så att en omstart inte ger samma påminnelse igen.
/// Ingen inställning: den stängs av i telefonens notisinställningar. Lovet frågas en gång, när appen är i förgrunden.
final class Batteripåminnelse {
    static let shared = Batteripåminnelse()

    private static let nyckel = "batteripåminnelse.gräns"
    /// Samma namn varje gång: en ny notis ersätter den gamla.
    private static let notisnamn = "bandets-batteri"

    /// Inte i provet (IdunnProv körs inuti appen): där läggs inga notiser och ställs inga frågor.
    private let iProv: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private var prenumerationer: Set<AnyCancellable> = []
    private var started: Bool = false
    private var frågat: Bool = false

    private init() {}

    /// Börjar lyssna på batteriet. Anropas en gång när `Recorder` skapas, så att det också lever när appen väcks i
    /// bakgrunden av bandets batterinotis.
    func starta(recorder: Recorder) {
        guard !iProv, !started else { return }
        started = true
        recorder.$battery
            .compactMap { (nivå: Int?) -> Int? in nivå }
            .sink { [weak self] (nivå: Int) -> Void in
                self?.läst(nivå)
            }
            .store(in: &prenumerationer)
        // Lovet frågas i förgrunden: första gången appen blir aktiv, och aldrig från bakgrunden.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] (_: Notification) -> Void in
                self?.fråga()
            }
            .store(in: &prenumerationer)
    }

    /// Frågar om lov en gång om läget är obestämt och appen är i förgrunden. Nekat eller givet lämnas som det är.
    private func fråga() {
        guard !frågat, UIApplication.shared.applicationState == .active else { return }
        frågat = true
        let central = UNUserNotificationCenter.current()
        central.getNotificationSettings { (läge: UNNotificationSettings) -> Void in
            guard läge.authorizationStatus == .notDetermined else { return }
            central.requestAuthorization(options: [.alert, .sound]) { (_: Bool, _: Error?) -> Void in }
        }
    }

    /// En ny läsning av batteriet: räkna, spara tillståndet och lägg en notis när räkningen säger det.
    private func läst(_ nivå: Int) {
        let förra: Int? = Self.sparad()
        let steg: BandBattery.Step = BandBattery.step(state: förra, level: nivå)
        if steg.state != förra { Self.spara(steg.state) }
        guard steg.reminder != nil else { return }
        lägg(nivå)
    }

    private func lägg(_ nivå: Int) {
        let innehåll = UNMutableNotificationContent()
        innehåll.title = "Ladda bandet"
        innehåll.body = "Bandet har \(nivå) % batteri kvar."
        innehåll.sound = .default
        // Utan trigger visas notisen direkt. Samma identifierare ersätter en tidigare.
        let begäran = UNNotificationRequest(identifier: Self.notisnamn, content: innehåll, trigger: nil)
        UNUserNotificationCenter.current().add(begäran, withCompletionHandler: nil)
    }

    private static func sparad() -> Int? {
        let d = UserDefaults.standard
        guard d.object(forKey: nyckel) != nil else { return nil }
        return d.integer(forKey: nyckel)
    }

    private static func spara(_ gräns: Int?) {
        if let gräns { UserDefaults.standard.set(gräns, forKey: nyckel) }
        else { UserDefaults.standard.removeObject(forKey: nyckel) }
    }
}
