@preconcurrency import AVFoundation
import SwiftUI

struct PrivateCameraView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = PrivateCameraEngine()
    @State private var ready = false
    @State private var kind = GalleryMediaKind.photo
    @State private var sound = true
    @State private var busy = false
    @State private var recording = false
    @State private var recordingStarted = Date()
    @State private var message: String?
    @State private var cameraError: String?
    @State private var showSettings = false
    @State private var captureTask: Task<Void, Never>?
    @State private var capabilities = PrivateCameraEngine.Controls()
    @State private var zoom = 1.0
    @State private var exposure = 0.0
    @State private var timer = 0
    @State private var countdown: Int?
    @State private var grid = false
    @State private var flash = AVCaptureDevice.FlashMode.off
    @State private var showsControls = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if ready {
                CameraPreview(session: engine.session) { point in Task { try? await engine.focus(at: point) } }.ignoresSafeArea()
                if grid {
                    GeometryReader { proxy in
                        Path { path in
                            for part in [1.0 / 3, 2.0 / 3] {
                                path.move(to: CGPoint(x: proxy.size.width * part, y: 0)); path.addLine(to: CGPoint(x: proxy.size.width * part, y: proxy.size.height))
                                path.move(to: CGPoint(x: 0, y: proxy.size.height * part)); path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * part))
                            }
                        }.stroke(.white.opacity(0.5), lineWidth: 1)
                    }.ignoresSafeArea().allowsHitTesting(false)
                }
            } else if let cameraError {
                ContentUnavailableView("Camera Unavailable", systemImage: "camera",
                    description: Text(cameraError)).foregroundStyle(.white)
            } else { ProgressView("Starting camera…").tint(.white).foregroundStyle(.white) }
            VStack(spacing: 0) {
                topBar
                Spacer()
                if let message {
                    Text(message).font(.callout.weight(.medium)).padding(12)
                        .background(.black.opacity(0.7), in: Capsule()).padding(.horizontal)
                }
                if let countdown {
                    Text("\(countdown)").font(.system(size: 64, weight: .bold)).padding()
                    Button("Cancel Timer") { captureTask?.cancel() }
                } else if busy && !recording {
                    ProgressView(model.processingMessage ?? "Preparing capture…")
                        .tint(.white).padding(14).background(.black.opacity(0.7), in: Capsule())
                }
                if showsControls && !busy { adjustmentControls }
                controls
            }
            .foregroundStyle(.white)
        }
        .task { await start() }
        .onDisappear {
            captureTask?.cancel()
            Task { await engine.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { captureTask?.cancel(); Task { await engine.stop() }; dismiss() }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                CameraMetadataSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
            }
        }
        .onChange(of: zoom) { _, _ in adjustCamera() }
        .onChange(of: exposure) { _, _ in adjustCamera() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("Close camera")
            VStack(alignment: .leading, spacing: 3) {
                Text("Private Camera").font(.headline)
                Label(model.cameraMetadataMode.title, systemImage: model.cameraMetadataMode == .clean ? "shield.checkered" : "theatermasks")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
            Button { showsControls.toggle() } label: { Image(systemName: "camera.aperture").frame(width: 44, height: 44) }
                .disabled(busy || !ready).accessibilityLabel("Camera controls")
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                .disabled(busy).accessibilityLabel("Camera metadata settings")
        }
        .padding(.horizontal, 10).background(.black.opacity(0.6))
    }

    private var controls: some View {
        VStack(spacing: 18) {
            if recording {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(max(0, context.date.timeIntervalSince(recordingStarted))).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit().font(.headline).foregroundStyle(.red)
                }
            }
            Picker("Capture mode", selection: $kind) {
                Text("Photo").tag(GalleryMediaKind.photo)
                Text("Video").tag(GalleryMediaKind.video)
            }
            .pickerStyle(.segmented).frame(maxWidth: 250).disabled(busy).colorScheme(.dark)
            HStack {
                if kind == .video {
                    Button { sound.toggle() } label: { Image(systemName: sound ? "mic.fill" : "mic.slash.fill").frame(width: 50, height: 50) }
                        .disabled(busy).accessibilityLabel(sound ? "Disable microphone" : "Enable microphone")
                } else { Color.clear.frame(width: 50, height: 50) }
                Spacer(minLength: 20)
                Button {
                    if recording { Task { await engine.finishRecording() } }
                    else { capture() }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                        if recording { RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30) }
                        else { Circle().fill(kind == .video ? .red : .white).frame(width: 64, height: 64) }
                    }
                }
                .disabled(!ready || (busy && !recording))
                .accessibilityLabel(recording ? "Stop recording" : kind == .photo ? "Take private photo" : "Record private video")
                .accessibilityIdentifier("camera.capture")
                Spacer(minLength: 20)
                Button { Task { do { try await engine.flip(); await updateControls() } catch { message = error.localizedDescription } } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 50, height: 50)
                }
                .disabled(busy || !ready).accessibilityLabel("Switch camera")
            }
            .frame(maxWidth: 380)
            Text("Saved only to Private · Photos access isn’t needed")
                .font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
        }
        .padding(22).frame(maxWidth: .infinity).background(.black.opacity(0.75))
    }

    private var adjustmentControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Zoom \(zoom.formatted(.number.precision(.fractionLength(1))))×").font(.caption).frame(width: 90)
                Slider(value: $zoom, in: capabilities.minimumZoom...max(capabilities.minimumZoom + 0.01, capabilities.maximumZoom))
                    .accessibilityLabel("Camera zoom").disabled(capabilities.maximumZoom <= capabilities.minimumZoom)
            }
            HStack {
                Text("EV \(exposure.formatted(.number.precision(.fractionLength(1))))").font(.caption).frame(width: 90)
                Slider(value: $exposure, in: capabilities.minimumExposure...max(capabilities.minimumExposure + 0.01, capabilities.maximumExposure), step: 0.1)
                    .accessibilityLabel("Exposure adjustment")
            }
            HStack {
                Toggle("Grid", isOn: $grid)
                Picker("Timer", selection: $timer) { Text("Off").tag(0); Text("3s").tag(3); Text("10s").tag(10) }.pickerStyle(.menu)
                if capabilities.flashAvailable && kind == .photo {
                    Picker("Flash", selection: $flash) { Text("Off").tag(AVCaptureDevice.FlashMode.off); Text("Auto").tag(AVCaptureDevice.FlashMode.auto); Text("On").tag(AVCaptureDevice.FlashMode.on) }.pickerStyle(.menu)
                }
            }.font(.caption)
            Text("Tap the preview to focus and meter exposure.").font(.caption2).foregroundStyle(.white.opacity(0.8))
        }.padding(16).background(.black.opacity(0.75)).colorScheme(.dark)
    }

    private func updateControls() async {
        if let value = try? await engine.controls() { capabilities = value; zoom = max(value.minimumZoom, 1); exposure = 0; flash = .off }
    }

    private func adjustCamera() { if ready { Task { try? await engine.adjust(zoom: zoom, exposure: exposure) } } }

    private func start() async {
        var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard authorized else { cameraError = PrivateCameraEngine.CameraError.permission.localizedDescription; return }
        do { try Task.checkCancellation(); try await engine.start(); ready = true; await updateControls() }
        catch { cameraError = error.localizedDescription }
    }

    private var rotation: CGFloat {
        switch UIDevice.current.orientation {
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .portraitUpsideDown: 270
        default: 90
        }
    }

    private func capture() {
        guard !busy else { return }
        busy = true
        message = nil
        captureTask = Task {
            var rawVideo: URL?
            do {
                if timer > 0 {
                    for remaining in stride(from: timer, through: 1, by: -1) {
                        countdown = remaining
                        try await Task.sleep(for: .seconds(1))
                    }
                    countdown = nil
                }
                try Task.checkCancellation()
                let profile = try model.captureProfile()
                if kind == .photo {
                    let data = try await engine.photo(rotation: rotation, flash: flash)
                    try Task.checkCancellation()
                    try await model.saveCapture(photo: data, video: nil, profile: profile)
                } else {
                    if sound {
                        var granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .audio) }
                        guard granted else { throw NSError(domain: "NoctGallery.Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Allow microphone access in Settings, or turn off the microphone to record a silent video."]) }
                    }
                    let session = await model.workStore.currentSession()
                    let url = try await model.workStore.allocate(extension: "mov", session: session)
                    rawVideo = url
                    recording = true
                    recordingStarted = Date()
                    _ = try await engine.record(to: url, rotation: rotation, audio: sound)
                    recording = false
                    try Task.checkCancellation()
                    try await model.saveCapture(photo: nil, video: url, profile: profile)
                }
                message = "Saved to Private"
            } catch { if !(error is CancellationError) { message = error.localizedDescription } }
            if let rawVideo { try? await model.workStore.remove(rawVideo) }
            recording = false
            countdown = nil
            busy = false
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let focus: (CGPoint) -> Void
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.focus = focus
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) { view.focus = focus }
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var focus: ((CGPoint) -> Void)?
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let point = touches.first?.location(in: self) else { return }
            focus?(previewLayer.captureDevicePointConverted(fromLayerPoint: point))
            let ring = CALayer(); ring.frame = CGRect(x: point.x - 25, y: point.y - 25, width: 50, height: 50)
            ring.borderWidth = 2; ring.borderColor = UIColor.systemYellow.cgColor; ring.cornerRadius = 8
            layer.addSublayer(ring)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ring.removeFromSuperlayer() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            let portrait = bounds.height > bounds.width
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(portrait ? 90 : 0) {
                connection.videoRotationAngle = portrait ? 90 : 0
            }
        }
    }
}
