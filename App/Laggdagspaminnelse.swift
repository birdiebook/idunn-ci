import Foundation
import Combine
import UserNotifications
import SleepNeed

/// BESLUT B103 · METOD M53
/// Påminnelsen före läggdags: en notis på telefonen 15 minuter före kvällens läggdags (läggdags för bästa förväntade
/// sömnpoäng, samma tid som kortet Ikväll visar). Notisen är lokal: telefonen lägger den själv, och inget skickas
/// någonstans. Tiderna räknas av `SleepNeed.reminders` (kvällens och tre nätter i reserv); här läggs de hos systemet
/// och byts ut varje gång planen räknas om (en ny natt, ett ändrat schema). Av eller på är en inställning i
/// UserDefaults, och första gången den slås på frågar telefonen om lov att visa notiser.
final class Läggdagspåminnelse: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Läggdagspåminnelse()

    /// Påminnelsen är påslagen.
    @Published private(set) var på: Bool
    /// Notiser är nekade för appen i telefonens inställningar: reglaget går inte att slå på härifrån.
    @Published private(set) var nekad: Bool = false

    private static let nyckel = "läggdagspåminnelse"
    /// Notisernas namn hos systemet börjar så, följt av uppvakningsdagens nummer.
    private static let förled = "laggdags-"

    /// Planens påminnelser, senast räknade.
    private var planerade: [BedtimeReminder] = []
    /// Inte i provet (IdunnProv körs inuti appen): där läggs inga notiser och ställs inga frågor.
    private let iProv: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private override init() {
        på = UserDefaults.standard.bool(forKey: Self.nyckel)
        super.init()
        guard !iProv else { return }
        UNUserNotificationCenter.current().delegate = self
        // Lovet kan ha tagits tillbaka i telefonens inställningar sedan sist.
        UNUserNotificationCenter.current().getNotificationSettings { (läge: UNNotificationSettings) -> Void in
            let nej: Bool = läge.authorizationStatus == .denied
            DispatchQueue.main.async { self.nekad = nej }
        }
    }

    /// Reglaget i bladet Upp i morgon. Att slå på frågar om lov första gången; ett nej lämnar påminnelsen av.
    func sätt(på ny: Bool) {
        guard !iProv else { return }
        guard ny else {
            spara(false)
            lägg()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { (ja: Bool, _: Error?) -> Void in
            DispatchQueue.main.async {
                self.nekad = !ja
                self.spara(ja)
                self.lägg()
            }
        }
    }

    /// Planen är räknad om (`SömnbehovModell`): de nya tiderna ersätter de gamla.
    func sätt(påminnelser: [BedtimeReminder]) {
        guard !iProv else { return }
        planerade = påminnelser
        lägg()
    }

    private func spara(_ ny: Bool) {
        på = ny
        UserDefaults.standard.set(ny, forKey: Self.nyckel)
    }

    /// Tar bort appens väntande påminnelser och lägger planens, när påminnelsen är på.
    private func lägg() {
        let nya: [UNNotificationRequest] = på ? planerade.map { (p: BedtimeReminder) -> UNNotificationRequest in
            Self.notis(p)
        } : []
        let central = UNUserNotificationCenter.current()
        central.getPendingNotificationRequests { (väntar: [UNNotificationRequest]) -> Void in
            let gamla: [String] = väntar.map { (r: UNNotificationRequest) -> String in r.identifier }
                .filter { (id: String) -> Bool in id.hasPrefix(Self.förled) }
            central.removePendingNotificationRequests(withIdentifiers: gamla)
            for n in nya { central.add(n, withCompletionHandler: nil) }
        }
    }

    /// Notisen för en natt: "Läggdags 22:48" på väggklockans tid för påminnelsen, en gång.
    static func notis(_ p: BedtimeReminder) -> UNNotificationRequest {
        let innehåll = UNMutableNotificationContent()
        innehåll.title = "Läggdags " + Fmt.clock(minutes: p.bedtimeMinute)
        innehåll.body = "Dags att göra dig i ordning för natten."
        innehåll.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: klockslag(p), repeats: false)
        return UNNotificationRequest(identifier: förled + String(p.wakeDay), content: innehåll, trigger: trigger)
    }

    /// Dagen och klockslaget för påminnelsen som år, månad, dag, timme och minut. Dagnumret räknas om till datum i
    /// UTC (dagnumret är redan väggklockans dag), och systemet tolkar delarna i telefonens zon.
    static func klockslag(_ p: BedtimeReminder) -> DateComponents {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let tid: (day: Int, minuteOfDay: Int) = p.fire
        let datum = Date(timeIntervalSince1970: Double(tid.day) * 86_400)
        var delar: DateComponents = utc.dateComponents([.year, .month, .day], from: datum)
        delar.hour = tid.minuteOfDay / 60
        delar.minute = tid.minuteOfDay % 60
        return delar
    }

    /// Notisen visas också när appen är öppen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
