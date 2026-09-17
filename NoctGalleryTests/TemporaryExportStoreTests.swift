import XCTest
@testable import NoctGallery

final class TemporaryExportStoreTests: XCTestCase {
    func testResetRejectsExportsFromPreviousSessionAndPreservesOutsideFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("original.jpg")
        try Data([9]).write(to: outside)
        let root = directory.appendingPathComponent("exports")
        let store = TemporaryExportStore(rootURL: root)
        let session = await store.currentSession()
        let image = SanitizedImage(data: Data([1]), sourceByteCount: 1, pixelWidth: 1, pixelHeight: 1,
                                   outputUTType: "public.jpeg", fileExtension: "jpg", sha256: "test", removedMetadataKeys: [])
        _ = try await store.write(image, session: session)
        try await store.reset()
        do {
            _ = try await store.write(image, session: session)
            XCTFail("An export started before reset recreated purged data")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data([9]))
    }

    @MainActor
    func testFullResetClearsSettingsAndRestartsOnboarding() async throws {
        let suite = "NoctGalleryResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "onboarding.completed")
        defaults.set("png", forKey: "share.outputFormat")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: root), privateStore: PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys()), workStore: MediaWorkStore(root: root.appendingPathComponent("work")), defaults: defaults, lock: GalleryLockController(store: GalleryLockStore(persistence: MemoryGalleryLockPersistence())))
        let originalGeneration = model.resetGeneration
        await model.purgeAndReset(defaults: defaults, domain: suite)
        XCTAssertNil(defaults.object(forKey: "onboarding.completed"))
        XCTAssertNil(defaults.object(forKey: "share.outputFormat"))
        XCTAssertNotEqual(originalGeneration, model.resetGeneration)
        XCTAssertFalse(model.isResetting)
        XCTAssertNil(model.errorMessage)
    }

    func testExportExistsOnlyUntilExplicitCleanup() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoctGalleryTests-\(UUID().uuidString)", isDirectory: true)
        let store = TemporaryExportStore(rootURL: root)
        let image = SanitizedImage(
            data: Data([0x01, 0x02, 0x03]),
            sourceByteCount: 99,
            pixelWidth: 1,
            pixelHeight: 1,
            outputUTType: "public.jpeg",
            fileExtension: "jpg",
            sha256: "test",
            removedMetadataKeys: []
        )

        let url = try await store.write(image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("shared-"))
        XCTAssertFalse(url.lastPathComponent.contains("original"))
        let filePermissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(filePermissions?.intValue, 0o600)
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)

        try await store.remove(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLaunchPurgeRemovesAbandonedExports() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoctGalleryTests-\(UUID().uuidString)", isDirectory: true)
        let store = TemporaryExportStore(rootURL: root)
        let image = SanitizedImage(
            data: Data([0x01]),
            sourceByteCount: 1,
            pixelWidth: 1,
            pixelHeight: 1,
            outputUTType: "public.png",
            fileExtension: "png",
            sha256: "test",
            removedMetadataKeys: []
        )
        _ = try await store.write(image)

        try await store.purgeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testShareLifecycleRetainsCleanupURLAfterPresentationBindingClears() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoctGalleryTests-\(UUID().uuidString)", isDirectory: true)
        let store = TemporaryExportStore(rootURL: root)
        let image = SanitizedImage(
            data: Data([0x01, 0x02]),
            sourceByteCount: 2,
            pixelWidth: 1,
            pixelHeight: 1,
            outputUTType: "public.jpeg",
            fileExtension: "jpg",
            sha256: "test",
            removedMetadataKeys: []
        )

        let url = try await store.write(image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // SwiftUI clears the item binding before running a sheet's onDismiss
        // callback. The lifecycle retains the exact URL independently.
        var lifecycle = ShareExportLifecycle()
        lifecycle.present(url)
        let cleanupURL = try XCTUnwrap(lifecycle.dismiss())
        XCTAssertNil(lifecycle.dismiss())
        try await store.remove(cleanupURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCleanupRejectsNestedSymlinkEscape() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("exports")
        let outside = directory.appendingPathComponent("unrelated")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let victim = outside.appendingPathComponent("shared-photo.jpg")
        let original = Data("preserve this file".utf8)
        try original.write(to: victim)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        do {
            try await TemporaryExportStore(rootURL: root).remove(link.appendingPathComponent(victim.lastPathComponent))
            XCTFail("Cleanup must reject nested paths")
        } catch TemporaryExportStore.ExportError.invalidExportURL {}
        XCTAssertEqual(try Data(contentsOf: victim), original)
    }

    @MainActor
    func testFailedLaunchCleanupRemainsVisible() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manager = FailingCleanupFileManager()
        let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: directory, fileManager: manager), privateStore: PrivateMediaStore(root: directory.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys()), workStore: MediaWorkStore(root: directory.appendingPathComponent("work")), lock: GalleryLockController(store: GalleryLockStore(persistence: MemoryGalleryLockPersistence())))
        await model.start()
        XCTAssertTrue(model.hasTemporaryShareFiles)
        XCTAssertNotNil(model.errorMessage)
    }
}

private final class FailingCleanupFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
