import GRDB
import XCTest
@testable import PlayerApp

final class DatabaseTests: XCTestCase {
    func testMigrationsCreateLibraryTables() throws {
        let database = try PlayerDatabase.inMemory()

        let tableNames = try database.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT name
                FROM sqlite_master
                WHERE type IN ('table', 'virtual table')
                ORDER BY name
                """
            )
        }

        XCTAssertTrue(tableNames.contains("source_roots"))
        XCTAssertTrue(tableNames.contains("tracks"))
        XCTAssertTrue(tableNames.contains("artwork"))
        XCTAssertTrue(tableNames.contains("track_fts"))
    }

    func testBatchUpsertUpdatesSearchIndex() throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBTrackRepository(database: database)
        let sourceRoot = SourceRootRecord(
            id: "source-1",
            kind: "appDocuments",
            displayName: "Documents",
            bookmarkData: nil,
            baseURL: nil,
            isEnabled: true,
            lastScanDate: nil
        )

        try repository.upsertSourceRoots([sourceRoot])
        try repository.upsertTracks([
            TrackRecord(
                id: "track-1",
                sourceRootID: sourceRoot.id,
                sourceKind: sourceRoot.kind,
                bookmarkData: nil,
                mediaPersistentID: nil,
                relativePath: "Albums/Kind of Blue/01 So What.flac",
                fileName: "01 So What.flac",
                fileSize: 128,
                modifiedDate: 1_803_000_000,
                contentHash: nil,
                containerFormat: "FLAC",
                codec: "FLAC",
                sampleRate: 96_000,
                bitDepth: 24,
                channelCount: 2,
                duration: 545,
                totalFrames: nil,
                bitrate: nil,
                isLossless: true,
                isDSD: false,
                dsdRate: nil,
                title: "So What",
                album: "Kind of Blue",
                albumArtist: "Miles Davis",
                artist: "Miles Davis",
                composer: nil,
                genre: "Jazz",
                year: 1959,
                discNumber: nil,
                discTotal: nil,
                trackNumber: 1,
                trackTotal: nil,
                sortTitle: nil,
                sortAlbum: nil,
                sortArtist: nil,
                musicBrainzID: nil,
                replayGainTrackGain: nil,
                replayGainAlbumGain: nil,
                replayGainTrackPeak: nil,
                replayGainAlbumPeak: nil,
                artworkID: nil
            )
        ])

        var results = try repository.searchTracks(matching: "Miles", limit: 10)
        XCTAssertEqual(results.map(\.track.id), ["track-1"])

        try repository.upsertTracks([
            TrackRecord(
                id: "track-1",
                sourceRootID: sourceRoot.id,
                sourceKind: sourceRoot.kind,
                bookmarkData: nil,
                mediaPersistentID: nil,
                relativePath: "Albums/Kind of Blue/01 So What.flac",
                fileName: "01 So What.flac",
                fileSize: 128,
                modifiedDate: 1_803_000_001,
                contentHash: nil,
                containerFormat: "FLAC",
                codec: "FLAC",
                sampleRate: 96_000,
                bitDepth: 24,
                channelCount: 2,
                duration: 545,
                totalFrames: nil,
                bitrate: nil,
                isLossless: true,
                isDSD: false,
                dsdRate: nil,
                title: "Freddie Freeloader",
                album: "Kind of Blue",
                albumArtist: "Miles Davis",
                artist: "Miles Davis Quintet",
                composer: nil,
                genre: "Jazz",
                year: 1959,
                discNumber: nil,
                discTotal: nil,
                trackNumber: 2,
                trackTotal: nil,
                sortTitle: nil,
                sortAlbum: nil,
                sortArtist: nil,
                musicBrainzID: nil,
                replayGainTrackGain: nil,
                replayGainAlbumGain: nil,
                replayGainTrackPeak: nil,
                replayGainAlbumPeak: nil,
                artworkID: nil
            )
        ])

        results = try repository.searchTracks(matching: "Freddie", limit: 10)
        XCTAssertEqual(results.map(\.track.title), ["Freddie Freeloader"])
    }
}
