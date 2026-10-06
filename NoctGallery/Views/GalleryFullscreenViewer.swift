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
    private var index: Int { items.firstIndex { $0.id == selectedID } ?? 0 }
    private var asset: PhotoAssetRecord { items[index] }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("\(index + 1) of \(items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    Button("Previous", systemImage: "chevron.left") { navigate(-1) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).disabled(index == 0)
                    Spacer(minLength: 0)
                    Text(asset.dateLabel).font(.footnote).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Button("Next", systemImage: "chevron.right") { navigate(1) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).disabled(index == items.count - 1)
                }.padding(.horizontal, 16).foregroundStyle(.white).background(.black)
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .task(id: selectedID) {
                image = nil; error = nil; zoomed = false
                guard asset.kind == .photo else { return }
                do {
                    let loaded = try await model.shareEditorImage(for: asset, photoEdits: model.organization.items[asset.id]?.photoEdits, maximumDimension: 4_096)
                    if !Task.isCancelled { image = loaded }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onChange(of: model.privateGeneration) { _, _ in image = nil; dismiss() }
            .onDisappear { image = nil }
        }
    }

    private func navigate(_ offset: Int) {
        let next = index + offset
        if items.indices.contains(next) { image = nil; selectedID = items[next].id }
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
    func updateUIView(_ view: ZoomView, context: Context) { context.coordinator.zoomed = $zoomed }
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
