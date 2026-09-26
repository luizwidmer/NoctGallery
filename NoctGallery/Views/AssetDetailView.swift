@preconcurrency import AVFoundation
import AVKit
import SwiftUI

struct AssetDetailView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let asset: PhotoAssetRecord
    @State private var showsMetadata = false
    @State private var editingPrivate = false
    @State private var confirmDelete = false
    @State private var copiedToPrivate = false
    @State private var savedMoveID: String?

    private var configuration: ImageSanitizer.Configuration {
        GalleryPreferences.configuration(format: model.shareOutputFormat, maximumDimension: model.shareMaximumDimension,
            quality: model.shareLossyQuality)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Group {
                    if asset.kind == .video { GalleryVideoPlayer(asset: asset) }
                    else { PhotoThumbnailView(asset: asset, targetSize: CGSize(width: 2_000, height: 2_000), contentMode: .fit) }
                }
                .aspectRatio(previewAspectRatio, contentMode: .fit).frame(maxHeight: 560)
                .background(.black.opacity(0.86)).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Label(asset.source == .photos ? "In Photos" : "In your private gallery",
                          systemImage: asset.source == .photos ? "photo.stack" : "lock.shield")
                        .font(.headline)
                    LabeledContent(asset.source == .privateLibrary && asset.decoyProfile == nil ? "Added" : "Captured", value: asset.dateLabel)
                    LabeledContent("Dimensions", value: asset.dimensionsLabel)
                    if asset.kind == .video { LabeledContent("Duration", value: asset.durationLabel) }
                    if let profile = asset.decoyProfile {
                        LabeledContent("Metadata profile", value: profile.displayName)
                        LabeledContent("Location", value: profile.location?.name ?? "No GPS")
                    }
                    LabeledContent("Share format", value: asset.kind == .video ? "H.264 video · MOV" : (GalleryOutputFormat(rawValue: model.shareOutputFormat) ?? .heic).title)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 12) {
                    Button {
                        Task { await model.prepareShare(asset: asset, configuration: configuration, syntheticMetadata: asset.decoyProfile) }
                    } label: {
                        Label(asset.decoyProfile == nil ? "Clean & Share" : "Share with Saved Metadata", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)

                    Button {
                        editingPrivate = false
                        showsMetadata = true
                    } label: { Label("Edit Share Metadata", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("media.editMetadata")

                    if asset.source == .photos {
                        Button {
                            Task {
                                if let result = await model.moveToPrivate(asset: asset, savedCopyID: savedMoveID) {
                                    savedMoveID = result.saved.id
                                    if result.originalRemoved { dismiss() }
                                }
                            }
                        } label: {
                            Label(savedMoveID == nil ? "Move to Private Gallery" : "Remove Photos Original",
                                  systemImage: "arrow.right.square").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("media.moveToPrivate")
                        Text("Move keeps original quality and metadata. Approve removal from Photos, then empty Recently Deleted. Deletion also syncs through iCloud Photos.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            Task { copiedToPrivate = await model.saveToPrivate(asset: asset, profile: nil) }
                        } label: { Label(copiedToPrivate ? "Saved to Private Gallery" : "Copy to Private Gallery", systemImage: copiedToPrivate ? "checkmark.circle" : "lock.rectangle.stack").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(copiedToPrivate || savedMoveID != nil)
                        Text("Copy saves a cleaned version and keeps the Photos original.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Menu {
                            Button("Edit Saved Metadata", systemImage: "pencil") { editingPrivate = true; showsMetadata = true }
                            Button("Share Without Metadata", systemImage: "shield.checkered") {
                                Task { await model.prepareShare(asset: asset, configuration: configuration, syntheticMetadata: nil) }
                            }
                            Button("Delete Private Item", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: { Label("More Options", systemImage: "ellipsis.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    }
                }.disabled(model.isProcessing || model.isResetting)

                if model.exportingAssetID == asset.id {
                    ProgressView(model.processingMessage ?? "Processing…").padding(.vertical, 8)
                }
                Text(asset.kind == .video
                     ? "Video shares: up to 1080p at 30 fps, without source metadata."
                     : "Sharing creates a temporary copy. The source stays unchanged.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(16).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }
        .navigationTitle(asset.kind.title).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsMetadata) {
            MetadataEditorView(profile: asset.decoyProfile ?? MetadataForge.randomProfile(), mediaKind: asset.kind,
                               actionTitle: editingPrivate ? "Save Changes" : "Share Copy") { profile in
                Task {
                    if editingPrivate {
                        await model.saveToPrivate(asset: asset, profile: profile, replace: true)
                        if !model.privateAssets.contains(where: { $0.id == asset.id }) { dismiss() }
                    } else {
                        // Allow the editor to dismiss before presenting the share sheet.
                        try? await Task.sleep(for: .milliseconds(350))
                        await model.prepareShare(asset: asset, configuration: configuration, syntheticMetadata: profile)
                    }
                }
            }
        }
        .confirmationDialog("Delete this private \(asset.kind.rawValue)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                Task { await model.deletePrivate(asset); if !model.privateAssets.contains(where: { $0.id == asset.id }) { dismiss() } }
            }
        } message: { Text("This deletes the private copy from Noct Gallery. It cannot be undone.") }
    }

    private var previewAspectRatio: CGFloat {
        guard asset.pixelHeight > 0 else { return 1 }
        return min(max(CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight), 0.72), 1.78)
    }
}

private struct GalleryVideoPlayer: View {
    @EnvironmentObject private var model: GalleryViewModel
    let asset: PhotoAssetRecord
    @State private var player: AVPlayer?
    @State private var lease: URL?
    @State private var error: String?

    var body: some View {
        ZStack {
            if let player { VideoPlayer(player: player) }
            else if let error { Text(error).font(.callout).foregroundStyle(.white).padding() }
            else { ProgressView("Loading video…").tint(.white).foregroundStyle(.white) }
        }
        .task(id: asset.id) {
            do {
                let (loaded, url) = try await model.player(for: asset)
                if Task.isCancelled {
                    if let url { try? await model.workStore.remove(url) }
                    return
                }
                player = loaded
                lease = url
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            if let lease { Task { try? await model.workStore.remove(lease) } }
            lease = nil
        }
    }
}
