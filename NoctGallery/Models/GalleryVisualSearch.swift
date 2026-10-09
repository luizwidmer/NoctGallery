import Foundation

struct GalleryVisualTag: Codable, Equatable, Sendable {
    let label: String
    let confidence: Float
    var isValid: Bool {
        GalleryOrganization.validName(label, maximum: 80) && !GalleryVisualSearch.normalized(label).isEmpty
            && confidence.isFinite && (0...1).contains(confidence)
    }
}

struct GallerySearchAliasGroup: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var terms: [String]

    static func parse(_ text: String) throws -> [String] {
        guard text.utf8.count <= 8_192 else { throw GallerySearchAliasError.invalidTerms }
        var seen: Set<String> = []
        let terms = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { seen.insert(GalleryVisualSearch.normalized($0)).inserted }
        try validate(terms)
        return terms
    }

    static func validate(_ terms: [String]) throws {
        guard (2...12).contains(terms.count), terms.allSatisfy({
            GalleryOrganization.validName($0, maximum: 80) && !GalleryVisualSearch.queryWords($0).isEmpty
        }), Set(terms.map(GalleryVisualSearch.normalized)).count == terms.count else { throw GallerySearchAliasError.invalidTerms }
    }
}

enum GallerySearchAliasError: LocalizedError {
    case invalidTerms, tooManyGroups, duplicateTerm(String), missingGroup
    var errorDescription: String? {
        switch self {
        case .invalidTerms: "Use 2–12 different terms, separated by commas; up to 80 characters each."
        case .tooManyGroups: "Keep up to 100 synonym groups."
        case .duplicateTerm(let term): "“\(term)” already belongs to another group. Edit that group to add a synonym."
        case .missingGroup: "This synonym group has changed. Open it again before saving."
        }
    }
}

enum GallerySearchAliasEdit: Sendable {
    case save(GallerySearchAliasGroup, replacing: UUID? = nil), delete(UUID), restoreDefaults
}

enum GalleryVisualSearch {
    // Labels come from the on-device classifier. Aliases improve everyday queries
    // without inventing classifications or sending private images to a service.
    static let defaultAliasGroups: [GallerySearchAliasGroup] = [
        ["headphones", "headphone", "headset", "headsets", "earphones", "earbuds", "fone", "fones", "fones de ouvido"],
        ["dog", "dogs", "puppy", "puppies", "cachorro", "cachorros"],
        ["cat", "cats", "kitten", "kittens", "gato", "gatos"],
        ["bicycle", "bike", "bikes", "bicicleta"],
        ["car", "cars", "automobile", "automobiles", "carro", "carros"],
        ["computer", "computers", "pc", "laptop", "notebook", "computador"],
        ["beach", "beaches", "seaside", "praia"],
        ["coffee", "cappuccino", "espresso", "café"],
        ["mountain", "mountains", "montanha", "montanhas"],
        ["flower", "flowers", "flor", "flores"]
    ].map { GallerySearchAliasGroup(terms: $0) }
    private static let stopWords: Set<String> = ["a", "an", "the", "of", "with", "my", "in", "on", "at", "photo", "photos", "picture", "pictures", "show", "me", "all", "de", "do", "da", "dos", "das", "com", "um", "uma", "foto", "fotos"]
    static let defaultMatcher = Matcher(groups: defaultAliasGroups)

    static func validateAliasGroups(_ groups: [GallerySearchAliasGroup]) throws {
        guard groups.count <= 100, Set(groups.map(\.id)).count == groups.count else { throw GallerySearchAliasError.tooManyGroups }
        var seen: Set<String> = []
        for group in groups {
            try GallerySearchAliasGroup.validate(group.terms)
            for term in group.terms where !seen.insert(normalized(term)).inserted { throw GallerySearchAliasError.duplicateTerm(term) }
        }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func queryWords(_ value: String) -> [String] {
        normalized(value).split(separator: " ").map(String.init).filter { !stopWords.contains($0) }
    }

    static func matches(_ query: String, text: String, tags: [GalleryVisualTag]) -> Bool {
        defaultMatcher.matches(query, text: text, tags: tags)
    }

    struct Matcher: Sendable {
        private var aliasesByLabel: [String: Set<String>] = [:]
        init(groups: [GallerySearchAliasGroup]) {
            for group in groups {
                let terms = Set(group.terms.map(normalized))
                for term in terms { aliasesByLabel[term] = terms }
            }
        }
        func matches(_ query: String, text: String, tags: [GalleryVisualTag]) -> Bool {
            let q = normalized(String(query.prefix(512)))
            guard !q.isEmpty else { return true }
            let ordinary = normalized(text)
            if ordinary.contains(q) { return true }
            let visualWords = Set(tags.flatMap { tag in
                let label = normalized(tag.label)
                return (aliasesByLabel[label] ?? [label]).flatMap { $0.split(separator: " ").map(String.init) }
            })
            let tokens = queryWords(q)
            guard !tokens.isEmpty else { return false }
            let textWords = Set(ordinary.split(separator: " ").map(String.init))
            return tokens.allSatisfy { textWords.contains($0) || visualWords.contains($0) }
        }
    }
}
