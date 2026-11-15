import SwiftUI

@main
struct IdunnApp: App {
    @StateObject private var store = Store()
    @StateObject private var recorder = Recorder.shared

    init() {
        // Inspelningen skapas vid start, före första vyn: när iOS väcker appen i
        // bakgrunden för bandet (state restoration) måste centralen finnas direkt.
        _ = Recorder.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(recorder)
                // BESLUT B63. Hela appen är mörk, med skissens färger (App/Tema.swift).
                .preferredColorScheme(.dark)
                .tint(Tema.accent)
        }
    }
}
