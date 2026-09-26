import CryptoKit
import UniformTypeIdentifiers
import XCTest
@testable import NoctGallery

@MainActor
final class GalleryFeatureStoreTests: XCTestCase {
    func testLiveAndRAWComponentsRoundTripAndSurviveDuressRekey() async throws {
        for raw in [false, true] {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let keys = MemoryPrivateMediaKeys()
            let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: keys)
            _ = try await store.unlock()
            let session = try await store.currentSession()
            let originals = try resources(root: root, raw: raw)
            let kind: GalleryOriginalKind = raw ? .rawPair : .livePhoto
            let item = try await store.saveOriginal(resources: originals, originalKind: kind,
                creationDate: Date(timeIntervalSince1970: 1_234_567), kind: .photo, width: 640, height: 480,
                duration: 0, thumbnail: Data([1, 2]), session: session)
            try await store.verifyOriginal(id: item.id, originals: originals, session: session)
            var organization = try await store.saveAlbum(name: "Secret Trip", session: session)
            organization = try await store.organize(ids: [item.id], edit: .addToAlbum(organization.albums[0].id), session: session)
            let oldKey = try keys.loadOrCreate(allowCreate: false)
            let replacement = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try await store.applyDuress(.init(id: UUID(), action: .retainDecoys, retainedIDs: [item.id],
                replacementPIN: .init(salt: Data(repeating: 1, count: 32), digest: Data(repeating: 2, count: 32)), replacementMediaKey: replacement))
            XCTAssertNotEqual(oldKey, try keys.loadOrCreate(allowCreate: false))
            let reopened = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: keys)
            let loaded = try await reopened.unlock()
            XCTAssertEqual(loaded.map(\.originalKind), [kind])
            XCTAssertEqual(loaded.first?.creationDate, item.creationDate)
            let newSession = try await reopened.currentSession()
            let manifest = try await reopened.resources(id: item.id)
            XCTAssertEqual(manifest.count, 2)
            for (component, original) in zip(manifest, originals) {
                let target = root.appendingPathComponent(component.id)
                try await reopened.materialize(id: item.id, resourceID: component.id, to: target, session: newSession)
                XCTAssertEqual(try Data(contentsOf: target), try Data(contentsOf: original.url))
            }
            try await reopened.verifyOriginal(id: item.id, originals: originals, session: newSession)
            let cleared = try await reopened.organization()
            XCTAssertTrue(cleared.albums.isEmpty, "Duress must not keep names of erased collections")
            XCTAssertTrue(cleared.items.isEmpty)
        }
    }

    func testCorruptCompanionNeverAuthorizesPhotosDeletion() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        _ = try await store.unlock()
        let session = try await store.currentSession()
        let originals = try resources(root: root, raw: false)
        let item = try await store.saveOriginal(resources: originals, originalKind: .livePhoto, creationDate: nil,
            kind: .photo, width: 640, height: 480, duration: 0, thumbnail: Data(), session: session)
        let manifest = try await store.resources(id: item.id)
        let companion = root.appendingPathComponent("vault/\(item.id)/\(manifest[1].id).sealed")
        var corrupted = try Data(contentsOf: companion)
        corrupted[corrupted.count / 2] ^= 1
        try corrupted.write(to: companion)
        var deleted = false
        let outcome = try await PrivateGalleryMove.perform(save: { item }, verify: {
            try await store.verifyOriginal(id: $0.id, originals: originals, session: session)
        }, mayDelete: { true }, deleteOriginal: { deleted = true })
        XCTAssertFalse(deleted)
        XCTAssertFalse(outcome.originalRemoved)
        XCTAssertNotNil(outcome.error)
        let output = root.appendingPathComponent("partial.mov")
        do { try await store.materialize(id: item.id, resourceID: manifest[1].id, to: output, session: session); XCTFail() } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testOriginalManifestRejectsUnsupportedAndAmbiguousResources() throws {
        XCTAssertEqual(try GalleryOriginalFormats.classify([(.photo, UTType.jpeg.identifier), (.pairedVideo, UTType.quickTimeMovie.identifier)]), .livePhoto)
        XCTAssertEqual(try GalleryOriginalFormats.classify([(.photo, "com.adobe.raw-image")]), .rawPhoto)
        XCTAssertThrowsError(try GalleryOriginalFormats.classify([(.photo, UTType.jpeg.identifier), (.photo, UTType.jpeg.identifier)]))
        XCTAssertThrowsError(try GalleryOriginalFormats.classify([(.photo, UTType.jpeg.identifier), (.alternatePhoto, UTType.png.identifier)]))
        XCTAssertThrowsError(try GalleryOriginalFormats.classify([(.photo, UTType.jpeg.identifier), (.pairedVideo, UTType.jpeg.identifier)]))
        XCTAssertThrowsError(try GalleryOriginalFormats.classify([(.photo, "public.data")]))
    }

    func testOrganizationIsEncryptedPersistsAndAlbumDeletionKeepsMedia() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryPrivateMediaKeys()
        let vault = root.appendingPathComponent("vault")
        let store = PrivateMediaStore(root: vault, keys: keys)
        _ = try await store.unlock()
        let session = try await store.currentSession()
        let originals = try resources(root: root, raw: false)
        let item = try await store.save(file: originals[0].url, fileExtension: "jpg", kind: .photo, width: 1, height: 1,
            duration: 0, thumbnail: Data(), profile: nil, session: session)
        let albums = try await store.saveAlbum(name: "Confidential Album", session: session)
        let id = albums.albums[0].id
        _ = try await store.organize(ids: [item.id], edit: .addToAlbum(id), session: session)
        _ = try await store.organize(ids: [item.id], edit: .favorite(true), session: session)
        _ = try await store.organize(ids: [item.id], edit: .tags(["private-tag"]), session: session)
        let sealed = try Data(contentsOf: vault.appendingPathComponent("organization.sealed"))
        for secret in ["Confidential Album", "private-tag", item.id] { XCTAssertNil(sealed.range(of: Data(secret.utf8))) }
        await store.lock()
        do { _ = try await store.organization(); XCTFail("Locked search exposed metadata") } catch PrivateMediaStore.StoreError.locked { }
        let reopened = PrivateMediaStore(root: vault, keys: keys)
        _ = try await reopened.unlock()
        let loaded = try await reopened.organization()
        XCTAssertEqual(loaded.items[item.id]?.tags, ["private-tag"])
        XCTAssertEqual(loaded.items[item.id]?.favorite, true)
        XCTAssertTrue(loaded.searchText(for: item.id).contains("Confidential Album"))
        let newSession = try await reopened.currentSession()
        let removed = try await reopened.deleteAlbum(id: id, session: newSession)
        XCTAssertTrue(removed.items[item.id]?.albumIDs.isEmpty == true)
        let remaining = try await reopened.list()
        XCTAssertEqual(remaining.count, 1)
        try await reopened.delete(id: item.id)
        let afterDeletion = try await reopened.organization()
        XCTAssertNil(afterDeletion.items[item.id])
    }

    func testCorruptOrganizationFailsClosedAndMissingKeyDoesNotReplaceAlbumOnlyVault() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = MemoryPrivateMediaKeys()
        let store = PrivateMediaStore(root: root, keys: keys)
        _ = try await store.unlock()
        let session = try await store.currentSession()
        _ = try await store.saveAlbum(name: "Album", session: session)
        let url = root.appendingPathComponent("organization.sealed")
        var bytes = try Data(contentsOf: url)
        bytes[20] ^= 1
        try bytes.write(to: url)
        do { _ = try await store.organization(); XCTFail("Unauthenticated organization was accepted") } catch { }
        await store.lock()
        try keys.delete()
        do { _ = try await store.unlock(); XCTFail("Replaced key in existing album-only vault") } catch PrivateMediaStore.StoreError.keyUnavailable { }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testOrganizationBoundsAndStaleSession() async throws {
        XCTAssertEqual(try GalleryOrganization.tags(from: "trip, family, trip"), ["family", "trip"])
        XCTAssertThrowsError(try GalleryOrganization.tags(from: String(repeating: "x", count: 41)))
        XCTAssertThrowsError(try GalleryOrganization.tags(from: "secret\u{0}"))
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateMediaStore(root: root, keys: MemoryPrivateMediaKeys())
        _ = try await store.unlock()
        let session = try await store.currentSession()
        await store.lock()
        _ = try await store.unlock()
        do { _ = try await store.saveAlbum(name: "Late write", session: session); XCTFail() } catch is CancellationError { }
        let result = try await store.organization()
        XCTAssertTrue(result.albums.isEmpty)
    }

    func testPracticeRunsBothActionsWithReplacementPINAndRejectsWrongPIN() async throws {
        let service = GalleryDuressPractice()
        for action in GalleryDuressAction.allCases {
            let result = try await service.run(action: action, retainedSamples: [0, 2], enteredPIN: GalleryDuressPractice.practicePIN)
            XCTAssertEqual(result.remainingSamples, action == .reset ? [] : [0, 2])
            XCTAssertTrue(result.mediaKeyChanged)
            XCTAssertTrue(result.onlyPINRequired)
            XCTAssertTrue(result.oldPINRejected)
            XCTAssertTrue(result.replacementPINWorks)
        }
        do { _ = try await service.run(action: .reset, retainedSamples: [], enteredPIN: "111111"); XCTFail() }
        catch GalleryLockError.rejected { }
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryDuressPractice")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryFeatureTests-" + UUID().uuidString)
        try MediaFileProtection.prepareDirectory(root)
        return root
    }

    private func resources(root: URL, raw: Bool) throws -> [GalleryOriginalResource] {
        let photo = root.appendingPathComponent("original.jpg")
        let other = root.appendingPathComponent(raw ? "original.dng" : "original.mov")
        try (Data("photo-secret".utf8) + Data(repeating: 23, count: 200)).write(to: photo)
        try (Data("companion-secret".utf8) + Data(repeating: 73, count: PrivateMediaStore.chunkSize + 11)).write(to: other)
        return [.init(url: photo, fileExtension: "jpg", role: .photo, typeIdentifier: UTType.jpeg.identifier),
                .init(url: other, fileExtension: raw ? "dng" : "mov", role: raw ? .alternatePhoto : .pairedVideo,
                      typeIdentifier: raw ? "com.adobe.raw-image" : UTType.quickTimeMovie.identifier)]
    }
}
