@preconcurrency import CoreImage
import CoreGraphics
import Foundation

/// The editor and both export paths use the same blur. Crop first so clear
/// pixels outside a selected area cannot bleed into its edges.
enum GalleryBlur {
    private static let context: CIContext = {
        #if targetEnvironment(simulator)
        CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
        #else
        CIContext(options: [.cacheIntermediates: false])
        #endif
    }()

    static func region(in image: CGImage, pixels: CGRect) throws -> CGImage {
        try Task.checkCancellation()
        guard image.width <= 8_192, image.height <= 8_192,
              !pixels.isEmpty, let cropped = image.cropping(to: pixels) else {
            throw ImageSanitizer.SanitizationError.invalidConfiguration
        }
        let source = CIImage(cgImage: cropped)
        let radius = max(12, Double(max(cropped.width, cropped.height)) * 0.18)
        let blurred = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: source.extent)
        guard let output = context.createCGImage(blurred, from: source.extent, format: .RGBA8,
                                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw ImageSanitizer.SanitizationError.colorNormalizationFailed
        }
        try Task.checkCancellation()
        return output
    }
}
