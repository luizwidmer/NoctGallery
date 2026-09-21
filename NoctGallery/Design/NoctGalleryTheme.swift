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
        Image("NoctGalleryBrand")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)
    }
}
