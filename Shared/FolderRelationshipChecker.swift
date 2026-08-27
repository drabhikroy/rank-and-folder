import FileProvider
import Foundation

public enum FolderProviderLocation: Equatable, Sendable {
    case local
    case domain(String)
    /// The provider API was unavailable. Exact identity can still be checked,
    /// but this state can never authorize descendant inheritance.
    case unknown
}

public struct ResolvedFolderIdentity: Equatable, Sendable {
    public let canonicalURL: URL
    public let bookmarkData: Data
    public let resourceIdentifier: Data
    public let volumeIdentifier: Data
    public let providerLocation: FolderProviderLocation

    public init(
        canonicalURL: URL,
        bookmarkData: Data,
        resourceIdentifier: Data,
        volumeIdentifier: Data,
        providerLocation: FolderProviderLocation
    ) {
        self.canonicalURL = canonicalURL
        self.bookmarkData = bookmarkData
        self.resourceIdentifier = resourceIdentifier
        self.volumeIdentifier = volumeIdentifier
        self.providerLocation = providerLocation
    }

    /// A synchronous last-moment guard for Finder's focused-folder validator.
    /// Provider compatibility is intentionally handled by the async resolver.
    public func matchesLiveFolderURL(_ folderURL: URL) -> Bool {
        guard (try? RankFolderProfile.requireLiveLocalDirectory(folderURL)) != nil else {
            return false
        }
        let canonical = folderURL.resolvingSymlinksInPath().standardizedFileURL
        return RankFolderProfile.archivedResourceIdentifier(for: canonical)
                == resourceIdentifier
            && RankFolderProfile.archivedVolumeIdentifier(for: canonical)
                == volumeIdentifier
    }
}

public struct StoredFolderReference: Equatable, Sendable {
    public let folderPath: String
    public let bookmarkData: Data?
    public let resourceIdentifier: Data?

    public init(folderPath: String, bookmarkData: Data?, resourceIdentifier: Data?) {
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.resourceIdentifier = resourceIdentifier
    }

    public init(profile: RankFolderProfile) {
        self.init(
            folderPath: profile.folderPath,
            bookmarkData: profile.folderBookmarkData,
            resourceIdentifier: profile.folderResourceIdentifier
        )
    }

    public init(boundary: FolderInheritanceBoundary) {
        self.init(
            folderPath: boundary.folderPath,
            bookmarkData: boundary.folderBookmarkData,
            resourceIdentifier: boundary.folderResourceIdentifier
        )
    }

    public var folderURL: URL {
        URL(fileURLWithPath: folderPath, isDirectory: true)
    }
}

public enum FolderReferenceIssue: Error, Equatable, Sendable {
    case invalidTarget
    case bookmarkMissing
    case bookmarkStale
    case bookmarkUnavailable
    case identityMismatch
    case relationshipUnavailable
    case volumeMismatch
    case providerMismatch
    case providerUnavailable
}

public enum FolderReferenceRelationship: Equatable, Sendable {
    case same
    case ancestor(distance: Int)
    case unrelated
    /// Lexical information may stop inheritance, but never authorizes it.
    case unavailableOnBranch(distance: Int, issue: FolderReferenceIssue)
}

public protocol FolderRelationshipChecking: Sendable {
    func captureTargetIdentity(
        for folderURL: URL
    ) async -> Result<ResolvedFolderIdentity, FolderReferenceIssue>

    func relationship(
        of reference: StoredFolderReference,
        to target: ResolvedFolderIdentity
    ) async -> FolderReferenceRelationship

    func revalidate(
        _ identity: ResolvedFolderIdentity,
        for folderURL: URL
    ) async -> Bool
}

/// Decides whether a saved record refers to the target folder, contains it, or
/// has nothing to do with it, using live filesystem evidence rather than text.
///
/// Three separate facts must agree before a record may act as an ancestor:
/// the bookmark must still resolve to the path the record displays, FileManager
/// must confirm the containment relationship, and both folders must sit on the
/// same volume and the same File Provider domain. Any fact that cannot be
/// established downgrades the result to `unavailableOnBranch`, which stops
/// inheritance without granting it.
public struct ProductionFolderRelationshipChecker: FolderRelationshipChecking {
    public init() {}

    public func captureTargetIdentity(
        for folderURL: URL
    ) async -> Result<ResolvedFolderIdentity, FolderReferenceIssue> {
        do {
            let canonical = try canonicalLiveDirectory(folderURL)
            guard let resourceIdentifier = RankFolderProfile.archivedResourceIdentifier(
                for: canonical
            ), let volumeIdentifier = RankFolderProfile.archivedVolumeIdentifier(
                for: canonical
            ) else {
                return .failure(.invalidTarget)
            }
            let providerLocation = await providerLocation(for: canonical)
            let bookmark = try RankFolderProfile.regularIdentityBookmark(for: canonical)
            return .success(ResolvedFolderIdentity(
                canonicalURL: canonical,
                bookmarkData: bookmark,
                resourceIdentifier: resourceIdentifier,
                volumeIdentifier: volumeIdentifier,
                providerLocation: providerLocation
            ))
        } catch let issue as FolderReferenceIssue {
            return .failure(issue)
        } catch {
            return .failure(.invalidTarget)
        }
    }

    public func relationship(
        of reference: StoredFolderReference,
        to target: ResolvedFolderIdentity
    ) async -> FolderReferenceRelationship {
        let savedURL = reference.folderURL
        let lexicalDistance = Self.componentDistance(
            ancestor: savedURL.standardizedFileURL,
            descendant: target.canonicalURL
        )

        guard let bookmarkData = reference.bookmarkData else {
            return pathOnlyRelationship(
                reference: reference,
                target: target,
                lexicalDistance: lexicalDistance
            )
        }

        let sourceURL: URL
        do {
            sourceURL = try RankFolderProfile.resolvedIdentityBookmark(bookmarkData)
        } catch FolderReferenceError.staleBookmark {
            return unavailableIfOnBranch(
                savedURL: savedURL,
                target: target,
                fallbackDistance: lexicalDistance,
                issue: .bookmarkStale
            )
        } catch {
            return unavailableIfOnBranch(
                savedURL: savedURL,
                target: target,
                fallbackDistance: lexicalDistance,
                issue: .bookmarkUnavailable
            )
        }

        // A bookmark follows moves. Rank & Folder's saved rule remains anchored to
        // its displayed path, so a moved bookmark cannot authorize a new branch.
        guard RankFolderProfile.urlsReferToSameItem(sourceURL, savedURL) else {
            return unavailableIfOnBranch(
                savedURL: savedURL,
                target: target,
                fallbackDistance: lexicalDistance,
                issue: .bookmarkUnavailable
            )
        }

        let relationship: FileManager.URLRelationship
        do {
            var value: FileManager.URLRelationship = .other
            try FileManager.default.getRelationship(
                &value,
                ofDirectoryAt: sourceURL,
                toItemAt: target.canonicalURL
            )
            relationship = value
        } catch {
            return unavailableIfOnBranch(
                savedURL: sourceURL,
                target: target,
                fallbackDistance: lexicalDistance,
                issue: .relationshipUnavailable
            )
        }

        guard relationship == .same || relationship == .contains else {
            return .unrelated
        }
        let verifiedDistance = relationship == .same ? 0 : Self.componentDistance(
            ancestor: sourceURL,
            descendant: target.canonicalURL
        ) ?? max(1, lexicalDistance ?? 1)

        guard RankFolderProfile.archivedVolumeIdentifier(for: sourceURL)
                == target.volumeIdentifier else {
            return .unavailableOnBranch(
                distance: verifiedDistance,
                issue: .volumeMismatch
            )
        }

        // Exact matches remain available when FileProvider cannot classify an
        // otherwise verified local URL. Descendants require positive evidence.
        if relationship == .same { return .same }
        let sourceProvider = await providerLocation(for: sourceURL)
        guard sourceProvider != .unknown, target.providerLocation != .unknown else {
            return .unavailableOnBranch(
                distance: verifiedDistance,
                issue: .providerUnavailable
            )
        }
        guard Self.providersAreCompatible(sourceProvider, target.providerLocation) else {
            return .unavailableOnBranch(
                distance: verifiedDistance,
                issue: .providerMismatch
            )
        }
        return .ancestor(distance: verifiedDistance)
    }

    public func revalidate(
        _ identity: ResolvedFolderIdentity,
        for folderURL: URL
    ) async -> Bool {
        guard case .success(let current) = await captureTargetIdentity(for: folderURL) else {
            return false
        }
        return current.resourceIdentifier == identity.resourceIdentifier
            && current.volumeIdentifier == identity.volumeIdentifier
            && current.providerLocation == identity.providerLocation
    }

    /// Handles records saved before Rank & Folder stored bookmarks. Such a record
    /// may still identify its own folder exactly, which keeps existing Finder
    /// automation working, but it can never establish an ancestor relationship.
    /// Containment therefore returns `unavailableOnBranch` rather than
    /// `ancestor`, so the person is asked to add the folder again.
    private func pathOnlyRelationship(
        reference: StoredFolderReference,
        target: ResolvedFolderIdentity,
        lexicalDistance: Int?
    ) -> FolderReferenceRelationship {
        if let liveSource = try? canonicalLiveDirectory(reference.folderURL) {
            var relationship: FileManager.URLRelationship = .other
            if (try? FileManager.default.getRelationship(
                &relationship,
                ofDirectoryAt: liveSource,
                toItemAt: target.canonicalURL
            )) != nil {
                if relationship == .same {
                    if let expected = reference.resourceIdentifier,
                       expected != target.resourceIdentifier {
                        return .unavailableOnBranch(distance: 0, issue: .identityMismatch)
                    }
                    return .same
                }
                if relationship == .contains {
                    let distance = Self.componentDistance(
                        ancestor: liveSource,
                        descendant: target.canonicalURL
                    ) ?? max(1, lexicalDistance ?? 1)
                    return .unavailableOnBranch(
                        distance: distance,
                        issue: .bookmarkMissing
                    )
                }
            }
        }
        if let expected = reference.resourceIdentifier,
           expected == target.resourceIdentifier {
            return .same
        }
        if lexicalDistance == 0 {
            if reference.resourceIdentifier == nil { return .same }
            return .unavailableOnBranch(distance: 0, issue: .identityMismatch)
        }
        if let lexicalDistance {
            return .unavailableOnBranch(
                distance: lexicalDistance,
                issue: .bookmarkMissing
            )
        }
        return .unrelated
    }

    private func unavailableIfOnBranch(
        savedURL: URL,
        target: ResolvedFolderIdentity,
        fallbackDistance: Int?,
        issue: FolderReferenceIssue
    ) -> FolderReferenceRelationship {
        let distance = Self.componentDistance(
            ancestor: savedURL.standardizedFileURL,
            descendant: target.canonicalURL
        ) ?? fallbackDistance
        guard let distance else { return .unrelated }
        return .unavailableOnBranch(distance: distance, issue: issue)
    }

    private func canonicalLiveDirectory(_ url: URL) throws -> URL {
        do {
            try RankFolderProfile.requireLiveLocalDirectory(url)
            return url.resolvingSymlinksInPath().standardizedFileURL
        } catch {
            throw FolderReferenceIssue.invalidTarget
        }
    }

    private func providerLocation(for url: URL) async -> FolderProviderLocation {
        do {
            let (_, domain) = try await NSFileProviderManager
                .identifierForUserVisibleFile(at: url)
            return .domain(domain.rawValue)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == CocoaError.fileNoSuchFile.rawValue {
            return .local
        } catch {
            return .unknown
        }
    }

    private static func providersAreCompatible(
        _ first: FolderProviderLocation,
        _ second: FolderProviderLocation
    ) -> Bool {
        switch (first, second) {
        case (.local, .local): true
        case (.domain(let firstID), .domain(let secondID)): firstID == secondID
        default: false
        }
    }

    /// Component comparison is used only to rank a relationship already
    /// authorized by FileManager, or to block an unavailable record.
    static func componentDistance(ancestor: URL, descendant: URL) -> Int? {
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        let descendantComponents = descendant.standardizedFileURL.pathComponents
        guard ancestorComponents.count <= descendantComponents.count,
              Array(descendantComponents.prefix(ancestorComponents.count))
                == ancestorComponents else {
            return nil
        }
        return descendantComponents.count - ancestorComponents.count
    }
}
