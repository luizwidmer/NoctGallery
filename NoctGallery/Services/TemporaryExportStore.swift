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
        guard ["heic", "jpg", "png"].contains(image.fileExtension) else {
            throw ExportError.invalidExportURL
        }
        try prepareDirectory()
        let filename = "shared-\(UUID().uuidString.lowercased()).\(image.fileExtension)"
        let url = rootURL.appendingPathComponent(filename, isDirectory: false)
        do {
            try image.data.write(to: url, options: [.atomic, .completeFileProtection])
            try applyProtection(to: url, permissions: 0o600)
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        return url
    }

    func remove(_ url: URL) throws {
        guard contains(url) else { throw ExportError.invalidExportURL }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func purgeAll() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let attributes = try fileManager.attributesOfItem(atPath: rootURL.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw ExportError.invalidExportURL
        }
        try applyProtection(to: rootURL, permissions: 0o700)
    }

    private func contains(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        // Only files returned by write are eligible, never a nested path that
        // could traverse a symbolic link into another directory.
        let candidate = url.standardizedFileURL
        return candidate.deletingLastPathComponent().path == rootURL.standardizedFileURL.path
            && candidate.lastPathComponent.hasPrefix("shared-")
    }

    private func applyProtection(to url: URL, permissions: Int) throws {
        try fileManager.setAttributes([
            .protectionKey: FileProtectionType.complete,
            .posixPermissions: permissions
        ], ofItemAtPath: url.path)
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }
}
