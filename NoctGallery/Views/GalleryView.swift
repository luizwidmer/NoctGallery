@preconcurrency import Photos
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var lock: GalleryLockController
    @EnvironmentObject private var model: GalleryViewModel
    var source: GallerySource = .photos
    @State private var searchText = ""
    @State private var filter = "all"
    @State private var showCamera = false
    @State private var collection = "all"
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var showsAlbums = false
    @State private var showsOrganize = false
    @State private var confirmsDelete = false
    @State private var batchBusy = false

    private var selectedAssets: [PhotoAssetRecord] {
        (source == .photos ? model.assets : model.privateAssets).filter { selection.contains($0.id) }
    }

    private var filteredAssets: [PhotoAssetRecord] {
        let assets = source == .photos ? model.assets : model.privateAssets
        return assets.filter { asset in
            (filter == "all" || asset.kind.rawValue == filter) &&
            (collection == "all" || (collection == "favorites" && model.organization.items[asset.id]?.favorite == true)
                || (UUID(uuidString: collection).map { id in model.organization.items[asset.id]?.albumIDs.contains(id) == true } ?? false)) &&
            (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
             || asset.dateLabel.localizedCaseInsensitiveContains(searchText)
             || asset.dimensionsLabel.localizedCaseInsensitiveContains(searchText)
             || asset.mediaTitle.localizedCaseInsensitiveContains(searchText)
             || (source == .privateLibrary && model.organization.searchText(for: asset.id).localizedCaseInsensitiveContains(searchText)))
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
                if source == .privateLibrary {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            collectionButton("All Items", id: "all", icon: "square.grid.2x2")
                            collectionButton("Favorites", id: "favorites", icon: "heart")
                            ForEach(model.organization.albums) { collectionButton($0.name, id: $0.id.uuidString, icon: "folder") }
                        }.padding(.horizontal, 16).padding(.bottom, 10)
                    }
                }
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
                            Label("Selected photos and videos", systemImage: "photo.badge.checkmark")
                                .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 220), spacing: 8)], spacing: 8) {
                            ForEach(filteredAssets) { asset in
                                Group {
                                    if selecting {
                                        Button { toggleSelection(asset.id) } label: { tile(asset) }
                                    } else {
                                        NavigationLink(value: asset) { tile(asset) }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(asset.mediaTitle) from \(asset.dateLabel)")
                                .accessibilityAddTraits(selection.contains(asset.id) ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 20)
                    }
                    .refreshable { if source == .photos { model.reload() } }
                }
            }
            .navigationTitle(source == .photos ? "Photos" : "Private")
            .searchable(text: $searchText, prompt: source == .privateLibrary ? "Dates, albums or tags" : "Dates, dimensions or type")
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .navigationDestination(for: PhotoAssetRecord.self) { AssetDetailView(asset: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") { selecting.toggle(); selection = [] }
                        .disabled(batchBusy)
                }
                if source == .privateLibrary {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Albums", systemImage: "folder") { showsAlbums = true }
                    }
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
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
            .sheet(isPresented: $showsAlbums) { GalleryAlbumsView() }
            .sheet(isPresented: $showsOrganize) { GalleryOrganizeView(ids: selection) }
            .confirmationDialog("Delete \(selection.count) private items?", isPresented: $confirmsDelete) {
                Button("Delete Permanently", role: .destructive) {
                    batchBusy = true
                    Task { await model.deletePrivateItems(selection); selection = []; batchBusy = false }
                }
            } message: { Text("This cannot be undone. Photos originals are not affected.") }
            .onChange(of: model.organization.albums) { _, albums in
                if let id = UUID(uuidString: collection), !albums.contains(where: { $0.id == id }) { collection = "all" }
            }
            .fullScreenCover(isPresented: $showCamera) { PrivateCameraView() }
        }
    }

    private func collectionButton(_ title: String, id: String, icon: String) -> some View {
        Button { collection = id } label: {
            Label(title, systemImage: icon).font(.subheadline.weight(.medium)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(collection == id ? NoctGalleryTheme.accent.opacity(0.18) : Color.secondary.opacity(0.09), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(collection == id ? .isSelected : [])
    }

    private func tile(_ asset: PhotoAssetRecord) -> some View {
        PhotoThumbnailView(asset: asset).aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if model.organization.items[asset.id]?.favorite == true {
                    Image(systemName: "heart.fill").foregroundStyle(.white).padding(6)
                        .background(.black.opacity(0.55), in: Circle()).padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selection.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(.white, NoctGalleryTheme.accent)
                        .padding(6).background(.black.opacity(0.35), in: Circle()).padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.kind == .video || asset.originalKind != nil {
                    Label(asset.kind == .video ? asset.durationLabel : asset.mediaTitle,
                          systemImage: asset.kind == .video ? "video.fill" : "photo.on.rectangle")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white)
                        .padding(6).background(.black.opacity(0.65), in: Capsule()).padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) }
        else if selection.count < 500 { selection.insert(id) }
    }

    private var selectionBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selection.count) selected")
                if selection.count > 20 { Text("Share up to 20 at a time").font(.caption2) }
            }.font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if batchBusy { ProgressView() }
            Button("Share", systemImage: "square.and.arrow.up") { model.beginShare(selectedAssets) }
                .labelStyle(.iconOnly).disabled(selection.count > 20)
            if source == .privateLibrary {
                Menu {
                    Button("Albums & Tags", systemImage: "folder") { showsOrganize = true }
                    Button("Favorite", systemImage: "heart") { Task { await model.organize(selection, edit: .favorite(true)) } }
                    Button("Remove Favorite", systemImage: "heart.slash") { Task { await model.organize(selection, edit: .favorite(false)) } }
                } label: { Label("Organize", systemImage: "folder").labelStyle(.iconOnly) }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true }.labelStyle(.iconOnly)
            } else {
                Button("Copy to Private", systemImage: "lock.rectangle.stack") {
                    batchBusy = true
                    Task { await model.copyPhotosToPrivate(selectedAssets); batchBusy = false }
                }.labelStyle(.iconOnly).disabled(selection.count > 20)
            }
        }
        .disabled(selection.isEmpty || batchBusy || model.isProcessing || model.isOrganizing)
        .padding(16).background(.regularMaterial)
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
                        Text("Encrypted photos and videos, kept on this device and excluded from backups.")
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
