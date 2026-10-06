import CryptoKit
import Darwin
import Foundation
import Security
import UniformTypeIdentifiers

/// Shared with the import extension. Only ciphertext and a recipient PUBLIC
/// key cross the app-group boundary. The vault and recipient private key do not.
struct GalleryImportInbox: Sendable {
    static let maximumBytes = 1_024 * 1_024 * 1_024
    static let chunkSize = 1_024 * 1_024
    let root: URL

    enum InboxError: LocalizedError {
        case unavailable, invalid, full, setupNeeded
        var errorDescription: String? {
            switch self {
            case .unavailable: "The protected import inbox is unavailable."
            case .invalid: "This incoming file is invalid or could not be authenticated."
            case .full: "The incoming queue holds up to 20 files and 1 GB. Open Gallery to import or clear it first."
            case .setupNeeded: "Open NoctGallery once to prepare its encrypted import inbox, then share again."
            }
        }
    }

    struct Metadata: Codable, Sendable {
        var version = 1
        var typeIdentifier: String
        var byteCount: Int
        var chunkCount: Int
    }
    private struct Header: Codable {
        var version = 1
        var senderPublicKey: Data
        var recipientHash: Data
        var metadata: Data
    }

    static func appInbox() throws -> Self {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "GalleryImportAppGroup") as? String,
              group.hasPrefix("group."), let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw InboxError.unavailable
        }
        return Self(root: container.appendingPathComponent("GalleryInbox", isDirectory: true))
    }

    func publish(_ publicKey: Data) throws {
        guard publicKey.count == 32 else { throw InboxError.invalid }
        try withLock {
            let url = root.appendingPathComponent("recipient.pub")
            if FileManager.default.fileExists(atPath: url.path) {
                guard try regularData(url, limit: 32) == publicKey else { throw InboxError.invalid }
            } else {
                try publicKey.write(to: url, options: [.atomic, .completeFileProtection]); try protect(url)
            }
        }
    }

    func pending() throws -> [URL] { try withLock { try files() } }

    func enqueue(source: URL, typeIdentifier: String, cancelled: @Sendable () -> Bool = { Task.isCancelled }) throws -> URL {
        guard typeIdentifier.utf8.count <= 256, let type = UTType(typeIdentifier), type.conforms(to: .image) || type.conforms(to: .movie) else { throw InboxError.invalid }
        return try withLock {
            let recipientURL = root.appendingPathComponent("recipient.pub")
            guard FileManager.default.fileExists(atPath: recipientURL.path) else { throw InboxError.setupNeeded }
            let recipientData = try regularData(recipientURL, limit: 32)
            guard recipientData.count == 32 else { throw InboxError.invalid }
            let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  let bytes = (attrs[.size] as? NSNumber)?.intValue, bytes > 0, bytes <= Self.maximumBytes else { throw InboxError.invalid }
            let current = try files()
            let used = try current.reduce(Int64(0)) { $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
            guard current.count < 20, used + Int64(bytes) <= Self.maximumBytes else { throw InboxError.full }
            let sender = Curve25519.KeyAgreement.PrivateKey()
            let key = try derive(sender, recipient: Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientData))
            let metadata = Metadata(typeIdentifier: typeIdentifier, byteCount: bytes, chunkCount: (bytes + Self.chunkSize - 1) / Self.chunkSize)
            let context = Data("NoctGallery.incoming.metadata.v1".utf8) + sender.publicKey.rawRepresentation + recipientData
            let encoded = try JSONEncoder().encode(metadata)
            let sealed = try AES.GCM.seal(encoded, using: key, authenticating: context).combined!
            let header = Header(senderPublicKey: sender.publicKey.rawRepresentation, recipientHash: Data(SHA256.hash(data: recipientData)), metadata: sealed)
            let headerData = try JSONEncoder().encode(header)
            guard headerData.count <= 4_096 else { throw InboxError.invalid }
            let encryptedSize = Int64(4 + headerData.count + bytes + 28 * metadata.chunkCount)
            guard used + encryptedSize <= Self.maximumBytes else { throw InboxError.full }
            let token = UUID().uuidString.lowercased()
            let staging = root.appendingPathComponent(token + ".staging")
            let destination = root.appendingPathComponent(token + ".incoming")
            guard FileManager.default.createFile(atPath: staging.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600]) else { throw InboxError.unavailable }
            try protect(staging)
            do {
                let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: staging)
                defer { try? input.close(); try? output.close() }
                var size = UInt32(headerData.count).bigEndian
                try output.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) })
                try output.write(contentsOf: headerData)
                let aad = Data(SHA256.hash(data: headerData))
                var remaining = bytes
                for index in 0..<metadata.chunkCount {
                    if cancelled() { throw CancellationError() }
                    try Task.checkCancellation()
                    var data = try input.read(upToCount: min(Self.chunkSize, remaining)) ?? Data()
                    defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
                    guard data.count == min(Self.chunkSize, remaining) else { throw InboxError.invalid }
                    try output.write(contentsOf: AES.GCM.seal(data, using: key, authenticating: chunkAAD(aad, index: index, total: bytes)).combined!)
                    remaining -= data.count
                }
                guard remaining == 0, try input.read(upToCount: 1)?.isEmpty != false else { throw InboxError.invalid }
                try output.synchronize()
                if cancelled() { throw CancellationError() }
                try FileManager.default.moveItem(at: staging, to: destination)
                return destination
            } catch { try? FileManager.default.removeItem(at: staging); throw error }
        }
    }

    func decrypt(_ item: URL, using privateKey: Curve25519.KeyAgreement.PrivateKey, to destination: URL) throws -> Metadata {
        try withLock {
            guard contains(item) else { throw InboxError.invalid }
            let attrs = try FileManager.default.attributesOfItem(atPath: item.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  let storedSize = (attrs[.size] as? NSNumber)?.intValue, storedSize <= Self.maximumBytes + 65_536 else { throw InboxError.invalid }
            let input = try FileHandle(forReadingFrom: item)
            defer { try? input.close() }
            let sizeData = try input.read(upToCount: 4) ?? Data()
            guard sizeData.count == 4 else { throw InboxError.invalid }
            let headerSize = sizeData.reduce(0) { ($0 << 8) | Int($1) }
            guard (1...4_096).contains(headerSize) else { throw InboxError.invalid }
            let headerData = try input.read(upToCount: headerSize) ?? Data()
            guard headerData.count == headerSize else { throw InboxError.invalid }
            let header = try JSONDecoder().decode(Header.self, from: headerData)
            let publicKey = privateKey.publicKey.rawRepresentation
            guard header.version == 1, header.senderPublicKey.count == 32, header.metadata.count <= 2_048,
                  header.recipientHash == Data(SHA256.hash(data: publicKey)) else { throw InboxError.invalid }
            let key = try derive(privateKey, recipient: Curve25519.KeyAgreement.PublicKey(rawRepresentation: header.senderPublicKey), salt: publicKey)
            let context = Data("NoctGallery.incoming.metadata.v1".utf8) + header.senderPublicKey + publicKey
            var metadataData = try AES.GCM.open(AES.GCM.SealedBox(combined: header.metadata), using: key, authenticating: context)
            defer { metadataData.resetBytes(in: metadataData.startIndex..<metadataData.endIndex) }
            let metadata = try JSONDecoder().decode(Metadata.self, from: metadataData)
            guard metadata.version == 1, metadata.typeIdentifier.utf8.count <= 256, let type = UTType(metadata.typeIdentifier),
                  type.conforms(to: .image) || type.conforms(to: .movie), (1...Self.maximumBytes).contains(metadata.byteCount),
                  metadata.chunkCount == (metadata.byteCount + Self.chunkSize - 1) / Self.chunkSize,
                  storedSize == 4 + headerSize + metadata.byteCount + 28 * metadata.chunkCount,
                  !FileManager.default.fileExists(atPath: destination.path) else { throw InboxError.invalid }
            guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600]) else { throw InboxError.unavailable }
            do {
                try protect(destination)
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                let aad = Data(SHA256.hash(data: headerData))
                var remaining = metadata.byteCount
                for index in 0..<metadata.chunkCount {
                    try Task.checkCancellation()
                    let count = min(Self.chunkSize, remaining)
                    let sealed = try input.read(upToCount: count + 28) ?? Data()
                    guard sealed.count == count + 28 else { throw InboxError.invalid }
                    var data = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: chunkAAD(aad, index: index, total: metadata.byteCount))
                    defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
                    try output.write(contentsOf: data); remaining -= data.count
                }
                guard remaining == 0, try input.read(upToCount: 1)?.isEmpty != false else { throw InboxError.invalid }
                try output.synchronize()
                return metadata
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
    }

    func remove(_ item: URL) throws {
        try withLock { guard contains(item) else { throw InboxError.invalid }; if FileManager.default.fileExists(atPath: item.path) { try FileManager.default.removeItem(at: item) } }
    }

    func clear() throws {
        try withLock {
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.lastPathComponent != ".lock" {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func derive(_ sender: Curve25519.KeyAgreement.PrivateKey, recipient: Curve25519.KeyAgreement.PublicKey, salt: Data? = nil) throws -> SymmetricKey {
        try sender.sharedSecretFromKeyAgreement(with: recipient).hkdfDerivedSymmetricKey(using: SHA256.self,
            salt: salt ?? recipient.rawRepresentation, sharedInfo: Data("NoctGallery.incoming.v1".utf8), outputByteCount: 32)
    }
    private func chunkAAD(_ header: Data, index: Int, total: Int) -> Data { header + Data(":\(index):\(total)".utf8) }
    private func contains(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.deletingLastPathComponent() == root.standardizedFileURL
            && url.pathExtension == "incoming" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }
    private func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { contains($0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func regularData(_ url: URL, limit: Int) throws -> Data {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= limit else { throw InboxError.invalid }
        return try Data(contentsOf: url)
    }
    private func protect(_ url: URL, directory: Bool = false) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: directory ? 0o700 : 0o600], ofItemAtPath: url.path)
        var target = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try target.setResourceValues(values)
    }
    private func withLock<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw InboxError.invalid }
        try protect(root, directory: true)
        let url = root.appendingPathComponent(".lock")
        let fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw InboxError.unavailable }
        defer { Darwin.close(fd) }
        try protect(url)
        guard flock(fd, LOCK_EX) == 0 else { throw InboxError.unavailable }
        defer { flock(fd, LOCK_UN) }
        // Holding the process-wide lock proves no live writer owns these leftovers.
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where file.pathExtension == "staging" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
            try FileManager.default.removeItem(at: file)
        }
        return try action()
    }
}

protocol GalleryInboxKeys: Sendable {
    func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey
    func delete() throws
}

struct GalleryInboxKeyStore: GalleryInboxKeys {
    let service: String
    init(service: String = (Bundle.main.bundleIdentifier ?? "NoctGallery") + ".incoming.v1") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "recipient", kSecAttrSynchronizable as String: false]
    }
    func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecSuccess, var data = result as? Data {
            defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        guard status == errSecItemNotFound else { throw GalleryImportInbox.InboxError.unavailable }
        let key = Curve25519.KeyAgreement.PrivateKey()
        var item = query; item[kSecValueData as String] = key.rawRepresentation; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw GalleryImportInbox.InboxError.unavailable }
        return key
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GalleryImportInbox.InboxError.unavailable }
    }
}
