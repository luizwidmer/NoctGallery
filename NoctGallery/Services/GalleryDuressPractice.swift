import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct GalleryPracticeResult: Sendable {
    let action: GalleryDuressAction
    let remainingSamples: [Int]
    let mediaKeyChanged: Bool
    let replacementPINWorks: Bool
    let oldPINRejected: Bool
    let onlyPINRequired: Bool
}

/// This service cannot receive the user's vault, lock controller, or Keychain.
/// It executes the production storage/credential logic on generated samples only.
actor GalleryDuressPractice {
    static let practicePIN = "638204"
    private static let primaryPIN = "482951"
    private static var parent: URL { FileManager.default.temporaryDirectory.appendingPathComponent("GalleryDuressPractice", isDirectory: true) }
    private var running = false

    static func removeAbandonedSamples() throws {
        if FileManager.default.fileExists(atPath: parent.path) { try FileManager.default.removeItem(at: parent) }
    }

    func run(action: GalleryDuressAction, retainedSamples: Set<Int>, enteredPIN: String) async throws -> GalleryPracticeResult {
        guard !running, retainedSamples.isSubset(of: [0, 1, 2]), action != .retainDecoys || !retainedSamples.isEmpty else {
            throw GalleryLockError.invalidConfiguration
        }
        running = true
        defer { running = false }
        let directory = Self.parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let keys = GalleryPracticeMemory()
        let credentials = GalleryLockStore(persistence: GalleryPracticeMemory())
        let store = PrivateMediaStore(root: directory.appendingPathComponent("vault"), keys: keys)
        do {
            try MediaFileProtection.prepareDirectory(directory)
            defer { try? FileManager.default.removeItem(at: directory) }
            _ = try await store.unlock()
            let session = try await store.currentSession()
            var samples: [PhotoAssetRecord] = []
            for index in 0..<3 {
                try Task.checkCancellation()
                let data = try Self.sampleImage(index: index)
                let source = directory.appendingPathComponent("sample.png")
                try data.write(to: source, options: [.atomic, .completeFileProtection])
                samples.append(try await store.save(file: source, fileExtension: "png", kind: .photo, width: 480, height: 320,
                    duration: 0, thumbnail: data, profile: nil, session: session))
                try FileManager.default.removeItem(at: source)
            }
            let oldKey = try keys.loadOrCreate(allowCreate: false)
            _ = try await credentials.configure(mode: .biometricsAndPIN, pin: Self.primaryPIN, keys: [])
            let retainedIDs = Set(retainedSamples.map { samples[$0].id })
            _ = try await credentials.setDuress(action, pin: Self.practicePIN, decoyIDs: retainedIDs)
            _ = try await credentials.configure(mode: .biometricsAndPIN, pin: "", keys: [], discreet: true)
            try Task.checkCancellation()
            guard case .duress(let plan) = try await credentials.attemptPIN(enteredPIN, allowPrimary: false) else {
                throw GalleryLockError.rejected
            }
            try await store.applyDuress(plan)
            let config = try await credentials.finishDuress(id: plan.id)
            let remaining = try await store.unlock()
            let newSession = try await store.currentSession()
            // Check retained bytes as well as the listing: the sample must still be usable.
            for item in remaining {
                guard let index = samples.firstIndex(where: { $0.id == item.id }) else { throw PrivateMediaStore.StoreError.invalidRecord }
                let output = directory.appendingPathComponent("restored.png")
                try await store.materialize(id: item.id, to: output, session: newSession)
                guard try Data(contentsOf: output) == Self.sampleImage(index: index) else { throw PrivateMediaStore.StoreError.invalidRecord }
                try FileManager.default.removeItem(at: output)
            }
            var oldRejected = false
            do { _ = try await credentials.attemptPIN(Self.primaryPIN) } catch GalleryLockError.rejected { oldRejected = true }
            let pinWorks: Bool
            if case .primary = try await credentials.attemptPIN(enteredPIN) { pinWorks = true } else { pinWorks = false }
            try Task.checkCancellation()
            let result = GalleryPracticeResult(action: action,
                remainingSamples: samples.indices.filter { index in remaining.contains { $0.id == samples[index].id } },
                mediaKeyChanged: oldKey != (try keys.loadOrCreate(allowCreate: false)), replacementPINWorks: pinWorks,
                oldPINRejected: oldRejected, onlyPINRequired: config.mode == .pin && config.keys.isEmpty && config.duress.isEmpty)
            await store.lock()
            try await credentials.reset()
            try keys.delete()
            return result
        } catch {
            await store.lock()
            try? await credentials.reset()
            try? keys.delete()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func sampleImage(index: Int) throws -> Data {
        guard let context = CGContext(data: nil, width: 480, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PrivateMediaStore.StoreError.invalidRecord
        }
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.39, 0.48), (0.42, 0.29, 0.55), (0.33, 0.46, 0.32)]
        let color = colors[index % colors.count]
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fillEllipse(in: CGRect(x: 55 + index * 75, y: 85, width: 130, height: 130))
        guard let image = context.makeImage() else { throw PrivateMediaStore.StoreError.invalidRecord }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw PrivateMediaStore.StoreError.invalidRecord }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PrivateMediaStore.StoreError.invalidRecord }
        return data as Data
    }
}

/// Separate instances hold the practice media key and credential record.
private final class GalleryPracticeMemory: PrivateMediaKeyStore, GalleryLockPersistence, @unchecked Sendable {
    private let mutex = NSLock()
    private var data: Data?
    func read() throws -> Data? { mutex.lock(); defer { mutex.unlock() }; return data }
    func write(_ value: Data) throws { mutex.lock(); defer { mutex.unlock() }; let count = data?.count ?? 0; data?.resetBytes(in: 0..<count); data = value }
    func replace(_ data: Data) throws { guard data.count == 32 else { throw PrivateMediaStore.StoreError.keyUnavailable }; try write(data) }
    func delete() throws { mutex.lock(); defer { mutex.unlock() }; let count = data?.count ?? 0; data?.resetBytes(in: 0..<count); data = nil }
    func loadOrCreate(allowCreate: Bool) throws -> Data {
        mutex.lock(); defer { mutex.unlock() }
        if let data, data.count == 32 { return data }
        guard allowCreate else { throw PrivateMediaStore.StoreError.keyUnavailable }
        let created = try GalleryPINVerifier.randomBytes(32)
        data = created
        return created
    }
}
