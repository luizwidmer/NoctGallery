import Foundation

struct GalleryDeletedItem: Identifiable, Sendable {
    let asset: PhotoAssetRecord
    let deletedAt: Date
    var id: String { asset.id }
    var expiresAt: Date { deletedAt.addingTimeInterval(PrivateMediaStore.deletedRetention) }
    func daysRemaining(now: Date = Date()) -> Int {
        max(0, min(7, Int(ceil(expiresAt.timeIntervalSince(now) / 86_400))))
    }
}
