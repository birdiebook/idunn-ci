import SwiftUI
import Night
import Sound

/// METOD M44 · METOD M46 · BESLUT B54 · BESLUT B56
/// Nattens rapport över ljudet, under kurvan: händelserna som följdes av ett uppvaknande eller en pulsreaktion
/// (klockslag, symbol, uppspelning), och alla klipp som finns kvar, där användaren trycker rätt eller fel på
/// klassen (för en snarkning också på om "din" eller "annans" stämmer). Omdömena sparas på telefonen
/// (`SoundFacitStore`) och räknas på Data. Klippen raderas efter 14 dagar; en händelse utan klipp har ingen
/// uppspelning och inga knappar.
struct SoundReport: View {
    let sound: NightSound
    /// Klippen visas från början (förhandsvisningen); annars bakom en rad.
    var clipsOpen = false
    @State private var open: Bool
    @Environment(\.clipExists) private var clipExists

    init(sound: NightSound, clipsOpen: Bool = false) {
        self.sound = sound
        self.clipsOpen = clipsOpen
        _open = State(initialValue: clipsOpen)
    }

    private var clips: [NightSound.Event] {
        sound.events.filter { (e: NightSound.Event) -> Bool in clipExists(e.clip) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !sound.followed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Efter ljudet", systemImage: "ear")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(sound.followed) { (e: NightSound.Event) in
                        SoundFollowRow(event: e)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if !clips.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        open.toggle()
                    } label: {
                        HStack {
                            Label("Klipp", systemImage: "waveform")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(clips.count)").monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: open ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open {
                        ForEach(clips) { (e: NightSound.Event) in
                            Divider()
                            SoundClipRow(event: e)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// En händelse som följdes av något: symbolen, klockslaget och nivån, vad som följde (uppvaknande, puls) och
/// uppspelningen.
struct SoundFollowRow: View {
    let event: NightSound.Event
    @Environment(\.clipExists) private var clipExists
    @ObservedObject private var spelare = ClipPlayer.shared

    var body: some View {
        HStack(spacing: 10) {
            SoundGlyph(soundClass: event.soundClass, owner: event.owner, woke: event.woke, pulse: event.pulse,
                       playing: spelare.playing == event.clip.key)
            Text(SoundLook.clock(event.time)).font(.headline).monospacedDigit()
            if let d = event.aboveFloor {
                Text("+\(Int(d.rounded())) dB").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            if event.woke {
                Image(systemName: "eye").foregroundStyle(TrendColor.warning).accessibilityLabel("Vaken")
            }
            if event.pulse {
                Image(systemName: "heart.fill").foregroundStyle(TrendColor.warning).accessibilityLabel("Pulsen steg")
            }
            if clipExists(event.clip) {
                PlayButton(clip: event.clip)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Spela eller stoppa ett klipp.
struct PlayButton: View {
    let clip: NightSound.Clip
    @ObservedObject private var spelare = ClipPlayer.shared

    var body: some View {
        let spelas: Bool = spelare.playing == clip.key
        Button {
            spelare.toggle(clip)
        } label: {
            Image(systemName: spelas ? "stop.circle.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(TrendColor.idun)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spelas ? "Stoppa klippet" : "Spela klippet")
    }
}

/// Ett klipp med uppspelning och facit: rätt eller fel på klassen, och för en snarkning med ägare (din eller
/// annans) en rad till för ägaren.
struct SoundClipRow: View {
    let event: NightSound.Event
    @ObservedObject private var facit = SoundFacitStore.shared

    private var omdöme: SoundFacit.Entry? { facit.facit.entry(for: event.clip) }
    private var frågaOmÄgare: Bool {
        event.isSnoring && (event.owner == .yours || event.owner == .someoneElse)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PlayButton(clip: event.clip)
                SoundGlyph(soundClass: event.soundClass, owner: event.owner, woke: event.woke, pulse: event.pulse)
                Text(SoundLook.clock(event.time)).font(.subheadline).monospacedDigit()
                Spacer(minLength: 4)
                RatingButtons(right: omdöme?.classRight, what: "klassen " + SoundLook.word(event.soundClass)) {
                    facit.rateClass(event, right: $0)
                }
            }
            if frågaOmÄgare {
                HStack(spacing: 10) {
                    Image(systemName: SoundLook.ownerSymbol(event.owner))
                        .foregroundStyle(SoundLook.ownerColor(event.owner))
                        .frame(width: 28)
                    Text(SoundLook.ownerWord(event.owner)).font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    RatingButtons(right: omdöme?.ownerRight, what: "ägaren " + SoundLook.ownerWord(event.owner)) {
                        facit.rateOwner(event, right: $0)
                    }
                }
            }
        }
    }
}

/// Två knappar, rätt och fel. Den valda är fylld; samma knapp en gång till tar bort omdömet (görs av butiken).
struct RatingButtons: View {
    let right: Bool?
    let what: String
    let choose: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button { choose(true) } label: {
                Image(systemName: right == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(right == true ? TrendColor.good : Color.secondary)
            }
            .accessibilityLabel("Stämmer: " + what)
            Button { choose(false) } label: {
                Image(systemName: right == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundStyle(right == false ? TrendColor.warning : Color.secondary)
            }
            .accessibilityLabel("Stämmer inte: " + what)
        }
        .buttonStyle(.plain)
        .font(.title3)
    }
}
