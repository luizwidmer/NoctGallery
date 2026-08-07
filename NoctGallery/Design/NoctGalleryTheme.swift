import SwiftUI

enum NoctGalleryTheme {
    static let warmIvory = Color(red: 250 / 255, green: 243 / 255, blue: 234 / 255)
    static let paleSand = Color(red: 235 / 255, green: 199 / 255, blue: 175 / 255)
    static let mutedCoral = Color(red: 201 / 255, green: 106 / 255, blue: 97 / 255)
    static let deepWine = Color(red: 146 / 255, green: 45 / 255, blue: 53 / 255)
    static let plumBlack = Color(red: 27 / 255, green: 18 / 255, blue: 23 / 255)
    static let success = Color(red: 121 / 255, green: 198 / 255, blue: 163 / 255)
    static let accent = mutedCoral

    static let gradient = LinearGradient(
        colors: [deepWine, mutedCoral, paleSand],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func background(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [Color(red: 18 / 255, green: 11 / 255, blue: 15 / 255), plumBlack],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color(red: 250 / 255, green: 246 / 255, blue: 242 / 255), Color(red: 247 / 255, green: 238 / 255, blue: 233 / 255)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 42 / 255, green: 27 / 255, blue: 33 / 255)
            : Color(red: 1, green: 253 / 255, blue: 251 / 255)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 86 / 255, green: 49 / 255, blue: 58 / 255)
            : Color(red: 217 / 255, green: 198 / 255, blue: 193 / 255)
    }
}
struct NoctGalleryMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )

            ZStack {
                RoundedRectangle(cornerRadius: side * 0.245, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NoctGalleryTheme.plumBlack, Color(red: 18 / 255, green: 11 / 255, blue: 15 / 255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                card(
                    side: side,
                    width: 0.527,
                    height: 0.488,
                    x: 0.209,
                    y: 0.246,
                    fill: NoctGalleryTheme.plumBlack,
                    stroke: NoctGalleryTheme.paleSand
                )

                card(
                    side: side,
                    width: 0.523,
                    height: 0.488,
                    x: 0.268,
                    y: 0.188,
                    fill: Color(red: 42 / 255, green: 27 / 255, blue: 33 / 255),
                    stroke: NoctGalleryTheme.warmIvory
                )

                Circle()
                    .fill(NoctGalleryTheme.paleSand)
                    .frame(width: side * 0.105, height: side * 0.105)
                    .position(point(x: 0.635, y: 0.332, side: side, origin: origin))

                landscapePath(side: side, origin: origin)
                    .fill(
                        LinearGradient(
                            colors: [NoctGalleryTheme.deepWine, NoctGalleryTheme.mutedCoral],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                sparklePath(side: side, origin: origin)
                    .fill(NoctGalleryTheme.warmIvory)
                Circle()
                    .fill(NoctGalleryTheme.mutedCoral)
                    .frame(width: side * 0.033, height: side * 0.033)
                    .position(point(x: 0.768, y: 0.205, side: side, origin: origin))
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }

    private func card(
        side: CGFloat,
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        fill: Color,
        stroke: Color
    ) -> some View {
        RoundedRectangle(cornerRadius: side * 0.082, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.082, style: .continuous)
                    .stroke(stroke, lineWidth: max(1, side * 0.027))
            }
            .frame(width: side * width, height: side * height)
            .position(x: side * (x + width / 2), y: side * (y + height / 2))
    }

    private func landscapePath(side: CGFloat, origin: CGPoint) -> Path {
        Path { path in
            path.move(to: point(x: 0.295, y: 0.611, side: side, origin: origin))
            path.addLine(to: point(x: 0.428, y: 0.463, side: side, origin: origin))
            path.addLine(to: point(x: 0.523, y: 0.561, side: side, origin: origin))
            path.addLine(to: point(x: 0.592, y: 0.494, side: side, origin: origin))
            path.addLine(to: point(x: 0.764, y: 0.658, side: side, origin: origin))
            path.addLine(to: point(x: 0.764, y: 0.648, side: side, origin: origin))
            path.addQuadCurve(
                to: point(x: 0.711, y: 0.701, side: side, origin: origin),
                control: point(x: 0.764, y: 0.684, side: side, origin: origin)
            )
            path.addLine(to: point(x: 0.320, y: 0.701, side: side, origin: origin))
            path.addQuadCurve(
                to: point(x: 0.268, y: 0.648, side: side, origin: origin),
                control: point(x: 0.268, y: 0.684, side: side, origin: origin)
            )
            path.closeSubpath()
        }
    }

    private func sparklePath(side: CGFloat, origin: CGPoint) -> Path {
        Path { path in
            let points: [(CGFloat, CGFloat)] = [
                (0.768, 0.145), (0.785, 0.188), (0.828, 0.205), (0.785, 0.223),
                (0.768, 0.266), (0.750, 0.223), (0.707, 0.205), (0.750, 0.188)
            ]
            guard let first = points.first else { return }
            path.move(to: point(x: first.0, y: first.1, side: side, origin: origin))
            for entry in points.dropFirst() {
                path.addLine(to: point(x: entry.0, y: entry.1, side: side, origin: origin))
            }
            path.closeSubpath()
        }
    }

    private func point(x: CGFloat, y: CGFloat, side: CGFloat, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + side * x, y: origin.y + side * y)
    }
}
