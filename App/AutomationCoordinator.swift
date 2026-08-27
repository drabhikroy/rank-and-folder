import AppKit
import Combine
import FinderSync
import Foundation

enum AutomationStatus: Equatable {
    case ready
    case applying(String)
    case applied(String)
    case needsSetup(String)
    case failed(String)

    var title: String {
        switch self {
        case .ready: "Ready"
        case .applying: "Applying view"
        case .applied: "View applied"
        case .needsSetup: "Finder automation needs attention"
        case .failed: "Could not apply view"
        }
    }

    var message: String {
        switch self {
        case .ready:
            "Rank & Folder is ready."
        case .applying(let message):
            message
        case .applied(let summary), .needsSetup(let summary), .failed(let summary):
            summary
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle"
        case .applying: "arrow.triangle.2.circlepath"
        case .applied: "checkmark.circle.fill"
        case .needsSetup: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    var isVisible: Bool {
        self != .ready
    }
}

/// Owns every path that ends in Rank & Folder operating Finder's view controls.
///
/// Three routes reach the same place. `applyNow` is a person choosing a saved
/// folder, and it opens Finder. `applyObserved` is the background monitor
/// noticing Finder already showing a folder, and it never navigates. Requests
/// from the Finder extension arrive through `processPendingRequests`.
///
/// Every route re-resolves and revalidates immediately before acting, because
/// the person can navigate away during the delay. A generation counter makes a
/// superseded attempt abandon its result instead of applying it late.
@MainActor
final class AutomationCoordinator: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var finderExtensionEnabled = false
    @Published private(set) var hasRequestedAccessibility = false
    @Published private(set) var manualOnlyTargetPaths: Set<String> = []
    @Published private(set) var status: AutomationStatus = .ready

    let includesFinderExtension = SharedConfiguration.includesFinderExtension

    var setupComplete: Bool {
        accessibilityGranted
    }

    var statusMessage: String {
        if status == .ready && !setupComplete {
            return "RankFolder is ready. Optional Finder automation is off."
        }
        return status.message
    }

    var runningAppURL: URL {
        Bundle.main.bundleURL
    }

    var isRunningFromApplications: Bool {
        let appPath = runningAppURL.resolvingSymlinksInPath().standardizedFileURL.path
        let applicationFolders = FileManager.default.urls(
            for: .applicationDirectory,
            in: [.localDomainMask, .userDomainMask]
        )
        return applicationFolders.contains { folder in
            let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
            return appPath.hasPrefix(folderPath + "/")
        }
    }

    private let profileStore: ProfileStore
    private let requestQueue: ApplyRequestQueue
    private let finderClient = FinderAccessibilityClient()
    private let setupStateOverride: (accessibilityGranted: Bool, extensionEnabled: Bool)?
    private var recentManualApply: (path: String, date: Date)?
    private var applyGeneration = 0
    private var pendingRequestTask: Task<Void, Never>?
    private var manualResolutionTask: Task<Void, Never>?

    init(
        profileStore: ProfileStore,
        requestQueue: ApplyRequestQueue,
        setupStateOverride: (accessibilityGranted: Bool, extensionEnabled: Bool)? = nil
    ) {
        self.profileStore = profileStore
        self.requestQueue = requestQueue
        self.setupStateOverride = setupStateOverride
        accessibilityGranted = setupStateOverride?.accessibilityGranted
            ?? AccessibilityPermission.isGranted
        let extensionIsEnabled = setupStateOverride?.extensionEnabled
            ?? FIFinderSyncController.isExtensionEnabled
        finderExtensionEnabled = includesFinderExtension
            ? extensionIsEnabled
            : false
    }

    func refreshSetupStatus() {
        let previousAccessibilityState = accessibilityGranted
        accessibilityGranted = setupStateOverride?.accessibilityGranted
            ?? AccessibilityPermission.isGranted
        let extensionIsEnabled = setupStateOverride?.extensionEnabled
            ?? FIFinderSyncController.isExtensionEnabled
        finderExtensionEnabled = includesFinderExtension
            ? extensionIsEnabled
            : false

        guard previousAccessibilityState != accessibilityGranted else {
            return
        }

        if setupComplete {
            status = .applied("Finder automation is on and ready to restore saved layouts.")
        } else {
            status = .needsSetup(
                hasRequestedAccessibility
                    ? permissionRecoveryMessage
                    : "Optional Finder automation is off. Allow Accessibility only if you want Rank & Folder to operate Finder’s view controls."
            )
        }
    }

    func requestAccessibilityPermission() {
        hasRequestedAccessibility = true
        _ = AccessibilityPermission.request()
        refreshSetupStatus()
        if !accessibilityGranted {
            status = .needsSetup(permissionRecoveryMessage)
        } else {
            status = .applied("Finder automation is on and ready to restore saved layouts.")
        }
    }

    func checkAccessibilityPermission() {
        hasRequestedAccessibility = true
        refreshSetupStatus()
        status = accessibilityGranted
            ? .applied("Accessibility is recognized. Optional Finder automation is ready.")
            : .needsSetup(permissionRecoveryMessage)
    }

    func revealRunningCopy() {
        NSWorkspace.shared.activateFileViewerSelecting([runningAppURL])
    }

    func requiresManualApply(_ targetFolderURL: URL) -> Bool {
        manualOnlyTargetPaths.contains(targetPath(for: targetFolderURL))
    }

    /// Convenience for the sidebar, where a saved profile's exact folder is
    /// also the target. Inherited callers must pass their resolved target URL.
    func requiresManualApply(_ profile: RankFolderProfile) -> Bool {
        requiresManualApply(profile.folderURL)
    }

    func showFinderExtensionSettings() {
        guard includesFinderExtension else { return }
        FIFinderSyncController.showExtensionManagementInterface()
        status = .applied("The Finder menu is optional; automatic profiles already work through Accessibility.")
    }

    func resetStatus() {
        pendingRequestTask?.cancel()
        pendingRequestTask = nil
        manualResolutionTask?.cancel()
        manualResolutionTask = nil
        applyGeneration += 1
        status = .ready
    }

    func resetForAppReset() {
        resetStatus()
        requestQueue.clear()
        manualOnlyTargetPaths = []
        recentManualApply = nil
        hasRequestedAccessibility = false
        refreshSetupStatus()
    }

    func processPendingRequests() {
        let requests = requestQueue.drain()
        guard let request = requests.last else { return }

        // Only the newest request can describe the focused Finder folder. A
        // future-dated or old request is untrusted stale state and is discarded.
        let age = Date().timeIntervalSince(request.requestedAt)
        guard (0...10).contains(age), request.folderPath.hasPrefix("/") else {
            return
        }
        refreshSetupStatus()
        guard accessibilityGranted else { return }

        pendingRequestTask?.cancel()
        let targetURL = URL(
            fileURLWithPath: request.folderPath,
            isDirectory: true
        )
        let generation = beginApply()
        pendingRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let resolution = await self.profileStore.resolution(for: targetURL)
            guard !Task.isCancelled, generation == self.applyGeneration else {
                return
            }
            guard case .resolved(let layout) = resolution else {
                self.status = .ready
                return
            }
            self.pendingRequestTask = nil
            self.startObservedApply(layout, generation: generation)
        }
    }

    func applyNow(_ profile: RankFolderProfile) {
        guard profile.finderRepresentation != nil else {
            status = .failed("This plan uses more levels or ordering choices than Finder can show. Open its read-only folder preview instead.")
            return
        }
        refreshSetupStatus()
        guard accessibilityGranted else {
            status = .needsSetup(
                "Finder automation is optional and currently off. Preview this layout in Rank & Folder, or allow Accessibility to apply it in Finder."
            )
            return
        }

        pendingRequestTask?.cancel()
        pendingRequestTask = nil
        manualResolutionTask?.cancel()
        let generation = beginApply()
        status = .applying("Checking \(profile.displayName) before opening Finder…")
        manualResolutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let resolution = await self.profileStore.resolution(for: profile.folderURL)
            guard !Task.isCancelled, generation == self.applyGeneration else {
                return
            }
            guard case .resolved(let layout) = resolution,
                  layout.origin == .exact,
                  layout.sourceProfile.id == profile.id,
                  layout.sourceProfile.finderRepresentation != nil else {
                self.status = .failed(
                    "Rank & Folder could not verify this saved folder and plan, so Finder was not opened."
                )
                return
            }
            guard await self.profileStore.revalidate(layout),
                  !Task.isCancelled,
                  generation == self.applyGeneration else {
                self.status = .failed(
                    "This folder or saved plan changed before Finder could open it, so no view was changed."
                )
                return
            }
            self.manualResolutionTask = nil
            self.openAndApplyManually(layout, generation: generation)
        }
    }

    /// Applies only to a Finder folder that was already observed and resolved.
    /// This path never opens Finder or navigates away from the focused target.
    func applyObserved(_ layout: ResolvedFolderLayout) {
        refreshSetupStatus()
        guard accessibilityGranted,
              layout.sourceProfile.isEnabled,
              layout.sourceProfile.finderRepresentation != nil else { return }

        let path = targetPath(for: layout.targetFolderURL)
        guard !manualOnlyTargetPaths.contains(path) else { return }
        if let recentManualApply,
           recentManualApply.path == path,
           Date().timeIntervalSince(recentManualApply.date) < 5 {
            return
        }

        pendingRequestTask?.cancel()
        pendingRequestTask = nil
        let generation = beginApply()
        startObservedApply(layout, generation: generation)
    }

    private func openAndApplyManually(
        _ layout: ResolvedFolderLayout,
        generation: Int
    ) {
        let targetName = displayName(for: layout.targetFolderURL)
        let targetPath = targetPath(for: layout.targetFolderURL)
        recentManualApply = (targetPath, Date())
        status = .applying("Opening \(layoutDescription(layout)) in Finder…")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(
            layout.targetFolderURL,
            configuration: configuration
        ) { [weak self] openedApplication, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.applyGeneration else { return }
                if let error {
                    self.status = .failed(
                        "Finder could not open \(targetName): \(error.localizedDescription)"
                    )
                    return
                }
                guard openedApplication?.bundleIdentifier == "com.apple.finder" else {
                    self.status = .failed(
                        "macOS did not confirm that Finder opened \(targetName), so no view was changed."
                    )
                    return
                }
                self.applyAfterFinderSettles(
                    layout,
                    delay: 0.2,
                    generation: generation,
                    verification: .explicitOpen(
                        expectedTitle: targetName,
                        validUntil: Date(timeIntervalSinceNow: 5)
                    ),
                    mode: .manual
                )
            }
        }
    }

    private func startObservedApply(
        _ layout: ResolvedFolderLayout,
        generation: Int
    ) {
        guard layout.sourceProfile.finderRepresentation != nil else { return }
        let path = targetPath(for: layout.targetFolderURL)
        guard !manualOnlyTargetPaths.contains(path) else {
            status = .ready
            return
        }
        if let recentManualApply,
           recentManualApply.path == path,
           Date().timeIntervalSince(recentManualApply.date) < 5 {
            status = .ready
            return
        }
        status = .applying("Applying \(layoutDescription(layout))…")
        applyAfterFinderSettles(
            layout,
            delay: 0.05,
            generation: generation,
            verification: .exactLocation,
            mode: .observed
        )
    }

    /// Waits for Finder to settle, checks that nothing changed, then applies.
    ///
    /// A manual apply retries while Finder is still opening the window, since
    /// the early failures there are expected. An observed apply never retries
    /// after the focused folder turns out to be a different one, because that
    /// means the person navigated and a retry would change a folder they did
    /// not ask about.
    private func applyAfterFinderSettles(
        _ layout: ResolvedFolderLayout,
        delay: TimeInterval = 0.2,
        attemptsRemaining: Int = 10,
        generation: Int,
        verification: FinderFolderVerification,
        mode: ApplyMode
    ) {
        Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            guard !Task.isCancelled, generation == self.applyGeneration else {
                return
            }
            self.refreshSetupStatus()
            guard await self.profileStore.revalidate(layout),
                  !Task.isCancelled,
                  generation == self.applyGeneration else {
                self.status = mode == .manual
                    ? .failed("This folder or saved plan changed before Rank & Folder could apply it, so no view was changed.")
                    : .ready
                return
            }
            guard let representation = layout.sourceProfile.finderRepresentation else {
                self.status = mode == .manual
                    ? .failed("This plan no longer fits Finder, so no view was changed.")
                    : .ready
                return
            }

            do {
                let outcome = try self.finderClient.apply(
                    targetFolderURL: layout.targetFolderURL,
                    recipe: representation,
                    verification: verification,
                    focusedURLValidator: self.focusedURLValidator(
                        for: layout.targetIdentity
                    )
                )
                let path = self.targetPath(for: layout.targetFolderURL)
                switch outcome {
                case .exactLocation:
                    self.manualOnlyTargetPaths.remove(path)
                    self.status = .applied(self.appliedDescription(layout, representation))
                case .explicitOpenTitle:
                    self.manualOnlyTargetPaths.insert(path)
                    self.status = .applied(
                        "\(self.appliedDescription(layout, representation)) Finder omitted \(self.displayName(for: layout.targetFolderURL))’s folder URL, so manual apply succeeded through explicit-open verification. Automatic matching is unavailable for this target on this macOS version."
                    )
                }
            } catch {
                if let finderError = error as? FinderAccessibilityError,
                   mode == .manual,
                   finderError.canRetryAfterFinderNavigation,
                   attemptsRemaining > 1 {
                    self.applyAfterFinderSettles(
                        layout,
                        delay: 0.25,
                        attemptsRemaining: attemptsRemaining - 1,
                        generation: generation,
                        verification: verification,
                        mode: mode
                    )
                } else if let finderError = error as? FinderAccessibilityError,
                          case .permissionRequired = finderError {
                    self.status = .needsSetup(error.localizedDescription)
                } else if mode == .observed,
                          let finderError = error as? FinderAccessibilityError,
                          case .unexpectedFolder = finderError {
                    // Ordinary navigation invalidates an automatic request. It
                    // must never retry against a folder that was not its target.
                    self.status = .ready
                } else {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func beginApply() -> Int {
        applyGeneration += 1
        return applyGeneration
    }

    private enum ApplyMode: Equatable {
        case manual
        case observed
    }

    private func targetPath(for url: URL) -> String {
        RankFolderProfile.normalizedPath(for: url)
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func layoutDescription(_ layout: ResolvedFolderLayout) -> String {
        let target = displayName(for: layout.targetFolderURL)
        switch layout.origin {
        case .exact:
            return target
        case .inherited:
            return "\(target) using the layout from \(layout.sourceProfile.displayName)"
        }
    }

    private func appliedDescription(
        _ layout: ResolvedFolderLayout,
        _ representation: FinderRecipeRepresentation
    ) -> String {
        let target = displayName(for: layout.targetFolderURL)
        let summary = "\(representation.groupBy.displayName) → \(representation.sortBy.displayName)"
        switch layout.origin {
        case .exact:
            return "\(target) now uses \(summary)."
        case .inherited:
            return "\(target) now uses the \(summary) layout from \(layout.sourceProfile.displayName)."
        }
    }

    private func focusedURLValidator(
        for identity: ResolvedFolderIdentity
    ) -> FinderFocusedURLValidator {
        { focusedURL in
            identity.matchesLiveFolderURL(focusedURL)
        }
    }

    private var permissionRecoveryMessage: String {
        if isRunningFromApplications {
            return "macOS has not approved this running copy. If Rank & Folder already appears On in Accessibility, remove that older entry and add this copy again."
        }
        return "Move Rank & Folder to Applications, reopen it there, then allow Accessibility for that copy."
    }
}
