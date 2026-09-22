import SwiftUI

struct SharePrivacyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PrivacyCard(
                        icon: "1.circle.fill",
                        title: "Read when needed",
                        detail: "Browsing uses thumbnails. Originals load only when you open or process media."
                    )
                    PrivacyCard(
                        icon: "2.circle.fill",
                        title: "Check the media",
                        detail: "Size and format checks limit processing and reject damaged files."
                    )
                    PrivacyCard(
                        icon: "3.circle.fill",
                        title: "Create a clean copy",
                        detail: "Re-encode photos and videos without their source metadata."
                    )
                    PrivacyCard(
                        icon: "4.circle.fill",
                        title: "Remove temporary files",
                        detail: "Protected share files are removed after sharing, cancellation or next launch."
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Decoy metadata is not anonymity", systemImage: "exclamationmark.shield")
                            .font(.headline)
                        Text("Decoy metadata changes file details. Visible content, sharing accounts and network records can still identify you.")
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
