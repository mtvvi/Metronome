import Foundation

struct AudioRawTag: Codable, Equatable, Sendable {
    var keySpace: String?
    var key: String?
    var commonKey: String?
    var identifier: String?
    var value: String
}

struct AudioMetadataNormalizationResult: Equatable, Sendable {
    var tags: AudioMetadataTags
    var rawTagsJSON: String
}

enum AudioMetadataTagNormalizer {
    static func normalize(rawTags: [AudioRawTag]) throws -> AudioMetadataNormalizationResult {
        var tags = AudioMetadataTags.empty

        for rawTag in rawTags {
            let keys = normalizedKeys(for: rawTag)

            if keys.contains("title") {
                tags.title = rawTag.value
            } else if keys.contains("albumname") || keys.contains("album") || keys.contains("talb") {
                tags.album = rawTag.value
            } else if keys.contains("albumartist") || keys.contains("tpe2") {
                tags.albumArtist = rawTag.value
            } else if keys.contains("artist") || keys.contains("tpe1") {
                tags.artist = rawTag.value
            } else if keys.contains("composer") || keys.contains("tcom") {
                tags.composer = rawTag.value
            } else if keys.contains("genre") || keys.contains("tcon") {
                tags.genre = rawTag.value
            } else if keys.contains("year") || keys.contains("tyer") || keys.contains("date") {
                tags.year = parseFirstInteger(rawTag.value)
            } else if keys.contains("tracknumber") || keys.contains("trck") {
                let parsed = parseNumberPair(rawTag.value)
                tags.trackNumber = parsed.current
                tags.trackTotal = parsed.total
            } else if keys.contains("discnumber") || keys.contains("tpos") {
                let parsed = parseNumberPair(rawTag.value)
                tags.discNumber = parsed.current
                tags.discTotal = parsed.total
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let rawTagsJSON = String(
            data: try encoder.encode(rawTags),
            encoding: .utf8
        ) ?? "[]"

        return AudioMetadataNormalizationResult(tags: tags, rawTagsJSON: rawTagsJSON)
    }

    private static func normalizedKeys(for rawTag: AudioRawTag) -> Set<String> {
        [
            rawTag.keySpace,
            rawTag.key,
            rawTag.commonKey,
            rawTag.identifier
        ]
        .compactMap { $0?.lowercased() }
        .reduce(into: Set<String>()) { result, value in
            result.insert(value)
            result.insert(value.replacingOccurrences(of: "_", with: ""))
            result.insert(value.replacingOccurrences(of: "-", with: ""))
            result.insert(value.components(separatedBy: ".").last ?? value)
        }
    }

    private static func parseFirstInteger(_ value: String) -> Int? {
        let prefix = value.prefix { $0.isNumber }
        return Int(prefix)
    }

    private static func parseNumberPair(_ value: String) -> (current: Int?, total: Int?) {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        let current = parts.first.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let total = parts.dropFirst().first.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return (current, total)
    }
}
