@preconcurrency import AVFoundation
import Foundation
import CoreVideo
import UIKit

struct SanitizedVideo: Sendable {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: Double
}

/// A fresh video/audio-only composition feeds decoded frames and PCM into new
/// H.264/AAC encoders. No source metadata or ancillary tracks are remuxed.
enum VideoSanitizer {
    enum VideoError: LocalizedError {
        case unsupported, tooLarge, conversionFailed, metadataVerification
        var errorDescription: String? {
            switch self {
            case .unsupported: "This video cannot be processed. Choose a standard video up to 4K and 10 minutes."
            case .tooLarge: "The video exceeds the 1 GB processing limit."
            case .conversionFailed: "The video could not be converted. No share copy was created."
            case .metadataVerification: "The exported video failed its metadata privacy check."
            }
        }
    }

    static func sanitize(asset: AVAsset, to url: URL, profile: SyntheticMetadataProfile?,
                         includeAudio: Bool = true) async throws -> SanitizedVideo {
        try Task.checkCancellation()
        if let profile { _ = try profile.validated() }
        if let fileAsset = asset as? AVURLAsset, fileAsset.url.isFileURL {
            let size = try fileAsset.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= PrivateMediaStore.maximumBytes else { throw VideoError.tooLarge }
        }
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 600 else { throw VideoError.unsupported }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard tracks.count == 1, let track = tracks.first else { throw VideoError.unsupported }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frameRate = try await track.load(.nominalFrameRate)
        guard naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 0, naturalSize.height > 0,
              naturalSize.width * naturalSize.height <= 9_000_000, frameRate.isFinite,
              [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite)
        else { throw VideoError.unsupported }
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
              rect.width >= 1, rect.height >= 1, max(rect.width, rect.height) <= 16_384 else { throw VideoError.unsupported }
        let scale = min(1, 1920 / max(rect.width, rect.height), 1080 / min(rect.width, rect.height))
        let width = max(2, Int(rect.width * scale) / 2 * 2)
        let height = max(2, Int(rect.height * scale) / 2 * 2)
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: width, height: height)
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, min(30, frameRate > 0 ? frameRate.rounded() : 30))))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let normalized = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        layer.setTransform(normalized, at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw VideoError.unsupported }
        reader.add(videoOutput)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = metadata(profile)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard writer.canAdd(videoInput) else { throw VideoError.unsupported }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if includeAudio, let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: false,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2
            ])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 128_000,
                AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2
            ])
            guard reader.canAdd(output), writer.canAdd(input) else { throw VideoError.unsupported }
            reader.add(output)
            writer.add(input)
            audioOutput = output
            audioInput = input
        }

        do {
            guard writer.startWriting(), reader.startReading() else { throw VideoError.conversionFailed }
            writer.startSession(atSourceTime: .zero)
            var videoFinished = false
            var audioFinished = audioInput == nil
            var frameCount = 0
            while !videoFinished || !audioFinished {
                try Task.checkCancellation()
                guard writer.status == .writing, reader.status != .failed else { throw VideoError.conversionFailed }
                var advanced = false
                if !videoFinished, videoInput.isReadyForMoreMediaData {
                    if let sample = videoOutput.copyNextSampleBuffer() {
                        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw VideoError.conversionFailed }
                        CVBufferRemoveAllAttachments(buffer)
                        guard adaptor.append(buffer, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample)) else { throw VideoError.conversionFailed }
                        frameCount += 1
                    } else { videoFinished = true; videoInput.markAsFinished() }
                    advanced = true
                }
                if !audioFinished, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                    if let sample = audioOutput.copyNextSampleBuffer() {
                        CMRemoveAllAttachments(sample)
                        guard audioInput.append(sample) else { throw VideoError.conversionFailed }
                    } else { audioFinished = true; audioInput.markAsFinished() }
                    advanced = true
                }
                if !advanced { try await Task.sleep(for: .milliseconds(2)) }
            }
            guard frameCount > 0, reader.status == .completed else { throw VideoError.conversionFailed }
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw VideoError.conversionFailed }
            try QuickTimeTimestamps.rewrite(url, date: profile?.capturedAt)
            try MediaFileProtection.protect(url)
            try await verify(url: url, profile: profile)
            return SanitizedVideo(url: url, pixelWidth: width, pixelHeight: height, duration: duration.seconds)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    static func metadata(_ profile: SyntheticMetadataProfile?) -> [AVMetadataItem] {
        guard let profile else { return [] }
        var pairs: [(AVMetadataIdentifier, String)] = [
            (.quickTimeMetadataCreationDate, ISO8601DateFormatter().string(from: profile.capturedAt))
        ]
        if profile.includesEquipment {
            pairs.append((.quickTimeMetadataMake, profile.make)); pairs.append((.quickTimeMetadataModel, profile.model))
        }
        if let location = profile.location { pairs.append((.quickTimeMetadataLocationISO6709, MetadataForge.iso6709(location))) }
        return pairs.map { identifier, value in
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            return item
        }
    }

    static func verify(url: URL, profile: SyntheticMetadataProfile?) async throws {
        try QuickTimeTimestamps.verify(url, date: profile?.capturedAt)
        let asset = AVURLAsset(url: url)
        let expected = Dictionary(uniqueKeysWithValues: metadata(profile).compactMap { item -> (String, String)? in
            guard let id = item.identifier?.rawValue, let value = item.stringValue else { return nil }
            return (id, value)
        })
        var actual: [String: String] = [:]
        for format in try await asset.load(.availableMetadataFormats) {
            for item in try await asset.loadMetadata(for: format) {
                guard let id = item.identifier?.rawValue,
                      let value = try await item.load(.stringValue), expected[id] == value else { throw VideoError.metadataVerification }
                actual[id] = value
            }
        }
        guard actual == expected else { throw VideoError.metadataVerification }
        for track in try await asset.load(.tracks) {
            guard [.video, .audio].contains(track.mediaType),
                  try await track.load(.metadata).isEmpty else { throw VideoError.metadataVerification }
        }
    }

    static func thumbnail(url: URL) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let result = try await generator.image(at: .zero)
        guard let data = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.8) else { throw VideoError.conversionFailed }
        return data
    }
}
