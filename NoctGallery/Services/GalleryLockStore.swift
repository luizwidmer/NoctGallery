import CommonCrypto
import CryptoKit
import Foundation
import NoctweaveSecurityKeys
import Security

enum GalleryLockFactor: String, Codable, Sendable { case securityKey, biometrics, pin }

enum GalleryLockMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, pin, biometrics, biometricsAndPIN, securityKey, securityKeyAndPIN, securityKeyAndBiometrics, allThree
    var id: String { rawValue }
    var factors: [GalleryLockFactor] {
        switch self {
        case .off: []
        case .pin: [.pin]
        case .biometrics: [.biometrics]
        case .biometricsAndPIN: [.biometrics, .pin]
        case .securityKey: [.securityKey]
        case .securityKeyAndPIN: [.securityKey, .pin]
        case .securityKeyAndBiometrics: [.securityKey, .biometrics]
        case .allThree: [.securityKey, .biometrics, .pin]
        }
    }
    var title: String {
        switch self {
        case .off: "Off"
        case .pin: "PIN"
        case .biometrics: "Biometrics"
        case .biometricsAndPIN: "Biometrics + PIN"
        case .securityKey: "Security Key"
        case .securityKeyAndPIN: "Security Key + PIN"
        case .securityKeyAndBiometrics: "Security Key + Biometrics"
        case .allThree: "Key + Biometrics + PIN"
        }
    }
    func next(after completed: Set<GalleryLockFactor>) -> GalleryLockFactor? { factors.first { !completed.contains($0) } }
    func accepts(_ completed: Set<GalleryLockFactor>) -> Bool { Set(factors).isSubset(of: completed) }
}

enum GalleryDuressAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case reset, retainDecoys
    var id: String { rawValue }
    var title: String { self == .reset ? "Reset Gallery" : "Keep Selected Decoys" }
}

enum GalleryLockError: LocalizedError {
    case storage, invalidPIN, rejected, cooldown(Date), invalidConfiguration, locked, duplicatePIN
    var errorDescription: String? {
        switch self {
        case .storage: "Protection settings could not be read or saved. Gallery remains locked."
        case .invalidPIN: "Use exactly six digits for your PIN."
        case .rejected: "Unable to unlock. Try again."
        case .cooldown(let date): "Try again in \(max(1, Int(ceil(date.timeIntervalSinceNow)))) seconds."
        case .invalidConfiguration: "Verify every selected unlock method before saving protection."
        case .locked: "Unlock Gallery before changing protection."
        case .duplicatePIN: "Choose a different PIN for each action and for ordinary unlock."
        }
    }
}

/// PIN material is salted and stretched, never persisted as plaintext. The
/// verifier and retry ledger live in the device-only, unlocked Keychain.
struct GalleryPINVerifier: Codable, Sendable {
    let salt: Data
    let digest: Data
    static let rounds: UInt32 = 600_000
    static func isValid(_ pin: String) -> Bool { pin.utf8.count == 6 && pin.utf8.allSatisfy { (48...57).contains($0) } }
    static func make(_ pin: String) throws -> Self {
        guard isValid(pin) else { throw GalleryLockError.invalidPIN }
        let salt = try randomBytes(32)
        return Self(salt: salt, digest: try derive(pin, salt: salt))
    }
    func matches(_ pin: String) throws -> Bool {
        guard salt.count == 32, digest.count == 32 else { throw GalleryLockError.storage }
        let candidate = try Self.derive(pin, salt: salt)
        return zip(candidate, digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private static func derive(_ pin: String, salt: Data) throws -> Data {
        guard isValid(pin) else { throw GalleryLockError.invalidPIN }
        var result = Data(count: 32)
        let status = result.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                pin.withCString { password in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, pin.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        output.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        guard status == kCCSuccess else { throw GalleryLockError.storage }
        return result
    }
    static func randomBytes(_ count: Int) throws -> Data {
        var result = Data(count: count)
        guard result.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }) == errSecSuccess
        else { throw GalleryLockError.storage }
        return result
    }
}

struct GalleryDuressCredential: Codable, Sendable, Identifiable {
    var id: GalleryDuressAction { action }
    let action: GalleryDuressAction
    let verifier: GalleryPINVerifier
}

struct GalleryDuressPlan: Codable, Sendable {
    let id: UUID
    let action: GalleryDuressAction
    let retainedIDs: Set<String>
    let replacementPIN: GalleryPINVerifier
    let replacementMediaKey: Data
}

struct GalleryLockConfiguration: Codable, Sendable {
    var version = 1
    var mode: GalleryLockMode
    var pin: GalleryPINVerifier?
    var keys: [SecurityKeyCredential] = []
    var duress: [GalleryDuressCredential] = []
    var decoyIDs: Set<String> = []
    var discreetUnlock: Bool? = nil
    var failedAttempts = 0
    var retryAfter: Date?
    var pendingDuress: GalleryDuressPlan?

    func validate() throws {
        guard version == 1, failedAttempts >= 0, failedAttempts <= 30,
              mode.factors.contains(.pin) == (pin != nil),
              !mode.factors.contains(.securityKey) || !keys.isEmpty,
              keys.count <= 8, keys.allSatisfy({ $0.isStructurallyValid &&
                  [SecurityKeyApplication.noctGallery.relyingPartyID, SecurityKeyApplication.noctGalleryLocal.relyingPartyID].contains($0.relyingPartyID) }),
              Set(keys.map(\.credentialID)).count == keys.count,
              duress.count <= 2, Set(duress.map(\.action)).count == duress.count,
              mode != .off || duress.isEmpty, discreetUnlock != true || (mode != .off && !duress.isEmpty),
              decoyIDs.count <= 10_000,
              decoyIDs.allSatisfy({ UUID(uuidString: $0)?.uuidString.lowercased() == $0 })
        else { throw GalleryLockError.storage }
        for verifier in [pin].compactMap({ $0 }) + duress.map(\.verifier) {
            guard verifier.salt.count == 32, verifier.digest.count == 32 else { throw GalleryLockError.storage }
        }
        if let pendingDuress {
            guard pendingDuress.replacementMediaKey.count == 32,
                  pendingDuress.replacementPIN.salt.count == 32, pendingDuress.replacementPIN.digest.count == 32,
                  pendingDuress.retainedIDs.isSubset(of: decoyIDs),
                  pendingDuress.action != .reset || pendingDuress.retainedIDs.isEmpty
            else { throw GalleryLockError.storage }
        }
    }
}

protocol GalleryLockPersistence: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

struct KeychainGalleryLockPersistence: GalleryLockPersistence {
    var service = (Bundle.main.bundleIdentifier ?? "NoctGallery") + ".app-lock.v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "protection", kSecAttrSynchronizable as String: false]
    }
    func read() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count <= 1_048_576 else { throw GalleryLockError.storage }
        return data
    }
    func write(_ data: Data) throws {
        guard data.count <= 1_048_576 else { throw GalleryLockError.storage }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw GalleryLockError.storage }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw GalleryLockError.storage }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GalleryLockError.storage }
    }
}

actor GalleryLockStore {
    enum PINResult: Sendable { case primary, duress(GalleryDuressPlan) }
    private let persistence: any GalleryLockPersistence
    init(persistence: any GalleryLockPersistence = KeychainGalleryLockPersistence()) { self.persistence = persistence }
    func load() throws -> GalleryLockConfiguration? {
        guard let data = try persistence.read() else { return nil }
        let value = try JSONDecoder().decode(GalleryLockConfiguration.self, from: data)
        try value.validate()
        return value
    }
    private func save(_ value: GalleryLockConfiguration) throws {
        try value.validate()
        try persistence.write(JSONEncoder().encode(value))
    }
    func configure(mode: GalleryLockMode, pin: String, keys: [SecurityKeyCredential], discreet: Bool = false) throws -> GalleryLockConfiguration {
        let old = try load()
        guard old?.pendingDuress == nil else { throw GalleryLockError.locked }
        let verifier: GalleryPINVerifier?
        if mode.factors.contains(.pin) {
            if pin.isEmpty, let existing = old?.pin { verifier = existing }
            else {
                for item in old?.duress ?? [] where try item.verifier.matches(pin) { throw GalleryLockError.duplicatePIN }
                verifier = try .make(pin)
            }
        } else { verifier = nil }
        var value = GalleryLockConfiguration(mode: mode, pin: verifier,
            keys: mode.factors.contains(.securityKey) ? keys : [])
        value.duress = mode == .off ? [] : old?.duress ?? []
        value.decoyIDs = old?.decoyIDs ?? []
        guard !discreet || (mode != .off && !value.duress.isEmpty) else { throw GalleryLockError.invalidConfiguration }
        value.discreetUnlock = discreet
        try save(value)
        return value
    }
    func attemptPIN(_ pin: String, allowPrimary: Bool = true, now: Date = Date()) throws -> PINResult {
        guard GalleryPINVerifier.isValid(pin) else { throw GalleryLockError.invalidPIN }
        guard var value = try load(), value.pendingDuress == nil else { throw GalleryLockError.locked }
        if let retry = value.retryAfter, now < retry { throw GalleryLockError.cooldown(retry) }
        // Persist the attempt first; terminating the process does not reset the ledger.
        value.failedAttempts = min(30, value.failedAttempts + 1)
        if value.failedAttempts >= 5 {
            value.retryAfter = now.addingTimeInterval(min(300, pow(2, Double(value.failedAttempts - 5)) * 5))
        }
        try save(value)
        var matchedDuress: GalleryDuressCredential?
        let primary = try value.pin?.matches(pin) ?? false
        for item in value.duress {
            if try item.verifier.matches(pin) { matchedDuress = item }
        }
        if let matchedDuress {
            let plan = GalleryDuressPlan(id: UUID(), action: matchedDuress.action,
                retainedIDs: matchedDuress.action == .retainDecoys ? value.decoyIDs : [],
                replacementPIN: matchedDuress.verifier, replacementMediaKey: try GalleryPINVerifier.randomBytes(32))
            value.pendingDuress = plan
            try save(value)
            return .duress(plan)
        }
        // Duress is deliberately available before other factors. A matching
        // ordinary PIN must not clear the retry ledger until its turn in the
        // configured key -> biometrics -> PIN sequence.
        guard primary, allowPrimary else { throw GalleryLockError.rejected }
        value.failedAttempts = 0
        value.retryAfter = nil
        try save(value)
        return .primary
    }
    func updateCounter(_ credential: SecurityKeyCredential) throws -> GalleryLockConfiguration {
        guard var value = try load(), value.pendingDuress == nil,
              let index = value.keys.firstIndex(where: { $0.id == credential.id }),
              credential.credentialID == value.keys[index].credentialID,
              credential.publicKey == value.keys[index].publicKey,
              credential.relyingPartyID == value.keys[index].relyingPartyID,
              credential.signatureCounter == 0 && value.keys[index].signatureCounter == 0
                || credential.signatureCounter > value.keys[index].signatureCounter else { throw GalleryLockError.rejected }
        value.keys[index] = credential
        try save(value)
        return value
    }
    func setDuress(_ action: GalleryDuressAction, pin: String, decoyIDs: Set<String>) throws -> GalleryLockConfiguration {
        guard var value = try load(), value.mode != .off, value.pendingDuress == nil else { throw GalleryLockError.locked }
        if try value.pin?.matches(pin) == true { throw GalleryLockError.duplicatePIN }
        for item in value.duress where item.action != action {
            if try item.verifier.matches(pin) { throw GalleryLockError.duplicatePIN }
        }
        guard action != .retainDecoys || !decoyIDs.isEmpty else { throw GalleryLockError.invalidConfiguration }
        value.duress.removeAll { $0.action == action }
        value.duress.append(.init(action: action, verifier: try .make(pin)))
        value.decoyIDs = decoyIDs
        try save(value)
        return value
    }
    func removeDuress(_ action: GalleryDuressAction) throws -> GalleryLockConfiguration {
        guard var value = try load(), value.pendingDuress == nil else { throw GalleryLockError.locked }
        value.duress.removeAll { $0.action == action }
        if value.duress.isEmpty { value.discreetUnlock = false }
        try save(value)
        return value
    }
    func updateDecoys(_ ids: Set<String>) throws -> GalleryLockConfiguration {
        guard var value = try load(), value.pendingDuress == nil else { throw GalleryLockError.locked }
        value.decoyIDs = ids
        try save(value)
        return value
    }
    func finishDuress(id: UUID) throws -> GalleryLockConfiguration {
        guard let plan = try load()?.pendingDuress, plan.id == id else { throw GalleryLockError.storage }
        let result = GalleryLockConfiguration(mode: .pin, pin: plan.replacementPIN)
        try save(result)
        return result
    }
    func reset() throws { try persistence.delete() }
}
