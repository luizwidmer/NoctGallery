import Foundation

struct PhotoAssetRecord: Identifiable, Hashable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int

    var id: String { localIdentifier }

    var dimensionsLabel: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var dateLabel: String {
        guard let creationDate else { return "Date unavailable" }
        return creationDate.formatted(date: .abbreviated, time: .shortened)
    }
}

enum GalleryOutputFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case heic
    case jpeg
    case png

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heic: "HEIC"
        case .jpeg: "JPEG"
        case .png: "PNG"
        }
    }
}

struct SanitizedImage: Sendable {
    let data: Data
    let sourceByteCount: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let outputUTType: String
    let fileExtension: String
    let sha256: String
    let removedMetadataKeys: [String]
}

struct SyntheticMetadataProfile: Identifiable, Hashable, Sendable {
    let id: UUID
    let make: String
    let model: String
    let software: String
    let capturedAt: Date
    let latitude: Double
    let longitude: Double
}

struct SharePayload: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let syntheticProfile: SyntheticMetadataProfile?
}
