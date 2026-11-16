import SwiftUI

@main
struct IdunnApp: App {
    @StateObject private var store = Store()
    @StateObject private var recorder = Recorder.shared

    init() {
        // Inspelningen skapas vid start, före första vyn: när iOS väcker appen i
        // bakgrunden för bandet (state restoration) måste centralen finnas direkt.
        // BESLUT B123. Påminnelsen om att ladda bandet lyssnar på batteriet från start, också i bakgrunden.
        Batteripåminnelse.shared.starta(recorder: Recorder.shared)
        // BESLUT B127. Coachen: skickar sammanfattningarna av sig själv när telefonen är kopplad (App/Coach.swift).
        CoachModell.shared.starta()
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
