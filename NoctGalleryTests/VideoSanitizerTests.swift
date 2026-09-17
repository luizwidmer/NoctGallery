@preconcurrency import AVFoundation
import CoreVideo
import XCTest
@testable import NoctGallery

final class VideoSanitizerTests: XCTestCase {
    func testCleanVideoReencodesAndRemovesSourceMetadataAndHeaderDates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try MediaFileProtection.prepareDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.mov")
        try await videoFixture(source)
        let output = directory.appendingPathComponent("clean.mov")
        let result = try await VideoSanitizer.sanitize(asset: AVURLAsset(url: source), to: output, profile: nil)
        XCTAssertEqual(result.pixelWidth, 64)
        XCTAssertEqual(result.pixelHeight, 48)
        XCTAssertGreaterThan(result.duration, 0.5)
        try await VideoSanitizer.verify(url: output, profile: nil)
        try QuickTimeTimestamps.verify(output, date: nil)
        XCTAssertFalse(try Data(contentsOf: output).containsSubsequence(Data("private-camera-identifier".utf8)))
        let thumbnail = try await VideoSanitizer.thumbnail(url: output)
        XCTAssertFalse(thumbnail.isEmpty)
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        let descriptions = try await XCTUnwrap(tracks.first).load(.formatDescriptions)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(descriptions.first)), kCMVideoCodecType_H264)
    }

    func testVideoDecoyMetadataAndContainerDatesAgree() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try MediaFileProtection.prepareDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mov")
        try await videoFixture(source)
        let profile = SyntheticMetadataProfile(equipmentID: "x100v", scene: .shade,
            capturedAt: Date(timeIntervalSince1970: 1_740_000_000), location: DecoyLocation.places[0])
        let output = directory.appendingPathComponent("decoy.mov")
        _ = try await VideoSanitizer.sanitize(asset: AVURLAsset(url: source), to: output, profile: profile)
        try await VideoSanitizer.verify(url: output, profile: profile)
        try QuickTimeTimestamps.verify(output, date: profile.capturedAt)
        let bytes = try Data(contentsOf: output)
        XCTAssertFalse(bytes.containsSubsequence(Data("private-camera-identifier".utf8)))
        XCTAssertTrue(bytes.containsSubsequence(Data("FUJIFILM".utf8)))
        XCTAssertTrue(bytes.containsSubsequence(Data(MetadataForge.iso6709(profile.location!).utf8)))
    }

    func testMalformedContainerTimestampRewriteIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let malformed = Data([0, 0, 0, 2]) + Data("moov".utf8)
        try malformed.write(to: url)
        XCTAssertThrowsError(try QuickTimeTimestamps.rewrite(url, date: nil))
        XCTAssertEqual(try Data(contentsOf: url), malformed)
    }

    func testAudioIsReencodedToAACAndCanBeOmitted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try MediaFileProtection.prepareDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.mov")
        try await videoFixture(source)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<48_000 {
            let sample = Float(sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.1)
            channels[0][frame] = sample
            channels[1][frame] = sample
        }
        let audioURL = directory.appendingPathComponent("sound.caf")
        let audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try audioFile.write(from: buffer)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: source)
        let audioAsset = AVURLAsset(url: audioURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let audioTrack = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        let duration = try await videoAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        try videoTrack.insertTimeRange(range, of: XCTUnwrap(videoTracks.first), at: .zero)
        try audioTrack.insertTimeRange(range, of: XCTUnwrap(audioTracks.first), at: .zero)
        let output = directory.appendingPathComponent("with-audio.mov")
        _ = try await VideoSanitizer.sanitize(asset: composition, to: output, profile: nil)
        let resultTracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)
        XCTAssertEqual(resultTracks.count, 1)
        let descriptions = try await XCTUnwrap(resultTracks.first).load(.formatDescriptions)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(descriptions.first)), kAudioFormatMPEG4AAC)
        let silent = directory.appendingPathComponent("silent.mov")
        _ = try await VideoSanitizer.sanitize(asset: composition, to: silent, profile: nil, includeAudio: false)
        let silentTracks = try await AVURLAsset(url: silent).loadTracks(withMediaType: .audio)
        XCTAssertTrue(silentTracks.isEmpty)
    }

    func testRotationBecomesPixelsAndCancellationLeavesNoCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try MediaFileProtection.prepareDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("portrait.mov")
        try await videoFixture(source, rotated: true)
        let output = directory.appendingPathComponent("normalized.mov")
        let result = try await VideoSanitizer.sanitize(asset: AVURLAsset(url: source), to: output, profile: nil)
        XCTAssertEqual(result.pixelWidth, 48)
        XCTAssertEqual(result.pixelHeight, 64)
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        let transform = try await XCTUnwrap(tracks.first).load(.preferredTransform)
        XCTAssertEqual(transform, .identity)
        let cancelled = directory.appendingPathComponent("cancelled.mov")
        let task = Task {
            try await VideoSanitizer.sanitize(asset: AVURLAsset(url: source), to: cancelled, profile: nil)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled conversion succeeded") } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.path))
    }

    private func videoFixture(_ url: URL, rotated: Bool = false) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let secret = AVMutableMetadataItem()
        secret.identifier = .quickTimeMetadataMake
        secret.value = "private-camera-identifier" as NSString
        writer.metadata = [secret]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48
        ])
        if rotated { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw VideoSanitizer.VideoError.conversionFailed }
                try await Task.sleep(for: .milliseconds(2))
            }
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32(index * 8), CVPixelBufferGetBytesPerRow(buffer) * 48)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}

private extension Data {
    func containsSubsequence(_ other: Data) -> Bool { range(of: other) != nil }
}
