import XCTest
@testable import NoctGallery

final class MetadataForgeTests: XCTestCase {
    func testSeededGenerationIsStableAndBounded() {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        var firstGenerator = SeededGenerator(seed: 42)
        var secondGenerator = SeededGenerator(seed: 42)

        let first = MetadataForge.randomProfile(referenceDate: reference, using: &firstGenerator)
        let second = MetadataForge.randomProfile(referenceDate: reference, using: &secondGenerator)

        XCTAssertEqual(first.make, second.make)
        XCTAssertEqual(first.model, second.model)
        XCTAssertEqual(first.software, second.software)
        XCTAssertEqual(first.capturedAt, second.capturedAt)
        XCTAssertEqual(first.latitude, second.latitude)
        XCTAssertEqual(first.longitude, second.longitude)
        XCTAssertTrue((-58.0 ... 58.0).contains(first.latitude))
        XCTAssertTrue((-170.0 ... 170.0).contains(first.longitude))
        XCTAssertLessThan(first.capturedAt, reference)
    }
}
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
