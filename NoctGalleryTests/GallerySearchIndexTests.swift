import XCTest
@testable import NoctGallery

final class GallerySearchIndexTests: XCTestCase {
    func testExplicitScopesUseActualDatesKindsAndAlbumMembership() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: .init(year: 2026, month: 10, day: 17)))
        let parsed = GallerySearchScope.parse("photos of coffee from last month album:\"Weekend Away\"", now: now, calendar: calendar)
        XCTAssertEqual(parsed.subject, "coffee"); XCTAssertEqual(parsed.kind, .photo); XCTAssertEqual(parsed.album, "Weekend Away")
        let start = try XCTUnwrap(parsed.dateRange?.start), end = try XCTUnwrap(parsed.dateRange?.end)
        XCTAssertEqual(calendar.component(.month, from: start), 9); XCTAssertEqual(calendar.component(.month, from: end), 10)
        let photo = asset(date: start), album = GalleryAlbum(id: UUID(), name: "Weekend Away")
        var organization = GalleryOrganization(); organization.albums = [album]
        organization.items[photo.id] = .init(albumIDs: [album.id])
        XCTAssertTrue(parsed.includes(photo, organization: organization))
        var outside = PhotoAssetRecord(localIdentifier: photo.id, creationDate: end, modificationDate: nil,
            pixelWidth: 960, pixelHeight: 720, kind: .photo, source: .privateLibrary)
        XCTAssertFalse(parsed.includes(outside, organization: organization), "Date end must be exclusive")
        outside = photo; outside.kind = .video; XCTAssertFalse(parsed.includes(outside, organization: organization))
        organization.items[photo.id]?.albumIDs = []
        XCTAssertFalse(parsed.includes(photo, organization: organization))
        let year = GallerySearchScope.parse("type:video bicycle in 2024", now: now, calendar: calendar)
        XCTAssertEqual(year.subject, "bicycle"); XCTAssertEqual(year.kind, .video)
        XCTAssertEqual(calendar.component(.year, from: try XCTUnwrap(year.dateRange?.start)), 2024)
        XCTAssertEqual(GallerySearchScope.parse("photosynthesis", now: now, calendar: calendar).subject, "photosynthesis")
        XCTAssertLessThanOrEqual(GallerySearchScope.parse(String(repeating: "x", count: 1_000)).subject.count, 512)
        let a = asset(date: start), b = asset(date: end)
        XCTAssertEqual(GalleryLibraryQuery.sorted([a, b], by: .relevance, sizes: [:]).map(\.id), [b.id, a.id],
            "An empty Best matches search must browse newest first")
    }

    func testRankingParityMutableAliasesInterpretationAndIncrementalChanges() throws {
        let assets = (0..<5).map { _ in asset() }
        var organization = GalleryOrganization(); organization.visualSearchEnabled = true; organization.aiQueryInterpretationEnabled = true
        organization.items[assets[0].id] = .init(tags: ["headphones"])
        organization.items[assets[1].id] = .init(visualTags: [.init(label: "headphones", confidence: 0.9)])
        organization.items[assets[2].id] = .init(visualTags: [.init(label: "bicycle", confidence: 0.9)])
        organization.items[assets[3].id] = .init(visualTags: [.init(label: "dog", confidence: 0.9)])
        organization.items[assets[4].id] = .init(visualTags: [.init(label: "dog", confidence: 0.9), .init(label: "people", confidence: 0.9)])
        var index = GallerySearchIndex(); index.update(assets: assets, organization: organization)
        let hits = index.search("headphones")
        XCTAssertGreaterThan(try XCTUnwrap(hits[assets[0].id]?.score), try XCTUnwrap(hits[assets[1].id]?.score))
        XCTAssertTrue(try XCTUnwrap(hits[assets[1].id]?.reason).contains("headphones"))
        for query in ["headphones", "bicycle", "dog", "bike", "people", "coffee", "dog people"] {
            XCTAssertEqual(Set(index.search(query).keys), Set(assets.filter { organization.matches(query, id: $0.id) }.map(\.id)), query)
        }
        let plan = GallerySearchQueryPlan(required: [.init(alternatives: ["dog"])], excluded: [.init(alternatives: ["people"])], hasUnverifiedDetails: false)
        XCTAssertEqual(Set(index.search("pets without humans", interpretation: plan).keys), [assets[3].id])
        var changed = organization
        changed.searchAliasGroups = [.init(terms: ["headphones", "listening gear"])]
        index.update(assets: assets, organization: changed, previous: organization)
        XCTAssertEqual(Set(index.search("listening gear").keys), [assets[1].id], "Object synonyms expand recognized labels; saved text stays literal")
        var next = changed; next.items[assets[2].id]?.tags = ["coffee"]
        next.items[assets[3].id]?.deletedAt = Date()
        index.update(assets: assets, organization: next, previous: changed)
        XCTAssertNotNil(index.search("coffee")[assets[2].id]); XCTAssertNil(index.search("dog")[assets[3].id])
        var off = next; off.visualSearchEnabled = false
        index.update(assets: assets, organization: off, previous: next)
        XCTAssertTrue(index.search("pets without humans", interpretation: plan).isEmpty)
        index.update(assets: [], organization: .init(), previous: off)
        XCTAssertTrue(index.search("").isEmpty)
    }

    func testOneAndTenThousandItemSearchBenchmarkMatchesExistingMatcher() throws {
        var measurements: [[String: Any]] = []
        for count in [1_000, 10_000] {
            let assets = (0..<count).map { _ in asset() }
            var organization = GalleryOrganization(); organization.visualSearchEnabled = true
            let labels = ["headphones", "bicycle", "dog", "coffee", "sunglasses", "mountain", "laptop", "plant"]
            for (n, asset) in assets.enumerated() {
                organization.items[asset.id] = .init(tags: ["weekend", "set\(n % 20)"], visualTags: [.init(label: labels[n % labels.count], confidence: 0.9)])
            }
            let begin = ProcessInfo.processInfo.systemUptime
            var index = GallerySearchIndex(); index.update(assets: assets, organization: organization)
            let indexed = ProcessInfo.processInfo.systemUptime
            let queries = ["headphones", "bicycle", "coffee"]
            var expected: [Set<String>] = []
            let matcher = organization.searchMatcher
            let baselineStart = ProcessInfo.processInfo.systemUptime
            for query in queries {
                expected.append(Set(assets.filter { item in
                    matcher.matches(query, text: organization.searchText(for: item.id) + " " + item.dateLabel + " " + item.dimensionsLabel + " " + item.mediaTitle,
                        tags: organization.items[item.id]?.visualTags ?? [])
                }.map(\.id)))
            }
            let baselineEnd = ProcessInfo.processInfo.systemUptime
            let actual = queries.map { Set(index.search($0).keys) }
            let end = ProcessInfo.processInfo.systemUptime
            XCTAssertEqual(actual, expected)
            measurements.append(["items": count, "queries": queries.count, "indexBuildMilliseconds": (indexed - begin) * 1_000,
                "baselineMilliseconds": (baselineEnd - baselineStart) * 1_000, "indexedMilliseconds": (end - baselineEnd) * 1_000])
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "library-search-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func asset(date: Date = Date()) -> PhotoAssetRecord {
        PhotoAssetRecord(localIdentifier: UUID().uuidString.lowercased(), creationDate: date, modificationDate: nil,
            pixelWidth: 960, pixelHeight: 720, kind: .photo, duration: 0, source: .privateLibrary)
    }
}
