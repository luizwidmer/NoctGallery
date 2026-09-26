import Foundation
import Security

/// Device-local settings contain decoy locations and camera presets. A single
/// Keychain record keeps them encrypted together across app restarts.
struct GallerySettingsRecord: Codable, Equatable {
    var cameraMetadataMode = CameraMetadataMode.clean
    var selectedPresetID = ""
    var randomIncludesEquipment = true
    var randomIncludesLocation = false
    var randomLocationRadius = 5.0
    var randomLocationCenter: DecoyLocation?
    var presets: [DecoyPreset] = []
    var shareOutputFormat = GalleryOutputFormat.heic.rawValue
    var shareMaximumDimension = 8_192
    var shareLossyQuality = 0.90
    var onboardingCompleted = false
    var photosConnected = false
    var resetPending = false

    func validated() throws -> Self {
        guard [0.5, 1, 5, 10, 25].contains(randomLocationRadius),
              randomLocationCenter?.isValid != false,
              presets.count <= 30,
              presets.allSatisfy({ (try? $0.profile.validated()) != nil }),
              GalleryOutputFormat(rawValue: shareOutputFormat) != nil,
              [2_048, 4_096, 8_192].contains(shareMaximumDimension),
              shareLossyQuality.isFinite, (0.65...1.0).contains(shareLossyQuality) else {
            throw GallerySettingsError.invalidRecord
        }
        return self
    }
}

enum GallerySettingsError: LocalizedError {
    case unavailable
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .unavailable: "Protected Gallery settings are unavailable. Unlock the device and try again."
        case .invalidRecord: "Protected Gallery settings could not be read. Existing settings were not replaced."
        }
    }
}

@MainActor
struct GallerySettingsStore {
    private static let maximumBytes = 512 * 1_024
    private static let legacyKeys = ["camera.metadataMode", "camera.presetID", "camera.randomEquipment",
        "camera.randomGPS", "camera.randomRadius", "camera.randomCenter", "decoy.presets",
        "share.outputFormat", "share.maximumDimension", "share.lossyQuality",
        "onboarding.completed", "photos.connected", "reset.pending"]

    let service: String
    let defaults: UserDefaults

    init(service: String = (Bundle.main.bundleIdentifier ?? "NoctGallery") + ".settings.v1",
         defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "settings",
         kSecAttrSynchronizable as String: false]
    }

    func loadOrMigrate() throws -> GallerySettingsRecord {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        switch SecItemCopyMatching(request as CFDictionary, &result) {
        case errSecSuccess:
            guard var data = result as? Data else { throw GallerySettingsError.invalidRecord }
            defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
            guard data.count <= Self.maximumBytes,
                  let record = try? JSONDecoder().decode(GallerySettingsRecord.self, from: data) else {
                throw GallerySettingsError.invalidRecord
            }
            let checked = try record.validated()
            clearLegacyDefaults()
            return checked
        case errSecItemNotFound:
            guard Self.legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return .init() }
            let record = try legacyRecord().validated()
            try save(record)
            return record
        default:
            throw GallerySettingsError.unavailable
        }
    }

    func save(_ record: GallerySettingsRecord) throws {
        var data = try JSONEncoder().encode(record.validated())
        defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
        guard data.count <= Self.maximumBytes else { throw GallerySettingsError.invalidRecord }
        let update = [kSecValueData as String: data] as CFDictionary
        var status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(query as CFDictionary, update) }
        }
        guard status == errSecSuccess else { throw GallerySettingsError.unavailable }
        clearLegacyDefaults()
    }

    func purge() throws {
        clearLegacyDefaults()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GallerySettingsError.unavailable
        }
    }

    private func legacyRecord() throws -> GallerySettingsRecord {
        var record = GallerySettingsRecord()
        if let raw = defaults.string(forKey: "camera.metadataMode") {
            guard let mode = CameraMetadataMode(rawValue: raw) else { throw GallerySettingsError.invalidRecord }
            record.cameraMetadataMode = mode
        }
        record.selectedPresetID = defaults.string(forKey: "camera.presetID") ?? ""
        if let value = defaults.object(forKey: "camera.randomEquipment") as? Bool { record.randomIncludesEquipment = value }
        if let value = defaults.object(forKey: "camera.randomGPS") as? Bool { record.randomIncludesLocation = value }
        if defaults.object(forKey: "camera.randomRadius") != nil { record.randomLocationRadius = defaults.double(forKey: "camera.randomRadius") }
        if var data = defaults.data(forKey: "camera.randomCenter") {
            defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
            guard data.count <= 4_096,
                  let center = try? JSONDecoder().decode(DecoyLocation?.self, from: data) else {
                throw GallerySettingsError.invalidRecord
            }
            record.randomLocationCenter = center
        }
        if var data = defaults.data(forKey: "decoy.presets") {
            defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
            guard data.count <= 262_144,
                  let presets = try? JSONDecoder().decode([DecoyPreset].self, from: data) else {
                throw GallerySettingsError.invalidRecord
            }
            record.presets = presets
        }
        if let raw = defaults.string(forKey: "share.outputFormat") { record.shareOutputFormat = raw }
        if defaults.object(forKey: "share.maximumDimension") != nil { record.shareMaximumDimension = defaults.integer(forKey: "share.maximumDimension") }
        if defaults.object(forKey: "share.lossyQuality") != nil { record.shareLossyQuality = defaults.double(forKey: "share.lossyQuality") }
        record.onboardingCompleted = defaults.bool(forKey: "onboarding.completed")
        record.photosConnected = defaults.bool(forKey: "photos.connected")
        record.resetPending = defaults.bool(forKey: "reset.pending")
        return record
    }

    private func clearLegacyDefaults() {
        for key in Self.legacyKeys { defaults.removeObject(forKey: key) }
    }
}
