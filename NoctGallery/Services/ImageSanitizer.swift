import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageSanitizer: Sendable {
    struct Configuration: Sendable, Equatable {
        var maximumEncodedBytes = 64 * 1_024 * 1_024
        var maximumSourcePixels = 120_000_000
        var maximumOutputDimension = 8_192
        var lossyQuality = 0.90
        var outputFormat = GalleryOutputFormat.heic

        func validated() throws -> Configuration {
            guard maximumEncodedBytes > 0,
                  maximumSourcePixels > 0,
                  (512 ... 8_192).contains(maximumOutputDimension),
                  (0.50 ... 1.0).contains(lossyQuality) else {
                throw SanitizationError.invalidConfiguration
            }
            return self
        }
    }

    enum SanitizationError: LocalizedError, Equatable {
        case emptyInput
        case encodedInputTooLarge(limit: Int)
        case unsupportedOrMalformedImage
        case invalidDimensions
        case sourcePixelLimitExceeded(limit: Int)
        case decodeFailed
        case colorNormalizationFailed
        case encodingUnavailable
        case encodingFailed
        case metadataVerificationFailed(keys: [String])
        case invalidConfiguration

        var errorDescription: String? {
            switch self {
            case .emptyInput: "The selected file is empty."
            case .encodedInputTooLarge(let limit): "The selected file exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) input limit."
            case .unsupportedOrMalformedImage: "The selected file is not a supported, well-formed image."
            case .invalidDimensions: "The image reports invalid dimensions."
            case .sourcePixelLimitExceeded: "The image dimensions exceed the safe decode limit."
            case .decodeFailed: "The image could not be decoded safely."
            case .colorNormalizationFailed: "The image could not be normalized into the safe color pipeline."
            case .encodingUnavailable: "The requested sanitized output format is unavailable."
            case .encodingFailed: "The sanitized image could not be encoded."
            case .metadataVerificationFailed(let keys): "The clean output failed metadata verification: \(keys.joined(separator: ", "))."
            case .invalidConfiguration: "The sanitizer configuration is outside its safe bounds."
            }
        }
    }

    func sanitize(
        _ sourceData: Data,
        configuration: Configuration = Configuration(),
        syntheticMetadata: SyntheticMetadataProfile? = nil
    ) throws -> SanitizedImage {
        let configuration = try configuration.validated()
        guard !sourceData.isEmpty else { throw SanitizationError.emptyInput }
        guard sourceData.count <= configuration.maximumEncodedBytes else {
            throw SanitizationError.encodedInputTooLarge(limit: configuration.maximumEncodedBytes)
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [String: Any] else {
            throw SanitizationError.unsupportedOrMalformedImage
        }

        guard let sourceWidth = number(properties[kCGImagePropertyPixelWidth as String]),
              let sourceHeight = number(properties[kCGImagePropertyPixelHeight as String]),
              sourceWidth > 0,
              sourceHeight > 0 else {
            throw SanitizationError.invalidDimensions
        }
        guard sourceWidth <= configuration.maximumSourcePixels / sourceHeight else {
            throw SanitizationError.sourcePixelLimitExceeded(limit: configuration.maximumSourcePixels)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: configuration.maximumOutputDimension,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw SanitizationError.decodeFailed
        }
        let normalized = try normalize(decoded)
        let encoded = try encode(
            normalized,
            format: configuration.outputFormat,
            quality: configuration.lossyQuality,
            syntheticMetadata: syntheticMetadata
        )

        if syntheticMetadata == nil {
            try verifySensitiveMetadataIsAbsent(encoded.data)
        }

        let digest = SHA256.hash(data: encoded.data).map { String(format: "%02x", $0) }.joined()
        return SanitizedImage(
            data: encoded.data,
            sourceByteCount: sourceData.count,
            pixelWidth: normalized.width,
            pixelHeight: normalized.height,
            outputUTType: encoded.utType,
            fileExtension: encoded.fileExtension,
            sha256: digest,
            removedMetadataKeys: metadataKeyPaths(in: properties)
        )
    }

    private func normalize(_ image: CGImage) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw SanitizationError.colorNormalizationFailed
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let normalized = context.makeImage() else {
            throw SanitizationError.colorNormalizationFailed
        }
        return normalized
    }

    private func encode(
        _ image: CGImage,
        format: GalleryOutputFormat,
        quality: Double,
        syntheticMetadata: SyntheticMetadataProfile?
    ) throws -> (data: Data, utType: String, fileExtension: String) {
        let requested = outputDescriptor(for: format)
        let supported = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        let descriptor: (utType: String, fileExtension: String)
        if supported.contains(requested.utType) {
            descriptor = requested
        } else if format == .heic, supported.contains(UTType.jpeg.identifier) {
            descriptor = (UTType.jpeg.identifier, "jpg")
        } else {
            throw SanitizationError.encodingUnavailable
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            descriptor.utType as CFString,
            1,
            nil
        ) else {
            throw SanitizationError.encodingUnavailable
        }
        var destinationProperties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: quality
        ]
        if let syntheticMetadata {
            destinationProperties.merge(
                MetadataForge.destinationProperties(for: syntheticMetadata, lossyQuality: quality),
                uniquingKeysWith: { _, generated in generated }
            )
        }
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw SanitizationError.encodingFailed
        }
        return (output as Data, descriptor.utType, descriptor.fileExtension)
    }

    private func outputDescriptor(for format: GalleryOutputFormat) -> (utType: String, fileExtension: String) {
        switch format {
        case .heic: (UTType.heic.identifier, "heic")
        case .jpeg: (UTType.jpeg.identifier, "jpg")
        case .png: (UTType.png.identifier, "png")
        }
    }

    private func verifySensitiveMetadataIsAbsent(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw SanitizationError.metadataVerificationFailed(keys: ["unreadable output"])
        }
        let sensitiveDictionaries = [
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyMakerAppleDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImageProperty8BIMDictionary,
            kCGImagePropertyDNGDictionary
        ]
        let presentDictionaries = sensitiveDictionaries
            .map { $0 as String }
            .filter { properties[$0] != nil }
        guard presentDictionaries.isEmpty else {
            throw SanitizationError.metadataVerificationFailed(keys: presentDictionaries)
        }

        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            let allowedStructuralFields = Set([
                kCGImagePropertyExifColorSpace as String,
                kCGImagePropertyExifPixelXDimension as String,
                kCGImagePropertyExifPixelYDimension as String
            ])
            let unexpectedFields = Set(exif.keys).subtracting(allowedStructuralFields).sorted()
            guard unexpectedFields.isEmpty else {
                throw SanitizationError.metadataVerificationFailed(
                    keys: unexpectedFields.map { "Exif.\($0)" }
                )
            }
        }

        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            let identifyingTIFFKeys = [
                kCGImagePropertyTIFFMake,
                kCGImagePropertyTIFFModel,
                kCGImagePropertyTIFFSoftware,
                kCGImagePropertyTIFFArtist,
                kCGImagePropertyTIFFCopyright,
                kCGImagePropertyTIFFDateTime,
                kCGImagePropertyTIFFImageDescription,
                kCGImagePropertyTIFFHostComputer,
                kCGImagePropertyTIFFDocumentName
            ]
            let identifyingFields = identifyingTIFFKeys
                .map { $0 as String }
                .filter { tiff[$0] != nil }
            guard identifyingFields.isEmpty else {
                throw SanitizationError.metadataVerificationFailed(keys: identifyingFields)
            }
        }
    }

    private func metadataKeyPaths(in properties: [String: Any]) -> [String] {
        let structural = Set([
            kCGImagePropertyPixelWidth as String,
            kCGImagePropertyPixelHeight as String,
            kCGImagePropertyDepth as String,
            kCGImagePropertyColorModel as String,
            kCGImagePropertyHasAlpha as String,
            kCGImagePropertyIsIndexed as String
        ])
        var paths: [String] = []
        for key in properties.keys.sorted() where !structural.contains(key) {
            collectPaths(value: properties[key], path: key, into: &paths)
        }
        return Array(Set(paths)).sorted()
    }

    private func collectPaths(value: Any?, path: String, into paths: inout [String]) {
        guard let value else { return }
        if let dictionary = value as? [String: Any] {
            if dictionary.isEmpty { paths.append(path) }
            for key in dictionary.keys.sorted() {
                collectPaths(value: dictionary[key], path: "\(path).\(key)", into: &paths)
            }
        } else {
            paths.append(path)
        }
    }

    private func number(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
