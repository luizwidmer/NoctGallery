import Foundation

enum GallerySort: String, CaseIterable, Identifiable {
    case newest, oldest, recentlyImported, largest, longest
    var id: Self { self }
    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .recentlyImported: "Recently imported"
        case .largest: "Largest first"
        case .longest: "Longest first"
        }
    }
}

enum GalleryFormatFilter: String, CaseIterable, Identifiable {
    case all, live, raw, ordinary
    var id: Self { self }
    var title: String {
        switch self { case .all: "All formats"; case .live: "Live Photos"; case .raw: "RAW"; case .ordinary: "Standard photos & videos" }
    }
    func matches(_ asset: PhotoAssetRecord) -> Bool {
        switch self {
        case .all: true
        case .live: asset.originalKind == .livePhoto
        case .raw: asset.originalKind == .rawPhoto || asset.originalKind == .rawPair
        case .ordinary: asset.originalKind == nil
        }
    }
}

struct GalleryStorageItem: Equatable, Sendable {
    let id: String
    let mediaBytes: Int64
    let storedBytes: Int64
}

struct GalleryDuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let itemIDs: [String]
    let exact: Bool
}

enum GalleryLibraryQuery {
    static func sorted(_ items: [PhotoAssetRecord], by sort: GallerySort, sizes: [String: GalleryStorageItem]) -> [PhotoAssetRecord] {
        items.sorted { a, b in
            switch sort {
            case .newest, .oldest:
                let lhs = a.creationDate ?? .distantPast, rhs = b.creationDate ?? .distantPast
                if lhs != rhs { return sort == .newest ? lhs > rhs : lhs < rhs }
            case .recentlyImported:
                let lhs = a.importedAt ?? a.creationDate ?? .distantPast
                let rhs = b.importedAt ?? b.creationDate ?? .distantPast
                if lhs != rhs { return lhs > rhs }
            case .largest:
                let lhs = sizes[a.id]?.mediaBytes ?? 0, rhs = sizes[b.id]?.mediaBytes ?? 0
                if lhs != rhs { return lhs > rhs }
            case .longest:
                if a.duration != b.duration { return a.duration > b.duration }
            }
            return a.id < b.id
        }
    }
}

struct GallerySharingPreset: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var format: GalleryOutputFormat = .heic
    var maximumDimension = 4_096
    var quality = 0.9
    var videoMaximumEdge = 1_920
    var removeAudio = false
    var metadata: SyntheticMetadataProfile?

    func validated() throws -> Self {
        guard GalleryOrganization.validName(name), [2_048, 4_096, 8_192].contains(maximumDimension),
              quality.isFinite, (0.65...1).contains(quality), [960, 1_280, 1_920].contains(videoMaximumEdge) else {
            throw GallerySettingsError.invalidRecord
        }
        if let metadata { _ = try metadata.validated() }
        return self
    }

    static var builtIns: [Self] {
        [Self(id: UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!, name: "Small copy", format: .jpeg,
              maximumDimension: 2_048, quality: 0.75, videoMaximumEdge: 960),
         Self(id: UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!, name: "Clear document", format: .png,
              maximumDimension: 4_096, quality: 1, removeAudio: true),
         Self(id: UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!, name: "High quality", maximumDimension: 8_192, quality: 1)]
    }
}
