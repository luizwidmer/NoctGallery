@preconcurrency import Photos
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @State private var searchText = ""

    private var filteredAssets: [PhotoAssetRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return model.assets
        }
        return model.assets.filter {
            $0.dateLabel.localizedCaseInsensitiveContains(searchText)
                || $0.dimensionsLabel.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView("Reading photo library…")
                } else if filteredAssets.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Photos Available" : "No Matches",
                        systemImage: searchText.isEmpty ? "photo.stack" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Photos allowed through PhotoKit will appear here." : "Try a date or image dimension.")
                    )
                } else {
                    ScrollView {
                        if model.authorizationStatus == .limited {
                            LimitedAccessBanner()
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 112, maximum: 220), spacing: 3)],
                            spacing: 3
                        ) {
                            ForEach(filteredAssets) { asset in
                                NavigationLink(value: asset) {
                                    PhotoThumbnailView(asset: asset)
                                        .aspectRatio(1, contentMode: .fit)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Photo from \(asset.dateLabel)")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 20)
                    }
                    .refreshable { model.reload() }
                }
            }
            .navigationTitle("Gallery")
            .searchable(text: $searchText, prompt: "Search dates or dimensions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") { model.reload() }
                        .labelStyle(.iconOnly)
                }
            }
            .navigationDestination(for: PhotoAssetRecord.self) { asset in
                AssetDetailView(asset: asset)
            }
        }
    }
}
struct PhotoThumbnailView: View {
    @EnvironmentObject private var model: GalleryViewModel
    let asset: PhotoAssetRecord
    var targetSize = CGSize(width: 500, height: 500)
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .task(id: asset.id) {
            image = await model.thumbnail(for: asset, targetSize: targetSize)
        }
    }
}

private struct LimitedAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.badge.checkmark")
                .foregroundStyle(NoctGalleryTheme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Limited Photo Access").font(.subheadline.weight(.semibold))
                Text("Only the photos selected in iOS Settings are visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
