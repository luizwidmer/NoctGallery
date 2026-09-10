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
    @Published private(set) var isResetting = false
    @Published private(set) var resetGeneration = UUID()
    private var operationGeneration = UUID()

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
        guard !started, !isResetting else { return }
        started = true
        let generation = operationGeneration
        do {
            try await exportStore.purgeAll()
            guard generation == operationGeneration else { return }
            hasTemporaryShareFiles = false
        } catch {
            guard generation == operationGeneration else { return }
            hasTemporaryShareFiles = true
            errorMessage = "Temporary share files could not be removed. Retry cleanup in Settings."
        }
        authorizationStatus = library.authorizationStatus
        if canReadLibrary {
            beginObservingLibraryChangesIfNeeded()
            reload()
        }
    }

    func requestAccess() async {
        guard !isResetting else { return }
        let generation = operationGeneration
        let status = await library.requestAuthorization()
        guard generation == operationGeneration else { return }
        authorizationStatus = status
        if canReadLibrary {
            beginObservingLibraryChangesIfNeeded()
            reload()
        }
    }

    func reload() {
        guard !isResetting, started else { return }
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
        guard !isResetting, exportingAssetID == nil else { return }
        let generation = operationGeneration
        let exportSession = await exportStore.currentSession()
        guard generation == operationGeneration, !isResetting else { return }
        exportingAssetID = asset.id
        defer { if generation == operationGeneration { exportingAssetID = nil } }
        do {
            let sourceData = try await library.originalData(for: asset)
            guard generation == operationGeneration, !isResetting else { return }
            let sanitizer = self.sanitizer
            let image = try await Task.detached(priority: .userInitiated) {
                try sanitizer.sanitize(
                    sourceData,
                    configuration: configuration,
                    syntheticMetadata: syntheticMetadata
                )
            }.value
            guard generation == operationGeneration, !isResetting else { return }
            let url = try await exportStore.write(image, session: exportSession)
            guard generation == operationGeneration, !isResetting else {
                try await exportStore.remove(url)
                return
            }
            hasTemporaryShareFiles = true
            shareExportLifecycle.present(url)
            sharePayload = SharePayload(url: url, syntheticProfile: syntheticMetadata)
        } catch {
            if generation == operationGeneration { errorMessage = error.localizedDescription }
        }
    }

    func purgeAndReset(defaults: UserDefaults = .standard,
                       domain: String? = Bundle.main.bundleIdentifier) async {
        guard !isResetting else { return }
        isResetting = true
        operationGeneration = UUID()
        defer { isResetting = false }
        started = false
        if observesLibraryChanges {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            observesLibraryChanges = false
        }
        sharePayload = nil
        _ = shareExportLifecycle.dismiss()
        exportingAssetID = nil
        assets = []
        library.clearCachedImages()
        do {
            try await exportStore.reset()
            hasTemporaryShareFiles = false
            if let domain { defaults.removePersistentDomain(forName: domain) }
            errorMessage = nil
            resetGeneration = UUID()
        } catch {
            hasTemporaryShareFiles = true
            errorMessage = "Reset could not finish. Retry Purge and Reset App in Settings."
        }
    }

    func finishShare() {
        let exportURL = shareExportLifecycle.dismiss()
        sharePayload = nil
        guard let exportURL else { return }
        let generation = operationGeneration
        Task {
            do {
                try await exportStore.remove(exportURL)
                guard generation == operationGeneration else { return }
                hasTemporaryShareFiles = false
            } catch {
                guard generation == operationGeneration else { return }
                hasTemporaryShareFiles = true
                errorMessage = "The temporary shared photo could not be removed. Retry cleanup in Settings."
            }
        }
    }

    func purgeTemporaryExports() async {
        guard !isResetting else { return }
        let generation = operationGeneration
        do {
            try await exportStore.purgeAll()
            guard generation == operationGeneration else { return }
            hasTemporaryShareFiles = false
        } catch {
            guard generation == operationGeneration else { return }
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
