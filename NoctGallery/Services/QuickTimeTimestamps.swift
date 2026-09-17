import Foundation

/// Only the calendar fields of fresh exports are rewritten. Sample timing,
/// durations, offsets, media payloads and relative presentation times stay intact.
enum QuickTimeTimestamps {
    struct Field { let offset: UInt64; let width: Int }
    private static let epochOffset: Double = 2_082_844_800

    static func rewrite(_ url: URL, date: Date?) throws {
        let file = try FileHandle(forUpdating: url)
        defer { try? file.close() }
        let fields = try timestampFields(file)
        let seconds = try timestamp(date)
        for field in fields {
            guard field.width == 8 || seconds <= UInt64(UInt32.max) else { throw VideoSanitizer.VideoError.metadataVerification }
            let data = Data((0..<field.width).reversed().map { UInt8(truncatingIfNeeded: seconds >> ($0 * 8)) })
            try file.seek(toOffset: field.offset)
            try file.write(contentsOf: data)
        }
        try file.synchronize()
    }

    static func verify(_ url: URL, date: Date?) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let expected = try timestamp(date)
        for field in try timestampFields(file) {
            let bytes = try read(file, offset: field.offset, count: field.width)
            guard integer(bytes) == expected else { throw VideoSanitizer.VideoError.metadataVerification }
        }
    }

    private static func timestamp(_ date: Date?) throws -> UInt64 {
        guard let date else { return 0 }
        let seconds = date.timeIntervalSince1970 + epochOffset
        guard seconds.isFinite, seconds >= 0, seconds < Double(UInt32.max) else { throw VideoSanitizer.VideoError.metadataVerification }
        return UInt64(seconds)
    }

    private static func timestampFields(_ file: FileHandle) throws -> [Field] {
        let length = try file.seekToEnd()
        var fields: [Field] = []
        var visited = 0
        func walk(_ start: UInt64, _ end: UInt64, _ depth: Int) throws {
            guard depth < 8 else { throw VideoSanitizer.VideoError.metadataVerification }
            var offset = start
            while offset < end {
                visited += 1
                guard visited < 10_000, end - offset >= 8 else { throw VideoSanitizer.VideoError.metadataVerification }
                let header = try read(file, offset: offset, count: 8)
                let smallSize = integer(header.prefix(4))
                let type = String(decoding: header.suffix(4), as: UTF8.self)
                let headerSize: UInt64 = smallSize == 1 ? 16 : 8
                let size: UInt64
                if smallSize == 1 { size = integer(try read(file, offset: offset + 8, count: 8)) }
                else { size = smallSize == 0 ? end - offset : smallSize }
                guard size >= headerSize, size <= end - offset else { throw VideoSanitizer.VideoError.metadataVerification }
                if ["moov", "trak", "mdia"].contains(type) {
                    try walk(offset + headerSize, offset + size, depth + 1)
                } else if ["mvhd", "tkhd", "mdhd"].contains(type) {
                    let version = try read(file, offset: offset + headerSize, count: 1)[0]
                    guard version <= 1 else { throw VideoSanitizer.VideoError.metadataVerification }
                    let width = version == 1 ? 8 : 4
                    guard size >= headerSize + 4 + UInt64(width * 2) else { throw VideoSanitizer.VideoError.metadataVerification }
                    fields.append(Field(offset: offset + headerSize + 4, width: width))
                    fields.append(Field(offset: offset + headerSize + 4 + UInt64(width), width: width))
                }
                offset += size
            }
        }
        try walk(0, length, 0)
        guard fields.count >= 6 else { throw VideoSanitizer.VideoError.metadataVerification }
        return fields
    }

    private static func read(_ file: FileHandle, offset: UInt64, count: Int) throws -> Data {
        try file.seek(toOffset: offset)
        let data = try file.read(upToCount: count) ?? Data()
        guard data.count == count else { throw VideoSanitizer.VideoError.metadataVerification }
        return data
    }
    private static func integer<T: DataProtocol>(_ bytes: T) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
