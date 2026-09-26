@preconcurrency import AVFoundation
import Foundation
import ImageIO
import Vision
import CoreML
import UIKit

struct GalleryMetadataField: Identifiable, Equatable, Sendable {
    let name: String
    let value: String
    var id: String { name }
}

struct GalleryExportInspection: Sendable {
    let byteCount: Int
    let width: Int
    let height: Int
    let duration: Double
    let hasAudio: Bool
    let fields: [GalleryMetadataField]

    static func inspect(url: URL, kind: GalleryMediaKind) async throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= PrivateMediaStore.maximumBytes else { throw PrivateMediaStore.StoreError.mediaTooLarge }
        if kind == .photo {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
                throw ImageSanitizer.SanitizationError.unsupportedOrMalformedImage
            }
            return .init(byteCount: size, width: (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0,
                height: (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0,
                duration: 0, hasAudio: false, fields: fields(properties))
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoSanitizer.VideoError.unsupported }
        let dimensions = try await track.load(.naturalSize)
        return try await .init(byteCount: size, width: Int(dimensions.width), height: Int(dimensions.height), duration: duration,
            hasAudio: !asset.loadTracks(withMediaType: .audio).isEmpty, fields: videoFields(asset))
    }

    static func photoFields(_ data: Data) throws -> [GalleryMetadataField] {
        guard data.count <= ImageSanitizer.Configuration().maximumEncodedBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw ImageSanitizer.SanitizationError.unsupportedOrMalformedImage
        }
        return fields(properties)
    }

    static func videoFields(_ asset: AVAsset) async throws -> [GalleryMetadataField] {
        var values: [String: String] = [:]
        for format in try await asset.load(.availableMetadataFormats) {
            for item in try await asset.loadMetadata(for: format) {
                guard values.count < 300 else { break }
                let name = item.identifier?.rawValue ?? "\(format.rawValue).\(String(describing: item.key))"
                values[String(name.prefix(160))] = String((try await item.load(.stringValue) ?? "Binary metadata").prefix(300))
            }
        }
        return values.keys.sorted().map { .init(name: $0, value: values[$0]!) }
    }

    private static func fields(_ properties: [String: Any]) -> [GalleryMetadataField] {
        var result: [String: String] = [:]
        func visit(_ value: Any, name: String, depth: Int) {
            guard result.count < 300, depth < 5 else { return }
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted().prefix(300) { visit(dictionary[key]!, name: name.isEmpty ? key : name + "." + key, depth: depth + 1) }
            } else if let text = value as? String {
                result[String(name.prefix(160))] = String(text.prefix(300))
            } else if let number = value as? NSNumber {
                result[String(name.prefix(160))] = number.stringValue
            } else if let array = value as? [Any] {
                for (index, entry) in array.prefix(32).enumerated() { visit(entry, name: name + "[\(index)]", depth: depth + 1) }
            } else if let data = value as? Data {
                result[String(name.prefix(160))] = "Binary data (\(data.count) bytes)"
            }
        }
        visit(properties, name: "", depth: 0)
        return result.keys.sorted().map { .init(name: $0, value: result[$0]!) }
    }
}

struct GalleryReviewedExport: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let kind: GalleryMediaKind
    let inspection: GalleryExportInspection
    let originalMetadata: [GalleryMetadataField]
}

struct GalleryShareRequest: Identifiable {
    let id = UUID()
    let assets: [PhotoAssetRecord]
    let profile: SyntheticMetadataProfile?
}

/// Detection produces suggestions only. No OCR transcripts are kept or indexed.
enum GalleryRedactionSuggestions {
    static func detect(in image: CGImage) throws -> [GalleryRedaction] {
        try Task.checkCancellation()
        let faces = VNDetectFaceRectanglesRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        #if targetEnvironment(simulator)
        // Simulator devices have no Neural Engine. Use the supported CPU path.
        for request in [faces as VNRequest, text] {
            for (stage, devices) in try request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        #endif
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([faces, text])
        try Task.checkCancellation()
        let boxes = (faces.results ?? []).map(\.boundingBox) + (text.results ?? []).map(\.boundingBox)
        return boxes.prefix(100).map { rect in
            let upright = CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
                .insetBy(dx: -0.008, dy: -0.008).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return GalleryRedaction(rect: upright)
        }.filter(\.isValid)
    }
}
