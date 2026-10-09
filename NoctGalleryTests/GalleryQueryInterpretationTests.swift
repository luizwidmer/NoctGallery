import ImageIO
import XCTest
@testable import NoctGallery

@MainActor
final class GalleryQueryInterpretationTests: XCTestCase {
    func testPlansCombineSubjectsAlternativesAndExclusionsWithoutAliases() throws {
        var organization = GalleryOrganization(); organization.visualSearchEnabled = true; organization.aiQueryInterpretationEnabled = true; organization.searchAliasGroups = []
        let dog = UUID().uuidString.lowercased(), bicycle = UUID().uuidString.lowercased(), personWithDog = UUID().uuidString.lowercased()
        organization.items[dog] = .init(visualTags: [.init(label: "dog", confidence: 0.9)])
        organization.items[bicycle] = .init(visualTags: [.init(label: "bicycle", confidence: 0.9)])
        organization.items[personWithDog] = .init(visualTags: [.init(label: "people", confidence: 0.9), .init(label: "dog", confidence: 0.9)])
        let withoutPeople = try GallerySearchQueryPlan(required: [.init(alternatives: ["dog", "canine"])], excluded: [.init(alternatives: ["people", "person"])], hasUnverifiedDetails: false).validated()
        XCTAssertTrue(organization.matches("pets without humans", id: dog, interpretation: withoutPeople))
        XCTAssertFalse(organization.matches("pets without humans", id: personWithDog, interpretation: withoutPeople))
        XCTAssertFalse(organization.matches("pets without humans", id: bicycle, interpretation: withoutPeople))
        let either = GallerySearchQueryPlan(required: [.init(alternatives: ["dog", "bicycle"])], excluded: [], hasUnverifiedDetails: false)
        XCTAssertTrue(organization.matches("pets or bikes", id: dog, interpretation: either))
        XCTAssertTrue(organization.matches("pets or bikes", id: bicycle, interpretation: either))
        let both = GallerySearchQueryPlan(required: [.init(alternatives: ["dog"]), .init(alternatives: ["people"])], excluded: [], hasUnverifiedDetails: true)
        XCTAssertFalse(organization.matches("a pet beside a person", id: dog, interpretation: both))
        XCTAssertTrue(organization.matches("a pet beside a person", id: personWithDog, interpretation: both))
        let untagged = UUID().uuidString.lowercased(); organization.items[untagged] = .init()
        let excludedOnly = GallerySearchQueryPlan(required: [], excluded: [.init(alternatives: ["people"])], hasUnverifiedDetails: false)
        XCTAssertFalse(organization.matches("no humans", id: untagged, interpretation: excludedOnly), "Unknown images must not be assumed to exclude a subject")
        organization.visualSearchEnabled = false
        XCTAssertFalse(organization.matches("pets without humans", id: dog, interpretation: withoutPeople))
    }

    func testModelOutputBoundsAndNoEmptyPlanCanMatchEverything() throws {
        let bad = [
            GallerySearchQueryPlan(required: [], excluded: [], hasUnverifiedDetails: false),
            .init(required: [.init(alternatives: [])], excluded: [], hasUnverifiedDetails: false),
            .init(required: [.init(alternatives: ["dog", "DOG"])], excluded: [], hasUnverifiedDetails: false),
            .init(required: [.init(alternatives: ["\u{0}private"])], excluded: [], hasUnverifiedDetails: false),
            .init(required: [.init(alternatives: [String(repeating: "a", count: 81)])], excluded: [], hasUnverifiedDetails: false),
            .init(required: [.init(alternatives: (0..<5).map { "word\($0)" })], excluded: [], hasUnverifiedDetails: false),
            .init(required: (0..<7).map { .init(alternatives: ["word\($0)"]) }, excluded: [], hasUnverifiedDetails: false),
            .init(required: [.init(alternatives: ["dog"])], excluded: [.init(alternatives: ["dog"])], hasUnverifiedDetails: false)
        ]
        for plan in bad { XCTAssertThrowsError(try plan.validated()) }
        var organization = GalleryOrganization(); organization.visualSearchEnabled = true; organization.aiQueryInterpretationEnabled = true
        let id = UUID().uuidString.lowercased(); organization.items[id] = .init(visualTags: [.init(label: "dog", confidence: 0.9)])
        XCTAssertFalse(organization.matches("unrelated", id: id, interpretation: bad[0]))
    }

    func testDeterministicOperatorsAndAmbiguousOrOversizedQueries() throws {
        XCTAssertEqual(try GalleryQueryPhrases("coffee and croissant").required, [["coffee"], ["croissant"]])
        XCTAssertEqual(try GalleryQueryPhrases("café com croissant").required, [["café"], ["croissant"]])
        XCTAssertEqual(try GalleryQueryPhrases("dog or bicycle").required, [["dog", "bicycle"]])
        XCTAssertEqual(try GalleryQueryPhrases("cachorro ou bicicleta").required, [["cachorro", "bicicleta"]])
        let excluded = try GalleryQueryPhrases("a bicycle without people")
        XCTAssertEqual(excluded.required, [["a bicycle"]]); XCTAssertEqual(excluded.excluded, ["people"])
        XCTAssertEqual(try GalleryQueryPhrases("cachorros sem pessoas").excluded, ["pessoas"])
        XCTAssertEqual(try GalleryQueryPhrases("a lake surrounded by mountains").required, [["a lake"], ["mountains"]])
        for query in ["dog or", "dog and", "dog without", "dog or bicycle and people", "a and", "dog or cat or bicycle or coffee or lake",
                      "dog and cat and bicycle and coffee and lake and people and plant"] {
            XCTAssertThrowsError(try GalleryQueryPhrases(query), query)
        }
    }

    func testRealLocalModelUnderstandsDescriptionsPortugueseAndOrQueries() async throws {
        let interpreter = GalleryAIQueryInterpreter()
        try XCTSkipUnless(interpreter.availability.isAvailable, "Requires the real on-device Apple Intelligence model; run on the eligible native Mac or iPhone/iPad.")
        var organization = GalleryOrganization(); organization.visualSearchEnabled = true; organization.aiQueryInterpretationEnabled = true; organization.searchAliasGroups = []
        var ids: [String: String] = [:]
        for name in ["headphones", "sunglasses", "dog", "bicycle", "laptop", "coffee", "lake", "portrait"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let tags = try await Task.detached { try GalleryLocalAnalysis.visualTags(in: image) }.value
            let id = UUID().uuidString.lowercased(); ids[name] = id
            organization.items[id] = .init(visualTags: tags)
        }
        let cases: [(query: String, positive: [String], negative: [String])] = [
            ("the things you wear on your ears to hear music", ["headphones"], ["dog", "bicycle", "coffee"]),
            ("óculos de sol", ["sunglasses"], ["headphones", "dog", "coffee"]),
            ("um cachorro", ["dog"], ["bicycle", "laptop", "coffee"]),
            ("a bicycle without people", ["bicycle"], ["portrait", "dog", "laptop"]),
            ("coffee and croissant", ["coffee"], ["sunglasses", "dog", "bicycle"]),
            ("café com croissant", ["coffee"], ["headphones", "dog", "bicycle"]),
            ("a lake surrounded by mountains", ["lake"], ["laptop", "bicycle", "coffee"]),
            ("dog or bicycle", ["dog", "bicycle"], ["laptop", "coffee", "headphones"]),
            ("something with two wheels that I pedal", ["bicycle"], ["dog", "laptop", "coffee"]),
            ("the portable computer I type on", ["laptop"], ["dog", "bicycle", "coffee"]),
            ("cachorro ou bicicleta", ["dog", "bicycle"], ["laptop", "coffee", "headphones"]),
            ("bicicleta sem pessoas", ["bicycle"], ["portrait", "dog", "laptop"])
        ]
        var plans: [String: GallerySearchQueryPlan] = [:]
        for sample in cases {
            let plan: GallerySearchQueryPlan
            do { plan = try await interpreter.interpret(sample.query, labels: organization.visualSearchVocabulary) }
            catch { XCTFail("Failed to interpret '\(sample.query)': \(error)"); continue }
            plans[sample.query] = plan
            for photo in sample.positive {
                XCTAssertTrue(organization.matches(sample.query, id: try XCTUnwrap(ids[photo]), interpretation: plan), "\(sample.query) should find \(photo): \(plan)")
            }
            for photo in sample.negative {
                XCTAssertFalse(organization.matches(sample.query, id: try XCTUnwrap(ids[photo]), interpretation: plan), "\(sample.query) should exclude \(photo): \(plan)")
            }
        }
        for query in ["coffee and croissant", "café com croissant"] {
            XCTAssertEqual(try XCTUnwrap(plans[query]).required.count, 2, "Both explicitly requested objects must be required")
        }
        XCTAssertEqual(plans["a bicycle without people"]?.excluded, [.init(alternatives: ["people"])])
        XCTAssertEqual(plans["dog or bicycle"]?.required.count, 1)
        XCTAssertEqual(Set(plans["dog or bicycle"]?.required.first?.alternatives ?? []), ["dog", "bicycle"])
        for query in ["an electric guitar", "a spaceship"] {
            do {
                let plan = try await interpreter.interpret(query, labels: organization.visualSearchVocabulary)
                for id in ids.values { XCTAssertFalse(organization.matches(query, id: id, interpretation: plan), "Absent subject must not become an unrelated object: \(query)") }
            } catch GalleryQueryInterpretationError.invalidResult {
                // Rejected substitutions retain literal search and find no photos.
                for id in ids.values { XCTAssertFalse(organization.matches(query, id: id)) }
            }
        }
        XCTAssertTrue(try XCTUnwrap(plans["a lake surrounded by mountains"]).matchScopeDescription.contains("aren't verified"),
            "Always explain the matching scope, including when the model misses a requested relationship")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let attachment = XCTAttachment(data: try encoder.encode(plans), uniformTypeIdentifier: "public.json")
        attachment.name = "real-ai-query-interpretations"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testLatestQueryWinsAndLockCancelsInterpretationAndClearsItsState() async throws {
        let fixture = try await makeModel(interpreter: SlowInterpreter()); defer { fixture.cleanup() }
        let model = fixture.model
        let old = Task { await model.interpretSearchQuery("older request") }
        for _ in 0..<100 where model.interpretingSearchQuery == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.interpretingSearchQuery, "older request")
        let newer = Task { await model.interpretSearchQuery("newer request") }
        await old.value; await newer.value
        XCTAssertEqual(model.interpretedSearch?.query, "newer request")
        let next = Task { await model.interpretSearchQuery("pending request") }
        for _ in 0..<100 where model.interpretingSearchQuery == nil { try await Task.sleep(for: .milliseconds(10)) }
        await model.lockPrivate(); await next.value
        XCTAssertFalse(model.privateUnlocked); XCTAssertNil(model.interpretedSearch); XCTAssertNil(model.interpretingSearchQuery)
        XCTAssertNil(model.searchInterpretationMessage); XCTAssertTrue(model.organization.items.isEmpty)
        await model.interpretSearchQuery("sunglasses")
        XCTAssertNil(model.interpretedSearch)
    }

    func testUnavailableAndDisabledInterpreterKeepLiteralSearchAndSynonyms() async throws {
        let unavailable = try await makeModel(interpreter: UnavailableInterpreter()); defer { unavailable.cleanup() }
        await unavailable.model.interpretSearchQuery("something to hear music")
        XCTAssertNil(unavailable.model.interpretedSearch)
        XCTAssertEqual(unavailable.model.searchInterpretationMessage, "Local model unavailable; tags and synonyms still work.")
        XCTAssertTrue(unavailable.model.organization.matches("headset", id: unavailable.photoID))
        await unavailable.model.lockPrivate()

        let available = try await makeModel(interpreter: SlowInterpreter()); defer { available.cleanup() }
        await available.model.setAIQueryInterpretation(false)
        await available.model.interpretSearchQuery("headphones")
        XCTAssertNil(available.model.interpretedSearch); XCTAssertNil(available.model.searchInterpretationMessage)
        XCTAssertTrue(available.model.organization.matches("headset", id: available.photoID))
        await available.model.lockPrivate()
    }

    func testLiteralContextAndCustomSynonymsKeepTheirResultsWithoutCallingAI() async throws {
        let fixture = try await makeModel(interpreter: UnavailableInterpreter()); defer { fixture.cleanup() }
        await fixture.model.organize([fixture.photoID], edit: .description(caption: "", notes: "travel"))
        await fixture.model.interpretSearchQuery("headphones travel")
        XCTAssertNil(fixture.model.interpretedSearch); XCTAssertNil(fixture.model.searchInterpretationMessage)
        XCTAssertTrue(fixture.model.organization.matches("headphones travel", id: fixture.photoID))
        await fixture.model.interpretSearchQuery("headphones vacation")
        XCTAssertNil(fixture.model.interpretedSearch); XCTAssertNil(fixture.model.searchInterpretationMessage)
        XCTAssertFalse(fixture.model.organization.matches("headphones vacation", id: fixture.photoID))
        var aliases = try XCTUnwrap(fixture.model.organization.effectiveSearchAliasGroups.first { $0.terms.contains("headphones") })
        aliases.terms = ["headphones", "listening gear"]
        let saved = await fixture.model.editSearchAliases(.save(aliases, replacing: aliases.id))
        XCTAssertTrue(saved)
        await fixture.model.interpretSearchQuery("listening gear")
        XCTAssertNil(fixture.model.interpretedSearch); XCTAssertNil(fixture.model.searchInterpretationMessage)
        XCTAssertTrue(fixture.model.organization.matches("listening gear", id: fixture.photoID))
        await fixture.model.lockPrivate()
        XCTAssertTrue(fixture.model.queryVocabulary.isEmpty)
    }

    func testFreshAndLegacyVaultsKeepSmartFeaturesOffByDefault() async throws {
        let old = try JSONDecoder().decode(GalleryOrganization.self, from: Data("{\"version\":1,\"albums\":[],\"items\":{}}".utf8))
        for organization in [GalleryOrganization(), old] {
            XCTAssertFalse(organization.visualSearchEnabled == true)
            XCTAssertFalse(organization.aiQueryInterpretationEnabled == true)
            XCTAssertFalse(organization.textSearchEnabled == true)
            XCTAssertTrue(organization.visualSearchVocabulary.isEmpty)
        }
        let interpreter = MutableInterpreter(.ready)
        let fixture = try await makeModel(interpreter: interpreter, taggingEnabled: false, phrasesEnabled: nil)
        defer { fixture.cleanup() }
        let model = fixture.model
        XCTAssertTrue(model.showsSmartSearch); XCTAssertTrue(model.smartFeaturesAvailable)
        model.indexVisualTags()
        await model.interpretSearchQuery("something to hear music")
        await model.setAIQueryInterpretation(true)
        let photoURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "headphones", withExtension: "jpg"))
        await model.importFiles([photoURL])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.privateAssets.count, 2, model.errorMessage ?? "Expected a normal import with smart features off")
        XCTAssertFalse(model.isTagging)
        XCTAssertNil(model.organization.visualSearchEnabled); XCTAssertNil(model.organization.aiQueryInterpretationEnabled)
        XCTAssertTrue(model.organization.items.values.allSatisfy { $0.visualTags == nil })
        XCTAssertTrue(model.queryVocabulary.isEmpty); XCTAssertEqual(interpreter.calls, 0)
        await model.lockPrivate()

        var taggedLegacy = old; taggedLegacy.visualSearchEnabled = true
        taggedLegacy.items[fixture.photoID] = .init(visualTags: [.init(label: "headphones", confidence: 0.9)])
        let plan = GallerySearchQueryPlan(required: [.init(alternatives: ["headphones"])], excluded: [], hasUnverifiedDetails: false)
        XCTAssertFalse(taggedLegacy.matches("something to hear music", id: fixture.photoID, interpretation: plan), "An unset AI search preference must not interpret a query")
        XCTAssertTrue(taggedLegacy.visualSearchVocabulary.isEmpty)
    }

    func testUnsupportedDevicesHideSmartSearchAndRejectOptIns() async throws {
        let interpreter = MutableInterpreter(.unsupported)
        let fixture = try await makeModel(interpreter: interpreter, taggingEnabled: false, phrasesEnabled: nil)
        defer { fixture.cleanup() }
        let model = fixture.model
        XCTAssertFalse(model.showsSmartSearch); XCTAssertFalse(model.smartFeaturesAvailable)
        await model.setVisualSearch(true); await model.setAIQueryInterpretation(true)
        model.indexVisualTags(); await model.interpretSearchQuery("something to hear music")
        XCTAssertNil(model.organization.visualSearchEnabled); XCTAssertNil(model.organization.aiQueryInterpretationEnabled)
        XCTAssertFalse(model.isTagging); XCTAssertEqual(interpreter.calls, 0)
        await model.lockPrivate()
    }

    func testIntelligenceOffAndDownloadingKeepOptionsVisibleButInactive() async throws {
        for state in [GalleryQueryInterpreterAvailability.State.intelligenceDisabled, .modelNotReady] {
            let interpreter = MutableInterpreter(state)
            let fixture = try await makeModel(interpreter: interpreter, taggingEnabled: false, phrasesEnabled: nil)
            let model = fixture.model
            XCTAssertTrue(model.showsSmartSearch); XCTAssertFalse(model.smartFeaturesAvailable)
            await model.setVisualSearch(true); await model.setAIQueryInterpretation(true)
            model.indexVisualTags(); await model.interpretSearchQuery("something to hear music")
            XCTAssertNil(model.organization.visualSearchEnabled); XCTAssertNil(model.organization.aiQueryInterpretationEnabled)
            XCTAssertFalse(model.isTagging); XCTAssertEqual(interpreter.calls, 0)
            await model.lockPrivate(); fixture.cleanup()
        }
    }

    func testAIQueryOptInIsSeparateFromTaggingAndPersistsEncrypted() async throws {
        let interpreter = MutableInterpreter(.ready)
        let fixture = try await makeModel(interpreter: interpreter, phrasesEnabled: nil)
        defer { fixture.cleanup() }
        let model = fixture.model
        await model.setVisualSearch(true)
        await model.interpretSearchQuery("something to hear music")
        XCTAssertNil(model.organization.aiQueryInterpretationEnabled); XCTAssertEqual(interpreter.calls, 0)
        XCTAssertTrue(model.queryVocabulary.isEmpty)
        await model.setAIQueryInterpretation(true)
        XCTAssertTrue(model.organization.aiQueryInterpretationEnabled == true)
        XCTAssertEqual(model.queryVocabulary, ["headphones"])
        await model.interpretSearchQuery("something to hear music")
        XCTAssertNotNil(model.interpretedSearch); XCTAssertEqual(interpreter.calls, 1)
        await model.lockPrivate(); model.lock.activate()
        let unlocked = await model.unlockPrivate(); XCTAssertTrue(unlocked)
        XCTAssertTrue(model.organization.aiQueryInterpretationEnabled == true)
        await model.setAIQueryInterpretation(false)
        await model.interpretSearchQuery("something to hear music")
        XCTAssertNil(model.interpretedSearch); XCTAssertEqual(interpreter.calls, 1)
        XCTAssertTrue(model.queryVocabulary.isEmpty)
        await model.lockPrivate()
    }

    func testAvailabilityLossCancelsPendingAIAndRefreshesControls() async throws {
        let interpreter = MutableInterpreter(.ready)
        let fixture = try await makeModel(interpreter: interpreter)
        defer { fixture.cleanup() }
        let model = fixture.model
        let pending = Task { await model.interpretSearchQuery("something to hear music") }
        for _ in 0..<150 where model.interpretingSearchQuery == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(model.interpretingSearchQuery)
        interpreter.setState(.intelligenceDisabled)
        await model.refreshSmartFeatureAvailability(); await pending.value
        XCTAssertTrue(model.showsSmartSearch); XCTAssertFalse(model.smartFeaturesAvailable)
        XCTAssertNil(model.interpretedSearch); XCTAssertNil(model.interpretingSearchQuery)
        XCTAssertNil(model.searchInterpretationMessage); XCTAssertTrue(model.queryVocabulary.isEmpty)
        model.indexVisualTags(ids: [fixture.photoID], refresh: true)
        XCTAssertFalse(model.isTagging)
        XCTAssertTrue(model.organization.visualSearchEnabled == true, "Keep the user's saved opt-in while enforcing system availability")
        interpreter.setState(.unsupported); await model.refreshSmartFeatureAvailability()
        XCTAssertFalse(model.showsSmartSearch)
        interpreter.setState(.ready); await model.refreshSmartFeatureAvailability()
        XCTAssertTrue(model.showsSmartSearch); XCTAssertTrue(model.smartFeaturesAvailable)
        await model.interpretSearchQuery("something to hear music")
        XCTAssertNotNil(model.interpretedSearch)
        let previousTags = model.organization.items[fixture.photoID]?.visualTags
        model.indexVisualTags(ids: [fixture.photoID], refresh: true)
        XCTAssertTrue(model.isTagging)
        interpreter.setState(.intelligenceDisabled); await model.refreshSmartFeatureAvailability()
        XCTAssertFalse(model.isTagging); XCTAssertFalse(model.isAnalyzing)
        XCTAssertEqual(model.organization.items[fixture.photoID]?.visualTags, previousTags)
        XCTAssertNil(model.interpretedSearch); XCTAssertTrue(model.queryVocabulary.isEmpty)
        await model.lockPrivate()
    }

    func testSavedOptInsCannotStartWorkWhenAppleIntelligenceIsUnavailable() async throws {
        for state in [GalleryQueryInterpreterAvailability.State.unsupported, .intelligenceDisabled, .modelNotReady] {
            let interpreter = MutableInterpreter(state)
            let fixture = try await makeModel(interpreter: interpreter)
            let model = fixture.model
            let photoURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "headphones", withExtension: "jpg"))
            await model.importFiles([photoURL])
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(model.untaggedPhotoCount, 1, model.errorMessage ?? "Expected import to work without Smart Search")
            XCTAssertFalse(model.isTagging)
            model.indexVisualTags(); await model.interpretSearchQuery("something to hear music")
            XCTAssertFalse(model.isTagging); XCTAssertEqual(interpreter.calls, 0)
            XCTAssertNil(model.interpretedSearch); XCTAssertTrue(model.queryVocabulary.isEmpty)
            await model.lockPrivate(); model.lock.activate()
            let unlocked = await model.unlockPrivate(); XCTAssertTrue(unlocked)
            XCTAssertFalse(model.isTagging)
            await model.lockPrivate(); fixture.cleanup()
        }
    }

    private final class MutableInterpreter: GallerySearchQueryInterpreting, @unchecked Sendable {
        private let lock = NSLock()
        private var state: GalleryQueryInterpreterAvailability.State
        private var callCount = 0
        init(_ state: GalleryQueryInterpreterAvailability.State) { self.state = state }
        var calls: Int { lock.withLock { callCount } }
        func setState(_ state: GalleryQueryInterpreterAvailability.State) { lock.withLock { self.state = state } }
        var availability: GalleryQueryInterpreterAvailability {
            lock.withLock { .init(state: state, message: "Test availability: \(state)") }
        }
        func interpret(_ query: String, labels: [String]) async throws -> GallerySearchQueryPlan {
            lock.withLock { callCount += 1 }
            // Deliberately ignore cancellation; the caller must discard a late result.
            try? await Task.sleep(for: .milliseconds(300))
            return .init(required: [.init(alternatives: ["headphones"])], excluded: [], hasUnverifiedDetails: false)
        }
    }

    private struct SlowInterpreter: GallerySearchQueryInterpreting {
        var availability: GalleryQueryInterpreterAvailability { .init(state: .ready, message: "Available") }
        func interpret(_ query: String, labels: [String]) async throws -> GallerySearchQueryPlan {
            // Deliberately return after cancellation to test the caller's guards.
            try? await Task.sleep(for: .milliseconds(300))
            return .init(required: [.init(alternatives: [query])], excluded: [], hasUnverifiedDetails: false)
        }
    }
    private struct UnavailableInterpreter: GallerySearchQueryInterpreting {
        var availability: GalleryQueryInterpreterAvailability { .init(state: .modelNotReady, message: "Local model unavailable; tags and synonyms still work.") }
        func interpret(_ query: String, labels: [String]) async throws -> GallerySearchQueryPlan { XCTFail("Called unavailable model"); throw GalleryQueryInterpretationError.unavailable }
    }
    private struct Fixture {
        let root: URL; let suite: String; let defaults: UserDefaults; let settings: GallerySettingsStore
        let model: GalleryViewModel; let photoID: String
        @MainActor func cleanup() { try? FileManager.default.removeItem(at: root); try? settings.purge(); defaults.removePersistentDomain(forName: suite) }
    }
    private func makeModel(interpreter: any GallerySearchQueryInterpreting, taggingEnabled: Bool = true, phrasesEnabled: Bool? = true) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GalleryQuery-" + UUID().uuidString)
        try MediaFileProtection.prepareDirectory(root)
        let suite = "GalleryQuery-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = GallerySettingsStore(service: suite, defaults: defaults)
        let store = PrivateMediaStore(root: root.appendingPathComponent("vault"), keys: MemoryPrivateMediaKeys())
        _ = try await store.unlock()
        let session = try await store.currentSession(), source = root.appendingPathComponent("photo.jpg")
        let photoURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "headphones", withExtension: "jpg"))
        let bytes = try Data(contentsOf: photoURL)
        try bytes.write(to: source)
        let photo = try await store.save(file: source, fileExtension: "jpg", kind: .photo, width: 1, height: 1, duration: 0,
            thumbnail: bytes, profile: nil, session: session)
        if taggingEnabled {
            _ = try await store.setVisualSearch(enabled: true, session: session)
            _ = try await store.setVisualTags(id: photo.id, tags: [.init(label: "headphones", confidence: 0.9)], session: session)
        }
        if let phrasesEnabled { _ = try await store.setAIQueryInterpretation(enabled: phrasesEnabled, session: session) }
        await store.lock()
        let credentials = GalleryLockStore(persistence: MemoryGalleryLockPersistence())
        _ = try await credentials.configure(mode: .off, pin: "", keys: [])
        let model = GalleryViewModel(exportStore: TemporaryExportStore(rootURL: root.appendingPathComponent("exports")),
            privateStore: store, workStore: MediaWorkStore(root: root.appendingPathComponent("work")), defaults: defaults,
            lock: GalleryLockController(store: credentials), preferencesDomain: suite, settingsStore: settings, queryInterpreter: interpreter)
        await model.start(); let unlocked = await model.unlockPrivate(); XCTAssertTrue(unlocked)
        return .init(root: root, suite: suite, defaults: defaults, settings: settings, model: model, photoID: photo.id)
    }
}
