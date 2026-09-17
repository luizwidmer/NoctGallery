import Foundation

enum GalleryMediaKind: String, Codable, CaseIterable, Sendable {
    case photo, video
    var title: String { self == .photo ? "Photo" : "Video" }
}

enum GallerySource: String, Codable, Sendable { case photos, privateLibrary }

struct PhotoAssetRecord: Identifiable, Hashable, Codable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    var kind: GalleryMediaKind = .photo
    var duration: Double = 0
    var source: GallerySource = .photos
    var decoyProfile: SyntheticMetadataProfile? = nil

    var id: String { localIdentifier }

    var dimensionsLabel: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var durationLabel: String {
        let seconds = duration.isFinite ? max(0, Int(duration)) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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

struct SharePayload: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let syntheticProfile: SyntheticMetadataProfile?
}
