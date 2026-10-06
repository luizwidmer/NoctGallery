import AVFoundation
import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import NoctGallery

@MainActor
final class GalleryLibraryUpgradeTests: XCTestCase {
    func testReleasedOrganizationAndSettingsDecodeWithoutNewFields() throws {
        let id = UUID().uuidString.lowercased()
        let legacy = Data("{\"version\":1,\"albums\":[],\"items\":{\"\(id)\":{\"favorite\":false,\"albumIDs\":[],\"tags\":[\"legacy\"]}}}".utf8)
        let organization = try JSONDecoder().decode(GalleryOrganization.self, from: legacy).validated()
        XCTAssertEqual(organization.searchText(for: id), "legacy")
        XCTAssertNil(organization.items[id]?.photoEdits)
        XCTAssertNil(organization.textSearchEnabled)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(GallerySettingsRecord())) as? [String: Any])
        object.removeValue(forKey: "sharingPresets")
        let settings = try JSONDecoder().decode(GallerySettingsRecord.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        XCTAssertNil(settings.sharingPresets)
    }

    func testNotesRecipesAndTextStayEncryptedAndSurviveReopen() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let asset = try await saveSample(store: store, root: root)
        let session = try await store.currentSession()
        let edits = GalleryPhotoEdits(quarterTurns: 1, straightenDegrees: 2, crop: CGRect(x: 0, y: 0, width: 0.8, height: 1))
        _ = try await store.organize(ids: [asset.id], edit: .description(caption: "caption-canary", notes: "notes-canary"), session: session)
        _ = try await store.organize(ids: [asset.id], edit: .photoEdits(edits), session: session)
        _ = try await store.setTextSearch(enabled: true, session: session)
        _ = try await store.setRecognizedText(id: asset.id, text: "ocr-canary", session: session)
        let sealed = try Data(contentsOf: root.appendingPathComponent("vault/organization.sealed"))
        for canary in ["caption-canary", "notes-canary", "ocr-canary", "straightenDegrees"] { XCTAssertNil(sealed.range(of: Data(canary.utf8))) }
        await store.lock()
        do { _ = try await store.organization(); XCTFail("Locked organization was readable") } catch { }
        _ = try await store.unlock()
        let opened = try await store.organization()
        XCTAssertEqual(opened.items[asset.id]?.photoEdits, edits)
        XCTAssertTrue(opened.searchText(for: asset.id).contains("ocr-canary"))
        let disabled = try await store.setTextSearch(enabled: false, session: store.currentSession())
        XCTAssertNil(disabled.items[asset.id]?.recognizedText)
        XCTAssertFalse(disabled.searchText(for: asset.id).contains("ocr-canary"))
        XCTAssertTrue(disabled.searchText(for: asset.id).contains("notes-canary"))
    }

    func testDuressDropsNotesTextAndRecipesWhileKeepingSelectedMedia() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let asset = try await saveSample(store: store, root: root)
        let session = try await store.currentSession()
        _ = try await store.organize(ids: [asset.id], edit: .description(caption: "private caption", notes: "private notes"), session: session)
        _ = try await store.organize(ids: [asset.id], edit: .photoEdits(.init(quarterTurns: 1)), session: session)
        _ = try await store.setTextSearch(enabled: true, session: session)
        _ = try await store.setRecognizedText(id: asset.id, text: "private transcript", session: session)
        let before = try await store.contentDigest(id: asset.id, session: session)
        try await store.applyDuress(.init(id: UUID(), action: .retainDecoys, retainedIDs: [asset.id],
            replacementPIN: .init(salt: Data(repeating: 1, count: 32), digest: Data(repeating: 2, count: 32)),
            replacementMediaKey: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }))
        _ = try await store.unlock()
        let organization = try await store.organization()
        XCTAssertTrue(organization.items.isEmpty)
        XCTAssertNil(organization.textSearchEnabled)
        let after = try await store.contentDigest(id: asset.id, session: store.currentSession())
        XCTAssertEqual(before, after)
    }

    func testPhotoRecipeChangesGeometryBeforeCoversAndLeavesSourceIntact() throws {
        let original = try image()
        let before = SHA256.hash(data: original)
        var config = ImageSanitizer.Configuration(); config.outputFormat = .png
        let recipe = GalleryPhotoEdits(quarterTurns: 1, crop: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let output = try ImageSanitizer().sanitize(original, configuration: config, edits: .init(
            redactions: [.init(rect: CGRect(x: 0, y: 0, width: 1, height: 0.2))], photoEdits: recipe))
        XCTAssertEqual(output.pixelWidth, 50); XCTAssertEqual(output.pixelHeight, 200)
        let decoded = try XCTUnwrap(UIImage(data: output.data)?.cgImage)
        XCTAssertLessThan(try pixel(decoded, x: 10, y: 10), 5)
        XCTAssertGreaterThan(try pixel(decoded, x: 10, y: 150), 245)
        XCTAssertEqual(SHA256.hash(data: original), before)
        XCTAssertThrowsError(try GalleryPhotoEdits(quarterTurns: 4).validated())
        XCTAssertThrowsError(try GalleryPhotoEdits(straightenDegrees: .nan).validated())
        XCTAssertThrowsError(try GalleryPhotoEdits(crop: CGRect(x: -0.1, y: 0, width: 1, height: 1)).validated())
        XCTAssertThrowsError(try GalleryPhotoEdits(crop: CGRect(x: 0, y: 0, width: 0.001, height: 1)).validated())
    }

    func testStraightenKeepsAnInscribedImageWithoutEmptyCorners() throws {
        let source = try XCTUnwrap(UIImage(data: image())?.cgImage)
        let output = try GalleryPhotoEdits(straightenDegrees: 12).apply(to: source)
        XCTAssertLessThan(output.width, source.width)
        XCTAssertLessThan(output.height, source.height)
        XCTAssertGreaterThan(try pixel(output, x: 2, y: 2), 240)
        XCTAssertGreaterThan(try pixel(output, x: output.width - 3, y: output.height - 3), 240)
    }

    func testMovingCoverInterpolationUsesSourceTimeAndRejectsInvalidKeyframes() throws {
        let a = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), b = CGRect(x: 0.6, y: 0.1, width: 0.2, height: 0.2)
        let cover = GalleryRedaction(rect: a, keyframes: [.init(time: 0, rect: a), .init(time: 2, rect: b)])
        XCTAssertTrue(cover.isValid)
        XCTAssertEqual(cover.rect(at: 1).minX, 0.35, accuracy: 0.0001)
        XCTAssertEqual(cover.rect(at: -1), a); XCTAssertEqual(cover.rect(at: 3), b)
        var invalid = cover; invalid.keyframes[1].time = 0
        XCTAssertFalse(invalid.isValid)
        invalid = cover; invalid.keyframes[1].rect.origin.x = 2
        XCTAssertFalse(invalid.isValid)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 100, 100, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let value = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(value, [])
        let pointer = try XCTUnwrap(CVPixelBufferGetBaseAddress(value)); let stride = CVPixelBufferGetBytesPerRow(value)
        memset(pointer, 255, stride * 100); CVPixelBufferUnlockBaseAddress(value, [])
        try GalleryShareEdits(redactions: [cover]).redact(value, at: 2)
        CVPixelBufferLockBaseAddress(value, .readOnly); defer { CVPixelBufferUnlockBaseAddress(value, .readOnly) }
        XCTAssertEqual(pointer.assumingMemoryBound(to: UInt8.self)[15 * stride + 65 * 4], 0)
        XCTAssertEqual(pointer.assumingMemoryBound(to: UInt8.self)[15 * stride + 15 * 4], 255)
    }

    func testSelectiveAudioMutingCopiesPCMAndRetainsOutsideSamples() throws {
        let input = try pcm()
        let before = try audioData(input)
        let result = try GalleryAudioRedaction.mute(input, ranges: [.init(start: 10.02, end: 10.04)])
        let output = try audioData(result)
        XCTAssertEqual(try audioData(input), before, "Source samples must remain intact")
        XCTAssertEqual(Array(output[(23 * 4)..<(36 * 4)]), Array(repeating: 0, count: 13 * 4))
        XCTAssertEqual(output[10 * 4], before[10 * 4]); XCTAssertEqual(output[50 * 4], before[50 * 4])
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(result), CMSampleBufferGetPresentationTimeStamp(input))
        XCTAssertThrowsError(try GalleryShareEdits(silencedRanges: [.init(start: 1, end: 3)]).validated(duration: 2))
        XCTAssertThrowsError(try GalleryShareEdits(silencedRanges: [.init(start: .nan, end: 3)]).validated(duration: 4))
    }

    func testDuplicateDigestAuthenticatesMediaAndStorageCountsCiphertext() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        let a = try await saveSample(store: store, root: root)
        let b = try await saveSample(store: store, root: root)
        let session = try await store.currentSession()
        let first = try await store.contentDigest(id: a.id, session: session), second = try await store.contentDigest(id: b.id, session: session)
        XCTAssertEqual(first, second)
        let sizes = try await store.storageItems()
        XCTAssertEqual(sizes.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(sizes[a.id]).storedBytes, try XCTUnwrap(sizes[a.id]).mediaBytes)
        let file = root.appendingPathComponent("vault/\(a.id)/media.sealed")
        var bytes = try Data(contentsOf: file); bytes[30] ^= 1; try bytes.write(to: file)
        do { _ = try await store.contentDigest(id: a.id, session: session); XCTFail("Accepted damaged duplicate content") } catch { }
    }

    func testLocalOCRAndSimilarityOnDisposableImages() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 300), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 300))
            "PRIVATE SAMPLE 54321".draw(at: CGPoint(x: 30, y: 90), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 38), .foregroundColor: UIColor.black])
        }
        let cg = try XCTUnwrap(image.cgImage)
        let text = try await Task.detached { try GalleryLocalAnalysis.text(in: cg) }.value
        XCTAssertTrue(text.contains("54321"))
        let groups = try await Task.detached { try GalleryLocalAnalysis.similarGroups([("a", cg), ("b", cg)], exactPairs: []) }.value
        XCTAssertEqual(groups.count, 1)
        let excluded = try await Task.detached { try GalleryLocalAnalysis.similarGroups([("a", cg), ("b", cg)], exactPairs: [GalleryLocalAnalysis.pairKey("a", "b")]) }.value
        XCTAssertTrue(excluded.isEmpty)
    }

    func testFilesImportSniffsImageFormatAndPreservesOriginalBytes() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("wrong-extension.mov"), copy = root.appendingPathComponent("copy.mov")
        let data = try image(); try data.write(to: source)
        try GalleryFileImport.copy(source, to: copy)
        let prepared = try await GalleryFileImport.inspect(copy, declaredType: UTType.quickTimeMovie.identifier)
        XCTAssertEqual(prepared.fileExtension, "png"); XCTAssertEqual(prepared.kind, .photo)
        XCTAssertEqual(try Data(contentsOf: copy), data)
        XCTAssertEqual(prepared.resources.count, 1)
        let unsupported = root.appendingPathComponent("bad.mov"); try Data([1, 2, 3]).write(to: unsupported)
        do { _ = try await GalleryFileImport.inspect(unsupported, declaredType: nil); XCTFail("Accepted invalid media") } catch { }
    }

    func testSharingPresetRoundTripAndBounds() throws {
        let suite = "GalleryUpgrade-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), store = GallerySettingsStore(service: suite, defaults: defaults)
        defer { try? store.purge(); defaults.removePersistentDomain(forName: suite) }
        var record = GallerySettingsRecord()
        record.sharingPresets = [.init(name: "Messages", format: .jpeg, maximumDimension: 2_048, quality: 0.75, videoMaximumEdge: 960, removeAudio: true)]
        try store.save(record)
        XCTAssertEqual(try store.loadOrMigrate(), record)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { "\($0)".contains("Messages") })
        XCTAssertThrowsError(try GallerySharingPreset(name: "Bad", videoMaximumEdge: 10_000).validated())
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryUpgrade-" + UUID().uuidString)
        try MediaFileProtection.prepareDirectory(root); return root
    }
    private func saveSample(store: PrivateMediaStore, root: URL) async throws -> PhotoAssetRecord {
        _ = try await store.unlock()
        let source = root.appendingPathComponent(UUID().uuidString + ".png"), data = try image()
        try data.write(to: source)
        return try await store.save(file: source, fileExtension: "png", kind: .photo, width: 200, height: 100,
            duration: 0, thumbnail: data, profile: nil, session: store.currentSession())
    }
    private func image() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let data = NSMutableData(), destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return data as Data
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let value = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(value, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)[0]
    }
    private func pcm() throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: 1_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
            mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
            layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 400,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: 400, flags: 0, blockBufferOut: &block), noErr)
        let data = Data(repeating: 31, count: 400)
        _ = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: 400) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 1_000), presentationTimeStamp: CMTime(value: 10, timescale: 1), decodeTimeStamp: .invalid)
        var size = 4, sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format!, sampleCount: 100,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
    private func audioData(_ sample: CMSampleBuffer) throws -> Data {
        let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample)), size = CMBlockBufferGetDataLength(block)
        var result = Data(count: size)
        let status = result.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!) }
        XCTAssertEqual(status, noErr); return result
    }
}
