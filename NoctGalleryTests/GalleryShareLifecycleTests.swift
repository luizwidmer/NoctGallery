import XCTest
@testable import NoctGallery

@MainActor
final class GalleryShareLifecycleTests: XCTestCase {
    func testBatchPreviewUsesInspectedOutputsAndBackToEditsRemovesAllFiles() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        model.beginShare(fixture.items)
        await model.prepareShares(assets: fixture.items, configuration: .init(), profile: nil)
        XCTAssertNil(model.errorMessage)
        let payload = try XCTUnwrap(model.sharePayload)
        XCTAssertEqual(payload.items.count, 2)
        for item in payload.items {
            XCTAssertEqual(item.inspection.width, 480)
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
        }
        XCTAssertTrue(model.hasTemporaryShareFiles)
        await model.editShareAgain()
        XCTAssertNil(model.sharePayload)
        XCTAssertNotNil(model.shareRequest)
        XCTAssertFalse(model.hasTemporaryShareFiles)
        for item in payload.items { XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path)) }
        await model.lockPrivate()
        XCTAssertTrue(model.organization.items.isEmpty)
    }

    func testDismissedBindingCancelsInflightBatchWithoutOrphanFiles() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let assets = Array(repeating: fixture.items[0], count: 20)
        model.beginShare(assets)
        let conversion = Task { await model.prepareShares(assets: assets, configuration: .init(), profile: nil) }
        for _ in 0..<100 where !model.isProcessing { await Task.yield() }
        XCTAssertTrue(model.isProcessing)
        // SwiftUI clears its sheet binding before invoking onDismiss.
        model.shareRequest = nil
        model.finishShare()
        await conversion.value
        XCTAssertNil(model.sharePayload)
        XCTAssertFalse(model.isProcessing)
        XCTAssertTrue(try files(fixture.root.appendingPathComponent("exports")).isEmpty)
        XCTAssertTrue(try files(fixture.root.appendingPathComponent("work")).isEmpty)
    }

    func testSecondItemFailureRemovesFirstExport() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanup() }
        let model = fixture.model
        let session = try await fixture.store.currentSession()
        let bad = fixture.root.appendingPathComponent("bad.jpg")
        try Data([0, 1, 2]).write(to: bad)
        let record = try await fixture.store.save(file: bad, fileExtension: "jpg", kind: .photo,
            width: 1, height: 1, duration: 0, thumbnail: Data(), profile: nil, session: session)
        model.beginShare([fixture.items[0], record])
        await model.prepareShares(assets: [fixture.items[0], record], configuration: .init(), profile: nil)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.sharePayload)
        XCTAssertTrue(try files(fixture.root.appendingPathComponent("exports")).isEmpty)
        XCTAssertTrue(try files(fixture.root.appendingPathComponent("work")).isEmpty)
    }

    @MainActor private struct Fixture {
        let model: GalleryViewModel
        let store: PrivateMediaStore
        let items: [PhotoAssetRecord]
        let root: URL
        let settings: GallerySettingsStore
        let defaults: UserDefaults
        let suite: String
        func cleanup() { try? FileManager.default.removeItem(at: root); try? settings.purge(); defaults.removePersistentDomain(forName: suite) }
    }

    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryShareTests-" + UUID().uuidString)
        try MediaFileProtection.prepareDirectory(root)
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let credentials = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await credentials.configure(mode: .off, pin: "", keys: [])
        let suite = "GalleryShareTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = GallerySettingsStore(service: suite, defaults: defaults)
        let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: root.appendingPathComponent("exports")),
            privateStore: store, workStore: MediaWorkStore(root: root.appendingPathComponent("work")), defaults: defaults,
            lock: GalleryLockController(store: credentials), preferencesDomain: suite, settingsStore: settings)
        await model.start()
        let unlocked = await model.unlockPrivate()
        XCTAssertTrue(unlocked)
        let session = try await store.currentSession()
        var items: [PhotoAssetRecord] = []
        for index in 0..<2 {
            let data = try GalleryDuressPractice.sampleImage(index: index)
            let source = root.appendingPathComponent("source-\(index).png")
            try data.write(to: source)
            items.append(try await store.save(file: source, fileExtension: "png", kind: .photo,
                width: 480, height: 320, duration: 0, thumbnail: data, profile: nil, session: session))
        }
        return Fixture(model: model, store: store, items: items, root: root, settings: settings, defaults: defaults, suite: suite)
    }

    private func files(_ directory: URL) throws -> [String] {
        FileManager.default.fileExists(atPath: directory.path) ? try FileManager.default.contentsOfDirectory(atPath: directory.path) : []
    }
}
