import Foundation
import GRDB

struct TrackRecord: Codable, Equatable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tracks"

    var id: String
    var sourceRootID: String
    var sourceKind: String
    var playbackLocatorKind: String = "securityScopedSource"
    var availabilityReason: String? = nil
    var lastSeenScanID: String? = nil
    var bookmarkData: Data?
    var mediaPersistentID: Int64?
    var relativePath: String?
    var fileName: String
    var fileSize: Int64?
    var modifiedDate: Double?
    var contentHash: String?
    var containerFormat: String?
    var codec: String?
    var sampleRate: Double?
    var bitDepth: Int?
    var channelCount: Int?
    var duration: Double?
    var totalFrames: Int64?
    var bitrate: Int?
    var isLossless: Bool
    var isDSD: Bool
    var dsdRate: Int?
    var title: String?
    var album: String?
    var albumArtist: String?
    var artist: String?
    var composer: String?
    var genre: String?
    var year: Int?
    var discNumber: Int?
    var discTotal: Int?
    var trackNumber: Int?
    var trackTotal: Int?
    var rawTagsJSON: String? = nil
    var sortTitle: String?
    var sortAlbum: String?
    var sortArtist: String?
    var musicBrainzID: String?
    var replayGainTrackGain: Double?
    var replayGainAlbumGain: Double?
    var replayGainTrackPeak: Double?
    var replayGainAlbumPeak: Double?
    var artworkID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceRootID = "source_root_id"
        case sourceKind = "source_kind"
        case playbackLocatorKind = "playback_locator_kind"
        case availabilityReason = "availability_reason"
        case lastSeenScanID = "last_seen_scan_id"
        case bookmarkData = "bookmark_data"
        case mediaPersistentID = "media_persistent_id"
        case relativePath = "relative_path"
        case fileName = "file_name"
        case fileSize = "file_size"
        case modifiedDate = "modified_date"
        case contentHash = "content_hash"
        case containerFormat = "container_format"
        case codec
        case sampleRate = "sample_rate"
        case bitDepth = "bit_depth"
        case channelCount = "channel_count"
        case duration
        case totalFrames = "total_frames"
        case bitrate
        case isLossless = "is_lossless"
        case isDSD = "is_dsd"
        case dsdRate = "dsd_rate"
        case title
        case album
        case albumArtist = "album_artist"
        case artist
        case composer
        case genre
        case year
        case discNumber = "disc_number"
        case discTotal = "disc_total"
        case trackNumber = "track_number"
        case trackTotal = "track_total"
        case rawTagsJSON = "raw_tags_json"
        case sortTitle = "sort_title"
        case sortAlbum = "sort_album"
        case sortArtist = "sort_artist"
        case musicBrainzID = "musicbrainz_id"
        case replayGainTrackGain = "replaygain_track_gain"
        case replayGainAlbumGain = "replaygain_album_gain"
        case replayGainTrackPeak = "replaygain_track_peak"
        case replayGainAlbumPeak = "replaygain_album_peak"
        case artworkID = "artwork_id"
    }
}
