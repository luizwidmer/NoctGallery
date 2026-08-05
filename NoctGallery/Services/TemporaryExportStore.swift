import Foundation

actor TemporaryExportStore {
    enum ExportError: LocalizedError {
        case invalidExportURL

        var errorDescription: String? {
            "The temporary export location is invalid."
        }
    }

    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.temporaryDirectory
            .appendingPathComponent("NoctGalleryShareExports", isDirectory: true)
    }

    func write(_ image: SanitizedImage) throws -> URL {
        try prepareDirectory()
        let filename = "shared-\(UUID().uuidString.lowercased()).\(image.fileExtension)"
        let url = rootURL.appendingPathComponent(filename, isDirectory: false)
        try image.data.write(to: url, options: [.atomic, .completeFileProtection])
        try applyProtection(to: url)
        return url
    }

    func remove(_ url: URL) throws {
        guard contains(url) else { throw ExportError.invalidExportURL }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func purgeAll() throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        try fileManager.removeItem(at: rootURL)
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try applyProtection(to: rootURL)
    }

    private func contains(_ url: URL) -> Bool {
        let root = rootURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate.hasPrefix(root + "/")
    }

    private func applyProtection(to url: URL) throws {
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }
}
