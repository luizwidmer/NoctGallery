import CoreImage
import CoreGraphics
import Foundation

/// A recipe in the encrypted organization index; original resources remain intact.
struct GalleryPhotoEdits: Codable, Equatable, Sendable {
    var quarterTurns = 0
    var straightenDegrees = 0.0
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var isIdentity: Bool { self == Self() }

    init(quarterTurns: Int = 0, straightenDegrees: Double = 0,
         crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
         brightness: Double = 0, contrast: Double = 1, saturation: Double = 1) {
        self.quarterTurns = quarterTurns; self.straightenDegrees = straightenDegrees; self.crop = crop
        self.brightness = brightness; self.contrast = contrast; self.saturation = saturation
    }

    private enum CodingKeys: String, CodingKey { case quarterTurns, straightenDegrees, crop, brightness, contrast, saturation }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quarterTurns = try c.decode(Int.self, forKey: .quarterTurns)
        straightenDegrees = try c.decode(Double.self, forKey: .straightenDegrees)
        crop = try c.decode(CGRect.self, forKey: .crop)
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
    }

    func validated() throws -> Self {
        guard (0...3).contains(quarterTurns), straightenDegrees.isFinite, (-15...15).contains(straightenDegrees),
              GalleryRedaction(rect: crop).isValid, crop.width >= 0.02, crop.height >= 0.02,
              brightness.isFinite, (-0.5...0.5).contains(brightness),
              contrast.isFinite, (0.5...1.5).contains(contrast), saturation.isFinite, (0...2).contains(saturation) else {
            throw ImageSanitizer.SanitizationError.invalidConfiguration
        }
        return self
    }

    func apply(to image: CGImage) throws -> CGImage {
        _ = try validated()
        guard !isIdentity else { return image }
        var input = CIImage(cgImage: image)
        if brightness != 0 || contrast != 1 || saturation != 1 {
            input = input.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: brightness,
                kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation])
        }
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
