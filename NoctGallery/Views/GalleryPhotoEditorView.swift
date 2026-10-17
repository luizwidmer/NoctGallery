import SwiftUI

private enum GalleryCropAspect: String, CaseIterable, Identifiable {
    case free = "Free", original = "Original", square = "Square", fourThree = "4:3", wide = "16:9"
    var id: Self { self }
    func ratio(original: Double) -> Double? {
        switch self { case .free: nil; case .original: original; case .square: 1; case .fourThree: 4.0 / 3; case .wide: 16.0 / 9 }
    }
}

struct GalleryPhotoEditorView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let asset: PhotoAssetRecord
    @State private var edits = GalleryPhotoEdits()
    @State private var preview: UIImage?
    @State private var original: UIImage?
    @State private var loaded = false
    @State private var error: String?
    @State private var aspect = GalleryCropAspect.free
    @State private var showsOriginal = false
    @State private var past: [GalleryPhotoEdits] = []
    @State private var future: [GalleryPhotoEdits] = []
    @State private var skipHistory = false
    @State private var sliderStart: GalleryPhotoEdits?

    private var renderRecipe: GalleryPhotoEdits { var copy = edits; copy.crop = .init(x: 0, y: 0, width: 1, height: 1); return copy }
    private var imageAspect: Double { guard let preview else { return 1 }; return preview.size.width / max(1, preview.size.height) }
    private var fixedAspect: Double? { aspect.ratio(original: Double(asset.pixelWidth) / Double(max(1, asset.pixelHeight))) }
    private var normalizedAspect: Double? { fixedAspect.map { $0 / imageAspect } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if showsOriginal, let original {
                        Image(uiImage: original).resizable().scaledToFit().frame(maxHeight: 420).frame(maxWidth: .infinity).overlay(alignment: .topLeading) { Text("Original").font(.caption.bold()).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(8) }
                            .listRowInsets(.init()).accessibilityLabel("Original photo, before edits")
                    } else if let preview {
                        GalleryCropCanvas(image: preview, crop: $edits.crop, normalizedAspect: normalizedAspect).frame(maxHeight: 420).frame(maxWidth: .infinity).listRowInsets(.init())
                    } else if let error { Text(error).foregroundStyle(.red) }
                    else { ProgressView("Loading photo…") }
                    Button(showsOriginal ? "Show Edits" : "Compare with Original", systemImage: "circle.lefthalf.filled") { showsOriginal.toggle() }
                        .disabled(original == nil).accessibilityValue(showsOriginal ? "Original" : "Edited")
                    Text("Move the crop or drag a corner. Original files stay unchanged.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Crop & rotate") {
                    Picker("Aspect ratio", selection: $aspect) { ForEach(GalleryCropAspect.allCases) { Text($0.rawValue).tag($0) } }
                        .onChange(of: aspect) { _, _ in applyAspect() }
                    Button("Rotate 90°", systemImage: "rotate.right") { edits.quarterTurns = (edits.quarterTurns + 1) % 4; edits.crop = .init(x: 0, y: 0, width: 1, height: 1) }
                    LabeledContent("Straighten", value: "\(edits.straightenDegrees.formatted(.number.precision(.fractionLength(1))))°")
                    Slider(value: $edits.straightenDegrees, in: -15...15, step: 0.1, onEditingChanged: groupSlider)
                        .accessibilityLabel("Straighten photo")
                    DisclosureGroup("Precise Crop Controls") { GalleryRectangleAdjustmentView(rect: $edits.crop, aspect: normalizedAspect, title: "Crop") }
                    Button("Reset Crop") { aspect = .free; edits.crop = .init(x: 0, y: 0, width: 1, height: 1) }
                }.disabled(showsOriginal)
                Section("Light & color") {
                    adjustment("Brightness", value: $edits.brightness, range: -0.5...0.5, neutral: 0)
                    adjustment("Contrast", value: $edits.contrast, range: 0.5...1.5, neutral: 1)
                    adjustment("Saturation", value: $edits.saturation, range: 0...2, neutral: 1)
                }.disabled(showsOriginal)
                Section {
                    Button("Reset All Edits", role: .destructive) { aspect = .free; edits = .init() }
                    Button("Save Edits", systemImage: "checkmark") {
                        Task {
                            model.errorMessage = nil
                            await model.organize([asset.id], edit: .photoEdits(edits.isIdentity ? nil : edits))
                            if model.errorMessage == nil { dismiss() }
                        }
                    }.disabled(model.isOrganizing || preview == nil)
                    if let error = model.errorMessage ?? error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undo() }.labelStyle(.iconOnly).disabled(past.isEmpty)
                    Button("Redo", systemImage: "arrow.uturn.forward") { redo() }.labelStyle(.iconOnly).disabled(future.isEmpty)
                }
            }
            .task {
                guard !loaded else { return }
                let saved = model.organization.items[asset.id]?.photoEdits ?? .init()
                skipHistory = saved != edits
                edits = saved; loaded = true; past = []
                do { original = try await model.shareEditorImage(for: asset, maximumDimension: 2_048) }
                catch { self.error = error.localizedDescription }
            }
            .task(id: RenderInput(recipe: renderRecipe, hasOriginal: original != nil)) {
                guard let cgImage = original?.cgImage else { return }
                let recipe = renderRecipe
                do {
                    try await Task.sleep(for: .milliseconds(65))
                    let worker = Task.detached(priority: .userInitiated) { try recipe.apply(to: cgImage) }
                    let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    guard !Task.isCancelled else { return }
                    let previousAspect = imageAspect
                    preview = UIImage(cgImage: result); error = nil
                    if fixedAspect != nil, abs(previousAspect - imageAspect) > 0.001 { applyAspect() }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onChange(of: edits) { old, new in
                guard old != new, loaded else { return }
                if skipHistory { skipHistory = false }
                else if sliderStart == nil { remember(old) }
            }
            .onDisappear { preview = nil; original = nil }
        }
    }
    private struct RenderInput: Equatable { let recipe: GalleryPhotoEdits; let hasOriginal: Bool }
    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, neutral: Double) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: String(format: "%+.0f", (value.wrappedValue - neutral) * 100))
            Slider(value: value, in: range, step: 0.01, onEditingChanged: groupSlider).accessibilityLabel(title)
        }
    }
    private func groupSlider(_ editing: Bool) {
        if editing { sliderStart = edits }
        else if let start = sliderStart { sliderStart = nil; if start != edits { remember(start) } }
    }
    private func remember(_ previous: GalleryPhotoEdits) { past.append(previous); if past.count > 100 { past.removeFirst() }; future = [] }
    private func applyAspect() {
        if let fixedAspect {
            let crop = GalleryRectangleEditing.centered(aspect: fixedAspect, imageAspect: imageAspect)
            if crop.width >= 0.02, crop.height >= 0.02 { edits.crop = crop }
            else { aspect = .free; error = "This aspect ratio is too narrow for this photo. Choose Free or Original." }
        }
    }
    private func undo() { guard let old = past.popLast() else { return }; future.append(edits); skipHistory = true; aspect = .free; edits = old }
    private func redo() { guard let next = future.popLast() else { return }; past.append(edits); skipHistory = true; aspect = .free; edits = next }
}

struct GalleryCropCanvas: View {
    let image: UIImage
    @Binding var crop: CGRect
    var normalizedAspect: Double?
    @State private var pending: CGRect?
    @State private var start: CGRect?
    var body: some View {
        GeometryReader { proxy in
            let value = pending ?? crop
            let rect = CGRect(x: value.minX * proxy.size.width, y: value.minY * proxy.size.height,
                width: value.width * proxy.size.width, height: value.height * proxy.size.height)
            ZStack {
                Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
                Path { path in path.addRect(CGRect(origin: .zero, size: proxy.size)); path.addRect(rect) }
                    .fill(.black.opacity(0.5), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                Rectangle().fill(.clear).contentShape(Rectangle()).frame(width: rect.width, height: rect.height)
                    .overlay(Rectangle().stroke(.white, lineWidth: 2)).position(x: rect.midX, y: rect.midY)
                    .gesture(DragGesture(minimumDistance: 2).onChanged { gesture in
                        if start == nil { start = crop }; guard let start else { return }
                        pending = GalleryRectangleEditing.move(start, dx: gesture.translation.width / proxy.size.width, dy: gesture.translation.height / proxy.size.height)
                    }.onEnded { _ in commit() })
                    .accessibilityLabel("Crop area").accessibilityHint("Use Precise Crop Controls below to move or resize without dragging.")
                ForEach(Array(GalleryCropHandle.allCases.enumerated()), id: \.offset) { _, handle in
                    let left = handle == .topLeft || handle == .bottomLeft
                    let top = handle == .topLeft || handle == .topRight
                    Circle().fill(.white).frame(width: 14, height: 14).frame(width: 44, height: 44).contentShape(Rectangle())
                        .position(x: left ? rect.minX : rect.maxX, y: top ? rect.minY : rect.maxY)
                        .gesture(DragGesture(minimumDistance: 2).onChanged { gesture in
                            if start == nil { start = crop }; guard let start else { return }
                            pending = GalleryRectangleEditing.resize(start, handle: handle, dx: gesture.translation.width / proxy.size.width,
                                dy: gesture.translation.height / proxy.size.height, aspect: normalizedAspect)
                        }.onEnded { _ in commit() })
                        .accessibilityHidden(true)
                }
            }.clipped()
        }
        .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
    }
    private func commit() { if let pending { crop = pending }; pending = nil; start = nil }
}

struct GalleryNotesView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let asset: PhotoAssetRecord
    @State private var caption = ""
    @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Caption") { TextField("Describe this item", text: $caption, axis: .vertical).accessibilityLabel("Caption") }
                Section("Private notes") { TextEditor(text: $notes).frame(minHeight: 180).accessibilityLabel("Private notes") }
                Section {
                    Text("Encrypted in your vault and searchable while unlocked. These notes are excluded from shared copies.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Caption & Notes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            model.errorMessage = nil
                            await model.organize([asset.id], edit: .description(caption: caption, notes: notes))
                            if model.errorMessage == nil { dismiss() }
                        }
                    }.disabled(caption.count > 512 || notes.count > 8_000 || model.isOrganizing)
                }
            }
            .onAppear { caption = model.organization.items[asset.id]?.caption ?? ""; notes = model.organization.items[asset.id]?.notes ?? "" }
        }
    }
}
