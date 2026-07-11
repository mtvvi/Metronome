import Foundation
import SFBAudioEngine

struct SFBAudioMetadataReader: MetadataReading {
    private let loader: any SFBAudioMetadataLoading

    init(loader: any SFBAudioMetadataLoading = SFBAudioMetadataLoader()) {
        self.loader = loader
    }

    func readMetadata(from url: URL) async throws -> AudioFileMetadata {
        let snapshot = try loader.loadMetadataSnapshot(from: url)
        let normalized = try AudioMetadataTagNormalizer.normalize(rawTags: snapshot.rawTags)

        return AudioFileMetadata(
            fileName: snapshot.fileName ?? url.lastPathComponent,
            containerFormat: snapshot.containerFormat,
            codec: snapshot.codec,
            duration: snapshot.duration,
            sampleRate: snapshot.sampleRate,
            bitDepth: snapshot.bitDepth,
            channelCount: snapshot.channelCount,
            tags: normalized.tags,
            artwork: snapshot.artwork,
            rawTagsJSON: normalized.rawTagsJSON
        )
    }
}

protocol SFBAudioMetadataLoading: Sendable {
    func loadMetadataSnapshot(from url: URL) throws -> SFBAudioMetadataSnapshot
}

struct SFBAudioMetadataSnapshot: Equatable, Sendable {
    var fileName: String?
    var containerFormat: String?
    var codec: String?
    var duration: TimeInterval?
    var sampleRate: Double?
    var bitDepth: Int?
    var channelCount: Int?
    var artwork: AudioArtwork?
    var rawTags: [AudioRawTag]
}

struct SFBAudioMetadataLoader: SFBAudioMetadataLoading {
    func loadMetadataSnapshot(from url: URL) throws -> SFBAudioMetadataSnapshot {
        let audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let properties = audioFile.properties
        let metadata = audioFile.metadata

        return SFBAudioMetadataSnapshot(
            fileName: url.lastPathComponent,
            containerFormat: properties.formatName,
            codec: properties.formatName,
            duration: properties.duration,
            sampleRate: properties.sampleRate,
            bitDepth: properties.bitDepth,
            channelCount: properties.channelCount.map(Int.init),
            artwork: artwork(from: metadata),
            rawTags: rawTags(from: metadata)
        )
    }

    private func rawTags(from metadata: AudioMetadata) -> [AudioRawTag] {
        var tags: [AudioRawTag] = []

        appendRawTag("Title", metadata.title, to: &tags)
        appendRawTag("Artist", metadata.artist, to: &tags)
        appendRawTag("Album Title", metadata.albumTitle, to: &tags)
        appendRawTag("Album Artist", metadata.albumArtist, to: &tags)
        appendRawTag("Composer", metadata.composer, to: &tags)
        appendRawTag("Genre", metadata.genre, to: &tags)
        appendRawTag("Date", metadata.releaseDate, to: &tags)
        appendRawTag("Track Number", metadata.trackNumber.map(String.init), to: &tags)
        appendRawTag("Track Total", metadata.trackTotal.map(String.init), to: &tags)
        appendRawTag("Disc Number", metadata.discNumber.map(String.init), to: &tags)
        appendRawTag("Disc Total", metadata.discTotal.map(String.init), to: &tags)

        metadata.additionalMetadata?.forEach { key, value in
            appendRawTag(String(describing: key), String(describing: value), to: &tags)
        }

        return tags
    }

    private func appendRawTag(_ key: String, _ value: String?, to tags: inout [AudioRawTag]) {
        guard tags.count < 256, let value, !value.isEmpty else { return }

        tags.append(
            AudioRawTag(
                keySpace: "SFBAudioEngine",
                key: String(key.prefix(512)),
                commonKey: nil,
                identifier: nil,
                value: String(value.prefix(4_096))
            )
        )
    }

    private func artwork(from metadata: AudioMetadata) -> AudioArtwork? {
        guard let picture = metadata.attachedPictures.first else { return nil }
        let data = picture.imageData as Data
        guard data.count <= 20_000_000 else { return nil }
        return AudioArtwork(data: data, mimeType: nil)
    }
}
