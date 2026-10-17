import SwiftUI
import UIKit

struct GalleryFullscreenViewer: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let items: [PhotoAssetRecord]
    @State var selectedID: String
    @State private var image: UIImage?
    @State private var zoomed = false
    @State private var error: String?
    @State private var showsInfo = false
    @State private var showsEditor = false
    @State private var confirmsDelete = false
    private var visibleItems: [PhotoAssetRecord] {
        let ids = Set((items.first?.source == .photos ? model.assets : model.privateAssets).map(\.id))
        return items.filter { ids.contains($0.id) }
    }
    private var index: Int { visibleItems.firstIndex { $0.id == selectedID } ?? 0 }
    private var asset: PhotoAssetRecord? { visibleItems.indices.contains(index) ? visibleItems[index] : nil }
    private var nearby: [PhotoAssetRecord] {
        Array(visibleItems[max(0, index - 10)..<min(visibleItems.count, index + 11)])
    }
    private var editedRecipe: GalleryPhotoEdits? { model.organization.items[selectedID]?.photoEdits }

    var body: some View {
        NavigationStack {
            Group {
                if let asset {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        if asset.kind == .video { GalleryVideoPlayer(asset: asset).id(asset.id) }
                        else if let image { GalleryZoomImage(image: image, zoomed: $zoomed).id(asset.id) }
                        else if let error { Text(error).foregroundStyle(.white).padding() }
                        else { ProgressView().tint(.white) }
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 45).onEnded { value in
                        guard !zoomed, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        navigate(value.translation.width < 0 ? 1 : -1)
                    })
                    .safeAreaInset(edge: .bottom) { controls(asset) }
                } else { ContentUnavailableView("Item Unavailable", systemImage: "photo").onAppear { dismiss() } }
            }
            .background(.black)
            .navigationTitle("\(min(index + 1, visibleItems.count)) of \(visibleItems.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Previous", systemImage: "chevron.left") { navigate(-1) }.disabled(index == 0)
                    Button("Next", systemImage: "chevron.right") { navigate(1) }.disabled(index >= visibleItems.count - 1)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .task(id: LoadInput(id: selectedID, recipe: editedRecipe)) {
                image = nil; error = nil; zoomed = false
                guard let asset, asset.kind == .photo else { return }
                do {
                    let loaded = try await model.shareEditorImage(for: asset, photoEdits: editedRecipe, maximumDimension: 4_096)
                    if !Task.isCancelled { image = loaded }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onChange(of: visibleItems.map(\.id)) { _, ids in
                if ids.isEmpty { dismiss() }
                else if !ids.contains(selectedID), let first = ids.first { selectedID = first }
            }
            .onChange(of: model.privateGeneration) { _, _ in image = nil; dismiss() }
            .onAppear { model.fullscreenPresented = true }
            .onDisappear { image = nil; model.fullscreenPresented = false }
            .sheet(isPresented: $showsInfo) {
                if let asset { NavigationStack { AssetDetailView(asset: asset, sequence: visibleItems, isViewerInformation: true)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsInfo = false } } } } }
            }
            .sheet(isPresented: $showsEditor) { if let asset { GalleryPhotoEditorView(asset: asset) } }
            .sheet(item: $model.shareRequest, onDismiss: model.finishShare) { GalleryShareFlowView(request: $0) }
            .confirmationDialog(model.organization.recentlyDeletedEnabled == true ? "Move this item to Recently Deleted?" : "Permanently delete this item?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button(model.organization.recentlyDeletedEnabled == true ? "Move to Recently Deleted" : "Delete Permanently", role: .destructive) {
                    if let asset { Task { await model.deletePrivate(asset) } }
                }
            } message: { Text(model.organization.recentlyDeletedEnabled == true ? "You can restore it for seven days. Photos originals are unaffected." : "This cannot be undone. Photos originals are unaffected.") }
        }
    }
    private struct LoadInput: Equatable { let id: String; let recipe: GalleryPhotoEdits? }
    private func controls(_ asset: PhotoAssetRecord) -> some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(nearby) { item in
                            Button { select(item.id) } label: {
                                PhotoThumbnailView(asset: item, targetSize: CGSize(width: 140, height: 140))
                                    .frame(width: 56, height: 56).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.id == selectedID ? Color.white : Color.clear, lineWidth: 3))
                            }.id(item.id).accessibilityLabel("\(item.mediaTitle) from \(item.dateLabel)")
                                .accessibilityAddTraits(item.id == selectedID ? .isSelected : [])
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 4)
                }.frame(height: 66)
                    .onChange(of: selectedID, initial: true) { _, id in proxy.scrollTo(id, anchor: .center) }
            }
            Text(asset.dateLabel).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
            HStack {
                if asset.source == .privateLibrary {
                    action(model.organization.items[asset.id]?.favorite == true ? "Remove Favorite" : "Favorite", model.organization.items[asset.id]?.favorite == true ? "heart.fill" : "heart") {
                        Task { await model.organize([asset.id], edit: .favorite(!(model.organization.items[asset.id]?.favorite ?? false))) }
                    }
                    if asset.kind == .photo { action("Edit Photo", "slider.horizontal.3") { showsEditor = true } }
                }
                action("Prepare to Share", "square.and.arrow.up") { model.beginShare([asset], profile: asset.decoyProfile) }
                action("Information", "info.circle") { showsInfo = true }
                if asset.source == .privateLibrary { action("Delete Item", "trash") { confirmsDelete = true } }
            }.disabled(model.isProcessing || model.isOrganizing)
        }.padding(.bottom, 8).background(.black)
    }
    private func action(_ label: String, _ icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: icon).font(.title3).frame(maxWidth: .infinity, minHeight: 44) }
            .foregroundStyle(.white).accessibilityLabel(label)
    }
    private func select(_ id: String) { image = nil; selectedID = id; zoomed = false }
    private func navigate(_ offset: Int) {
        let next = index + offset
        if visibleItems.indices.contains(next) { select(visibleItems[next].id) }
    }
}

struct GalleryZoomImage: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomed: Bool
    func makeCoordinator() -> Coordinator { Coordinator(zoomed: $zoomed) }
    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView()
        view.delegate = context.coordinator
        view.imageView.image = image
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2; view.addGestureRecognizer(tap)
        view.accessibilityLabel = "Photo. Pinch or double tap to zoom."
        return view
    }
    func updateUIView(_ view: ZoomView, context: Context) {
        context.coordinator.zoomed = $zoomed
        view.updateImage(image)
    }
    static func dismantleUIView(_ view: ZoomView, coordinator: Coordinator) { view.imageView.image = nil; view.delegate = nil }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var zoomed: Binding<Bool>
        init(zoomed: Binding<Bool>) { self.zoomed = zoomed }
        func viewForZooming(in view: UIScrollView) -> UIView? { (view as? ZoomView)?.imageView }
        func scrollViewDidZoom(_ view: UIScrollView) {
            zoomed.wrappedValue = view.zoomScale > 1.01
            (view as? ZoomView)?.centerImage()
        }
        @objc func doubleTap(_ tap: UITapGestureRecognizer) {
            guard let view = tap.view as? ZoomView else { return }
            if view.zoomScale > 1.01 { view.setZoomScale(1, animated: true) }
            else {
                let point = tap.location(in: view.imageView), scale: CGFloat = 3
                view.zoom(to: CGRect(x: point.x - view.bounds.width / scale / 2, y: point.y - view.bounds.height / scale / 2,
                    width: view.bounds.width / scale, height: view.bounds.height / scale), animated: true)
            }
        }
    }

    final class ZoomView: UIScrollView {
        let imageView = UIImageView()
        private var lastSize = CGSize.zero
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black; minimumZoomScale = 1; maximumZoomScale = 6
            showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
            imageView.contentMode = .scaleAspectFit; addSubview(imageView)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func updateImage(_ image: UIImage) {
            guard imageView.image !== image else { return }
            imageView.image = image
            lastSize = .zero
            setNeedsLayout()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != lastSize, let image = imageView.image, bounds.width > 0, bounds.height > 0 {
                lastSize = bounds.size; setZoomScale(1, animated: false)
                let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
                imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))
                contentSize = imageView.frame.size
            }
            centerImage()
        }
        func centerImage() {
            contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2),
                bottom: 0, right: 0)
        }
    }
}
