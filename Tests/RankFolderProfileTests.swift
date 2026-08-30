import Foundation
import XCTest
@testable import RankFolderCore

final class RankFolderProfileTests: XCTestCase {
    func testVersionFourRecipeRoundTripsWithoutLegacyKeys() throws {
        let recipe = OrganizationRecipe(
            sections: [
                OrganizationLevel(criterion: .kind, direction: .ascending),
                OrganizationLevel(criterion: .dateModified, direction: .descending)
            ],
            itemOrder: [
                OrganizationLevel(criterion: .size, direction: .descending),
                OrganizationLevel(criterion: .name, direction: .ascending)
            ]
        )
        let profile = RankFolderProfile(
            id: UUID(uuidString: "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA")!,
            folderURL: URL(fileURLWithPath: "/Users/example/Research", isDirectory: true),
            recipe: recipe
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(RankFolderProfile.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.schemaVersion, 4)
        XCTAssertEqual(decoded.descendantScope, .exactFolder)
        XCTAssertFalse(json.contains("recipeMode"))
        XCTAssertFalse(json.contains("advancedRules"))
        XCTAssertFalse(json.contains("groupBy"))
        XCTAssertFalse(json.contains("sortBy"))
    }

    func testFutureSchemaIsRejectedInsteadOfSilentlyDowngraded() throws {
        let json = """
        {
          "schemaVersion": 99,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "/Users/example/Future",
          "displayName": "Future",
          "recipe": {
            "sections": [],
            "itemOrder": [{"id":"11111111-1111-1111-1111-111111111111","criterion":"name"}]
          },
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RankFolderProfile.self,
                from: Data(json.utf8)
            )
        )
    }

    func testInvalidZeroSchemaIsRejected() {
        let json = """
        {
          "schemaVersion": 0,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "/Users/example/Invalid",
          "displayName": "Invalid",
          "groupBy": "none",
          "sortBy": "name",
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RankFolderProfile.self,
                from: Data(json.utf8)
            )
        )
    }

    func testVersionOneFinderProfileMigratesToCanonicalRecipe() throws {
        let profile = try decodeLegacy("""
        {
          "schemaVersion": 1,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "/Users/example/Research",
          "displayName": "Research",
          "groupBy": "kind",
          "sortBy": "dateModified",
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """)

        XCTAssertEqual(profile.recipe.sections.map(\.criterion), [.kind])
        XCTAssertEqual(profile.recipe.itemOrder.map(\.criterion), [.dateModified])
        XCTAssertNil(profile.recipe.sections.first?.direction)
        XCTAssertNil(profile.recipe.itemOrder.first?.direction)
        XCTAssertEqual(
            profile.finderRepresentation,
            FinderRecipeRepresentation(groupBy: .kind, sortBy: .dateModified)
        )
        XCTAssertEqual(profile.descendantScope, .exactFolder)
        XCTAssertNil(profile.folderBookmarkData)
        XCTAssertFalse(profile.canSafelyReadFolderMetadata)
    }

    func testVersionThreeMigratesToExactScopeWithoutBookmark() throws {
        let profile = try decodeLegacy("""
        {
          "schemaVersion": 3,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "/Users/example/Research",
          "displayName": "Research",
          "recipe": {
            "sections": [],
            "itemOrder": [{"id":"11111111-1111-1111-1111-111111111111","criterion":"name"}]
          },
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """)

        XCTAssertEqual(profile.schemaVersion, 4)
        XCTAssertEqual(profile.descendantScope, .exactFolder)
        XCTAssertNil(profile.folderBookmarkData)
    }

    func testVersionFourDescendantBookmarkRoundTripsAndRefreshes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RankFolderBookmark-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var profile = RankFolderProfile(
            folderURL: folder,
            descendantScope: .descendants
        )
        XCTAssertNotNil(profile.folderBookmarkData)
        XCTAssertTrue(profile.canSafelyReadFolderMetadata)
        let decoded = try JSONDecoder().decode(
            RankFolderProfile.self,
            from: JSONEncoder().encode(profile)
        )
        XCTAssertEqual(decoded, profile)

        profile.folderBookmarkData = nil
        try profile.refreshFolderReference()
        XCTAssertNotNil(profile.folderBookmarkData)
        XCTAssertTrue(profile.hasOriginalFolderIdentity)
    }

    func testVersionOneNoGroupMigratesToNoSections() throws {
        let profile = try decodeLegacy("""
        {
          "schemaVersion": 1,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "/Users/example/Research",
          "displayName": "Research",
          "groupBy": "none",
          "sortBy": "name",
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """)

        XCTAssertTrue(profile.recipe.sections.isEmpty)
        XCTAssertEqual(profile.recipe.itemOrder.map(\.criterion), [.name])
        XCTAssertNotNil(profile.finderRepresentation)
    }

    func testVersionTwoFinderMigrationIgnoresUnusedAdvancedDefaults() throws {
        let profile = try decodeLegacy("""
        {
          "schemaVersion": 2,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "/Users/example/Downloads",
          "displayName": "Downloads",
          "groupBy": "name",
          "sortBy": "size",
          "recipeMode": "finder",
          "advancedRules": [
            {"id":"11111111-1111-1111-1111-111111111111","behavior":"group","criterion":"kind","direction":"ascending"},
            {"id":"22222222-2222-2222-2222-222222222222","behavior":"group","criterion":"dateModified","direction":"descending"},
            {"id":"33333333-3333-3333-3333-333333333333","behavior":"sort","criterion":"name","direction":"ascending"}
          ],
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """)

        XCTAssertEqual(profile.recipe.sections.map(\.criterion), [.name])
        XCTAssertEqual(profile.recipe.itemOrder.map(\.criterion), [.size])
        XCTAssertEqual(profile.recipe.levelCount, 2)
    }

    func testVersionTwoAdvancedMigrationPreservesLevelsIDsAndDirections() throws {
        let profile = try decodeLegacy("""
        {
          "schemaVersion": 2,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "/Users/example/Research",
          "displayName": "Research",
          "groupBy": "none",
          "sortBy": "name",
          "recipeMode": "advanced",
          "advancedRules": [
            {"id":"11111111-1111-1111-1111-111111111111","behavior":"group","criterion":"kind","direction":"ascending"},
            {"id":"22222222-2222-2222-2222-222222222222","behavior":"group","criterion":"dateModified","direction":"descending"},
            {"id":"33333333-3333-3333-3333-333333333333","behavior":"sort","criterion":"size","direction":"descending"},
            {"id":"44444444-4444-4444-4444-444444444444","behavior":"sort","criterion":"name","direction":"ascending"}
          ],
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """)

        XCTAssertEqual(profile.recipe.sections.map(\.criterion), [.kind, .dateModified])
        XCTAssertEqual(profile.recipe.sections.map(\.direction), [.ascending, .descending])
        XCTAssertEqual(profile.recipe.itemOrder.map(\.criterion), [.size, .name])
        XCTAssertEqual(
            profile.recipe.sections.first?.id,
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        XCTAssertTrue(profile.requiresOrganizedView)
    }

    func testFinderRepresentationRequiresTheWholeRecipeToFit() {
        let folder = URL(fileURLWithPath: "/tmp/Folder", isDirectory: true)
        let simple = RankFolderProfile(
            folderURL: folder,
            recipe: OrganizationRecipe(
                sections: [OrganizationLevel(criterion: .kind)],
                itemOrder: [OrganizationLevel(criterion: .name)]
            )
        )
        XCTAssertEqual(simple.finderRepresentation?.groupBy, .kind)
        XCTAssertEqual(simple.finderRepresentation?.sortBy, .name)

        let extraSection = RankFolderProfile(
            folderURL: folder,
            recipe: OrganizationRecipe(
                sections: [
                    OrganizationLevel(criterion: .kind),
                    OrganizationLevel(criterion: .dateModified)
                ],
                itemOrder: [OrganizationLevel(criterion: .name)]
            )
        )
        XCTAssertNil(extraSection.finderRepresentation)

        let requestedDirection = RankFolderProfile(
            folderURL: folder,
            recipe: OrganizationRecipe(
                itemOrder: [OrganizationLevel(criterion: .name, direction: .ascending)]
            )
        )
        XCTAssertNil(requestedDirection.finderRepresentation)

        let extensionRule = RankFolderProfile(
            folderURL: folder,
            recipe: OrganizationRecipe(
                sections: [OrganizationLevel(criterion: .fileExtension)],
                itemOrder: [OrganizationLevel(criterion: .name)]
            )
        )
        XCTAssertNil(extensionRule.finderRepresentation)

        let tieBreaker = RankFolderProfile(
            folderURL: folder,
            recipe: OrganizationRecipe(
                itemOrder: [
                    OrganizationLevel(criterion: .dateModified),
                    OrganizationLevel(criterion: .name)
                ]
            )
        )
        XCTAssertNil(tieBreaker.finderRepresentation)
    }

    func testRecipeNormalizesAnEmptyOrderAndCapsLevels() {
        let tooMany = (0..<20).map { _ in OrganizationLevel(criterion: .name) }
        let recipe = OrganizationRecipe(sections: tooMany, itemOrder: [])

        XCTAssertEqual(recipe.sections.count, OrganizationRecipe.maximumLevelsPerArea)
        XCTAssertEqual(recipe.itemOrder.map(\.criterion), [.name])
    }

    func testFriendlyLabelsDoNotChangeFinderEnglishMenuTitles() {
        XCTAssertEqual(GroupCriterion.kind.displayName, "File type")
        XCTAssertEqual(GroupCriterion.kind.finderMenuTitle, "Kind")
        XCTAssertEqual(SortCriterion.dateModified.displayName, "Last modified")
        XCTAssertEqual(SortCriterion.dateModified.finderMenuTitle, "Date Modified")
    }

    func testPathNormalizationRemovesOnlyTrailingSlash() {
        XCTAssertEqual(
            RankFolderProfile.normalizedPath(
                for: URL(fileURLWithPath: "/Users/example/Research/", isDirectory: true)
            ),
            "/Users/example/Research"
        )
        XCTAssertEqual(
            RankFolderProfile.normalizedPath(for: URL(fileURLWithPath: "/", isDirectory: true)),
            "/"
        )
    }

    func testExactFolderMatchingDoesNotImplyInheritance() {
        let profile = RankFolderProfile(
            folderURL: URL(fileURLWithPath: "/Users/example/Research", isDirectory: true)
        )
        XCTAssertTrue(profile.matches(
            folderURL: URL(fileURLWithPath: "/Users/example/Research", isDirectory: true)
        ))
        XCTAssertFalse(profile.matches(
            folderURL: URL(fileURLWithPath: "/Users/example/Research/Child", isDirectory: true)
        ))
    }

    func testDisabledProfileStillRetainsItsSavedIdentity() {
        let profile = RankFolderProfile(
            folderURL: URL(fileURLWithPath: "/Users/example/Research", isDirectory: true),
            isEnabled: false
        )

        XCTAssertFalse(profile.isEnabled)
        XCTAssertTrue(profile.matches(folderURL: profile.folderURL))
    }

    func testMatchingRecognizesSymbolicLinkToSameFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RankFolderIdentity-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let alias = root.appendingPathComponent("Folder Alias", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)

        let profile = RankFolderProfile(folderURL: folder)
        XCTAssertTrue(profile.matches(folderURL: alias))
    }

    func testSavedIdentityRejectsAReplacementAtTheSamePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RankFolderReplacement-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let profile = RankFolderProfile(folderURL: folder)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertFalse(profile.hasOriginalFolderIdentity)
        XCTAssertFalse(profile.canSafelyReadFolderMetadata)
        XCTAssertFalse(profile.matches(folderURL: folder))
    }

    func testSavedIdentityRoundTripsForAnExistingFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RankFolderIdentityRoundTrip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let profile = RankFolderProfile(folderURL: root)
        let decoded = try JSONDecoder().decode(
            RankFolderProfile.self,
            from: JSONEncoder().encode(profile)
        )

        XCTAssertNotNil(decoded.folderResourceIdentifier)
        XCTAssertTrue(decoded.hasOriginalFolderIdentity)
        XCTAssertTrue(decoded.canSafelyReadFolderMetadata)
        XCTAssertTrue(decoded.matches(folderURL: root))
    }

    func testRelativeStoredPathIsRejected() {
        let json = """
        {
          "schemaVersion": 4,
          "id": "90D2C59F-C73D-49E8-91CB-4F6CDA9E0EAA",
          "folderPath": "Relative/Downloads",
          "displayName": "Downloads",
          "recipe": {
            "sections": [],
            "itemOrder": [{"id":"11111111-1111-1111-1111-111111111111","criterion":"name"}]
          },
          "isEnabled": true,
          "createdAt": 0,
          "updatedAt": 0
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RankFolderProfile.self,
                from: Data(json.utf8)
            )
        )
    }

    func testIdentityFailsWhenTheStoredIdentifierDisagreesWithTheFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RankFolderIdentityDisagreement-\(UUID().uuidString)",
                isDirectory: true
            )
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RankFolderIdentityOther-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        var profile = RankFolderProfile(folderURL: root)
        XCTAssertNotNil(profile.folderBookmarkData)
        XCTAssertTrue(profile.hasOriginalFolderIdentity)

        // A bookmark that still resolves to this path is no longer enough. The
        // recorded identifier belongs to a different folder, which is what a
        // folder replaced at the same path looks like.
        profile.folderResourceIdentifier = RankFolderProfile.archivedResourceIdentifier(
            for: other
        )
        XCTAssertFalse(profile.hasOriginalFolderIdentity)
        XCTAssertFalse(profile.canSafelyReadFolderMetadata)
    }

    private func decodeLegacy(_ json: String) throws -> RankFolderProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(RankFolderProfile.self, from: Data(json.utf8))
    }
}
