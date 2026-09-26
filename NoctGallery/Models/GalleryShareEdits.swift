import CoreGraphics
import CoreVideo
import Foundation

/// Coordinates are normalized to the upright displayed image, with a top-left origin.
struct GalleryRedaction: Equatable, Identifiable, Sendable {
    let id: UUID
    let rect: CGRect
    init(id: UUID = UUID(), rect: CGRect) { self.id = id; self.rect = rect }

    var isValid: Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.minX >= 0 && rect.minY >= 0 && rect.width > 0 && rect.height > 0
            && rect.maxX <= 1.000001 && rect.maxY <= 1.000001
    }

    func pixelRect(width: Int, height: Int) -> CGRect {
        // Expand to whole pixels, so a fractional edge never exposes source pixels.
        let x = max(0, floor(rect.minX * Double(width)))
        let y = max(0, floor(rect.minY * Double(height)))
        return CGRect(x: x, y: y, width: min(Double(width), ceil(rect.maxX * Double(width))) - x,
                      height: min(Double(height), ceil(rect.maxY * Double(height))) - y)
    }
}

struct GalleryShareEdits: Equatable, Sendable {
    var redactions: [GalleryRedaction] = []
    var trimStart: Double = 0
    var trimEnd: Double?
    var removeAudio = false

    func validated(duration: Double? = nil) throws -> Self {
        guard redactions.count <= 100, redactions.allSatisfy(\.isValid), trimStart.isFinite, trimStart >= 0,
              trimEnd.map({ $0.isFinite && $0 > trimStart }) != false else { throw ImageSanitizer.SanitizationError.invalidConfiguration }
        if let duration {
            guard duration.isFinite, duration > 0, trimStart < duration,
                  (trimEnd ?? duration) <= duration + 0.001,
                  (trimEnd ?? duration) - trimStart >= 0.1 else { throw ImageSanitizer.SanitizationError.invalidConfiguration }
        }
        return self
    }

    func redact(_ image: CGImage) throws -> CGImage {
        guard !redactions.isEmpty else { return image }
        _ = try validated()
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw ImageSanitizer.SanitizationError.colorNormalizationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setShouldAntialias(false)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for mask in redactions {
            let rect = mask.pixelRect(width: image.width, height: image.height)
            context.fill(CGRect(x: rect.minX, y: Double(image.height) - rect.maxY, width: rect.width, height: rect.height))
        }
        guard let result = context.makeImage() else { throw ImageSanitizer.SanitizationError.colorNormalizationFailed }
        return result
    }

    func redact(_ buffer: CVPixelBuffer) throws {
        guard !redactions.isEmpty else { return }
        _ = try validated()
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw VideoSanitizer.VideoError.conversionFailed }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, width <= 8_192, height > 0, height <= 8_192, stride >= width * 4,
              let base = CVPixelBufferGetBaseAddress(buffer) else { throw VideoSanitizer.VideoError.conversionFailed }
        for mask in redactions {
            let rect = mask.pixelRect(width: width, height: height)
            for y in Int(rect.minY)..<Int(rect.maxY) {
                let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    row[x * 4] = 0; row[x * 4 + 1] = 0; row[x * 4 + 2] = 0; row[x * 4 + 3] = 255
                }
            }
        }
    }
}
