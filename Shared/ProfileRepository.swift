import Foundation

public enum ProfileRepositoryError: LocalizedError {
    case encodingFailed(Error)
    case decodingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            "Could not save folder profiles: \(error.localizedDescription)"
        case .decodingFailed(let error):
            "Could not read folder profiles: \(error.localizedDescription)"
        }
    }
}

/// Reads and writes saved layouts as JSON in a preferences suite. The suite is
/// the App Group when the Finder extension is present, so both processes see
/// one collection, and ordinary application preferences otherwise.
public final class UserDefaultsProfileRepository: @unchecked Sendable {
    public static let profilesKey = "rankFolderProfiles.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .rankFolderShared) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> [RankFolderProfile] {
        guard let data = defaults.data(forKey: Self.profilesKey) else { return [] }
        do {
            return try decoder.decode([RankFolderProfile].self, from: data)
        } catch {
            throw ProfileRepositoryError.decodingFailed(error)
        }
    }

    public func save(_ profiles: [RankFolderProfile]) throws {
        do {
            let data = try encoder.encode(profiles)
            defaults.set(data, forKey: Self.profilesKey)
            // The app and extension are separate processes. Synchronizing here
            // narrows the handoff window before the Darwin notification is sent.
            defaults.synchronize()
        } catch {
            throw ProfileRepositoryError.encodingFailed(error)
        }
    }
}

