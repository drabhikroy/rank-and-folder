import AppKit
import FinderSync

/// Holds the extension weakly so a registered callback does not keep it alive.
private final class WeakFinderSyncReference: @unchecked Sendable {
    weak var value: FinderSyncExtension?

    init(_ value: FinderSyncExtension) {
        self.value = value
    }
}

/// The optional Finder menu item. It reads the saved layouts and queues a
/// request for the app to act on. The extension never drives Finder itself.
final class FinderSyncExtension: FIFinderSync {
    private let repository = UserDefaultsProfileRepository()
    private let requestQueue = ApplyRequestQueue()
    private var profilesObserver: DarwinNotificationObserver?
    private var lastMenuTargetURL: URL?

    override init() {
        super.init()
        configureMonitoredDirectories()
        let weakSelf = WeakFinderSyncReference(self)
        profilesObserver = DarwinNotificationObserver(
            name: SharedConfiguration.profilesChangedNotification
        ) {
            DispatchQueue.main.async {
                weakSelf.value?.configureMonitoredDirectories()
            }
        }
    }

    override func beginObservingDirectory(at url: URL) {
        // Finder Sync reports the open Finder folder. Queue that
        // exact target unchanged; the containing app performs the authoritative
        // bookmark, boundary, volume, and provider-domain resolution.
        requestApply(for: url)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let controller = FIFinderSyncController.default()
        lastMenuTargetURL = controller.targetedURL()

        let menu = NSMenu(title: "Rank & Folder")
        let applyItem = NSMenuItem(
            title: "Apply Rank & Folder Settings",
            action: #selector(applyCurrentFolder),
            keyEquivalent: ""
        )
        applyItem.target = self
        menu.addItem(applyItem)

        let openItem = NSMenuItem(
            title: "Open Rank & Folder…",
            action: #selector(openContainingApp),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        return menu
    }

    override var toolbarItemName: String { "Rank & Folder" }

    override var toolbarItemToolTip: String {
        "Apply or edit folder-specific view settings"
    }

    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Rank & Folder")
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    @objc private func applyCurrentFolder() {
        guard let target = lastMenuTargetURL else { return }
        requestApply(for: directoryURL(for: target))
    }

    @objc private func openContainingApp() {
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Rank & Folder.app
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    private func requestApply(for folderURL: URL) {
        requestQueue.enqueue(folderURL: folderURL)
        DarwinNotification.post(SharedConfiguration.applyRequestNotification)
    }

    private func configureMonitoredDirectories() {
        let urls = (try? repository.load())?
            .filter { $0.isEnabled && $0.finderRepresentation != nil }
            .map(\.folderURL) ?? []
        FIFinderSyncController.default().directoryURLs = Set(urls)
    }

    private func directoryURL(for target: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return target
        }
        return target.deletingLastPathComponent()
    }
}
