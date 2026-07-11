import XCTest
@testable import PlayerApp

final class QueuePersistenceTests: XCTestCase {
    func testQueueSnapshotRoundTripsThroughGRDB() throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBQueueRepository(database: database)
        let snapshot = PersistedQueueSnapshot(
            itemIDs: ["one", "two", "three"],
            originalItemIDs: ["two", "one", "three"],
            currentIndex: 1,
            currentPosition: 42.5,
            repeatMode: .all,
            isShuffleEnabled: true
        )

        try repository.save(snapshot)

        XCTAssertEqual(try repository.load(), snapshot)
    }

    func testClearingQueueRemovesPersistedSnapshot() throws {
        let database = try PlayerDatabase.inMemory()
        let repository = GRDBQueueRepository(database: database)
        try repository.save(PersistedQueueSnapshot(
            itemIDs: ["one"],
            currentIndex: 0,
            currentPosition: 0,
            repeatMode: .off,
            isShuffleEnabled: false
        ))

        try repository.clear()

        XCTAssertNil(try repository.load())
    }

    func testRestoredCoordinatorDoesNotAutoPlay() async throws {
        let backend = QueuePersistencePlaybackBackend()
        let coordinator = PlaybackCoordinator(playback: backend)
        let items = [
            PlaybackItem(
                id: "one",
                url: URL(fileURLWithPath: "/music/one.flac"),
                metadata: NowPlayingTrackMetadata(fileName: "one.flac")
            )
        ]

        await coordinator.restoreQueue(items: items, currentIndex: 0, elapsed: 15)
        let snapshot = await coordinator.currentSnapshot

        XCTAssertEqual(snapshot.status, .paused)
        XCTAssertEqual(snapshot.currentItem?.id, "one")
        XCTAssertEqual(snapshot.elapsed, 15)
        XCTAssertTrue(backend.playedURLs.isEmpty)
    }
}

private final class QueuePersistencePlaybackBackend: PlaybackControlling, @unchecked Sendable {
    private(set) var playedURLs: [URL] = []

    func play(url: URL) throws { playedURLs.append(url) }
    func resume() throws {}
    func pause() {}
    func stop() {}
    func seek(to time: TimeInterval) throws {}
}
