@preconcurrency import Photos
import SwiftUI

@MainActor
final class GalleryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var assets: [PhotoAssetRecord] = []
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var exportingAssetID: String?
    @Published private(set) var hasTemporaryShareFiles = false
    @Published var sharePayload: SharePayload?
    @Published var errorMessage: String?

    private let library: PhotoLibraryService
    private let exportStore: TemporaryExportStore
    private let sanitizer: ImageSanitizer
    private var started = false
    private var observesLibraryChanges = false
    private var shareExportLifecycle = ShareExportLifecycle()

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
        if observesLibraryChanges {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        try? await exportStore.purgeAll()
        hasTemporaryShareFiles = false
        authorizationStatus = library.authorizationStatus
        if canReadLibrary {
            beginObservingLibraryChangesIfNeeded()
            reload()
        }
    }

    func requestAccess() async {
        authorizationStatus = await library.requestAuthorization()
        if canReadLibrary {
            beginObservingLibraryChangesIfNeeded()
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

    private func beginObservingLibraryChangesIfNeeded() {
        guard !observesLibraryChanges else { return }
        PHPhotoLibrary.shared().register(self)
        observesLibraryChanges = true
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
            hasTemporaryShareFiles = true
            shareExportLifecycle.present(url)
            sharePayload = SharePayload(url: url, syntheticProfile: syntheticMetadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishShare() {
        let exportURL = shareExportLifecycle.dismiss()
        sharePayload = nil
        guard let exportURL else { return }
        Task {
            do {
                try await exportStore.remove(exportURL)
                hasTemporaryShareFiles = false
            } catch {
                hasTemporaryShareFiles = true
            }
        }
    }

    func purgeTemporaryExports() async {
        do {
            try await exportStore.purgeAll()
            hasTemporaryShareFiles = false
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

struct ShareExportLifecycle {
    private var presentedURL: URL?

    mutating func present(_ url: URL) {
        presentedURL = url
    }

    mutating func dismiss() -> URL? {
        defer { presentedURL = nil }
        return presentedURL
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
