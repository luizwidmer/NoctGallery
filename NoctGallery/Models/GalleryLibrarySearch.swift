import Foundation

/// Explicit, reviewable scopes use stored media dates/types/albums, not guesses
/// about pixels. Nothing here enables an AI feature or stores search history.
struct GallerySearchScope: Equatable, Sendable {
    var subject: String
    var dateRange: DateInterval?
    var kind: GalleryMediaKind?
    var album: String?
    var labels: [String] = []

    static func parse(_ query: String, now: Date = Date(), calendar: Calendar = .current) -> Self {
        var value = Self(subject: String(query.prefix(512)))
        func remove(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: value.subject, range: NSRange(value.subject.startIndex..., in: value.subject)),
                  let range = Range(match.range, in: value.subject) else { return nil }
            let result = String(value.subject[range]); value.subject.replaceSubrange(range, with: " "); return result
        }
        let day = calendar.startOfDay(for: now)
        for (phrase, component, offset, count) in [
            ("last month", Calendar.Component.month, -1, 1), ("this month", .month, 0, 1),
            ("last week", .weekOfYear, -1, 1), ("this week", .weekOfYear, 0, 1),
            ("last year", .year, -1, 1), ("this year", .year, 0, 1),
            ("yesterday", .day, -1, 1), ("today", .day, 0, 1)
        ] {
            if remove("\\b(?:from\\s+|in\\s+)?" + phrase + "\\b") != nil,
               let interval = calendar.dateInterval(of: component, for: day),
               let start = calendar.date(byAdding: component, value: offset, to: interval.start),
               let end = calendar.date(byAdding: component, value: count, to: start) {
                value.dateRange = DateInterval(start: start, end: end); value.labels.append(phrase.capitalized); break
            }
        }
        if value.dateRange == nil, let yearText = remove("\\b(?:in|from)\\s+(?:19|20|21)[0-9]{2}\\b"),
           let year = Int(yearText.suffix(4)), let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
           let end = calendar.date(byAdding: .year, value: 1, to: start) {
            value.dateRange = DateInterval(start: start, end: end); value.labels.append(String(year))
        }
        if let type = remove("\\btype:(?:video|photo)s?\\b") {
            value.kind = type.lowercased().contains("video") ? .video : .photo
        } else if let type = remove("^\\s*(?:videos?|photos?|pictures?)\\b(?:\\s+of\\b)?") {
            value.kind = type.lowercased().contains("video") ? .video : .photo
        }
        if let kind = value.kind { value.labels.append(kind == .video ? "Videos" : "Photos") }
        if let album = remove("\\balbum:\"[^\"]{1,80}\"|\\balbum:[^\\s]{1,80}") {
            value.album = String(album.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            value.labels.append("Album: " + (value.album ?? ""))
        }
        value.subject = value.subject.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return value
    }

    func includes(_ asset: PhotoAssetRecord, organization: GalleryOrganization) -> Bool {
        if let kind, asset.kind != kind { return false }
        if let range = dateRange {
            guard let date = asset.creationDate, date >= range.start, date < range.end else { return false }
        }
        if let album {
            guard organization.albums.contains(where: { $0.name.compare(album, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && organization.items[asset.id]?.albumIDs.contains($0.id) == true }) else { return false }
        }
        return true
    }
}

struct GallerySearchHit: Sendable {
    let score: Int
    let reason: String
}

/// Only lives in memory while unlocked. Normalize text and expand aliases when
/// a record changes, rather than once per item on every keystroke or render.
struct GallerySearchIndex: Sendable {
    private struct Entry: Sendable {
        let document: GalleryVisualSearch.Matcher.Document
        let manualText: String
        let tags: [GalleryVisualTag]
    }
    private var entries: [String: Entry] = [:]
    private var matcher = GalleryVisualSearch.defaultMatcher
    private var interpretationEnabled = false

    mutating func update(assets: [PhotoAssetRecord], organization: GalleryOrganization, previous: GalleryOrganization? = nil) {
        let rebuild = previous == nil || previous?.albums != organization.albums
            || previous?.effectiveSearchAliasGroups != organization.effectiveSearchAliasGroups
            || previous?.visualSearchEnabled != organization.visualSearchEnabled || previous?.textSearchEnabled != organization.textSearchEnabled
        matcher = organization.searchMatcher
        interpretationEnabled = organization.visualSearchEnabled == true && organization.aiQueryInterpretationEnabled == true
        let ids = Set(assets.map(\.id))
        entries = entries.filter { ids.contains($0.key) }
        for asset in assets where rebuild || entries[asset.id] == nil || previous?.items[asset.id] != organization.items[asset.id] {
            guard organization.items[asset.id]?.deletedAt == nil else { entries.removeValue(forKey: asset.id); continue }
            let manual = organization.searchText(for: asset.id)
            let tags = organization.visualSearchEnabled == true ? organization.items[asset.id]?.visualTags ?? [] : []
            entries[asset.id] = Entry(document: matcher.prepare(text: manual + " " + asset.dateLabel + " " + asset.dimensionsLabel + " " + asset.mediaTitle, tags: tags),
                manualText: GalleryVisualSearch.normalized(manual), tags: tags)
        }
    }

    func search(_ query: String, interpretation: GallerySearchQueryPlan? = nil) -> [String: GallerySearchHit] {
        let q = GalleryVisualSearch.Matcher.Query(query)
        let plan = interpretationEnabled ? interpretation.flatMap { try? $0.validated() } : nil
        let required = plan?.required.map { $0.alternatives.map(GalleryVisualSearch.Matcher.Query.init) } ?? []
        let excluded = plan?.excluded.map { $0.alternatives.map(GalleryVisualSearch.Matcher.Query.init) } ?? []
        var result: [String: GallerySearchHit] = [:]
        for (id, entry) in entries {
            if excluded.contains(where: { $0.contains { matcher.matches($0, document: entry.document) } }) { continue }
            let literal = matcher.matches(q, document: entry.document)
            let inferred = plan != nil && !entry.tags.isEmpty && required.allSatisfy { group in group.contains { matcher.matches($0, document: entry.document) } }
            guard literal || inferred else { continue }
            if q.phrase.isEmpty { result[id] = .init(score: 0, reason: "Matches filters") }
            else if entry.manualText.contains(q.phrase) { result[id] = .init(score: 400, reason: "Saved tags, captions, notes or text") }
            else if let tag = entry.tags.filter({ GalleryVisualSearch.normalized($0.label) == q.phrase }).max(by: { $0.confidence < $1.confidence }) {
                result[id] = .init(score: 250 + Int(tag.confidence * 100), reason: "Recognized: \(tag.label)")
            } else if literal { result[id] = .init(score: 200, reason: "Media details, words or search synonyms") }
            else { result[id] = .init(score: 100, reason: "AI interpretation: \(plan?.displayTerms ?? "")") }
        }
        return result
    }
}
