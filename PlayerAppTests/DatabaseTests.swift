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

    func testFetchLibraryTracksReturnsImportedTracksInAlbumOrder() throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBTrackRepository(database: database)
        let sourceRoot = SourceRootRecord(
            id: "source-1",
            kind: "securityScopedFolder",
            displayName: "Documents",
            bookmarkData: nil,
            baseURL: nil,
            isEnabled: true,
            lastScanDate: nil
        )

        try repository.upsertSourceRoots([sourceRoot])
        try repository.upsertTracks([
            makeTrack(id: "track-2", album: "Kind of Blue", trackNumber: 2, fileName: "02 Freddie.flac"),
            makeTrack(id: "track-1", album: "Kind of Blue", trackNumber: 1, fileName: "01 So What.flac"),
            makeTrack(id: "track-3", album: "Blue Train", trackNumber: 1, fileName: "01 Blue Train.flac")
        ])

        let results = try repository.fetchLibraryTracks(limit: 10)

        XCTAssertEqual(results.map(\.track.id), ["track-3", "track-1", "track-2"])
    }

    private func makeTrack(
        id: String,
        album: String,
        trackNumber: Int,
        fileName: String
    ) -> TrackRecord {
        TrackRecord(
            id: id,
            sourceRootID: "source-1",
            sourceKind: "securityScopedFolder",
            bookmarkData: nil,
            mediaPersistentID: nil,
            relativePath: fileName,
            fileName: fileName,
            fileSize: nil,
            modifiedDate: nil,
            contentHash: nil,
            containerFormat: "FLAC",
            codec: "FLAC",
            sampleRate: 96_000,
            bitDepth: 24,
            channelCount: 2,
            duration: nil,
            totalFrames: nil,
            bitrate: nil,
            isLossless: true,
            isDSD: false,
            dsdRate: nil,
            title: nil,
            album: album,
            albumArtist: nil,
            artist: nil,
            composer: nil,
            genre: nil,
            year: nil,
            discNumber: nil,
            discTotal: nil,
            trackNumber: trackNumber,
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
    }
}
