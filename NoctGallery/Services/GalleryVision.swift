@preconcurrency import Vision
@preconcurrency import CoreImage
import Foundation

enum GalleryVision {
    #if targetEnvironment(simulator)
    private static let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    #endif

    static func perform(_ requests: [VNRequest], in image: CGImage) throws {
        try Task.checkCancellation()
        guard image.width <= 8_192, image.height <= 8_192 else { throw ImageSanitizer.SanitizationError.invalidConfiguration }
        #if targetEnvironment(simulator)
        // Both inference and image preprocessing need a supported simulator path.
        for request in requests {
            for (stage, devices) in try request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [.ciContext: context])
        #else
        let handler = VNImageRequestHandler(cgImage: image)
        #endif
        try handler.perform(requests)
        try Task.checkCancellation()
    }
}
