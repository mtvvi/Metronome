import XCTest
@testable import PlayerApp

final class GaplessQueueTests: XCTestCase {
    func testQueueSupportsPlayNextAddLastReorderAndRemove() {
        var queue = PlaybackQueue(
            items: [item("one"), item("two")],
            currentIndex: 0
        )

        queue.playNext(item("next"))
        queue.addLast(item("last"))
        queue.moveItem(from: 3, to: 2)
        queue.removeItem(id: "two")

        XCTAssertEqual(queue.items.map(\.id), ["one", "next", "last"])
        XCTAssertEqual(queue.currentItem?.id, "one")
    }

    func testRepeatOneReplaysCurrentItemWhenItFinishes() {
        var queue = PlaybackQueue(
            items: [item("one"), item("two")],
            currentIndex: 0,
            repeatMode: .one
        )
        queue.updateCurrentPosition(25)

        XCTAssertEqual(queue.finishCurrent()?.id, "one")
        XCTAssertEqual(queue.currentItem?.id, "one")
        XCTAssertEqual(queue.currentPosition, 0)
    }

    func testRepeatAllWrapsAfterLastItem() {
        var queue = PlaybackQueue(
            items: [item("one"), item("two")],
            currentIndex: 1,
            repeatMode: .all
        )

        XCTAssertEqual(queue.finishCurrent()?.id, "one")
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testRepeatOffStopsAfterLastItem() {
        var queue = PlaybackQueue(
            items: [item("one"), item("two")],
            currentIndex: 1,
            repeatMode: .off
        )

        XCTAssertNil(queue.finishCurrent())
        XCTAssertNil(queue.currentIndex)
    }

    func testShuffleRestoresStableOriginalOrderAndKeepsCurrentItem() {
        var queue = PlaybackQueue(
            items: [item("one"), item("two"), item("three")],
            currentIndex: 1
        )

        queue.setShuffleEnabled(true, shuffledOrder: ["three", "two", "one"])
        XCTAssertEqual(queue.items.map(\.id), ["three", "two", "one"])
        XCTAssertEqual(queue.currentItem?.id, "two")

        queue.setShuffleEnabled(false)
        XCTAssertEqual(queue.items.map(\.id), ["one", "two", "three"])
        XCTAssertEqual(queue.currentItem?.id, "two")
    }

    func testShufflePreservesDuplicateQueueEntries() {
        var queue = PlaybackQueue(
            items: [item("one"), item("one"), item("two")],
            currentIndex: 0
        )

        queue.setShuffleEnabled(true, shuffledOrder: ["two", "one", "one"])

        XCTAssertEqual(queue.items.map(\.id), ["two", "one", "one"])
        XCTAssertEqual(queue.currentIndex, 1)
    }

    func testRemovingByIndexRemovesOnlyOneDuplicateEntry() {
        var queue = PlaybackQueue(
            items: [item("one"), item("one"), item("two")],
            currentIndex: 0
        )

        queue.removeItem(at: 1)

        XCTAssertEqual(queue.items.map(\.id), ["one", "two"])
        XCTAssertEqual(queue.currentIndex, 0)
    }

    func testFinishCurrentSkipsUnavailableNextItem() {
        var unavailable = item("unavailable")
        unavailable.isAvailable = false
        var queue = PlaybackQueue(
            items: [item("one"), unavailable, item("three")],
            currentIndex: 0
        )

        XCTAssertEqual(queue.finishCurrent()?.id, "three")
        XCTAssertEqual(queue.currentIndex, 2)
    }
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
        XCTAssertTrue(try coordinator.transitionToNextTrack())

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

    func testCoordinatorReportsGaplessAndReconfigurationExpectations() throws {
        let decoder = FakeQueueDecoder()
        let format = AudioStreamFormatSnapshot(
            sampleRate: 96_000,
            channelCount: 2,
            commonFormat: "pcmFormatFloat32",
            isInterleaved: false
        )
        var first = item("one")
        first.format = format
        var second = item("two")
        second.format = format
        var coordinator = GaplessPlaybackCoordinator(
            queue: PlaybackQueue(items: [first, second], currentIndex: 0),
            decoder: decoder
        )

        try coordinator.start()
        XCTAssertEqual(coordinator.diagnostics.transitionExpectation, .gapless)

        var incompatible = item("three")
        incompatible.format = AudioStreamFormatSnapshot(
            sampleRate: 44_100,
            channelCount: 2,
            commonFormat: "pcmFormatFloat32",
            isInterleaved: false
        )
        coordinator.replaceQueue(
            PlaybackQueue(items: [first, incompatible], currentIndex: 0)
        )
        try coordinator.start()
        XCTAssertEqual(
            coordinator.diagnostics.transitionExpectation,
            .graphReconfiguration(.incompatibleGaplessTransition)
        )
    }

    func testQueueReplacementInvalidatesPreviouslyPreparedGeneration() throws {
        let decoder = FakeQueueDecoder()
        var coordinator = GaplessPlaybackCoordinator(
            queue: PlaybackQueue(items: [item("one"), item("two")], currentIndex: 0),
            decoder: decoder
        )
        try coordinator.start()
        let firstGeneration = coordinator.generation

        coordinator.replaceQueue(
            PlaybackQueue(items: [item("three")], currentIndex: 0)
        )
        try coordinator.start()

        XCTAssertGreaterThan(coordinator.generation, firstGeneration)
        XCTAssertEqual(coordinator.currentStream?.item.id, "three")
        XCTAssertEqual(coordinator.currentStream?.generation, coordinator.generation)
    }

    func testOfflineGaplessToleranceHasNoNearZeroSamplesAtToneBoundary() {
        let firstTone = Array(repeating: Float(0.5), count: 1_024)
        let secondTone = Array(repeating: Float(-0.5), count: 1_024)
        let joined = firstTone + secondTone

        let nearZeroCount = GaplessContinuityAnalyzer.nearZeroSampleCount(
            samples: joined,
            boundaryIndex: firstTone.count,
            radius: 32
        )

        XCTAssertLessThanOrEqual(nearZeroCount, 0, "Tolerance: zero near-silent samples in a 64-sample join window.")
    }
}

private func item(_ id: String) -> PlaybackQueueItem {
    PlaybackQueueItem(id: id, url: fileURL("\(id).flac"), title: id.capitalized)
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
