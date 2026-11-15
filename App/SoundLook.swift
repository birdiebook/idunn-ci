import SwiftUI
import Night
import Sound

/// BESLUT B54
/// Hur ljudets klasser ser ut: en symbol per klass, och för snarkning en färg per ägare. Symbolen och färgen
/// bär betydelsen; orden finns för VoiceOver och för teckenförklaringen under diagrammet. Klasserna är
/// index i `SoundClass` (IdunnKit), ägarna `NightSound.Owner`.
enum SoundLook {
    static func symbol(_ c: Int) -> String {
        switch SoundClass(rawValue: c) ?? .other {
        case .snoring: return "zzz"
        case .breathing: return "lungs"
        case .speech: return "bubble.left.fill"
        case .cough: return "mouth"
        case .child: return "face.smiling"
        case .traffic: return "car.fill"
        case .alarm: return "bell.fill"
        case .door: return "door.left.hand.closed"
        case .animal: return "pawprint.fill"
        case .weather: return "cloud.rain.fill"
        case .music: return "music.note"
        case .other: return "waveform"
        }
    }

    static func word(_ c: Int) -> String {
        (SoundClass(rawValue: c) ?? .other).label
    }

    /// Ägarens färg i diagrammet: din i Idunns blå, någon annans i grönblått, okänd grå.
    static func ownerColor(_ o: NightSound.Owner?) -> Color {
        switch o {
        case .some(.yours): return TrendColor.idun
        case .some(.someoneElse): return Color.adaptive(light: 0x1B8F83, dark: 0x3CC4B3)
        default: return Color.secondary.opacity(0.7)
        }
    }

    static func ownerSymbol(_ o: NightSound.Owner?) -> String {
        switch o {
        case .some(.yours): return "person.fill"
        case .some(.someoneElse): return "person.2.fill"
        default: return "questionmark"
        }
    }

    static func ownerWord(_ o: NightSound.Owner?) -> String {
        switch o {
        case .some(.yours): return "din"
        case .some(.someoneElse): return "annans"
        default: return "okänd"
        }
    }

    /// Klockslaget för ett ögonblick (bandets klocka, Unix-sekunder).
    static func clock(_ t: TimeInterval) -> String {
        Date(timeIntervalSince1970: t).formatted(.dateTime.hour().minute())
    }
}

/// En händelse som en symbol: klassens symbol, på en gul skiva när den väckte och med en gul kant när pulsen
/// steg. Snarkningens symbol har ägarens färg. `playing` byter symbolen mot en högtalare.
struct SoundGlyph: View {
    let soundClass: Int
    var owner: NightSound.Owner? = nil
    var woke = false
    var pulse = false
    var playing = false
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: playing ? "speaker.wave.2.fill" : SoundLook.symbol(soundClass))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .padding(4)
            .background(Circle().fill(woke ? TrendColor.warning : TrendColor.surface))
            .overlay(Circle().strokeBorder(pulse && !woke ? TrendColor.warning : Color.clear, lineWidth: 1.5))
    }

    private var tint: Color {
        if woke { return Color.black }
        if soundClass == NightSound.snoringClass { return SoundLook.ownerColor(owner) }
        return Color.primary.opacity(0.85)
    }
}
