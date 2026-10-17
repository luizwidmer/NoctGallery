import SwiftUI

/// Button and stepper alternatives to precision dragging for VoiceOver,
/// Switch Control, keyboard users and anyone who prefers small adjustments.
struct GalleryRectangleAdjustmentView: View {
    @Binding var rect: CGRect
    var aspect: Double?
    var title = "Area"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move \(title.lowercased())").font(.subheadline)
            ViewThatFits(in: .horizontal) {
                directions
                VStack { directions }
            }
            Stepper("Width: \(Int((rect.width * 100).rounded()))%", onIncrement: { resize(dx: 0.01, dy: 0) }, onDecrement: { resize(dx: -0.01, dy: 0) })
                .accessibilityLabel("\(title) width").accessibilityValue("\(Int(rect.width * 100)) percent")
            Stepper("Height: \(Int((rect.height * 100).rounded()))%", onIncrement: { resize(dx: 0, dy: 0.01) }, onDecrement: { resize(dx: 0, dy: -0.01) })
                .accessibilityLabel("\(title) height").accessibilityValue("\(Int(rect.height * 100)) percent")
        }
    }
    private var directions: some View {
        HStack(spacing: 12) {
            direction("Move left", "arrow.left", -0.01, 0)
            direction("Move right", "arrow.right", 0.01, 0)
            direction("Move up", "arrow.up", 0, -0.01)
            direction("Move down", "arrow.down", 0, 0.01)
        }
    }
    private func direction(_ label: String, _ image: String, _ x: Double, _ y: Double) -> some View {
        Button { rect = GalleryRectangleEditing.move(rect, dx: x, dy: y) } label: {
            Image(systemName: image).frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel(label)
    }
    private func resize(dx: Double, dy: Double) {
        rect = GalleryRectangleEditing.resize(rect, handle: .bottomRight, dx: dx, dy: dy, aspect: aspect)
    }
}
