import CryptoKit
import Foundation
import Security

protocol PrivateMediaKeyStore: Sendable {
    func loadOrCreate(allowCreate: Bool) throws -> Data
    func replace(_ data: Data) throws
    func delete() throws
}

struct KeychainPrivateMediaKeyStore: PrivateMediaKeyStore {
    let service: String
    init(service: String = (Bundle.main.bundleIdentifier ?? "NoctGallery") + ".private-media.v1") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "master", kSecAttrSynchronizable as String: false]
    }

    func loadOrCreate(allowCreate: Bool) throws -> Data {
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return data }
        guard status == errSecItemNotFound, allowCreate else { throw PrivateMediaStore.StoreError.keyUnavailable }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw PrivateMediaStore.StoreError.keyUnavailable }
        var create = query
        create[kSecValueData as String] = bytes
        create[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(create as CFDictionary, nil) == errSecSuccess else { throw PrivateMediaStore.StoreError.keyUnavailable }
        return bytes
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PrivateMediaStore.StoreError.keyUnavailable }
    }

    func replace(_ data: Data) throws {
        guard data.count == 32 else { throw PrivateMediaStore.StoreError.keyUnavailable }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PrivateMediaStore.StoreError.keyUnavailable }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PrivateMediaStore.StoreError.keyUnavailable }
    }
}

/// All persistent records, thumbnails and media are encrypted. Large files are
/// sealed in bounded chunks; AAD binds each chunk to its item, position and size.
/// File-system operations are actor-serialized, including lock/reset/import.
actor PrivateMediaStore {
    enum StoreError: LocalizedError {
        case locked, keyUnavailable, invalidRecord, mediaTooLarge, resetPending
        var errorDescription: String? {
            switch self {
            case .locked: "Unlock the private gallery to continue."
            case .keyUnavailable: "The private gallery key is unavailable. Existing media has not been replaced."
            case .invalidRecord: "This private item is damaged or could not be authenticated."
            case .mediaTooLarge: "Private media must be between 1 byte and 1 GB."
            case .resetPending: "A private gallery reset must finish before opening it."
            }
        }
    }

    struct StoredRecord: Codable {
        let version: Int
        let asset: PhotoAssetRecord
        let fileExtension: String
        let byteCount: Int
        let chunkCount: Int
    }

    static let maximumBytes = 1_024 * 1_024 * 1_024
    static let chunkSize = 1_024 * 1_024
    private let root: URL
    private let keys: any PrivateMediaKeyStore
    private var master: SymmetricKey?
    private var session = UUID()
    private let manager = FileManager.default

    init(root: URL? = nil, keys: any PrivateMediaKeyStore = KeychainPrivateMediaKeyStore()) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateGallery", isDirectory: true)
        self.keys = keys
    }

    func currentSession() throws -> UUID {
        guard master != nil else { throw StoreError.locked }
        return session
    }

    func unlock() throws -> [PhotoAssetRecord] {
        if manager.fileExists(atPath: root.appendingPathComponent("reset.pending").path)
            || manager.fileExists(atPath: root.appendingPathComponent("duress.ready").path)
            || manager.fileExists(atPath: duressOld.path) { throw StoreError.resetPending }
        try MediaFileProtection.prepareDirectory(root)
        let hasItems = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .contains { UUID(uuidString: $0.lastPathComponent) != nil }
        let data = try keys.loadOrCreate(allowCreate: !hasItems)
        master = SymmetricKey(data: data)
        session = UUID()
        do {
            // Incomplete imports are never made visible as saved items.
            for url in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix("staging-") { try manager.removeItem(at: url) }
            return try list()
        } catch { master = nil; throw error }
    }

    func lock() { master = nil; session = UUID() }

    func list() throws -> [PhotoAssetRecord] {
        guard master != nil else { throw StoreError.locked }
        return try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map { try record(id: $0.lastPathComponent).asset }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    func save(file: URL, fileExtension: String, kind: GalleryMediaKind, width: Int, height: Int,
              duration: Double, thumbnail: Data, profile: SyntheticMetadataProfile?, session expected: UUID) throws -> PhotoAssetRecord {
        try requireSession(expected)
        guard ["jpg", "heic", "png", "mov", "mp4", "m4v"].contains(fileExtension),
              width > 0, height > 0, duration.isFinite, duration >= 0, thumbnail.count <= 4_194_304 else { throw StoreError.invalidRecord }
        if let profile { _ = try profile.validated() }
        let attributes = try manager.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size > 0, size <= Self.maximumBytes else { throw StoreError.mediaTooLarge }
        let id = UUID().uuidString.lowercased()
        let asset = PhotoAssetRecord(localIdentifier: id, creationDate: profile?.capturedAt ?? Date(), modificationDate: nil,
            pixelWidth: width, pixelHeight: height, kind: kind, duration: duration, source: .privateLibrary, decoyProfile: profile)
        let count = (size + Self.chunkSize - 1) / Self.chunkSize
        let record = StoredRecord(version: 1, asset: asset, fileExtension: fileExtension, byteCount: size, chunkCount: count)
        let staging = root.appendingPathComponent("staging-" + id, isDirectory: true)
        try MediaFileProtection.prepareDirectory(staging)
        do {
            let key = try itemKey(id)
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            let target = staging.appendingPathComponent("media.sealed")
            try MediaFileProtection.createFile(target)
            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }
            var total = 0
            for index in 0..<count {
                try Task.checkCancellation()
                let plain = try input.read(upToCount: min(Self.chunkSize, size - total)) ?? Data()
                guard plain.count == min(Self.chunkSize, size - total) else { throw StoreError.invalidRecord }
                let sealed = try AES.GCM.seal(plain, using: key, authenticating: aad(id, index, size)).combined!
                try output.write(contentsOf: sealed)
                total += plain.count
            }
            guard try input.read(upToCount: 1)?.isEmpty != false else { throw StoreError.invalidRecord }
            try output.synchronize()
            try seal(JSONEncoder().encode(record), to: staging.appendingPathComponent("record.sealed"), key: key, context: id + ":record")
            try seal(thumbnail, to: staging.appendingPathComponent("thumbnail.sealed"), key: key, context: id + ":thumbnail")
            try manager.moveItem(at: staging, to: itemDirectory(id))
            return asset
        } catch { try? manager.removeItem(at: staging); throw error }
    }

    func thumbnail(id: String) throws -> Data {
        let key = try itemKey(id)
        return try open(itemDirectory(id).appendingPathComponent("thumbnail.sealed"), key: key, context: id + ":thumbnail", limit: 4_194_332)
    }

    func materialize(id: String, to url: URL, session expected: UUID) throws {
        try requireSession(expected)
        let record = try record(id: id)
        let input = try FileHandle(forReadingFrom: itemDirectory(id).appendingPathComponent("media.sealed"))
        defer { try? input.close() }
        try MediaFileProtection.createFile(url)
        do {
            let output = try FileHandle(forWritingTo: url)
            defer { try? output.close() }
            let key = try itemKey(id)
            var remaining = record.byteCount
            for index in 0..<record.chunkCount {
                try Task.checkCancellation()
                let bytes = min(Self.chunkSize, remaining)
                let sealed = try input.read(upToCount: bytes + 28) ?? Data()
                guard sealed.count == bytes + 28 else { throw StoreError.invalidRecord }
                let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad(id, index, record.byteCount))
                guard plain.count == bytes else { throw StoreError.invalidRecord }
                try output.write(contentsOf: plain)
                remaining -= bytes
            }
            guard remaining == 0, try input.read(upToCount: 1)?.isEmpty != false else { throw StoreError.invalidRecord }
        } catch { try? manager.removeItem(at: url); throw error }
    }

    func fileExtension(id: String) throws -> String { try record(id: id).fileExtension }

    /// Authenticate every saved byte and compare it with the imported original
    /// before Photos deletion. This check creates no plaintext output file.
    func verifySavedCopy(id: String, original: URL, session expected: UUID) throws {
        try requireSession(expected)
        let record = try record(id: id)
        _ = try thumbnail(id: id)
        let source = try FileHandle(forReadingFrom: original)
        defer { try? source.close() }
        let encrypted = try FileHandle(forReadingFrom: itemDirectory(id).appendingPathComponent("media.sealed"))
        defer { try? encrypted.close() }
        let key = try itemKey(id)
        var remaining = record.byteCount
        for index in 0..<record.chunkCount {
            try Task.checkCancellation()
            let count = min(Self.chunkSize, remaining)
            let sealed = try encrypted.read(upToCount: count + 28) ?? Data()
            guard sealed.count == count + 28 else { throw StoreError.invalidRecord }
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key,
                                        authenticating: aad(id, index, record.byteCount))
            guard plain.count == count, plain == (try source.read(upToCount: count)) else { throw StoreError.invalidRecord }
            remaining -= count
        }
        guard remaining == 0, try source.read(upToCount: 1)?.isEmpty != false,
              try encrypted.read(upToCount: 1)?.isEmpty != false else { throw StoreError.invalidRecord }
    }

    func delete(id: String) throws {
        _ = try record(id: id)
        try manager.removeItem(at: itemDirectory(id))
    }

    func reset() throws {
        master = nil
        session = UUID()
        try MediaFileProtection.prepareDirectory(root)
        try Data([1]).write(to: root.appendingPathComponent("reset.pending"), options: [.atomic, .completeFileProtection])
        for url in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where url.lastPathComponent != "reset.pending" { try manager.removeItem(at: url) }
        try keys.delete()
        for url in [duressNext, duressOld] where manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        try manager.removeItem(at: root)
    }

    private var duressNext: URL { root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + ".duress-next") }
    private var duressOld: URL { root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + ".duress-old") }

    /// The caller persists the plan in Keychain before entering this transaction.
    /// Re-encrypt retained items in bounded memory, then atomically swap directories.
    /// Never cancel a committed action on backgrounding; resume it before any unlock.
    func applyDuress(_ plan: GalleryDuressPlan) throws {
        guard plan.replacementMediaKey.count == 32,
              plan.action != .reset || plan.retainedIDs.isEmpty else { throw StoreError.invalidRecord }
        master = nil
        session = UUID()
        defer { master = nil }
        let markerName = "duress.ready"
        let marker = Data(plan.id.uuidString.utf8)
        func isReady(_ directory: URL) -> Bool {
            (try? Data(contentsOf: directory.appendingPathComponent(markerName))) == marker
        }
        if manager.fileExists(atPath: duressOld.path) {
            if !manager.fileExists(atPath: root.path), isReady(duressNext) {
                try manager.moveItem(at: duressNext, to: root)
            }
            guard isReady(root) else { throw StoreError.invalidRecord }
        } else if !isReady(root) {
            if manager.fileExists(atPath: duressNext.path) { try manager.removeItem(at: duressNext) }
            try MediaFileProtection.prepareDirectory(root)
            try MediaFileProtection.prepareDirectory(duressNext)
            if !plan.retainedIDs.isEmpty {
                master = SymmetricKey(data: try keys.loadOrCreate(allowCreate: false))
                let existing = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    .filter { plan.retainedIDs.contains($0.lastPathComponent) }
                for source in existing { try rekey(id: source.lastPathComponent, to: duressNext, newMaster: plan.replacementMediaKey) }
            }
            try marker.write(to: duressNext.appendingPathComponent(markerName), options: [.atomic, .completeFileProtection])
            try manager.moveItem(at: root, to: duressOld)
            try manager.moveItem(at: duressNext, to: root)
        }
        // Update the one persistent media key before retiring old ciphertext.
        // If this fails, the Keychain plan and ready marker make retry idempotent.
        try keys.replace(plan.replacementMediaKey)
        if manager.fileExists(atPath: duressOld.path) { try manager.removeItem(at: duressOld) }
        let ready = root.appendingPathComponent(markerName)
        if manager.fileExists(atPath: ready.path) { try manager.removeItem(at: ready) }
    }

    private func rekey(id: String, to directory: URL, newMaster: Data) throws {
        let record = try record(id: id)
        let oldKey = try itemKey(id)
        let newKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: newMaster), salt: Data(id.utf8),
            info: Data("NoctGallery.private-media.v1".utf8), outputByteCount: 32)
        let destination = directory.appendingPathComponent(id)
        try MediaFileProtection.prepareDirectory(destination)
        try seal(JSONEncoder().encode(record), to: destination.appendingPathComponent("record.sealed"), key: newKey, context: id + ":record")
        try seal(thumbnail(id: id), to: destination.appendingPathComponent("thumbnail.sealed"), key: newKey, context: id + ":thumbnail")
        let input = try FileHandle(forReadingFrom: itemDirectory(id).appendingPathComponent("media.sealed"))
        defer { try? input.close() }
        let target = destination.appendingPathComponent("media.sealed")
        try MediaFileProtection.createFile(target)
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        var remaining = record.byteCount
        for index in 0..<record.chunkCount {
            let bytes = min(Self.chunkSize, remaining)
            let encrypted = try input.read(upToCount: bytes + 28) ?? Data()
            guard encrypted.count == bytes + 28 else { throw StoreError.invalidRecord }
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: oldKey,
                authenticating: aad(id, index, record.byteCount))
            guard plain.count == bytes else { throw StoreError.invalidRecord }
            try output.write(contentsOf: AES.GCM.seal(plain, using: newKey, authenticating: aad(id, index, record.byteCount)).combined!)
            remaining -= bytes
        }
        guard remaining == 0, try input.read(upToCount: 1)?.isEmpty != false else { throw StoreError.invalidRecord }
        try output.synchronize()
    }

    func resumeResetIfNeeded() throws {
        if manager.fileExists(atPath: root.appendingPathComponent("reset.pending").path) { try reset() }
    }

    private func requireSession(_ expected: UUID) throws {
        guard master != nil else { throw StoreError.locked }
        guard expected == session else { throw CancellationError() }
    }

    private func itemDirectory(_ id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else { throw StoreError.invalidRecord }
        return root.appendingPathComponent(id, isDirectory: true)
    }

    private func itemKey(_ id: String) throws -> SymmetricKey {
        _ = try itemDirectory(id)
        guard let master else { throw StoreError.locked }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: Data(id.utf8),
            info: Data("NoctGallery.private-media.v1".utf8), outputByteCount: 32)
    }

    private func aad(_ id: String, _ index: Int, _ total: Int) -> Data { Data("\(id):media:\(index):\(total)".utf8) }

    private func record(id: String) throws -> StoredRecord {
        let data = try open(itemDirectory(id).appendingPathComponent("record.sealed"), key: itemKey(id), context: id + ":record", limit: 65_536)
        let record = try JSONDecoder().decode(StoredRecord.self, from: data)
        guard record.version == 1, record.asset.id == id, record.asset.source == .privateLibrary,
              (1...Self.maximumBytes).contains(record.byteCount),
              record.chunkCount == (record.byteCount + Self.chunkSize - 1) / Self.chunkSize,
              ["jpg", "heic", "png", "mov", "mp4", "m4v"].contains(record.fileExtension) else { throw StoreError.invalidRecord }
        return record
    }

    private func seal(_ data: Data, to url: URL, key: SymmetricKey, context: String) throws {
        let sealed = try AES.GCM.seal(data, using: key, authenticating: Data(context.utf8)).combined!
        try sealed.write(to: url, options: [.atomic, .completeFileProtection])
        try MediaFileProtection.protect(url)
    }

    private func open(_ url: URL, key: SymmetricKey, context: String, limit: Int) throws -> Data {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= limit else { throw StoreError.invalidRecord }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: url)), using: key, authenticating: Data(context.utf8))
    }
}

enum MediaFileProtection {
    static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw PrivateMediaStore.StoreError.invalidRecord }
        try protect(url, permissions: 0o700)
    }
    static func createFile(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path),
              FileManager.default.createFile(atPath: url.path, contents: nil,
                attributes: [.posixPermissions: 0o600, .protectionKey: FileProtectionType.complete]) else { throw PrivateMediaStore.StoreError.invalidRecord }
        try protect(url)
    }
    static func protect(_ url: URL, permissions: Int = 0o600) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions, .protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

/// A protected, backup-excluded scratch directory for capture, conversion and
/// playback. Callers own exact leases; launch and lock invalidate old leases.
actor MediaWorkStore {
    private let root: URL
    private var session = UUID()
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("NoctGalleryMediaWork", isDirectory: true)
    }
    func currentSession() -> UUID { session }
    func allocate(extension suffix: String, session expected: UUID) throws -> URL {
        guard session == expected else { throw CancellationError() }
        guard ["jpg", "heic", "png", "mov", "mp4", "m4v"].contains(suffix) else { throw PrivateMediaStore.StoreError.invalidRecord }
        try MediaFileProtection.prepareDirectory(root)
        return root.appendingPathComponent(UUID().uuidString.lowercased() + "." + suffix)
    }
    func write(_ data: Data, extension suffix: String, session expected: UUID) throws -> URL {
        let url = try allocate(extension: suffix, session: expected)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try MediaFileProtection.protect(url)
            return url
        } catch { try? remove(url); throw error }
    }
    func remove(_ url: URL) throws {
        guard url.standardizedFileURL.deletingLastPathComponent() == root.standardizedFileURL else { throw PrivateMediaStore.StoreError.invalidRecord }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func reset() throws {
        session = UUID()
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
}
