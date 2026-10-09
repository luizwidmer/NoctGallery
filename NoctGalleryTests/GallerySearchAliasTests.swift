import XCTest
@testable import NoctGallery

@MainActor
final class GallerySearchAliasTests: XCTestCase {
    func testReleasedVaultDefaultsAndCustomSynonymsApplyImmediately() throws {
        let old = Data("{\"version\":1,\"albums\":[],\"items\":{}}".utf8)
        var organization = try JSONDecoder().decode(GalleryOrganization.self, from: old).validated()
        XCTAssertNil(organization.searchAliasGroups); XCTAssertNil(organization.aiQueryInterpretationEnabled)
        try GalleryVisualSearch.validateAliasGroups(organization.effectiveSearchAliasGroups)
        let id = UUID().uuidString.lowercased()
        organization.visualSearchEnabled = true
        organization.items[id] = .init(visualTags: [.init(label: "sunglasses", confidence: 0.8)])
        XCTAssertFalse(organization.matches("shades", id: id))
        organization.searchAliasGroups = organization.effectiveSearchAliasGroups + [.init(terms: ["sunglasses", "shades", "óculos de sol"])]
        organization = try organization.validated()
        for query in ["shades", "ÓCULOS DE SOL", "show me my sunglasses"] { XCTAssertTrue(organization.matches(query, id: id), query) }
        for query in ["coffee", "shades dog"] { XCTAssertFalse(organization.matches(query, id: id), query) }
        let matcher = organization.searchMatcher
        XCTAssertTrue(organization.matches("shades", id: id, using: matcher))
        organization.searchAliasGroups = []
        XCTAssertFalse(organization.matches("shades", id: id)); XCTAssertTrue(organization.matches("sunglasses", id: id))
        organization.visualSearchEnabled = false
        XCTAssertFalse(organization.matches("sunglasses", id: id))
    }

    func testInvalidConflictingAndExcessiveSynonymsAreRejected() throws {
        XCTAssertEqual(try GallerySearchAliasGroup.parse(" coffee, café, cafe, COFFEE "), ["coffee", "café"])
        for value in ["", "dog", "dog, !!!", "dog, the", "dog, private\u{0}", "dog, " + String(repeating: "a", count: 81), (0..<13).map { "word\($0)" }.joined(separator: ",")] {
            XCTAssertThrowsError(try GallerySearchAliasGroup.parse(value), value)
        }
        let original = GallerySearchAliasGroup(terms: ["dog", "puppy"])
        XCTAssertThrowsError(try GalleryVisualSearch.validateAliasGroups([original, .init(terms: ["DOG", "canine"])]))
        XCTAssertThrowsError(try GalleryVisualSearch.validateAliasGroups([original, original]))
        XCTAssertThrowsError(try GalleryVisualSearch.validateAliasGroups((0..<101).map { .init(terms: ["label\($0)", "alias\($0)"]) }))
        var organization = GalleryOrganization(); organization.searchAliasGroups = [.init(terms: ["dog", "DOG"])]
        XCTAssertThrowsError(try organization.validated())
    }

    func testEncryptedEditsRemovalRestoreAndOptOutPreservePhotosAndTags() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryAliases-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try MediaFileProtection.prepareDirectory(root)
        let source = root.appendingPathComponent("source.jpg"); try Data("fictional photo bytes".utf8).write(to: source)
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        _ = try await store.unlock()
        let session = try await store.currentSession()
        let photo = try await store.save(file: source, fileExtension: "jpg", kind: .photo, width: 1, height: 1, duration: 0,
            thumbnail: Data(), profile: nil, session: session)
        _ = try await store.setVisualSearch(enabled: true, session: session)
        let tags = [GalleryVisualTag(label: "headphones", confidence: 0.9)]
        _ = try await store.setVisualTags(id: photo.id, tags: tags, session: session)
        let initial = try await store.organization()
        var headphones = try XCTUnwrap(initial.effectiveSearchAliasGroups.first { $0.terms.contains("headphones") })
        headphones.terms = ["headphones", "private-cans-canary"]
        let changed = try await store.editSearchAliases(.save(headphones, replacing: headphones.id), session: session)
        XCTAssertTrue(changed.matches("private cans canary", id: photo.id)); XCTAssertFalse(changed.matches("headset", id: photo.id))
        XCTAssertEqual(changed.items[photo.id]?.visualTags, tags)
        let preference = try await store.setAIQueryInterpretation(enabled: false, session: session)
        XCTAssertFalse(preference.aiQueryInterpretationEnabled ?? true)
        let sealed = try Data(contentsOf: root.appendingPathComponent("vault/organization.sealed"))
        for marker in ["private-cans-canary", "searchAliasGroups", "aiQueryInterpretationEnabled"] { XCTAssertNil(sealed.range(of: Data(marker.utf8))) }
        await store.lock(); _ = try await store.unlock()
        let opened = try await store.organization()
        XCTAssertTrue(opened.matches("private cans canary", id: photo.id)); XCTAssertEqual(opened.searchAliasGroups, changed.searchAliasGroups)
        let current = try await store.currentSession()
        do { _ = try await store.editSearchAliases(.restoreDefaults, session: session); XCTFail("Old session changed aliases") } catch is CancellationError { }
        let removed = try await store.editSearchAliases(.delete(headphones.id), session: current)
        XCTAssertFalse(removed.matches("private cans canary", id: photo.id)); XCTAssertTrue(removed.matches("headphones", id: photo.id))
        do { _ = try await store.editSearchAliases(.save(headphones, replacing: headphones.id), session: current); XCTFail("Late edit resurrected deleted aliases") } catch GallerySearchAliasError.missingGroup { }
        let restored = try await store.editSearchAliases(.restoreDefaults, session: current)
        XCTAssertNil(restored.searchAliasGroups); XCTAssertTrue(restored.matches("headset", id: photo.id))
        XCTAssertEqual(restored.items[photo.id]?.visualTags, tags)
        _ = try await store.editSearchAliases(.save(.init(terms: ["sunglasses", "shades"])), session: current)
        let disabled = try await store.setVisualSearch(enabled: false, session: current)
        XCTAssertNotNil(disabled.searchAliasGroups, "User-authored synonyms are kept like other user metadata")
        let remaining = try await store.list(); XCTAssertEqual(remaining.map(\.id), [photo.id])
        await store.lock()
        do { _ = try await store.editSearchAliases(.restoreDefaults, session: current); XCTFail("Locked aliases were editable") } catch { }
    }
}
