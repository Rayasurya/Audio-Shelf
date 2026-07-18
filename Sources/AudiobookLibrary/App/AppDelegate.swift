import AppKit
import UserNotifications

// Quit protection (D12) and notification-click handling (D13). The store is
// attached by RootView once the SwiftUI scene exists.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static weak var store: AppStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The notification center API requires a real bundle; `swift run`
        // has none, so guard to keep dev runs alive.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store = Self.store, store.state.activeJob != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A book is being narrated"
        alert.informativeText = "Stop narration and quit? Finished chapters are kept, and you can resume exactly where it left off next time."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Keep Narrating")
        if alert.runModal() == .alertFirstButtonReturn {
            store.stopGenerationForQuit()
            return .terminateNow
        }
        return .terminateCancel
    }

    // Clicking "Ready to listen" opens the finished book's player.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        if let bookID = UUID(uuidString: identifier) {
            Task { @MainActor in
                Self.store?.openPlayer(bookID: bookID)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        completionHandler()
    }
}
