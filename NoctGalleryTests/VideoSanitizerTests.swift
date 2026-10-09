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

        let trimmed = directory.appendingPathComponent("trimmed.mov")
        _ = try await VideoSanitizer.sanitize(asset: composition, to: trimmed, profile: nil,
            edits: .init(trimStart: 0.2, trimEnd: 0.7, removeAudio: true))
        let inspected = try await GalleryExportInspection.inspect(url: trimmed, kind: .video)
        XCTAssertEqual(inspected.duration, 0.5, accuracy: 0.06)
        XCTAssertFalse(inspected.hasAudio)
        let trimmedAudio = directory.appendingPathComponent("trimmed-audio.mov")
        _ = try await VideoSanitizer.sanitize(asset: composition, to: trimmedAudio, profile: nil,
            edits: .init(trimStart: 0.2, trimEnd: 0.7))
        let audible = try await GalleryExportInspection.inspect(url: trimmedAudio, kind: .video)
        XCTAssertEqual(audible.duration, 0.5, accuracy: 0.06)
        XCTAssertTrue(audible.hasAudio)

        let selective = directory.appendingPathComponent("selective-audio.mov")
        _ = try await VideoSanitizer.sanitize(asset: composition, to: selective, profile: nil,
            edits: .init(silencedRanges: [.init(start: 0.25, end: 0.65)]))
        let middle = try await audioLevel(selective, from: 0.35, to: 0.55)
        let before = try await audioLevel(selective, from: 0.05, to: 0.15)
        let after = try await audioLevel(selective, from: 0.8, to: 0.9)
        XCTAssertLessThan(middle, 0.001, "The encoded AAC track must silence the selected interval")
        XCTAssertGreaterThan(before, 0.04, "Audio before the interval must remain audible")
        XCTAssertGreaterThan(after, 0.04, "Audio after the interval must remain audible")
    }

    func testMovingCoverFollowsSourceTimeAfterTrimming() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try MediaFileProtection.prepareDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mov")
        try await videoFixture(source)
        let left = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let right = CGRect(x: 0.65, y: 0.1, width: 0.2, height: 0.2)
        let cover = GalleryRedaction(rect: left, keyframes: [.init(time: 0, rect: left), .init(time: 1, rect: right)])
        let output = directory.appendingPathComponent("moving-cover.mov")
        _ = try await VideoSanitizer.sanitize(asset: AVURLAsset(url: source), to: output, profile: nil,
            edits: .init(redactions: [cover], trimStart: 0.2, trimEnd: 0.9))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        for outputTime in [0.1, 0.5] {
            let frame = try await generator.image(at: CMTime(seconds: outputTime, preferredTimescale: 600)).image
            let context = try XCTUnwrap(CGContext(data: nil, width: frame.width, height: frame.height, bitsPerComponent: 8,
                bytesPerRow: frame.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            let samples = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let expected = cover.rect(at: outputTime + 0.2)
            let center = (Int(expected.midY * Double(frame.height)) * frame.width + Int(expected.midX * Double(frame.width))) * 4
            let uncovered = ((frame.height - 4) * frame.width + 4) * 4
            XCTAssertGreaterThan(samples[center], 60, "Blur must retain color instead of inserting black")
            XCTAssertLessThan(samples[center], 200)
            XCTAssertLessThan(abs(Int(samples[center]) - Int(samples[center + 8])), 25,
                              "Blur must smooth the area at its original timestamp after trimming")
            XCTAssertGreaterThan(samples[uncovered], 30, "Content outside the cover must survive")
            XCTAssertGreaterThan(abs(Int(samples[uncovered]) - Int(samples[uncovered + 8])), 60)
        }
    }

    func testAutomaticTrackingFollowsMovingTexturedArea() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try MediaFileProtection.prepareDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("tracking.mov")
        try await trackingFixture(source)
        let seed = CGRect(x: 0.15, y: 0.3, width: 0.25, height: 1.0 / 3.0)
        let frames = try await GalleryVideoTracking.track(asset: AVURLAsset(url: source),
            cover: .init(rect: seed, referenceTime: 0.6), start: 0, end: 1.2)
        let first = try XCTUnwrap(frames.first), last = try XCTUnwrap(frames.last)
        XCTAssertEqual(first.time, 0, accuracy: 0.001)
        XCTAssertEqual(last.time, 1.2, accuracy: 0.001)
        XCTAssertLessThan(first.rect.minX, seed.minX - 0.025)
        XCTAssertGreaterThan(last.rect.minX, seed.minX + 0.025)
        XCTAssertEqual(last.rect.minY, seed.minY, accuracy: 0.06)
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

        let redacted = directory.appendingPathComponent("redacted.mov")
        _ = try await VideoSanitizer.sanitize(asset: AVURLAsset(url: source), to: redacted, profile: nil,
            edits: .init(redactions: [.init(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.25))], trimStart: 0.2, trimEnd: 0.8))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: redacted))
        let frame = try await generator.image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
        let context = try XCTUnwrap(CGContext(data: nil, width: frame.width, height: frame.height, bitsPerComponent: 8,
            bytesPerRow: frame.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        let samples = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let topLeft = (2 * frame.width + 2) * 4
        let bottomRight = ((frame.height - 3) * frame.width + frame.width - 3) * 4
        XCTAssertGreaterThan(samples[topLeft], 60)
        XCTAssertLessThan(samples[topLeft], 200)
        XCTAssertLessThan(abs(Int(samples[topLeft]) - Int(samples[topLeft + 8])), 25, "Blur follows upright coordinates after rotation")
        XCTAssertGreaterThan(samples[bottomRight], 20, "Uncovered content must survive")
        XCTAssertGreaterThan(abs(Int(samples[bottomRight]) - Int(samples[bottomRight - 8])), 60)
        let cancelled = directory.appendingPathComponent("cancelled.mov")
        let task = Task {
            try await VideoSanitizer.sanitize(asset: AVURLAsset(url: source), to: cancelled, profile: nil)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled conversion succeeded") } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.path))
    }

    private func audioLevel(_ url: URL, from start: Double, to end: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 48_000),
            duration: CMTime(seconds: end - start, preferredTimescale: 48_000))
        let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(tracks.first), outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var squareSum = 0.0, count = 0
        while let sample = output.copyNextSampleBuffer() {
            let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let result = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            XCTAssertEqual(result, kCMBlockBufferNoErr)
            for value in bytes { squareSum += Double(value) * Double(value); count += 1 }
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertGreaterThan(count, 0)
        return sqrt(squareSum / Double(max(1, count)))
    }

    private func trackingFixture(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 200, AVVideoHeightKey: 150
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 200, kCVPixelBufferHeightKey as String: 150,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(input)
        XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for index in 0..<14 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw VideoSanitizer.VideoError.conversionFailed }
                try await Task.sleep(for: .milliseconds(2))
            }
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            memset(base, 230, stride * 150)
            let originX = 18 + index * 2
            for y in 45..<95 {
                for x in originX..<(originX + 50) {
                    let offset = y * stride + x * 4
                    let value: UInt8 = ((x - originX) / 5 + (y - 45) / 5).isMultiple(of: 2) ? 20 : 100
                    base[offset] = value; base[offset + 1] = value; base[offset + 2] = value; base[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
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
                let values = base.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<48 { for x in 0..<64 {
                    let value = UInt8((x / 2 + y / 2).isMultiple(of: 2) ? 20 + index * 2 : 220 - index * 2)
                    let offset = y * stride + x * 4
                    values[offset] = value; values[offset + 1] = value; values[offset + 2] = value; values[offset + 3] = 255
                } }
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
