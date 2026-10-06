import SwiftUI

struct GalleryPhotoEditorView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let asset: PhotoAssetRecord
    @State private var edits = GalleryPhotoEdits()
    @State private var preview: UIImage?
    @State private var loaded = false
    @State private var revision = 0
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let preview { GalleryCropCanvas(image: preview, crop: $edits.crop).listRowInsets(.init()) }
                    else if let error { Text(error).foregroundStyle(.red) }
                    else { ProgressView("Loading original…") }
                    Text("Drag a crop rectangle. Edits are saved as an encrypted recipe; original files stay intact.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Adjust") {
                    Button("Rotate 90°", systemImage: "rotate.right") { edits.quarterTurns = (edits.quarterTurns + 1) % 4; edits.crop = GalleryPhotoEdits().crop; revision += 1 }
                    LabeledContent("Straighten", value: "\(edits.straightenDegrees.formatted(.number.precision(.fractionLength(1))))°")
                    Slider(value: $edits.straightenDegrees, in: -15...15, step: 0.1, onEditingChanged: { if !$0 { revision += 1 } })
                        .accessibilityLabel("Straighten photo")
                    Button("Reset Crop") { edits.crop = GalleryPhotoEdits().crop }
                    Button("Reset All Edits", role: .destructive) { edits = .init(); revision += 1 }
                }
                Section {
                    Button("Save Edits", systemImage: "checkmark") {
                        Task {
                            model.errorMessage = nil
                            await model.organize([asset.id], edit: .photoEdits(edits.isIdentity ? nil : edits))
                            if model.errorMessage == nil { dismiss() }
                        }
                    }.disabled(model.isOrganizing || preview == nil)
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Photo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: revision) {
                if !loaded { edits = model.organization.items[asset.id]?.photoEdits ?? .init(); loaded = true }
                var uncropped = edits; uncropped.crop = GalleryPhotoEdits().crop
                do {
                    let image = try await model.shareEditorImage(for: asset, photoEdits: uncropped)
                    if !Task.isCancelled { preview = image; error = nil }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onDisappear { preview = nil }
        }
    }
}

struct GalleryCropCanvas: View {
    let image: UIImage
    @Binding var crop: CGRect
    @State private var pending: CGRect?
    var body: some View {
        GeometryReader { proxy in
            let value = pending ?? crop
            let rect = CGRect(x: value.minX * proxy.size.width, y: value.minY * proxy.size.height,
                width: value.width * proxy.size.width, height: value.height * proxy.size.height)
            ZStack {
                Image(uiImage: image).resizable().scaledToFit()
                Path { path in path.addRect(CGRect(origin: .zero, size: proxy.size)); path.addRect(rect) }
                    .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
                Rectangle().stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                let a = CGPoint(x: min(1, max(0, value.startLocation.x / proxy.size.width)), y: min(1, max(0, value.startLocation.y / proxy.size.height)))
                let b = CGPoint(x: min(1, max(0, value.location.x / proxy.size.width)), y: min(1, max(0, value.location.y / proxy.size.height)))
                pending = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            }.onEnded { _ in if let pending, pending.width >= 0.02, pending.height >= 0.02 { crop = pending }; pending = nil })
        }
        .aspectRatio(image.size.width / max(1, image.size.height), contentMode: .fit)
        .accessibilityElement(children: .ignore).accessibilityLabel("Photo crop preview")
        .accessibilityHint("Drag to select a crop. Use Reset Crop to restore the full frame.")
    }
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
