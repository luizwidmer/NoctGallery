import AVKit
import ImageIO
import SwiftUI

struct GalleryShareFlowView: View {
    @EnvironmentObject private var model: GalleryViewModel
    let request: GalleryShareRequest
    @State private var edits = GalleryShareEdits()
    @State private var profile: SyntheticMetadataProfile?
    @State private var image: UIImage?
    @State private var suggestions: [GalleryRedaction] = []
    @State private var showsMetadata = false
    @State private var detecting = false
    @State private var detectionTask: Task<[GalleryRedaction], Error>?
    @State private var suggestionStatus: String?
    @State private var frameTime = 0.0
    @State private var frameRevision = 0
    @State private var previewError: String?
    @State private var selectedExport = 0
    @State private var showsActivity = false
    @State private var selectedCover: UUID?
    @State private var tracking = false
    @State private var trackingWork: Task<Void, Never>?
    @State private var loadedDefaults = false
    @State private var outputFormat = GalleryOutputFormat.heic.rawValue
    @State private var maximumDimension = 4_096
    @State private var quality = 0.9
    @State private var namesPreset = false
    @State private var presetName = ""
    @State private var silenceStart = 0.0
    @State private var silenceEnd = 1.0

    init(request: GalleryShareRequest) {
        self.request = request
        _profile = State(initialValue: request.profile)
    }

    private var asset: PhotoAssetRecord { request.assets[0] }
    private var isSingle: Bool { request.assets.count == 1 }

    var body: some View {
        NavigationStack {
            Group {
                if let payload = model.sharePayload { review(payload) }
                else { editor }
            }
            .navigationTitle(model.sharePayload == nil ? "Prepare Share" : "Review Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { model.finishShare() }
                }
            }
        }
        .sheet(isPresented: $showsMetadata) {
            MetadataEditorView(profile: profile ?? MetadataForge.randomProfile(), mediaKind: asset.kind,
                               actionTitle: "Use Metadata") { profile = $0 }
        }
        .sheet(isPresented: $showsActivity) {
            if let payload = model.sharePayload {
                ShareSheet(urls: payload.items.map(\.url)) { showsActivity = false }
                    .presentationDetents([.medium, .large])
            }
        }
        .task(id: frameRevision) {
            if !loadedDefaults {
                outputFormat = model.shareOutputFormat; maximumDimension = model.shareMaximumDimension; quality = model.shareLossyQuality
                if isSingle && asset.kind == .photo { edits.photoEdits = model.organization.items[asset.id]?.photoEdits }
                loadedDefaults = true
            }
            guard isSingle else { return }
            do {
                let loaded = try await model.shareEditorImage(for: asset, time: frameTime, photoEdits: edits.photoEdits)
                guard !Task.isCancelled else { return }
                image = loaded; previewError = nil; suggestions = []
            } catch { if !Task.isCancelled { previewError = error.localizedDescription } }
        }
        .onDisappear { detectionTask?.cancel(); trackingWork?.cancel(); detectionTask = nil; image = nil; suggestions = [] }
        .alert("Save Sharing Preset", isPresented: $namesPreset) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                model.saveSharingPreset(.init(name: presetName.trimmingCharacters(in: .whitespacesAndNewlines), format: GalleryOutputFormat(rawValue: outputFormat) ?? .heic,
                    maximumDimension: maximumDimension, quality: quality, videoMaximumEdge: edits.videoMaximumEdge, removeAudio: edits.removeAudio, metadata: profile))
            }.disabled(!GalleryOrganization.validName(presetName.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    private var editor: some View {
        Form {
            if isSingle {
                Section {
                    if let image {
                        GalleryRedactionCanvas(image: image, masks: $edits.redactions, suggestions: $suggestions, selectedID: $selectedCover, time: frameTime)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        Text("Tap dotted suggestions to accept them.")
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button("Suggest Faces & Text", systemImage: "viewfinder") { detect() }
                                .disabled(detecting || edits.redactions.count >= 100)
                            Spacer()
                            if detecting { ProgressView() }
                            if !edits.redactions.isEmpty {
                                Button("Clear", role: .destructive) { edits.redactions = [] }
                            }
                        }
                        if let suggestionStatus { Text(suggestionStatus).font(.footnote).foregroundStyle(.secondary) }
                        Text("On-device suggestions can miss details. Review faces, plates and text.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if let previewError {
                        Text(previewError).foregroundStyle(.secondary)
                    } else { ProgressView("Loading preview…") }
                } header: { Text("Cover sensitive details") }
                if asset.kind == .video, asset.duration >= 0.1 {
                    Section("Video") {
                        LabeledContent("Preview frame", value: timeLabel(frameTime))
                        Slider(value: $frameTime, in: 0...max(0.01, asset.duration - 0.05), onEditingChanged: { editing in
                            if !editing { frameRevision += 1 }
                        }).accessibilityLabel("Preview frame")
                        LabeledContent("Start", value: timeLabel(edits.trimStart))
                        Slider(value: $edits.trimStart, in: 0...max(0.001, (edits.trimEnd ?? asset.duration) - 0.1))
                            .accessibilityLabel("Trim start")
                        LabeledContent("End", value: timeLabel(edits.trimEnd ?? asset.duration))
                        Slider(value: Binding(get: { edits.trimEnd ?? asset.duration }, set: { edits.trimEnd = $0 }),
                               in: min(edits.trimStart + 0.1, asset.duration)...asset.duration)
                            .accessibilityLabel("Trim end")
                        Toggle("Remove Audio", isOn: $edits.removeAudio)
                        if let index = edits.redactions.firstIndex(where: { $0.id == selectedCover }) {
                            Button("Track Selected Cover Through Clip", systemImage: "viewfinder") { trackSelectedCover() }.disabled(tracking)
                            Button("Add Manual Keyframe at Preview") {
                                if edits.redactions[index].keyframes.isEmpty {
                                    let rect = edits.redactions[index].rect
                                    edits.redactions[index].keyframes = [.init(time: 0, rect: rect), .init(time: asset.duration, rect: rect)]
                                }
                                let rect = edits.redactions[index].rect(at: frameTime)
                                edits.redactions[index].setRect(rect, at: frameTime)
                            }
                            if !edits.redactions[index].keyframes.isEmpty {
                                LabeledContent("Moving cover", value: "\(edits.redactions[index].keyframes.count) keyframes")
                                Button("Make Cover Static") {
                                    let rect = edits.redactions[index].rect(at: frameTime)
                                    edits.redactions[index].rect = rect; edits.redactions[index].keyframes = []
                                }
                            }
                        }
                        if tracking { ProgressView("Tracking selected area…"); Button("Cancel Tracking") { trackingWork?.cancel() } }
                        Text("Tracking and interpolation can miss motion. Scrub to adjust cover keyframes and review the whole export.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !edits.removeAudio {
                        Section("Silence parts of the audio") {
                            LabeledContent("From", value: timeLabel(silenceStart))
                            Slider(value: $silenceStart, in: 0...max(0.001, asset.duration - 0.1)).accessibilityLabel("Silence start")
                            LabeledContent("Through", value: timeLabel(max(silenceStart + 0.1, min(asset.duration, silenceEnd))))
                            Slider(value: $silenceEnd, in: min(asset.duration, silenceStart + 0.1)...asset.duration).accessibilityLabel("Silence end")
                            Button("Add Silent Section", systemImage: "speaker.slash") {
                                edits.silencedRanges.append(.init(start: silenceStart, end: min(asset.duration, max(silenceStart + 0.1, silenceEnd))))
                            }.disabled(edits.silencedRanges.count >= 100)
                            ForEach(edits.silencedRanges) { range in
                                HStack {
                                    Text("\(timeLabel(range.start)) – \(timeLabel(range.end))").font(.caption)
                                    Spacer()
                                    Button("Remove Silent Section", systemImage: "minus.circle", role: .destructive) { edits.silencedRanges.removeAll { $0.id == range.id } }.labelStyle(.iconOnly)
                                }
                            }
                            Text("Times refer to the original clip. Audio outside these sections is retained.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if asset.originalKind != nil {
                    Section {
                        Text("Shares contain a rendered still. All original components remain in your private gallery.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Label("\(request.assets.count) items", systemImage: "square.stack")
                    Text("One metadata choice applies to every copy. Open an item individually to cover details or trim video.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Share metadata") {
                LabeledContent("Mode", value: profile?.displayName ?? "Remove source metadata")
                if profile != nil { Button("Remove Metadata") { profile = nil } }
                if !model.presets.isEmpty {
                    Menu("Use Saved Preset", systemImage: "square.stack") {
                        ForEach(model.presets) { preset in
                            Button(preset.name) { profile = preset.profile }
                        }
                    }
                }
                Button("Customize Metadata", systemImage: "slider.horizontal.3") { showsMetadata = true }
            }
            Section("Output & sharing presets") {
                Menu("Use Sharing Preset", systemImage: "slider.horizontal.3") {
                    ForEach(GallerySharingPreset.builtIns + model.sharingPresets) { preset in
                        Button(preset.name) {
                            outputFormat = preset.format.rawValue; maximumDimension = preset.maximumDimension; quality = preset.quality
                            edits.videoMaximumEdge = preset.videoMaximumEdge; edits.removeAudio = preset.removeAudio; profile = preset.metadata
                        }
                    }
                }
                Picker("Photo format", selection: $outputFormat) { ForEach(GalleryOutputFormat.allCases) { Text($0.title).tag($0.rawValue) } }
                Picker("Photo maximum edge", selection: $maximumDimension) { Text("2,048 px").tag(2_048); Text("4,096 px").tag(4_096); Text("8,192 px").tag(8_192) }
                if outputFormat != GalleryOutputFormat.png.rawValue {
                    LabeledContent("Photo quality", value: quality.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $quality, in: 0.65...1, step: 0.01).accessibilityLabel("Photo export quality")
                }
                Picker("Video maximum edge", selection: $edits.videoMaximumEdge) { Text("960 px").tag(960); Text("1,280 px").tag(1_280); Text("1,920 px").tag(1_920) }
                if !isSingle { Toggle("Remove Video Audio", isOn: $edits.removeAudio) }
                Button("Save Current Sharing Preset") { presetName = ""; namesPreset = true }.disabled(model.sharingPresets.count >= 30)
            }
            Section {
                Button {
                    selectedExport = 0
                    model.errorMessage = nil
                    let configuration = GalleryPreferences.configuration(format: outputFormat, maximumDimension: maximumDimension, quality: quality)
                    Task { await model.prepareShares(assets: request.assets, configuration: configuration, profile: profile, edits: edits) }
                } label: {
                    Label("Prepare Preview", systemImage: "eye").frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("share.preparePreview")
                .disabled(tracking)
                if model.isProcessing { ProgressView(model.processingMessage ?? "Preparing…") }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            } footer: {
                Text(isSingle ? "Your originals stay unchanged. Covers are burned into the shared copy." : "Your originals stay unchanged. Review each copy before sharing.")
            }
        }
        .disabled(model.isProcessing)
    }

    @ViewBuilder private func review(_ payload: SharePayload) -> some View {
        if !payload.items.isEmpty {
            let item = payload.items[min(selectedExport, payload.items.count - 1)]
            ScrollView {
                VStack(spacing: 20) {
                    if payload.items.count > 1 {
                        Picker("Export", selection: $selectedExport) {
                            ForEach(payload.items.indices, id: \.self) { Text("Item \($0 + 1)").tag($0) }
                        }.pickerStyle(.menu)
                    }
                    GalleryExportPreview(item: item).id(item.id)
                        .frame(maxHeight: 460).clipShape(RoundedRectangle(cornerRadius: 20))
                    VStack(spacing: 10) {
                        LabeledContent("Dimensions", value: "\(item.inspection.width) × \(item.inspection.height)")
                        LabeledContent("File", value: "\(item.url.pathExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(item.inspection.byteCount), countStyle: .file))")
                        if item.kind == .video {
                            LabeledContent("Duration", value: timeLabel(item.inspection.duration))
                            LabeledContent("Audio", value: item.inspection.hasAudio ? "Included" : "None")
                        }
                    }.font(.subheadline)
                    GalleryMetadataComparison(original: item.originalMetadata, exported: item.inspection.fields)
                    Button {
                        showsActivity = true
                    } label: {
                        Label(payload.items.count == 1 ? "Share This Copy" : "Share \(payload.items.count) Copies", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("share.confirm")
                    Button("Back to Edits") { Task { await model.editShareAgain() } }
                    Text("This is the exported file. Temporary copies are removed when you close this screen or lock Gallery.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        String(format: "%02d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    private func detect() {
        guard let cgImage = image?.cgImage else { return }
        detecting = true
        suggestionStatus = nil
        let revision = frameRevision
        Task {
            let task = Task.detached(priority: .userInitiated) { try GalleryRedactionSuggestions.detect(in: cgImage) }
            detectionTask = task
            defer { detecting = false }
            do {
                let found = try await task.value
                guard model.privateUnlocked, revision == frameRevision, model.shareRequest?.id == request.id else { return }
                suggestions = found
                suggestionStatus = found.isEmpty ? "No suggestions found. Draw covers where needed." : "Found \(found.count) areas. Tap the ones to cover."
            } catch {
                if model.shareRequest?.id == request.id { suggestionStatus = "Suggestions unavailable. Draw covers where needed." }
            }
        }
    }

    private func trackSelectedCover() {
        guard let index = edits.redactions.firstIndex(where: { $0.id == selectedCover }) else { return }
        let cover = edits.redactions[index]
        let start = edits.trimStart, end = edits.trimEnd ?? asset.duration
        tracking = true; suggestionStatus = nil
        trackingWork = Task {
            defer { tracking = false }
            do {
                let frames = try await model.trackCover(for: asset, cover: cover, start: start, end: end)
                try Task.checkCancellation()
                guard let current = edits.redactions.firstIndex(where: { $0.id == cover.id }), model.shareRequest?.id == request.id else { return }
                guard edits.redactions[current] == cover, edits.trimStart == start, (edits.trimEnd ?? asset.duration) == end else {
                    suggestionStatus = "The cover or clip changed. Track again using the current edits."
                    return
                }
                edits.redactions[current].keyframes = frames
                suggestionStatus = "Tracking ready. Review and adjust across the clip."
            } catch { if !(error is CancellationError) { suggestionStatus = error.localizedDescription } }
        }
    }
}

private struct GalleryExportPreview: View {
    let item: GalleryReviewedExport
    @State private var player: AVPlayer?
    @State private var photo: UIImage?
    var body: some View {
        Group {
            if let player { VideoPlayer(player: player).aspectRatio(CGFloat(item.inspection.width) / CGFloat(max(1, item.inspection.height)), contentMode: .fit) }
            else if let photo { Image(uiImage: photo).resizable().scaledToFit() }
            else { ProgressView() }
        }
        .task {
            if item.kind == .video { player = AVPlayer(url: item.url) }
            else if let source = CGImageSourceCreateWithURL(item.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                    let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2_048
                    ] as CFDictionary) {
                photo = UIImage(cgImage: thumbnail)
            }
        }
        .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil; photo = nil }
    }
}

private struct GalleryMetadataComparison: View {
    let original: [GalleryMetadataField]
    let exported: [GalleryMetadataField]
    private var removed: [GalleryMetadataField] { original.filter { field in !exported.contains { $0.name == field.name } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup("Metadata in this copy (\(exported.count))") {
                if exported.isEmpty { Text("No descriptive metadata.").foregroundStyle(.secondary) }
                ForEach(exported) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.name).font(.caption).foregroundStyle(.secondary)
                        Text(field.value).font(.footnote)
                        if let previous = original.first(where: { $0.name == field.name }), previous.value != field.value {
                            Text("Was: \(previous.value)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                }
            }
            DisclosureGroup("Removed fields (\(removed.count))") {
                ForEach(removed) { field in
                    Text(field.name).font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
                }
            }
            Text("Inspected from the output file. Format, dimensions and encoding fields are needed for playback.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
