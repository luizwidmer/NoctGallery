import CryptoKit
import XCTest
@testable import NoctGallery

final class GalleryDuressTests: XCTestCase {
    func testRetainedPhotoAndVideoAreReencryptedAndEverythingElseIsRemoved() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryPrivateMediaKeys()
        let vault = root.appendingPathComponent("vault")
        let store = PrivateMediaStore(root: vault, keys: keys)
        let items = try await Self.addItems(root: root, store: store)
        let oldKey = try keys.loadOrCreate(allowCreate: false)
        let retained = Set(items.prefix(2).map(\.id))
        let plan = plan(action: .retainDecoys, ids: retained)
        try await store.applyDuress(plan)
        let reopened = PrivateMediaStore(root: vault, keys: keys)
        let remaining = try await reopened.unlock()
        XCTAssertEqual(Set(remaining.map(\.id)), retained)
        XCTAssertNotEqual(try keys.loadOrCreate(allowCreate: false), oldKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(items[2].id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("photos-original.jpg").path))
        let oldItemKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: oldKey), salt: Data(items[0].id.utf8),
            info: Data("NoctGallery.private-media.v1".utf8), outputByteCount: 32)
        let encryptedRecord = try Data(contentsOf: vault.appendingPathComponent(items[0].id + "/record.sealed"))
        XCTAssertThrowsError(try AES.GCM.open(AES.GCM.SealedBox(combined: encryptedRecord), using: oldItemKey,
            authenticating: Data((items[0].id + ":record").utf8)))
        let session = try await reopened.currentSession()
        for (index, item) in items.prefix(2).enumerated() {
            let target = root.appendingPathComponent("restored-\(index)")
            try await reopened.materialize(id: item.id, to: target, session: session)
            XCTAssertEqual(try Data(contentsOf: target), Data(repeating: UInt8(index + 1), count: PrivateMediaStore.chunkSize + 57))
        }
        // Replay after an interruption between file completion and lock-setting commit.
        try await reopened.applyDuress(plan)
        let replayed = try await reopened.unlock()
        XCTAssertEqual(Set(replayed.map(\.id)), retained)
    }

    func testInterruptedRotationResumesBeforeAnyUnlock() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryPrivateMediaKeys()
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: keys)
        let items = try await Self.addItems(root: root, store: store)
        let plan = plan(action: .retainDecoys, ids: [items[1].id])
        keys.setDeleteFailure(true)
        do { try await store.applyDuress(plan); XCTFail("Key update failure ignored") } catch {}
        let reopened = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: keys)
        do { _ = try await reopened.unlock(); XCTFail("Incomplete rotation exposed a gallery") }
        catch PrivateMediaStore.StoreError.resetPending {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.duress-old").path))
        let ready = try Data(contentsOf: root.appendingPathComponent("vault/duress.ready"))
        XCTAssertNil(ready.range(of: Data(plan.id.uuidString.utf8)))
        let replacementKey = SymmetricKey(data: plan.replacementMediaKey)
        XCTAssertEqual(try AES.GCM.open(AES.GCM.SealedBox(combined: ready), using: replacementKey,
            authenticating: Data("NoctGallery.duress.ready.v1".utf8)), Data(plan.id.uuidString.utf8))
        XCTAssertThrowsError(try AES.GCM.open(AES.GCM.SealedBox(combined: ready),
            using: SymmetricKey(size: .bits256), authenticating: Data("NoctGallery.duress.ready.v1".utf8)))
        // Released builds may have left the old UUID marker during a crashed
        // transition; the new build must finish that committed action.
        try Data(plan.id.uuidString.utf8).write(to: root.appendingPathComponent("vault/duress.ready"))
        keys.setDeleteFailure(false)
        try await reopened.applyDuress(plan)
        let remaining = try await reopened.unlock()
        XCTAssertEqual(remaining.map(\.id), [items[1].id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.duress-old").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.duress-next").path))
    }

    @MainActor
    func testDuressResetClearsMediaSettingsAndSharesButRetainsReplacementPIN() async throws {
        let root = temporaryRoot()
        let suite = "NoctGalleryDuressTests-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        let settings = GallerySettingsStore(service: suite + ".settings", defaults: preferences)
        defer { try? FileManager.default.removeItem(at: root); try? settings.purge(); preferences.removePersistentDomain(forName: suite) }
        let media = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        _ = try await Self.addItems(root: root, store: media)
        let credentials = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await credentials.configure(mode: .biometricsAndPIN, pin: "482951", keys: [])
        _ = try await credentials.setDuress(.reset, pin: "638204", decoyIDs: [])
        guard case .duress(let plan) = try await credentials.attemptPIN("638204") else { return XCTFail() }
        let lock = GalleryLockController(store: credentials)
        await lock.load()
        let work = MediaWorkStore(root: root.appendingPathComponent("work"))
        let oldSession = await work.currentSession()
        let temporary = try await work.write(Data([9, 9, 9]), extension: "jpg", session: oldSession)
        preferences.set(true, forKey: "onboarding.completed")
        preferences.set(true, forKey: "photos.connected")
        let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: root.appendingPathComponent("exports")),
            privateStore: media, workStore: work, defaults: preferences, lock: lock, preferencesDomain: suite,
            settingsStore: settings)
        model.savePreset(name: "Old preset", profile: MetadataForge.randomProfile())
        await model.applyDuress(plan)
        XCTAssertNil(model.errorMessage)
        let remaining = try await media.unlock()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(model.presets.isEmpty)
        XCTAssertFalse(preferences.bool(forKey: "onboarding.completed"))
        XCTAssertFalse(preferences.bool(forKey: "photos.connected"))
        XCTAssertTrue(model.onboardingCompleted == false)
        XCTAssertFalse(model.photosConnected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        do { _ = try await work.write(Data([1]), extension: "jpg", session: oldSession); XCTFail("Stale work restored data after reset") }
        catch is CancellationError {}
        let config = try await credentials.load()
        XCTAssertEqual(config?.mode, .pin)
        XCTAssertNil(config?.pendingDuress)
        guard case .primary = try await credentials.attemptPIN("638204") else { return XCTFail("Replacement PIN missing") }
        do { _ = try await credentials.attemptPIN("482951"); XCTFail("Old PIN still works") }
        catch GalleryLockError.rejected {}
    }

    private func plan(action: GalleryDuressAction, ids: Set<String>) -> GalleryDuressPlan {
        GalleryDuressPlan(id: UUID(), action: action, retainedIDs: ids,
            replacementPIN: .init(salt: Data(repeating: 1, count: 32), digest: Data(repeating: 2, count: 32)),
            replacementMediaKey: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }
    private static func addItems(root: URL, store: PrivateMediaStore) async throws -> [PhotoAssetRecord] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("Photos original remains".utf8).write(to: root.appendingPathComponent("photos-original.jpg"))
        _ = try await store.unlock()
        let session = try await store.currentSession()
        var result: [PhotoAssetRecord] = []
        for index in 0..<3 {
            let file = root.appendingPathComponent("fixture-\(index)")
            try Data(repeating: UInt8(index + 1), count: PrivateMediaStore.chunkSize + 57).write(to: file)
            result.append(try await store.save(file: file, fileExtension: index == 1 ? "mov" : "jpg",
                kind: index == 1 ? .video : .photo, width: 640, height: 480, duration: index == 1 ? 1 : 0,
                thumbnail: Data([1, 2, 3]), profile: nil, session: session))
        }
        return result
    }
    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("GalleryDuressTests-" + UUID().uuidString) }
}
