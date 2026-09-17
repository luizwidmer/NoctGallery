@preconcurrency import Photos
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var lock: GalleryLockController
    @EnvironmentObject private var model: GalleryViewModel
    var source: GallerySource = .photos
    @State private var searchText = ""
    @State private var filter = "all"
    @State private var showCamera = false

    private var filteredAssets: [PhotoAssetRecord] {
        let assets = source == .photos ? model.assets : model.privateAssets
        return assets.filter {
            (filter == "all" || $0.kind.rawValue == filter) &&
            (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
             || $0.dateLabel.localizedCaseInsensitiveContains(searchText)
             || $0.dimensionsLabel.localizedCaseInsensitiveContains(searchText)
             || $0.kind.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Media", selection: $filter) {
                    Text("All").tag("all")
                    Text("Photos").tag("photo")
                    Text("Videos").tag("video")
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 10)
                if model.isLoading { Spacer(); ProgressView("Reading library…"); Spacer() }
                else if filteredAssets.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? (source == .privateLibrary ? "Your Private Gallery" : "No Media Available") : "No Matches",
                              systemImage: source == .privateLibrary ? "lock.rectangle.stack" : "photo.stack")
                    } description: {
                        Text(source == .privateLibrary
                             ? "Take a private photo or video, or copy selected media from the Photos tab."
                             : "Photos and videos you allow access to appear here.")
                    } actions: {
                        if source == .privateLibrary {
                            Button("Open Private Camera", systemImage: "camera") { showCamera = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ScrollView {
                        if source == .photos && model.authorizationStatus == .limited {
                            Label("Showing your selected photos and videos", systemImage: "photo.badge.checkmark")
                                .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 220), spacing: 8)], spacing: 8) {
                            ForEach(filteredAssets) { asset in
                                NavigationLink(value: asset) {
                                    PhotoThumbnailView(asset: asset)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay(alignment: .bottomTrailing) {
                                            if asset.kind == .video {
                                                Label(asset.durationLabel, systemImage: "video.fill")
                                                    .font(.caption2.monospacedDigit()).foregroundStyle(.white)
                                                    .padding(6).background(.black.opacity(0.65), in: Capsule()).padding(6)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(asset.kind.title) from \(asset.dateLabel)")
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 20)
                    }
                    .refreshable { if source == .photos { model.reload() } }
                }
            }
            .navigationTitle(source == .photos ? "Photos" : "Private")
            .searchable(text: $searchText, prompt: "Dates, dimensions or media type")
            .navigationDestination(for: PhotoAssetRecord.self) { AssetDetailView(asset: $0) }
            .toolbar {
                if source == .privateLibrary {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Camera", systemImage: "camera") { showCamera = true }.accessibilityIdentifier("private.camera")
                    }
                    if lock.mode != .off {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Lock", systemImage: "lock") { Task { await model.lockPrivate() } }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) { PrivateCameraView() }
        }
    }
}

struct PrivateGalleryView: View {
    @EnvironmentObject private var model: GalleryViewModel
    var body: some View {
        Group {
            if model.privateUnlocked { GalleryView(source: .privateLibrary).id(model.privateGeneration) }
            else {
                NavigationStack {
                    ContentUnavailableView {
                        Label("Private Gallery", systemImage: "lock.rectangle.stack")
                    } description: {
                        Text("An encrypted space for your photos and videos. Captures stay inside Noct Gallery and are excluded from backups.")
                    } actions: {
                        Button { Task { await model.unlockPrivate() } } label: {
                            if model.isUnlocking { ProgressView() }
                            else { Label("Unlock Private", systemImage: "lock.open") }
                        }
                        .buttonStyle(.borderedProminent).disabled(model.isUnlocking || model.isResetting)
                        .accessibilityIdentifier("private.unlock")
                    }
                    .navigationTitle("Private")
                }
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
    @State private var finished = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else if finished { Image(systemName: "photo").foregroundStyle(.secondary) }
                else { ProgressView().controlSize(.small) }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .task(id: asset.id) { image = await model.thumbnail(for: asset, targetSize: targetSize); finished = true }
    }
}
