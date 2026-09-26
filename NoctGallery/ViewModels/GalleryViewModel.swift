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
}

@MainActor
final class GalleryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var assets: [PhotoAssetRecord] = []
    @Published private(set) var privateAssets: [PhotoAssetRecord] = []
    @Published private(set) var privateUnlocked = false
    @Published private(set) var isUnlocking = false
    @Published private(set) var privateGeneration = UUID()
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published private(set) var exportingAssetID: String?
    @Published private(set) var processingMessage: String?
    @Published private(set) var hasTemporaryShareFiles = false
    @Published var sharePayload: SharePayload?
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
            guard generation == operationGeneration, lock.isUnlocked else { await privateStore.lock(); return false }
            privateAssets = items
            privateUnlocked = true
            privateGeneration = UUID()
            if canReadLibrary { reload() }
            return true
        } catch {
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

    func player(for asset: PhotoAssetRecord) async throws -> (AVPlayer, URL?) {
        if asset.source == .photos { return (AVPlayer(playerItem: AVPlayerItem(asset: try await library.videoAsset(for: asset))), nil) }
        let url = try await privateSourceURL(asset)
        guard privateUnlocked else { try? await workStore.remove(url); throw CancellationError() }
        return (AVPlayer(url: url), url)
    }

    private func privateSourceURL(_ asset: PhotoAssetRecord) async throws -> URL {
        guard privateUnlocked else { throw PrivateMediaStore.StoreError.locked }
        let privateSession = try await privateStore.currentSession()
        let workSession = await workStore.currentSession()
        let suffix = try await privateStore.fileExtension(id: asset.id)
        let url = try await workStore.allocate(extension: suffix, session: workSession)
        try await privateStore.materialize(id: asset.id, to: url, session: privateSession)
        return url
    }

    private func process(asset: PhotoAssetRecord, configuration: ImageSanitizer.Configuration,
                         profile: SyntheticMetadataProfile?) async throws -> PreparedGalleryMedia {
        var source: URL?
        do {
            if asset.source == .privateLibrary { source = try await privateSourceURL(asset) }
            let session = await workStore.currentSession()
            let result: PreparedGalleryMedia
            if asset.kind == .photo {
                let data: Data
                if let source { data = try Data(contentsOf: source) }
                else { data = try await library.originalData(for: asset) }
                result = try await processPhoto(data, configuration: configuration, profile: profile, session: session)
            } else {
                let video: AVAsset
                if let source { video = AVURLAsset(url: source) }
                else { video = try await library.videoAsset(for: asset) }
                result = try await processVideo(video, profile: profile, session: session)
            }
            if let source { try await workStore.remove(source) }
            return result
        } catch { if let source { try? await workStore.remove(source) }; throw error }
    }

    private func processPhoto(_ data: Data, configuration: ImageSanitizer.Configuration,
                              profile: SyntheticMetadataProfile?, session: UUID) async throws -> PreparedGalleryMedia {
        let store = workStore
        let sanitizer = sanitizer
        let task = Task.detached(priority: .userInitiated) {
            let image = try sanitizer.sanitize(data, configuration: configuration, syntheticMetadata: profile)
            try Task.checkCancellation()
            let url = try await store.write(image.data, extension: image.fileExtension, session: session)
            do {
                var thumbnailConfiguration = ImageSanitizer.Configuration()
                thumbnailConfiguration.maximumOutputDimension = 600
                thumbnailConfiguration.outputFormat = .jpeg
                let thumbnail = try sanitizer.sanitize(image.data, configuration: thumbnailConfiguration).data
                return PreparedGalleryMedia(url: url, fileExtension: image.fileExtension, kind: .photo,
                    width: image.pixelWidth, height: image.pixelHeight, duration: 0, thumbnail: thumbnail)
            } catch { try? await store.remove(url); throw error }
        }
        conversion = task
        return try await task.value
    }

    private func processVideo(_ asset: AVAsset, profile: SyntheticMetadataProfile?, session: UUID) async throws -> PreparedGalleryMedia {
        let store = workStore
        let task = Task.detached(priority: .userInitiated) {
            let url = try await store.allocate(extension: "mov", session: session)
            do {
                let video = try await VideoSanitizer.sanitize(asset: asset, to: url, profile: profile)
                let thumbnail = try await VideoSanitizer.thumbnail(url: url)
                return PreparedGalleryMedia(url: url, fileExtension: "mov", kind: .video,
                    width: video.pixelWidth, height: video.pixelHeight, duration: video.duration, thumbnail: thumbnail)
            } catch { try? await store.remove(url); throw error }
        }
        conversion = task
        return try await task.value
    }

    func prepareShare(asset: PhotoAssetRecord, configuration: ImageSanitizer.Configuration,
                      syntheticMetadata: SyntheticMetadataProfile?) async {
        guard !isResetting, !isProcessing else { return }
        let generation = operationGeneration
        let exportSession = await exportStore.currentSession()
        exportingAssetID = asset.id
        processingMessage = asset.kind == .video ? "Rebuilding video and audio…" : "Preparing a clean copy…"
        defer { if generation == operationGeneration { exportingAssetID = nil; processingMessage = nil; conversion = nil } }
        var prepared: PreparedGalleryMedia?
        do {
            let media = try await process(asset: asset, configuration: configuration, profile: syntheticMetadata)
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
            try? await workStore.remove(media.url)
            guard generation == operationGeneration else { try await exportStore.remove(url); return }
            hasTemporaryShareFiles = true
            shareExportLifecycle.present(url)
            sharePayload = SharePayload(url: url, syntheticProfile: syntheticMetadata)
        } catch {
            if let prepared { try? await workStore.remove(prepared.url) }
            if generation == operationGeneration, !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    @discardableResult
    func saveToPrivate(asset: PhotoAssetRecord, profile: SyntheticMetadataProfile?, replace: Bool = false) async -> Bool {
        guard !isResetting, !isProcessing else { return false }
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
                    try await lock.replaceDecoy(asset.id, with: saved.id)
                    try await privateStore.delete(id: asset.id)
                }
                if generation == operationGeneration { privateAssets = try await privateStore.list() }
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
        var source: URL?
        do {
            let session = try await privateStore.currentSession()
            let workSession = await workStore.currentSession()
            let transfer = Task { try await library.originalFile(for: asset, workStore: workStore, session: workSession) }
            conversion = transfer
            let media = try await transfer.value
            source = media.url
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
                try await self.privateStore.verifySavedCopy(id: saved.id, original: media.url, session: session)
            }, mayDelete: {
                generation == self.operationGeneration && self.privateUnlocked && self.lock.isUnlocked && !self.isResetting
            }, deleteOriginal: {
                self.processingMessage = "Confirm removal in Photos…"
                try await self.library.deleteOriginal(asset)
            })
            try? await workStore.remove(media.url)
            if generation == operationGeneration {
                privateAssets = try await privateStore.list()
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
            if let source { try? await workStore.remove(source) }
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
            if generation == operationGeneration { privateAssets = try await privateStore.list() }
            try await workStore.remove(media.url)
        } catch { try? await workStore.remove(media.url); throw error }
    }

    private func keep(_ media: PreparedGalleryMedia, profile: SyntheticMetadataProfile?, session: UUID) async throws -> PhotoAssetRecord {
        try await privateStore.save(file: media.url, fileExtension: media.fileExtension, kind: media.kind,
            width: media.width, height: media.height, duration: media.duration, thumbnail: media.thumbnail,
            profile: profile, session: session)
    }

    func deletePrivate(_ asset: PhotoAssetRecord) async {
        guard asset.source == .privateLibrary, privateUnlocked, !isProcessing else { return }
        do { try await lock.replaceDecoy(asset.id, with: nil); try await privateStore.delete(id: asset.id); privateAssets = try await privateStore.list() }
        catch { errorMessage = error.localizedDescription }
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

    func finishShare() {
        let exportURL = shareExportLifecycle.dismiss()
        sharePayload = nil
        guard let exportURL else { return }
        let generation = operationGeneration
        Task {
            do {
                try await exportStore.remove(exportURL)
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
    private var presentedURL: URL?
    mutating func present(_ url: URL) { presentedURL = url }
    mutating func dismiss() -> URL? { defer { presentedURL = nil }; return presentedURL }
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
