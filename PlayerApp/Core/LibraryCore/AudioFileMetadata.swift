import Foundation

struct AudioFileMetadata: Equatable, Sendable {
    var fileName: String
    var containerFormat: String?
    var codec: String?
    var duration: TimeInterval?
    var sampleRate: Double?
    var bitDepth: Int?
    var channelCount: Int?
    var tags: AudioMetadataTags
    var artwork: AudioArtwork?
    var rawTagsJSON: String?
}

struct AudioMetadataTags: Equatable, Sendable {
    var title: String? = nil
    var album: String? = nil
    var albumArtist: String? = nil
    var artist: String? = nil
    var composer: String? = nil
    var genre: String? = nil
    var year: Int? = nil
    var discNumber: Int? = nil
    var discTotal: Int? = nil
    var trackNumber: Int? = nil
    var trackTotal: Int? = nil

    static let empty = AudioMetadataTags()
}

struct AudioArtwork: Equatable, Sendable {
    var data: Data
    var mimeType: String?
}
