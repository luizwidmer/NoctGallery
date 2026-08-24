import XCTest
@testable import NoctGallery

final class TemporaryExportStoreTests: XCTestCase {
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
}
