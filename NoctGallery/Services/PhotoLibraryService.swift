@preconcurrency import Photos
@preconcurrency import AVFoundation
import UIKit
import UniformTypeIdentifiers

@MainActor
final class PhotoLibraryService {
    enum LibraryError: LocalizedError {
        case accessUnavailable
        case assetUnavailable
        case imageUnavailable
        case requestCancelled
        case originalChanged, unsupportedOriginal, deletionUnavailable
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .accessUnavailable: "Photo library access is unavailable."
            case .assetUnavailable: "This media item is no longer in the library."
            case .imageUnavailable: "The original image data is unavailable."
            case .requestCancelled: "The media request was cancelled."
            case .originalChanged: "This item changed in Photos. Reopen it before moving."
            case .unsupportedOriginal: "This item has a format, edits or extra media that Gallery cannot move intact yet. Use Copy to Private Gallery; the original will stay in Photos."
            case .deletionUnavailable: "Photos does not allow this original to be deleted."
            case .underlying(let message): message
            }
        }
    }

    private let imageManager = PHCachingImageManager()

    /// Move never goes through the sharing encoder. Only a complete, supported
    /// single resource is eligible; Live Photos, RAW pairs and edits stay in Photos.
    func originalFile(for record: PhotoAssetRecord, workStore: MediaWorkStore, session: UUID) async throws -> PreparedGalleryMedia {
        let asset = try unchangedAsset(for: record)
        guard asset.canPerform(.delete) else { throw LibraryError.deletionUnavailable }
        let resources = PHAssetResource.assetResources(for: asset)
        guard resources.count == 1, let resource = resources.first,
              resource.type == .photo || resource.type == .video else { throw LibraryError.unsupportedOriginal }
        let suffix: String
        switch resource.uniformTypeIdentifier {
        case UTType.jpeg.identifier: suffix = "jpg"
        case UTType.png.identifier: suffix = "png"
        case UTType.heic.identifier, UTType.heif.identifier: suffix = "heic"
        case UTType.quickTimeMovie.identifier: suffix = "mov"
        case UTType.mpeg4Movie.identifier: suffix = "mp4"
        case "com.apple.m4v-video": suffix = "m4v"
        default: throw LibraryError.unsupportedOriginal
        }
        let url = try await workStore.allocate(extension: suffix, session: session)
        do {
            try await OriginalResourceWriter.write(resource, to: url)
            try Task.checkCancellation()
            let thumbnail = try await thumbnail(for: record, targetSize: CGSize(width: 600, height: 600))
            guard let preview = thumbnail.jpegData(compressionQuality: 0.85) else { throw LibraryError.imageUnavailable }
            _ = try unchangedAsset(for: record)
            return PreparedGalleryMedia(url: url, fileExtension: suffix, kind: record.kind,
                width: record.pixelWidth, height: record.pixelHeight, duration: record.duration, thumbnail: preview)
        } catch { try? await workStore.remove(url); throw error }
    }

    func deleteOriginal(_ record: PhotoAssetRecord) async throws {
        try Task.checkCancellation()
        let original = try unchangedAsset(for: record)
        guard original.canPerform(.delete) else { throw LibraryError.deletionUnavailable }
        // PhotoKit presents Apple's deletion confirmation. There is deliberately
        // no unattended retry after cancellation, relaunch, lock or a crash.
        // PhotoKit runs this callback on its own changes queue, not MainActor.
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.deleteAssets([original] as NSArray)
        }
    }

    private func unchangedAsset(for record: PhotoAssetRecord) throws -> PHAsset {
        guard record.source == .photos else { throw LibraryError.assetUnavailable }
        let original = try asset(for: record)
        guard original.modificationDate == record.modificationDate,
              original.pixelWidth == record.pixelWidth, original.pixelHeight == record.pixelHeight,
              (original.mediaType == .video) == (record.kind == .video) else { throw LibraryError.originalChanged }
        return original
    }

    func clearCachedImages() {
        imageManager.stopCachingImagesForAllAssets()
    }

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchAssets() -> [PhotoAssetRecord] {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var records: [PhotoAssetRecord] = []
        records.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            records.append(
                PhotoAssetRecord(
                    localIdentifier: asset.localIdentifier,
                    creationDate: asset.creationDate,
                    modificationDate: asset.modificationDate,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    kind: asset.mediaType == .video ? .video : .photo,
                    duration: asset.duration
                )
            )
        }
        return records
    }

    func thumbnail(for record: PhotoAssetRecord, targetSize: CGSize) async throws -> UIImage {
        let asset = try asset(for: record)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let wrapped: UncheckedImage = try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<UncheckedImage>(continuation)
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { @Sendable image, info in
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    gate.fail(LibraryError.requestCancelled)
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    gate.fail(LibraryError.underlying(error.localizedDescription))
                    return
                }
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if let image {
                    gate.succeed(UncheckedImage(value: image))
                } else {
                    gate.fail(LibraryError.imageUnavailable)
                }
            }
        }
        return wrapped.value
    }

    func originalData(for record: PhotoAssetRecord) async throws -> Data {
        let asset = try asset(for: record)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<Data>(continuation)
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { @Sendable data, _, _, info in
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    gate.fail(LibraryError.requestCancelled)
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    gate.fail(LibraryError.underlying(error.localizedDescription))
                    return
                }
                if let data {
                    gate.succeed(data)
                } else {
                    gate.fail(LibraryError.imageUnavailable)
                }
            }
        }
    }

    private func asset(for record: PhotoAssetRecord) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [record.localIdentifier],
            options: nil
        ).firstObject else {
            throw LibraryError.assetUnavailable
        }
        return asset
    }

    func videoAsset(for record: PhotoAssetRecord) async throws -> AVAsset {
        let asset = try asset(for: record)
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let wrapper: VideoAssetBox = try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate<VideoAssetBox>(continuation)
            imageManager.requestAVAsset(forVideo: asset, options: options) { @Sendable video, _, info in
                if let error = info?[PHImageErrorKey] as? Error { gate.fail(error) }
                else if let video { gate.succeed(VideoAssetBox(value: video)) }
                else { gate.fail(LibraryError.assetUnavailable) }
            }
        }
        return wrapper.value
    }
}

/// Streams the selected resource into bounded, protected scratch storage.
private final class OriginalResourceWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let output: FileHandle
    private var count = 0
    private var failure: Error?
    private var request: PHAssetResourceDataRequestID?
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    private init(url: URL) throws {
        try MediaFileProtection.createFile(url)
        output = try FileHandle(forWritingTo: url)
    }

    static func write(_ resource: PHAssetResource, to url: URL) async throws {
        let writer = try OriginalResourceWriter(url: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                writer.lock.withLock { writer.continuation = continuation }
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                let request = PHAssetResourceManager.default().requestData(for: resource, options: options,
                    dataReceivedHandler: { writer.receive($0) }, completionHandler: { writer.finish($0) })
                let stop = writer.lock.withLock { writer.request = request; return writer.failure != nil }
                if stop { PHAssetResourceManager.default().cancelDataRequest(request) }
            }
        } onCancel: { writer.cancel() }
    }

    private func receive(_ data: Data) {
        let stop: PHAssetResourceDataRequestID? = lock.withLock {
            guard !finished else { return nil }
            guard failure == nil else { return request }
            do {
                guard data.count <= PrivateMediaStore.maximumBytes - count else { throw PrivateMediaStore.StoreError.mediaTooLarge }
                try output.write(contentsOf: data)
                count += data.count
                return nil
            } catch { failure = error; return request }
        }
        if let stop { PHAssetResourceManager.default().cancelDataRequest(stop) }
    }

    private func cancel() {
        let request = lock.withLock { () -> PHAssetResourceDataRequestID? in
            guard !finished else { return nil }
            failure = CancellationError()
            return self.request
        }
        if let request { PHAssetResourceManager.default().cancelDataRequest(request) }
    }

    private func finish(_ error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        var result: Result<Void, Error>
        do {
            if let failure = failure ?? error { throw failure }
            guard count > 0 else { throw PrivateMediaStore.StoreError.invalidRecord }
            try output.synchronize()
            result = .success(())
        } catch { result = .failure(error) }
        try? output.close()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

/// Only a verified, still-authorized transfer may delete the Photos original.
@MainActor
enum PrivateGalleryMove {
    struct Result {
        let saved: PhotoAssetRecord
        let originalRemoved: Bool
        let error: Error?
    }

    static func perform(save: () async throws -> PhotoAssetRecord,
                        verify: (PhotoAssetRecord) async throws -> Void,
                        mayDelete: () -> Bool,
                        deleteOriginal: () async throws -> Void) async throws -> Result {
        let saved = try await save()
        do {
            try await verify(saved)
            try Task.checkCancellation()
            guard mayDelete() else { throw CancellationError() }
            try await deleteOriginal()
            return Result(saved: saved, originalRemoved: true, error: nil)
        } catch { return Result(saved: saved, originalRemoved: false, error: error) }
    }
}

private struct VideoAssetBox: @unchecked Sendable { let value: AVAsset }

private struct UncheckedImage: @unchecked Sendable {
    let value: UIImage
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func succeed(_ value: Value) {
        take()?.resume(returning: value)
    }

    func fail(_ error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = continuation
        continuation = nil
        return value
    }
}
