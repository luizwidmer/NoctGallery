import CoreGraphics
import Foundation

enum GalleryCropHandle: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

enum GalleryRectangleEditing {
    static func move(_ rect: CGRect, dx: Double, dy: Double) -> CGRect {
        CGRect(x: min(1 - rect.width, max(0, rect.minX + dx)),
               y: min(1 - rect.height, max(0, rect.minY + dy)), width: rect.width, height: rect.height)
    }

    static func resize(_ rect: CGRect, handle: GalleryCropHandle, dx: Double, dy: Double, aspect: Double? = nil) -> CGRect {
        let left = handle == .topLeft || handle == .bottomLeft
        let top = handle == .topLeft || handle == .topRight
        let anchor = CGPoint(x: left ? rect.maxX : rect.minX, y: top ? rect.maxY : rect.minY)
        let availableW = left ? anchor.x : 1 - anchor.x, availableH = top ? anchor.y : 1 - anchor.y
        var w = min(availableW, max(0.02, rect.width + (left ? -dx : dx)))
        var h = min(availableH, max(0.02, rect.height + (top ? -dy : dy)))
        if let aspect, aspect.isFinite, aspect > 0 {
            w = abs(dx) >= abs(dy) ? w : h * aspect
            w = min(availableW, availableH * aspect, max(0.02, 0.02 * aspect, w))
            h = w / aspect
        }
        return CGRect(x: left ? anchor.x - w : anchor.x, y: top ? anchor.y - h : anchor.y, width: w, height: h)
    }

    static func centered(aspect: Double, imageAspect: Double) -> CGRect {
        guard aspect.isFinite, imageAspect.isFinite, aspect > 0, imageAspect > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let normalized = aspect / imageAspect
        let w = min(1, normalized), h = min(1, 1 / normalized)
        return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }
}
