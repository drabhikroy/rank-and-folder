import Foundation
import XCTest
@testable import RankFolderCore

final class ProfileRepositoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RankFolderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRepositoryStartsEmptyAndPersistsProfiles() throws {
        let repository = UserDefaultsProfileRepository(defaults: defaults)
        XCTAssertEqual(try repository.load(), [])

        let profiles = [
            RankFolderProfile(
                folderURL: URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true),
                groupBy: .dateModified,
                sortBy: .name,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
        try repository.save(profiles)

        XCTAssertEqual(try repository.load(), profiles)
    }

    func testBoundaryRepositoryStartsEmptyAndPersistsBoundaries() throws {
        let repository = UserDefaultsBoundaryRepository(defaults: defaults)
        XCTAssertEqual(try repository.load(), [])
        let boundary = FolderInheritanceBoundary(
            folderURL: URL(fileURLWithPath: "/tmp/Boundary", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try repository.save([boundary])
        XCTAssertEqual(try repository.load(), [boundary])
    }

    func testCombinedConfigurationRejectsProfilesWhenBoundariesAreCorrupt() throws {
        let profileRepository = UserDefaultsProfileRepository(defaults: defaults)
        let boundaryRepository = UserDefaultsBoundaryRepository(defaults: defaults)
        let profile = RankFolderProfile(
            folderURL: URL(fileURLWithPath: "/tmp/Saved", isDirectory: true),
            groupBy: .kind,
            sortBy: .name
        )
        try profileRepository.save([profile])
        defaults.set(
            Data("not valid boundary JSON".utf8),
            forKey: UserDefaultsBoundaryRepository.boundariesKey
        )

        XCTAssertEqual(try profileRepository.load().map(\.id), [profile.id])
        XCTAssertThrowsError(
            try StoredFolderConfiguration.load(
                profileRepository: profileRepository,
                boundaryRepository: boundaryRepository
            )
        )
    }

    func testRequestQueueDrainsInOrder() {
        let queue = ApplyRequestQueue(defaults: defaults)
        queue.enqueue(folderURL: URL(fileURLWithPath: "/tmp/A", isDirectory: true))
        queue.enqueue(folderURL: URL(fileURLWithPath: "/tmp/B", isDirectory: true))

        XCTAssertEqual(queue.drain().map(\.folderPath), ["/tmp/A", "/tmp/B"])
        XCTAssertTrue(queue.drain().isEmpty)
    }

    func testRequestQueueIsBounded() {
        let queue = ApplyRequestQueue(defaults: defaults)
        for index in 0..<(ApplyRequestQueue.maximumRequestCount + 5) {
            queue.enqueue(
                folderURL: URL(fileURLWithPath: "/tmp/\(index)", isDirectory: true)
            )
        }

        let requests = queue.drain()
        XCTAssertEqual(requests.count, ApplyRequestQueue.maximumRequestCount)
        XCTAssertEqual(requests.first?.folderPath, "/tmp/5")
    }

    func testRequestQueueCanBeClearedWithoutProcessingRequests() {
        let queue = ApplyRequestQueue(defaults: defaults)
        queue.enqueue(folderURL: URL(fileURLWithPath: "/tmp/A", isDirectory: true))
        queue.enqueue(folderURL: URL(fileURLWithPath: "/tmp/B", isDirectory: true))

        queue.clear()

        XCTAssertTrue(queue.drain().isEmpty)
        XCTAssertNil(defaults.object(forKey: ApplyRequestQueue.requestsKey))
    }
}
