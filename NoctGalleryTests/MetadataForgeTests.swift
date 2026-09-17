import AVFoundation
import ImageIO
import XCTest
@testable import NoctGallery

final class MetadataForgeTests: XCTestCase {
    func testSeededProfilesUseKnownCompatibleEquipmentWithoutGPSByDefault() throws {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        for _ in 0..<100 {
            let first = MetadataForge.randomProfile(referenceDate: reference, using: &a)
            let second = MetadataForge.randomProfile(referenceDate: reference, using: &b)
            XCTAssertEqual(first.equipmentID, second.equipmentID)
            XCTAssertEqual(first.scene, second.scene)
            XCTAssertEqual(first.capturedAt, second.capturedAt)
            XCTAssertEqual(first.location, second.location)
            XCTAssertTrue(DecoyEquipment.catalog.contains(first.equipment))
            XCTAssertNil(first.location)
            XCTAssertEqual(first.exposure, second.exposure)
            XCTAssertTrue(first.equipment.accepts(first.exposure))
            XCTAssertGreaterThanOrEqual(first.capturedAt, SyntheticMetadataProfile.earliestDate)
            XCTAssertLessThanOrEqual(first.capturedAt, reference)
            _ = try first.validated(referenceDate: reference)
            if first.equipmentID == "iphone15pro-main" { XCTAssertEqual(first.exposure.aperture, 1.78) }
            if first.equipmentID == "x100v" {
                XCTAssertEqual(first.equipment.focalLength, 23)
                XCTAssertGreaterThanOrEqual(first.exposure.iso, 160)
            }
        }
    }

    func testRandomProfilesCoverModelsLensesAndManyExposureCombinations() throws {
        var generator = SeededGenerator(seed: 7919)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var models = Set<String>(), lenses = Set<String>(), exposures = Set<DecoyExposure>(), dates = Set<Date>()
        for _ in 0..<2000 {
            let profile = MetadataForge.randomProfile(referenceDate: now, using: &generator)
            _ = try profile.validated(referenceDate: now)
            models.insert(profile.model); lenses.insert(profile.equipmentID)
            exposures.insert(profile.exposure); dates.insert(profile.capturedAt)
            let expected: ClosedRange<Double> = switch profile.scene {
            case .daylight: 12...16; case .shade: 8...12; case .indoors: 4...8
            }
            XCTAssertTrue(expected.contains(profile.exposure.exposureValue))
            if profile.scene != .indoors {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = profile.timeZone
                XCTAssertTrue((10...16).contains(calendar.component(.hour, from: profile.capturedAt)))
            }
        }
        XCTAssertEqual(models, Set(DecoyEquipment.modelNames))
        XCTAssertEqual(lenses, Set(DecoyEquipment.catalog.map(\.id)))
        XCTAssertGreaterThanOrEqual(models.count, 20)
        XCTAssertGreaterThan(exposures.count, 500)
        XCTAssertEqual(dates.count, 2000)
        XCTAssertEqual(Set(DecoyEquipment.catalog.map(\.id)).count, DecoyEquipment.catalog.count)
    }

    func testOptionalGPSVariesWithinChosenAreaIncludingLongitudeWrap() throws {
        var generator = SeededGenerator(seed: 17)
        let center = DecoyLocation(name: "Dateline", latitude: 30, longitude: 179.999, timeZoneIdentifier: "Pacific/Auckland")
        var coordinates = Set<DecoyLocation>()
        for _ in 0..<200 {
            let profile = MetadataForge.randomProfile(includeLocation: true, around: center, radiusKilometers: 5, using: &generator)
            let place = try XCTUnwrap(profile.location)
            _ = try profile.validated()
            XCTAssertTrue(place.isValid)
            XCTAssertNotEqual(place, center)
            XCTAssertEqual(place.timeZoneIdentifier, center.timeZoneIdentifier)
            let lat1 = center.latitude * .pi / 180, lat2 = place.latitude * .pi / 180
            let lonDelta = (place.longitude - center.longitude) * .pi / 180
            let haversine = pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(lonDelta / 2), 2)
            XCTAssertLessThanOrEqual(2 * 6371 * asin(sqrt(haversine)), 5.001)
            coordinates.insert(place)
        }
        XCTAssertEqual(coordinates.count, 200)
    }

    func testExposureEditsRoundTripRejectIncompatibleLensAndReadLegacyPreset() throws {
        let data = Data(#"{"equipmentID":"x100v","scene":"daylight","capturedAt":760000000,"location":null,"id":"AE2D489B-F134-446A-AD45-9FF4D2809E2C"}"#.utf8)
        var profile = try JSONDecoder().decode(SyntheticMetadataProfile.self, from: data)
        XCTAssertNil(profile.exposureOverride)
        XCTAssertEqual(profile.exposure, DecoyExposure(aperture: 8, iso: 160, shutterDenominator: 250))
        profile.exposureOverride = .init(aperture: 2.8, iso: 640, shutterDenominator: 125)
        profile.captureTimeZoneIdentifier = "Asia/Kolkata"
        _ = try profile.validated()
        let reopened = try JSONDecoder().decode(SyntheticMetadataProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(reopened.exposure, profile.exposure)
        XCTAssertEqual(reopened.timeZone.identifier, "Asia/Kolkata")
        profile.equipmentID = "iphone15pro-main"
        XCTAssertThrowsError(try profile.validated())
        profile.exposureOverride = .init(aperture: 1.78, iso: 800, shutterDenominator: 60)
        _ = try profile.validated()
        profile.exposureOverride?.iso = 99999
        XCTAssertThrowsError(try profile.validated())
    }

    func testLocalExifTimeAndUTCGeotimeDescribeSameInstant() throws {
        let date = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00 UTC
        let profile = SyntheticMetadataProfile(equipmentID: "x100v", scene: .daylight, capturedAt: date,
            location: DecoyLocation(name: "San Francisco", latitude: 37.7749, longitude: -122.4194,
                                    timeZoneIdentifier: "America/Los_Angeles"))
        let properties = MetadataForge.destinationProperties(for: profile, lossyQuality: 0.9)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2024:12:31 16:00:00")
        XCTAssertEqual(exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String, "-08:00")
        XCTAssertEqual(gps[kCGImagePropertyGPSDateStamp as String] as? String, "2025:01:01")
        XCTAssertEqual(gps[kCGImagePropertyGPSTimeStamp as String] as? String, "00:00:00")
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef as String] as? String, "W")
    }

    func testNoGPSMeansNoLocationDictionaryAndNoInventedSerialOrSoftware() throws {
        var profile = MetadataForge.randomProfile()
        profile.location = nil
        let properties = MetadataForge.destinationProperties(for: profile, lossyQuality: 0.9)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        XCTAssertNil(tiff[kCGImagePropertyTIFFSoftware as String])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertNil(exif[kCGImagePropertyExifBodySerialNumber as String])
        XCTAssertNil(exif[kCGImagePropertyExifLensSerialNumber as String])
        XCTAssertNil(exif[kCGImagePropertyExifUserComment as String])
    }

    func testInvalidDatesEquipmentAndCoordinatesAreRejected() throws {
        var profile = MetadataForge.randomProfile(includeLocation: true)
        profile.location?.latitude = .nan
        XCTAssertThrowsError(try profile.validated())
        profile.location = nil
        profile.capturedAt = .distantPast
        XCTAssertThrowsError(try profile.validated())
        profile.capturedAt = .distantFuture
        XCTAssertThrowsError(try profile.validated())
        profile.capturedAt = Date()
        profile.equipmentID = "invented-camera"
        XCTAssertThrowsError(try profile.validated())
    }

    func testDateOnlyProfilesOmitAllCameraIdentityAndExposureFromPhotosAndMovies() throws {
        let profile = MetadataForge.randomProfile(includeEquipment: false)
        let properties = MetadataForge.destinationProperties(for: profile, lossyQuality: 0.9)
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertNil(tiff[kCGImagePropertyTIFFMake as String])
        XCTAssertNil(tiff[kCGImagePropertyTIFFModel as String])
        for key in [kCGImagePropertyExifFNumber, kCGImagePropertyExifISOSpeedRatings, kCGImagePropertyExifExposureTime,
                    kCGImagePropertyExifFocalLength, kCGImagePropertyExifFocalLenIn35mmFilm, kCGImagePropertyExifFlash] {
            XCTAssertNil(exif[key as String])
        }
        XCTAssertNotNil(exif[kCGImagePropertyExifDateTimeOriginal as String])
        XCTAssertEqual(VideoSanitizer.metadata(profile).compactMap(\.identifier), [.quickTimeMetadataCreationDate])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
    }

    func testQuickTimeCoordinateEncodingHasSignsAndTerminator() {
        let place = DecoyLocation(name: "Place", latitude: -12.5, longitude: 38.75, timeZoneIdentifier: "GMT")
        XCTAssertEqual(MetadataForge.iso6709(place), "-12.50000+038.75000/")
    }

    func testCameraPresetPreservesTimeOffsetAndLocation() throws {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let profile = SyntheticMetadataProfile(equipmentID: "x100v", scene: .indoors,
            capturedAt: now.addingTimeInterval(-86_400), location: DecoyLocation.places[0])
        let preset = DecoyPreset(name: "Travel", profile: profile, savedAt: now)
        let later = try preset.captureProfile(now: now.addingTimeInterval(45))
        XCTAssertEqual(later.capturedAt.timeIntervalSince(profile.capturedAt), 45)
        XCTAssertEqual(later.location, profile.location)
        XCTAssertEqual(later.equipmentID, profile.equipmentID)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
