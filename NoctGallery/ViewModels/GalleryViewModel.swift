@preconcurrency import Photos
import SwiftUI

@MainActor
final class GalleryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var assets: [PhotoAssetRecord] = []
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var exportingAssetID: String?
    @Published var sharePayload: SharePayload?
    @Published var errorMessage: String?

    private let library: PhotoLibraryService
    private let exportStore: TemporaryExportStore
    private let sanitizer: ImageSanitizer
    private var started = false

    init(
        library: PhotoLibraryService = PhotoLibraryService(),
        exportStore: TemporaryExportStore = TemporaryExportStore(),
        sanitizer: ImageSanitizer = ImageSanitizer()
    ) {
        self.library = library
        self.exportStore = exportStore
        self.sanitizer = sanitizer
        self.authorizationStatus = library.authorizationStatus
        super.init()
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func start() async {
        guard !started else { return }
        started = true
        PHPhotoLibrary.shared().register(self)
        try? await exportStore.purgeAll()
        authorizationStatus = library.authorizationStatus
        if canReadLibrary {
            reload()
        }
    }

    func requestAccess() async {
        authorizationStatus = await library.requestAuthorization()
        if canReadLibrary {
            reload()
        }
    }

    func reload() {
        authorizationStatus = library.authorizationStatus
        guard canReadLibrary else {
            assets = []
            return
        }
        isLoading = true
        assets = library.fetchAssets()
        isLoading = false
    }

    var canReadLibrary: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func thumbnail(for asset: PhotoAssetRecord, targetSize: CGSize) async -> UIImage? {
        try? await library.thumbnail(for: asset, targetSize: targetSize)
    }

    func prepareShare(
        asset: PhotoAssetRecord,
        configuration: ImageSanitizer.Configuration,
        syntheticMetadata: SyntheticMetadataProfile?
    ) async {
        guard exportingAssetID == nil else { return }
        exportingAssetID = asset.id
        defer { exportingAssetID = nil }
        do {
            let sourceData = try await library.originalData(for: asset)
            let sanitizer = self.sanitizer
            let image = try await Task.detached(priority: .userInitiated) {
                try sanitizer.sanitize(
                    sourceData,
                    configuration: configuration,
                    syntheticMetadata: syntheticMetadata
                )
            }.value
            let url = try await exportStore.write(image)
            sharePayload = SharePayload(url: url, syntheticProfile: syntheticMetadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishShare() {
        guard let payload = sharePayload else { return }
        sharePayload = nil
        Task {
            try? await exportStore.remove(payload.url)
        }
    }

    func purgeTemporaryExports() async {
        do {
            try await exportStore.purgeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.reload()
        }
    }
}
enum GalleryPreferences {
    static func configuration(format: String, maximumDimension: Int, quality: Double) -> ImageSanitizer.Configuration {
        var configuration = ImageSanitizer.Configuration()
        configuration.outputFormat = GalleryOutputFormat(rawValue: format) ?? .heic
        configuration.maximumOutputDimension = maximumDimension
        configuration.lossyQuality = quality
        return configuration
    }
}
