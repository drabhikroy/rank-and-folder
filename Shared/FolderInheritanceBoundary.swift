import Foundation

/// Stops a layout from being inherited across this folder. Boundaries carry
/// identity only; they never carry a recipe or filesystem access authority.
public struct FolderInheritanceBoundary: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var folderPath: String
    public var displayName: String
    public var folderBookmarkData: Data?
    public var folderResourceIdentifier: Data?
    /// The saved layout this exception was created against. A boundary keeps
    /// blocking every source once it exists, so this records which layout the
    /// person was looking at when they asked Rank & Folder to stop. Removing that
    /// layout removes the exception with it instead of leaving a marker that
    /// silently blocks an unrelated folder later.
    public var sourceProfileID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        folderURL: URL,
        displayName: String? = nil,
        sourceProfileID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        folderPath = RankFolderProfile.normalizedPath(for: folderURL)
        self.displayName = displayName ?? folderURL.lastPathComponent
        folderBookmarkData = try? RankFolderProfile.regularIdentityBookmark(for: folderURL)
        folderResourceIdentifier = RankFolderProfile.archivedResourceIdentifier(for: folderURL)
        self.sourceProfileID = sourceProfileID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var folderURL: URL {
        URL(fileURLWithPath: folderPath, isDirectory: true)
    }

    public mutating func refreshFolderReference() throws {
        try RankFolderProfile.requireLiveLocalDirectory(folderURL)
        folderBookmarkData = try RankFolderProfile.regularIdentityBookmark(for: folderURL)
        folderResourceIdentifier = RankFolderProfile.archivedResourceIdentifier(for: folderURL)
        guard folderResourceIdentifier != nil else {
            throw FolderReferenceError.identityUnavailable
        }
        schemaVersion = Self.currentSchemaVersion
        updatedAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, folderPath, displayName, folderBookmarkData
        case folderResourceIdentifier, sourceProfileID, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "This boundary was created by a newer Rank & Folder version."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        // Same rule as a saved layout: a record read back from shared storage
        // has to name an absolute path before anything is done with it.
        let storedFolderPath = try container.decode(String.self, forKey: .folderPath)
        folderPath = try RankFolderProfile.requireAbsolutePath(
            storedFolderPath,
            in: container,
            forKey: .folderPath
        )
        displayName = try container.decode(String.self, forKey: .displayName)
        folderBookmarkData = try container.decodeIfPresent(Data.self, forKey: .folderBookmarkData)
        folderResourceIdentifier = try container.decodeIfPresent(
            Data.self,
            forKey: .folderResourceIdentifier
        )
        // Records written before this field existed decode as nil. A nil value
        // means the exception is not tied to any one layout, so it survives
        // profile removal exactly as it always has.
        sourceProfileID = try container.decodeIfPresent(UUID.self, forKey: .sourceProfileID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

