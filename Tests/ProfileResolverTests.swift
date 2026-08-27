import Foundation
import XCTest
@testable import RankFolderCore

final class ProfileResolverTests: XCTestCase {
    func testExactEnabledProfileWinsAndKeepsTargetSeparate() async {
        let exact = profile("/Rules/Exact", scope: .exactFolder)
        let parent = profile("/Rules", scope: .descendants)
        let checker = MockRelationshipChecker(relationships: [
            exact.folderPath: .same,
            parent.folderPath: .ancestor(distance: 1)
        ])

        let result = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [parent, exact]
        )

        guard case .resolved(let layout) = result else {
            return XCTFail("Expected an exact resolution")
        }
        XCTAssertEqual(layout.sourceProfile.id, exact.id)
        XCTAssertEqual(layout.targetFolderURL, checker.targetURL)
        XCTAssertEqual(layout.origin, .exact)
    }

    func testNearestVerifiedDescendantProfileWins() async {
        let near = profile("/Rules/Near", scope: .descendants)
        let far = profile("/Rules", scope: .descendants)
        let checker = MockRelationshipChecker(relationships: [
            near.folderPath: .ancestor(distance: 1),
            far.folderPath: .ancestor(distance: 2)
        ])

        let result = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [far, near]
        )

        guard case .resolved(let layout) = result else {
            return XCTFail("Expected inherited resolution")
        }
        XCTAssertEqual(layout.sourceProfile.id, near.id)
        XCTAssertEqual(layout.origin, .inherited(distance: 1))
    }

    func testEnabledExactOnlyAncestorIsTransparent() async {
        let exactOnly = profile("/Rules/Near", scope: .exactFolder)
        let inheritable = profile("/Rules", scope: .descendants)
        let checker = MockRelationshipChecker(relationships: [
            exactOnly.folderPath: .ancestor(distance: 1),
            inheritable.folderPath: .ancestor(distance: 2)
        ])

        let result = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [exactOnly, inheritable]
        )
        guard case .resolved(let layout) = result else {
            return XCTFail("Expected farther inherited resolution")
        }
        XCTAssertEqual(layout.sourceProfile.id, inheritable.id)
    }

    func testDisabledProfileBlocksHigherSource() async {
        var disabled = profile("/Rules/Near", scope: .exactFolder)
        disabled.isEnabled = false
        let far = profile("/Rules", scope: .descendants)
        let checker = MockRelationshipChecker(relationships: [
            disabled.folderPath: .ancestor(distance: 1),
            far.folderPath: .ancestor(distance: 2)
        ])

        let result = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [disabled, far]
        )
        XCTAssertEqual(result, .blocked(.disabledProfile(disabled.id)))
    }

    func testBoundaryAndUnavailableProviderBlockHigherSource() async {
        let boundary = FolderInheritanceBoundary(
            folderURL: URL(fileURLWithPath: "/Rules/Near", isDirectory: true)
        )
        let far = profile("/Rules", scope: .descendants)
        var checker = MockRelationshipChecker(relationships: [
            boundary.folderPath: .ancestor(distance: 1),
            far.folderPath: .ancestor(distance: 2)
        ])
        let boundaryResult = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [far],
            boundaries: [boundary]
        )
        XCTAssertEqual(boundaryResult, .blocked(.boundary(boundary.id)))

        checker.relationships = [
            far.folderPath: .unavailableOnBranch(
                distance: 2,
                issue: .providerUnavailable
            )
        ]
        let providerResult = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [far]
        )
        XCTAssertEqual(
            providerResult,
            .blocked(.unavailableProfile(far.id, .providerUnavailable))
        )

        checker.relationships = [
            far.folderPath: .unavailableOnBranch(
                distance: 2,
                issue: .volumeMismatch
            )
        ]
        let volumeResult = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [far]
        )
        XCTAssertEqual(
            volumeResult,
            .blocked(.unavailableProfile(far.id, .volumeMismatch))
        )
    }

    func testDuplicateProfilesAtSameDistanceBlock() async {
        let first = profile("/Rules/A", scope: .descendants)
        let second = profile("/Rules/B", scope: .descendants)
        let checker = MockRelationshipChecker(relationships: [
            first.folderPath: .ancestor(distance: 1),
            second.folderPath: .ancestor(distance: 1)
        ])
        let result = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [first, second]
        )
        guard case .blocked(.duplicateProfiles(let ids)) = result else {
            return XCTFail("Expected duplicate block")
        }
        XCTAssertEqual(Set(ids), Set([first.id, second.id]))
    }

    func testAdvancedNearestRecipeDoesNotFallThrough() async {
        var near = profile("/Rules/Near", scope: .descendants)
        near.recipe = OrganizationRecipe(
            sections: [
                OrganizationLevel(criterion: .kind),
                OrganizationLevel(criterion: .dateModified)
            ]
        )
        let far = profile("/Rules", scope: .descendants)
        let checker = MockRelationshipChecker(relationships: [
            near.folderPath: .ancestor(distance: 1),
            far.folderPath: .ancestor(distance: 2)
        ])
        let result = await SecureProfileResolver(checker: checker).resolve(
            folderURL: checker.targetURL,
            from: [far, near]
        )
        guard case .resolved(let layout) = result else {
            return XCTFail("Expected nearest recipe")
        }
        XCTAssertEqual(layout.sourceProfile.id, near.id)
        XCTAssertTrue(layout.sourceProfile.requiresOrganizedView)
    }

    func testLexicalPathPrefixCannotCreateAnAncestor() {
        XCTAssertNil(ProductionFolderRelationshipChecker.componentDistance(
            ancestor: URL(fileURLWithPath: "/Users/a", isDirectory: true),
            descendant: URL(fileURLWithPath: "/Users/ab/Child", isDirectory: true)
        ))
    }

    func testTargetIdentityRejectsReplacementAtSamePath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RankFolderTarget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let checker = ProductionFolderRelationshipChecker()
        guard case .success(let identity) = await checker.captureTargetIdentity(for: root) else {
            return XCTFail("Expected a live target identity")
        }
        XCTAssertTrue(identity.matchesLiveFolderURL(root))
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertFalse(identity.matchesLiveFolderURL(root))
    }

    func testRevalidationRejectsChangedSourceRevision() async {
        let source = profile("/Rules", scope: .descendants)
        let checker = MockRelationshipChecker(relationships: [
            source.folderPath: .ancestor(distance: 1)
        ])
        let resolver = SecureProfileResolver(checker: checker)
        let initial = await resolver.resolve(
            folderURL: checker.targetURL,
            from: [source]
        )
        guard case .resolved(let layout) = initial else {
            return XCTFail("Expected initial resolution")
        }
        let unchangedIsValid = await resolver.revalidate(layout, from: [source])
        XCTAssertTrue(unchangedIsValid)

        var changed = source
        changed.updatedAt = source.updatedAt.addingTimeInterval(1)
        let changedIsValid = await resolver.revalidate(layout, from: [changed])
        XCTAssertFalse(changedIsValid)
    }

    func testSymlinkEscapeCannotAuthorizeInheritance() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RankFolderEscape-\(UUID().uuidString)",
            isDirectory: true
        )
        let source = base.appendingPathComponent("Source", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        let escape = source.appendingPathComponent("Escape", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)

        let profile = RankFolderProfile(
            folderURL: source,
            descendantScope: .descendants
        )
        let result = await SecureProfileResolver().resolve(
            folderURL: escape,
            from: [profile]
        )
        XCTAssertEqual(result, .none)
    }

    private func profile(
        _ path: String,
        scope: ProfileDescendantScope
    ) -> RankFolderProfile {
        RankFolderProfile(
            folderURL: URL(fileURLWithPath: path, isDirectory: true),
            descendantScope: scope
        )
    }
}

private struct MockRelationshipChecker: FolderRelationshipChecking {
    var relationships: [String: FolderReferenceRelationship]
    var allowsRevalidation = true
    let targetURL = URL(fileURLWithPath: "/Rules/Target", isDirectory: true)

    private var identity: ResolvedFolderIdentity {
        ResolvedFolderIdentity(
            canonicalURL: targetURL,
            bookmarkData: Data([1]),
            resourceIdentifier: Data([2]),
            volumeIdentifier: Data([3]),
            providerLocation: .local
        )
    }

    func captureTargetIdentity(
        for folderURL: URL
    ) async -> Result<ResolvedFolderIdentity, FolderReferenceIssue> {
        .success(identity)
    }

    func relationship(
        of reference: StoredFolderReference,
        to target: ResolvedFolderIdentity
    ) async -> FolderReferenceRelationship {
        relationships[reference.folderPath] ?? .unrelated
    }

    func revalidate(
        _ identity: ResolvedFolderIdentity,
        for folderURL: URL
    ) async -> Bool {
        allowsRevalidation
    }
}
