import Foundation
import UniformTypeIdentifiers

enum GalleryOriginalKind: String, Codable, Sendable {
    case livePhoto, rawPair, rawPhoto
    var title: String {
        switch self { case .livePhoto: "Live Photo"; case .rawPair: "RAW + Photo"; case .rawPhoto: "RAW Photo" }
    }
}

enum GalleryResourceRole: String, Codable, Sendable {
    case photo, video, pairedVideo, alternatePhoto
    var title: String {
        switch self { case .photo: "Photo"; case .video: "Video"; case .pairedVideo: "Live Photo motion"; case .alternatePhoto: "Alternate photo" }
    }
}

struct GalleryOriginalResource: Sendable {
    let url: URL
    let fileExtension: String
    let role: GalleryResourceRole
    let typeIdentifier: String
}

struct GalleryStoredResource: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let role: GalleryResourceRole
    let fileExtension: String
    let typeIdentifier: String
    let byteCount: Int
    let chunkCount: Int
}

enum GalleryOriginalFormats {
    static let extensions: Set<String> = ["jpg", "heic", "png", "mov", "mp4", "m4v", "dng", "raw", "cr2", "cr3", "nef", "nrw", "arw", "raf", "rw2", "orf", "pef", "srw"]

    static func suffix(for identifier: String) -> String? {
        switch identifier {
        case UTType.jpeg.identifier: return "jpg"
        case UTType.png.identifier: return "png"
        case UTType.heic.identifier, UTType.heif.identifier: return "heic"
        case UTType.quickTimeMovie.identifier: return "mov"
        case UTType.mpeg4Movie.identifier: return "mp4"
        case "com.apple.m4v-video": return "m4v"
        default:
            guard let type = UTType(identifier), type.conforms(to: .rawImage) else { return nil }
            let suffix = type.preferredFilenameExtension?.lowercased() ?? "raw"
            return extensions.contains(suffix) ? suffix : "raw"
        }
    }

    static func isRAW(_ identifier: String) -> Bool { UTType(identifier)?.conforms(to: .rawImage) == true }

    /// Refuse unknown or edited components instead of dropping any source bytes.
    static func classify(_ resources: [(GalleryResourceRole, String)]) throws -> GalleryOriginalKind? {
        guard (1...3).contains(resources.count), resources.allSatisfy({ suffix(for: $0.1) != nil }) else {
            throw PhotoLibraryService.LibraryError.unsupportedOriginal
        }
        let roles = resources.map(\.0)
        guard Set(roles).count == roles.count else { throw PhotoLibraryService.LibraryError.unsupportedOriginal }
        if roles == [.video], UTType(resources[0].1)?.conforms(to: .movie) == true { return nil }
        guard roles.contains(.photo), !roles.contains(.video) else { throw PhotoLibraryService.LibraryError.unsupportedOriginal }
        for (role, type) in resources {
            let valid = role == .pairedVideo ? UTType(type)?.conforms(to: .movie) == true : UTType(type)?.conforms(to: .image) == true
            guard valid else { throw PhotoLibraryService.LibraryError.unsupportedOriginal }
        }
        if roles.contains(.pairedVideo) {
            guard !roles.contains(.alternatePhoto), !resources.contains(where: { isRAW($0.1) }) else { throw PhotoLibraryService.LibraryError.unsupportedOriginal }
            return .livePhoto
        }
        if roles.contains(.alternatePhoto) {
            guard resources.filter({ isRAW($0.1) }).count == 1 else { throw PhotoLibraryService.LibraryError.unsupportedOriginal }
            return .rawPair
        }
        return isRAW(resources[0].1) ? .rawPhoto : nil
    }
}
