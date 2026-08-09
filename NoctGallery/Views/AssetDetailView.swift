import SwiftUI

struct AssetDetailView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @AppStorage("share.outputFormat") private var outputFormat = GalleryOutputFormat.heic.rawValue
    @AppStorage("share.maximumDimension") private var maximumDimension = 8_192
    @AppStorage("share.lossyQuality") private var lossyQuality = 0.90
    let asset: PhotoAssetRecord
    @State private var decoyProfile: SyntheticMetadataProfile?
    @State private var showsAdvancedSharing = false

    private var configuration: ImageSanitizer.Configuration {
        GalleryPreferences.configuration(
            format: outputFormat,
            maximumDimension: maximumDimension,
            quality: lossyQuality
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PhotoThumbnailView(
                    asset: asset,
                    targetSize: CGSize(width: 2_000, height: 2_000),
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(previewAspectRatio, contentMode: .fit)
                .frame(maxHeight: 560)
                .background(.black.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Label("Original stays in Photos", systemImage: "photo.stack")
                        .font(.headline)
                    LabeledContent("Captured", value: asset.dateLabel)
                    LabeledContent("Dimensions", value: asset.dimensionsLabel)
                    LabeledContent("Shared format", value: (GalleryOutputFormat(rawValue: outputFormat) ?? .heic).title)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 12) {
                    Button {
                        Task {
                            await model.prepareShare(
                                asset: asset,
                                configuration: configuration,
                                syntheticMetadata: nil
                            )
                        }
                    } label: {
                        Label("Sanitize & Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(NoctGalleryTheme.accent)

                    DisclosureGroup("Advanced sharing", isExpanded: $showsAdvancedSharing) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Decoy metadata is optional and can be recognized as synthetic. Normal sanitized sharing is the recommended path.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button {
                                decoyProfile = MetadataForge.randomProfile()
                            } label: {
                                Label("Create Share with Decoy Metadata", systemImage: "theatermasks")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        .padding(.top, 8)
                    }
                }
                .disabled(model.exportingAssetID != nil)

                if model.exportingAssetID == asset.id {
                    ProgressView("Reading and sanitizing original…")
                        .padding(.vertical, 8)
                }

                Text("Noct Gallery requests the original only after you choose a share action. iCloud may download the source at that moment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(16)
        }
        .navigationTitle(asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Photo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $decoyProfile) { profile in
            DecoyMetadataSheet(initialProfile: profile) { chosenProfile in
                decoyProfile = nil
                Task {
                    await model.prepareShare(
                        asset: asset,
                        configuration: configuration,
                        syntheticMetadata: chosenProfile
                    )
                }
            }
        }
    }

    private var previewAspectRatio: CGFloat {
        guard asset.pixelHeight > 0 else { return 1 }
        return min(max(CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight), 0.72), 1.65)
    }
}
private struct DecoyMetadataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile: SyntheticMetadataProfile
    let share: (SyntheticMetadataProfile) -> Void

    init(initialProfile: SyntheticMetadataProfile, share: @escaping (SyntheticMetadataProfile) -> Void) {
        _profile = State(initialValue: initialProfile)
        self.share = share
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Generated profile") {
                    LabeledContent("Camera", value: "\(profile.make) \(profile.model)")
                    LabeledContent("Software", value: profile.software)
                    LabeledContent("Date", value: profile.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Latitude", value: profile.latitude.formatted(.number.precision(.fractionLength(4))))
                    LabeledContent("Longitude", value: profile.longitude.formatted(.number.precision(.fractionLength(4))))
                }
                Section {
                    Button("Generate Another", systemImage: "arrow.triangle.2.circlepath") {
                        profile = MetadataForge.randomProfile()
                    }
                    Button("Create Temporary Share Copy", systemImage: "square.and.arrow.up") {
                        share(profile)
                    }
                    .fontWeight(.semibold)
                }
                Section {
                    Text("Decoy metadata can be detected as synthetic and does not hide visible content, accounts, network records, or timing. It is never written back to Photos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Decoy Metadata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
