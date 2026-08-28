import AppKit

@MainActor
/// Handles the parts of the application lifecycle SwiftUI does not cover, in
/// particular listening for apply requests sent by the Finder extension.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var applyObserver: DarwinNotificationObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyObserver = DarwinNotificationObserver(
            name: SharedConfiguration.applyRequestNotification
        ) {
            DispatchQueue.main.async {
                AppServices.shared.automation.processPendingRequests()
            }
        }
        AppServices.shared.automation.processPendingRequests()
        AppServices.shared.finderMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.finderMonitor.stop()
        ManagedOllamaRuntime.shared.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppServices.shared.automation.refreshSetupStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            let mainWindow = sender.windows.first { $0.title == "Rank & Folder" }
                ?? sender.keyWindow
                ?? sender.windows.first
            mainWindow?.makeKeyAndOrderFront(nil)
        }
        return true
    }

}
