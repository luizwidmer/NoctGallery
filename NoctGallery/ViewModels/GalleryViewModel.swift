@preconcurrency import Photos
@preconcurrency import AVFoundation
import ImageIO
import SwiftUI

struct PreparedGalleryMedia: Sendable {
    let url: URL
    let fileExtension: String
    let kind: GalleryMediaKind
    let width: Int
    let height: Int
    let duration: Double
    let thumbnail: Data
    var resources: [GalleryOriginalResource] = []
    var originalKind: GalleryOriginalKind?
    var originalCreationDate: Date?
    var sourceMetadata: [GalleryMetadataField] = []
    var allURLs: [URL] { resources.isEmpty ? [url] : resources.map(\.url) }
}

@MainActor
final class GalleryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var assets: [PhotoAssetRecord] = []
    @Published private(set) var privateAssets: [PhotoAssetRecord] = []
    @Published private(set) var organization = GalleryOrganization()
    @Published private(set) var privateUnlocked = false
    @Published private(set) var isUnlocking = false
    @Published private(set) var privateGeneration = UUID()
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var exportingAssetID: String?
    @Published private(set) var processingMessage: String?
    @Published private(set) var hasTemporaryShareFiles = false
    @Published var sharePayload: SharePayload?
    @Published var shareRequest: GalleryShareRequest?
    @Published private(set) var isOrganizing = false
    @Published var errorMessage: String?
    @Published private(set) var isResetting = false
    @Published private(set) var resetNeedsRetry = false
    @Published private(set) var resetGeneration = UUID()
    @Published var cameraMetadataMode: CameraMetadataMode { didSet { persistSettings() } }
    @Published var selectedPresetID: String { didSet { persistSettings() } }
    @Published var randomIncludesEquipment: Bool { didSet { persistSettings() } }
    @Published var randomIncludesLocation: Bool { didSet { persistSettings() } }
    @Published var randomLocationRadius: Double { didSet { persistSettings() } }
    @Published var randomLocationCenter: DecoyLocation? { didSet { persistSettings() } }
    @Published private(set) var presets: [DecoyPreset] = [] { didSet { persistSettings() } }
    @Published var shareOutputFormat: String { didSet { persistSettings() } }
    @Published var shareMaximumDimension: Int { didSet { persistSettings() } }
    @Published var shareLossyQuality: Double { didSet { persistSettings() } }
    @Published var onboardingCompleted: Bool { didSet { persistSettings() } }
    @Published private(set) var photosConnected: Bool { didSet { persistSettings() } }
    @Published private(set) var settingsLoadError: String?
    private var operationGeneration = UUID()
    let lock: GalleryLockController
    private var lockCleanup: Task<Void, Never>?
    private var conversion: Task<PreparedGalleryMedia, Error>?
    private let library: PhotoLibraryService
    private let exportStore: TemporaryExportStore
    let workStore: MediaWorkStore
    private let privateStore: PrivateMediaStore
    private let sanitizer: ImageSanitizer
    private let settingsStore: GallerySettingsStore
    private var settingsRecord: GallerySettingsRecord
    private var suppressSettingsWrites = false
    private let defaults: UserDefaults
    private let preferencesDomain: String?
    private var started = false
    private var observesLibraryChanges = false
    private var shareExportLifecycle = ShareExportLifecycle()
    private var activeShareOperation: UUID?

    init(library: PhotoLibraryService = PhotoLibraryService(),
         exportStore: TemporaryExportStore = TemporaryExportStore(),
         sanitizer: ImageSanitizer = ImageSanitizer(),
         privateStore: PrivateMediaStore = PrivateMediaStore(),
         workStore: MediaWorkStore = MediaWorkStore(), defaults: UserDefaults = .standard,
         lock: GalleryLockController = GalleryLockController(), preferencesDomain: String? = Bundle.main.bundleIdentifier,
         settingsStore providedSettingsStore: GallerySettingsStore? = nil) {
        let store = providedSettingsStore ?? GallerySettingsStore(defaults: defaults)
        let loaded: GallerySettingsRecord
        let loadError: String?
        do { loaded = try store.loadOrMigrate(); loadError = nil }
        catch { loaded = .init(); loadError = error.localizedDescription }
        self.preferencesDomain = preferencesDomain
        self.lock = lock
        self.library = library
        self.exportStore = exportStore
        self.sanitizer = sanitizer
        self.privateStore = privateStore
        self.workStore = workStore
        self.defaults = defaults
        self.settingsStore = store
        self.settingsRecord = loaded
        self.settingsLoadError = loadError
        self.authorizationStatus = library.authorizationStatus
        self.cameraMetadataMode = loaded.cameraMetadataMode
        self.selectedPresetID = loaded.selectedPresetID
        self.randomIncludesEquipment = loaded.randomIncludesEquipment
        self.randomIncludesLocation = loaded.randomIncludesLocation
        self.randomLocationRadius = loaded.randomLocationRadius
        self.randomLocationCenter = loaded.randomLocationCenter
        self.presets = loaded.presets
        self.shareOutputFormat = loaded.shareOutputFormat
        self.shareMaximumDimension = loaded.shareMaximumDimension
        self.shareLossyQuality = loaded.shareLossyQuality
        self.onboardingCompleted = loaded.onboardingCompleted
        self.photosConnected = loaded.photosConnected
        super.init()
    }

    deinit {
        if observesLibraryChanges { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    private func persistSettings() {
        guard !suppressSettingsWrites, settingsLoadError == nil else { return }
        var next = settingsRecord
        next.cameraMetadataMode = cameraMetadataMode
        next.selectedPresetID = selectedPresetID
        next.randomIncludesEquipment = randomIncludesEquipment
        next.randomIncludesLocation = randomIncludesLocation
        next.randomLocationRadius = randomLocationRadius
        next.randomLocationCenter = randomLocationCenter
        next.presets = presets
        next.shareOutputFormat = shareOutputFormat
        next.shareMaximumDimension = shareMaximumDimension
        next.shareLossyQuality = shareLossyQuality
        next.onboardingCompleted = onboardingCompleted
        next.photosConnected = photosConnected
        do { try settingsStore.save(next); settingsRecord = next }
        catch {
            settingsLoadError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func retrySettingsLoad() {
        do {
            let loaded = try settingsStore.loadOrMigrate()
            suppressSettingsWrites = true
            settingsRecord = loaded
            cameraMetadataMode = loaded.cameraMetadataMode
            selectedPresetID = loaded.selectedPresetID
            randomIncludesEquipment = loaded.randomIncludesEquipment
            randomIncludesLocation = loaded.randomIncludesLocation
            randomLocationRadius = loaded.randomLocationRadius
            randomLocationCenter = loaded.randomLocationCenter
            presets = loaded.presets
            shareOutputFormat = loaded.shareOutputFormat
            shareMaximumDimension = loaded.shareMaximumDimension
            shareLossyQuality = loaded.shareLossyQuality
            onboardingCompleted = loaded.onboardingCompleted
            photosConnected = loaded.photosConnected
            suppressSettingsWrites = false
            settingsLoadError = nil
            errorMessage = nil
            resetGeneration = UUID()
        } catch {
            suppressSettingsWrites = false
            settingsLoadError = error.localizedDescription
        }
    }

    var canReadLibrary: Bool { photosConnected && (authorizationStatus == .authorized || authorizationStatus == .limited) }
    var isProcessing: Bool { exportingAssetID != nil }
    var selectedPreset: DecoyPreset? { presets.first { $0.id.uuidString == selectedPresetID } }

    func savePreset(name: String, profile: SyntheticMetadataProfile) {
        guard (try? profile.validated()) != nil else { errorMessage = MetadataForge.ProfileError.invalidProfile.localizedDescription; return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let preset = DecoyPreset(name: trimmed.isEmpty ? profile.displayName : trimmed, profile: profile)
        presets.append(preset)
        presets = Array(presets.suffix(30))
        selectedPresetID = preset.id.uuidString
    }

    func deletePreset(_ preset: DecoyPreset) {
        presets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id.uuidString { selectedPresetID = ""; cameraMetadataMode = .clean }
    }

    func captureProfile() throws -> SyntheticMetadataProfile? {
        switch cameraMetadataMode {
        case .clean: return nil
        case .random: return MetadataForge.randomProfile(includeLocation: randomIncludesLocation, includeEquipment: randomIncludesEquipment,
            around: randomLocationCenter, radiusKilometers: randomLocationRadius)
        case .preset:
            guard let selectedPreset else { throw MetadataForge.ProfileError.invalidProfile }
            return try selectedPreset.captureProfile()
        }
    }

    func start() async {
        guard !started, !isResetting else { return }
        await lock.load()
        if let plan = lock.pendingDuress { await applyDuress(plan); return }
        guard settingsLoadError == nil else { return }
        if settingsRecord.resetPending { await purgeAndReset(); return }
        started = true
        let generation = operationGeneration
        do {
            try GalleryDuressPractice.removeAbandonedSamples()
            try await privateStore.resumeResetIfNeeded()
            try await workStore.reset()
            try await exportStore.purgeAll()
            guard generation == operationGeneration else { return }
            hasTemporaryShareFiles = false
        } catch {
            guard generation == operationGeneration else { return }
            hasTemporaryShareFiles = true
            errorMessage = "Local cleanup could not finish. Retry cleanup or reset in Settings."
        }
        authorizationStatus = library.authorizationStatus
        if canReadLibrary { beginObservingLibraryChangesIfNeeded(); reload() }
    }

    func requestAccess() async {
        guard !isResetting else { return }
        let generation = operationGeneration
        let status = await library.requestAuthorization()
        guard generation == operationGeneration else { return }
        authorizationStatus = status
        photosConnected = status == .authorized || status == .limited
        if canReadLibrary { beginObservingLibraryChangesIfNeeded(); reload() }
    }

    func reload() {
        guard !isResetting, started else { return }
        authorizationStatus = library.authorizationStatus
        guard canReadLibrary else { assets = []; return }
        isLoading = true
        assets = library.fetchAssets()
        isLoading = false
    }

    @discardableResult
    func unlockPrivate() async -> Bool {
        await lockCleanup?.value
        guard lock.isUnlocked, !isResetting, !isUnlocking else { return false }
        if privateUnlocked { return true }
        isUnlocking = true
        defer { isUnlocking = false }
        let generation = operationGeneration
        do {
            let items = try await privateStore.unlock()
            let organization = try await privateStore.organization()
            guard generation == operationGeneration, lock.isUnlocked else { await privateStore.lock(); return false }
            privateAssets = items
            self.organization = organization
            privateUnlocked = true
            privateGeneration = UUID()
            if canReadLibrary { reload() }
            return true
        } catch {
            await privateStore.lock()
            if generation == operationGeneration { errorMessage = error.localizedDescription }
            return false
        }
    }

    func lockPrivate(lockApp: Bool = true) async {
        if lockApp { lock.lock() }
        if let lockCleanup { await lockCleanup.value; return }
        operationGeneration = UUID()
        privateGeneration = UUID()
        privateUnlocked = false
        privateAssets = []
        organization = .init()
        assets = []
        let activeConversion = conversion
        activeConversion?.cancel()
        conversion = nil
        exportingAssetID = nil
        processingMessage = nil
        finishShare()
        library.clearCachedImages()
        let cleanup = Task { [privateStore, workStore, exportStore] in
            await privateStore.lock()
            // Wait for encoders to close their files before removing scratch data.
            _ = try? await activeConversion?.value
            do {
                try await workStore.reset()
                try await exportStore.reset()
                hasTemporaryShareFiles = false
            } catch { errorMessage = "Temporary media could not be removed. Retry cleanup in Settings." }
        }
        lockCleanup = cleanup
        await cleanup.value
        lockCleanup = nil
    }

    func applyDuress(_ plan: GalleryDuressPlan) async {
        guard !isResetting else { return }
        isResetting = true
        let background = UIApplication.shared.beginBackgroundTask(withName: "Finish local storage update")
        defer {
            isResetting = false
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
        await lockPrivate(lockApp: false)
        assets = []
        suppressSettingsWrites = true
        presets = []
        if observesLibraryChanges { PHPhotoLibrary.shared().unregisterChangeObserver(self); observesLibraryChanges = false }
        do {
            try await privateStore.applyDuress(plan)
            try await exportStore.reset()
            try await workStore.reset()
            cameraMetadataMode = .clean
            randomIncludesEquipment = true; randomIncludesLocation = false; randomLocationCenter = nil; randomLocationRadius = 5
            selectedPresetID = ""
            shareOutputFormat = GalleryOutputFormat.heic.rawValue
            shareMaximumDimension = 8_192
            shareLossyQuality = 0.90
            photosConnected = false
            onboardingCompleted = plan.action == .retainDecoys
            var replacementSettings = GallerySettingsRecord()
            replacementSettings.onboardingCompleted = onboardingCompleted
            try settingsStore.save(replacementSettings)
            settingsRecord = replacementSettings
            settingsLoadError = nil
            if let domain = preferencesDomain { defaults.removePersistentDomain(forName: domain) }
            try await lock.finishDuress(plan, unlock: UIApplication.shared.applicationState == .active)
            hasTemporaryShareFiles = false
            errorMessage = nil
            started = false
            resetGeneration = UUID()
        } catch {
            errorMessage = "Unable to finish setup. Close and reopen Gallery to retry."
        }
        suppressSettingsWrites = false
    }

    func thumbnail(for asset: PhotoAssetRecord, targetSize: CGSize) async -> UIImage? {
        if asset.source == .photos { return try? await library.thumbnail(for: asset, targetSize: targetSize) }
        guard privateUnlocked else { return nil }
        let generation = privateGeneration
        if asset.kind == .photo, max(targetSize.width, targetSize.height) > 600 {
            do {
                let url = try await privateSourceURL(asset)
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)
                let image = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_000
                ] as CFDictionary) }
                try await workStore.remove(url)
                guard generation == privateGeneration, let image else { return nil }
                return UIImage(cgImage: image)
            } catch { return nil }
        }
        guard let data = try? await privateStore.thumbnail(id: asset.id), generation == privateGeneration else { return nil }
        return UIImage(data: data)
    }

    func player(for asset: PhotoAssetRecord, motion: Bool = false) async throws -> (AVPlayer, URL?) {
        if asset.source == .photos { return (AVPlayer(playerItem: AVPlayerItem(asset: try await library.videoAsset(for: asset))), nil) }
        let url = try await privateSourceURL(asset, role: motion ? .pairedVideo : nil)
        guard privateUnlocked else { try? await workStore.remove(url); throw CancellationError() }
        return (AVPlayer(url: url), url)
    }

    private func privateSourceURL(_ asset: PhotoAssetRecord, role: GalleryResourceRole? = nil) async throws -> URL {
        guard privateUnlocked else { throw PrivateMediaStore.StoreError.locked }
        let privateSession = try await privateStore.currentSession()
        let workSession = await workStore.currentSession()
        let resources = try await privateStore.resources(id: asset.id)
        guard let resource = role == nil ? resources.first : resources.first(where: { $0.role == role }) else { throw PrivateMediaStore.StoreError.invalidRecord }
        let suffix = resource.fileExtension
        let url = try await workStore.allocate(extension: suffix, session: workSession)
        try await privateStore.materialize(id: asset.id, resourceID: resource.id, to: url, session: privateSession)
        return url
    }

    private func process(asset: PhotoAssetRecord, configuration: ImageSanitizer.Configuration,
                         profile: SyntheticMetadataProfile?, edits: GalleryShareEdits = .init()) async throws -> PreparedGalleryMedia {
        var source: URL?
        do {
            if asset.source == .privateLibrary { source = try await privateSourceURL(asset) }
            let session = await workStore.currentSession()
            let result: PreparedGalleryMedia
            if asset.kind == .photo {
                let data: Data
                if let source { data = try boundedPhotoData(source) }
                else { data = try await library.originalData(for: asset) }
                result = try await processPhoto(data, configuration: configuration, profile: profile, session: session, edits: edits)
            } else {
                let video: AVAsset
                if let source { video = AVURLAsset(url: source) }
                else { video = try await library.videoAsset(for: asset) }
                result = try await processVideo(video, profile: profile, session: session, edits: edits)
            }
            if let source { try await workStore.remove(source) }
            return result
        } catch { if let source { try? await workStore.remove(source) }; throw error }
    }

    private func processPhoto(_ data: Data, configuration: ImageSanitizer.Configuration,
                              profile: SyntheticMetadataProfile?, session: UUID, edits: GalleryShareEdits = .init()) async throws -> PreparedGalleryMedia {
        let store = workStore
        let sanitizer = sanitizer
        let task = Task.detached(priority: .userInitiated) {
            let sourceMetadata = try GalleryExportInspection.photoFields(data)
            let image = try sanitizer.sanitize(data, configuration: configuration, syntheticMetadata: profile, edits: edits)
            try Task.checkCancellation()
            let url = try await store.write(image.data, extension: image.fileExtension, session: session)
            do {
                var thumbnailConfiguration = ImageSanitizer.Configuration()
                thumbnailConfiguration.maximumOutputDimension = 600
                thumbnailConfiguration.outputFormat = .jpeg
                let thumbnail = try sanitizer.sanitize(image.data, configuration: thumbnailConfiguration).data
                return PreparedGalleryMedia(url: url, fileExtension: image.fileExtension, kind: .photo,
                    width: image.pixelWidth, height: image.pixelHeight, duration: 0, thumbnail: thumbnail, sourceMetadata: sourceMetadata)
            } catch { try? await store.remove(url); throw error }
        }
        conversion = task
        return try await task.value
    }

    private func processVideo(_ asset: AVAsset, profile: SyntheticMetadataProfile?, session: UUID, edits: GalleryShareEdits = .init()) async throws -> PreparedGalleryMedia {
        let store = workStore
        let task = Task.detached(priority: .userInitiated) {
            let url = try await store.allocate(extension: "mov", session: session)
            do {
                let sourceMetadata = try await GalleryExportInspection.videoFields(asset)
                let video = try await VideoSanitizer.sanitize(asset: asset, to: url, profile: profile, edits: edits)
                let thumbnail = try await VideoSanitizer.thumbnail(url: url)
                return PreparedGalleryMedia(url: url, fileExtension: "mov", kind: .video,
                    width: video.pixelWidth, height: video.pixelHeight, duration: video.duration, thumbnail: thumbnail, sourceMetadata: sourceMetadata)
            } catch { try? await store.remove(url); throw error }
        }
        conversion = task
        return try await task.value
    }

    func prepareShare(asset: PhotoAssetRecord, configuration: ImageSanitizer.Configuration,
                      syntheticMetadata: SyntheticMetadataProfile?) async {
        await prepareShares(assets: [asset], configuration: configuration, profile: syntheticMetadata)
    }

    func beginShare(_ assets: [PhotoAssetRecord], profile: SyntheticMetadataProfile? = nil) {
        guard lock.isUnlocked, !isProcessing, !isResetting, !assets.isEmpty else { return }
        guard assets.count <= 20 else { errorMessage = "Choose up to 20 items per share."; return }
        errorMessage = nil
        shareRequest = GalleryShareRequest(assets: assets, profile: profile)
    }

    func prepareShares(assets: [PhotoAssetRecord], configuration: ImageSanitizer.Configuration,
                       profile: SyntheticMetadataProfile?, edits: GalleryShareEdits = .init()) async {
        guard lock.isUnlocked, !isResetting, !isProcessing, !assets.isEmpty, assets.count <= 20 else { return }
        // Spatial edits belong to a single source, never silently copied to other items.
        guard assets.count == 1 || edits == GalleryShareEdits() else { errorMessage = "Open one item to edit its content."; return }
        let generation = operationGeneration
        let operation = UUID()
        activeShareOperation = operation
        exportingAssetID = assets[0].id
        defer {
            if activeShareOperation == operation { activeShareOperation = nil }
            if generation == operationGeneration { exportingAssetID = nil; processingMessage = nil; conversion = nil }
        }
        let exportSession = await exportStore.currentSession()
        var prepared: PreparedGalleryMedia?
        var exports: [URL] = []
        do {
            var reviewed: [GalleryReviewedExport] = []
            var total = 0
            for (index, asset) in assets.enumerated() {
                try Task.checkCancellation()
                guard generation == operationGeneration, lock.isUnlocked else { throw CancellationError() }
                processingMessage = assets.count == 1 ? "Preparing your preview…" : "Preparing \(index + 1) of \(assets.count)…"
                let media = try await process(asset: asset, configuration: configuration, profile: profile, edits: edits)
                prepared = media
                guard generation == operationGeneration else { throw CancellationError() }
                let url: URL
                if media.kind == .video { url = try await exportStore.adoptVideo(media.url, session: exportSession) }
                else {
                    let image = SanitizedImage(data: try Data(contentsOf: media.url), sourceByteCount: 0,
                        pixelWidth: media.width, pixelHeight: media.height, outputUTType: "", fileExtension: media.fileExtension,
                        sha256: "", removedMetadataKeys: [])
                    url = try await exportStore.write(image, session: exportSession)
                }
                exports.append(url)
                try? await workStore.remove(media.url)
                prepared = nil
                let inspection = try await GalleryExportInspection.inspect(url: url, kind: media.kind)
                guard inspection.byteCount <= 512 * 1_024 * 1_024 - total else { throw PrivateMediaStore.StoreError.mediaTooLarge }
                total += inspection.byteCount
                reviewed.append(.init(url: url, kind: media.kind, inspection: inspection, originalMetadata: media.sourceMetadata))
            }
            guard generation == operationGeneration, lock.isUnlocked, let first = reviewed.first else { throw CancellationError() }
            hasTemporaryShareFiles = true
            shareExportLifecycle.present(exports)
            sharePayload = SharePayload(url: first.url, syntheticProfile: profile, items: reviewed)
        } catch {
            if let prepared { try? await workStore.remove(prepared.url) }
            for url in exports { try? await exportStore.remove(url) }
            if generation == operationGeneration, !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    func shareEditorImage(for asset: PhotoAssetRecord, time: Double = 0) async throws -> UIImage {
        guard lock.isUnlocked else { throw PrivateMediaStore.StoreError.locked }
        let generation = operationGeneration
        var source: URL?
        do {
            if asset.source == .privateLibrary { source = try await privateSourceURL(asset) }
            let image: UIImage
            if asset.kind == .photo {
                let data: Data
                if let source { data = try boundedPhotoData(source) } else { data = try await library.originalData(for: asset) }
                let preview = try await Task.detached(priority: .userInitiated) {
                    var config = ImageSanitizer.Configuration()
                    config.maximumOutputDimension = 1_600; config.outputFormat = .jpeg
                    return try ImageSanitizer().sanitize(data, configuration: config).data
                }.value
                guard let decoded = UIImage(data: preview) else { throw ImageSanitizer.SanitizationError.decodeFailed }
                image = decoded
            } else {
                let video: AVAsset
                if let source { video = AVURLAsset(url: source) } else { video = try await library.videoAsset(for: asset) }
                let generator = AVAssetImageGenerator(asset: video)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1_600, height: 1_600)
                let result = try await generator.image(at: CMTime(seconds: max(0, time), preferredTimescale: 600))
                image = UIImage(cgImage: result.image)
            }
            if let source { try await workStore.remove(source) }
            try Task.checkCancellation()
            guard generation == operationGeneration, lock.isUnlocked else { throw CancellationError() }
            return image
        } catch { if let source { try? await workStore.remove(source) }; throw error }
    }

    @discardableResult
    func saveToPrivate(asset: PhotoAssetRecord, profile: SyntheticMetadataProfile?, replace: Bool = false) async -> Bool {
        guard !isResetting, !isProcessing else { return false }
        guard !replace || asset.originalKind == nil else {
            errorMessage = "Edit metadata on a shared copy to keep all original components intact."
            return false
        }
        guard await unlockPrivate() else { return false }
        let generation = operationGeneration
        exportingAssetID = asset.id
        processingMessage = "Preparing an encrypted private copy…"
        defer { if generation == operationGeneration { exportingAssetID = nil; processingMessage = nil; conversion = nil } }
        do {
            let session = try await privateStore.currentSession()
            let media = try await process(asset: asset, configuration: ImageSanitizer.Configuration(), profile: profile)
            do {
                guard generation == operationGeneration else { throw CancellationError() }
                let saved = try await keep(media, profile: profile, session: session)
                if replace && asset.source == .privateLibrary {
                    try await privateStore.copyOrganization(from: asset.id, to: saved.id, session: session)
                    try await lock.replaceDecoy(asset.id, with: saved.id)
                    try await privateStore.delete(id: asset.id, session: session)
                }
                let updated = try await privateStore.list()
                let updatedOrganization = try await privateStore.organization()
                if generation == operationGeneration { privateAssets = updated; organization = updatedOrganization }
            } catch { try? await workStore.remove(media.url); throw error }
            try await workStore.remove(media.url)
            return true
        } catch {
            if generation == operationGeneration, !(error is CancellationError) { errorMessage = error.localizedDescription }
            return false
        }
    }

    func moveToPrivate(asset: PhotoAssetRecord, savedCopyID: String? = nil) async -> PrivateGalleryMove.Result? {
        guard asset.source == .photos, !isResetting, !isProcessing, await unlockPrivate() else { return nil }
        let generation = operationGeneration
        exportingAssetID = asset.id
        processingMessage = "Saving the original privately…"
        defer { if generation == operationGeneration { exportingAssetID = nil; processingMessage = nil; conversion = nil } }
        var sources: [URL] = []
        do {
            let session = try await privateStore.currentSession()
            let workSession = await workStore.currentSession()
            let transfer = Task { try await library.originalFile(for: asset, workStore: workStore, session: workSession) }
            conversion = transfer
            let media = try await transfer.value
            sources = media.allURLs
            guard generation == operationGeneration, lock.isUnlocked else { throw CancellationError() }
            let result = try await PrivateGalleryMove.perform(save: {
                if let savedCopyID {
                    guard let existing = try await self.privateStore.list().first(where: { $0.id == savedCopyID }) else {
                        throw PrivateMediaStore.StoreError.invalidRecord
                    }
                    return existing
                }
                return try await self.keep(media, profile: nil, session: session)
            }, verify: { saved in
                self.processingMessage = "Checking the saved original…"
                try await self.privateStore.verifyOriginal(id: saved.id, originals: media.resources, session: session)
            }, mayDelete: {
                generation == self.operationGeneration && self.privateUnlocked && self.lock.isUnlocked && !self.isResetting
            }, deleteOriginal: {
                self.processingMessage = "Confirm removal in Photos…"
                try await self.library.deleteOriginal(asset)
            })
            for url in media.allURLs { try? await workStore.remove(url) }
            let updated = try await privateStore.list()
            if generation == operationGeneration {
                privateAssets = updated
                if result.originalRemoved {
                    assets.removeAll { $0.id == asset.id }
                } else if let error = result.error {
                    let nsError = error as NSError
                    if error is CancellationError || (nsError.domain == PHPhotosErrorDomain && nsError.code == PHPhotosError.Code.userCancelled.rawValue) {
                        errorMessage = "The private copy is saved. The Photos original was kept."
                    } else {
                        errorMessage = "The Photos original was kept. \(error.localizedDescription)"
                    }
                }
            }
            return result
        } catch {
            for url in sources { try? await workStore.remove(url) }
            if generation == operationGeneration, !(error is CancellationError) { errorMessage = error.localizedDescription }
            return nil
        }
    }

    func saveCapture(photo: Data?, video: URL?, profile: SyntheticMetadataProfile?) async throws {
        guard privateUnlocked, !isProcessing, !isResetting else { throw PrivateMediaStore.StoreError.locked }
        let generation = operationGeneration
        let session = try await privateStore.currentSession()
        let workSession = await workStore.currentSession()
        exportingAssetID = "camera"
        processingMessage = "Saving to your private gallery…"
        defer { if generation == operationGeneration { exportingAssetID = nil; processingMessage = nil; conversion = nil } }
        let media: PreparedGalleryMedia
        if let photo { media = try await processPhoto(photo, configuration: ImageSanitizer.Configuration(), profile: profile, session: workSession) }
        else if let video { media = try await processVideo(AVURLAsset(url: video), profile: profile, session: workSession) }
        else { throw PrivateCameraEngine.CameraError.captureFailed }
        do {
            guard generation == operationGeneration else { throw CancellationError() }
            _ = try await keep(media, profile: profile, session: session)
            let updated = try await privateStore.list()
            if generation == operationGeneration { privateAssets = updated }
            try await workStore.remove(media.url)
        } catch { try? await workStore.remove(media.url); throw error }
    }

    private func keep(_ media: PreparedGalleryMedia, profile: SyntheticMetadataProfile?, session: UUID) async throws -> PhotoAssetRecord {
        if !media.resources.isEmpty {
            return try await privateStore.saveOriginal(resources: media.resources, originalKind: media.originalKind,
                creationDate: media.originalCreationDate, kind: media.kind, width: media.width, height: media.height,
                duration: media.duration, thumbnail: media.thumbnail, session: session)
        }
        return try await privateStore.save(file: media.url, fileExtension: media.fileExtension, kind: media.kind,
            width: media.width, height: media.height, duration: media.duration, thumbnail: media.thumbnail,
            profile: profile, session: session)
    }

    func deletePrivate(_ asset: PhotoAssetRecord) async {
        guard asset.source == .privateLibrary, privateUnlocked, !isProcessing, !isOrganizing else { return }
        let generation = operationGeneration
        do {
            let session = try await privateStore.currentSession()
            try await lock.replaceDecoy(asset.id, with: nil)
            guard generation == operationGeneration else { throw CancellationError() }
            try await privateStore.delete(id: asset.id, session: session)
            let items = try await privateStore.list()
            let index = try await privateStore.organization()
            if generation == operationGeneration, privateUnlocked { privateAssets = items; organization = index }
        } catch { if generation == operationGeneration, !(error is CancellationError) { errorMessage = error.localizedDescription } }
    }

    func organize(_ ids: Set<String>, edit: GalleryOrganizationEdit) async {
        guard privateUnlocked, !isResetting, !isProcessing, !isOrganizing else { return }
        let generation = operationGeneration
        isOrganizing = true
        defer { isOrganizing = false }
        do {
            let session = try await privateStore.currentSession()
            let value = try await privateStore.organize(ids: ids, edit: edit, session: session)
            if generation == operationGeneration { organization = value }
        } catch { if generation == operationGeneration { errorMessage = error.localizedDescription } }
    }

    func saveAlbum(id: UUID? = nil, name: String) async {
        guard privateUnlocked, !isResetting, !isProcessing, !isOrganizing else { return }
        let generation = operationGeneration
        isOrganizing = true
        defer { isOrganizing = false }
        do {
            let session = try await privateStore.currentSession()
            let value = try await privateStore.saveAlbum(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), session: session)
            if generation == operationGeneration { organization = value }
        } catch { if generation == operationGeneration { errorMessage = error.localizedDescription } }
    }

    func deleteAlbum(_ id: UUID) async {
        guard privateUnlocked, !isResetting, !isProcessing, !isOrganizing else { return }
        let generation = operationGeneration
        isOrganizing = true
        defer { isOrganizing = false }
        do {
            let session = try await privateStore.currentSession()
            let value = try await privateStore.deleteAlbum(id: id, session: session)
            if generation == operationGeneration { organization = value }
        } catch { if generation == operationGeneration { errorMessage = error.localizedDescription } }
    }

    func deletePrivateItems(_ ids: Set<String>) async {
        guard ids.count <= 500 else { errorMessage = "Choose up to 500 items at a time."; return }
        errorMessage = nil
        let generation = operationGeneration
        for asset in privateAssets.filter({ ids.contains($0.id) }) {
            guard generation == operationGeneration, privateUnlocked, !isResetting, lock.isUnlocked else { return }
            await deletePrivate(asset)
            if errorMessage != nil { return }
        }
    }

    func copyPhotosToPrivate(_ assets: [PhotoAssetRecord]) async {
        guard assets.count <= 20 else { errorMessage = "Choose up to 20 items per copy."; return }
        let generation = operationGeneration
        for asset in assets {
            guard generation == operationGeneration, lock.isUnlocked, await saveToPrivate(asset: asset, profile: nil) else { return }
        }
    }

    func purgeAndReset(defaults override: UserDefaults? = nil, domain: String? = Bundle.main.bundleIdentifier) async {
        guard !isResetting else { return }
        let preferences = override ?? defaults
        do {
            var pending = settingsRecord
            pending.resetPending = true
            try settingsStore.save(pending)
            settingsRecord = pending
        } catch {
            errorMessage = "Protected reset state is unavailable. Unlock the device and retry."
            return
        }
        resetNeedsRetry = true
        isResetting = true
        suppressSettingsWrites = true
        await lockPrivate()
        defer { suppressSettingsWrites = false; isResetting = false }
        started = false
        if observesLibraryChanges { PHPhotoLibrary.shared().unregisterChangeObserver(self); observesLibraryChanges = false }
        sharePayload = nil
        _ = shareExportLifecycle.dismiss()
        assets = []
        library.clearCachedImages()
        do {
            try await privateStore.reset()
            try await lock.reset()
            try await exportStore.reset()
            try await workStore.reset()
            hasTemporaryShareFiles = false
            presets = []
            cameraMetadataMode = .clean
            randomIncludesEquipment = true; randomIncludesLocation = false; randomLocationCenter = nil; randomLocationRadius = 5
            selectedPresetID = ""
            shareOutputFormat = GalleryOutputFormat.heic.rawValue
            shareMaximumDimension = 8_192
            shareLossyQuality = 0.90
            onboardingCompleted = false
            photosConnected = false
            try settingsStore.purge()
            settingsRecord = .init()
            if let domain { preferences.removePersistentDomain(forName: domain) }
            resetNeedsRetry = false
            errorMessage = nil
            resetGeneration = UUID()
        } catch {
            hasTemporaryShareFiles = true
            errorMessage = "Reset could not finish. Retry Purge and Reset App in Settings."
        }
    }

    private func boundedPhotoData(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= ImageSanitizer.Configuration().maximumEncodedBytes else {
            throw ImageSanitizer.SanitizationError.encodedInputTooLarge(limit: ImageSanitizer.Configuration().maximumEncodedBytes)
        }
        return try Data(contentsOf: url)
    }

    func editShareAgain() async {
        guard !isProcessing else { return }
        let urls = shareExportLifecycle.dismissAll()
        sharePayload = nil
        for url in urls { try? await exportStore.remove(url) }
        hasTemporaryShareFiles = false
    }

    func finishShare() {
        let exportURLs = shareExportLifecycle.dismissAll()
        sharePayload = nil
        shareRequest = nil
        if activeShareOperation != nil {
            activeShareOperation = nil
            operationGeneration = UUID()
            conversion?.cancel()
            exportingAssetID = nil
            processingMessage = nil
        }
        guard !exportURLs.isEmpty else { return }
        let generation = operationGeneration
        Task {
            do {
                for url in exportURLs { try await exportStore.remove(url) }
                if generation == operationGeneration { hasTemporaryShareFiles = false }
            } catch { errorMessage = "A temporary share could not be removed. Retry cleanup in Settings." }
        }
    }

    func purgeTemporaryExports() async {
        guard !isResetting, !isProcessing else { return }
        do {
            try await exportStore.purgeAll()
            if !privateUnlocked { try await workStore.reset() }
            hasTemporaryShareFiles = false
        } catch { errorMessage = error.localizedDescription }
    }

    private func beginObservingLibraryChangesIfNeeded() {
        guard !observesLibraryChanges else { return }
        PHPhotoLibrary.shared().register(self)
        observesLibraryChanges = true
    }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.reload() }
    }
}

struct ShareExportLifecycle {
    private var presentedURLs: [URL] = []
    mutating func present(_ url: URL) { presentedURLs = [url] }
    mutating func present(_ urls: [URL]) { presentedURLs = urls }
    mutating func dismiss() -> URL? { dismissAll().first }
    mutating func dismissAll() -> [URL] { defer { presentedURLs = [] }; return presentedURLs }
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
