@preconcurrency import AVFoundation
import Foundation

/// Session graph mutations and capture completion state belong to one queue.
/// The preview layer is the only external consumer of the capture session.
final class PrivateCameraEngine: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "NoctGallery.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var movieContinuation: CheckedContinuation<URL, Error>?
    private var recordingCancelled = false
    private var configured = false

    enum CameraError: LocalizedError {
        case unavailable, permission, busy, captureFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: "A camera is unavailable on this device. The private gallery still works without one."
            case .permission: "Camera access is required. Enable it in iOS Settings."
            case .busy: "Wait for the current capture to finish."
            case .captureFailed: "The capture could not be saved."
            }
        }
    }

    func start() async throws {
        try await perform {
            if !self.configured {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraError.unavailable }
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                self.session.sessionPreset = .hd1920x1080
                guard self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput),
                      self.session.canAddOutput(self.movieOutput) else { throw CameraError.unavailable }
                self.session.addInput(input)
                self.session.addOutput(self.photoOutput)
                self.session.addOutput(self.movieOutput)
                self.videoInput = input
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                self.movieOutput.maxRecordedDuration = CMTime(seconds: 600, preferredTimescale: 600)
                self.movieOutput.maxRecordedFileSize = Int64(PrivateMediaStore.maximumBytes)
                self.movieOutput.metadata = []
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop(cancelRecording: Bool = true) async {
        try? await perform {
            if self.movieOutput.isRecording {
                self.recordingCancelled = cancelRecording
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func flip() async throws {
        try await perform {
            guard self.photoContinuation == nil, self.movieContinuation == nil else { throw CameraError.busy }
            let position: AVCaptureDevice.Position = self.videoInput?.device.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { throw CameraError.unavailable }
            let new = try AVCaptureDeviceInput(device: device)
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            let old = self.videoInput
            if let old { self.session.removeInput(old) }
            guard self.session.canAddInput(new) else {
                if let old, self.session.canAddInput(old) { self.session.addInput(old) }
                throw CameraError.unavailable
            }
            self.session.addInput(new)
            self.videoInput = new
        }
    }

    func photo(rotation: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning else { continuation.resume(throwing: CameraError.unavailable); return }
                guard self.photoContinuation == nil, self.movieContinuation == nil else { continuation.resume(throwing: CameraError.busy); return }
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .quality
                if let connection = self.photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
                    connection.videoRotationAngle = rotation
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func record(to url: URL, rotation: CGFloat, audio: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard self.session.isRunning else { throw CameraError.unavailable }
                    guard self.movieContinuation == nil, self.photoContinuation == nil else { throw CameraError.busy }
                    self.session.beginConfiguration()
                    if let old = self.audioInput { self.session.removeInput(old); self.audioInput = nil }
                    if audio {
                        guard let device = AVCaptureDevice.default(for: .audio) else {
                            self.session.commitConfiguration(); throw CameraError.unavailable
                        }
                        do {
                            let input = try AVCaptureDeviceInput(device: device)
                            guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                            self.session.addInput(input)
                            self.audioInput = input
                        } catch { self.session.commitConfiguration(); throw error }
                    }
                    self.session.commitConfiguration()
                    if let connection = self.movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
                        connection.videoRotationAngle = rotation
                    }
                    self.recordingCancelled = false
                    self.movieContinuation = continuation
                    self.movieOutput.startRecording(to: url, recordingDelegate: self)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func finishRecording() async { try? await perform { if self.movieOutput.isRecording { self.movieOutput.stopRecording() } } }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        queue.async {
            let continuation = self.photoContinuation
            self.photoContinuation = nil
            if let error { continuation?.resume(throwing: error) }
            else if let data { continuation?.resume(returning: data) }
            else { continuation?.resume(throwing: CameraError.captureFailed) }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let continuation = self.movieContinuation
            self.movieContinuation = nil
            if self.recordingCancelled { continuation?.resume(throwing: CancellationError()) }
            else if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                continuation?.resume(throwing: error)
            } else { continuation?.resume(returning: outputFileURL) }
        }
    }

    private func perform(_ action: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { do { try action(); continuation.resume() } catch { continuation.resume(throwing: error) } }
        }
    }
}
