import Combine
import Foundation

/// Holds the monitor weakly so a callback registered with the system does not
/// keep it alive after it is no longer needed.
private final class WeakFinderFolderMonitorReference: @unchecked Sendable {
    weak var value: FinderFolderMonitor?

    init(_ value: FinderFolderMonitor) {
        self.value = value
    }
}

/// Detects navigation in the active Finder window using the same public
/// Accessibility API already needed to choose Finder's View menu items.
/// This makes automatic profiles work without requiring a Finder extension.
@MainActor
final class FinderFolderMonitor {
    private let profileStore: ProfileStore
    private let automation: AutomationCoordinator
    private let finderClient = FinderAccessibilityClient()
    private var timer: Timer?
    private var resolutionTask: Task<Void, Never>?
    private var profileChanges: AnyCancellable?
    private var lastObservedTargetURL: URL?
    private var lastObservedPath: String?
    private var lastObservedRulesRevision = -1
    private var rulesRevision = 0

    init(profileStore: ProfileStore, automation: AutomationCoordinator) {
        self.profileStore = profileStore
        self.automation = automation

        // ProfileStore publishes both profiles and inheritance boundaries.
        // Delivering asynchronously on main lets the published values reach
        // changed before the same focused target is resolved again.
        let weakSelf = WeakFinderFolderMonitorReference(self)
        profileChanges = profileStore.objectWillChange.sink {
            DispatchQueue.main.async {
                weakSelf.value?.rulesDidChange()
            }
        }
    }

    /// Polls rather than observing. An Accessibility observer would be cheaper,
    /// but Finder does not reliably emit a notification when the focused folder
    /// changes without a window change. The read is skipped entirely when
    /// Finder is not frontmost or when no saved layout could apply, so the cost
    /// falls to nothing while the person is working elsewhere.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollFinder()
            }
        }
        timer?.tolerance = 0.15
        pollFinder()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resetObservation()
    }

    private func pollFinder() {
        // Accessibility approval is asynchronous. Rechecking here keeps every
        // window and the menu bar item current even if the user leaves System
        // Settings open while toggling the permission.
        automation.refreshSetupStatus()
        guard automation.accessibilityGranted else {
            resetObservation()
            return
        }
        // Avoid reading Finder's Accessibility tree when no enabled source can
        // produce a Finder-compatible layout.
        guard hasEnabledFinderSource else {
            resetObservation()
            return
        }

        do {
            let folderURL = try finderClient.focusedFolderURL()
            let path = RankFolderProfile.normalizedPath(for: folderURL)
            guard path != lastObservedPath
                    || lastObservedRulesRevision != rulesRevision else {
                return
            }
            lastObservedTargetURL = folderURL
            lastObservedPath = path
            lastObservedRulesRevision = rulesRevision
            scheduleResolution(
                for: folderURL,
                path: path,
                rulesRevision: rulesRevision
            )
        } catch FinderAccessibilityError.finderNotActive {
            resetObservation()
        } catch FinderAccessibilityError.finderNotRunning {
            resetObservation()
        } catch {
            // Background observation stays quiet for transient Finder states,
            // such as a closing window or a non-folder focused surface.
        }
    }

    private func scheduleResolution(
        for targetURL: URL,
        path: String,
        rulesRevision scheduledRulesRevision: Int
    ) {
        resolutionTask?.cancel()
        resolutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let resolution = await self.profileStore.resolution(for: targetURL)
            guard !Task.isCancelled,
                  self.lastObservedPath == path,
                  self.rulesRevision == scheduledRulesRevision,
                  case .resolved(let layout) = resolution,
                  layout.sourceProfile.finderRepresentation != nil else {
                return
            }

            // Debounce navigation, then re-resolve through ProfileStore's
            // identity-aware revalidation immediately before handing off.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled,
                  self.lastObservedPath == path,
                  self.rulesRevision == scheduledRulesRevision,
                  await self.profileStore.revalidate(layout),
                  !Task.isCancelled else {
                return
            }
            self.automation.applyObserved(layout)
        }
    }

    private var hasEnabledFinderSource: Bool {
        profileStore.profiles.contains {
            $0.isEnabled && $0.finderRepresentation != nil
        }
    }

    private func rulesDidChange() {
        rulesRevision &+= 1
        resolutionTask?.cancel()
        resolutionTask = nil
        guard timer != nil else { return }
        guard hasEnabledFinderSource else {
            resetObservation()
            return
        }

        // Reuse the observed target rather than performing an extra AX read.
        // The adapter's live validator will still require Finder to be focused
        // on this exact identity before either menu action.
        if let targetURL = lastObservedTargetURL,
           let path = lastObservedPath {
            lastObservedRulesRevision = rulesRevision
            scheduleResolution(
                for: targetURL,
                path: path,
                rulesRevision: rulesRevision
            )
        } else {
            pollFinder()
        }
    }

    private func resetObservation() {
        lastObservedTargetURL = nil
        lastObservedPath = nil
        lastObservedRulesRevision = -1
        resolutionTask?.cancel()
        resolutionTask = nil
    }
}
