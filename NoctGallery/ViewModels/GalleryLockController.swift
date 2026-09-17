import CoreNFC
import LocalAuthentication
import NoctweaveSecurityKeys
import SwiftUI

@MainActor
final class GalleryLockController: ObservableObject {
    @Published private(set) var configuration: GalleryLockConfiguration?
    @Published private(set) var isLoaded = false
    @Published private(set) var loadFailed = false
    @Published private(set) var isUnlocked = false
    @Published private(set) var isBusy = false
    @Published private(set) var completed: Set<GalleryLockFactor> = []
    @Published private(set) var pendingDuress: GalleryDuressPlan?
    @Published private(set) var verifiedKey: SecurityKeyCredential?
    @Published var message: String?
    @Published var showsProtectionSettings = false
    private var wantsProtectionSettings = false
    private var generation = UUID()
    private var context: LAContext?
    private let hardware = HardwareSecurityKey()
    let store: GalleryLockStore

    init(store: GalleryLockStore = GalleryLockStore()) { self.store = store }
    var mode: GalleryLockMode { configuration?.mode ?? .pin }
    var nextFactor: GalleryLockFactor? { mode.next(after: completed) }
    var hasDuress: Bool { !(configuration?.duress.isEmpty ?? true) }
    var isDiscreet: Bool { configuration?.discreetUnlock == true }
    var biometricName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID ? "Face ID" : "Touch ID"
    }
    var securityKeysAvailable: Bool { NFCTagReaderSession.readingAvailable }
    var biometricsAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false; isLoaded = true }
        do {
            configuration = try await store.load()
            pendingDuress = configuration?.pendingDuress
            loadFailed = false
            message = nil
            if pendingDuress == nil, configuration?.mode == .off { isUnlocked = true }
        } catch { loadFailed = true; isUnlocked = false; message = GalleryLockError.storage.localizedDescription }
    }

    func lock() {
        generation = UUID()
        context?.invalidate()
        context = nil
        Task { await hardware.cancel() }
        completed = []
        verifiedKey = nil
        showsProtectionSettings = false
        wantsProtectionSettings = false
        message = nil
        isUnlocked = false
    }

    func activate() {
        if isLoaded, !loadFailed, pendingDuress == nil, mode == .off { isUnlocked = true }
    }

    func requestProtectionSettings() {
        guard isUnlocked else { return }
        lock()
        wantsProtectionSettings = true
        if mode == .off { finishUnlock() }
    }

    func authenticateBiometrics() async {
        guard !isBusy, !isUnlocked, pendingDuress == nil, nextFactor == .biometrics else { return }
        let attempt = generation
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await evaluateBiometrics()
            guard attempt == generation else { return }
            completed.insert(.biometrics)
            if mode.accepts(completed) { finishUnlock() }
        } catch { if attempt == generation { showAuthenticationError(error) } }
    }

    func authenticateKey(pin: String, transport: SecurityKeyTransport) async {
        guard !isBusy, !isUnlocked, pendingDuress == nil, securityKeysAvailable, transport == .nfc, nextFactor == .securityKey,
              let credentials = configuration?.keys else { return }
        let attempt = generation
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let result = try await hardware.authenticate(application: .noctGallery, credentials: credentials, pin: pin, transport: transport)
            guard attempt == generation else { return }
            configuration = try await store.updateCounter(result)
            guard attempt == generation else { return }
            completed.insert(.securityKey)
            if mode.accepts(completed) { finishUnlock() }
        } catch { if attempt == generation { showAuthenticationError(error) } }
    }

    func submitPIN(_ pin: String) async {
        guard !isBusy, !isUnlocked, pendingDuress == nil else { return }
        let attempt = generation
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let result = try await store.attemptPIN(pin)
            switch result {
            case .duress(let plan):
                // A committed action survives cancellation/backgrounding. No ordinary
                // PIN or earlier factor can postpone it after the Keychain commit.
                lock()
                pendingDuress = plan
            case .primary:
                guard attempt == generation, nextFactor == .pin else { throw GalleryLockError.rejected }
                completed.insert(.pin)
                if mode.accepts(completed) { finishUnlock() }
            }
        } catch { if attempt == generation { message = error.localizedDescription } }
    }

    func verifyKeyForSetup(name: String, pin: String, transport: SecurityKeyTransport, register: Bool) async {
        guard !isBusy, securityKeysAvailable, transport == .nfc, (isUnlocked || configuration == nil), pendingDuress == nil else { return }
        let attempt = generation
        isBusy = true
        verifiedKey = nil
        message = nil
        defer { isBusy = false }
        do {
            let result: SecurityKeyCredential
            if register {
                result = try await hardware.register(application: .noctGallery, name: name,
                    excluding: configuration?.keys ?? [], pin: pin, transport: transport)
            } else {
                result = try await hardware.authenticate(application: .noctGallery, credentials: configuration?.keys ?? [], pin: pin, transport: transport)
            }
            guard attempt == generation else { return }
            if !register { configuration = try await store.updateCounter(result) }
            guard attempt == generation else { return }
            verifiedKey = result
        } catch { if attempt == generation { showAuthenticationError(error) } }
    }

    func configure(mode: GalleryLockMode, pin: String, discreet: Bool = false) async -> Bool {
        guard !isBusy, !loadFailed, (isUnlocked || configuration == nil), pendingDuress == nil else { return false }
        let attempt = generation
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            var keys = configuration?.keys ?? []
            if mode.factors.contains(.securityKey) {
                guard let verifiedKey else { throw GalleryLockError.invalidConfiguration }
                keys.removeAll { $0.id == verifiedKey.id }
                keys.append(verifiedKey)
            }
            if mode.factors.contains(.biometrics) { try await evaluateBiometrics() }
            guard attempt == generation else { return false }
            configuration = try await store.configure(mode: mode, pin: pin, keys: keys, discreet: discreet)
            guard attempt == generation else { return false }
            verifiedKey = nil
            completed = Set(mode.factors)
            isUnlocked = true
            return true
        } catch { if attempt == generation { message = error.localizedDescription }; return false }
    }

    func setDuress(_ action: GalleryDuressAction, pin: String, ids: Set<String>) async -> Bool {
        guard isUnlocked, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do { configuration = try await store.setDuress(action, pin: pin, decoyIDs: ids); message = nil; return true }
        catch { message = error.localizedDescription; return false }
    }
    func removeDuress(_ action: GalleryDuressAction) async {
        guard isUnlocked, !isBusy else { return }
        do { configuration = try await store.removeDuress(action) } catch { message = error.localizedDescription }
    }
    func setDecoys(_ ids: Set<String>) async {
        guard isUnlocked, !isBusy else { return }
        do { configuration = try await store.updateDecoys(ids) } catch { message = error.localizedDescription }
    }
    func replaceDecoy(_ previous: String, with next: String?) async throws {
        guard var ids = configuration?.decoyIDs, ids.remove(previous) != nil else { return }
        if let next { ids.insert(next) }
        configuration = try await store.updateDecoys(ids)
    }

    func finishDuress(_ plan: GalleryDuressPlan, unlock: Bool) async throws {
        configuration = try await store.finishDuress(id: plan.id)
        pendingDuress = nil
        completed = []
        message = nil
        if unlock { completed = [.pin]; finishUnlock() }
    }
    func reset() async throws {
        lock()
        try await store.reset()
        configuration = nil
        pendingDuress = nil
        loadFailed = false
        isLoaded = true
    }

    private func evaluateBiometrics() async throws {
        let context = LAContext()
        self.context = context
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        defer { context.invalidate(); self.context = nil }
        guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Noct Gallery.") else { throw GalleryLockError.rejected }
    }
    private func finishUnlock() {
        guard pendingDuress == nil, mode.accepts(completed) else { return }
        isUnlocked = true
        message = nil
        if wantsProtectionSettings {
            wantsProtectionSettings = false
            showsProtectionSettings = true
        }
    }
    private func showAuthenticationError(_ error: Error) {
        if let error = error as? LAError, [.userCancel, .systemCancel, .appCancel].contains(error.code) { return }
        if error as? SecurityKeyError == .cancelled { return }
        message = error.localizedDescription
    }
}
