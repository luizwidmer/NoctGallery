import CryptoKit
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import NoctGallery

@MainActor
final class GalleryImportInboxTests: XCTestCase {
    func testChunkedIncomingRoundTripNeverStoresPlaintextInSharedContainer() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let inbox = GalleryImportInbox(root: root.appendingPathComponent("inbox")), key = Curve25519.KeyAgreement.PrivateKey()
        try inbox.publish(key.publicKey.rawRepresentation)
        let source = root.appendingPathComponent("source.png")
        var data = Data("incoming-plaintext-canary".utf8); data.append(Data(repeating: 77, count: GalleryImportInbox.chunkSize + 37))
        try data.write(to: source)
        let saved = try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier)
        let ciphertext = try Data(contentsOf: saved)
        XCTAssertNil(ciphertext.range(of: Data("incoming-plaintext-canary".utf8)))
        XCTAssertNil(ciphertext.range(of: Data(UTType.png.identifier.utf8)))
        let destination = root.appendingPathComponent("decoded.png")
        let metadata = try inbox.decrypt(saved, using: key, to: destination)
        XCTAssertEqual(metadata.byteCount, data.count); XCTAssertEqual(metadata.chunkCount, 2)
        XCTAssertEqual(try Data(contentsOf: destination), data)
        XCTAssertEqual(try saved.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try inbox.pending(), [saved])
        try inbox.remove(saved); XCTAssertTrue(try inbox.pending().isEmpty)
    }

    func testWrongKeysTamperingTruncationAndTrailingDataLeaveNoDecryptedFile() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let inbox = GalleryImportInbox(root: root.appendingPathComponent("inbox")), key = Curve25519.KeyAgreement.PrivateKey()
        try inbox.publish(key.publicKey.rawRepresentation)
        let source = root.appendingPathComponent("source.png")
        try Data(repeating: 7, count: GalleryImportInbox.chunkSize + 64).write(to: source)
        let saved = try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier), original = try Data(contentsOf: saved)
        let destination = root.appendingPathComponent("decoded.png")
        XCTAssertThrowsError(try inbox.decrypt(saved, using: Curve25519.KeyAgreement.PrivateKey(), to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        var tampered = original; tampered[tampered.count - 35] ^= 1
        for data in [tampered, Data(original.dropLast()), original + Data([1]), Data([255, 255, 255, 255])] {
            try data.write(to: saved)
            XCTAssertThrowsError(try inbox.decrypt(saved, using: key, to: destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
        try original.write(to: saved)
        XCTAssertThrowsError(try inbox.publish(Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation))
        XCTAssertEqual(try inbox.pending(), [saved], "A recipient-key mismatch must not erase existing incoming files")
    }

    func testQueueBoundsCancellationAndUnsupportedTypes() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let inbox = GalleryImportInbox(root: root.appendingPathComponent("inbox")), key = Curve25519.KeyAgreement.PrivateKey()
        let source = root.appendingPathComponent("source.png"); try Data([1, 2, 3]).write(to: source)
        XCTAssertThrowsError(try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier))
        try inbox.publish(key.publicKey.rawRepresentation)
        XCTAssertThrowsError(try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier, cancelled: { true }))
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: inbox.root.path).contains { $0.hasSuffix(".staging") })
        XCTAssertThrowsError(try inbox.enqueue(source: source, typeIdentifier: UTType.plainText.identifier))
        let abandoned = inbox.root.appendingPathComponent(UUID().uuidString + ".staging")
        try Data([99]).write(to: abandoned)
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path), "The next locked operation removes an interrupted writer's staging file")
        let large = root.appendingPathComponent("large.mov")
        XCTAssertTrue(FileManager.default.createFile(atPath: large.path, contents: nil))
        let largeFile = try FileHandle(forWritingTo: large)
        try largeFile.truncate(atOffset: UInt64(GalleryImportInbox.maximumBytes)); try largeFile.close()
        XCTAssertThrowsError(try inbox.enqueue(source: large, typeIdentifier: UTType.movie.identifier)) { error in
            guard case GalleryImportInbox.InboxError.full = error else { return XCTFail("Ciphertext overhead must participate in the queue bound: \(error)") }
        }
        XCTAssertTrue(try inbox.pending().isEmpty)
        try FileManager.default.removeItem(at: large)
        for _ in 0..<20 { _ = try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier) }
        XCTAssertThrowsError(try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier))
        try inbox.clear(); XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertThrowsError(try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier))
    }

    func testInboxRejectsLinkedDirectoriesAndUnownedRemovalPaths() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real"), link = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let inbox = GalleryImportInbox(root: link)
        XCTAssertThrowsError(try inbox.publish(Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation))
        let normal = GalleryImportInbox(root: real)
        XCTAssertThrowsError(try normal.remove(root.appendingPathComponent("outside.incoming")))
    }

    func testModelImportsOriginalThenLockDropsLoadedLibraryAndAnalysis() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let suite = "GalleryImportModel-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), settings = GallerySettingsStore(service: suite, defaults: defaults)
        defer { try? settings.purge(); defaults.removePersistentDomain(forName: suite) }
        let credentials = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await credentials.configure(mode: .off, pin: "", keys: [])
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let keys = MemoryGalleryInboxKeys(), inbox = GalleryImportInbox(root: root.appendingPathComponent("inbox"))
        let model = GalleryViewModel(privateStore: store, workStore: MediaWorkStore(root: root.appendingPathComponent("work")),
            defaults: defaults, lock: GalleryLockController(store: credentials), preferencesDomain: suite,
            settingsStore: settings, inbox: inbox, inboxKeys: keys)
        let source = root.appendingPathComponent("sample.png"), data = try GalleryDuressPractice.sampleImage(index: 0)
        try data.write(to: source)
        await model.start()
        _ = try inbox.enqueue(source: source, typeIdentifier: UTType.png.identifier)
        await model.importIncoming()
        XCTAssertTrue(try inbox.pending().count == 1, "App-level protection must gate incoming decryption")
        let unlocked = await model.unlockPrivate(); XCTAssertTrue(unlocked)
        await model.importIncoming()
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertEqual(model.privateAssets.count, 1)
        let item = try XCTUnwrap(model.privateAssets.first)
        let resources = try await store.resources(id: item.id)
        XCTAssertEqual(resources[0].byteCount, data.count)
        XCTAssertNotNil(item.importedAt)
        await model.setTextSearch(true)
        await model.organize([item.id], edit: .description(caption: "caption", notes: "notes"))
        await model.lockPrivate()
        XCTAssertTrue(model.privateAssets.isEmpty); XCTAssertTrue(model.organization.items.isEmpty)
        XCTAssertTrue(model.storageItems.isEmpty); XCTAssertTrue(model.duplicateGroups.isEmpty)
        XCTAssertFalse(model.isAnalyzing)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains("sample.png"), "The source stays intact")
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("work").path) {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("work").path).isEmpty)
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryInboxTests-" + UUID().uuidString)
        try MediaFileProtection.prepareDirectory(root); return root
    }
}

private final class MemoryGalleryInboxKeys: GalleryInboxKeys, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey {
        lock.lock(); defer { lock.unlock() }
        if let data { return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) }
        let key = Curve25519.KeyAgreement.PrivateKey(); data = key.rawRepresentation; return key
    }
    func delete() throws { lock.lock(); data = nil; lock.unlock() }
}
