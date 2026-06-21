import XCTest
@testable import PlayerApp

final class MusicLibraryImporterTests: XCTestCase {
    func testRequestsAuthorizationBeforeImportingSongs() async throws {
        let authorization = FakeMusicLibraryAuthorization(statuses: [.notDetermined, .authorized])
        let query = FakeMusicLibraryQuery(items: [
            makeMediaItem(id: 42, assetURL: fileURL("song.m4a"))
        ])
        let repository = FakeMusicLibraryRepository()
        let importer = MusicLibraryImporter(
            authorization: authorization,
            query: query,
            sourceRootRepository: repository,
            trackRepository: repository
        )

        let summary = try await importer.importLocalMusicLibrary()

        XCTAssertEqual(authorization.requestCount, 1)
        XCTAssertEqual(summary.authorizationStatus, .authorized)
        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(repository.sourceRoots.map(\.kind), ["musicLibrary"])
        XCTAssertEqual(repository.tracks.map(\.mediaPersistentID), [42])
        XCTAssertEqual(repository.tracks.map(\.sourceKind), ["musicLibrary"])
    }

    func testDoesNotQueryWhenAuthorizationIsDenied() async throws {
        let authorization = FakeMusicLibraryAuthorization(statuses: [.denied])
        let query = FakeMusicLibraryQuery(items: [
            makeMediaItem(id: 42, assetURL: fileURL("song.m4a"))
        ])
        let repository = FakeMusicLibraryRepository()
        let importer = MusicLibraryImporter(
            authorization: authorization,
            query: query,
            sourceRootRepository: repository,
            trackRepository: repository
        )

        let summary = try await importer.importLocalMusicLibrary()

        XCTAssertEqual(summary.authorizationStatus, .denied)
        XCTAssertEqual(summary.importedCount, 0)
        XCTAssertEqual(query.queryCount, 0)
        XCTAssertTrue(repository.tracks.isEmpty)
    }

    func testSkipsProtectedAndUnavailableItems() async throws {
        let authorization = FakeMusicLibraryAuthorization(statuses: [.authorized])
        let query = FakeMusicLibraryQuery(items: [
            makeMediaItem(id: 1, assetURL: fileURL("readable.m4a"), hasProtectedAsset: false),
            makeMediaItem(id: 2, assetURL: fileURL("protected.m4p"), hasProtectedAsset: true),
            makeMediaItem(id: 3, assetURL: nil, hasProtectedAsset: false)
        ])
        let repository = FakeMusicLibraryRepository()
        let importer = MusicLibraryImporter(
            authorization: authorization,
            query: query,
            sourceRootRepository: repository,
            trackRepository: repository
        )

        let summary = try await importer.importLocalMusicLibrary()

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.protectedSkippedCount, 1)
        XCTAssertEqual(summary.unavailableSkippedCount, 1)
        XCTAssertEqual(repository.tracks.map(\.mediaPersistentID), [1])
    }

    func testIndexesImportedMusicLibraryTracksForSpotlight() async throws {
        let repository = FakeMusicLibraryRepository()
        let spotlightIndexer = FakeLibraryTrackSearchIndexer()
        let importer = MusicLibraryImporter(
            authorization: FakeMusicLibraryAuthorization(statuses: [.authorized]),
            query: FakeMusicLibraryQuery(items: [
                makeMediaItem(id: 1, assetURL: fileURL("readable.m4a"), hasProtectedAsset: false),
                makeMediaItem(id: 2, assetURL: fileURL("protected.m4p"), hasProtectedAsset: true)
            ]),
            sourceRootRepository: repository,
            trackRepository: repository,
            spotlightIndexer: spotlightIndexer
        )

        _ = try await importer.importLocalMusicLibrary()

        XCTAssertEqual(spotlightIndexer.indexedTracks.map(\.id), ["music-library-1"])
    }

    func testMusicLibraryImportSucceedsWhenSpotlightIndexingFails() async throws {
        let repository = FakeMusicLibraryRepository()
        let spotlightIndexer = FakeLibraryTrackSearchIndexer(indexError: TestError.indexFailed)
        let importer = MusicLibraryImporter(
            authorization: FakeMusicLibraryAuthorization(statuses: [.authorized]),
            query: FakeMusicLibraryQuery(items: [
                makeMediaItem(id: 1, assetURL: fileURL("readable.m4a"), hasProtectedAsset: false)
            ]),
            sourceRootRepository: repository,
            trackRepository: repository,
            spotlightIndexer: spotlightIndexer
        )

        let summary = try await importer.importLocalMusicLibrary()

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(repository.tracks.map(\.id), ["music-library-1"])
    }

    func testMapsMediaMetadataToTrackRecord() async throws {
        let item = makeMediaItem(
            id: 99,
            assetURL: fileURL("artist/album/01-title.m4a"),
            title: "Title",
            albumTitle: "Album",
            albumArtist: "Album Artist",
            artist: "Artist",
            composer: "Composer",
            genre: "Jazz",
            releaseYear: 1959,
            discNumber: 1,
            trackNumber: 2,
            duration: 123.5
        )
        let repository = FakeMusicLibraryRepository()
        let importer = MusicLibraryImporter(
            authorization: FakeMusicLibraryAuthorization(statuses: [.authorized]),
            query: FakeMusicLibraryQuery(items: [item]),
            sourceRootRepository: repository,
            trackRepository: repository
        )

        _ = try await importer.importLocalMusicLibrary()

        let track = try XCTUnwrap(repository.tracks.first)
        XCTAssertEqual(track.id, "music-library-99")
        XCTAssertEqual(track.fileName, "01-title.m4a")
        XCTAssertEqual(track.mediaPersistentID, 99)
        XCTAssertEqual(track.title, "Title")
        XCTAssertEqual(track.album, "Album")
        XCTAssertEqual(track.albumArtist, "Album Artist")
        XCTAssertEqual(track.artist, "Artist")
        XCTAssertEqual(track.composer, "Composer")
        XCTAssertEqual(track.genre, "Jazz")
        XCTAssertEqual(track.year, 1959)
        XCTAssertEqual(track.discNumber, 1)
        XCTAssertEqual(track.trackNumber, 2)
        XCTAssertEqual(track.duration, 123.5)
        XCTAssertEqual(track.relativePath, nil)
    }

    @MainActor
    func testSourcesViewModelShowsMusicLibraryImportCounts() async {
        let summary = MusicLibraryImportSummary(
            authorizationStatus: .authorized,
            importedCount: 3,
            protectedSkippedCount: 1,
            unavailableSkippedCount: 2
        )
        let viewModel = SourcesViewModel(
            musicLibraryImporter: FakeMusicLibraryImporter(summary: summary)
        )

        await viewModel.importMusicLibrary()

        XCTAssertEqual(viewModel.latestMusicLibraryImportSummary, summary)
        XCTAssertEqual(
            viewModel.statusMessage,
            "Imported 3 Music Library tracks. Skipped 1 protected and 2 unavailable."
        )
    }
}

private func makeMediaItem(
    id: Int64,
    assetURL: URL?,
    hasProtectedAsset: Bool = false,
    title: String? = nil,
    albumTitle: String? = nil,
    albumArtist: String? = nil,
    artist: String? = nil,
    composer: String? = nil,
    genre: String? = nil,
    releaseYear: Int? = nil,
    discNumber: Int? = nil,
    trackNumber: Int? = nil,
    duration: TimeInterval? = nil
) -> MusicLibraryMediaItem {
    MusicLibraryMediaItem(
        persistentID: id,
        assetURL: assetURL,
        hasProtectedAsset: hasProtectedAsset,
        title: title,
        albumTitle: albumTitle,
        albumArtist: albumArtist,
        artist: artist,
        composer: composer,
        genre: genre,
        releaseYear: releaseYear,
        discNumber: discNumber,
        trackNumber: trackNumber,
        duration: duration
    )
}

private final class FakeMusicLibraryAuthorization: MusicLibraryAuthorizationProviding, @unchecked Sendable {
    private var statuses: [MusicLibraryAuthorizationStatus]
    private(set) var requestCount = 0

    init(statuses: [MusicLibraryAuthorizationStatus]) {
        self.statuses = statuses
    }

    var currentStatus: MusicLibraryAuthorizationStatus {
        statuses.first ?? .denied
    }

    func requestAuthorization() async -> MusicLibraryAuthorizationStatus {
        requestCount += 1
        if statuses.count > 1 {
            statuses.removeFirst()
        }
        return statuses.first ?? .denied
    }
}

private final class FakeMusicLibraryQuery: MusicLibraryQuerying, @unchecked Sendable {
    private let items: [MusicLibraryMediaItem]
    private(set) var queryCount = 0

    init(items: [MusicLibraryMediaItem]) {
        self.items = items
    }

    func songs() -> [MusicLibraryMediaItem] {
        queryCount += 1
        return items
    }
}

private final class FakeMusicLibraryRepository: SourceRootRepository, TrackRepository, @unchecked Sendable {
    private(set) var sourceRoots: [SourceRootRecord] = []
    private(set) var tracks: [TrackRecord] = []

    func fetchSourceRoot(id: String) throws -> SourceRootRecord? {
        sourceRoots.first { $0.id == id }
    }

    func fetchSourceRoots() throws -> [SourceRootRecord] {
        sourceRoots
    }

    func upsertSourceRoots(_ sourceRoots: [SourceRootRecord]) throws {
        self.sourceRoots = sourceRoots
    }

    func upsertTracks(_ tracks: [TrackRecord]) throws {
        self.tracks = tracks
    }
}

private enum TestError: Error {
    case indexFailed
}

private final class FakeLibraryTrackSearchIndexer: LibraryTrackSearchIndexing, @unchecked Sendable {
    private(set) var indexedTracks: [TrackRecord] = []
    private let indexError: Error?

    init(indexError: Error? = nil) {
        self.indexError = indexError
    }

    func indexTracks(_ tracks: [TrackRecord]) async throws {
        if let indexError {
            throw indexError
        }

        indexedTracks = tracks
    }
}

private struct FakeMusicLibraryImporter: MusicLibraryImporting {
    var summary: MusicLibraryImportSummary

    func importLocalMusicLibrary() async throws -> MusicLibraryImportSummary {
        summary
    }
}

private func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: "/music/\(path)")
}
