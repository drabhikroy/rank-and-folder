import Foundation

// MARK: - Finder's supported controls

/// The grouping choices Finder itself offers. A recipe is reproducible in Finder
/// only when its first section rule maps onto one of these.
public enum GroupCriterion: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case name
    case kind
    case dateModified
    case dateCreated
    case size
    case tags

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "No sections"
        case .name: "Name"
        case .kind: "File type"
        case .dateModified: "Last modified"
        case .dateCreated: "Date created"
        case .size: "Size"
        case .tags: "Tags"
        }
    }

    /// Finder exposes English menu titles rather than stable identifiers.
    public var finderMenuTitle: String {
        switch self {
        case .none: "None"
        case .name: "Name"
        case .kind: "Kind"
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        case .size: "Size"
        case .tags: "Tags"
        }
    }
}

/// The sorting choices Finder itself offers, used the same way as the grouping
/// choices above.
public enum SortCriterion: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    case kind
    case dateModified
    case dateCreated
    case size
    case tags

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .name: "Name"
        case .kind: "File type"
        case .dateModified: "Last modified"
        case .dateCreated: "Date created"
        case .size: "Size"
        case .tags: "Tags"
        }
    }

    public var finderMenuTitle: String {
        switch self {
        case .name: "Name"
        case .kind: "Kind"
        case .dateModified: "Date Modified"
        case .dateCreated: "Date Created"
        case .size: "Size"
        case .tags: "Tags"
        }
    }
}

// MARK: - One canonical organization recipe

/// Everything a level can be built on, including the criteria Finder has no
/// control for. Those extra ones are why a recipe can go deeper than Finder can
/// reproduce.
public enum AdvancedCriterion: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    case kind
    case fileExtension
    case dateModified
    case dateCreated
    case size
    case tags

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .name: "Name"
        case .kind: "File type"
        case .fileExtension: "File extension"
        case .dateModified: "Last modified"
        case .dateCreated: "Date created"
        case .size: "Size"
        case .tags: "Tags"
        }
    }

    public var systemImage: String {
        switch self {
        case .name: "textformat"
        case .kind: "doc.on.doc"
        case .fileExtension: "character.cursor.ibeam"
        case .dateModified: "clock.arrow.circlepath"
        case .dateCreated: "calendar.badge.plus"
        case .size: "internaldrive"
        case .tags: "tag"
        }
    }

    public var finderGroupCriterion: GroupCriterion? {
        switch self {
        case .name: .name
        case .kind: .kind
        case .dateModified: .dateModified
        case .dateCreated: .dateCreated
        case .size: .size
        case .tags: .tags
        case .fileExtension: nil
        }
    }

    public var finderSortCriterion: SortCriterion? {
        switch self {
        case .name: .name
        case .kind: .kind
        case .dateModified: .dateModified
        case .dateCreated: .dateCreated
        case .size: .size
        case .tags: .tags
        case .fileExtension: nil
        }
    }

    init(_ criterion: GroupCriterion) {
        switch criterion {
        case .none, .name: self = .name
        case .kind: self = .kind
        case .dateModified: self = .dateModified
        case .dateCreated: self = .dateCreated
        case .size: self = .size
        case .tags: self = .tags
        }
    }

    init(_ criterion: SortCriterion) {
        switch criterion {
        case .name: self = .name
        case .kind: self = .kind
        case .dateModified: self = .dateModified
        case .dateCreated: self = .dateCreated
        case .size: self = .size
        case .tags: self = .tags
        }
    }
}

/// Which way a level runs when the person chooses rather than leaving the
/// criterion to decide.
public enum AdvancedSortDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case ascending
    case descending

    public var id: String { rawValue }

    public func displayName(for criterion: AdvancedCriterion) -> String {
        switch (self, criterion) {
        case (.ascending, .dateModified), (.ascending, .dateCreated): "Oldest first"
        case (.descending, .dateModified), (.descending, .dateCreated): "Newest first"
        case (.ascending, .size): "Smallest first"
        case (.descending, .size): "Largest first"
        case (.ascending, _): "A-Z"
        case (.descending, _): "Z-A"
        }
    }

    public var displayName: String {
        self == .ascending ? "Ascending" : "Descending"
    }

    public var shortDisplayName: String {
        self == .ascending ? "A-Z" : "Z-A"
    }
}

/// One level of a recipe: what it is built on and which way it runs.
public struct OrganizationLevel: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var criterion: AdvancedCriterion
    /// `nil` preserves Finder's own direction and keeps simple recipes native.
    public var direction: AdvancedSortDirection?

    public init(
        id: UUID = UUID(),
        criterion: AdvancedCriterion,
        direction: AdvancedSortDirection? = nil
    ) {
        self.id = id
        self.criterion = criterion
        self.direction = direction
    }
}

/// A whole saved layout. Sections split a folder into headings and item order
/// decides what comes first inside the smallest section, each up to seven levels.
public struct OrganizationRecipe: Codable, Equatable, Sendable {
    public static let maximumLevelsPerArea = 7

    public var sections: [OrganizationLevel]
    public var itemOrder: [OrganizationLevel]

    public init(
        sections: [OrganizationLevel] = [],
        itemOrder: [OrganizationLevel] = [OrganizationLevel(criterion: .name)]
    ) {
        self.sections = Array(sections.prefix(Self.maximumLevelsPerArea))
        self.itemOrder = Array(itemOrder.prefix(Self.maximumLevelsPerArea))
        if self.itemOrder.isEmpty {
            self.itemOrder = [OrganizationLevel(criterion: .name)]
        }
    }

    public var levelCount: Int { sections.count + itemOrder.count }

    public var allLevels: [OrganizationLevel] { sections + itemOrder }
}

/// The one grouping rule and one sorting rule Finder can actually be set to,
/// derived from a recipe when the recipe is shallow enough.
public struct FinderRecipeRepresentation: Equatable, Sendable {
    public var groupBy: GroupCriterion
    public var sortBy: SortCriterion
}

/// How far a saved layout reaches beyond the folder it was saved for.
public enum ProfileDescendantScope: String, Codable, CaseIterable, Sendable {
    /// Apply the recipe only when Finder is showing the saved folder itself.
    case exactFolder
    /// Allow the recipe to be inherited by verified descendant folders.
    case descendants
}

// MARK: - Stored schema compatibility

/// Whether a recipe is shallow enough for Finder, or can only be shown as a
/// preview inside the app.
public enum RecipeMode: String, Codable, Sendable {
    case finder
    case advanced
}

/// Whether a rule creates headings or orders rows.
public enum AdvancedRuleBehavior: String, Codable, Sendable {
    case group
    case sort
}

/// One rule of a flattened recipe, in the form the preview builder consumes.
public struct AdvancedViewRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var behavior: AdvancedRuleBehavior
    public var criterion: AdvancedCriterion
    public var direction: AdvancedSortDirection

    public init(
        id: UUID = UUID(),
        behavior: AdvancedRuleBehavior,
        criterion: AdvancedCriterion,
        direction: AdvancedSortDirection = .ascending
    ) {
        self.id = id
        self.behavior = behavior
        self.criterion = criterion
        self.direction = direction
    }
}

/// One saved folder and the recipe Rank & Folder keeps for it.
///
/// A profile holds three kinds of information about the folder: the path it
/// displays, a bookmark that identifies the folder without granting access to
/// it, and an archived filesystem identifier. The last two exist so that a
/// folder deleted and recreated at the same path is recognized as a different
/// folder. Older records may carry fewer of them, which limits what they are
/// allowed to do rather than making them invalid.
public struct RankFolderProfile: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var id: UUID
    public var folderPath: String
    public var displayName: String
    public var recipe: OrganizationRecipe
    public var descendantScope: ProfileDescendantScope
    /// A non-security-scoped identity bookmark. It identifies the folder but
    /// intentionally carries no implicit filesystem access authority.
    public var folderBookmarkData: Data?
    /// Archived read-only filesystem identity captured when the folder is added.
    /// It is optional so v1/v2 and early v3 profiles remain decodable.
    public var folderResourceIdentifier: Data?
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        folderURL: URL,
        displayName: String? = nil,
        recipe: OrganizationRecipe = OrganizationRecipe(),
        descendantScope: ProfileDescendantScope = .exactFolder,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.folderPath = Self.normalizedPath(for: folderURL)
        self.displayName = displayName ?? folderURL.lastPathComponent
        self.recipe = recipe
        self.descendantScope = descendantScope
        self.folderBookmarkData = try? Self.regularIdentityBookmark(for: folderURL)
        self.folderResourceIdentifier = Self.archivedResourceIdentifier(for: folderURL)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Source-compatible initializer for tests and clients that create Finder recipes.
    public init(
        id: UUID = UUID(),
        folderURL: URL,
        displayName: String? = nil,
        groupBy: GroupCriterion,
        sortBy: SortCriterion,
        descendantScope: ProfileDescendantScope = .exactFolder,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let sections = groupBy == .none
            ? []
            : [OrganizationLevel(criterion: AdvancedCriterion(groupBy))]
        self.init(
            id: id,
            folderURL: folderURL,
            displayName: displayName,
            recipe: OrganizationRecipe(
                sections: sections,
                itemOrder: [OrganizationLevel(criterion: AdvancedCriterion(sortBy))]
            ),
            descendantScope: descendantScope,
            isEnabled: isEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public var folderURL: URL {
        URL(fileURLWithPath: folderPath, isDirectory: true)
    }

    /// Finder is selected automatically only when the complete recipe can be
    /// represented without dropping a level or a requested direction.
    /// The Finder equivalent of this recipe, or nil when Finder cannot show it.
    ///
    /// Finder supports one grouping and one sort. A recipe qualifies only if it
    /// fits entirely: at most one section, exactly one order rule, no explicit
    /// directions, and no criterion Finder lacks. Rank & Folder never drops a
    /// level to force a fit, so a recipe that does not qualify is offered as a
    /// read-only preview instead.
    public var finderRepresentation: FinderRecipeRepresentation? {
        guard recipe.sections.count <= 1,
              recipe.itemOrder.count == 1,
              recipe.allLevels.allSatisfy({ $0.direction == nil }),
              let sortBy = recipe.itemOrder[0].criterion.finderSortCriterion else {
            return nil
        }

        let groupBy: GroupCriterion
        if let section = recipe.sections.first {
            guard let mapped = section.criterion.finderGroupCriterion else { return nil }
            groupBy = mapped
        } else {
            groupBy = .none
        }
        return FinderRecipeRepresentation(groupBy: groupBy, sortBy: sortBy)
    }

    public var requiresOrganizedView: Bool { finderRepresentation == nil }

    /// Compatibility accessors used only by the Finder Accessibility adapter.
    public var groupBy: GroupCriterion { finderRepresentation?.groupBy ?? .none }
    public var sortBy: SortCriterion { finderRepresentation?.sortBy ?? .name }

    public var advancedRules: [AdvancedViewRule] {
        recipe.sections.map {
            AdvancedViewRule(
                id: $0.id,
                behavior: .group,
                criterion: $0.criterion,
                direction: $0.direction ?? .ascending
            )
        } + recipe.itemOrder.map {
            AdvancedViewRule(
                id: $0.id,
                behavior: .sort,
                criterion: $0.criterion,
                direction: $0.direction ?? .ascending
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case folderPath
        case displayName
        case recipe
        case descendantScope
        case folderBookmarkData
        case folderResourceIdentifier
        case isEnabled
        case createdAt
        case updatedAt

        // v1/v2, decode only.
        case groupBy
        case sortBy
        case recipeMode
        case advancedRules
    }

    /// Reads any schema version Rank & Folder has written and produces a current
    /// recipe. A version above the current one is rejected instead of being
    /// read partially, because unknown fields could carry choices this build
    /// would silently discard on the next save. Fields added in version 4 are
    /// ignored for older records so that a migrated profile never gains
    /// subfolder authority it was never granted.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let savedSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        guard (1...Self.currentSchemaVersion).contains(savedSchemaVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "This profile was created by a newer RankFolder version."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        folderPath = try container.decode(String.self, forKey: .folderPath)
        displayName = try container.decode(String.self, forKey: .displayName)
        descendantScope = savedSchemaVersion >= 4
            ? try container.decodeIfPresent(
                ProfileDescendantScope.self,
                forKey: .descendantScope
            ) ?? .exactFolder
            : .exactFolder
        folderBookmarkData = savedSchemaVersion >= 4
            ? try container.decodeIfPresent(Data.self, forKey: .folderBookmarkData)
            : nil
        folderResourceIdentifier = try container.decodeIfPresent(
            Data.self,
            forKey: .folderResourceIdentifier
        )
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if let savedRecipe = try container.decodeIfPresent(
            OrganizationRecipe.self,
            forKey: .recipe
        ) {
            recipe = OrganizationRecipe(
                sections: savedRecipe.sections,
                itemOrder: savedRecipe.itemOrder
            )
            return
        }

        let legacyMode = try container.decodeIfPresent(RecipeMode.self, forKey: .recipeMode)
            ?? .finder
        if legacyMode == .advanced,
           let rules = try container.decodeIfPresent(
               [AdvancedViewRule].self,
               forKey: .advancedRules
           ) {
            recipe = OrganizationRecipe(
                sections: rules.filter { $0.behavior == .group }.map {
                    OrganizationLevel(id: $0.id, criterion: $0.criterion, direction: $0.direction)
                },
                itemOrder: rules.filter { $0.behavior == .sort }.map {
                    OrganizationLevel(id: $0.id, criterion: $0.criterion, direction: $0.direction)
                }
            )
        } else {
            let legacyGroup = try container.decode(GroupCriterion.self, forKey: .groupBy)
            let legacySort = try container.decode(SortCriterion.self, forKey: .sortBy)
            recipe = OrganizationRecipe(
                sections: legacyGroup == .none
                    ? []
                    : [OrganizationLevel(criterion: AdvancedCriterion(legacyGroup))],
                itemOrder: [OrganizationLevel(criterion: AdvancedCriterion(legacySort))]
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(recipe, forKey: .recipe)
        try container.encode(descendantScope, forKey: .descendantScope)
        try container.encodeIfPresent(folderBookmarkData, forKey: .folderBookmarkData)
        try container.encodeIfPresent(
            folderResourceIdentifier,
            forKey: .folderResourceIdentifier
        )
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    /// A saved record matches a folder only when the path agrees and any
    /// stored identity evidence still agrees. A record that carries a bookmark
    /// but no resource identifier must still have its bookmark checked, so the
    /// skip applies only when the record carries no evidence at all.
    public func matches(folderURL: URL) -> Bool {
        let hasNoStoredIdentity = folderBookmarkData == nil
            && folderResourceIdentifier == nil
        return Self.urlsReferToSameItem(self.folderURL, folderURL)
            && (hasNoStoredIdentity || hasOriginalFolderIdentity)
    }

    /// Refreshes the durable folder identity before the caller turns on
    /// descendant inheritance. This never creates a security-scoped bookmark.
    public mutating func refreshFolderReference() throws {
        let url = folderURL
        try Self.requireLiveLocalDirectory(url)
        folderBookmarkData = try Self.regularIdentityBookmark(for: url)
        folderResourceIdentifier = Self.archivedResourceIdentifier(for: url)
        guard folderResourceIdentifier != nil else {
            throw FolderReferenceError.identityUnavailable
        }
        schemaVersion = Self.currentSchemaVersion
        updatedAt = Date()
    }

    /// Prevents a saved path from silently reading a replacement folder.
    /// Profiles without stored identity data must be added again before metadata is read.
    public var hasOriginalFolderIdentity: Bool {
        if let folderBookmarkData {
            guard let bookmarkedURL = try? Self.resolvedIdentityBookmark(folderBookmarkData) else {
                return false
            }
            return Self.urlsReferToSameItem(bookmarkedURL, folderURL)
        }
        guard let folderResourceIdentifier else { return true }
        return Self.archivedResourceIdentifier(for: folderURL)
            == folderResourceIdentifier
    }

    /// Metadata views require evidence captured when the folder was added.
    /// Very old path-only profiles may still drive exact Finder automation,
    /// but must be re-added before Rank & Folder enumerates their contents.
    public var canSafelyReadFolderMetadata: Bool {
        guard folderBookmarkData != nil || folderResourceIdentifier != nil else {
            return false
        }
        return hasOriginalFolderIdentity
    }

    public static func normalizedPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    /// Compares two folder URLs by increasingly authoritative means: the
    /// normalized path, then the path with symbolic links resolved, then the
    /// filesystem resource identifier. The identifier is what distinguishes a
    /// folder from a different folder occupying the same path later.
    public static func urlsReferToSameItem(_ first: URL, _ second: URL) -> Bool {
        guard first.isFileURL, second.isFileURL else { return false }

        if normalizedPath(for: first) == normalizedPath(for: second) {
            return true
        }

        let resolvedFirst = first.resolvingSymlinksInPath()
        let resolvedSecond = second.resolvingSymlinksInPath()
        if normalizedPath(for: resolvedFirst) == normalizedPath(for: resolvedSecond) {
            return true
        }

        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let firstIdentifier = try? resolvedFirst.resourceValues(forKeys: keys)
                .fileResourceIdentifier,
              let secondIdentifier = try? resolvedSecond.resourceValues(forKeys: keys)
                .fileResourceIdentifier else {
            return false
        }
        return (firstIdentifier as AnyObject).isEqual(secondIdentifier)
    }

    static func archivedResourceIdentifier(for url: URL) -> Data? {
        let resolved = url.resolvingSymlinksInPath()
        guard let identifier = try? resolved.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: identifier as Any,
            requiringSecureCoding: true
        )
    }

    static func archivedVolumeIdentifier(for url: URL) -> Data? {
        let resolved = url.resolvingSymlinksInPath()
        guard let identifier = try? resolved.resourceValues(
            forKeys: [.volumeIdentifierKey]
        ).volumeIdentifier else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: identifier as Any,
            requiringSecureCoding: true
        )
    }

    /// Creates a bookmark used only to recognize a folder. The
    /// `withoutImplicitSecurityScope` option is what keeps it identity evidence
    /// rather than a stored access grant: resolving it later confirms which
    /// folder the record means without reopening access the person did not
    /// give again.
    static func regularIdentityBookmark(for url: URL) throws -> Data {
        try requireLiveLocalDirectory(url)
        return try url.resolvingSymlinksInPath().bookmarkData(
            options: [.withoutImplicitSecurityScope],
            includingResourceValuesForKeys: [
                .fileResourceIdentifierKey,
                .volumeIdentifierKey,
                .isDirectoryKey,
                .isPackageKey
            ],
            relativeTo: nil
        )
    }

    static func resolvedIdentityBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else { throw FolderReferenceError.staleBookmark }
        try requireLiveLocalDirectory(url)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Rejects anything that is not a real, present, ordinary directory on
    /// this Mac. Bundles such as apps and photo libraries are excluded because
    /// arranging their contents is not something Rank & Folder should offer.
    static func requireLiveLocalDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw FolderReferenceError.notFileURL }
        guard url.host == nil || url.host?.isEmpty == true else {
            throw FolderReferenceError.remoteFileURL
        }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try resolved.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey
        ])
        guard values.isDirectory == true else { throw FolderReferenceError.notDirectory }
        guard values.isPackage != true else { throw FolderReferenceError.packageDirectory }
    }
}

/// Every reason a chosen folder cannot be saved, such as a file rather than a
/// folder, a package, or a location that is not on this Mac.
public enum FolderReferenceError: Error, Equatable, Sendable {
    case notFileURL
    case remoteFileURL
    case notDirectory
    case packageDirectory
    case staleBookmark
    case identityUnavailable
}
