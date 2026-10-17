import Foundation

struct GalleryImportOutcome: Identifiable {
    enum Status { case imported, failed, cancelled }
    let id = UUID()
    let name: String
    let status: Status
    var message: String?
    var source: URL?
}

/// Filenames, provider URLs and errors are temporary, never written to disk.
/// Locking clears the report and all retry handles.
struct GalleryImportReport: Identifiable {
    let id = UUID()
    var outcomes: [GalleryImportOutcome]
    var incoming = false
    var succeeded: Int { outcomes.filter { $0.status == .imported }.count }
    var retryURLs: [URL] { outcomes.filter { $0.status != .imported }.compactMap(\.source) }
}
