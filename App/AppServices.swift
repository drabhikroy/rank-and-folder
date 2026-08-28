import Foundation
import Combine

@MainActor
/// The single instance of each long-lived object, built once at launch so every
/// window works against the same store and the same coordinator.
final class AppServices {
    static let shared = AppServices()

    let profileStore: ProfileStore
    let automation: AutomationCoordinator
    private(set) var finderMonitor: FinderFolderMonitor!

    private init() {
        let defaults = SharedConfiguration.includesFinderExtension
            ? UserDefaults.rankFolderShared
            : UserDefaults.standard
        let repository = UserDefaultsProfileRepository(defaults: defaults)
        let boundaryRepository = UserDefaultsBoundaryRepository(defaults: defaults)
        let requestQueue = ApplyRequestQueue(defaults: defaults)

        let store = ProfileStore(
            repository: repository,
            boundaryRepository: boundaryRepository
        )
        self.profileStore = store
        self.automation = AutomationCoordinator(
            profileStore: store,
            requestQueue: requestQueue
        )
        self.finderMonitor = FinderFolderMonitor(
            profileStore: store,
            automation: automation
        )
    }
}

/// Carries the small amount of context needed by separately movable utility
/// windows. The folder data still belongs to ProfileStore; this object only
/// records what the user asked the next window to show.
@MainActor
final class SecondaryWindowStore: ObservableObject {
    static let shared = SecondaryWindowStore()

    @Published var organizedLayout: ResolvedFolderLayout?
    @Published var modelProfileID: UUID?
    @Published var requestedPreviewProfileID: UUID?

    private init() {}
}

/// The two notifications a secondary window sends to ask the main window to
/// change what it is showing.
extension Notification.Name {
    static let rankFolderSelectProfile = Notification.Name("RankFolderSelectProfile")
    static let rankFolderShowPreview = Notification.Name("RankFolderShowPreview")
}
