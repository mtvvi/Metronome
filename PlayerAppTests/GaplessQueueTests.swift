import XCTest
@testable import PlayerApp

final class GaplessQueueTests: XCTestCase {
    func testPlaybackQueueMovesForwardAndBackward() {
        let tracks = [
            PlaybackQueueItem(id: "one", url: fileURL("one.flac"), title: "One"),
            PlaybackQueueItem(id: "two", url: fileURL("two.flac"), title: "Two"),
            PlaybackQueueItem(id: "three", url: fileURL("three.flac"), title: "Three")
        ]
        var queue = PlaybackQueue(items: tracks, currentIndex: 1, currentPosition: 12.5)

        XCTAssertEqual(queue.currentItem?.id, "two")
        XCTAssertEqual(queue.nextItem?.id, "three")
        XCTAssertEqual(queue.previousItem?.id, "one")

        XCTAssertTrue(queue.advanceToNext())
        XCTAssertEqual(queue.currentItem?.id, "three")
        XCTAssertEqual(queue.currentPosition, 0)

        XCTAssertTrue(queue.moveToPrevious())
        XCTAssertEqual(queue.currentItem?.id, "two")
        XCTAssertEqual(queue.currentPosition, 0)
    }

    func testPlaybackQueuePreservesPlaybackPosition() {
        var queue = PlaybackQueue(
            items: [
                PlaybackQueueItem(id: "one", url: fileURL("one.flac"), title: "One")
            ],
            currentIndex: 0
        )

        queue.updateCurrentPosition(48.25)

        XCTAssertEqual(queue.currentPosition, 48.25)
    }

    func testGaplessCoordinatorKeepsCurrentAndNextStreams() throws {
        let decoder = FakeQueueDecoder()
        var coordinator = GaplessPlaybackCoordinator(
            queue: PlaybackQueue(
                items: [
                    PlaybackQueueItem(id: "one", url: fileURL("one.flac"), title: "One"),
                    PlaybackQueueItem(id: "two", url: fileURL("two.flac"), title: "Two")
                ],
                currentIndex: 0
            ),
            decoder: decoder
        )

        try coordinator.start()
        try coordinator.prepareNextTrack()

        XCTAssertEqual(decoder.preparedURLs, [fileURL("one.flac"), fileURL("two.flac")])
        XCTAssertEqual(coordinator.currentStream?.item.id, "one")
        XCTAssertEqual(coordinator.nextStream?.item.id, "two")
        XCTAssertTrue(coordinator.diagnostics.isNextTrackPrebuffered)
        XCTAssertEqual(coordinator.diagnostics.nextTrackTitle, "Two")
    }

    func testGaplessCoordinatorTransitionsToPrebufferedNextTrack() throws {
        let decoder = FakeQueueDecoder()
        var coordinator = GaplessPlaybackCoordinator(
            queue: PlaybackQueue(
                items: [
                    PlaybackQueueItem(id: "one", url: fileURL("one.flac"), title: "One"),
                    PlaybackQueueItem(id: "two", url: fileURL("two.flac"), title: "Two"),
                    PlaybackQueueItem(id: "three", url: fileURL("three.flac"), title: "Three")
                ],
                currentIndex: 0
            ),
            decoder: decoder
        )

        try coordinator.start()
        try coordinator.prepareNextTrack()
        XCTAssertTrue(coordinator.transitionToNextTrack())

        XCTAssertEqual(coordinator.queue.currentItem?.id, "two")
        XCTAssertEqual(coordinator.currentStream?.item.id, "two")
        XCTAssertEqual(coordinator.nextStream?.item.id, "three")
        XCTAssertTrue(coordinator.diagnostics.isNextTrackPrebuffered)
        XCTAssertEqual(decoder.preparedURLs, [
            fileURL("one.flac"),
            fileURL("two.flac"),
            fileURL("three.flac")
        ])
    }

    func testGaplessCoordinatorPreservesPositionBeforeTransition() throws {
        let decoder = FakeQueueDecoder()
        var coordinator = GaplessPlaybackCoordinator(
            queue: PlaybackQueue(
                items: [
                    PlaybackQueueItem(id: "one", url: fileURL("one.flac"), title: "One"),
                    PlaybackQueueItem(id: "two", url: fileURL("two.flac"), title: "Two")
                ],
                currentIndex: 0
            ),
            decoder: decoder
        )

        try coordinator.start()
        coordinator.updateCurrentPosition(91.75)

        XCTAssertEqual(coordinator.queue.currentPosition, 91.75)
        XCTAssertEqual(coordinator.diagnostics.currentPosition, 91.75)
    }
}

private final class FakeQueueDecoder: QueueDecoderPreparing, @unchecked Sendable {
    private(set) var preparedURLs: [URL] = []

    func prepareStream(for item: PlaybackQueueItem) throws -> PreparedQueueStream {
        preparedURLs.append(item.url)
        return PreparedQueueStream(item: item, estimatedDuration: 180)
    }
}

private func fileURL(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name)")
}
