import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import NoctGallery

final class GalleryShareFeatureTests: XCTestCase {
    @MainActor
    func testTextSuggestionsAreBoundedAndUpright() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            "SAMPLE 1234".draw(at: CGPoint(x: 70, y: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let boxes = try await Task.detached { try GalleryRedactionSuggestions.detect(in: cgImage) }.value
        XCTAssertFalse(boxes.isEmpty)
        XCTAssertLessThanOrEqual(boxes.count, 100)
        XCTAssertTrue(boxes.allSatisfy(\.isValid))
        XCTAssertTrue(boxes.contains { $0.rect.minY < 0.3 && $0.rect.maxY < 0.5 })
    }
    func testRedactionIsBurnedIntoUprightExportAndMetadataInspectorReadsOutput() async throws {
        let original = try whiteImage()
        var configuration = ImageSanitizer.Configuration()
        configuration.outputFormat = .png
        let edited = try ImageSanitizer().sanitize(original, configuration: configuration, edits: .init(
            redactions: [.init(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.25))]))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(edited.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThan(try pixel(image, x: 10, y: 5), 5, "Top-left cover must be black")
        XCTAssertGreaterThan(try pixel(image, x: 10, y: 70), 245, "Bottom-left pixels must stay white")
        XCTAssertGreaterThan(try pixel(image, x: 75, y: 5), 245)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try edited.data.write(to: url)
        let inspection = try await GalleryExportInspection.inspect(url: url, kind: .photo)
        XCTAssertEqual(inspection.width, 100)
        XCTAssertEqual(inspection.height, 80)
        XCTAssertEqual(inspection.byteCount, edited.data.count)
        XCTAssertFalse(inspection.fields.contains { $0.name.contains("GPS") || $0.value == "source-secret" })
        XCTAssertTrue(try GalleryExportInspection.photoFields(original).contains { $0.value == "source-secret" })
    }

    func testInvalidAndNonfiniteMasksAreRejectedBeforePixelAccess() throws {
        for rect in [CGRect(x: -1, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 2, height: 1),
                     CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 0, height: 1)] {
            XCTAssertThrowsError(try GalleryShareEdits(redactions: [.init(rect: rect)]).validated())
        }
        XCTAssertThrowsError(try GalleryShareEdits(trimStart: 5, trimEnd: 2).validated(duration: 10))
        XCTAssertThrowsError(try GalleryShareEdits(trimStart: 2, trimEnd: 10).validated(duration: 5))
        XCTAssertThrowsError(try GalleryShareEdits(trimStart: .nan).validated(duration: 5))
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 100, 80, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        XCTAssertThrowsError(try GalleryShareEdits(redactions: [.init(rect: CGRect(x: 2, y: 0, width: 1, height: 1))])
            .redact(try XCTUnwrap(buffer)))
    }

    func testVideoPixelMasksUseTopLeftCoordinatesAndNeverOverwritePadding() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 100, 80, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        let pointer = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixel))
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        memset(pointer, 255, stride * 80)
        CVPixelBufferUnlockBaseAddress(pixel, [])
        try GalleryShareEdits(redactions: [.init(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.25))]).redact(pixel)
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        let values = pointer.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(values[5 * stride + 10 * 4], 0)
        XCTAssertEqual(values[5 * stride + 10 * 4 + 3], 255)
        XCTAssertEqual(values[70 * stride + 10 * 4], 255)
        if stride > 400 { XCTAssertEqual(values[400], 255) }
    }

    func testBatchLifecycleReleasesEveryExportExactlyOnce() {
        let urls = (0..<4).map { URL(fileURLWithPath: "/tmp/test-\($0).jpg") }
        var lifecycle = ShareExportLifecycle()
        lifecycle.present(urls)
        XCTAssertEqual(lifecycle.dismissAll(), urls)
        XCTAssertTrue(lifecycle.dismissAll().isEmpty)
    }

    private func whiteImage() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "source-secret"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 13.2, kCGImagePropertyGPSLatitudeRef: "N"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)[0]
    }
}
