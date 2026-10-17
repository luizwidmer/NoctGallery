@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct GalleryTimelineData: Sendable {
    struct Frame: Identifiable, Sendable { let id: Int; let time: Double; let jpeg: Data }
    let frames: [Frame]
    let waveform: [Float]
    let frameRate: Double
}

enum GalleryTimelineAnalysis {
    static func load(_ asset: AVAsset) async throws -> GalleryTimelineData {
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 600 else { throw VideoSanitizer.VideoError.unsupported }
        let track = try await asset.loadTracks(withMediaType: .video).first
        let rate = Double(try await track?.load(.nominalFrameRate) ?? 30)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 180, height: 110)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
        var frames: [GalleryTimelineData.Frame] = []
        for i in 0..<12 {
            try Task.checkCancellation()
            let time = max(0, min(duration - 0.02, Double(i) * duration / 12))
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000)).image
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
            if CGImageDestinationFinalize(destination) { frames.append(.init(id: i, time: time, jpeg: data as Data)) }
        }
        let waveform = try await waveform(asset, duration: duration)
        return GalleryTimelineData(frames: frames, waveform: waveform, frameRate: rate.isFinite && rate > 0 ? min(240, rate) : 30)
    }

    private static func waveform(_ asset: AVAsset, duration: Double) async throws -> [Float] {
        try Task.checkCancellation()
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 8_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        var bins = Array(repeating: Float(0), count: 96), read = 0
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
                let length = CMBlockBufferGetDataLength(buffer)
                if length == 0 { continue }
                guard length <= 2_000_000, length.isMultiple(of: 2), read + length / 2 <= 4_810_000 else { reader.cancelReading(); return [] }
                var data = Data(count: length)
                let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
                guard status == kCMBlockBufferNoErr else { reader.cancelReading(); return [] }
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard start.isFinite else { reader.cancelReading(); return [] }
                data.withUnsafeBytes { bytes in
                    for i in 0..<(length / 2) {
                        let value = bytes.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)
                        let index = min(95, max(0, Int((start + Double(i) / 8_000) / duration * 96)))
                        bins[index] = max(bins[index], Float(abs(Int(value))) / 32_768)
                    }
                }
                read += length / 2
            }
            return reader.status == .completed ? bins : []
        } catch { reader.cancelReading(); throw error }
    }
}
