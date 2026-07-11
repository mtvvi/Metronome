protocol TrackRepository: Sendable {
    func upsertTracks(_ tracks: [TrackRecord]) throws
}

enum LibraryChange: Equatable, Sendable {
    case tracksChanged
}

protocol LibraryChangeObservingRepository: Sendable {
    func libraryChanges() -> AsyncStream<LibraryChange>
}

protocol ArtworkRepository: Sendable {
    func upsertArtwork(_ artworkRecords: [ArtworkRecord]) throws
    func fetchArtwork(id: String) throws -> ArtworkRecord?
}

protocol TrackLookupRepository: Sendable {
    func fetchTracks(ids: [String]) throws -> [TrackRecord]
}

struct LibraryTrackCursor: Equatable, Sendable {
    var albumSort: String
    var discNumber: Int
    var trackNumber: Int
    var fileName: String
    var id: String
}

struct LibraryTrackPage: Equatable, Sendable {
    var tracks: [TrackRecord]
    var nextCursor: LibraryTrackCursor?
    var hasMore: Bool
}

struct AlbumSummary: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var albumArtist: String
    var trackCount: Int
    var artworkID: String?
}

struct ArtistSummary: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var albumCount: Int
    var trackCount: Int
}

protocol LibraryBrowsingRepository: Sendable {
    func fetchTrackPage(after cursor: LibraryTrackCursor?, limit: Int) throws -> LibraryTrackPage
    func fetchAlbums() throws -> [AlbumSummary]
    func fetchArtists() throws -> [ArtistSummary]
    func fetchTracks(album: String, albumArtist: String) throws -> [TrackRecord]
    func fetchTracks(artist: String) throws -> [TrackRecord]
}
