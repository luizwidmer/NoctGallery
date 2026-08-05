import Foundation
import ImageIO

enum MetadataForge {
    static func randomProfile(referenceDate: Date = Date()) -> SyntheticMetadataProfile {
        var generator = SystemRandomNumberGenerator()
        return randomProfile(referenceDate: referenceDate, using: &generator)
    }

    static func randomProfile<R: RandomNumberGenerator>(
        referenceDate: Date = Date(),
        using generator: inout R
    ) -> SyntheticMetadataProfile {
        let makes = ["Aster Imaging", "Northstar Optical", "Morrow Camera Works", "Solace Digital"]
        let models = ["Field 28", "Pocket 40", "Studio C", "Range 7"]
        let software = ["Imaging Engine 3.2", "Capture Stack 5.1", "Photo Processor 2.8"]
        let dayOffset = Int.random(in: 45 ... 2_800, using: &generator)
        let secondOffset = Int.random(in: 0 ..< 86_400, using: &generator)
        let capturedAt = referenceDate.addingTimeInterval(-Double(dayOffset * 86_400 + secondOffset))

        return SyntheticMetadataProfile(
            id: UUID(),
            make: makes.randomElement(using: &generator) ?? makes[0],
            model: models.randomElement(using: &generator) ?? models[0],
            software: software.randomElement(using: &generator) ?? software[0],
            capturedAt: capturedAt,
            latitude: Double.random(in: -58.0 ... 58.0, using: &generator),
            longitude: Double.random(in: -170.0 ... 170.0, using: &generator)
        )
    }

    static func destinationProperties(
        for profile: SyntheticMetadataProfile,
        lossyQuality: Double
    ) -> [String: Any] {
        let timestamp = exifTimestamp(profile.capturedAt)
        let latitude = abs(profile.latitude)
        let longitude = abs(profile.longitude)

        return [
            kCGImageDestinationLossyCompressionQuality as String: lossyQuality,
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: profile.make,
                kCGImagePropertyTIFFModel as String: profile.model,
                kCGImagePropertyTIFFSoftware as String: profile.software,
                kCGImagePropertyTIFFDateTime as String: timestamp
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: timestamp,
                kCGImagePropertyExifDateTimeDigitized as String: timestamp,
                kCGImagePropertyExifUserComment as String: ""
            ],
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: latitude,
                kCGImagePropertyGPSLatitudeRef as String: profile.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String: longitude,
                kCGImagePropertyGPSLongitudeRef as String: profile.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSDateStamp as String: gpsDate(profile.capturedAt),
                kCGImagePropertyGPSTimeStamp as String: gpsTime(profile.capturedAt)
            ]
        ]
    }

    private static func exifTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func gpsDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd"
        return formatter.string(from: date)
    }

    private static func gpsTime(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        return String(format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }
}
