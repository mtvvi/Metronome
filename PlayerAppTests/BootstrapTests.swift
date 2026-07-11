import XCTest
@testable import PlayerApp

final class BootstrapTests: XCTestCase {
    func testDependencyContainerPropagatesDatabaseOpenFailure() {
        XCTAssertThrowsError(
            try DependencyContainer.bootstrap(
                databasePath: "/unavailable/Library.sqlite",
                databaseOpener: FailingPlayerDatabaseOpener()
            )
        ) { error in
            XCTAssertEqual(error as? TestBootstrapError, .databaseLocked)
        }
    }

    @MainActor
    func testDependencyContainerBuildsSourcesViewModelWithMusicImportAvailable() {
        let database = try? PlayerDatabase.inMemory()
        let repository = database.map(GRDBTrackRepository.init(database:))
        let container = DependencyContainer(repository: repository)

        let viewModel = container.makeSourcesViewModel()

        XCTAssertEqual(viewModel.canImportMusicLibrary, repository != nil)
    }

    @MainActor
    func testBootstrapStorePublishesFailureAndCanRetry() async {
        let expectedError = AppError.databaseBootstrapFailed(diagnostic: "database locked")
        let bootstrapper = SequencedDependencyContainerBootstrapper(
            results: [
                .failure(expectedError),
                .success(DependencyContainer())
            ]
        )
        let store = AppBootstrapStore(bootstrapper: bootstrapper)

        await store.loadIfNeeded()

        XCTAssertEqual(store.error, expectedError)
        XCTAssertNil(store.container)

        await store.retry()

        XCTAssertNil(store.error)
        XCTAssertNotNil(store.container)
    }

    @MainActor
    func testConfirmedDatabaseResetRetriesBootstrap() async {
        let resetter = RecordingLibraryDatabaseResetter()
        let bootstrapper = SequencedDependencyContainerBootstrapper(
            results: [.success(DependencyContainer())]
        )
        let store = AppBootstrapStore(
            bootstrapper: bootstrapper,
            databaseResetter: resetter
        )

        await store.resetLibrary()

        let resetCount = await resetter.resetCount
        XCTAssertEqual(resetCount, 1)
        XCTAssertNotNil(store.container)
    }

    @MainActor
    func testBootstrapStoreShutsDownPlaybackCoordinator() async {
        let playback = BootstrapPlaybackController()
        let container = DependencyContainer(
            playbackCoordinator: PlaybackCoordinator(playback: playback)
        )
        let store = AppBootstrapStore(
            bootstrapper: SequencedDependencyContainerBootstrapper(
                results: [.success(container)]
            )
        )
        await store.loadIfNeeded()

        await store.shutdown()

        XCTAssertEqual(playback.stopCount, 1)
    }

    @MainActor
    func testDatabaseResetShutsDownExistingContainerBeforeReload() async {
        let playback = BootstrapPlaybackController()
        let existing = DependencyContainer(
            playbackCoordinator: PlaybackCoordinator(playback: playback)
        )
        let replacement = DependencyContainer()
        let resetter = RecordingLibraryDatabaseResetter()
        let store = AppBootstrapStore(
            bootstrapper: SequencedDependencyContainerBootstrapper(
                results: [.success(existing), .success(replacement)]
            ),
            databaseResetter: resetter
        )
        await store.loadIfNeeded()

        await store.resetLibrary()

        let resetCount = await resetter.resetCount
        XCTAssertEqual(playback.stopCount, 1)
        XCTAssertEqual(resetCount, 1)
        XCTAssertNotNil(store.container)
    }

    @MainActor
    func testContainerLibraryAndPlaybackStoreShareCoordinatorState() async throws {
        let repository = GRDBTrackRepository(database: try PlayerDatabase.inMemory())
        let playback = BootstrapPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        let container = DependencyContainer(
            repository: repository,
            playbackCoordinator: coordinator
        )
        let library = container.makeLibraryViewModel()
        let store = container.makePlaybackStore()
        let item = PlaybackItem(
            id: "shared-track",
            url: URL(fileURLWithPath: "/music/shared.flac"),
            metadata: NowPlayingTrackMetadata(fileName: "shared.flac")
        )

        store.start()
        try await coordinator.play(item: item)
        for _ in 0..<50 where library.currentlyPlayingTrackID == nil {
            await Task.yield()
        }

        XCTAssertEqual(store.snapshot.currentItem?.id, item.id)
        XCTAssertEqual(library.currentlyPlayingTrackID, item.id)
        store.stopObserving()
        await coordinator.shutdown()
    }
}

private struct FailingPlayerDatabaseOpener: PlayerDatabaseOpening {
    func open(at path: String) throws -> PlayerDatabase {
        throw TestBootstrapError.databaseLocked
    }
}

private enum TestBootstrapError: Error, Equatable {
    case databaseLocked
}

private actor SequencedDependencyContainerBootstrapper: DependencyContainerBootstrapping {
    private var results: [Result<DependencyContainer, AppError>]

    init(results: [Result<DependencyContainer, AppError>]) {
        self.results = results
    }

    func bootstrap() async -> Result<DependencyContainer, AppError> {
        guard !results.isEmpty else {
            return .failure(.databaseBootstrapFailed(diagnostic: "No result configured."))
        }

        return results.removeFirst()
    }
}

private actor RecordingLibraryDatabaseResetter: LibraryDatabaseResetting {
    private(set) var resetCount = 0

    func resetLibraryDatabase() async throws {
        resetCount += 1
    }
}

private final class BootstrapPlaybackController: PlaybackControlling, @unchecked Sendable {
    private(set) var stopCount = 0

    func play(url: URL) throws {}
    func resume() throws {}
    func pause() {}
    func stop() { stopCount += 1 }
    func seek(to time: TimeInterval) throws {}
}
