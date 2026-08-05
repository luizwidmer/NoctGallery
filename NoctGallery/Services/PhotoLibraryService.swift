@preconcurrency import Photos
import UIKit

@MainActor
final class PhotoLibraryService {
    enum LibraryError: LocalizedError {
        case accessUnavailable
        case assetUnavailable
        case imageUnavailable
        case requestCancelled
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .accessUnavailable: "Photo library access is unavailable."
            case .assetUnavailable: "This photo is no longer in the library."
            case .imageUnavailable: "The original image data is unavailable."
            case .requestCancelled: "The photo request was cancelled."
            case .underlying(let message): message
            }
        }
    }

    private let imageManager = PHCachingImageManager()

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
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
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
                    pixelHeight: asset.pixelHeight
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
            ) { image, info in
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
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
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
}

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
