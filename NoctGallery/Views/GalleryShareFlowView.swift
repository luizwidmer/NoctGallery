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
            guard isSingle else { return }
            do {
                let loaded = try await model.shareEditorImage(for: asset, time: frameTime)
                guard !Task.isCancelled else { return }
                image = loaded; previewError = nil; suggestions = []
            } catch { if !Task.isCancelled { previewError = error.localizedDescription } }
        }
        .onDisappear { detectionTask?.cancel(); detectionTask = nil; image = nil; suggestions = [] }
    }

    private var editor: some View {
        Form {
            if isSingle {
                Section {
                    if let image {
                        GalleryRedactionCanvas(image: image, masks: $edits.redactions, suggestions: $suggestions)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        Text("Drag to cover; tap to remove. Tap dotted suggestions to accept them.")
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
                        Text("Covers stay in the same position throughout the clip. Review the whole export for moving details.")
                            .font(.footnote).foregroundStyle(.secondary)
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
            Section {
                Button {
                    selectedExport = 0
                    model.errorMessage = nil
                    let configuration = GalleryPreferences.configuration(format: model.shareOutputFormat,
                        maximumDimension: model.shareMaximumDimension, quality: model.shareLossyQuality)
                    Task { await model.prepareShares(assets: request.assets, configuration: configuration, profile: profile, edits: edits) }
                } label: {
                    Label("Prepare Preview", systemImage: "eye").frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("share.preparePreview")
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
}

private struct GalleryRedactionCanvas: View {
    let image: UIImage
    @Binding var masks: [GalleryRedaction]
    @Binding var suggestions: [GalleryRedaction]
    @State private var drag: CGRect?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
                ForEach(suggestions) { suggestion in
                    Button {
                        if masks.count < 100 { masks.append(suggestion); suggestions.removeAll { $0.id == suggestion.id } }
                    } label: {
                        Rectangle().strokeBorder(.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: suggestion.rect.width * proxy.size.width, height: suggestion.rect.height * proxy.size.height)
                    .position(x: suggestion.rect.midX * proxy.size.width, y: suggestion.rect.midY * proxy.size.height)
                    .accessibilityLabel("Suggested sensitive area")
                }
                ForEach(masks) { mask in
                    Button { masks.removeAll { $0.id == mask.id } } label: { Rectangle().fill(.black) }
                    .buttonStyle(.plain)
                    .frame(width: mask.rect.width * proxy.size.width, height: mask.rect.height * proxy.size.height)
                    .position(x: mask.rect.midX * proxy.size.width, y: mask.rect.midY * proxy.size.height)
                    .accessibilityLabel("Remove cover")
                }
                if let drag { box(drag, size: proxy.size, suggested: false).allowsHitTesting(false) }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 8)
                .onChanged { drag = normalized($0, in: proxy.size) }
                .onEnded { value in
                    if let rect = normalized(value, in: proxy.size), masks.count < 100 { masks.append(.init(rect: rect)) }
                    drag = nil
                })
        }
        .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
    }

    private func box(_ rect: CGRect, size: CGSize, suggested: Bool) -> some View {
        Rectangle().strokeBorder(suggested ? .yellow : .white, style: StrokeStyle(lineWidth: 2, dash: suggested ? [5, 4] : []))
            .frame(width: rect.width * size.width, height: rect.height * size.height)
            .position(x: rect.midX * size.width, y: rect.midY * size.height)
    }

    private func normalized(_ value: DragGesture.Value, in size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let x = min(max(0, value.startLocation.x / size.width), 1)
        let y = min(max(0, value.startLocation.y / size.height), 1)
        let endX = min(max(0, value.location.x / size.width), 1)
        let endY = min(max(0, value.location.y / size.height), 1)
        let rect = CGRect(x: min(x, endX), y: min(y, endY), width: abs(endX - x), height: abs(endY - y))
        return rect.width > 0.005 && rect.height > 0.005 ? rect : nil
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
