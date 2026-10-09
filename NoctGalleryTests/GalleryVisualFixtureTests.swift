@preconcurrency import AVFoundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import NoctGallery

/// Explicit fixture installer for a separate simulator app. Never runs against
/// the production bundle or modifies the simulator's Photos library.
@MainActor
final class GalleryVisualFixtureTests: XCTestCase {
    func testInstallDisposableVisualFixtures() async throws {
        try XCTSkipUnless(Self.isReviewHost, "Fixtures require a simulator or the isolated iOS app on Mac.")
        try XCTSkipUnless(Bundle.main.bundleIdentifier?.hasSuffix(".gallery-features.visual-review") == true,
            "Run only with the disposable Gallery visual-review bundle identifier.")
        let store = PrivateMediaStore()
        try await store.reset()
        _ = try await store.unlock()
        let session = try await store.currentSession()
        let work = MediaWorkStore()
        try await work.reset()
        let workSession = await work.currentSession()
        var saved: [PhotoAssetRecord] = []
        for index in 0..<(Self.hasMarketingMedia ? 5 : 6) {
            let data = Self.photo(index)
            let source = try await work.write(data, extension: "jpg", session: workSession)
            let item = try await store.save(file: source, fileExtension: "jpg", kind: .photo, width: 960, height: 720,
                duration: 0, thumbnail: data, profile: nil, session: session)
            saved.append(item)
            try await work.remove(source)
        }
        let motion = try await work.allocate(extension: "mov", session: workSession)
        try await Self.video(motion)
        let thumbnail = try await VideoSanitizer.thumbnail(url: motion)
        saved.append(try await store.save(file: motion, fileExtension: "mov", kind: .video, width: 640, height: 480,
            duration: 3, thumbnail: thumbnail, profile: nil, session: session))
        let still = try await work.write(Self.photo(Self.hasMarketingMedia ? 1 : 0), extension: "jpg", session: workSession)
        var pairedMotion = motion
        if Self.hasMarketingMedia {
            pairedMotion = try await work.allocate(extension: "mov", session: workSession)
            try await Self.video(pairedMotion, photoIndex: 1)
        }
        saved.append(try await store.saveOriginal(resources: [
            .init(url: still, fileExtension: "jpg", role: .photo, typeIdentifier: "public.jpeg"),
            .init(url: pairedMotion, fileExtension: "mov", role: .pairedVideo, typeIdentifier: "com.apple.quicktime-movie")],
            originalKind: .livePhoto, creationDate: Date(), kind: .photo, width: 960, height: 720, duration: 0,
            thumbnail: Self.photo(Self.hasMarketingMedia ? 1 : 0), session: session))
        try await work.reset()
        let organization = try await store.saveAlbum(name: Self.hasMarketingMedia ? "Escapes" : "Weekend", session: session)
        _ = try await store.saveAlbum(name: Self.hasMarketingMedia ? "Everyday" : "Documents", session: session)
        _ = try await store.organize(ids: Set(saved.prefix(3).map(\.id)), edit: .addToAlbum(organization.albums[0].id), session: session)
        _ = try await store.organize(ids: Set(saved.prefix(2).map(\.id)), edit: .favorite(true), session: session)
        _ = try await store.organize(ids: [saved[0].id], edit: .tags(["travel", "sample"]), session: session)
        _ = try await store.organize(ids: [saved[0].id], edit: .description(caption: "Sample travel pass", notes: "Generated visual-review fixture. No personal data."), session: session)
        if Self.hasMarketingMedia {
            let captions = ["Lisbon weekend", "A slow morning", "First light at the lake", "The long way home", "One more hour by the sea"]
            for index in 0..<5 {
                _ = try await store.organize(ids: [saved[index].id], edit: .tags(index == 1 ? ["coffee", "morning"] : ["travel", "weekend"]), session: session)
                _ = try await store.organize(ids: [saved[index].id], edit: .description(caption: captions[index], notes: index == 4 ? "The little path past the wildflowers leads down to the cove.\n\nCome back just before sunset. Bring a book and stay until the light is gone." : "A favorite moment from the weekend."), session: session)
            }
        }
        for name in ["headphones", "portrait"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"))
            let data = try Data(contentsOf: url)
            let source = try await work.write(data, extension: "jpg", session: await work.currentSession())
            let item = try await store.save(file: source, fileExtension: "jpg", kind: .photo, width: 1_024, height: 1_024,
                duration: 0, thumbnail: data, profile: nil, session: session)
            _ = try await store.organize(ids: [item.id], edit: .description(caption: name == "headphones" ? "A little listening time" : "A friend at the cafe",
                notes: name == "headphones" ? "A new playlist for quiet afternoons." : "Coffee and a catch-up before the weekend."), session: session)
            try await work.remove(source)
        }
        let credentials = GalleryLockStore()
        try await credentials.reset()
        _ = try await credentials.configure(mode: .off, pin: "", keys: [])
        var settings = GallerySettingsRecord()
        settings.onboardingCompleted = true
        settings.shareOutputFormat = GalleryOutputFormat.png.rawValue
        settings.presets = [DecoyPreset(name: "Weekend camera", profile: MetadataForge.randomProfile())]
        settings.sharingPresets = [.init(name: "Small silent copy", format: .jpeg, maximumDimension: 2_048, quality: 0.75, videoMaximumEdge: 960, removeAudio: true)]
        try GallerySettingsStore().save(settings)
        #if targetEnvironment(simulator)
        if let url = Bundle(for: Self.self).url(forResource: "native-vision-classifications", withExtension: "json") {
            let reference = try JSONDecoder().decode([String: [GalleryVisualTag]].self, from: Data(contentsOf: url))
            _ = try await store.setVisualSearch(enabled: true, session: session)
            let items = try await store.list(), organization = try await store.organization()
            for item in items where item.kind == .photo {
                let key = organization.items[item.id]?.caption ?? "fixture-live-photo"
                // Legacy generated cards have no native photographic reference.
                let tags = reference[key] ?? []
                _ = try await store.setVisualTags(id: item.id, tags: tags, session: session)
            }
        }
        #endif
    }

    func testRenderUpgradeScreensInDisposableReviewApp() async throws {
        try XCTSkipUnless(Self.isReviewHost, "Rendering requires the isolated simulator or iOS app on Mac.")
        try XCTSkipUnless(Bundle.main.bundleIdentifier?.hasSuffix(".gallery-features.visual-review") == true,
            "Render only inside the isolated simulator review app.")
        let model = GalleryViewModel(inbox: try? GalleryImportInbox.appInbox(), queryInterpreter: Self.reviewInterpreter)
        await model.start()
        let unlocked = await model.unlockPrivate()
        XCTAssertTrue(unlocked)
        let photo = try XCTUnwrap(model.privateAssets.first { $0.kind == .photo && $0.originalKind == nil })
        let document = model.privateAssets.first { model.organization.items[$0.id]?.caption == "Lisbon weekend" } ?? photo
        let video = try XCTUnwrap(model.privateAssets.first { $0.kind == .video })
        if Self.hasMarketingMedia {
            await model.setTextSearch(true)
            model.indexText()
            for _ in 0..<200 where model.isAnalyzing { try await Task.sleep(for: .milliseconds(100)) }
            XCTAssertFalse(model.isAnalyzing)
        }
        #if targetEnvironment(simulator)
        try XCTSkipUnless(Bundle(for: Self.self).url(forResource: "native-vision-classifications", withExtension: "json") != nil,
            "This simulator classifier is unsupported; render using genuine Vision reference results exported by the native iOS-on-Mac test.")
        #endif
        await model.setVisualSearch(true)
        for _ in 0..<400 {
            if model.untaggedPhotoCount == 0 && !model.isAnalyzing { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(model.untaggedPhotoCount, 0, model.errorMessage ?? "Expected automatic AI tagging")
        await model.setAIQueryInterpretation(true)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            var reference: [String: [GalleryVisualTag]] = [:]
            for item in model.privateAssets where item.kind == .photo {
                let key = model.organization.items[item.id]?.caption ?? "fixture-live-photo"
                reference[key] = model.organization.items[item.id]?.visualTags
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let attachment = XCTAttachment(data: try encoder.encode(reference), uniformTypeIdentifier: UTType.json.identifier)
            attachment.name = "native-vision-classifications"; attachment.lifetime = .keepAlways; add(attachment)
        }
        let headphones = try XCTUnwrap(model.privateAssets.first { model.organization.items[$0.id]?.caption == "A little listening time" })
        XCTAssertTrue(model.organization.matches("headphones", id: headphones.id))
        let synonyms = GallerySearchAliasGroup(terms: ["sunglasses", "shades", "óculos de sol"])
        let savedSynonyms = await model.editSearchAliases(.save(synonyms))
        XCTAssertTrue(savedSynonyms)
        if Self.hasMarketingMedia { XCTAssertTrue(model.organization.matches("shades", id: document.id)) }
        let portrait = try XCTUnwrap(model.privateAssets.first { model.organization.items[$0.id]?.caption == "A friend at the cafe" })
        let loadedPortrait = try await model.shareEditorImage(for: portrait)
        let portraitImage = try XCTUnwrap(loadedPortrait.cgImage)
        let faceMasks = try await Task.detached {
            try GalleryRedactionSuggestions.detect(in: portraitImage, options: .init(faces: true, text: .off, codes: false))
        }.value
        XCTAssertFalse(faceMasks.isEmpty)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let screens: [(String, AnyView)] = [
            ("library", AnyView(GalleryView(source: .privateLibrary))),
            ("detail", AnyView(NavigationStack { AssetDetailView(asset: photo, sequence: model.privateAssets) })),
            ("fullscreen", AnyView(GalleryFullscreenViewer(items: model.privateAssets, selectedID: photo.id))),
            ("photo-editor", AnyView(GalleryPhotoEditorView(asset: photo))),
            ("notes", AnyView(GalleryNotesView(asset: photo))),
            ("photo-share", AnyView(GalleryShareFlowView(request: .init(assets: [document], profile: nil)))),
            ("video-share", AnyView(GalleryShareFlowView(request: .init(assets: [video], profile: nil)))),
            ("storage", AnyView(NavigationStack { GalleryStorageView() })),
            ("text-search", AnyView(NavigationStack { GalleryTextSearchView() })),
            ("smart-search", AnyView(NavigationStack { GallerySmartSearchView() })),
            ("search-synonyms", AnyView(NavigationStack { GallerySearchAliasesView() })),
            ("synonym-editor", AnyView(NavigationStack { GallerySearchAliasEditor(group: synonyms, isNew: false) })),
            ("shades-search", AnyView(GalleryView(source: .privateLibrary, initialSearchText: "shades"))),
            ("headphones-search", AnyView(GalleryView(source: .privateLibrary, initialSearchText: "headphones"))),
            ("face-blur", AnyView(GalleryShareFlowView(request: .init(assets: [portrait], profile: nil), initialEdits: .init(redactions: faceMasks)))),
            ("inbox", AnyView(NavigationStack { GalleryInboxView() })),
            ("settings", AnyView(GallerySettingsView()))
        ]
        func capture(_ name: String, _ screen: AnyView) async throws {
            let window = UIWindow(windowScene: scene)
            window.frame = scene.screen.bounds
            let root = screen.environmentObject(model).environmentObject(model.lock)
            let host = UIHostingController(rootView: root)
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            // Let visible cells finish their asynchronous thumbnail loads before capture.
            try await Task.sleep(for: .milliseconds(name == "library" ? 2_000 : 750))
            if name == "semantic-search" {
                for _ in 0..<200 where model.interpretedSearch == nil { try await Task.sleep(for: .milliseconds(50)) }
                XCTAssertNotNil(model.interpretedSearch, model.searchInterpretationMessage ?? "Expected real AI query interpretation")
                // The filtered thumbnail starts loading only after the AI plan
                // publishes; give that new visible cell time to finish too.
                try await Task.sleep(for: .milliseconds(750))
            }
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
            let image = renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            XCTAssertGreaterThan(image.size.width, 300)
            let attachment = XCTAttachment(image: image)
            let platform = ProcessInfo.processInfo.isiOSAppOnMac ? "mac" : (UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
            attachment.name = "upgrade-\(platform)-\(name)"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
        for (name, screen) in screens { try await capture(name, screen) }
        if ProcessInfo.processInfo.isiOSAppOnMac, model.queryInterpreterAvailability.isAvailable {
            try await capture("semantic-search", AnyView(GalleryView(source: .privateLibrary,
                initialSearchText: "the things you wear on your ears to hear music")))
        }
        if Self.hasMarketingMedia {
            var edits = GalleryShareEdits()
            edits.redactions = [.init(rect: CGRect(x: 0.405, y: 0.414, width: 0.205, height: 0.05)),
                                .init(rect: CGRect(x: 0.508, y: 0.485, width: 0.105, height: 0.038))]
            model.beginShare([document])
            await model.prepareShares(assets: [document], configuration: GalleryPreferences.configuration(format: "png", maximumDimension: 4_096, quality: 0.9), profile: nil, edits: edits)
            XCTAssertNotNil(model.sharePayload, model.errorMessage ?? "Expected the actual rendered export")
            try await capture("review", AnyView(GalleryShareFlowView(request: .init(assets: [document], profile: nil))))
            model.finishShare()
        }
        model.beginShare([portrait])
        await model.prepareShares(assets: [portrait], configuration: GalleryPreferences.configuration(format: "png", maximumDimension: 4_096, quality: 0.9), profile: nil, edits: .init(redactions: faceMasks))
        XCTAssertNotNil(model.sharePayload, model.errorMessage ?? "Expected an actual photo with blur burned in")
        try await capture("face-blur-export", AnyView(GalleryShareFlowView(request: .init(assets: [portrait], profile: nil))))
        model.finishShare()
        await model.lockPrivate()
        await model.purgeAndReset()
        XCTAssertFalse(model.resetNeedsRetry, "The disposable review app must remove its fixture keys and media")
    }

    func testRenderSmartFeatureDefaultsAndAvailabilityStates() async throws {
        try XCTSkipUnless(Self.isReviewHost && Bundle.main.bundleIdentifier?.hasSuffix(".gallery-features.visual-review") == true,
            "Availability screenshots require the isolated review app.")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let states: [(GalleryQueryInterpreterAvailability.State, String)] = [
            (.ready, "smart-defaults-off"), (.unsupported, "settings-smart-unsupported"),
            (.intelligenceDisabled, "smart-intelligence-off"), (.modelNotReady, "smart-model-downloading")
        ]
        for (state, name) in states {
            let suite = "GalleryAvailabilityUI-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let settings = GallerySettingsStore(service: suite, defaults: defaults)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            let credentials = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
            _ = try await credentials.configure(mode: .off, pin: "", keys: [])
            let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: root.appendingPathComponent("exports")),
                privateStore: PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys()),
                workStore: MediaWorkStore(root: root.appendingPathComponent("work")), defaults: defaults,
                lock: GalleryLockController(store: credentials), preferencesDomain: suite, settingsStore: settings,
                queryInterpreter: AvailabilityFixtureInterpreter(state: state))
            await model.start(); let unlocked = await model.unlockPrivate(); XCTAssertTrue(unlocked)
            XCTAssertFalse(model.organization.visualSearchEnabled == true)
            XCTAssertFalse(model.organization.aiQueryInterpretationEnabled == true)
            XCTAssertEqual(model.showsSmartSearch, state != .unsupported)
            XCTAssertEqual(model.smartFeaturesAvailable, state == .ready)
            let screens = state == .intelligenceDisabled
                ? [(name, AnyView(NavigationStack { GallerySmartSearchView() })), ("settings-smart-intelligence-off", AnyView(GallerySettingsView()))]
                : [(name, state == .unsupported ? AnyView(GallerySettingsView()) : AnyView(NavigationStack { GallerySmartSearchView() }))]
            for (screenName, screen) in screens {
                let window = UIWindow(windowScene: scene); window.frame = scene.screen.bounds
                let host = UIHostingController(rootView: screen.environmentObject(model).environmentObject(model.lock))
                window.rootViewController = host; window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(750))
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                let platform = ProcessInfo.processInfo.isiOSAppOnMac ? "mac" : (UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
                attachment.name = "upgrade-\(platform)-\(screenName)"; attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
            }
            await model.lockPrivate()
            try settings.purge(); defaults.removePersistentDomain(forName: suite)
            try FileManager.default.removeItem(at: root)
        }
    }

    private static var reviewInterpreter: any GallerySearchQueryInterpreting {
        #if targetEnvironment(simulator)
        // Readiness is injected only for UI layout; the interpreter still calls
        // the real model and cannot manufacture functional AI search results.
        AvailabilityFixtureInterpreter(state: .ready)
        #else
        GalleryAIQueryInterpreter()
        #endif
    }

    private struct AvailabilityFixtureInterpreter: GallerySearchQueryInterpreting {
        let state: GalleryQueryInterpreterAvailability.State
        var availability: GalleryQueryInterpreterAvailability {
            let message: String
            switch state {
            case .unsupported: message = "Smart Search requires a device that supports Apple Intelligence."
            case .intelligenceDisabled: message = "Turn on Apple Intelligence in system Settings to enable Smart Search. Tagging and AI search are unavailable while Apple Intelligence is off."
            case .modelNotReady: message = "Apple Intelligence's local model isn't ready yet. Smart Search will be available once the model is ready."
            case .ready: message = "Apple Intelligence is ready on this device. Smart features stay off until you enable them. Photo tags are in English."
            }
            return .init(state: state, message: message)
        }
        func interpret(_ query: String, labels: [String]) async throws -> GallerySearchQueryPlan {
            try await GalleryAIQueryInterpreter().interpret(query, labels: labels)
        }
    }

    private static var isReviewHost: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    private static var hasMarketingMedia: Bool {
        Bundle(for: GalleryVisualFixtureTests.self).url(forResource: "marketing-coast", withExtension: "jpg") != nil
    }

    private static func photo(_ index: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        if hasMarketingMedia {
            let names = ["itinerary", "cafe", "mountains", "city", "coast"]
            let url = Bundle(for: GalleryVisualFixtureTests.self).url(forResource: "marketing-\(names[index % names.count])", withExtension: "jpg")!
            let image = UIImage(contentsOfFile: url.path)!
            return UIGraphicsImageRenderer(size: CGSize(width: 960, height: 720), format: format).jpegData(withCompressionQuality: 0.95) { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: 960, height: 720))
            }
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 960, height: 720), format: format).jpegData(withCompressionQuality: 0.92) { context in
            let colors: [UIColor] = [.systemTeal, .systemIndigo, .systemGreen, .systemOrange, .systemBlue, .systemPink]
            colors[index % colors.count].setFill(); context.fill(CGRect(x: 0, y: 0, width: 960, height: 720))
            UIColor.white.withAlphaComponent(0.2).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 620, y: -150, width: 450, height: 450))
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 90, y: 170, width: 780, height: 400), cornerRadius: 35).fill()
            let title = index == 0 ? "SAMPLE TRAVEL PASS" : "Sample \(index + 1)"
            title.draw(at: CGPoint(x: 135, y: 220), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 40), .foregroundColor: UIColor.darkGray])
            "DEMO  •  NO PERSONAL DATA".draw(at: CGPoint(x: 135, y: 310), withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.gray])
            "ABC 1234".draw(at: CGPoint(x: 135, y: 405), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 52, weight: .medium), .foregroundColor: UIColor.black])
        }
    }

    private static func video(_ url: URL, photoIndex: Int? = nil) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640, AVVideoHeightKey: 480])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 480,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(input)
        guard writer.startWriting() else { throw VideoSanitizer.VideoError.conversionFailed }
        writer.startSession(atSourceTime: .zero)
        let still = try XCTUnwrap(UIImage(data: photo(photoIndex ?? (hasMarketingMedia ? 2 : 0)))?.cgImage)
        for index in 0..<90 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var optional: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &optional)
            let buffer = try XCTUnwrap(optional)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 480,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            let zoom = hasMarketingMedia ? 1 + Double(index) / 1_800 : 1
            context.draw(still, in: CGRect(x: -(zoom - 1) * 320, y: -(zoom - 1) * 240, width: 640 * zoom, height: 480 * zoom))
            if !hasMarketingMedia {
                context.setFillColor(UIColor.systemYellow.cgColor)
                context.fillEllipse(in: CGRect(x: index * 5, y: 10, width: 45, height: 45))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw VideoSanitizer.VideoError.conversionFailed }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw VideoSanitizer.VideoError.conversionFailed }
    }
}
