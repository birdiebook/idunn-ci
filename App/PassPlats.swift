import CoreLocation
import Foundation
import Pass

/// BESLUT B107 · BESLUT B110 · METOD M65
/// Telefonens plats under ett pass ute. Äger en `CLLocationManager`, ber om tillstånd "när appen används"
/// första gången, och lämnar varje position som en `TrackPoint` på huvudkön. Den bestämmer ingenting om passet:
/// `PassController` slår på platsen bara i fasen running i ett pass ute och stänger av den vid stopp och klar.
/// Platsen stannar på telefonen; den lämnar den bara i exporten med spår (BESLUT B107).
final class PassPlats: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// Vill passet ha platsen just nu? Sätts av `start` och `stop`.
    private var vill = false

    /// Varje ny position, på huvudkön.
    var onPoint: ((TrackPoint) -> Void)?
    /// Tillståndet är nekat eller begränsat (frågan nekades, eller platsen är av i Inställningar), på huvudkön.
    var onDenied: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Nekat av användaren eller av en begränsning på telefonen.
    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Slå på platsen. Första gången kommer frågan om tillstånd; uppdateringarna startar när svaret är ja.
    func start() {
        vill = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            begin()
        case .denied, .restricted:
            onDenied?()
        @unknown default:
            onDenied?()
        }
    }

    /// Stäng av platsen.
    func stop() {
        vill = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    private func begin() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        // Kräver `location` i UIBackgroundModes (project.yml); platsen går då vidare med skärmen låst.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    /// En position som en spårpunkt. Farten tas bara när telefonen gav en (negativ = okänd), och höjden bara
    /// när den vertikala noggrannheten är giltig.
    static func point(_ l: CLLocation) -> TrackPoint {
        TrackPoint(t: l.timestamp, lat: l.coordinate.latitude, lon: l.coordinate.longitude,
                   speed: l.speed >= 0 ? l.speed : nil,
                   altitude: l.verticalAccuracy > 0 ? l.altitude : nil,
                   accuracy: l.horizontalAccuracy)
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard vill else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            begin()
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in self?.onDenied?() }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let punkter: [TrackPoint] = locations.map { (l: CLLocation) -> TrackPoint in Self.point(l) }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.vill else { return }
            for p in punkter { self.onPoint?(p) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ett tillfälligt fel (ingen position just nu) låter uppdateringarna gå vidare; nekat fångas ovan.
    }
}
