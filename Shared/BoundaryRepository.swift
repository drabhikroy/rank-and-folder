import Foundation

public enum BoundaryRepositoryError: LocalizedError {
    case encodingFailed(Error)
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            "Could not save the folders Rank & Folder should leave alone: \(error.localizedDescription)"
        case .decodingFailed(let error):
            "Could not read the folders Rank & Folder should leave alone: \(error.localizedDescription)"
        }
    }
}

/// Stores the folders Rank & Folder must leave alone. These are kept separate
/// from saved layouts so that a decoding failure in one collection is visible
/// on its own rather than silently reducing the other.
public final class UserDefaultsBoundaryRepository: @unchecked Sendable {
    public static let boundariesKey = "rankFolderInheritanceBoundaries.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .rankFolderShared) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> [FolderInheritanceBoundary] {
        guard let data = defaults.data(forKey: Self.boundariesKey) else { return [] }
        do {
            return try decoder.decode([FolderInheritanceBoundary].self, from: data)
        } catch {
            throw BoundaryRepositoryError.decodingFailed(error)
        }
    }

    public func save(_ boundaries: [FolderInheritanceBoundary]) throws {
        do {
            defaults.set(try encoder.encode(boundaries), forKey: Self.boundariesKey)
            defaults.synchronize()
        } catch {
            throw BoundaryRepositoryError.encodingFailed(error)
        }
    }
}

/// Loads the two rule collections as one safety unit. Callers must not publish
/// profiles when their matching leave-alone boundaries could not be decoded.
public struct StoredFolderConfiguration: Sendable {
    public let profiles: [RankFolderProfile]
    public let boundaries: [FolderInheritanceBoundary]

    public init(
        profiles: [RankFolderProfile],
        boundaries: [FolderInheritanceBoundary]
    ) {
        self.profiles = profiles
        self.boundaries = boundaries
    }

    public static func load(
        profileRepository: UserDefaultsProfileRepository,
        boundaryRepository: UserDefaultsBoundaryRepository
    ) throws -> StoredFolderConfiguration {
        let loadedProfiles = try profileRepository.load()
        let loadedBoundaries = try boundaryRepository.load()
        return StoredFolderConfiguration(
            profiles: loadedProfiles,
            boundaries: loadedBoundaries
        )
    }
}
