@preconcurrency import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum GalleryFileImport {
    static func copy(_ source: URL, to destination: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        guard source.isFileURL, attrs[.type] as? FileAttributeType == .typeRegular,
              let bytes = (attrs[.size] as? NSNumber)?.intValue, bytes > 0, bytes <= PrivateMediaStore.maximumBytes else { throw PrivateMediaStore.StoreError.mediaTooLarge }
        try MediaFileProtection.createFile(destination)
        do {
            let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
            defer { try? input.close(); try? output.close() }
            var remaining = bytes
            while remaining > 0 {
                try Task.checkCancellation()
                var data = try input.read(upToCount: min(PrivateMediaStore.chunkSize, remaining)) ?? Data()
                defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
                guard !data.isEmpty else { throw PrivateMediaStore.StoreError.invalidRecord }
                try output.write(contentsOf: data); remaining -= data.count
            }
            guard try input.read(upToCount: 1)?.isEmpty != false else { throw PrivateMediaStore.StoreError.invalidRecord }
            try output.synchronize()
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }

    static func inspect(_ source: URL, declaredType: String?) async throws -> PreparedGalleryMedia {
        try Task.checkCancellation()
        if let image = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let identifier = CGImageSourceGetType(image) as String?,
           let suffix = GalleryOriginalFormats.suffix(for: identifier),
           let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any],
           let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
           let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue {
            guard width > 0, height > 0, width <= 120_000_000 / height,
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600, kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary), let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
                throw ImageSanitizer.SanitizationError.decodeFailed
            }
            let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
            let swap = (5...8).contains(orientation)
            let resource = GalleryOriginalResource(url: source, fileExtension: suffix, role: .photo, typeIdentifier: identifier)
            return PreparedGalleryMedia(url: source, fileExtension: suffix, kind: .photo, width: swap ? height : width, height: swap ? width : height,
                duration: 0, thumbnail: data, resources: [resource], originalKind: GalleryOriginalFormats.isRAW(identifier) ? .rawPhoto : nil)
        }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 600, tracks.count == 1, let track = tracks.first else { throw VideoSanitizer.VideoError.unsupported }
        let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, size.width * size.height <= 9_000_000,
              [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite) else { throw VideoSanitizer.VideoError.unsupported }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        guard rect.width.isFinite, rect.height.isFinite, rect.width >= 1, rect.height >= 1, max(rect.width, rect.height) <= 16_384 else { throw VideoSanitizer.VideoError.unsupported }
        let type = declaredType.flatMap { GalleryOriginalFormats.suffix(for: $0) != nil && UTType($0)?.conforms(to: .movie) == true ? $0 : nil } ?? UTType.quickTimeMovie.identifier
        let suffix = GalleryOriginalFormats.suffix(for: type) ?? "mov"
        return PreparedGalleryMedia(url: source, fileExtension: suffix, kind: .video, width: Int(rect.width), height: Int(rect.height),
            duration: duration.seconds, thumbnail: try await VideoSanitizer.thumbnail(url: source),
            resources: [.init(url: source, fileExtension: suffix, role: .video, typeIdentifier: type)])
    }
}
