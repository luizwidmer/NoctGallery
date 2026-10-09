import Foundation

struct GallerySearchConcept: Codable, Equatable, Sendable {
    var alternatives: [String]
}

struct GallerySearchQueryPlan: Codable, Equatable, Sendable {
    var required: [GallerySearchConcept]
    var excluded: [GallerySearchConcept]
    var hasUnverifiedDetails: Bool

    func validated() throws -> Self {
        guard required.count <= 6, excluded.count <= 6, !(required.isEmpty && excluded.isEmpty),
              (required + excluded).allSatisfy({ concept in
                  (1...4).contains(concept.alternatives.count) && concept.alternatives.allSatisfy {
                      GalleryOrganization.validName($0, maximum: 80) && !GalleryVisualSearch.queryWords($0).isEmpty
                  } && Set(concept.alternatives.map(GalleryVisualSearch.normalized)).count == concept.alternatives.count
              }) else { throw GalleryQueryInterpretationError.invalidResult }
        let excludedTerms = Set(excluded.flatMap(\.alternatives).map(GalleryVisualSearch.normalized))
        guard !required.contains(where: { Set($0.alternatives.map(GalleryVisualSearch.normalized)).isSubset(of: excludedTerms) }) else {
            throw GalleryQueryInterpretationError.invalidResult
        }
        return self
    }

    var displayTerms: String {
        let included = required.compactMap { $0.alternatives.first }.joined(separator: " + ")
        let removed = excluded.compactMap { $0.alternatives.first }.joined(separator: ", ")
        return removed.isEmpty ? included : "\(included.isEmpty ? "All tagged photos" : included) · excluding \(removed)"
    }

    var matchScopeDescription: String {
        "Matching objects, scenes and saved text. Actions, positions and other details aren't verified."
    }
}

struct GalleryInterpretedSearch: Equatable, Sendable {
    let query: String
    let plan: GallerySearchQueryPlan
}

struct GalleryQueryInterpreterAvailability: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unsupported, intelligenceDisabled, modelNotReady, ready
    }
    let state: State
    let message: String

    var isSupported: Bool { state != .unsupported }
    var isAvailable: Bool { state == .ready }
}

enum GalleryQueryInterpretationError: Error, Equatable {
    case unavailable, unsupportedLanguage, invalidQuery, invalidResult, timedOut
}

protocol GallerySearchQueryInterpreting: Sendable {
    var availability: GalleryQueryInterpreterAvailability { get }
    func interpret(_ query: String, labels: [String]) async throws -> GallerySearchQueryPlan
}

/// Search operators have deterministic semantics. The language model only maps
/// each subject phrase to an English label; it never decides AND/OR/negation.
struct GalleryQueryPhrases: Equatable, Sendable {
    let required: [[String]]
    let excluded: [String]

    init(_ query: String) throws {
        func replace(_ pattern: String, in text: String, with replacement: String) -> String {
            text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        func terms(_ text: String, separator: String) throws -> [String] {
            let values = text.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard values.allSatisfy({ !GalleryVisualSearch.queryWords($0).isEmpty }) else { throw GalleryQueryInterpretationError.invalidQuery }
            return values
        }
        var text = replace(#"\b(without|excluding|not|sem|exceto)\b"#, in: query, with: " NOT ")
        text = replace(#"^\s*no\s+"#, in: text, with: " NOT ")
        text = replace(#"\b(or|ou)\b"#, in: text, with: " OR ")
        text = replace(#"\b(and|e|com(?!\s+que\b)|surrounded by|next to|beside|near)\b"#, in: text, with: " AND ")
        let negativeParts = text.components(separatedBy: " NOT ")
        let positive = negativeParts[0]
        // Mixed AND/OR needs grouping that this compact search UI doesn't expose.
        guard !(positive.contains(" AND ") && positive.contains(" OR ")) else { throw GalleryQueryInterpretationError.invalidQuery }
        if positive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { required = [] }
        else if positive.contains(" OR ") { required = [try terms(positive, separator: " OR ")] }
        else { required = try terms(positive, separator: " AND ").map { [$0] } }
        excluded = try negativeParts.dropFirst().flatMap { try terms(replace(#"\s+(AND|OR)\s+"#, in: $0, with: " | "), separator: " | ") }
        guard required.count <= 6, required.allSatisfy({ $0.count <= 4 }), excluded.count <= 6,
              required.reduce(0, { $0 + $1.count }) + excluded.count <= 6,
              !(required.isEmpty && excluded.isEmpty) else { throw GalleryQueryInterpretationError.invalidQuery }
    }
}
