import Foundation

public struct ApplyRequest: Codable, Equatable, Sendable {
    public var folderPath: String
    public var requestedAt: Date

    public init(folderURL: URL, requestedAt: Date = Date()) {
        self.folderPath = RankFolderProfile.normalizedPath(for: folderURL)
        self.requestedAt = requestedAt
    }
}

/// Carries apply requests from the Finder extension to the containing app.
///
/// The two run as separate processes, so the request is written to the shared
/// suite and announced with a Darwin notification. The queue is bounded and
/// drained rather than read, so a containing app that was not running cannot
/// replay a backlog of stale requests when it next launches.
public final class ApplyRequestQueue: @unchecked Sendable {
    public static let requestsKey = "rankFolderApplyRequests.v1"
    public static let maximumRequestCount = 32

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .rankFolderShared) {
        self.defaults = defaults
        // Match the profile and boundary repositories so every Rank & Folder
        // record in the shared suite uses one date representation.
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func enqueue(folderURL: URL) {
        var requests = loadRequests()
        requests.append(ApplyRequest(folderURL: folderURL))
        requests = Array(requests.suffix(Self.maximumRequestCount))
        saveRequests(requests)
    }

    public func drain() -> [ApplyRequest] {
        let requests = loadRequests()
        defaults.removeObject(forKey: Self.requestsKey)
        defaults.synchronize()
        return requests
    }

    public func clear() {
        defaults.removeObject(forKey: Self.requestsKey)
        defaults.synchronize()
    }

    private func loadRequests() -> [ApplyRequest] {
        guard let data = defaults.data(forKey: Self.requestsKey) else { return [] }
        return (try? decoder.decode([ApplyRequest].self, from: data)) ?? []
    }

    private func saveRequests(_ requests: [ApplyRequest]) {
        guard let data = try? encoder.encode(requests) else { return }
        defaults.set(data, forKey: Self.requestsKey)
        defaults.synchronize()
    }
}
