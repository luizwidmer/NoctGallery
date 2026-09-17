import Foundation
import ImageIO

struct DecoyLocation: Codable, Hashable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
            && (-180...180).contains(longitude) && TimeZone(identifier: timeZoneIdentifier) != nil
    }
    // Optional seed regions; coordinates are sampled within an area, never a fixed city pin.
    static let places = [
        DecoyLocation(name: "Lisbon", latitude: 38.7223, longitude: -9.1393, timeZoneIdentifier: "Europe/Lisbon"),
        DecoyLocation(name: "Kyoto", latitude: 35.0116, longitude: 135.7681, timeZoneIdentifier: "Asia/Tokyo"),
        DecoyLocation(name: "San Francisco", latitude: 37.7749, longitude: -122.4194, timeZoneIdentifier: "America/Los_Angeles"),
        DecoyLocation(name: "Copenhagen", latitude: 55.6761, longitude: 12.5683, timeZoneIdentifier: "Europe/Copenhagen"),
        DecoyLocation(name: "Porto", latitude: 41.1579, longitude: -8.6291, timeZoneIdentifier: "Europe/Lisbon"),
        DecoyLocation(name: "Madrid", latitude: 40.4168, longitude: -3.7038, timeZoneIdentifier: "Europe/Madrid"),
        DecoyLocation(name: "Paris", latitude: 48.8566, longitude: 2.3522, timeZoneIdentifier: "Europe/Paris"),
        DecoyLocation(name: "Berlin", latitude: 52.52, longitude: 13.405, timeZoneIdentifier: "Europe/Berlin"),
        DecoyLocation(name: "Rome", latitude: 41.9028, longitude: 12.4964, timeZoneIdentifier: "Europe/Rome"),
        DecoyLocation(name: "London", latitude: 51.5074, longitude: -0.1278, timeZoneIdentifier: "Europe/London"),
        DecoyLocation(name: "Vienna", latitude: 48.2082, longitude: 16.3738, timeZoneIdentifier: "Europe/Vienna"),
        DecoyLocation(name: "Prague", latitude: 50.0755, longitude: 14.4378, timeZoneIdentifier: "Europe/Prague"),
        DecoyLocation(name: "Warsaw", latitude: 52.2297, longitude: 21.0122, timeZoneIdentifier: "Europe/Warsaw"),
        DecoyLocation(name: "Athens", latitude: 37.9838, longitude: 23.7275, timeZoneIdentifier: "Europe/Athens"),
        DecoyLocation(name: "Istanbul", latitude: 41.0082, longitude: 28.9784, timeZoneIdentifier: "Europe/Istanbul"),
        DecoyLocation(name: "Montreal", latitude: 45.5019, longitude: -73.5674, timeZoneIdentifier: "America/Toronto"),
        DecoyLocation(name: "New York", latitude: 40.7128, longitude: -74.006, timeZoneIdentifier: "America/New_York"),
        DecoyLocation(name: "Chicago", latitude: 41.8781, longitude: -87.6298, timeZoneIdentifier: "America/Chicago"),
        DecoyLocation(name: "Mexico City", latitude: 19.4326, longitude: -99.1332, timeZoneIdentifier: "America/Mexico_City"),
        DecoyLocation(name: "Bogotá", latitude: 4.711, longitude: -74.0721, timeZoneIdentifier: "America/Bogota"),
        DecoyLocation(name: "São Paulo", latitude: -23.5505, longitude: -46.6333, timeZoneIdentifier: "America/Sao_Paulo"),
        DecoyLocation(name: "Buenos Aires", latitude: -34.6037, longitude: -58.3816, timeZoneIdentifier: "America/Argentina/Buenos_Aires"),
        DecoyLocation(name: "Santiago", latitude: -33.4489, longitude: -70.6693, timeZoneIdentifier: "America/Santiago"),
        DecoyLocation(name: "Lima", latitude: -12.0464, longitude: -77.0428, timeZoneIdentifier: "America/Lima"),
        DecoyLocation(name: "Marrakesh", latitude: 31.6295, longitude: -7.9811, timeZoneIdentifier: "Africa/Casablanca"),
        DecoyLocation(name: "Cairo", latitude: 30.0444, longitude: 31.2357, timeZoneIdentifier: "Africa/Cairo"),
        DecoyLocation(name: "Nairobi", latitude: -1.2921, longitude: 36.8219, timeZoneIdentifier: "Africa/Nairobi"),
        DecoyLocation(name: "Johannesburg", latitude: -26.2041, longitude: 28.0473, timeZoneIdentifier: "Africa/Johannesburg"),
        DecoyLocation(name: "Delhi", latitude: 28.6139, longitude: 77.209, timeZoneIdentifier: "Asia/Kolkata"),
        DecoyLocation(name: "Bangkok", latitude: 13.7563, longitude: 100.5018, timeZoneIdentifier: "Asia/Bangkok"),
        DecoyLocation(name: "Singapore", latitude: 1.3521, longitude: 103.8198, timeZoneIdentifier: "Asia/Singapore"),
        DecoyLocation(name: "Kuala Lumpur", latitude: 3.139, longitude: 101.6869, timeZoneIdentifier: "Asia/Kuala_Lumpur"),
        DecoyLocation(name: "Seoul", latitude: 37.5665, longitude: 126.978, timeZoneIdentifier: "Asia/Seoul"),
        DecoyLocation(name: "Taipei", latitude: 25.033, longitude: 121.5654, timeZoneIdentifier: "Asia/Taipei"),
        DecoyLocation(name: "Osaka", latitude: 34.6937, longitude: 135.5023, timeZoneIdentifier: "Asia/Tokyo"),
        DecoyLocation(name: "Melbourne", latitude: -37.8136, longitude: 144.9631, timeZoneIdentifier: "Australia/Melbourne"),
        DecoyLocation(name: "Sydney", latitude: -33.8688, longitude: 151.2093, timeZoneIdentifier: "Australia/Sydney"),
        DecoyLocation(name: "Auckland", latitude: -36.8485, longitude: 174.7633, timeZoneIdentifier: "Pacific/Auckland"),
        DecoyLocation(name: "Perth", latitude: -31.9523, longitude: 115.8613, timeZoneIdentifier: "Australia/Perth"),
        DecoyLocation(name: "Helsinki", latitude: 60.1699, longitude: 24.9384, timeZoneIdentifier: "Europe/Helsinki")
    ]

    func randomized<R: RandomNumberGenerator>(radiusKilometers: Double, using generator: inout R) -> Self {
        // Uniform area on a small spherical cap. No geocoder or device location is used.
        let radius = min(50, max(0.1, radiusKilometers.isFinite ? radiusKilometers : 5))
        let angular = sqrt(Double.random(in: 0...1, using: &generator)) * radius / 6_371
        let bearing = Double.random(in: 0..<(2 * .pi), using: &generator)
        let lat = latitude * .pi / 180, lon = longitude * .pi / 180
        let nextLat = asin(sin(lat) * cos(angular) + cos(lat) * sin(angular) * cos(bearing))
        let nextLon = lon + atan2(sin(bearing) * sin(angular) * cos(lat), cos(angular) - sin(lat) * sin(nextLat))
        let degrees = (nextLon * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180
        return Self(name: name, latitude: nextLat * 180 / .pi, longitude: degrees, timeZoneIdentifier: timeZoneIdentifier)
    }
}

enum DecoyScene: String, Codable, CaseIterable, Identifiable, Sendable {
    case daylight, shade, indoors
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct DecoyExposure: Codable, Hashable, Sendable {
    var aperture: Double
    var iso: Int
    var shutterDenominator: Int
    var exposureValue: Double { log2(aperture * aperture * Double(shutterDenominator) * 100 / Double(iso)) }
}

/// Published lens specifications with a conservative subset of exposure settings.
/// Catalog provenance and synthesis limits are in Docs/MediaMetadata.md.
struct DecoyEquipment: Identifiable, Hashable, Sendable {
    let id: String
    let make: String
    let model: String
    let title: String
    let focalLength: Double?
    let equivalentFocalLength: Int
    let apertures: [Double]
    let isoValues: [Int]
    let shutterDenominators: [Int]

    static let apertureSteps: [Double] = [1.6, 1.7, 1.8, 2, 2.2, 2.5, 2.8, 3.2, 3.5, 4, 4.5, 5, 5.6, 6.3, 7.1, 8]
    static let isoSteps = [50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400]
    static let shutterSteps = [15, 20, 25, 30, 40, 50, 60, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000]

    static func phone(_ id: String, _ model: String, _ lens: String, _ equivalent: Int, _ aperture: Double) -> Self {
        .init(id: id, make: "Apple", model: model, title: "\(model) · \(lens)", focalLength: nil,
              equivalentFocalLength: equivalent, apertures: [aperture],
              isoValues: isoSteps.filter { (80...1600).contains($0) }, shutterDenominators: shutterSteps)
    }
    static func camera(_ id: String, _ make: String, _ model: String, _ focal: Double, _ equivalent: Int,
                       _ minimumAperture: Double, _ minimumISO: Int, maxISO: Int = 6400, lens: String = "") -> Self {
        .init(id: id, make: make, model: model, title: "\(model.hasPrefix(make) ? model : make + " " + model)\(lens.isEmpty ? "" : " · " + lens)",
              focalLength: focal, equivalentFocalLength: equivalent,
              apertures: (minimumAperture == 1.7 ? [1.7] : []) + apertureSteps.filter { $0 >= (minimumAperture == 1.7 ? 2 : minimumAperture) },
              isoValues: isoSteps.filter { (minimumISO...maxISO).contains($0) },
              // Avoid undocumented aperture-dependent leaf-shutter restrictions.
              shutterDenominators: shutterSteps.filter { $0 <= 1000 })
    }
    static let catalog: [Self] = [
        phone("iphone15pro-main", "iPhone 15 Pro", "Main", 24, 1.78),
        phone("iphone15pro-ultra", "iPhone 15 Pro", "Ultra Wide", 13, 2.2),
        phone("iphone15pro-tele", "iPhone 15 Pro", "Telephoto", 77, 2.8),
        phone("iphone15promax-main", "iPhone 15 Pro Max", "Main", 24, 1.78),
        phone("iphone15promax-ultra", "iPhone 15 Pro Max", "Ultra Wide", 13, 2.2),
        phone("iphone15promax-tele", "iPhone 15 Pro Max", "Telephoto", 120, 2.8),
        phone("iphone15-main", "iPhone 15", "Main", 26, 1.6),
        phone("iphone15-ultra", "iPhone 15", "Ultra Wide", 13, 2.4),
        phone("iphone15plus-main", "iPhone 15 Plus", "Main", 26, 1.6),
        phone("iphone15plus-ultra", "iPhone 15 Plus", "Ultra Wide", 13, 2.4),
        phone("iphone14pro-main", "iPhone 14 Pro", "Main", 24, 1.78),
        phone("iphone14pro-ultra", "iPhone 14 Pro", "Ultra Wide", 13, 2.2),
        phone("iphone14pro-tele", "iPhone 14 Pro", "Telephoto", 77, 2.8),
        phone("iphone14promax-main", "iPhone 14 Pro Max", "Main", 24, 1.78),
        phone("iphone14promax-ultra", "iPhone 14 Pro Max", "Ultra Wide", 13, 2.2),
        phone("iphone14promax-tele", "iPhone 14 Pro Max", "Telephoto", 77, 2.8),
        camera("x100v", "FUJIFILM", "X100V", 23, 35, 2, 160),
        camera("x100f", "FUJIFILM", "X100F", 23, 35, 2, 200),
        camera("xf10", "FUJIFILM", "XF10", 18.5, 28, 2.8, 200),
        camera("gr3", "RICOH", "GR III", 18.3, 28, 2.8, 100),
        camera("gr3x", "RICOH", "GR IIIx", 26.1, 40, 2.8, 100),
        camera("rx100m7-wide", "SONY", "DSC-RX100M7", 9, 24, 2.8, 100, lens: "Wide"),
        camera("rx100m7-tele", "SONY", "DSC-RX100M7", 72, 200, 4.5, 100, lens: "Telephoto"),
        camera("rx100m3-wide", "SONY", "DSC-RX100M3", 8.8, 24, 1.8, 125, lens: "Wide"),
        camera("rx100m3-tele", "SONY", "DSC-RX100M3", 25.7, 70, 2.8, 125, lens: "Telephoto"),
        camera("rx100m5-wide", "SONY", "DSC-RX100M5", 8.8, 24, 1.8, 125, lens: "Wide"),
        camera("rx100m5-tele", "SONY", "DSC-RX100M5", 25.7, 70, 2.8, 125, lens: "Telephoto"),
        camera("rx1rm2", "SONY", "DSC-RX1RM2", 35, 35, 2, 100),
        camera("g7xm2-wide", "Canon", "Canon PowerShot G7 X Mark II", 8.8, 24, 1.8, 125, lens: "Wide"),
        camera("g7xm2-tele", "Canon", "Canon PowerShot G7 X Mark II", 36.8, 100, 2.8, 125, lens: "Telephoto"),
        camera("g5xm2-wide", "Canon", "Canon PowerShot G5 X Mark II", 8.8, 24, 1.8, 125, lens: "Wide"),
        camera("g5xm2-tele", "Canon", "Canon PowerShot G5 X Mark II", 44, 120, 2.8, 125, lens: "Telephoto"),
        camera("lx100-wide", "Panasonic", "DMC-LX100", 10.9, 24, 1.7, 200, lens: "Wide"),
        camera("lx100-tele", "Panasonic", "DMC-LX100", 34, 75, 2.8, 200, lens: "Telephoto"),
        camera("lx100m2-wide", "Panasonic", "DC-LX100M2", 10.9, 24, 1.7, 200, lens: "Wide"),
        camera("lx100m2-tele", "Panasonic", "DC-LX100M2", 34, 75, 2.8, 200, lens: "Telephoto"),
        camera("dlux7-wide", "LEICA", "D-Lux 7", 10.9, 24, 1.7, 200, lens: "Wide"),
        camera("dlux7-tele", "LEICA", "D-Lux 7", 34, 75, 2.8, 200, lens: "Telephoto"),
        camera("p1000-wide", "NIKON", "COOLPIX P1000", 4.3, 24, 2.8, 100, maxISO: 1600, lens: "Wide"),
        camera("p1000-tele", "NIKON", "COOLPIX P1000", 539, 3000, 8, 100, maxISO: 1600, lens: "Telephoto")
    ]
    static let modelNames = Set(catalog.map(\.model)).sorted()
    static let brands = Set(catalog.map(\.make)).sorted()

    func accepts(_ exposure: DecoyExposure) -> Bool {
        apertures.contains(exposure.aperture) && isoValues.contains(exposure.iso)
            && shutterDenominators.contains(exposure.shutterDenominator)
    }
    func exposure(for scene: DecoyScene) -> DecoyExposure {
        // Preserve the original three profiles when reading previously saved media.
        if id == "iphone15pro-main" {
            switch scene {
            case .daylight: return .init(aperture: 1.78, iso: 80, shutterDenominator: 2000)
            case .shade: return .init(aperture: 1.78, iso: 160, shutterDenominator: 500)
            case .indoors: return .init(aperture: 1.78, iso: 400, shutterDenominator: 60)
            }
        }
        if id == "x100v" {
            switch scene {
            case .daylight: return .init(aperture: 8, iso: 160, shutterDenominator: 250)
            case .shade: return .init(aperture: 4, iso: 400, shutterDenominator: 250)
            case .indoors: return .init(aperture: 2, iso: 800, shutterDenominator: 60)
            }
        }
        if id == "rx100m7-wide" {
            switch scene {
            case .daylight: return .init(aperture: 5.6, iso: 100, shutterDenominator: 500)
            case .shade: return .init(aperture: 4, iso: 400, shutterDenominator: 250)
            case .indoors: return .init(aperture: 2.8, iso: 800, shutterDenominator: 60)
            }
        }
        let choices = Self.pools[id]![scene]!
        return choices[choices.count / 2]
    }

    private static let pools: [String: [DecoyScene: [DecoyExposure]]] = Dictionary(uniqueKeysWithValues: catalog.map { camera in
        let all = camera.apertures.flatMap { aperture in camera.isoValues.flatMap { iso in
            camera.shutterDenominators.map { DecoyExposure(aperture: aperture, iso: iso, shutterDenominator: $0) }
        }}
        return (camera.id, Dictionary(uniqueKeysWithValues: DecoyScene.allCases.map { scene in
            let range: ClosedRange<Double> = switch scene { case .daylight: 12...16; case .shade: 8...12; case .indoors: 4...8 }
            return (scene, all.filter { range.contains($0.exposureValue) })
        }))
    })
    func randomExposure<R: RandomNumberGenerator>(for scene: DecoyScene, using generator: inout R) -> DecoyExposure {
        Self.pools[id]![scene]!.randomElement(using: &generator)!
    }
}

struct SyntheticMetadataProfile: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var equipmentID: String
    var scene: DecoyScene
    var capturedAt: Date
    var location: DecoyLocation?
    var includeEquipment: Bool? = nil
    var exposureOverride: DecoyExposure? = nil
    var captureTimeZoneIdentifier: String? = nil

    var equipment: DecoyEquipment {
        DecoyEquipment.catalog.first { $0.id == equipmentID } ?? DecoyEquipment.catalog[0]
    }
    var displayName: String { includesEquipment ? equipment.title : "Date & location only" }
    var includesEquipment: Bool { includeEquipment != false }
    var make: String { equipment.make }
    var model: String { equipment.model }
    var exposure: DecoyExposure { exposureOverride ?? equipment.exposure(for: scene) }
    var timeZone: TimeZone { location.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) }
        ?? captureTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)! }
    // A conservative common availability date for every catalog entry.
    static let earliestDate = Date(timeIntervalSince1970: 1_704_067_200)

    func validated(referenceDate: Date = Date()) throws -> Self {
        guard DecoyEquipment.catalog.contains(where: { $0.id == equipmentID }),
              capturedAt.timeIntervalSince1970.isFinite,
              capturedAt >= Self.earliestDate, capturedAt <= referenceDate,
              location?.isValid != false,
              captureTimeZoneIdentifier == nil || TimeZone(identifier: captureTimeZoneIdentifier!) != nil,
              exposureOverride == nil || equipment.accepts(exposureOverride!) else { throw MetadataForge.ProfileError.invalidProfile }
        return self
    }
}

enum CameraMetadataMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case clean, preset, random
    var id: String { rawValue }
    var title: String {
        switch self { case .clean: "Clean"; case .preset: "Preset decoy"; case .random: "Random decoy" }
    }
}

struct DecoyPreset: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var profile: SyntheticMetadataProfile
    var savedAt = Date()

    func captureProfile(now: Date = Date()) throws -> SyntheticMetadataProfile {
        var result = profile
        // A preset preserves a time offset; consecutive captures advance naturally.
        result.capturedAt = min(now, profile.capturedAt.addingTimeInterval(max(0, now.timeIntervalSince(savedAt))))
        return try result.validated(referenceDate: now)
    }
}

enum MetadataForge {
    enum ProfileError: LocalizedError {
        case invalidProfile
        var errorDescription: String? { "Choose compatible camera settings, a date from 2024 through today, and valid map coordinates." }
    }

    static func randomProfile(referenceDate: Date = Date(), includeLocation: Bool = false, includeEquipment: Bool = true,
                              around center: DecoyLocation? = nil, radiusKilometers: Double = 5) -> SyntheticMetadataProfile {
        var generator = SystemRandomNumberGenerator()
        return randomProfile(referenceDate: referenceDate, includeLocation: includeLocation, includeEquipment: includeEquipment,
                             around: center, radiusKilometers: radiusKilometers, using: &generator)
    }

    static func randomProfile<R: RandomNumberGenerator>(referenceDate: Date = Date(), includeLocation: Bool = false, includeEquipment: Bool = true,
        around center: DecoyLocation? = nil, radiusKilometers: Double = 5, using generator: inout R) -> SyntheticMetadataProfile {
        // Sample models first so phones with more lens entries do not dominate.
        let model = DecoyEquipment.modelNames.randomElement(using: &generator)!
        let equipment = DecoyEquipment.catalog.filter { $0.model == model }.randomElement(using: &generator)!
        let place = (center?.isValid == true ? center : nil) ?? DecoyLocation.places.randomElement(using: &generator)!
        var scene = DecoyScene.allCases.randomElement(using: &generator)!
        let available = max(0, referenceDate.timeIntervalSince(SyntheticMetadataProfile.earliestDate))
        let offset = Double.random(in: 0...min(available, 365 * 86_400), using: &generator)
        var capturedAt = referenceDate.addingTimeInterval(-offset)
        // Outdoor exposure should not claim the middle of the local night.
        if scene != .indoors {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: place.timeZoneIdentifier)!
            let seconds = Int.random(in: (10 * 3600)..<(16 * 3600), using: &generator)
            var parts = calendar.dateComponents([.year, .month, .day], from: capturedAt)
            parts.hour = seconds / 3600; parts.minute = seconds % 3600 / 60; parts.second = seconds % 60
            var daytime = calendar.date(from: parts)!
            if daytime > referenceDate { daytime = calendar.date(byAdding: .day, value: -1, to: daytime)! }
            if daytime >= SyntheticMetadataProfile.earliestDate { capturedAt = daytime }
            else { scene = .indoors }
        }
        return SyntheticMetadataProfile(equipmentID: equipment.id, scene: scene, capturedAt: capturedAt,
            location: includeLocation ? place.randomized(radiusKilometers: radiusKilometers, using: &generator) : nil,
            includeEquipment: includeEquipment, exposureOverride: equipment.randomExposure(for: scene, using: &generator),
            captureTimeZoneIdentifier: place.timeZoneIdentifier)
    }

    static func destinationProperties(for profile: SyntheticMetadataProfile, lossyQuality: Double) -> [String: Any] {
        let timestamp = formatted(profile.capturedAt, format: "yyyy:MM:dd HH:mm:ss", timeZone: profile.timeZone)
        let seconds = profile.timeZone.secondsFromGMT(for: profile.capturedAt)
        let offset = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
        let exposure = profile.exposure
        var exif: [String: Any] = [
            kCGImagePropertyExifDateTimeOriginal as String: timestamp,
            kCGImagePropertyExifDateTimeDigitized as String: timestamp,
            kCGImagePropertyExifOffsetTimeOriginal as String: offset,
            kCGImagePropertyExifOffsetTimeDigitized as String: offset,
            kCGImagePropertyExifFNumber as String: exposure.aperture,
            kCGImagePropertyExifExposureTime as String: 1.0 / Double(exposure.shutterDenominator),
            kCGImagePropertyExifISOSpeedRatings as String: [exposure.iso],
            kCGImagePropertyExifFocalLenIn35mmFilm as String: profile.equipment.equivalentFocalLength,
            kCGImagePropertyExifFlash as String: 0,
            kCGImagePropertyExifWhiteBalance as String: 0
        ]
        if let focal = profile.equipment.focalLength { exif[kCGImagePropertyExifFocalLength as String] = focal }
        if !profile.includesEquipment {
            let cameraKeys = [kCGImagePropertyExifFNumber, kCGImagePropertyExifExposureTime, kCGImagePropertyExifISOSpeedRatings,
                kCGImagePropertyExifFocalLenIn35mmFilm, kCGImagePropertyExifFocalLength, kCGImagePropertyExifFlash, kCGImagePropertyExifWhiteBalance]
            for key in cameraKeys { exif.removeValue(forKey: key as String) }
        }
        var tiff: [String: Any] = [kCGImagePropertyTIFFDateTime as String: timestamp]
        if profile.includesEquipment {
            tiff[kCGImagePropertyTIFFMake as String] = profile.make
            tiff[kCGImagePropertyTIFFModel as String] = profile.model
        }
        var properties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: lossyQuality,
            kCGImagePropertyTIFFDictionary as String: tiff,
            kCGImagePropertyExifDictionary as String: exif
        ]
        if let location = profile.location {
            properties[kCGImagePropertyGPSDictionary as String] = [
                kCGImagePropertyGPSLatitude as String: abs(location.latitude),
                kCGImagePropertyGPSLatitudeRef as String: location.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String: abs(location.longitude),
                kCGImagePropertyGPSLongitudeRef as String: location.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSDateStamp as String: formatted(profile.capturedAt, format: "yyyy:MM:dd"),
                kCGImagePropertyGPSTimeStamp as String: formatted(profile.capturedAt, format: "HH:mm:ss")
            ]
        }
        return properties
    }

    static func iso6709(_ location: DecoyLocation) -> String {
        func component(_ value: Double, digits: Int) -> String {
            let number = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), abs(value))
            return (value.sign == .minus ? "-" : "+") + String(repeating: "0", count: max(0, digits + 6 - number.count)) + number
        }
        return component(location.latitude, digits: 2) + component(location.longitude, digits: 3) + "/"
    }

    static func formatted(_ date: Date, format: String, timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
