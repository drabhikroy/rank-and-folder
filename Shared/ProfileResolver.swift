import Foundation

/// Which saved layout was used and when it last changed, so a pending apply can
/// be abandoned if the layout changed underneath it.
public struct FolderProfileRevision: Equatable, Sendable {
    public let profileID: UUID
    public let updatedAt: Date

    public init(profileID: UUID, updatedAt: Date) {
        self.profileID = profileID
        self.updatedAt = updatedAt
    }
}

/// The layout that applies to one folder, and whether it was saved for that
/// folder or inherited from a parent.
public struct ResolvedFolderLayout: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        case exact
        case inherited(distance: Int)
    }

    public let targetFolderURL: URL
    public let targetIdentity: ResolvedFolderIdentity
    public let sourceProfile: RankFolderProfile
    public let origin: Origin
    public let sourceRevision: FolderProfileRevision

    public init(
        targetFolderURL: URL,
        targetIdentity: ResolvedFolderIdentity,
        sourceProfile: RankFolderProfile,
        origin: Origin
    ) {
        self.targetFolderURL = targetFolderURL.standardizedFileURL
        self.targetIdentity = targetIdentity
        self.sourceProfile = sourceProfile
        self.origin = origin
        self.sourceRevision = FolderProfileRevision(
            profileID: sourceProfile.id,
            updatedAt: sourceProfile.updatedAt
        )
    }
}

/// Why no layout was applied. Each case names the specific thing that stopped
/// it, so the app can say which folder or which mark is responsible.
public enum FolderResolutionBlockReason: Equatable, Sendable {
    case targetUnavailable(FolderReferenceIssue)
    case disabledProfile(UUID)
    case boundary(UUID)
    case unavailableProfile(UUID, FolderReferenceIssue)
    case unavailableBoundary(UUID, FolderReferenceIssue)
    case duplicateProfiles([UUID])
}

/// The three possible answers for a folder: a layout applies, something stopped
/// one from applying, or none was ever saved for it.
public enum FolderLayoutResolution: Equatable, Sendable {
    case resolved(ResolvedFolderLayout)
    case blocked(FolderResolutionBlockReason)
    case none
}

public protocol ProfileResolving: Sendable {
    func resolve(
        folderURL: URL,
        from profiles: [RankFolderProfile],
        boundaries: [FolderInheritanceBoundary]
    ) async -> FolderLayoutResolution
}

/// Chooses which saved recipe, if any, applies to a folder Finder is showing.
///
/// The rules are ordered so that a more specific choice always wins and an
/// unverifiable one never grants authority:
///
/// 1. An exact saved layout on the folder itself wins, even inside a branch
///    the person asked Rank & Folder to leave alone. Saving a layout on a folder
///    is a direct statement about that folder.
/// 2. Otherwise the closest verified ancestor that opted into subfolder use
///    wins, and only if nothing blocks the branch between here and there.
/// 3. A boundary, a paused layout, an unreadable identity, or two records at
///    the same distance blocks the branch instead of guessing.
///
/// Every relationship is decided by `FolderRelationshipChecking` against live
/// filesystem identity. A matching path string is never sufficient.
public struct SecureProfileResolver: ProfileResolving {
    private let checker: any FolderRelationshipChecking

    public init(
        checker: any FolderRelationshipChecking = ProductionFolderRelationshipChecker()
    ) {
        self.checker = checker
    }

    public func resolve(
        folderURL: URL,
        from profiles: [RankFolderProfile],
        boundaries: [FolderInheritanceBoundary] = []
    ) async -> FolderLayoutResolution {
        let targetIdentity: ResolvedFolderIdentity
        switch await checker.captureTargetIdentity(for: folderURL) {
        case .success(let identity): targetIdentity = identity
        case .failure(let issue): return .blocked(.targetUnavailable(issue))
        }

        // Records are bucketed by how many path components separate them from
        // the target. Distance 0 is the folder itself. Collecting every record
        // first, including unavailable ones, lets a broken record at a closer
        // distance block a working record further up rather than being skipped.
        var profileNodes: [Int: [ProfileNode]] = [:]
        for profile in profiles {
            let relationship = await checker.relationship(
                of: StoredFolderReference(profile: profile),
                to: targetIdentity
            )
            switch relationship {
            case .same:
                profileNodes[0, default: []].append(.valid(profile))
            case .ancestor(let distance):
                profileNodes[distance, default: []].append(.valid(profile))
            case .unavailableOnBranch(let distance, let issue):
                profileNodes[distance, default: []].append(.unavailable(profile, issue))
            case .unrelated:
                break
            }
        }

        var boundaryNodes: [Int: [BoundaryNode]] = [:]
        for boundary in boundaries {
            let relationship = await checker.relationship(
                of: StoredFolderReference(boundary: boundary),
                to: targetIdentity
            )
            switch relationship {
            case .same:
                boundaryNodes[0, default: []].append(.valid(boundary))
            case .ancestor(let distance):
                boundaryNodes[distance, default: []].append(.valid(boundary))
            case .unavailableOnBranch(let distance, let issue):
                boundaryNodes[distance, default: []].append(.unavailable(boundary, issue))
            case .unrelated:
                break
            }
        }

        // An exact rule is the one exception that may start inside a boundary.
        if let exactProfiles = profileNodes[0], !exactProfiles.isEmpty {
            if exactProfiles.count != 1 {
                return .blocked(.duplicateProfiles(exactProfiles.map(\.id).sorted(by: uuidOrder)))
            }
            switch exactProfiles[0] {
            case .valid(let profile) where profile.isEnabled:
                return .resolved(ResolvedFolderLayout(
                    targetFolderURL: folderURL,
                    targetIdentity: targetIdentity,
                    sourceProfile: profile,
                    origin: .exact
                ))
            case .valid(let profile):
                return .blocked(.disabledProfile(profile.id))
            case .unavailable(let profile, let issue):
                return .blocked(.unavailableProfile(profile.id, issue))
            }
        }
        if let exactBoundary = boundaryNodes[0]?.first {
            return exactBoundary.blockReason
        }

        // Walk outward from the target. The first distance carrying anything
        // decides the outcome, so a nearer boundary always beats a further
        // layout and inheritance can never jump over an exception.
        let distances = Set(profileNodes.keys).union(boundaryNodes.keys)
            .filter { $0 > 0 }
            .sorted()
        for distance in distances {
            let profilesHere = profileNodes[distance] ?? []
            let boundariesHere = boundaryNodes[distance] ?? []

            if profilesHere.count > 1 {
                return .blocked(.duplicateProfiles(profilesHere.map(\.id).sorted(by: uuidOrder)))
            }
            if let boundary = boundariesHere.first {
                return boundary.blockReason
            }
            guard let profileNode = profilesHere.first else { continue }
            switch profileNode {
            case .unavailable(let profile, let issue):
                return .blocked(.unavailableProfile(profile.id, issue))
            case .valid(let profile) where !profile.isEnabled:
                return .blocked(.disabledProfile(profile.id))
            case .valid(let profile) where profile.descendantScope == .descendants:
                return .resolved(ResolvedFolderLayout(
                    targetFolderURL: folderURL,
                    targetIdentity: targetIdentity,
                    sourceProfile: profile,
                    origin: .inherited(distance: distance)
                ))
            case .valid:
                // Active exact-only ancestors are deliberately transparent.
                continue
            }
        }
        return .none
    }

    /// Rechecks the target identity and resolves current rules again. Callers
    /// can use this immediately before a delayed Finder or Organized View action.
    public func revalidate(
        _ layout: ResolvedFolderLayout,
        from profiles: [RankFolderProfile],
        boundaries: [FolderInheritanceBoundary] = []
    ) async -> Bool {
        guard await checker.revalidate(
            layout.targetIdentity,
            for: layout.targetFolderURL
        ) else { return false }
        guard case .resolved(let current) = await resolve(
            folderURL: layout.targetFolderURL,
            from: profiles,
            boundaries: boundaries
        ) else { return false }
        return current.sourceRevision == layout.sourceRevision
            && current.origin == layout.origin
            && current.targetIdentity.resourceIdentifier
                == layout.targetIdentity.resourceIdentifier
    }

    private enum ProfileNode {
        case valid(RankFolderProfile)
        case unavailable(RankFolderProfile, FolderReferenceIssue)

        var id: UUID {
            switch self {
            case .valid(let profile), .unavailable(let profile, _): profile.id
            }
        }
    }

    private enum BoundaryNode {
        case valid(FolderInheritanceBoundary)
        case unavailable(FolderInheritanceBoundary, FolderReferenceIssue)

        var blockReason: FolderLayoutResolution {
            switch self {
            case .valid(let boundary):
                .blocked(.boundary(boundary.id))
            case .unavailable(let boundary, let issue):
                .blocked(.unavailableBoundary(boundary.id, issue))
            }
        }
    }

    private func uuidOrder(_ first: UUID, _ second: UUID) -> Bool {
        first.uuidString < second.uuidString
    }
}
