import XCTest
@testable import PlayerApp

final class SourceReconcilerTests: XCTestCase {
    func testRejectsDuplicateAndNestedRoots() {
        let existing = SourceRootRecord(
            id: "root",
            kind: "securityScopedFolder",
            displayName: "Music",
            bookmarkData: Data(),
            baseURL: URL(fileURLWithPath: "/Files/Music").absoluteString,
            isEnabled: true,
            lastScanDate: nil
        )

        XCTAssertThrowsError(try SourceReconciler.validateCandidate(
            URL(fileURLWithPath: "/Files/Music"), against: [existing]
        )) { XCTAssertEqual($0 as? SourceRootConflict, .duplicate(existingID: "root")) }
        XCTAssertThrowsError(try SourceReconciler.validateCandidate(
            URL(fileURLWithPath: "/Files/Music/Jazz"), against: [existing]
        )) { XCTAssertEqual($0 as? SourceRootConflict, .nested(existingID: "root")) }
        XCTAssertNoThrow(try SourceReconciler.validateCandidate(
            URL(fileURLWithPath: "/Files/Other"), against: [existing]
        ))
    }

    func testSuccessfulReconciliationDeletesUnseenTracksFromDatabaseAndFTS() throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBTrackRepository(database: database)
        let source = SourceRootRecord(
            id: "root", kind: "securityScopedFolder", displayName: "Music",
            bookmarkData: nil, baseURL: nil, isEnabled: true, lastScanDate: nil
        )
        try repository.upsertSourceRoots([source])
        var old = makeReconciledTrack(id: "old", path: "old.flac")
        old.lastSeenScanID = "previous"
        try repository.upsertTracks([old])
        let current = makeReconciledTrack(id: "current", path: "current.flac")

        let result = try repository.reconcileSource(
            sourceRootID: source.id,
            scanID: "new",
            tracks: [current]
        )

        XCTAssertEqual(result.deletedTrackIDs, ["old"])
        XCTAssertTrue(try repository.searchTracks(matching: "old", limit: 10).isEmpty)
        XCTAssertEqual(try repository.fetchTracks(ids: ["current"]).map(\.id), ["current"])
    }
}

private func makeReconciledTrack(id: String, path: String) -> TrackRecord {
    TrackRecord(
        id: id, sourceRootID: "root", sourceKind: "securityScopedFolder",
        bookmarkData: nil, mediaPersistentID: nil, relativePath: path,
        fileName: path, fileSize: nil, modifiedDate: nil, contentHash: nil,
        containerFormat: "FLAC", codec: "FLAC", sampleRate: 44_100,
        bitDepth: 16, channelCount: 2, duration: nil, totalFrames: nil,
        bitrate: nil, isLossless: true, isDSD: false, dsdRate: nil,
        title: id, album: nil, albumArtist: nil, artist: nil, composer: nil,
        genre: nil, year: nil, discNumber: nil, discTotal: nil,
        trackNumber: nil, trackTotal: nil, sortTitle: nil, sortAlbum: nil,
        sortArtist: nil, musicBrainzID: nil, replayGainTrackGain: nil,
        replayGainAlbumGain: nil, replayGainTrackPeak: nil,
        replayGainAlbumPeak: nil, artworkID: nil
    )
}
