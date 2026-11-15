import AVFoundation
import Foundation
import SwiftUI
import Night
import Sound

/// BESLUT B54
/// Klippen ligger i `ljudklipp/<stam>/<sekund>.m4a` (METOD M38) och raderas efter 14
/// dagar; ett klipp som saknas är en händelse utan ljud, inget fel.
enum SoundClips {
    static func url(_ clip: NightSound.Clip) -> URL {
        SoundListener.defaultRoot
            .appendingPathComponent("ljudklipp", isDirectory: true)
            .appendingPathComponent(clip.stem, isDirectory: true)
            .appendingPathComponent(clip.fileName)
    }

    static func exists(_ clip: NightSound.Clip) -> Bool {
        FileManager.default.fileExists(atPath: url(clip).path)
    }
}

/// Vyerna frågar om ett klipp finns genom miljön, så att förhandsvisningen (IdunnProv) kan rita knapparna
/// utan filer. Förvalet är filsystemet.
private struct ClipExistsKey: EnvironmentKey {
    static let defaultValue: (NightSound.Clip) -> Bool = { (c: NightSound.Clip) -> Bool in SoundClips.exists(c) }
}

extension EnvironmentValues {
    var clipExists: (NightSound.Clip) -> Bool {
        get { self[ClipExistsKey.self] }
        set { self[ClipExistsKey.self] = newValue }
    }
}

/// BESLUT B54
/// Spelar ett klipp åt gången (`AVAudioPlayer`). Sessionen får inte störa en pågående
/// lyssning: lyssnaren äger ljudsessionen medan den går (`.playAndRecord`, läget
/// `.measurement`, METOD M38), och då rörs sessionen inte alls — klippet spelas på den som är.
/// Går ingen lyssning sätts sessionen till `.playback` och släpps när klippet är slut
/// (`.notifyOthersOnDeactivation`, så att en podcast fortsätter).
@MainActor
final class ClipPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = ClipPlayer()

    /// Nyckeln (`NightSound.Clip.key`) för klippet som spelas.
    @Published private(set) var playing: String?
    private var player: AVAudioPlayer?
    private var ownsSession = false

    /// Spelar klippet, eller stoppar det om det redan spelas.
    func toggle(_ clip: NightSound.Clip) {
        if playing == clip.key {
            stop()
            return
        }
        stop()
        guard SoundClips.exists(clip) else { return }
        do {
            if !SoundListener.shared.status.listening {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                ownsSession = true
            }
            let p = try AVAudioPlayer(contentsOf: SoundClips.url(clip))
            p.delegate = self
            guard p.play() else {
                stop()
                return
            }
            player = p
            playing = clip.key
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
        if ownsSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsSession = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

/// METOD M46 · BESLUT B56
/// Facit för klassningen, sparat på telefonen i en egen fil bredvid ljudmapparna: klippen raderas
/// efter 14 dagar men omdömena ska överleva dem. Räkningen och formatet ligger i IdunnKit (`SoundFacit`).
@MainActor
final class SoundFacitStore: ObservableObject {
    static let shared = SoundFacitStore()

    @Published private(set) var facit: SoundFacit
    private let url: URL

    init(url: URL = SoundListener.defaultRoot.appendingPathComponent("ljudfacit.json")) {
        self.url = url
        facit = (try? Data(contentsOf: url)).map { (d: Data) -> SoundFacit in SoundFacit.decode(d) } ?? SoundFacit()
    }

    /// Rätt eller fel på klassen. Samma knapp en gång till tar bort omdömet.
    func rateClass(_ e: NightSound.Event, right: Bool) {
        var f: SoundFacit = facit
        let nu: Int = Int(Date().timeIntervalSince1970)
        let förut: Bool? = f.entry(for: e.clip)?.classRight
        f.rateClass(e.clip, soundClass: e.soundClass, owner: e.owner, right: förut == right ? nil : right, at: nu)
        save(f)
    }

    /// Rätt eller fel på ägaren (din eller annans). Samma knapp en gång till tar bort omdömet.
    func rateOwner(_ e: NightSound.Event, right: Bool) {
        var f: SoundFacit = facit
        let nu: Int = Int(Date().timeIntervalSince1970)
        let förut: Bool? = f.entry(for: e.clip)?.ownerRight
        f.rateOwner(e.clip, soundClass: e.soundClass, owner: e.owner, right: förut == right ? nil : right, at: nu)
        save(f)
    }

    private func save(_ f: SoundFacit) {
        facit = f
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        NightFiles.write(f.encode(), to: url)
    }
}
