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

struct GalleryDetectionOptions: Equatable, Sendable {
    enum TextMode: String, CaseIterable, Identifiable, Sendable {
        case all, sensitive, off
        var id: Self { self }
        var title: String { switch self { case .all: "All text"; case .sensitive: "Sensitive text"; case .off: "Off" } }
    }
    enum Sensitivity: String, CaseIterable, Identifiable, Sendable {
        case balanced, thorough
        var id: Self { self }
        var title: String { self == .balanced ? "Balanced" : "Thorough" }
    }
    var faces = true
    var text: TextMode = .all
    var codes = true
    var sensitivity: Sensitivity = .balanced
    var hasDetectors: Bool { faces || text != .off || codes }
}

/// Detection produces suggestions only. Text and barcode payloads are discarded.
enum GalleryRedactionSuggestions {
    static func detect(in image: CGImage, options: GalleryDetectionOptions = .init()) throws -> [GalleryRedaction] {
        try Task.checkCancellation()
        let faces = VNDetectFaceRectanglesRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        text.automaticallyDetectsLanguage = true
        text.minimumTextHeight = options.sensitivity == .thorough ? 0.004 : 0.008
        let codes = VNDetectBarcodesRequest()
        #if targetEnvironment(simulator)
        // The newer barcode backends do not decode on this CPU-only runtime.
        codes.revision = 2
        #endif
        var requests: [VNRequest] = []
        if options.faces { requests.append(faces) }
        if options.text != .off { requests.append(text) }
        if options.codes { requests.append(codes) }
        guard !requests.isEmpty else { return [] }
        try GalleryVision.perform(requests, in: image)
        try Task.checkCancellation()
        let threshold: Float = options.sensitivity == .thorough ? 0.2 : 0.45
        var boxes: [(CGRect, GalleryDetectionKind)] = []
        if options.faces { boxes += (faces.results ?? []).filter { $0.confidence >= threshold }.map { ($0.boundingBox, .face) } }
        // Barcode observations carry decoded geometry; their inherited confidence
        // is not calibrated like face and OCR recognition confidence.
        if options.codes { boxes += (codes.results ?? []).map { ($0.boundingBox, .code) } }
        if options.text != .off {
            boxes += (text.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= threshold,
                      options.text == .all || isSensitiveText(candidate.string) else { return nil }
                return (observation.boundingBox, .text)
            }
        }
        let suggestions = boxes.map { rect, kind in
            let padding: CGFloat = kind == .face ? 0.12 : 0.06
            let upright = CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
                .insetBy(dx: -max(0.006, rect.width * padding), dy: -max(0.006, rect.height * padding))
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return GalleryRedaction(rect: upright, detectionKind: kind)
        }.filter(\.isValid)
        let result = deduplicated(suggestions)
        try Task.checkCancellation()
        return result
    }

    static func isSensitiveText(_ value: String) -> Bool {
        let bounded = String(value.prefix(16_000))
        if bounded.filter(\.isNumber).count >= 4 { return true }
        let patterns = [#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                        #"\b(passport|password|booking|reservation|address|license|licence|cpf|rg|senha|endereço|endereco|reserva)\b"#,
                        #"\b[A-Z]{2,4}[ -]?[0-9][A-Z0-9]{2,4}\b"#]
        if patterns.contains(where: { bounded.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) { return true }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: bounded, range: NSRange(bounded.startIndex..., in: bounded)) != nil
    }

    static func deduplicated(_ values: [GalleryRedaction]) -> [GalleryRedaction] {
        var result: [GalleryRedaction] = []
        // Keep larger areas when text is nested inside a face or a code.
        for value in values.filter(\.isValid).sorted(by: { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }) {
            if Task.isCancelled { break }
            let area = value.rect.width * value.rect.height
            guard !result.contains(where: { existing in
                let intersection = existing.rect.intersection(value.rect)
                return !intersection.isNull && intersection.width * intersection.height / area >= 0.9
            }) else { continue }
            result.append(value)
            if result.count == 100 { break }
        }
        return result
    }
}
