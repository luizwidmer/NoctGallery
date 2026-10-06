import CoreGraphics
import CoreVideo
import Foundation

/// Coordinates are normalized to the upright displayed image, with a top-left origin.
struct GalleryRedaction: Equatable, Identifiable, Sendable {
    let id: UUID
    var rect: CGRect
    var referenceTime: Double
    var keyframes: [GalleryCoverKeyframe]
    init(id: UUID = UUID(), rect: CGRect, referenceTime: Double = 0, keyframes: [GalleryCoverKeyframe] = []) {
        self.id = id; self.rect = rect; self.referenceTime = referenceTime; self.keyframes = keyframes
    }

    var isValid: Bool {
        Self.valid(rect) && referenceTime.isFinite && (0...600).contains(referenceTime)
            && keyframes.count <= 6_001 && keyframes.allSatisfy({ $0.time.isFinite && (0...600).contains($0.time) && Self.valid($0.rect) })
            && zip(keyframes, keyframes.dropFirst()).allSatisfy { $0.0.time < $0.1.time }
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.minX >= 0 && rect.minY >= 0 && rect.width > 0 && rect.height > 0
            && rect.maxX <= 1.000001 && rect.maxY <= 1.000001
    }

    func rect(at time: Double) -> CGRect {
        guard let first = keyframes.first, let last = keyframes.last else { return rect }
        if time <= first.time { return first.rect }
        if time >= last.time { return last.rect }
        var low = 0, high = keyframes.count - 1
        while high - low > 1 { let mid = (low + high) / 2; if keyframes[mid].time <= time { low = mid } else { high = mid } }
        let a = keyframes[low], b = keyframes[high], fraction = (time - a.time) / (b.time - a.time)
        return CGRect(x: a.rect.minX + (b.rect.minX - a.rect.minX) * fraction,
            y: a.rect.minY + (b.rect.minY - a.rect.minY) * fraction,
            width: a.rect.width + (b.rect.width - a.rect.width) * fraction,
            height: a.rect.height + (b.rect.height - a.rect.height) * fraction)
    }

    mutating func setRect(_ value: CGRect, at time: Double) {
        if keyframes.isEmpty { rect = value; referenceTime = time; return }
        keyframes.removeAll { abs($0.time - time) < 0.02 }
        keyframes.append(.init(time: time, rect: value)); keyframes.sort { $0.time < $1.time }
    }

    func pixelRect(width: Int, height: Int, time: Double = 0) -> CGRect {
        let rect = rect(at: time)
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
    var photoEdits: GalleryPhotoEdits?
    var videoMaximumEdge = 1_920
    var silencedRanges: [GalleryAudioRange] = []
    var hasSpatialOrTimedEdits: Bool {
        !redactions.isEmpty || trimStart != 0 || trimEnd != nil || photoEdits != nil || !silencedRanges.isEmpty
    }

    func validated(duration: Double? = nil) throws -> Self {
        guard redactions.count <= 100, redactions.allSatisfy(\.isValid), trimStart.isFinite, trimStart >= 0,
              [960, 1_280, 1_920].contains(videoMaximumEdge), silencedRanges.count <= 100,
              silencedRanges.allSatisfy(\.isValid),
              trimEnd.map({ $0.isFinite && $0 > trimStart }) != false else { throw ImageSanitizer.SanitizationError.invalidConfiguration }
        if let photoEdits { _ = try photoEdits.validated() }
        if let duration {
            guard silencedRanges.allSatisfy({ $0.end <= duration }) else { throw ImageSanitizer.SanitizationError.invalidConfiguration }
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

    func redact(_ buffer: CVPixelBuffer, at time: Double = 0) throws {
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
            let rect = mask.pixelRect(width: width, height: height, time: time)
            for y in Int(rect.minY)..<Int(rect.maxY) {
                let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    row[x * 4] = 0; row[x * 4 + 1] = 0; row[x * 4 + 2] = 0; row[x * 4 + 3] = 255
                }
            }
        }
    }
}
