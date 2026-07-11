import XCTest
@testable import PlayerApp

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testLoadsLibraryRowsFromRepository() async {
        let repository = FakeLibrarySearchRepository(
            libraryResults: [
                TrackSearchResult(track: Self.track(
                    id: "track-1",
                    title: "So What",
                    album: "Kind of Blue",
                    artist: "Miles Davis",
                    fileName: "01 So What.flac",
                    sampleRate: 96_000,
                    bitDepth: 24,
                    duration: 545,
                    isLossless: true
                ))
            ]
        )
        let viewModel = LibraryViewModel(searchRepository: repository)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.rows.map(\.id), ["track-1"])
        XCTAssertEqual(viewModel.rows.map(\.title), ["So What"])
        XCTAssertEqual(viewModel.rows.map(\.subtitle), ["Miles Davis - Kind of Blue"])
        XCTAssertEqual(viewModel.rows.map(\.technicalSummary), ["FLAC Lossless - 96 kHz / 24-bit - 9:05"])
        XCTAssertNil(viewModel.emptyStateMessage)
        XCTAssertNil(viewModel.loadError)
        XCTAssertNil(viewModel.notice)
    }

    func testSearchUsesQueryAndShowsEmptyState() async {
        let repository = FakeLibrarySearchRepository(searchResults: [])
        let viewModel = LibraryViewModel(searchRepository: repository)
        viewModel.searchText = "coltrane"

        await viewModel.refresh()

        XCTAssertEqual(repository.searchQueries, ["coltrane"])
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.emptyStateMessage, "No tracks match \"coltrane\".")
        XCTAssertNil(viewModel.loadError)
    }

    func testSearchResultsLoadBeyondInitialPage() async {
        let tracks = (1...3).map { index in
            TrackSearchResult(track: Self.track(
                id: "track-\(index)", title: "Track \(index)", album: "Album",
                artist: "Artist", fileName: "\(index).flac", sampleRate: 48_000,
                bitDepth: 24, duration: 60, isLossless: true
            ))
        }
        let repository = FakeLibrarySearchRepository(searchResults: tracks)
        let viewModel = LibraryViewModel(searchRepository: repository, resultLimit: 2)
        viewModel.searchText = "track"

        await viewModel.refresh()
        XCTAssertEqual(viewModel.rows.count, 2)
        XCTAssertTrue(viewModel.hasMoreTracks)

        await viewModel.loadMoreTracks()
        XCTAssertEqual(viewModel.rows.count, 3)
        XCTAssertFalse(viewModel.hasMoreTracks)
    }

    func testRefreshFailurePreservesPreviouslyLoadedRows() async {
        let expectedTrack = Self.track(
            id: "track-1",
            title: "So What",
            album: "Kind of Blue",
            artist: "Miles Davis",
            fileName: "01 So What.flac",
            sampleRate: 96_000,
            bitDepth: 24,
            duration: 545,
            isLossless: true
        )
        let repository = FakeLibrarySearchRepository(
            libraryResults: [TrackSearchResult(track: expectedTrack)]
        )
        let viewModel = LibraryViewModel(searchRepository: repository)

        await viewModel.refresh()
        repository.libraryError = TestLibraryRepositoryError.readFailed
        await viewModel.refresh()

        XCTAssertEqual(viewModel.rows.map(\.id), ["track-1"])
        XCTAssertEqual(viewModel.loadError?.code, .libraryLoadFailed)
        XCTAssertNil(viewModel.emptyStateMessage)
    }

    func testRepositoryChangeRefreshesVisibleLibrary() async throws {
        let repository = GRDBTrackRepository(database: try PlayerDatabase.inMemory())
        let viewModel = LibraryViewModel(searchRepository: repository, resultLimit: 20)
        await viewModel.refresh()
        await Task.yield()
        let track = Self.track(
            id: "observed-track",
            title: "Observed",
            album: "Changes",
            artist: "Database",
            fileName: "observed.flac",
            sampleRate: 48_000,
            bitDepth: 24,
            duration: 60,
            isLossless: true
        )

        try await Task.detached {
            try repository.upsertSourceRoots([SourceRootRecord(
                id: "source-1",
                kind: "securityScopedFolder",
                displayName: "Observed",
                bookmarkData: nil,
                baseURL: nil,
                isEnabled: true,
                lastScanDate: nil
            )])
            try repository.upsertTracks([track])
        }.value
        for _ in 0..<50 where viewModel.rows.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(viewModel.rows.map(\.id), ["observed-track"])
    }

    func testMissingRepositoryExposesRetryableLoadError() async {
        let viewModel = LibraryViewModel()

        await viewModel.refresh()

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.loadError?.code, .libraryUnavailable)
        XCTAssertNotNil(viewModel.loadError?.recoverySuggestion)
        XCTAssertNil(viewModel.emptyStateMessage)
    }

    func testCollectionPlaybackNoticeReportsSkippedUnavailableTracks() async {
        let playable = Self.track(
            id: "track-1", title: "One", album: "Album", artist: "Artist",
            fileName: "one.flac", sampleRate: 48_000, bitDepth: 24,
            duration: 60, isLossless: true
        )
        var unavailable = playable
        unavailable.id = "track-2"
        unavailable.relativePath = nil
        let starter = FakeCollectionPlaybackStarter(summary: .init(
            playableCount: 1,
            skippedCount: 1,
            firstPlayedTrackID: playable.id
        ))
        let viewModel = LibraryViewModel(playbackStarter: starter)

        await viewModel.play(
            rows: [LibraryTrackRow(track: playable), LibraryTrackRow(track: unavailable)],
            collectionName: "Album"
        )

        XCTAssertEqual(viewModel.currentlyPlayingTrackID, playable.id)
        XCTAssertEqual(
            viewModel.notice?.message,
            "Playing Album. 1 track queued; 1 unavailable track skipped."
        )
    }

    private static func track(
        id: String,
        title: String?,
        album: String?,
        artist: String?,
        fileName: String,
        sampleRate: Double?,
        bitDepth: Int?,
        duration: Double?,
        isLossless: Bool
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
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: 2,
            duration: duration,
            totalFrames: nil,
            bitrate: nil,
            isLossless: isLossless,
            isDSD: false,
            dsdRate: nil,
            title: title,
            album: album,
            albumArtist: nil,
            artist: artist,
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

private final class FakeLibrarySearchRepository: SearchRepository, @unchecked Sendable {
    private let libraryResults: [TrackSearchResult]
    private let searchResults: [TrackSearchResult]
    private(set) var searchQueries: [String] = []
    var libraryError: Error?
    var searchError: Error?

    init(
        libraryResults: [TrackSearchResult] = [],
        searchResults: [TrackSearchResult] = []
    ) {
        self.libraryResults = libraryResults
        self.searchResults = searchResults
    }

    func fetchLibraryTracks(limit: Int) throws -> [TrackSearchResult] {
        if let libraryError {
            throw libraryError
        }

        libraryResults
    }

    func searchTracks(matching query: String, limit: Int) throws -> [TrackSearchResult] {
        if let searchError {
            throw searchError
        }

        searchQueries.append(query)
        return Array(searchResults.prefix(limit))
    }
}

private enum TestLibraryRepositoryError: Error {
    case readFailed
}

private final class FakeCollectionPlaybackStarter: LibraryTrackPlaybackStarting, LibraryCollectionPlaybackStarting, @unchecked Sendable {
    let summary: LibraryCollectionPlaybackSummary

    init(summary: LibraryCollectionPlaybackSummary) {
        self.summary = summary
    }

    func play(track: TrackRecord) async throws {}

    func play(tracks: [TrackRecord]) async throws -> LibraryCollectionPlaybackSummary {
        summary
    }
}
