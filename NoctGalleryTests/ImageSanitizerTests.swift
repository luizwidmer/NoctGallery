import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NoctGallery

final class ImageSanitizerTests: XCTestCase {
    func testCleanShareReencodesPixelsAndRemovesSensitiveMetadata() throws {
        let source = try fixtureJPEG(width: 640, height: 480, includeMetadata: true)
        var configuration = ImageSanitizer.Configuration()
        configuration.outputFormat = .jpeg
        configuration.maximumOutputDimension = 512

        let result = try ImageSanitizer().sanitize(source, configuration: configuration)
        let properties = try outputProperties(result.data)

        XCTAssertNotEqual(result.data, source)
        XCTAssertEqual(result.pixelWidth, 512)
        XCTAssertEqual(result.pixelHeight, 384)
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal as String])
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeDigitized as String])
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment as String])
        XCTAssertNil(exif?[kCGImagePropertyExifBodySerialNumber as String])
        XCTAssertNil(exif?[kCGImagePropertyExifCameraOwnerName as String])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake as String])
        XCTAssertNil(tiff?[kCGImagePropertyTIFFModel as String])
        XCTAssertNil(tiff?[kCGImagePropertyTIFFSoftware as String])
        XCTAssertNil(tiff?[kCGImagePropertyTIFFDateTime as String])
        XCTAssertFalse(result.sha256.isEmpty)
        XCTAssertTrue(result.removedMetadataKeys.contains { $0.contains("GPS") })
    }

    func testSyntheticExportContainsOnlyChosenGeneratedProfile() throws {
        let source = try fixtureJPEG(width: 200, height: 120, includeMetadata: true)
        let profile = SyntheticMetadataProfile(
            id: UUID(),
            make: "Aster Imaging",
            model: "Field 28",
            software: "Capture Stack 5.1",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            latitude: -12.25,
            longitude: 38.75
        )
        var configuration = ImageSanitizer.Configuration()
        configuration.outputFormat = .jpeg

        let result = try ImageSanitizer().sanitize(
            source,
            configuration: configuration,
            syntheticMetadata: profile
        )
        let properties = try outputProperties(result.data)
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary as String] as? [String: Any])

        XCTAssertEqual(tiff[kCGImagePropertyTIFFMake as String] as? String, profile.make)
        XCTAssertEqual(tiff[kCGImagePropertyTIFFModel as String] as? String, profile.model)
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitudeRef as String] as? String, "S")
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef as String] as? String, "E")
    }

    func testMalformedInputIsRejected() {
        XCTAssertThrowsError(try ImageSanitizer().sanitize(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? ImageSanitizer.SanitizationError, .unsupportedOrMalformedImage)
        }
    }

    func testSourcePixelLimitIsEnforcedBeforeDecode() throws {
        let source = try fixtureJPEG(width: 40, height: 40, includeMetadata: false)
        var configuration = ImageSanitizer.Configuration()
        configuration.maximumSourcePixels = 1_000

        XCTAssertThrowsError(try ImageSanitizer().sanitize(source, configuration: configuration)) { error in
            XCTAssertEqual(
                error as? ImageSanitizer.SanitizationError,
                .sourcePixelLimitExceeded(limit: 1_000)
            )
        }
    }

    private func fixtureJPEG(width: Int, height: Int, includeMetadata: Bool) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        var properties: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.9]
        if includeMetadata {
            properties[kCGImagePropertyTIFFDictionary as String] = [
                kCGImagePropertyTIFFMake as String: "Original Camera",
                kCGImagePropertyTIFFModel as String: "Traceable Model"
            ]
            properties[kCGImagePropertyExifDictionary as String] = [
                kCGImagePropertyExifUserComment as String: "private note"
            ]
            properties[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String: 12.5,
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 42.5,
                kCGImagePropertyGPSLongitudeRef as String: "W"
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func outputProperties(_ data: Data) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }
}
