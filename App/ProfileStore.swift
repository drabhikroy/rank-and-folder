import Combine
import Foundation

/// The single owner of saved layouts and leave-alone exceptions.
///
/// Both collections load together. If either fails to decode, both are cleared,
/// because publishing layouts without their exceptions would let a layout cross
/// a branch the person deliberately excluded.
///
/// Several methods await filesystem checks partway through. The main actor can
/// be re-entered during that wait, so duplicate checks are repeated immediately
/// before any change to the collections.
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [RankFolderProfile] = []
    @Published private(set) var boundaries: [FolderInheritanceBoundary] = []
    @Published var lastError: String?

    private let repository: UserDefaultsProfileRepository
    private let boundaryRepository: UserDefaultsBoundaryRepository
    private let resolver: SecureProfileResolver

    init(
        repository: UserDefaultsProfileRepository,
        boundaryRepository: UserDefaultsBoundaryRepository,
        resolver: SecureProfileResolver = SecureProfileResolver()
    ) {
        self.repository = repository
        self.boundaryRepository = boundaryRepository
        self.resolver = resolver
        reload()
    }

    var hasFinderAutomationCandidates: Bool {
        profiles.contains { $0.isEnabled && $0.finderRepresentation != nil }
    }

    func reload() {
        do {
            let configuration = try StoredFolderConfiguration.load(
                profileRepository: repository,
                boundaryRepository: boundaryRepository
            )
            profiles = sortedProfiles(configuration.profiles)
            boundaries = sortedBoundaries(configuration.boundaries)
            lastError = nil
        } catch {
            // A missing boundary could let a higher layout cross a branch the
            // person explicitly left alone. Disable all resolution rather than
            // publishing only the half of the configuration that decoded.
            profiles = []
            boundaries = []
            lastError = error.localizedDescription
        }
    }

    /// Adds a separate saved layout. If this folder already receives a layout
    /// from a higher folder, start with that complete recipe so nothing changes
    /// merely because the person chose to make an exception here.
    @discardableResult
    func add(folderURL: URL) async -> UUID {
        let normalizedPath = RankFolderProfile.normalizedPath(for: folderURL)
        if let existing = profiles.first(where: {
            $0.folderPath == normalizedPath || $0.matches(folderURL: folderURL)
        }) {
            return existing.id
        }

        let inheritedRecipe: OrganizationRecipe?
        if case .resolved(let layout) = await resolution(for: folderURL),
           case .inherited = layout.origin {
            inheritedRecipe = layout.sourceProfile.recipe
        } else {
            inheritedRecipe = nil
        }

        // Main-actor methods may be re-entered while the resolver is awaiting
        // filesystem checks. Another window may have added this folder during
        // that time, so repeat the check immediately before mutation.
        if let existing = profiles.first(where: {
            $0.folderPath == normalizedPath || $0.matches(folderURL: folderURL)
        }) {
            return existing.id
        }

        // Explicitly saving a layout at a boundary means this folder now has
        // its own choice. Remove only the exact boundary; deeper boundaries stay.
        boundaries.removeAll {
            $0.folderPath == normalizedPath
                || RankFolderProfile.urlsReferToSameItem($0.folderURL, folderURL)
        }
        let profile = RankFolderProfile(
            folderURL: folderURL,
            recipe: inheritedRecipe ?? OrganizationRecipe()
        )
        profiles.append(profile)
        profiles = sortedProfiles(profiles)
        persistAll()
        return profile.id
    }

    @discardableResult
    func update(
        id: UUID,
        recipe: OrganizationRecipe? = nil,
        isEnabled: Bool? = nil,
        descendantScope: ProfileDescendantScope? = nil
    ) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        if let descendantScope,
           descendantScope == .descendants,
           profiles[index].descendantScope != .descendants {
            do {
                // Broader use is an explicit action. Capture a fresh,
                // non-authorizing bookmark before granting descendant scope.
                try profiles[index].refreshFolderReference()
                guard profiles[index].folderBookmarkData != nil else {
                    lastError = "Rank & Folder could not create a durable identity for this folder, so its layout still applies here only."
                    return false
                }
            } catch {
                lastError = "Rank & Folder could not safely verify this folder for subfolder use. Remove and add the folder again, then try once more."
                return false
            }
        }

        if let recipe { profiles[index].recipe = recipe }
        if let isEnabled { profiles[index].isEnabled = isEnabled }
        if let descendantScope { profiles[index].descendantScope = descendantScope }
        profiles[index].updatedAt = Date()
        persistProfiles()
        return lastError == nil
    }

    /// Removes a saved layout and any leave-alone exception that exists only
    /// because of it. An exception created under this layout has no meaning
    /// once the layout is gone, and leaving it behind would silently block a
    /// different higher folder from ever applying there.
    func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
        let orphanedBoundaryCount = boundaries.filter { $0.sourceProfileID == id }.count
        boundaries.removeAll { $0.sourceProfileID == id }
        if orphanedBoundaryCount > 0 {
            persistAll()
        } else {
            persistProfiles()
        }
    }

    /// Exceptions saved before Rank & Folder recorded a source layout, or whose
    /// source layout was removed by an earlier version. They still block
    /// inheritance, so the interface lists them for explicit review rather
    /// than removing choices the person made deliberately.
    var unlinkedBoundaries: [FolderInheritanceBoundary] {
        boundaries.filter { boundary in
            guard let sourceProfileID = boundary.sourceProfileID else { return true }
            return !profiles.contains { $0.id == sourceProfileID }
        }
    }

    func profile(id: UUID?) -> RankFolderProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    func boundary(id: UUID?) -> FolderInheritanceBoundary? {
        guard let id else { return nil }
        return boundaries.first { $0.id == id }
    }

    func resolution(for folderURL: URL) async -> FolderLayoutResolution {
        let profileSnapshot = profiles
        let boundarySnapshot = boundaries
        return await resolver.resolve(
            folderURL: folderURL,
            from: profileSnapshot,
            boundaries: boundarySnapshot
        )
    }

    func resolution(forFolderPath path: String) async -> FolderLayoutResolution {
        await resolution(
            for: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    func revalidate(_ layout: ResolvedFolderLayout) async -> Bool {
        let profileSnapshot = profiles
        let boundarySnapshot = boundaries
        return await resolver.revalidate(
            layout,
            from: profileSnapshot,
            boundaries: boundarySnapshot
        )
    }

    /// A paused exact profile may still be previewed on explicit request. This
    /// captures a fresh target identity without making the profile eligible for
    /// automatic or inherited use.
    func exactPreviewResolution(profileID: UUID) async -> ResolvedFolderLayout? {
        guard let profile = profile(id: profileID),
              profile.canSafelyReadFolderMetadata else { return nil }
        let checker = ProductionFolderRelationshipChecker()
        guard case .success(let identity) = await checker.captureTargetIdentity(
            for: profile.folderURL
        ), case .same = await checker.relationship(
            of: StoredFolderReference(profile: profile),
            to: identity
        ) else { return nil }
        return ResolvedFolderLayout(
            targetFolderURL: profile.folderURL,
            targetIdentity: identity,
            sourceProfile: profile,
            origin: .exact
        )
    }

    /// Creates an explicit “leave this branch alone” marker only when the
    /// selected folder is currently covered by the chosen source profile.
    @discardableResult
    func addBoundary(
        folderURL: URL,
        under sourceProfileID: UUID
    ) async -> UUID? {
        let normalizedPath = RankFolderProfile.normalizedPath(for: folderURL)
        if profiles.contains(where: {
            $0.folderPath == normalizedPath || $0.matches(folderURL: folderURL)
        }) {
            lastError = "This folder already has its own saved layout. Remove that layout before leaving the branch alone."
            return nil
        }
        if let existing = boundaries.first(where: {
            $0.folderPath == normalizedPath
                || RankFolderProfile.urlsReferToSameItem($0.folderURL, folderURL)
        }) {
            return existing.id
        }

        guard case .resolved(let current) = await resolution(for: folderURL),
              current.sourceProfile.id == sourceProfileID,
              case .inherited = current.origin else {
            lastError = "Choose a subfolder that currently uses this saved layout."
            return nil
        }


        // The async relationship check above permits main-actor re-entry.
        // Recheck exact records immediately before appending so two windows
        // cannot create duplicate profiles or leave-alone choices.
        if profiles.contains(where: {
            $0.folderPath == normalizedPath || $0.matches(folderURL: folderURL)
        }) {
            lastError = "This folder now has its own saved layout, so it was not marked to be left alone."
            return nil
        }
        if let existing = boundaries.first(where: {
            $0.folderPath == normalizedPath
                || RankFolderProfile.urlsReferToSameItem($0.folderURL, folderURL)
        }) {
            return existing.id
        }

        let boundary = FolderInheritanceBoundary(
            folderURL: folderURL,
            sourceProfileID: sourceProfileID
        )
        guard boundary.folderBookmarkData != nil,
              boundary.folderResourceIdentifier != nil else {
            lastError = "Rank & Folder could not save a durable identity for that folder, so no exception was created."
            return nil
        }
        boundaries.append(boundary)
        boundaries = sortedBoundaries(boundaries)
        persistBoundaries()
        return boundary.id
    }

    func removeBoundary(id: UUID) {
        boundaries.removeAll { $0.id == id }
        persistBoundaries()
    }

    /// Removes Rank & Folder's saved choices only. It never mutates the selected
    /// folders or anything inside them.
    func resetAllSavedChoices() {
        profiles = []
        boundaries = []
        persistAll()
    }

    private func persistProfiles() {
        do {
            try repository.save(profiles)
            lastError = nil
            postConfigurationChange()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistBoundaries() {
        do {
            try boundaryRepository.save(boundaries)
            lastError = nil
            postConfigurationChange()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistAll() {
        do {
            try repository.save(profiles)
            try boundaryRepository.save(boundaries)
            lastError = nil
            postConfigurationChange()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func postConfigurationChange() {
        DarwinNotification.post(SharedConfiguration.profilesChangedNotification)
    }

    private func sortedProfiles(_ values: [RankFolderProfile]) -> [RankFolderProfile] {
        values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func sortedBoundaries(
        _ values: [FolderInheritanceBoundary]
    ) -> [FolderInheritanceBoundary] {
        values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
