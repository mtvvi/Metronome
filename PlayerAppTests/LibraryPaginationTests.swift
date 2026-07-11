import XCTest
@testable import PlayerApp

final class LibraryPaginationTests: XCTestCase {
    func testKeysetPaginationReturnsEveryTrackWithoutDuplicates() throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBTrackRepository(database: database)
        try repository.upsertSourceRoots([SourceRootRecord(
            id: "root", kind: "appDocuments", displayName: "Documents",
            bookmarkData: nil, baseURL: nil, isEnabled: true, lastScanDate: nil
        )])
        try repository.upsertTracks((0..<450).map(makePageTrack))

        var cursor: LibraryTrackCursor?
        var ids: [String] = []
        repeat {
            let page = try repository.fetchTrackPage(after: cursor, limit: 100)
            ids.append(contentsOf: page.tracks.map(\.id))
            cursor = page.nextCursor
        } while cursor != nil

        XCTAssertEqual(ids.count, 450)
        XCTAssertEqual(Set(ids).count, 450)
    }

    func testAlbumAndArtistAggregatesUseNormalizedUnknownValues() throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBTrackRepository(database: database)
        try repository.upsertSourceRoots([SourceRootRecord(
            id: "root", kind: "appDocuments", displayName: "Documents",
            bookmarkData: nil, baseURL: nil, isEnabled: true, lastScanDate: nil
        )])
        try repository.upsertTracks([makePageTrack(0)])

        XCTAssertEqual(try repository.fetchAlbums().first?.title, "Unknown Album")
        XCTAssertEqual(try repository.fetchArtists().first?.name, "Unknown Artist")
    }
}

private func makePageTrack(_ index: Int) -> TrackRecord {
    TrackRecord(
        id: "track-\(index)", sourceRootID: "root", sourceKind: "appDocuments",
        bookmarkData: nil, mediaPersistentID: nil,
        relativePath: "track-\(index).flac", fileName: "track-\(index).flac",
        fileSize: nil, modifiedDate: nil, contentHash: nil,
        containerFormat: "FLAC", codec: "FLAC", sampleRate: 44_100,
        bitDepth: 16, channelCount: 2, duration: 180, totalFrames: nil,
        bitrate: nil, isLossless: true, isDSD: false, dsdRate: nil,
        title: "Track \(index)", album: nil, albumArtist: nil, artist: nil,
        composer: nil, genre: nil, year: nil, discNumber: nil, discTotal: nil,
        trackNumber: index, trackTotal: nil, sortTitle: nil, sortAlbum: nil,
        sortArtist: nil, musicBrainzID: nil, replayGainTrackGain: nil,
        replayGainAlbumGain: nil, replayGainTrackPeak: nil,
        replayGainAlbumPeak: nil, artworkID: nil
    )
}
