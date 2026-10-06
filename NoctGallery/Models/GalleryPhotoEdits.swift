import CoreImage
import CoreGraphics
import Foundation

/// A recipe in the encrypted organization index; original resources remain intact.
struct GalleryPhotoEdits: Codable, Equatable, Sendable {
    var quarterTurns = 0
    var straightenDegrees = 0.0
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var isIdentity: Bool { self == Self() }

    func validated() throws -> Self {
        guard (0...3).contains(quarterTurns), straightenDegrees.isFinite, (-15...15).contains(straightenDegrees),
              GalleryRedaction(rect: crop).isValid, crop.width >= 0.02, crop.height >= 0.02 else {
            throw ImageSanitizer.SanitizationError.invalidConfiguration
        }
        return self
    }

    func apply(to image: CGImage) throws -> CGImage {
        _ = try validated()
        guard !isIdentity else { return image }
        var input = CIImage(cgImage: image)
        let orientations: [Int32] = [1, 6, 3, 8]
        input = input.oriented(forExifOrientation: orientations[quarterTurns])
        input = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        if abs(straightenDegrees) > 0.001 {
            let w = input.extent.width, h = input.extent.height
            let angle = straightenDegrees * .pi / 180
            let transform = CGAffineTransform(translationX: -w / 2, y: -h / 2)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: w / 2, y: h / 2))
            input = input.transformed(by: transform)
            // An inscribed rectangle avoids introducing empty corners after rotation.
            let c = abs(cos(angle)), s = abs(sin(angle))
            let scale = min(w / (w * c + h * s), h / (w * s + h * c))
            input = input.cropped(to: CGRect(x: w * (1 - scale) / 2, y: h * (1 - scale) / 2, width: w * scale, height: h * scale))
        }
        let bounds = input.extent
        let region = CGRect(x: bounds.minX + crop.minX * bounds.width,
            y: bounds.minY + (1 - crop.maxY) * bounds.height, width: crop.width * bounds.width, height: crop.height * bounds.height).integral.intersection(bounds)
        guard region.width >= 1, region.height >= 1,
              let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(input, from: region) else {
            throw ImageSanitizer.SanitizationError.colorNormalizationFailed
        }
        return result
    }
}
