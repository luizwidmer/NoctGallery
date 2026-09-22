import CryptoKit
import NoctweaveSecurityKeys
import XCTest
@testable import NoctGallery

final class GalleryLockTests: XCTestCase {
    func testAllModesRequireEveryFactorInOrder() {
        for mode in GalleryLockMode.allCases {
            var completed: Set<GalleryLockFactor> = []
            for factor in mode.factors {
                XCTAssertFalse(mode.accepts(completed))
                XCTAssertEqual(mode.next(after: completed), factor)
                completed.insert(factor)
            }
            XCTAssertTrue(mode.accepts(completed))
            XCTAssertNil(mode.next(after: completed))
        }
        XCTAssertEqual(GalleryLockMode.allThree.factors, [.securityKey, .biometrics, .pin])
    }

    func testPINPolicySaltAndPersistentCooldown() async throws {
        for pin in ["", "12345", "1234567", "abcdef", "１２３４５６"] { XCTAssertFalse(GalleryPINVerifier.isValid(pin)) }
        let first = try GalleryPINVerifier.make("482951")
        let second = try GalleryPINVerifier.make("482951")
        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertNotEqual(first.digest, second.digest)
        XCTAssertTrue(try first.matches("482951"))
        XCTAssertFalse(try first.matches("111111"))
        let persistence = MemoryGalleryLockPersistence()
        let store = GalleryLockStore(persistence: persistence)
        _ = try await store.configure(mode: .pin, pin: "482951", keys: [])
        let now = Date()
        for _ in 0..<5 {
            do { _ = try await store.attemptPIN("111111", now: now); XCTFail("Wrong PIN accepted") }
            catch GalleryLockError.rejected {}
        }
        let reopened = GalleryLockStore(persistence: persistence)
        do { _ = try await reopened.attemptPIN("482951", now: now); XCTFail("Relaunch bypassed cooldown") }
        catch GalleryLockError.cooldown {}
        guard case .primary = try await reopened.attemptPIN("482951", now: now.addingTimeInterval(6)) else {
            return XCTFail("Correct PIN rejected after delay")
        }
        let saved = try await reopened.load()
        XCTAssertEqual(saved?.failedAttempts, 0)
        XCTAssertNil(saved?.retryAfter)
        XCTAssertNil(try persistence.read()?.range(of: Data("482951".utf8)))
    }

    func testDuressPersistsBeforeReturningAndBecomesOnlyPIN() async throws {
        let persistence = MemoryGalleryLockPersistence()
        let store = GalleryLockStore(persistence: persistence)
        _ = try await store.configure(mode: .biometricsAndPIN, pin: "482951", keys: [])
        let retained = UUID().uuidString.lowercased()
        _ = try await store.setDuress(.retainDecoys, pin: "638204", decoyIDs: [retained])
        guard case .duress(let plan) = try await store.attemptPIN("638204") else { return XCTFail("Duress not recognized") }
        let pending = try await GalleryLockStore(persistence: persistence).load()
        XCTAssertEqual(pending?.pendingDuress?.id, plan.id)
        XCTAssertEqual(plan.retainedIDs, [retained])
        XCTAssertEqual(plan.replacementMediaKey.count, 32)
        do { _ = try await store.attemptPIN("482951"); XCTFail("Normal unlock postponed committed action") }
        catch GalleryLockError.locked {}
        let final = try await store.finishDuress(id: plan.id)
        XCTAssertEqual(final.mode, .pin)
        XCTAssertTrue(final.keys.isEmpty)
        XCTAssertTrue(final.duress.isEmpty)
        XCTAssertTrue(final.decoyIDs.isEmpty)
        XCTAssertNil(final.pendingDuress)
        guard case .primary = try await store.attemptPIN("638204") else { return XCTFail("Duress PIN did not become primary") }
        do { _ = try await store.attemptPIN("482951"); XCTFail("Old PIN remained active") }
        catch GalleryLockError.rejected {}
    }

    func testDuressCannotReusePINOrEnableEmptyDecoySet() async throws {
        let store = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await store.configure(mode: .pin, pin: "482951", keys: [])
        do { _ = try await store.setDuress(.reset, pin: "482951", decoyIDs: []); XCTFail("Duplicate primary PIN allowed") }
        catch GalleryLockError.duplicatePIN {}
        _ = try await store.setDuress(.reset, pin: "638204", decoyIDs: [])
        do { _ = try await store.setDuress(.retainDecoys, pin: "638204", decoyIDs: [UUID().uuidString.lowercased()]); XCTFail("Duplicate action PIN allowed") }
        catch GalleryLockError.duplicatePIN {}
        do { _ = try await store.configure(mode: .pin, pin: "638204", keys: []); XCTFail("Primary changed to an action PIN") }
        catch GalleryLockError.duplicatePIN {}
        do { _ = try await store.setDuress(.retainDecoys, pin: "715826", decoyIDs: []); XCTFail("Empty decoy action enabled") }
        catch GalleryLockError.invalidConfiguration {}
    }

    @MainActor
    func testLocalAndEarlierKeysPersistWithoutChangingCredentialScope() async throws {
        let persistence = MemoryGalleryLockPersistence()
        let store = GalleryLockStore(persistence: persistence)
        let publicKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let legacy = SecurityKeyCredential(name: "Earlier key", relyingPartyID: SecurityKeyApplication.noctGallery.relyingPartyID,
            credentialID: Data([1]), publicKey: publicKey, signatureCounter: 1)
        var local = SecurityKeyCredential(name: "Local key", relyingPartyID: SecurityKeyApplication.noctGalleryLocal.relyingPartyID,
            credentialID: Data([2]), publicKey: publicKey, signatureCounter: 1)
        _ = try await store.configure(mode: .allThree, pin: "482951", keys: [legacy, local])
        let reopened = GalleryLockController(store: GalleryLockStore(persistence: persistence))
        await reopened.load()
        XCTAssertTrue(reopened.hasLocalKeys)
        XCTAssertTrue(reopened.hasLegacyKeys)
        XCTAssertFalse(reopened.requiresLegacyKeyPIN)
        local.signatureCounter = 2
        let saved = try await store.updateCounter(local)
        XCTAssertEqual(saved.keys, [legacy, local])
        let scopeChange = SecurityKeyCredential(id: local.id, name: local.name, relyingPartyID: legacy.relyingPartyID,
            credentialID: local.credentialID, publicKey: publicKey, signatureCounter: 3)
        do { _ = try await store.updateCounter(scopeChange); XCTFail("Credential scope changed during assertion") }
        catch GalleryLockError.rejected {}
        do { _ = try await store.updateCounter(local); XCTFail("Counter replay was persisted") }
        catch GalleryLockError.rejected {}
        let unchanged = try await store.load()
        XCTAssertEqual(unchanged?.keys, [legacy, local])
        await reopened.submitPIN("482951")
        XCTAssertFalse(reopened.isUnlocked)
        XCTAssertEqual(reopened.nextFactor, .securityKey)
        let alien = SecurityKeyCredential(name: "Wrong app", relyingPartyID: "example.com",
            credentialID: Data([3]), publicKey: publicKey, signatureCounter: 0)
        do { _ = try await store.configure(mode: .securityKey, pin: "", keys: [alien]); XCTFail("External scope persisted") }
        catch GalleryLockError.storage {}
    }

    @MainActor
    func testPINCannotSatisfyBiometricsOrSecurityKeyAndLockClearsProofs() async throws {
        let persistence = MemoryGalleryLockPersistence()
        let store = GalleryLockStore(persistence: persistence)
        _ = try await store.configure(mode: .biometricsAndPIN, pin: "482951", keys: [])
        let lock = GalleryLockController(store: store)
        await lock.load()
        await lock.submitPIN("482951")
        XCTAssertFalse(lock.isUnlocked)
        XCTAssertTrue(lock.completed.isEmpty)
        XCTAssertEqual(lock.nextFactor, .biometrics)
        let key = P256.Signing.PrivateKey()
        let credential = SecurityKeyCredential(name: "Fixture", relyingPartyID: SecurityKeyApplication.noctGallery.relyingPartyID,
            credentialID: Data([1]), publicKey: key.publicKey.x963Representation, signatureCounter: 1)
        _ = try await store.configure(mode: .allThree, pin: "482951", keys: [credential])
        await lock.load()
        await lock.submitPIN("482951")
        XCTAssertFalse(lock.isUnlocked)
        XCTAssertEqual(lock.nextFactor, .securityKey)
        lock.lock()
        XCTAssertTrue(lock.completed.isEmpty)
        XCTAssertNil(lock.verifiedKey)
    }

    @MainActor
    func testDiscreetBiometricsKeepsDuressPINUsableAndMigratesOlderSettings() async throws {
        let persistence = MemoryGalleryLockPersistence()
        let store = GalleryLockStore(persistence: persistence)
        let original = try await store.configure(mode: .biometrics, pin: "", keys: [])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "discreetUnlock")
        try persistence.write(JSONSerialization.data(withJSONObject: legacy))
        let loaded = try await store.load()
        XCTAssertNil(loaded?.discreetUnlock)
        do { _ = try await store.configure(mode: .biometrics, pin: "", keys: [], discreet: true); XCTFail("Hidden empty PIN screen allowed") }
        catch GalleryLockError.invalidConfiguration {}
        _ = try await store.setDuress(.reset, pin: "638204", decoyIDs: [])
        let saved = try await store.configure(mode: .biometrics, pin: "", keys: [], discreet: true)
        XCTAssertEqual(saved.discreetUnlock, true)
        XCTAssertNil(saved.pin)
        let lock = GalleryLockController(store: store)
        await lock.load()
        XCTAssertTrue(lock.isDiscreet)
        XCTAssertFalse(lock.isUnlocked)
        XCTAssertEqual(lock.nextFactor, .biometrics)
        await lock.submitPIN("638204")
        XCTAssertNotNil(lock.pendingDuress)
        XCTAssertFalse(lock.isUnlocked)
        let plan = try XCTUnwrap(lock.pendingDuress)
        let after = try await store.finishDuress(id: plan.id)
        XCTAssertNotEqual(after.discreetUnlock, true)
        XCTAssertEqual(after.mode, .pin)
    }

    func testRemovingLastDuressPINDisablesDiscreetMode() async throws {
        let store = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await store.configure(mode: .biometrics, pin: "", keys: [])
        _ = try await store.setDuress(.reset, pin: "638204", decoyIDs: [])
        _ = try await store.configure(mode: .biometrics, pin: "", keys: [], discreet: true)
        let saved = try await store.removeDuress(.reset)
        XCTAssertNotEqual(saved.discreetUnlock, true)
        var malformed = saved
        malformed.discreetUnlock = true
        XCTAssertThrowsError(try malformed.validate())
    }

    func testStorageFailureDoesNotReleaseDuressPlanAndBadConfigurationFailsClosed() async throws {
        let persistence = MemoryGalleryLockPersistence()
        let store = GalleryLockStore(persistence: persistence)
        _ = try await store.configure(mode: .pin, pin: "482951", keys: [])
        _ = try await store.setDuress(.reset, pin: "638204", decoyIDs: [])
        persistence.setWriteFailure(true)
        do { _ = try await store.attemptPIN("638204"); XCTFail("Failed commit released action") }
        catch GalleryLockError.storage {}
        persistence.setWriteFailure(false)
        let saved = try await store.load()
        XCTAssertNil(saved?.pendingDuress)
        try persistence.write(Data("{}".utf8))
        do { _ = try await store.load(); XCTFail("Corrupt protection silently disabled lock") } catch {}
    }
}

final class MemoryGalleryLockPersistence: GalleryLockPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var failWrite = false
    func read() throws -> Data? { lock.withLock { data } }
    func write(_ data: Data) throws { try lock.withLock { if failWrite { throw GalleryLockError.storage }; self.data = data } }
    func delete() throws { lock.withLock { data = nil } }
    func setWriteFailure(_ value: Bool) { lock.withLock { failWrite = value } }
}
