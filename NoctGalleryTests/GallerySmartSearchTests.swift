import ImageIO
import UIKit
import XCTest
@testable import NoctGallery

@MainActor
final class GallerySmartSearchTests: XCTestCase {
    func testContextQueriesCombineDetectedObjectsWithNotesAndRespectOptOut() throws {
        let id = UUID().uuidString.lowercased()
        var organization = GalleryOrganization()
        organization.visualSearchEnabled = true
        organization.items[id] = .init(tags: ["travel"], notes: "Coffee before the flight",
            visualTags: [.init(label: "headphones", confidence: 0.95), .init(label: "coffee", confidence: 0.8)])
        for query in ["headphones", "HEADSET", "show me my headphones", "fones de ouvido", "headphones with coffee", "headphones travel", "café"] {
            XCTAssertTrue(organization.matches(query, id: id), query)
        }
        for query in ["headphones dog", "phone", "ear", "mountain"] { XCTAssertFalse(organization.matches(query, id: id), query) }
        organization.visualSearchEnabled = false
        XCTAssertFalse(organization.matches("headphones", id: id))
        XCTAssertTrue(organization.matches("flight", id: id))
        XCTAssertTrue(organization.matches("travel", id: id))
        XCTAssertTrue(organization.matches("", id: id))
    }

    func testExistingVaultsDecodeAndInvalidTagsCannotEnterEncryptedIndex() throws {
        let id = UUID().uuidString.lowercased()
        let data = Data("{\"version\":1,\"albums\":[],\"items\":{\"\(id)\":{\"favorite\":false,\"albumIDs\":[],\"tags\":[\"legacy\"]}}}".utf8)
        let old = try JSONDecoder().decode(GalleryOrganization.self, from: data).validated()
        XCTAssertNil(old.visualSearchEnabled); XCTAssertNil(old.items[id]?.visualTags)
        XCTAssertTrue(old.matches("legacy", id: id))
        let invalid: [[GalleryVisualTag]] = [
            [.init(label: "headphones", confidence: .nan)], [.init(label: "headphones", confidence: 1.01)],
            [.init(label: "\nprivate", confidence: 0.8)], [.init(label: "", confidence: 0.8)],
            [.init(label: "Headphones", confidence: 0.8), .init(label: "headphones", confidence: 0.7)],
            (0..<25).map { .init(label: "label \($0)", confidence: 0.8) }
        ]
        for tags in invalid {
            var value = old; value.items[id]?.visualTags = tags
            XCTAssertThrowsError(try value.validated())
        }
    }

    func testRealOnDeviceClassifierFindsHeadphonesWithoutTextOrManualTags() async throws {
        let image = try headphoneImage()
        let tags = try await Task.detached { try GalleryLocalAnalysis.visualTags(in: image) }.value
        let headphones = try XCTUnwrap(tags.first { $0.label == "headphones" }, "Actual Vision labels: \(tags.map(\.label))")
        XCTAssertGreaterThanOrEqual(headphones.confidence, 0.15)
        XCTAssertTrue(tags.allSatisfy(\.isValid)); XCTAssertLessThanOrEqual(tags.count, 24)
        XCTAssertTrue(GalleryVisualSearch.matches("headphones", text: "", tags: tags))
        XCTAssertTrue(GalleryVisualSearch.matches("headset", text: "", tags: tags))
    }

    func testRealClassifierFindsDiverseObjectsAndRejectsUnrelatedContext() async throws {
        let cases: [(photo: String, positive: [String], negative: [String])] = [
            ("dog", ["dog", "puppy", "cachorro", "show me my dog"], ["bicycle", "headphones", "laptop", "coffee"]),
            ("bicycle", ["bicycle", "bike", "bicicleta"], ["dog", "headphones", "coffee", "laptop"]),
            ("laptop", ["laptop", "computer", "computador"], ["dog", "bicycle", "coffee", "headphones"]),
            ("coffee", ["coffee", "café", "croissant", "coffee with croissant"], ["headphones", "dog", "bicycle", "sunglasses"]),
            ("sunglasses", ["sunglasses"], ["headphones", "coffee", "dog", "bicycle"]),
            ("lake", ["lake", "water", "mountains", "lake with mountains"], ["headphones", "laptop", "coffee", "dog"]),
            ("headphones", ["headphones", "plant", "headphones with plant"], ["dog", "coffee", "bicycle", "laptop"]),
            ("portrait", ["people", "plant", "people with plant"], ["headphones", "dog", "bicycle", "laptop"])
        ]
        var actual: [String: [GalleryVisualTag]] = [:]
        for sample in cases {
            let image = try fixtureImage(sample.photo)
            let tags = try await Task.detached { try GalleryLocalAnalysis.visualTags(in: image) }.value
            actual[sample.photo] = tags
            XCTAssertTrue(tags.allSatisfy(\.isValid)); XCTAssertLessThanOrEqual(tags.count, 24)
            let id = UUID().uuidString.lowercased()
            var organization = GalleryOrganization()
            organization.visualSearchEnabled = true
            organization.items[id] = .init(visualTags: tags)
            for query in sample.positive {
                XCTAssertTrue(organization.matches(query, id: id), "\(sample.photo): expected \(query); actual \(tags.map(\.label))")
            }
            for query in sample.negative {
                XCTAssertFalse(organization.matches(query, id: id), "\(sample.photo): unrelated \(query) matched actual \(tags.map(\.label))")
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(actual), uniformTypeIdentifier: "public.json")
        attachment.name = "diverse-object-classifications"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAITagsAreEncryptedSurviveReopenAndOptOutKeepsUserMetadata() async throws {
        let fixture = try await makeFixture(); defer { fixture.cleanup() }
        let (store, item) = (fixture.store, try await savePhoto(fixture))
        let session = try await store.currentSession()
        _ = try await store.organize(ids: [item.id], edit: .tags(["my-tag"]), session: session)
        _ = try await store.organize(ids: [item.id], edit: .description(caption: "My photo", notes: "My notes"), session: session)
        _ = try await store.setVisualSearch(enabled: true, session: session)
        _ = try await store.setVisualTags(id: item.id, tags: [.init(label: "headphones", confidence: 0.95)], session: session)
        let sealed = try Data(contentsOf: fixture.root.appendingPathComponent("vault/organization.sealed"))
        for text in ["headphones", "visualTags", "My notes", "my-tag"] { XCTAssertNil(sealed.range(of: Data(text.utf8))) }
        await store.lock()
        do { _ = try await store.organization(); XCTFail("Locked AI index was accessible") } catch PrivateMediaStore.StoreError.locked { }
        _ = try await store.unlock()
        let opened = try await store.organization()
        XCTAssertTrue(opened.matches("headphones", id: item.id))
        let disabled = try await store.setVisualSearch(enabled: false, session: store.currentSession())
        XCTAssertNil(disabled.items[item.id]?.visualTags)
        XCTAssertFalse(disabled.matches("headphones", id: item.id))
        XCTAssertEqual(disabled.items[item.id]?.tags, ["my-tag"])
        XCTAssertEqual(disabled.items[item.id]?.notes, "My notes")
        let manifest = try await store.resources(id: item.id)
        XCTAssertFalse(manifest.isEmpty, "Opting out must preserve the original")
    }

    func testStaleDisabledDeletedAndChangedCropResultsAreRejected() async throws {
        let fixture = try await makeFixture(); defer { fixture.cleanup() }
        let store = fixture.store, item = try await savePhoto(fixture)
        let session = try await store.currentSession(), tags = [GalleryVisualTag(label: "headphones", confidence: 0.9)]
        do { _ = try await store.setVisualTags(id: item.id, tags: tags, session: session); XCTFail("Accepted tags without consent") } catch { }
        _ = try await store.setVisualSearch(enabled: true, session: session)
        _ = try await store.setVisualTags(id: item.id, tags: tags, session: session)
        let recipe = GalleryPhotoEdits(crop: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let edited = try await store.organize(ids: [item.id], edit: .photoEdits(recipe), session: session)
        XCTAssertNil(edited.items[item.id]?.visualTags)
        do { _ = try await store.setVisualTags(id: item.id, tags: tags, session: session); XCTFail("Accepted tags for an outdated crop") } catch { }
        _ = try await store.setVisualTags(id: item.id, tags: tags, photoEdits: recipe, session: session)
        let removed = try await store.organize(ids: [item.id], edit: .removeVisualTag("headphones"), session: session)
        XCTAssertEqual(removed.items[item.id]?.visualTags, [], "Removing a suggestion must not schedule it again automatically")
        do {
            _ = try await store.setVisualTags(id: item.id, tags: tags, photoEdits: recipe, replacing: tags, session: session)
            XCTFail("A late refresh restored a tag the user removed")
        } catch { }
        await store.lock(); _ = try await store.unlock()
        do { _ = try await store.setVisualTags(id: item.id, tags: tags, photoEdits: recipe, session: session); XCTFail("Accepted an old unlock session") } catch is CancellationError { }
        let current = try await store.currentSession()
        try await store.delete(id: item.id, session: current)
        do { _ = try await store.setVisualTags(id: item.id, tags: tags, photoEdits: recipe, session: current); XCTFail("Recreated an index for deleted media") } catch { }
        let final = try await store.organization(); XCTAssertNil(final.items[item.id])
    }

    func testNewImportsAreAutomaticallyTaggedAndLockCancelsRefresh() async throws {
        let fixture = try await makeFixture(); defer { fixture.cleanup() }
        await fixture.store.lock()
        let credentials = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await credentials.configure(mode: .off, pin: "", keys: [])
        let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: fixture.root.appendingPathComponent("exports")),
            privateStore: fixture.store, workStore: MediaWorkStore(root: fixture.root.appendingPathComponent("work")),
            defaults: fixture.defaults, lock: GalleryLockController(store: credentials), preferencesDomain: fixture.suite, settingsStore: fixture.settings)
        await model.start()
        let unlocked = await model.unlockPrivate(); XCTAssertTrue(unlocked)
        await model.setVisualSearch(true)
        await model.importFiles([try headphoneURL()])
        XCTAssertEqual(model.privateAssets.count, 1, model.errorMessage ?? "Import failed")
        for _ in 0..<400 {
            if model.untaggedPhotoCount == 0 && !model.isAnalyzing { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.untaggedPhotoCount, 0, model.errorMessage ?? "Automatic indexing did not finish")
        let id = try XCTUnwrap(model.privateAssets.first?.id)
        XCTAssertTrue(model.organization.matches("headphones", id: id))
        model.indexVisualTags(ids: [id], refresh: true)
        XCTAssertTrue(model.isTagging)
        await model.lockPrivate()
        XCTAssertFalse(model.privateUnlocked); XCTAssertFalse(model.isAnalyzing); XCTAssertFalse(model.isTagging)
        XCTAssertTrue(model.privateAssets.isEmpty); XCTAssertTrue(model.organization.items.isEmpty)
        model.lock.activate()
        let reopened = await model.unlockPrivate(); XCTAssertTrue(reopened)
        XCTAssertTrue(model.organization.matches("headphones", id: id), "Lock must preserve completed encrypted tags")
        model.indexVisualTags(ids: [id], refresh: true)
        await model.setVisualSearch(false)
        XCTAssertFalse(model.isAnalyzing); XCTAssertNil(model.organization.items[id]?.visualTags)
        XCTAssertFalse(model.organization.matches("headphones", id: id))
        await model.lockPrivate()
    }

    private struct Fixture {
        let root: URL; let store: PrivateMediaStore; let suite: String; let defaults: UserDefaults; let settings: GallerySettingsStore
        @MainActor func cleanup() { try? FileManager.default.removeItem(at: root); try? settings.purge(); defaults.removePersistentDomain(forName: suite) }
    }
    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryAI-" + UUID().uuidString)
        try MediaFileProtection.prepareDirectory(root)
        let suite = "GalleryAI-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        _ = try await store.unlock()
        return .init(root: root, store: store, suite: suite, defaults: defaults, settings: GallerySettingsStore(service: suite, defaults: defaults))
    }
    private func savePhoto(_ fixture: Fixture) async throws -> PhotoAssetRecord {
        let data = try Data(contentsOf: headphoneURL()), source = fixture.root.appendingPathComponent("photo.jpg")
        try data.write(to: source)
        return try await fixture.store.save(file: source, fileExtension: "jpg", kind: .photo, width: 1_024, height: 1_024,
            duration: 0, thumbnail: data, profile: nil, session: fixture.store.currentSession())
    }
    private func headphoneURL() throws -> URL { try XCTUnwrap(Bundle(for: Self.self).url(forResource: "headphones", withExtension: "jpg")) }
    private func headphoneImage() throws -> CGImage {
        try fixtureImage("headphones")
    }
    private func fixtureImage(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}
