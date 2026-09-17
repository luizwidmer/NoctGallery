import CryptoKit
import XCTest
@testable import NoctGallery

final class PrivateMediaStoreTests: XCTestCase {
    func testEncryptedChunkRoundTripAndLockedAccess() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data(repeating: 0x5a, count: PrivateMediaStore.chunkSize * 2 + 731)
        let file = root.appendingPathComponent("source.mov")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try original.write(to: file)
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        _ = try await store.unlock()
        let session = try await store.currentSession()
        let asset = try await store.save(file: file, fileExtension: "mov", kind: .video, width: 1920, height: 1080,
            duration: 2, thumbnail: Data("thumbnail-secret".utf8), profile: MetadataForge.randomProfile(), session: session)
        let encrypted = try Data(contentsOf: root.appendingPathComponent("vault/\(asset.id)/media.sealed"))
        XCTAssertNotEqual(encrypted, original)
        XCTAssertEqual(encrypted.count, original.count + 3 * 28)
        XCTAssertNil(encrypted.range(of: Data(repeating: 0x5a, count: 80)))
        let recordBytes = try Data(contentsOf: root.appendingPathComponent("vault/\(asset.id)/record.sealed"))
        XCTAssertNil(recordBytes.range(of: Data(asset.decoyProfile!.make.utf8)))
        let restored = root.appendingPathComponent("restored.mov")
        try await store.materialize(id: asset.id, to: restored, session: session)
        XCTAssertEqual(try Data(contentsOf: restored), original)
        let thumbnail = try await store.thumbnail(id: asset.id)
        XCTAssertEqual(thumbnail, Data("thumbnail-secret".utf8))
        await store.lock()
        do { _ = try await store.thumbnail(id: asset.id); XCTFail("Locked gallery exposed a thumbnail") }
        catch PrivateMediaStore.StoreError.locked {}
        _ = try await store.unlock()
        do {
            _ = try await store.save(file: file, fileExtension: "mov", kind: .video, width: 1, height: 1,
                duration: 1, thumbnail: Data(), profile: nil, session: session)
            XCTFail("Old unlock session was accepted")
        } catch is CancellationError {}
    }

    func testTamperedTruncatedAndReorderedChunksFailWithoutLeavingPlaintext() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.mov")
        try Data(repeating: 7, count: PrivateMediaStore.chunkSize * 2).write(to: source)
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        _ = try await store.unlock()
        let session = try await store.currentSession()
        let item = try await store.save(file: source, fileExtension: "mov", kind: .video, width: 2, height: 2,
            duration: 1, thumbnail: Data(), profile: nil, session: session)
        let sealedURL = root.appendingPathComponent("vault/\(item.id)/media.sealed")
        let sealed = try Data(contentsOf: sealedURL)
        var flipped = sealed
        flipped[100] ^= 1
        let block = PrivateMediaStore.chunkSize + 28
        let reordered = Data(sealed.dropFirst(block)) + Data(sealed.prefix(block))
        for broken in [flipped, Data(sealed.dropLast()), reordered, sealed + Data([0])] {
            try broken.write(to: sealedURL)
            let plain = root.appendingPathComponent(UUID().uuidString + ".mov")
            do { try await store.materialize(id: item.id, to: plain, session: session); XCTFail("Corrupt media was accepted") }
            catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: plain.path))
        }
    }

    func testResetDeletesOnlyVaultAndRejectsLateWrites() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("photos-original.jpg")
        try Data([1, 2, 3]).write(to: source)
        let keys = MemoryPrivateMediaKeys()
        let vault = root.appendingPathComponent("vault")
        let store = PrivateMediaStore(root: vault, keys: keys)
        _ = try await store.unlock()
        let session = try await store.currentSession()
        _ = try await store.save(file: source, fileExtension: "jpg", kind: .photo, width: 1, height: 1,
            duration: 0, thumbnail: Data(), profile: nil, session: session)
        try await store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.path))
        XCTAssertEqual(try Data(contentsOf: source), Data([1, 2, 3]))
        XCTAssertFalse(keys.hasKey)
        do {
            _ = try await store.save(file: source, fileExtension: "jpg", kind: .photo, width: 1, height: 1,
                duration: 0, thumbnail: Data(), profile: nil, session: session)
            XCTFail("Reset writer recreated the vault")
        } catch PrivateMediaStore.StoreError.locked {}
    }

    func testFailedKeyDeletionLeavesResetIntentAndCanResume() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryPrivateMediaKeys()
        let store = PrivateMediaStore(root: root, keys: keys)
        _ = try await store.unlock()
        keys.setDeleteFailure(true)
        do { try await store.reset(); XCTFail("Reset reported success after key deletion failed") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("reset.pending").path))
        do { _ = try await store.unlock(); XCTFail("Opened a vault with pending reset") }
        catch PrivateMediaStore.StoreError.resetPending {}
        keys.setDeleteFailure(false)
        try await store.resumeResetIfNeeded()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testMissingKeyDoesNotReplaceExistingVault() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(UUID().uuidString.lowercased()), withIntermediateDirectories: true)
        let keys = MemoryPrivateMediaKeys()
        let store = PrivateMediaStore(root: root, keys: keys)
        do { _ = try await store.unlock(); XCTFail("Created a key over existing encrypted items") }
        catch PrivateMediaStore.StoreError.keyUnavailable {}
        XCTAssertFalse(keys.hasKey)
    }

    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("NoctGalleryVaultTests-" + UUID().uuidString) }
}

final class MemoryPrivateMediaKeys: PrivateMediaKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?
    private var failDelete = false
    var hasKey: Bool { lock.withLock { key != nil } }
    func setDeleteFailure(_ value: Bool) { lock.withLock { failDelete = value } }
    func loadOrCreate(allowCreate: Bool) throws -> Data {
        try lock.withLock {
            if let key { return key }
            guard allowCreate else { throw PrivateMediaStore.StoreError.keyUnavailable }
            let created = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            key = created
            return created
        }
    }
    func replace(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if failDelete { throw PrivateMediaStore.StoreError.keyUnavailable }
        key = data
    }
    func delete() throws {
        try lock.withLock {
            if failDelete { throw PrivateMediaStore.StoreError.keyUnavailable }
            key = nil
        }
    }
}
