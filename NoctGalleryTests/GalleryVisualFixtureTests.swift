@preconcurrency import AVFoundation
import UIKit
import XCTest
@testable import NoctGallery

/// Explicit fixture installer for a separate simulator app. Never runs against
/// the production bundle or modifies the simulator's Photos library.
@MainActor
final class GalleryVisualFixtureTests: XCTestCase {
    func testInstallDisposableVisualFixtures() async throws {
        #if targetEnvironment(simulator)
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
        for index in 0..<6 {
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
        let still = try await work.write(Self.photo(0), extension: "jpg", session: workSession)
        saved.append(try await store.saveOriginal(resources: [
            .init(url: still, fileExtension: "jpg", role: .photo, typeIdentifier: "public.jpeg"),
            .init(url: motion, fileExtension: "mov", role: .pairedVideo, typeIdentifier: "com.apple.quicktime-movie")],
            originalKind: .livePhoto, creationDate: Date(), kind: .photo, width: 960, height: 720, duration: 0,
            thumbnail: Self.photo(0), session: session))
        try await work.reset()
        let organization = try await store.saveAlbum(name: "Weekend", session: session)
        _ = try await store.saveAlbum(name: "Documents", session: session)
        _ = try await store.organize(ids: Set(saved.prefix(3).map(\.id)), edit: .addToAlbum(organization.albums[0].id), session: session)
        _ = try await store.organize(ids: Set(saved.prefix(2).map(\.id)), edit: .favorite(true), session: session)
        _ = try await store.organize(ids: [saved[0].id], edit: .tags(["travel", "sample"]), session: session)
        let credentials = GalleryLockStore()
        try await credentials.reset()
        _ = try await credentials.configure(mode: .off, pin: "", keys: [])
        var settings = GallerySettingsRecord()
        settings.onboardingCompleted = true
        settings.shareOutputFormat = GalleryOutputFormat.png.rawValue
        settings.presets = [DecoyPreset(name: "Weekend camera", profile: MetadataForge.randomProfile())]
        try GallerySettingsStore().save(settings)
        #else
        throw XCTSkip("Simulator fixtures only")
        #endif
    }

    private static func photo(_ index: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
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

    private static func video(_ url: URL) async throws {
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
        let still = try XCTUnwrap(UIImage(data: photo(0))?.cgImage)
        for index in 0..<90 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var optional: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &optional)
            let buffer = try XCTUnwrap(optional)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 480,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.draw(still, in: CGRect(x: 0, y: 0, width: 640, height: 480))
            context.setFillColor(UIColor.systemYellow.cgColor)
            context.fillEllipse(in: CGRect(x: index * 5, y: 10, width: 45, height: 45))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw VideoSanitizer.VideoError.conversionFailed }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw VideoSanitizer.VideoError.conversionFailed }
    }
}
