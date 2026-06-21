import XCTest
@testable import PlayerApp

final class LibraryPlaybackTests: XCTestCase {
    func testCoordinatorResolvesTrackURLAndStartsPlayback() throws {
        let playback = FakePlaybackController()
        let coordinator = LibraryTrackPlaybackCoordinator(
            sourceRootRepository: FakeSourceRootRepository(sourceRoots: [Self.sourceRoot()]),
            sourceAccess: FakeSourceRootAccess(rootURL: URL(fileURLWithPath: "/music")),
            playback: playback
        )

        try coordinator.play(track: Self.track(relativePath: "Albums/Kind of Blue/01 So What.flac"))

        XCTAssertEqual(
            playback.playedURLs,
            [URL(fileURLWithPath: "/music/Albums/Kind of Blue/01 So What.flac")]
        )
    }

    func testCoordinatorRejectsTracksWithoutRelativePath() {
        let coordinator = LibraryTrackPlaybackCoordinator(
            sourceRootRepository: FakeSourceRootRepository(sourceRoots: [Self.sourceRoot()]),
            sourceAccess: FakeSourceRootAccess(rootURL: URL(fileURLWithPath: "/music")),
            playback: FakePlaybackController()
        )

        XCTAssertThrowsError(try coordinator.play(track: Self.track(relativePath: nil))) { error in
            XCTAssertEqual(error as? LibraryTrackPlaybackError, .missingRelativePath)
        }
    }

    @MainActor
    func testViewModelPlaysSelectedRow() async {
        let playback = FakeLibraryTrackPlaybackStarter()
        let nowPlaying = FakeNowPlayingUpdater()
        let viewModel = LibraryViewModel(
            searchRepository: FakePlaybackSearchRepository(libraryResults: [
                TrackSearchResult(track: Self.track(relativePath: "song.flac"))
            ]),
            playbackStarter: playback,
            nowPlayingUpdater: nowPlaying
        )

        await viewModel.refresh()
        let row = viewModel.rows[0]
        await viewModel.play(row: row)

        XCTAssertEqual(playback.playedTrackIDs, ["track-1"])
        XCTAssertEqual(viewModel.currentlyPlayingTrackID, "track-1")
        XCTAssertEqual(viewModel.statusMessage, "Playing So What.")
        XCTAssertEqual(
            nowPlaying.updates,
            [
                NowPlayingUpdate(
                    track: NowPlayingTrackMetadata(
                        fileName: "01 So What.flac",
                        title: "So What",
                        artist: "Miles Davis",
                        albumTitle: "Kind of Blue",
                        duration: 545
                    ),
                    elapsed: 0,
                    playbackRate: 1
                )
            ]
        )
    }

    @MainActor
    func testViewModelDoesNotUpdateNowPlayingWhenPlaybackFails() async {
        let playback = FakeLibraryTrackPlaybackStarter(playError: TestPlaybackError.playFailed)
        let nowPlaying = FakeNowPlayingUpdater()
        let viewModel = LibraryViewModel(
            searchRepository: FakePlaybackSearchRepository(libraryResults: [
                TrackSearchResult(track: Self.track(relativePath: "song.flac"))
            ]),
            playbackStarter: playback,
            nowPlayingUpdater: nowPlaying
        )

        await viewModel.refresh()
        await viewModel.play(row: viewModel.rows[0])

        XCTAssertTrue(nowPlaying.updates.isEmpty)
        XCTAssertNil(viewModel.currentlyPlayingTrackID)
        XCTAssertEqual(viewModel.statusMessage, "Unable to play So What.")
    }

    fileprivate static func sourceRoot() -> SourceRootRecord {
        SourceRootRecord(
            id: "source-1",
            kind: "securityScopedFolder",
            displayName: "Music",
            bookmarkData: Data(),
            baseURL: nil,
            isEnabled: true,
            lastScanDate: nil
        )
    }

    fileprivate static func track(relativePath: String?) -> TrackRecord {
        TrackRecord(
            id: "track-1",
            sourceRootID: "source-1",
            sourceKind: "securityScopedFolder",
            bookmarkData: nil,
            mediaPersistentID: nil,
            relativePath: relativePath,
            fileName: "01 So What.flac",
            fileSize: nil,
            modifiedDate: nil,
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
            albumArtist: nil,
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
    }
}

private final class FakeSourceRootRepository: SourceRootRepository, @unchecked Sendable {
    private var sourceRoots: [SourceRootRecord]

    init(sourceRoots: [SourceRootRecord]) {
        self.sourceRoots = sourceRoots
    }

    func fetchSourceRoot(id: String) throws -> SourceRootRecord? {
        sourceRoots.first { $0.id == id }
    }

    func fetchSourceRoots() throws -> [SourceRootRecord] {
        sourceRoots
    }

    func upsertSourceRoots(_ sourceRoots: [SourceRootRecord]) throws {
        self.sourceRoots = sourceRoots
    }
}

private final class FakePlaybackSearchRepository: SearchRepository, @unchecked Sendable {
    private let libraryResults: [TrackSearchResult]

    init(libraryResults: [TrackSearchResult]) {
        self.libraryResults = libraryResults
    }

    func fetchLibraryTracks(limit: Int) throws -> [TrackSearchResult] {
        libraryResults
    }

    func searchTracks(matching query: String, limit: Int) throws -> [TrackSearchResult] {
        []
    }
}

private struct FakeSourceRootAccess: SourceRootAccessing {
    var rootURL: URL

    func makeSecurityScopedSource(from url: URL) throws -> SourceRootRecord {
        LibraryPlaybackTests.sourceRoot()
    }

    func resolve(_ sourceRoot: SourceRootRecord) throws -> SecurityScopedResource {
        SecurityScopedResource(url: rootURL, didStartAccessing: false)
    }
}

private final class FakePlaybackController: PlaybackControlling, @unchecked Sendable {
    private(set) var playedURLs: [URL] = []

    func play(url: URL) throws {
        playedURLs.append(url)
    }

    func resume() throws {}
    func pause() {}
    func stop() {}
    func seek(to time: TimeInterval) throws {}
}

private final class FakeLibraryTrackPlaybackStarter: LibraryTrackPlaybackStarting, @unchecked Sendable {
    private(set) var playedTrackIDs: [String] = []
    private let playError: Error?

    init(playError: Error? = nil) {
        self.playError = playError
    }

    func play(track: TrackRecord) throws {
        if let playError {
            throw playError
        }

        playedTrackIDs.append(track.id)
    }
}

private struct NowPlayingUpdate: Equatable {
    var track: NowPlayingTrackMetadata
    var elapsed: TimeInterval
    var playbackRate: Double
}

@MainActor
private final class FakeNowPlayingUpdater: NowPlayingUpdating {
    private(set) var updates: [NowPlayingUpdate] = []

    func update(
        track: NowPlayingTrackMetadata,
        elapsed: TimeInterval,
        playbackRate: Double
    ) {
        updates.append(
            NowPlayingUpdate(
                track: track,
                elapsed: elapsed,
                playbackRate: playbackRate
            )
        )
    }

    func clear() {
        updates = []
    }
}

private enum TestPlaybackError: Error {
    case playFailed
}
