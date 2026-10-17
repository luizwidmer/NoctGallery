import CryptoKit
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import NoctGallery

@MainActor
final class GalleryNextUpdateTests: XCTestCase {
    func testRecoveryIsOptInEncryptedAndExcludedUntilRestored() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryPrivateMediaKeys(), vault = root.appendingPathComponent("vault")
        let store = PrivateMediaStore(root: vault, keys: keys)
        let first = try await save(store, root: root), session = try await store.currentSession()
        let initial = try await store.organization()
        XCTAssertNil(initial.recentlyDeletedEnabled)
        try await store.remove(ids: [first.id], session: session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(first.id).path))
        let second = try await save(store, root: root)
        _ = try await store.setRecentlyDeleted(enabled: true, session: session)
        _ = try await store.organize(ids: [second.id], edit: .tags(["recovery-secret"]), session: session)
        let digest = try await store.contentDigest(id: second.id, session: session)
        let now = Date()
        try await store.remove(ids: [second.id], session: session, now: now)
        let active = try await store.list(), deleted = try await store.recentlyDeleted()
        XCTAssertTrue(active.isEmpty); XCTAssertEqual(deleted.map(\.id), [second.id])
        XCTAssertEqual(deleted[0].daysRemaining(now: now), 7)
        let organization = try await store.organization()
        XCTAssertFalse(organization.matches("recovery-secret", id: second.id))
        XCTAssertEqual(organization.searchText(for: second.id), "")
        let bytes = try await store.recentlyDeletedBytes(); XCTAssertGreaterThan(bytes, 0)
        do { _ = try await store.fileExtension(id: second.id); XCTFail("Deleted original was exposed") } catch {}
        do { _ = try await store.thumbnail(id: second.id); XCTFail("Deleted thumbnail was exposed") } catch {}
        let recoveryThumbnail = try await store.deletedThumbnail(id: second.id, session: session)
        XCTAssertNotNil(UIImage(data: recoveryThumbnail))
        do { _ = try await store.setRecentlyDeleted(enabled: false, session: session); XCTFail("Silently discarded recovery") } catch {}
        let sealed = try Data(contentsOf: vault.appendingPathComponent("organization.sealed"))
        for text in ["recovery-secret", "deletedAt", "recentlyDeletedEnabled"] { XCTAssertNil(sealed.range(of: Data(text.utf8))) }
        await store.lock()
        _ = try await store.unlock()
        let newSession = try await store.currentSession()
        do { try await store.restoreDeleted(ids: [second.id], session: session); XCTFail("Stale session restored media") } catch {}
        try await store.restoreDeleted(ids: [second.id], session: newSession)
        let restored = try await store.list(), restoredOrganization = try await store.organization()
        XCTAssertEqual(restored.map(\.id), [second.id]); XCTAssertTrue(restoredOrganization.matches("recovery-secret", id: second.id))
        let after = try await store.contentDigest(id: second.id, session: newSession)
        XCTAssertEqual(digest, after)
    }

    func testSevenDayExpiryPermanentRemovalAndDuressBypassRecovery() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let expired = try await save(store, root: root), session = try await store.currentSession()
        _ = try await store.setRecentlyDeleted(enabled: true, session: session)
        let date = Date().addingTimeInterval(-PrivateMediaStore.deletedRetention)
        try await store.remove(ids: [expired.id], session: session, now: date)
        do { try await store.restoreDeleted(ids: [expired.id], session: session); XCTFail("Expired media restored") } catch {}
        do { _ = try await store.deletedThumbnail(id: expired.id, session: session); XCTFail("Expired recovery thumbnail was exposed") } catch {}
        await store.lock()
        _ = try await store.unlock()
        let deleted = try await store.recentlyDeleted()
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault/" + expired.id).path))
        let trashed = try await save(store, root: root), decoy = try await save(store, root: root)
        let current = try await store.currentSession()
        try await store.remove(ids: [trashed.id], session: current)
        try await store.applyDuress(.init(id: UUID(), action: .retainDecoys, retainedIDs: [trashed.id, decoy.id],
            replacementPIN: .init(salt: Data(repeating: 1, count: 32), digest: Data(repeating: 2, count: 32)),
            replacementMediaKey: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }))
        _ = try await store.unlock()
        let surviving = try await store.list(), recovery = try await store.recentlyDeleted()
        XCTAssertEqual(surviving.map(\.id), [decoy.id]); XCTAssertTrue(recovery.isEmpty)
        let replacement = try await store.organization(); XCTAssertNil(replacement.recentlyDeletedEnabled)
        _ = try await store.setRecentlyDeleted(enabled: true, session: store.currentSession())
        try await store.remove(ids: [decoy.id], session: store.currentSession())
        try await store.emptyRecentlyDeleted(session: store.currentSession())
        _ = try await store.setRecentlyDeleted(enabled: false, session: store.currentSession())
        let empty = try await store.list(); XCTAssertTrue(empty.isEmpty)
        try await store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault").path))
    }

    func testMissingPermanentlyDeletedMediaDoesNotBlockRecoveryList() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let item = try await save(store, root: root), session = try await store.currentSession()
        _ = try await store.setRecentlyDeleted(enabled: true, session: session)
        try await store.remove(ids: [item.id], session: session)
        try FileManager.default.removeItem(at: root.appendingPathComponent("vault/" + item.id))
        let deleted = try await store.recentlyDeleted(), organization = try await store.organization()
        XCTAssertTrue(deleted.isEmpty); XCTAssertNil(organization.items[item.id])
    }

    func testImportsContinueAfterFailureRetryOnlyFailuresAndClearSessionState() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let suite = "GalleryNextImport-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), settings = GallerySettingsStore(service: suite, defaults: defaults)
        defer { try? settings.purge(); defaults.removePersistentDomain(forName: suite) }
        let credentials = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await credentials.configure(mode: .off, pin: "", keys: [])
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let work = MediaWorkStore(root: root.appendingPathComponent("work"))
        let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: root.appendingPathComponent("exports")),
            privateStore: store, workStore: work, defaults: defaults, lock: GalleryLockController(store: credentials),
            preferencesDomain: suite, settingsStore: settings, inbox: GalleryImportInbox(root: root.appendingPathComponent("inbox")),
            inboxKeys: NextUpdateInboxKeys())
        await model.start(); let unlocked = await model.unlockPrivate(); XCTAssertTrue(unlocked)
        let urls = ["first.png", "broken.png", "last.png"].map { root.appendingPathComponent($0) }
        let image = try GalleryDuressPractice.sampleImage(index: 0)
        try image.write(to: urls[0]); try Data("broken image".utf8).write(to: urls[1]); try image.write(to: urls[2])
        await model.importFiles(urls)
        let report = try XCTUnwrap(model.importReport)
        XCTAssertEqual(report.succeeded, 2); XCTAssertEqual(report.outcomes.filter { $0.status == .failed }.count, 1)
        XCTAssertEqual(report.retryURLs, [urls[1]]); XCTAssertEqual(model.privateAssets.count, 2)
        try image.write(to: urls[1])
        await model.importFiles(report.retryURLs)
        XCTAssertEqual(model.privateAssets.count, 3); XCTAssertEqual(model.importReport?.succeeded, 1)
        XCTAssertEqual(try Data(contentsOf: urls[0]), image, "Import must leave the source intact")
        let pending = Task { await model.importFiles(Array(repeating: urls[0], count: 20)) }
        for _ in 0..<100 where !model.isProcessing { await Task.yield() }
        XCTAssertTrue(model.isProcessing)
        model.cancelImport(); await pending.value
        XCTAssertTrue(model.importReport?.outcomes.contains(where: { $0.status == .cancelled }) == true)
        let item = try XCTUnwrap(model.privateAssets.first)
        let before = await model.thumbnail(for: item, targetSize: CGSize(width: 200, height: 200))
        await model.organize([item.id], edit: .photoEdits(.init(quarterTurns: 1)))
        let after = await model.thumbnail(for: item, targetSize: CGSize(width: 200, height: 200))
        XCTAssertNotEqual(before?.size, after?.size, "Recipe changes must invalidate cached thumbnails")
        await model.setRecentlyDeleted(enabled: true)
        await model.deletePrivate(item)
        let deletedImage = await model.thumbnail(for: item, targetSize: CGSize(width: 200, height: 200))
        XCTAssertNil(deletedImage, "A cached thumbnail must not expose a deleted item")
        model.gridDensity = 4; model.groupByDate = false
        await model.lockPrivate()
        XCTAssertNil(model.importReport); XCTAssertTrue(model.searchIndex.search("").isEmpty)
        let lockedImage = await model.thumbnail(for: item, targetSize: CGSize(width: 200, height: 200)); XCTAssertNil(lockedImage)
        let scratch = try await work.byteCount(); XCTAssertEqual(scratch, 0)
        _ = await model.unlockPrivate()
        await model.purgeAndReset()
        XCTAssertFalse(model.resetNeedsRetry); XCTAssertEqual(model.gridDensity, 3); XCTAssertTrue(model.groupByDate)
    }

    func testLegacyPhotoRecipeAndPreciseCropColorControls() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(GalleryPhotoEdits(quarterTurns: 1))) as? [String: Any])
        for field in ["brightness", "contrast", "saturation"] { json.removeValue(forKey: field) }
        let legacy = try JSONDecoder().decode(GalleryPhotoEdits.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.brightness, 0); XCTAssertEqual(legacy.contrast, 1); XCTAssertEqual(legacy.saturation, 1)
        let crop = GalleryRectangleEditing.centered(aspect: 1, imageAspect: 2)
        XCTAssertEqual(crop.width, 0.5); XCTAssertEqual(crop.height, 1)
        for handle in GalleryCropHandle.allCases {
            let resized = GalleryRectangleEditing.resize(CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.6), handle: handle, dx: 0.8, dy: -0.8, aspect: 1)
            XCTAssertGreaterThanOrEqual(resized.minX, 0); XCTAssertLessThanOrEqual(resized.maxX, 1)
            XCTAssertGreaterThanOrEqual(resized.minY, 0); XCTAssertLessThanOrEqual(resized.maxY, 1)
            XCTAssertEqual(resized.width, resized.height, accuracy: 0.00001)
            _ = try GalleryPhotoEdits(crop: resized).validated()
        }
        let moved = GalleryRectangleEditing.move(crop, dx: -20, dy: 20)
        XCTAssertEqual(moved.minX, 0); XCTAssertEqual(moved.maxY, 1)
        let original = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor(white: 0.3, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let source = try XCTUnwrap(original.cgImage)
        let bright = try GalleryPhotoEdits(brightness: 0.2).apply(to: source)
        XCTAssertNotEqual(try XCTUnwrap(bright.dataProvider?.data) as Data, try XCTUnwrap(source.dataProvider?.data) as Data)
        XCTAssertEqual(source.width, bright.width)
        for recipe in [GalleryPhotoEdits(brightness: .nan), .init(contrast: 2), .init(saturation: -1)] { XCTAssertThrowsError(try recipe.validated()) }
    }

    func testFullscreenZoomViewRefreshesAnEditedImageAndItsGeometry() {
        func picture(_ size: CGSize) -> UIImage {
            UIGraphicsImageRenderer(size: size).image { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }
        }
        let view = GalleryZoomImage.ZoomView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let original = picture(CGSize(width: 200, height: 100)), edited = picture(CGSize(width: 100, height: 200))
        view.updateImage(original); view.layoutIfNeeded()
        XCTAssertEqual(view.imageView.frame.size, CGSize(width: 100, height: 50))
        view.updateImage(edited); view.layoutIfNeeded()
        XCTAssertTrue(view.imageView.image === edited)
        XCTAssertEqual(view.imageView.frame.size, CGSize(width: 50, height: 100), "Returning from editing must refresh the existing fullscreen view")
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryNext-" + UUID().uuidString)
        try MediaFileProtection.prepareDirectory(url); return url
    }
    private func save(_ store: PrivateMediaStore, root: URL) async throws -> PhotoAssetRecord {
        if (try? await store.currentSession()) == nil { _ = try await store.unlock() }
        let source = root.appendingPathComponent(UUID().uuidString + ".png")
        let data = try GalleryDuressPractice.sampleImage(index: 0); try data.write(to: source)
        return try await store.save(file: source, fileExtension: "png", kind: .photo, width: 960, height: 720,
            duration: 0, thumbnail: data, profile: nil, session: store.currentSession())
    }
}

private final class NextUpdateInboxKeys: GalleryInboxKeys, @unchecked Sendable {
    private let lock = NSLock()
    private var key = Curve25519.KeyAgreement.PrivateKey()
    func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey { lock.lock(); defer { lock.unlock() }; return key }
    func delete() throws { lock.lock(); defer { lock.unlock() }; key = Curve25519.KeyAgreement.PrivateKey() }
}
