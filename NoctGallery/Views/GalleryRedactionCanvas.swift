import SwiftUI

struct GalleryRedactionCanvas: View {
    let image: UIImage
    @Binding var masks: [GalleryRedaction]
    @Binding var suggestions: [GalleryRedaction]
    @Binding var selectedID: UUID?
    var time = 0.0
    @State private var mode = "draw"
    @State private var zoom = 1.0
    @State private var pending: CGRect?
    @State private var gestureStart: CGRect?
    @State private var past: [[GalleryRedaction]] = []
    @State private var future: [[GalleryRedaction]] = []
    @State private var skipHistory = false
    private var aspect: CGFloat { image.size.width / max(1, image.size.height) }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Blur tool", selection: $mode) {
                Text("Draw").tag("draw"); Text("Move / resize").tag("move"); Text("Pan").tag("pan")
            }.pickerStyle(.segmented)
            GeometryReader { viewport in
                ScrollView([.horizontal, .vertical]) {
                    GeometryReader { proxy in canvas(size: proxy.size) }
                        .frame(width: viewport.size.width * zoom, height: viewport.size.width * zoom / aspect)
                        .coordinateSpace(name: "galleryCoverCanvas")
                }
                .scrollDisabled(mode != "pan")
            }
            .aspectRatio(aspect, contentMode: .fit).frame(maxHeight: 460).clipped()
            HStack(spacing: 16) {
                Button("Undo", systemImage: "arrow.uturn.backward") { undo() }.labelStyle(.iconOnly).disabled(past.isEmpty)
                Button("Redo", systemImage: "arrow.uturn.forward") { redo() }.labelStyle(.iconOnly).disabled(future.isEmpty)
                Button("Remove Selected Blur", systemImage: "trash") { masks.removeAll { $0.id == selectedID }; selectedID = nil }
                    .labelStyle(.iconOnly).disabled(selectedID == nil)
                Text("Zoom").font(.caption)
                Slider(value: $zoom, in: 1...3, step: 0.25).accessibilityLabel("Blur editor zoom")
            }
            Text("Draw an area to blur, or select Move / resize to adjust it. Pan moves around the zoomed image.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .onChange(of: masks) { old, new in
            guard old != new else { return }
            if skipHistory { skipHistory = false }
            else { past.append(old); if past.count > 100 { past.removeFirst() }; future = [] }
            if !masks.contains(where: { $0.id == selectedID }) { selectedID = nil }
        }
        .onChange(of: mode) { _, _ in pending = nil; gestureStart = nil }
        .onChange(of: time) { _, _ in pending = nil; gestureStart = nil }
    }

    private func canvas(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
                .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("galleryCoverCanvas"))
                    .onChanged { value in if mode == "draw" { pending = normalized(value, size: size) } }
                    .onEnded { value in
                        if mode == "draw", let rect = normalized(value, size: size), masks.count < 100 {
                            let mask = GalleryRedaction(rect: rect, referenceTime: time); masks.append(mask); selectedID = mask.id
                        }
                        pending = nil
                    })
            ForEach(suggestions) { suggestion in
                let rect = suggestion.rect
                Button {
                    if masks.count < 100 {
                        var accepted = suggestion; accepted.referenceTime = time
                        masks.append(accepted); selectedID = accepted.id; suggestions.removeAll { $0.id == accepted.id }
                    }
                } label: { Rectangle().strokeBorder(.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 4])) }
                .buttonStyle(.plain).frame(width: rect.width * size.width, height: rect.height * size.height)
                .position(x: rect.midX * size.width, y: rect.midY * size.height).accessibilityLabel("Accept suggested sensitive area")
            }
            ForEach(masks) { mask in
                let selected = mask.id == selectedID
                let rect = selected && mode == "move" ? (pending ?? mask.rect(at: time)) : mask.rect(at: time)
                GalleryBlurRegion(image: image, rect: rect, canvasSize: size)
                    .overlay { if selected { Rectangle().stroke(.white, lineWidth: 2) } }
                    .frame(width: rect.width * size.width, height: rect.height * size.height)
                    .position(x: rect.midX * size.width, y: rect.midY * size.height)
                    .onTapGesture { selectedID = mask.id; mode = "move" }
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("galleryCoverCanvas"))
                        .onChanged { value in
                            guard mode == "move" else { return }
                            if gestureStart == nil { selectedID = mask.id; gestureStart = mask.rect(at: time) }
                            guard let start = gestureStart else { return }
                            pending = CGRect(x: min(1 - start.width, max(0, start.minX + value.translation.width / size.width)),
                                y: min(1 - start.height, max(0, start.minY + value.translation.height / size.height)), width: start.width, height: start.height)
                        }.onEnded { _ in commitPending() })
                    .accessibilityElement().accessibilityLabel(selected ? "Selected blur" : "Select blur")
                    .accessibilityAddTraits(.isButton).accessibilityAction { selectedID = mask.id; mode = "move" }
                if selected && mode == "move" {
                    Circle().fill(.white).overlay { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2).foregroundStyle(.black) }
                        .frame(width: 28, height: 28).position(x: rect.maxX * size.width, y: rect.maxY * size.height)
                        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("galleryCoverCanvas"))
                            .onChanged { value in
                                if gestureStart == nil { gestureStart = mask.rect(at: time) }
                                guard let start = gestureStart else { return }
                                pending = CGRect(x: start.minX, y: start.minY,
                                    width: min(1 - start.minX, max(0.01, start.width + value.translation.width / size.width)),
                                    height: min(1 - start.minY, max(0.01, start.height + value.translation.height / size.height)))
                            }.onEnded { _ in commitPending() })
                        .accessibilityLabel("Resize selected blur")
                }
            }
            if mode == "draw", let pending {
                Rectangle().stroke(.white, lineWidth: 2).frame(width: pending.width * size.width, height: pending.height * size.height)
                    .position(x: pending.midX * size.width, y: pending.midY * size.height).allowsHitTesting(false)
            }
        }
    }

    private func commitPending() {
        if let pending, let index = masks.firstIndex(where: { $0.id == selectedID }) { masks[index].setRect(pending, at: time) }
        pending = nil; gestureStart = nil
    }
    private func undo() {
        guard let value = past.popLast() else { return }
        future.append(masks); skipHistory = true; masks = value
    }
    private func redo() {
        guard let value = future.popLast() else { return }
        past.append(masks); skipHistory = true; masks = value
    }
    private func normalized(_ value: DragGesture.Value, size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let x = min(1, max(0, value.startLocation.x / size.width)), y = min(1, max(0, value.startLocation.y / size.height))
        let endX = min(1, max(0, value.location.x / size.width)), endY = min(1, max(0, value.location.y / size.height))
        let rect = CGRect(x: min(x, endX), y: min(y, endY), width: abs(endX - x), height: abs(endY - y))
        return rect.width > 0.005 && rect.height > 0.005 ? rect : nil
    }
}

private struct GalleryBlurRegion: View {
    let image: UIImage
    let rect: CGRect
    let canvasSize: CGSize
    @State private var blurred: UIImage?
    private struct Input: Equatable { let image: ObjectIdentifier; let rect: CGRect }

    var body: some View {
        ZStack {
            // Keep the area blurred while the matching export-quality preview renders.
            Image(uiImage: image).resizable().frame(width: canvasSize.width, height: canvasSize.height)
                .offset(x: -rect.minX * canvasSize.width, y: -rect.minY * canvasSize.height)
                .frame(width: rect.width * canvasSize.width, height: rect.height * canvasSize.height, alignment: .topLeading)
                .clipped().blur(radius: 24, opaque: true)
            if let blurred { Image(uiImage: blurred).resizable() }
        }
        .clipped().contentShape(Rectangle())
        .task(id: Input(image: ObjectIdentifier(image), rect: rect)) {
            blurred = nil
            guard let source = image.cgImage, GalleryRedaction(rect: rect).isValid else { return }
            let pixels = GalleryRedaction(rect: rect).pixelRect(width: source.width, height: source.height)
            let worker = Task.detached(priority: .userInitiated) { try GalleryBlur.region(in: source, pixels: pixels) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { return }
                blurred = UIImage(cgImage: result)
            } catch { }
        }
        .onDisappear { blurred = nil }
    }
}
