@preconcurrency import AVFoundation
@preconcurrency import Vision
import Foundation

struct GalleryCoverKeyframe: Equatable, Sendable {
    var time: Double
    var rect: CGRect
}

struct GalleryAudioRange: Equatable, Identifiable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var isValid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start && end <= 600 }
}

enum GalleryVideoTracking {
    enum TrackingError: LocalizedError {
        case lost
        var errorDescription: String? { "Tracking lost the selected area. Add or adjust covers manually, or choose a shorter clip." }
    }

    static func track(asset: AVAsset, cover: GalleryRedaction, start: Double, end: Double) async throws -> [GalleryCoverKeyframe] {
        guard cover.isValid, start.isFinite, end.isFinite, start >= 0, end > start, end <= 600 else { throw TrackingError.lost }
        guard cover.referenceTime >= start, cover.referenceTime <= end else { throw TrackingError.lost }
        let reference = cover.referenceTime
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        try Task.checkCancellation()
        let referenceFrame = try await generator.image(at: CMTime(seconds: min(reference, max(0, end - 0.001)), preferredTimescale: 60_000)).image
        var frames = [GalleryCoverKeyframe(time: reference, rect: cover.rect)]
        for direction in [-1.0, 1.0] {
            let handler = VNSequenceRequestHandler()
            let seed = cover.rect
            var observation = VNDetectedObjectObservation(boundingBox: CGRect(x: seed.minX, y: 1 - seed.maxY, width: seed.width, height: seed.height))
            let initialRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
            initialRequest.trackingLevel = .accurate
            #if targetEnvironment(simulator)
            initialRequest.usesCPUOnly = true
            #endif
            try handler.perform([initialRequest], on: referenceFrame)
            guard let initial = initialRequest.results?.first as? VNDetectedObjectObservation, initial.confidence >= 0.4 else { throw TrackingError.lost }
            observation = initial
            var time = reference
            while direction < 0 ? time > start : time < end {
                try Task.checkCancellation()
                time = direction < 0 ? max(start, time - 0.2) : min(end, time + 0.2)
                let result = try await generator.image(at: CMTime(seconds: min(time, max(0, end - 0.001)), preferredTimescale: 60_000))
                let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                request.trackingLevel = .accurate
                #if targetEnvironment(simulator)
                request.usesCPUOnly = true
                #endif
                try handler.perform([request], on: result.image)
                guard let found = request.results?.first as? VNDetectedObjectObservation, found.confidence >= 0.4 else { throw TrackingError.lost }
                observation = found
                let box = found.boundingBox
                let rect = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard GalleryRedaction(rect: rect).isValid else { throw TrackingError.lost }
                frames.append(.init(time: time, rect: rect))
            }
        }
        return frames.sorted { $0.time < $1.time }
    }
}

enum GalleryAudioRedaction {
    /// Copies decoded PCM before muting. Intervals use original source timestamps.
    static func mute(_ sample: CMSampleBuffer, ranges: [GalleryAudioRange]) throws -> CMSampleBuffer {
        guard !ranges.isEmpty else { return sample }
        guard ranges.allSatisfy(\.isValid), let original = CMSampleBufferGetDataBuffer(sample),
              let format = CMSampleBufferGetFormatDescription(sample),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM, description.mSampleRate.isFinite, description.mSampleRate > 0,
              description.mBytesPerFrame > 0, description.mBytesPerFrame <= 32 else { throw VideoSanitizer.VideoError.conversionFailed }
        let count = CMSampleBufferGetNumSamples(sample), bytesPerFrame = Int(description.mBytesPerFrame)
        let length = CMBlockBufferGetDataLength(original)
        guard count > 0, length == count * bytesPerFrame, length <= 4_194_304 else { throw VideoSanitizer.VideoError.conversionFailed }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard timestamp.isFinite else { throw VideoSanitizer.VideoError.conversionFailed }
        var data = Data(count: length)
        defer { data.resetBytes(in: data.startIndex..<data.endIndex) }
        let copied = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(original, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        guard copied == kCMBlockBufferNoErr else { throw VideoSanitizer.VideoError.conversionFailed }
        for range in ranges {
            let first = max(0, min(count, Int(floor((range.start - timestamp) * description.mSampleRate))))
            let last = max(0, min(count, Int(ceil((range.end - timestamp) * description.mSampleRate))))
            if last > first { data.resetBytes(in: (first * bytesPerFrame)..<(last * bytesPerFrame)) }
        }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr,
              let block else { throw VideoSanitizer.VideoError.conversionFailed }
        let replaced = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) }
        guard replaced == noErr else { throw VideoSanitizer.VideoError.conversionFailed }
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing) == noErr else { throw VideoSanitizer.VideoError.conversionFailed }
        var size = bytesPerFrame
        var output: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: count,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &output) == noErr,
              let output else { throw VideoSanitizer.VideoError.conversionFailed }
        return output
    }
}
