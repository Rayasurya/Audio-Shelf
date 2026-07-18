import SwiftUI

@main
struct AudiobookLibraryApp: App {
    @State private var store = AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Audio Shelf") {
            RootView(store: store)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import a Book…") { store.chooseAndImport() }
                    .keyboardShortcut("i", modifiers: .command)
            }
            CommandMenu("Listening") {
                Button(store.isPlaying ? "Pause" : "Play") { store.togglePlayback() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("Focus Mode") { store.isFocusMode = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Back 15 Seconds") { store.seek(to: max(0, store.currentPlaybackSeconds - 15)) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Forward 30 Seconds") { store.seek(to: store.currentPlaybackSeconds + 30) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
