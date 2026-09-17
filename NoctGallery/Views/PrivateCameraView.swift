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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if ready {
                CameraPreview(session: engine.session).ignoresSafeArea()
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
                if busy && !recording {
                    ProgressView(model.processingMessage ?? "Preparing capture…")
                        .tint(.white).padding(14).background(.black.opacity(0.7), in: Capsule())
                }
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
                Button { Task { do { try await engine.flip() } catch { message = error.localizedDescription } } } label: {
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

    private func start() async {
        var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard authorized else { cameraError = PrivateCameraEngine.CameraError.permission.localizedDescription; return }
        do { try Task.checkCancellation(); try await engine.start(); ready = true }
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
                let profile = try model.captureProfile()
                if kind == .photo {
                    let data = try await engine.photo(rotation: rotation)
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
            busy = false
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            let portrait = bounds.height > bounds.width
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(portrait ? 90 : 0) {
                connection.videoRotationAngle = portrait ? 90 : 0
            }
        }
    }
}
