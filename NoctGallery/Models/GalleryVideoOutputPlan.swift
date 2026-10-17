import CoreGraphics
import Foundation

struct GalleryVideoOutputPlan: Sendable {
    let width: Int, height: Int
    let frameRate: Double
    let bitRate: Int
    static func make(size: CGSize, sourceFrameRate: Double, edits: GalleryShareEdits) throws -> Self {
        _ = try edits.validated()
        guard size.width.isFinite, size.height.isFinite, size.width >= 2, size.height >= 2,
              max(size.width, size.height) <= 16_384, sourceFrameRate.isFinite else { throw VideoSanitizer.VideoError.unsupported }
        let edge = Double(edits.videoMaximumEdge)
        let scale = min(1, edge / max(size.width, size.height), edge * 9 / 16 / min(size.width, size.height))
        let width = max(2, Int(size.width * scale) / 2 * 2), height = max(2, Int(size.height * scale) / 2 * 2)
        let fps = min(Double(edits.videoMaximumFrameRate), sourceFrameRate > 0 ? sourceFrameRate : 30)
        guard fps >= 1 / 600 else { throw VideoSanitizer.VideoError.unsupported }
        let pixels = width * height
        let base = pixels > 2_073_600 ? 24_000_000 : pixels > 921_600 ? 8_000_000 : pixels > 518_400 ? 4_000_000 : 2_000_000
        return Self(width: width, height: height, frameRate: fps, bitRate: Int(Double(base) * min(1.5, max(1, fps / 30))))
    }
    func estimatedBytes(duration: Double) -> Int64 {
        guard duration.isFinite, duration >= 0, duration <= 600 else { return 0 }
        return Int64(ceil(Double(bitRate + 128_000) * duration / 8))
    }
}
