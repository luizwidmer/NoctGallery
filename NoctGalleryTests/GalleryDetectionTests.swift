import CoreImage
import ImageIO
import UIKit
import XCTest
@testable import NoctGallery

@MainActor
final class GalleryDetectionTests: XCTestCase {
    func testSensitiveTextIncludesContactDetailsDocumentsNumbersAndPlates() {
        for value in ["hello@example.test", "+1 415 555 0134", "https://example.test", "Passport", "Booking reference",
                      "CPF 123.456.789-00", "Senha", "AB1C234", "1234 5678 9012 3456"] {
            XCTAssertTrue(GalleryRedactionSuggestions.isSensitiveText(value), value)
        }
        for value in ["A slow morning", "Coffee by the sea", "Summer landscape"] {
            XCTAssertFalse(GalleryRedactionSuggestions.isSensitiveText(value), value)
        }
    }

    func testAccurateSmallTextDetectionAndSensitiveModeSelectDifferentAreas() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_000, height: 700), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 700))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black]
            "Coffee by the sea".draw(at: CGPoint(x: 80, y: 80), withAttributes: attributes)
            "hello@example.test".draw(at: CGPoint(x: 80, y: 420), withAttributes: attributes)
        }
        let source = try XCTUnwrap(image.cgImage)
        let all = try await Task.detached {
            try GalleryRedactionSuggestions.detect(in: source, options: .init(faces: false, text: .all, codes: false, sensitivity: .thorough))
        }.value
        let sensitive = try await Task.detached {
            try GalleryRedactionSuggestions.detect(in: source, options: .init(faces: false, text: .sensitive, codes: false, sensitivity: .thorough))
        }.value
        XCTAssertGreaterThanOrEqual(all.count, 2)
        XCTAssertEqual(sensitive.count, 1)
        XCTAssertTrue(all.allSatisfy { $0.isValid && $0.detectionKind == .text })
        XCTAssertGreaterThan(try XCTUnwrap(sensitive.first).rect.minY, 0.5, "Suggestions must use upright top-left coordinates")
    }

    func testQRCodesAreDetectedWithoutTextAndOnlyBoundsAreReturned() async throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data("https://example.test/private-fixture".utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let ci = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let qr = try XCTUnwrap(CIContext().createCGImage(ci, from: ci.extent))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: qr).draw(in: CGRect(x: 340, y: 60, width: 220, height: 220))
        }
        let source = try XCTUnwrap(image.cgImage)
        let attachment = XCTAttachment(image: image); attachment.name = "generated-qr-fixture"; attachment.lifetime = .keepAlways; add(attachment)
        let detected = try await Task.detached {
            try GalleryRedactionSuggestions.detect(in: source, options: .init(faces: false, text: .off, codes: true))
        }.value
        let code = try XCTUnwrap(detected.first)
        XCTAssertEqual(code.detectionKind, .code); XCTAssertTrue(code.isValid)
        XCTAssertGreaterThan(code.rect.midX, 0.5); XCTAssertLessThan(code.rect.midY, 0.5)
        let disabled = try await Task.detached {
            try GalleryRedactionSuggestions.detect(in: source, options: .init(faces: false, text: .off, codes: false))
        }.value
        XCTAssertTrue(disabled.isEmpty)
    }

    func testRealFaceDetectionPadsFaceBoundsAndRespectsFaceSwitch() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "portrait", withExtension: "jpg"))
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let found = try await Task.detached {
            try GalleryRedactionSuggestions.detect(in: image, options: .init(faces: true, text: .off, codes: false))
        }.value
        XCTAssertEqual(found.count, 1)
        let face = try XCTUnwrap(found.first)
        XCTAssertEqual(face.detectionKind, .face); XCTAssertTrue(face.isValid)
        XCTAssertGreaterThan(face.rect.width, 0.2); XCTAssertGreaterThan(face.rect.height, 0.2)
        let off = try await Task.detached {
            try GalleryRedactionSuggestions.detect(in: image, options: .init(faces: false, text: .off, codes: false))
        }.value
        XCTAssertTrue(off.isEmpty)
    }

    func testDuplicateNestedSuggestionsAreRemovedAndResultCountIsBounded() {
        let outer = GalleryRedaction(rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), detectionKind: .face)
        let inner = GalleryRedaction(rect: CGRect(x: 0.15, y: 0.15, width: 0.1, height: 0.1), detectionKind: .text)
        let unique = GalleryRedactionSuggestions.deduplicated([inner, outer, outer])
        XCTAssertEqual(unique, [outer])
        let many = (0..<200).map { index in GalleryRedaction(rect: CGRect(x: Double(index % 20) * 0.05,
            y: Double(index / 20) * 0.05, width: 0.025, height: 0.025), detectionKind: .text) }
        let bounded = GalleryRedactionSuggestions.deduplicated(many)
        XCTAssertEqual(bounded.count, 100); XCTAssertTrue(bounded.allSatisfy(\.isValid))
    }
}
