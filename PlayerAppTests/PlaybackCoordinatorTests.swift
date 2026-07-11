import XCTest
@testable import PlayerApp

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    func testPublishesLoadingAndPlayingSnapshots() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        let item = Self.playbackItem()
        let stream = await coordinator.snapshots()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        try await coordinator.play(item: item)
        let loading = await iterator.next()
        let playing = await iterator.next()

        XCTAssertEqual(initial, PlaybackSnapshot.idle)
        XCTAssertEqual(loading?.status, .loading)
        XCTAssertEqual(loading?.currentItem, item)
        XCTAssertEqual(playing?.status, .playing)
        XCTAssertEqual(playing?.currentItem, item)
        XCTAssertEqual(playback.events, [.play(item.url)])
    }

    func testRequestsSourceSampleRateBeforeStartingPlayback() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        var item = Self.playbackItem()
        item.sourceSampleRate = 96_000

        try await coordinator.play(item: item)

        XCTAssertEqual(playback.events, [
            .requestSampleRate(96_000),
            .play(item.url)
        ])
    }

    func testRejectedSampleRateRequestDoesNotBlockPlayback() async throws {
        let playback = FakeCoordinatorPlaybackController(
            sampleRateRequestError: CoordinatorTestPlaybackError.sampleRateFailed
        )
        let coordinator = PlaybackCoordinator(playback: playback)
        var item = Self.playbackItem()
        item.sourceSampleRate = 192_000

        try await coordinator.play(item: item)

        let snapshot = await coordinator.currentSnapshot
        XCTAssertEqual(snapshot.status, .playing)
        XCTAssertNotNil(snapshot.failureMessage)
        XCTAssertEqual(playback.events, [
            .requestSampleRate(192_000),
            .play(item.url)
        ])
    }

    func testPublishesFailureAndClearsCurrentItem() async {
        let playback = FakeCoordinatorPlaybackController(
            playError: CoordinatorTestPlaybackError.playFailed
        )
        let coordinator = PlaybackCoordinator(playback: playback)

        do {
            try await coordinator.play(item: Self.playbackItem())
            XCTFail("Expected playback to fail.")
        } catch {
            let snapshot = await coordinator.currentSnapshot
            XCTAssertEqual(snapshot.status, .failed)
            XCTAssertNil(snapshot.currentItem)
            XCTAssertNotNil(snapshot.failureMessage)
        }
    }

    func testPlaybackStoreUpdatesNowPlayingFromSnapshots() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        let nowPlaying = FakeSnapshotNowPlayingUpdater()
        let updateExpectation = expectation(description: "Now Playing updated")
        nowPlaying.onUpdate = {
            updateExpectation.fulfill()
        }
        let store = PlaybackStore(
            coordinator: coordinator,
            nowPlayingUpdater: nowPlaying
        )

        store.start()
        try await coordinator.play(item: Self.playbackItem())
        await fulfillment(of: [updateExpectation], timeout: 1)

        XCTAssertEqual(store.snapshot.status, .playing)
        XCTAssertEqual(nowPlaying.updates.last?.track.title, "So What")
        XCTAssertEqual(nowPlaying.updates.last?.playbackRate, 1)
    }

    func testPlaybackStoreCancelsQueueRestorationWhenObservationStops() async {
        let restorer = BlockingPlaybackQueueRestorer()
        let store = PlaybackStore(
            coordinator: PlaybackCoordinator(playback: FakeCoordinatorPlaybackController()),
            queueRestorer: restorer
        )

        store.start()
        for _ in 0..<100 {
            let hasStarted = await restorer.didStart()
            if hasStarted { break }
            await Task.yield()
        }

        store.stopObserving()
        for _ in 0..<100 {
            let wasCancelled = await restorer.didCancel()
            if wasCancelled { break }
            await Task.yield()
        }

        let hasStarted = await restorer.didStart()
        let wasCancelled = await restorer.didCancel()
        XCTAssertTrue(hasStarted)
        XCTAssertTrue(wasCancelled)
    }

    func testInterruptionResumesOnlyWhenPlaybackWasActiveAndSystemAllowsIt() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        try await coordinator.play(item: Self.playbackItem())

        await coordinator.handleInterruptionBegan()
        await coordinator.handleInterruptionEnded(shouldResume: true)

        XCTAssertEqual(playback.events, [
            .play(Self.playbackItem().url),
            .pause,
            .resume
        ])
        let snapshot = await coordinator.currentSnapshot
        XCTAssertEqual(snapshot.status, .playing)
    }

    func testInterruptionDoesNotResumeAlreadyPausedPlayback() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        try await coordinator.play(item: Self.playbackItem())
        await coordinator.pause()

        await coordinator.handleInterruptionBegan()
        await coordinator.handleInterruptionEnded(shouldResume: true)

        XCTAssertEqual(playback.events, [.play(Self.playbackItem().url), .pause])
        let snapshot = await coordinator.currentSnapshot
        XCTAssertEqual(snapshot.status, .paused)
    }

    func testRouteLossPausesAndMediaServicesResetRequiresExplicitResume() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        try await coordinator.play(item: Self.playbackItem())

        await coordinator.handleRouteLoss()
        await coordinator.handleMediaServicesReset()

        XCTAssertEqual(playback.events, [
            .play(Self.playbackItem().url),
            .pause,
            .stop,
            .recover
        ])
        let snapshot = await coordinator.currentSnapshot
        XCTAssertEqual(snapshot.status, .paused)
    }

    func testFinishingLastItemStopsPlaybackAndPublishesIdleState() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        try await coordinator.play(item: Self.playbackItem())

        let didAdvance = try await coordinator.finishCurrent()

        XCTAssertFalse(didAdvance)
        XCTAssertEqual(playback.events, [.play(Self.playbackItem().url), .stop])
        let snapshot = await coordinator.currentSnapshot
        XCTAssertEqual(snapshot.status, .idle)
        XCTAssertNil(snapshot.currentItem)
    }

    func testBackendRenderingCompletionAdvancesPreloadedQueueWithoutRestartingPlayer() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        let first = Self.playbackItem()
        var second = Self.playbackItem()
        second.id = "track-2"
        second.url = URL(fileURLWithPath: "/music/02 Freddie Freeloader.flac")
        try await coordinator.play(items: [first, second], startingAt: 0)
        XCTAssertEqual(playback.preloadedURLs, [second.url])

        playback.emit(.renderingComplete(first.url))
        for _ in 0..<20 {
            let snapshot = await coordinator.currentSnapshot
            if snapshot.currentItem?.id == second.id { break }
            await Task.yield()
        }

        let snapshot = await coordinator.currentSnapshot
        XCTAssertEqual(snapshot.currentItem?.id, second.id)
        XCTAssertEqual(playback.events, [.play(first.url)])
    }

    func testReplayGainChangeUsesControlledTransitionInsteadOfUnsafePreload() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let equalizer = EqualizerService(applicator: RecordingCoordinatorDSPApplicator())
        _ = try await equalizer.update(
            preset: .flat16BandPreset,
            settings: DSPSettings(replayGainEnabled: true, replayGainMode: .track),
            replayGainMetadata: ReplayGainMetadata(trackGainDB: -3),
            sampleRate: 48_000
        )
        let coordinator = PlaybackCoordinator(
            playback: playback,
            equalizerService: equalizer
        )
        var first = Self.playbackItem()
        first.sourceSampleRate = 48_000
        first.replayGainMetadata = ReplayGainMetadata(trackGainDB: -3)
        var second = Self.playbackItem()
        second.id = "track-2"
        second.url = URL(fileURLWithPath: "/music/02 Freddie Freeloader.flac")
        second.sourceSampleRate = 48_000
        second.replayGainMetadata = ReplayGainMetadata(trackGainDB: -7)

        try await coordinator.play(items: [first, second], startingAt: 0)
        XCTAssertTrue(playback.preloadedURLs.isEmpty)

        playback.emit(.renderingComplete(first.url))
        for _ in 0..<20 {
            let snapshot = await coordinator.currentSnapshot
            if snapshot.currentItem?.id == second.id { break }
            await Task.yield()
        }

        XCTAssertEqual(playback.events, [
            .requestSampleRate(48_000),
            .play(first.url),
            .requestSampleRate(48_000),
            .play(second.url)
        ])
    }

    func testRemovingCurrentQueueItemStartsTheNextItem() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        let first = Self.playbackItem()
        var second = Self.playbackItem()
        second.id = "track-2"
        second.url = URL(fileURLWithPath: "/music/02 Freddie Freeloader.flac")
        try await coordinator.play(items: [first, second], startingAt: 0)

        await coordinator.removeFromQueue(id: first.id)

        let snapshot = await coordinator.currentSnapshot
        XCTAssertEqual(snapshot.currentItem?.id, second.id)
        XCTAssertEqual(playback.events, [.play(first.url), .play(second.url)])
    }

    func testAddingToEmptyQueueCreatesPausedItemThatCanStart() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        let item = Self.playbackItem()

        await coordinator.addLast(item)
        let queued = await coordinator.currentSnapshot
        XCTAssertEqual(queued.status, .paused)
        XCTAssertEqual(queued.currentItem?.id, item.id)

        try await coordinator.resume()

        XCTAssertEqual(playback.events, [.play(item.url)])
    }

    func testShutdownStopsBackendPreservesQueueAndFinishesSnapshots() async throws {
        let playback = FakeCoordinatorPlaybackController()
        let coordinator = PlaybackCoordinator(playback: playback)
        let item = Self.playbackItem()
        let stream = await coordinator.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        try await coordinator.play(item: item)
        _ = await iterator.next()
        _ = await iterator.next()

        await coordinator.shutdown()

        let terminal = await iterator.next()
        let end = await iterator.next()
        XCTAssertEqual(terminal?.status, .paused)
        XCTAssertEqual(terminal?.currentItem?.id, item.id)
        XCTAssertNil(end)
        XCTAssertEqual(playback.events.last, .stop)
        XCTAssertFalse(playback.hasPlaybackEventHandler)
    }

    private static func playbackItem() -> PlaybackItem {
        PlaybackItem(
            id: "track-1",
            url: URL(fileURLWithPath: "/music/01 So What.flac"),
            metadata: NowPlayingTrackMetadata(
                fileName: "01 So What.flac",
                title: "So What",
                artist: "Miles Davis",
                albumTitle: "Kind of Blue",
                duration: 545
            )
        )
    }
}

private final class FakeCoordinatorPlaybackController: PlaybackControlling, PlaybackBackendEventSource, QueuePreloadingPlaybackBackend, MediaServicesResetRecovering, PreferredSampleRateRequesting, @unchecked Sendable {
    enum Event: Equatable {
        case play(URL)
        case resume
        case pause
        case stop
        case recover
        case seek(TimeInterval)
        case requestSampleRate(Double)
    }

    private(set) var events: [Event] = []
    private(set) var preloadedURLs: [URL] = []
    private let playError: Error?
    private let sampleRateRequestError: Error?
    private var playbackEventHandler: (@Sendable (PlaybackBackendEvent) -> Void)?

    var hasPlaybackEventHandler: Bool {
        playbackEventHandler != nil
    }

    init(
        playError: Error? = nil,
        sampleRateRequestError: Error? = nil
    ) {
        self.playError = playError
        self.sampleRateRequestError = sampleRateRequestError
    }

    func play(url: URL) throws {
        if let playError {
            throw playError
        }

        events.append(.play(url))
    }

    func resume() throws {
        events.append(.resume)
    }

    func pause() {
        events.append(.pause)
    }

    func stop() {
        events.append(.stop)
    }

    func recoverAfterMediaServicesReset() throws {
        events.append(.recover)
    }

    func seek(to time: TimeInterval) throws {
        events.append(.seek(time))
    }

    func requestPreferredSampleRate(_ sampleRate: Double) throws {
        events.append(.requestSampleRate(sampleRate))
        if let sampleRateRequestError {
            throw sampleRateRequestError
        }
    }

    func setPlaybackEventHandler(
        _ handler: (@Sendable (PlaybackBackendEvent) -> Void)?
    ) {
        playbackEventHandler = handler
    }

    func preload(urls: [URL], generation: UInt64) throws {
        preloadedURLs = urls
    }

    func emit(_ event: PlaybackBackendEvent) {
        playbackEventHandler?(event)
    }
}

private final class RecordingCoordinatorDSPApplicator: DSPConfigurationApplying, @unchecked Sendable {
    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot) {}
}

@MainActor
private final class FakeSnapshotNowPlayingUpdater: NowPlayingUpdating {
    struct Update {
        var track: NowPlayingTrackMetadata
        var elapsed: TimeInterval
        var playbackRate: Double
    }

    private(set) var updates: [Update] = []
    var onUpdate: (() -> Void)?

    func update(
        track: NowPlayingTrackMetadata,
        elapsed: TimeInterval,
        playbackRate: Double
    ) {
        updates.append(Update(track: track, elapsed: elapsed, playbackRate: playbackRate))
        onUpdate?()
    }

    func clear() {
        updates = []
    }
}

private enum CoordinatorTestPlaybackError: Error {
    case playFailed
    case sampleRateFailed
}

private actor BlockingPlaybackQueueRestorer: PlaybackQueueRestoring {
    private(set) var hasStarted = false
    private(set) var wasCancelled = false

    func restoreQueue() async throws -> RestoredPlaybackQueue? {
        hasStarted = true
        do {
            try await Task.sleep(for: .seconds(60))
            return nil
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }

    func didStart() -> Bool { hasStarted }

    func didCancel() -> Bool { wasCancelled }
}
