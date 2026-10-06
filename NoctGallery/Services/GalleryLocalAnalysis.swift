@preconcurrency import Vision
import CoreGraphics
import Foundation

enum GalleryLocalAnalysis {
    static func text(in image: CGImage) throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").prefix(16_000))
    }

    static func similarGroups(_ images: [(String, CGImage)], exactPairs: Set<String>) throws -> [GalleryDuplicateGroup] {
        var prints: [(String, VNFeaturePrintObservation)] = []
        for (id, image) in images.prefix(300) {
            try Task.checkCancellation()
            let request = VNGenerateImageFeaturePrintRequest()
            #if targetEnvironment(simulator)
            request.usesCPUOnly = true
            #endif
            try VNImageRequestHandler(cgImage: image).perform([request])
            if let print = request.results?.first as? VNFeaturePrintObservation { prints.append((id, print)) }
        }
        var groups: [GalleryDuplicateGroup] = []
        for i in prints.indices {
            for j in prints.indices where j > i {
                try Task.checkCancellation()
                if exactPairs.contains(pairKey(prints[i].0, prints[j].0)) { continue }
                var distance: Float = 0
                try prints[i].1.computeDistance(&distance, to: prints[j].1)
                if distance.isFinite, distance < 0.25 {
                    groups.append(.init(itemIDs: [prints[i].0, prints[j].0], exact: false))
                    if groups.count >= 100 { return groups }
                }
            }
        }
        return groups
    }

    static func pairKey(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: ":") }
}
