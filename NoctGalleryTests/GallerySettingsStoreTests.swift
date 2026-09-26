import Foundation
import Security
import XCTest
@testable import NoctGallery

@MainActor
final class GallerySettingsStoreTests: XCTestCase {
    func testReleasedPreferencesMigrateWithoutLeavingPlaintextCanary() throws {
        let scope = UUID().uuidString
        let suite = "GallerySettingsTests." + scope
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = GallerySettingsStore(service: suite + ".keychain", defaults: defaults)
        defer { try? store.purge(); defaults.removePersistentDomain(forName: suite) }
        let location = DecoyLocation(name: "private-location-" + scope,
            latitude: 10, longitude: 20, timeZoneIdentifier: "Etc/UTC")
        defaults.set(try JSONEncoder().encode(location), forKey: "camera.randomCenter")
        defaults.set("png", forKey: "share.outputFormat")
        defaults.set(true, forKey: "onboarding.completed")
        defaults.set(true, forKey: "reset.pending")

        let migrated = try store.loadOrMigrate()
        XCTAssertEqual(migrated.randomLocationCenter, location)
        XCTAssertEqual(migrated.shareOutputFormat, "png")
        XCTAssertTrue(migrated.onboardingCompleted)
        XCTAssertTrue(migrated.resetPending)
        XCTAssertEqual(try store.loadOrMigrate(), migrated)
        XCTAssertNil(defaults.object(forKey: "camera.randomCenter"))
        XCTAssertNil(defaults.object(forKey: "share.outputFormat"))
        XCTAssertNil(defaults.object(forKey: "reset.pending"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains {
            "\($0)".contains(location.name)
        })
    }

    func testDamagedProtectedRecordNeverFallsBackToOldPlaintext() throws {
        let scope = UUID().uuidString
        let suite = "GallerySettingsTests." + scope
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let service = suite + ".keychain"
        let store = GallerySettingsStore(service: service, defaults: defaults)
        defer { try? store.purge(); defaults.removePersistentDomain(forName: suite) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "settings",
            kSecAttrSynchronizable as String: false, kSecValueData as String: Data("damaged".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
        defaults.set("png", forKey: "share.outputFormat")
        XCTAssertThrowsError(try store.loadOrMigrate())
        XCTAssertEqual(defaults.string(forKey: "share.outputFormat"), "png")
    }
}
