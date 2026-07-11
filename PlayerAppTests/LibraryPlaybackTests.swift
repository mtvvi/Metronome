import XCTest
@testable import PlayerApp

final class LibraryPlaybackTests: XCTestCase {
    func testCoordinatorResolvesTrackURLAndStartsPlayback() async throws {
        let playback = FakePlaybackItemController()
        let coordinator = LibraryTrackPlaybackCoordinator(
            locatorResolver: PlaybackLocatorResolver(
                sourceRootRepository: FakeSourceRootRepository(sourceRoots: [Self.sourceRoot()]),
                sourceAccess: FakeSourceRootAccess(rootURL: URL(fileURLWithPath: "/music")),
                musicItemResolver: FakeMusicItemAssetResolver()
            ),
            playback: playback
        )

        try await coordinator.play(track: Self.track(relativePath: "Albums/Kind of Blue/01 So What.flac"))
        let playedItems = await playback.playedItems

        XCTAssertEqual(
            playedItems.map(\.url),
            [URL(fileURLWithPath: "/music/Albums/Kind of Blue/01 So What.flac")]
        )
    }

    func testCoordinatorRejectsTracksWithoutRelativePath() async {
        let coordinator = LibraryTrackPlaybackCoordinator(
            locatorResolver: PlaybackLocatorResolver(
                sourceRootRepository: FakeSourceRootRepository(sourceRoots: [Self.sourceRoot()]),
                sourceAccess: FakeSourceRootAccess(rootURL: URL(fileURLWithPath: "/music")),
                musicItemResolver: FakeMusicItemAssetResolver()
            ),
            playback: FakePlaybackItemController()
        )

        do {
            try await coordinator.play(track: Self.track(relativePath: nil))
            XCTFail("Expected a missing relative path error.")
        } catch {
            XCTAssertEqual(
                error as? LibraryTrackPlaybackError,
                .unavailable(.missingLocator)
            )
        }
    }

    func testCollectionPlaybackReportsUnavailableTracksThatWereSkipped() async throws {
        let playback = FakePlaybackItemController()
        let coordinator = LibraryTrackPlaybackCoordinator(
            locatorResolver: PlaybackLocatorResolver(
                sourceRootRepository: FakeSourceRootRepository(sourceRoots: [Self.sourceRoot()]),
                sourceAccess: FakeSourceRootAccess(rootURL: URL(fileURLWithPath: "/music")),
                musicItemResolver: FakeMusicItemAssetResolver()
            ),
            playback: playback
        )
        let playable = Self.track(relativePath: "song.flac")
        let unavailable = Self.track(relativePath: nil)

        let summary = try await coordinator.play(tracks: [playable, unavailable])

        XCTAssertEqual(
            summary,
            LibraryCollectionPlaybackSummary(
                playableCount: 1,
                skippedCount: 1,
                firstPlayedTrackID: "track-1"
            )
        )
        let queuedIDs = await playback.queuedItems.map(\.id)
        XCTAssertEqual(queuedIDs, ["track-1"])
    }

    func testResolverRejectsPathTraversalOutsideSelectedFolder() async {
        let stopCounter = StopAccessCounter()
        let resolver = PlaybackLocatorResolver(
            sourceRootRepository: FakeSourceRootRepository(sourceRoots: [Self.sourceRoot()]),
            sourceAccess: FakeSourceRootAccess(
                rootURL: URL(fileURLWithPath: "/music"),
                stopCounter: stopCounter
            ),
            musicItemResolver: FakeMusicItemAssetResolver()
        )

        do {
            _ = try await resolver.resolve(
                .securityScopedSource(sourceRootID: "source-1", relativePath: "../private/song.flac")
            )
            XCTFail("Expected path traversal to be rejected.")
        } catch {
            XCTAssertEqual(error as? PlaybackLocatorError, .pathOutsideSourceRoot)
        }
        XCTAssertEqual(stopCounter.count, 1)
    }

    func testResolverPersistsRefreshedStaleBookmark() async throws {
        let repository = FakeSourceRootRepository(sourceRoots: [Self.sourceRoot()])
        let refreshedBookmark = Data([1, 2, 3])
        let resolver = PlaybackLocatorResolver(
            sourceRootRepository: repository,
            sourceAccess: FakeSourceRootAccess(
                rootURL: URL(fileURLWithPath: "/music"),
                refreshedBookmarkData: refreshedBookmark
            ),
            musicItemResolver: FakeMusicItemAssetResolver()
        )

        let location = try await resolver.resolve(
            .securityScopedSource(sourceRootID: "source-1", relativePath: "song.flac")
        )
        defer { location.stopAccessing() }

        XCTAssertEqual(
            try repository.fetchSourceRoot(id: "source-1")?.bookmarkData,
            refreshedBookmark
        )
    }

    func testAppDocumentsSourceResolvesWithoutSecurityScopedBookmark() throws {
        let expectedURL = URL(fileURLWithPath: "/app/Documents")
        let access = SourceRootAccess(appDocumentsRoot: { expectedURL })
        var source = Self.sourceRoot()
        source.kind = "appDocuments"
        source.bookmarkData = nil

        let resource = try access.resolve(source)

        XCTAssertEqual(resource.url, expectedURL)
        resource.stopAccessing()
    }

    func testMusicLocatorResolvesCurrentAssetURLByPersistentID() async throws {
        let expectedURL = URL(fileURLWithPath: "/current/music/song.m4a")
        let resolver = PlaybackLocatorResolver(
            sourceRootRepository: FakeSourceRootRepository(sourceRoots: []),
            sourceAccess: FakeSourceRootAccess(rootURL: URL(fileURLWithPath: "/unused")),
            musicItemResolver: FakeMusicItemAssetResolver(urls: [42: expectedURL])
        )

        let location = try await resolver.resolve(.musicPersistentID(42))

        XCTAssertEqual(location.url, expectedURL)
    }

    func testMusicLocatorReturnsTypedUnavailability() async {
        let resolver = PlaybackLocatorResolver(
            sourceRootRepository: FakeSourceRootRepository(sourceRoots: []),
            sourceAccess: FakeSourceRootAccess(rootURL: URL(fileURLWithPath: "/unused")),
            musicItemResolver: FakeMusicItemAssetResolver(
                error: MusicItemAssetResolutionError.unavailable(.cloudOnly)
            )
        )

        do {
            _ = try await resolver.resolve(.musicPersistentID(42))
            XCTFail("Expected a typed Music Library availability error.")
        } catch {
            XCTAssertEqual(
                error as? MusicItemAssetResolutionError,
                .unavailable(.cloudOnly)
            )
        }
    }

    func testRowExposesPersistedPlaybackAvailability() {
        var track = Self.track(relativePath: nil)
        track.playbackLocatorKind = PlaybackLocatorKind.musicPersistentID.rawValue
        track.mediaPersistentID = 42
        track.availabilityReason = PlaybackUnavailabilityReason.cloudOnly.rawValue

        let row = LibraryTrackRow(track: track)

        XCTAssertEqual(row.playbackAvailability, .unavailable(.cloudOnly))
    }

    @MainActor
    func testViewModelPlaysSelectedRow() async {
        let playback = FakeLibraryTrackPlaybackStarter()
        let viewModel = LibraryViewModel(
            searchRepository: FakePlaybackSearchRepository(libraryResults: [
                TrackSearchResult(track: Self.track(relativePath: "song.flac"))
            ]),
            playbackStarter: playback
        )

        await viewModel.refresh()
        let row = viewModel.rows[0]
        await viewModel.play(row: row)

        XCTAssertEqual(playback.playedTrackIDs, ["track-1"])
        XCTAssertEqual(viewModel.currentlyPlayingTrackID, "track-1")
        XCTAssertEqual(
            viewModel.notice,
            LibraryNotice(kind: .information, message: "Playing So What.")
        )
        XCTAssertEqual(viewModel.rows.map(\.id), ["track-1"])
        XCTAssertNil(viewModel.emptyStateMessage)
        XCTAssertNil(viewModel.loadError)
    }

    @MainActor
    func testViewModelDoesNotUpdateNowPlayingWhenPlaybackFails() async {
        let playback = FakeLibraryTrackPlaybackStarter(playError: TestPlaybackError.playFailed)
        let viewModel = LibraryViewModel(
            searchRepository: FakePlaybackSearchRepository(libraryResults: [
                TrackSearchResult(track: Self.track(relativePath: "song.flac"))
            ]),
            playbackStarter: playback
        )

        await viewModel.refresh()
        await viewModel.play(row: viewModel.rows[0])

        XCTAssertNil(viewModel.currentlyPlayingTrackID)
        XCTAssertEqual(
            viewModel.notice,
            LibraryNotice(kind: .error, message: "Unable to play So What.")
        )
        XCTAssertEqual(viewModel.rows.map(\.id), ["track-1"])
        XCTAssertNil(viewModel.emptyStateMessage)
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
    var refreshedBookmarkData: Data?
    var stopCounter: StopAccessCounter?

    init(
        rootURL: URL,
        refreshedBookmarkData: Data? = nil,
        stopCounter: StopAccessCounter? = nil
    ) {
        self.rootURL = rootURL
        self.refreshedBookmarkData = refreshedBookmarkData
        self.stopCounter = stopCounter
    }

    func makeSecurityScopedSource(from url: URL) throws -> SourceRootRecord {
        LibraryPlaybackTests.sourceRoot()
    }

    func resolve(_ sourceRoot: SourceRootRecord) throws -> SecurityScopedResource {
        SecurityScopedResource(
            url: rootURL,
            didStartAccessing: stopCounter != nil,
            refreshedBookmarkData: refreshedBookmarkData,
            stopAccessingHandler: { stopCounter?.increment() }
        )
    }
}

private final class StopAccessCounter: @unchecked Sendable {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private struct FakeMusicItemAssetResolver: MusicItemAssetResolving {
    var urls: [Int64: URL] = [:]
    var error: MusicItemAssetResolutionError?

    func resolveAssetURL(for persistentID: Int64) async throws -> URL {
        if let error {
            throw error
        }

        guard let url = urls[persistentID] else {
            throw MusicItemAssetResolutionError.itemNotFound(persistentID)
        }

        return url
    }
}

private actor FakePlaybackItemController: PlaybackQueueCoordinating {
    private(set) var playedItems: [PlaybackItem] = []
    private(set) var queuedItems: [PlaybackItem] = []

    func play(item: PlaybackItem) async throws {
        playedItems.append(item)
    }

    func play(items: [PlaybackItem], startingAt index: Int) async throws {
        queuedItems = items
        if items.indices.contains(index) {
            playedItems.append(items[index])
        }
    }

    func resume() async throws {}
    func pause() async {}
    func stop() async {}
    func seek(to time: TimeInterval) async throws {}
    func playNext(_ item: PlaybackItem) async { queuedItems.append(item) }
    func addLast(_ item: PlaybackItem) async { queuedItems.append(item) }
    func next() async throws -> Bool { false }
    func previous() async throws -> Bool { false }
    func removeFromQueue(id: String) async { queuedItems.removeAll { $0.id == id } }
    func moveQueueItem(from sourceIndex: Int, to destinationIndex: Int) async {}
    func setRepeatMode(_ mode: PlaybackRepeatMode) async {}
    func setShuffleEnabled(_ enabled: Bool) async {}
}

private final class FakeLibraryTrackPlaybackStarter: LibraryTrackPlaybackStarting, @unchecked Sendable {
    private(set) var playedTrackIDs: [String] = []
    private let playError: Error?

    init(playError: Error? = nil) {
        self.playError = playError
    }

    func play(track: TrackRecord) async throws {
        if let playError {
            throw playError
        }

        playedTrackIDs.append(track.id)
    }
}

private enum TestPlaybackError: Error {
    case playFailed
}
