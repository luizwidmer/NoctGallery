import Foundation

struct GalleryAlbum: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
}

struct GalleryItemOrganization: Codable, Equatable, Sendable {
    var favorite = false
    var albumIDs: Set<UUID> = []
    var tags: [String] = []
    var caption: String?
    var notes: String?
    var recognizedText: String?
    var visualTags: [GalleryVisualTag]?
    var photoEdits: GalleryPhotoEdits?
}

/// Kept inside the encrypted vault, never in preferences or a system search index.
struct GalleryOrganization: Codable, Equatable, Sendable {
    var version = 1
    var albums: [GalleryAlbum] = []
    var items: [String: GalleryItemOrganization] = [:]
    var textSearchEnabled: Bool?
    var visualSearchEnabled: Bool?
    var searchAliasGroups: [GallerySearchAliasGroup]?
    var aiQueryInterpretationEnabled: Bool?

    var effectiveSearchAliasGroups: [GallerySearchAliasGroup] { searchAliasGroups ?? GalleryVisualSearch.defaultAliasGroups }
    var searchMatcher: GalleryVisualSearch.Matcher {
        searchAliasGroups.map { GalleryVisualSearch.Matcher(groups: $0) } ?? GalleryVisualSearch.defaultMatcher
    }

    func validated() throws -> Self {
        if let groups = searchAliasGroups { try GalleryVisualSearch.validateAliasGroups(groups) }
        guard version == 1, albums.count <= 200, items.count <= 50_000,
              Set(albums.map(\.id)).count == albums.count,
              albums.allSatisfy({ Self.validName($0.name) }) else { throw PrivateMediaStore.StoreError.invalidRecord }
        let albumIDs = Set(albums.map(\.id))
        for (id, item) in items {
            guard UUID(uuidString: id)?.uuidString.lowercased() == id,
                  item.albumIDs.isSubset(of: albumIDs), item.tags.count <= 32,
                  Set(item.tags).count == item.tags.count,
                  item.tags.allSatisfy({ Self.validName($0, maximum: 40) }),
                  item.caption.map({ $0.count <= 512 && $0.utf8.count <= 2_048 }) != false,
                  item.notes.map({ $0.count <= 8_000 && $0.utf8.count <= 32_000 }) != false,
                  item.recognizedText.map({ $0.count <= 16_000 && $0.utf8.count <= 64_000 }) != false,
                  item.visualTags.map({ $0.count <= 24 && $0.allSatisfy(\.isValid) && Set($0.map { GalleryVisualSearch.normalized($0.label) }).count == $0.count }) != false,
                  item.photoEdits.map({ (try? $0.validated()) != nil }) != false else { throw PrivateMediaStore.StoreError.invalidRecord }
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
        var parts = item.tags + albums.filter { item.albumIDs.contains($0.id) }.map(\.name)
        parts += [item.caption, item.notes].compactMap { $0 }
        if textSearchEnabled == true, let text = item.recognizedText { parts.append(text) }
        return parts.joined(separator: " ")
    }

    func matches(_ query: String, id: String, extraText: String = "", using matcher: GalleryVisualSearch.Matcher? = nil,
                 interpretation: GallerySearchQueryPlan? = nil) -> Bool {
        let matcher = matcher ?? searchMatcher, text = searchText(for: id) + " " + extraText
        let tags = visualSearchEnabled == true ? (items[id]?.visualTags ?? []) : []
        let literal = matcher.matches(query, text: text, tags: tags)
        guard let plan = interpretation, visualSearchEnabled == true, aiQueryInterpretationEnabled == true, items[id]?.visualTags != nil,
              (try? plan.validated()) != nil else { return literal }
        func matchesConcept(_ concept: GallerySearchConcept) -> Bool {
            concept.alternatives.contains { matcher.matches($0, text: text, tags: tags) }
        }
        guard !plan.excluded.contains(where: matchesConcept) else { return false }
        return literal || plan.required.allSatisfy(matchesConcept)
    }

    /// A bounded vocabulary of actual labels, with no item IDs, counts, captions,
    /// notes or media supplied to the text model. Literal search covers all tags.
    var visualSearchVocabulary: [String] {
        guard visualSearchEnabled == true, aiQueryInterpretationEnabled == true else { return [] }
        var counts: [String: Int] = [:]
        for item in items.values { for tag in item.visualTags ?? [] where tag.isValid { counts[tag.label, default: 0] += 1 } }
        return counts.keys.sorted {
            counts[$0] == counts[$1] ? $0 < $1 : counts[$0, default: 0] > counts[$1, default: 0]
        }.prefix(256).sorted()
    }
}

enum GalleryOrganizationEdit: Sendable {
    case favorite(Bool)
    case addToAlbum(UUID)
    case removeFromAlbum(UUID)
    case tags([String])
    case description(caption: String, notes: String)
    case photoEdits(GalleryPhotoEdits?)
    case removeVisualTag(String)
}
