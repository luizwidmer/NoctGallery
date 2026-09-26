import Foundation

struct GalleryAlbum: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
}

struct GalleryItemOrganization: Codable, Equatable, Sendable {
    var favorite = false
    var albumIDs: Set<UUID> = []
    var tags: [String] = []
}

/// Kept inside the encrypted vault, never in preferences or a system search index.
struct GalleryOrganization: Codable, Equatable, Sendable {
    var version = 1
    var albums: [GalleryAlbum] = []
    var items: [String: GalleryItemOrganization] = [:]

    func validated() throws -> Self {
        guard version == 1, albums.count <= 200, items.count <= 50_000,
              Set(albums.map(\.id)).count == albums.count,
              albums.allSatisfy({ Self.validName($0.name) }) else { throw PrivateMediaStore.StoreError.invalidRecord }
        let albumIDs = Set(albums.map(\.id))
        for (id, item) in items {
            guard UUID(uuidString: id)?.uuidString.lowercased() == id,
                  item.albumIDs.isSubset(of: albumIDs), item.tags.count <= 32,
                  Set(item.tags).count == item.tags.count,
                  item.tags.allSatisfy({ Self.validName($0, maximum: 40) }) else { throw PrivateMediaStore.StoreError.invalidRecord }
        }
        return self
    }

    static func validName(_ value: String, maximum: Int = 80) -> Bool {
        !value.isEmpty && value.count <= maximum && value.utf8.count <= maximum * 4
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    static func tags(from text: String) throws -> [String] {
        guard text.utf8.count <= 8_192 else { throw PrivateMediaStore.StoreError.invalidRecord }
        let values = Array(Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard values.count <= 32, values.allSatisfy({ validName($0, maximum: 40) }) else { throw PrivateMediaStore.StoreError.invalidRecord }
        return values
    }

    func searchText(for id: String) -> String {
        guard let item = items[id] else { return "" }
        return (item.tags + albums.filter { item.albumIDs.contains($0.id) }.map(\.name)).joined(separator: " ")
    }
}

enum GalleryOrganizationEdit: Sendable {
    case favorite(Bool)
    case addToAlbum(UUID)
    case removeFromAlbum(UUID)
    case tags([String])
}
