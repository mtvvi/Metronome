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
        let boundedRawTags = rawTags.prefix(256).map { rawTag in
            AudioRawTag(
                keySpace: rawTag.keySpace.map { String($0.prefix(512)) },
                key: rawTag.key.map { String($0.prefix(512)) },
                commonKey: rawTag.commonKey.map { String($0.prefix(512)) },
                identifier: rawTag.identifier.map { String($0.prefix(512)) },
                value: String(rawTag.value.prefix(4_096))
            )
        }

        for rawTag in boundedRawTags {
            let keys = normalizedKeys(for: rawTag)

            if keys.contains("title") {
                tags.title = rawTag.value
            } else if keys.contains("albumtitle") || keys.contains("albumname") || keys.contains("album") || keys.contains("talb") {
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
            } else if keys.contains("tracktotal") {
                tags.trackTotal = parseFirstInteger(rawTag.value)
            } else if keys.contains("discnumber") || keys.contains("tpos") {
                let parsed = parseNumberPair(rawTag.value)
                tags.discNumber = parsed.current
                tags.discTotal = parsed.total
            } else if keys.contains("disctotal") {
                tags.discTotal = parseFirstInteger(rawTag.value)
            } else if keys.contains("replaygaintrackgain") {
                tags.replayGainTrackGain = parseReplayGainNumber(rawTag.value)
            } else if keys.contains("replaygainalbumgain") {
                tags.replayGainAlbumGain = parseReplayGainNumber(rawTag.value)
            } else if keys.contains("replaygaintrackpeak") {
                tags.replayGainTrackPeak = parseReplayGainPeak(rawTag.value)
            } else if keys.contains("replaygainalbumpeak") {
                tags.replayGainAlbumPeak = parseReplayGainPeak(rawTag.value)
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let rawTagsJSON = String(
            data: try encoder.encode(boundedRawTags),
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
            result.insert(value.replacingOccurrences(of: " ", with: ""))
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

    private static func parseReplayGainNumber(_ value: String) -> Double? {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let token = normalizedValue.split(whereSeparator: { $0.isWhitespace }).first else {
            return Double(normalizedValue)
        }

        guard let value = Double(String(token)), value.isFinite else { return nil }
        return value
    }

    private static func parseReplayGainPeak(_ value: String) -> Double? {
        guard let peak = parseReplayGainNumber(value), peak > 0 else { return nil }
        return peak
    }
}
