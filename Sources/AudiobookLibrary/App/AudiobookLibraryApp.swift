import SwiftUI

@main
struct AudiobookLibraryApp: App {
    var body: some Scene {
        WindowGroup("Audio Shelf") {
            RootView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_120, height: 720)

        Settings {
            SettingsView()
        }
    }
}
