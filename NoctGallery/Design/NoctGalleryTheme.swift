import SwiftUI

enum NoctGalleryTheme {
    static let violet = Color(red: 0.486, green: 0.424, blue: 1.0)
    static let blue = Color(red: 0.373, green: 0.659, blue: 1.0)
    static let teal = Color(red: 0.282, green: 0.843, blue: 0.773)

    static let gradient = LinearGradient(
        colors: [violet, blue, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func background(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [Color(red: 0.027, green: 0.035, blue: 0.075), Color(red: 0.035, green: 0.090, blue: 0.110)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color(red: 0.955, green: 0.951, blue: 1.0), Color(red: 0.910, green: 0.980, blue: 0.970)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
struct NoctGalleryMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(NoctGalleryTheme.gradient.opacity(0.18))
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(NoctGalleryTheme.gradient)
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NoctGalleryTheme.teal)
                .offset(x: 17, y: -17)
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }
}
