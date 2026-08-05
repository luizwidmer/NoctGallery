import SwiftUI

struct SharePrivacyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PrivacyCard(
                        icon: "1.circle.fill",
                        title: "Read on demand",
                        detail: "Noct Gallery requests original bytes only after you tap a share action. Browsing uses PhotoKit thumbnails."
                    )
                    PrivacyCard(
                        icon: "2.circle.fill",
                        title: "Decode within limits",
                        detail: "Encoded size, source pixels, output dimensions, floating-point decoding, and malformed inputs are bounded before export."
                    )
                    PrivacyCard(
                        icon: "3.circle.fill",
                        title: "Rebuild from pixels",
                        detail: "Orientation and color are normalized, then a new HEIC, JPEG, or PNG is encoded without source metadata dictionaries."
                    )
                    PrivacyCard(
                        icon: "4.circle.fill",
                        title: "Erase the handoff",
                        detail: "The share sheet receives a randomized protected file. It is removed after sharing, cancellation, or the next launch."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Decoy metadata is not anonymity", systemImage: "exclamationmark.shield")
                            .font(.headline)
                        Text("It changes selected EXIF, TIFF, and GPS fields on the temporary export. The picture itself, destination account, timing, and network records may still reveal its origin.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Share Privacy")
        }
    }
}
private struct PrivacyCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(NoctGalleryTheme.gradient)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
