import Foundation

protocol PlaybackCoordinating: Sendable {
    func play(item: PlaybackItem) async throws
    func resume() async throws
    func pause() async
    func stop() async
    func seek(to time: TimeInterval) async throws
}

protocol PlaybackQueueCoordinating: PlaybackCoordinating {
    func play(items: [PlaybackItem], startingAt index: Int) async throws
    func playNext(_ item: PlaybackItem) async
    func addLast(_ item: PlaybackItem) async
    func next() async throws -> Bool
    func previous() async throws -> Bool
    func removeFromQueue(id: String) async
    func moveQueueItem(from sourceIndex: Int, to destinationIndex: Int) async
    func setRepeatMode(_ mode: PlaybackRepeatMode) async
    func setShuffleEnabled(_ enabled: Bool) async
}

actor PlaybackCoordinator: PlaybackQueueCoordinating {
    private let playback: any PlaybackControlling
    private let queuePersistence: (any QueuePersisting)?
    private let equalizerService: EqualizerService?
    private var observers: [UUID: AsyncStream<PlaybackSnapshot>.Continuation] = [:]
    private var queue = PlaybackQueue()
    private var itemsByID: [String: PlaybackItem] = [:]
    private var restoredWithoutBackend = false
    private var wasPlayingBeforeInterruption = false
    private var queueGeneration: UInt64 = 0
    private var progressTask: Task<Void, Never>?
    private var equalizerObservationTask: Task<Void, Never>?
    private var lastPersistedProgress: TimeInterval = 0
    private var preloadedNextItemID: String?
    private var preloadedItemIDs: [String] = []
    private var isShutdown = false

    private(set) var currentSnapshot: PlaybackSnapshot = .idle

    init(
        playback: any PlaybackControlling = PlaybackEngine(),
        queuePersistence: (any QueuePersisting)? = nil,
        equalizerService: EqualizerService? = nil
    ) {
        self.playback = playback
        self.queuePersistence = queuePersistence
        self.equalizerService = equalizerService
        (playback as? any PlaybackBackendEventSource)?.setPlaybackEventHandler { [weak self] event in
            Task { await self?.handleBackendEvent(event) }
        }
    }

    deinit {
        progressTask?.cancel()
        equalizerObservationTask?.cancel()
    }

    func snapshots() -> AsyncStream<PlaybackSnapshot> {
        let observerID = UUID()
        let pair = AsyncStream<PlaybackSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )

        observers[observerID] = pair.continuation
        pair.continuation.yield(currentSnapshot)
        if isShutdown {
            pair.continuation.finish()
            observers[observerID] = nil
            return pair.stream
        }
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(observerID) }
        }
        return pair.stream
    }

    func play(item: PlaybackItem) async throws {
        try await play(items: [item], startingAt: 0)
    }

    func play(items: [PlaybackItem], startingAt index: Int) async throws {
        ensureEqualizerObservation()
        guard items.indices.contains(index) else {
            await stop()
            return
        }

        let target = items[index]
        publish(snapshot(status: .loading, currentItem: target, elapsed: 0))

        do {
            let sampleRateWarning = requestPreferredSampleRate(for: target)
            try await equalizerService?.updatePlaybackContext(
                sampleRate: target.sourceSampleRate,
                replayGainMetadata: target.replayGainMetadata
            )
            resetPreloadTracking()
            try playback.play(url: target.url)
            itemsByID = Self.indexItemsByID(items)
            queue = PlaybackQueue(
                items: items.map(PlaybackQueueItem.init),
                currentIndex: index
            )
            try await preloadRemainingItems()
            restoredWithoutBackend = false
            var playing = snapshot(status: .playing, currentItem: target, elapsed: 0)
            playing.failureMessage = sampleRateWarning
            publish(playing)
            startProgressUpdates()
            persistQueue()
        } catch {
            stopProgressUpdates()
            playback.stop()
            publish(failureSnapshot(error))
            throw error
        }
    }

    func restoreQueue(
        items: [PlaybackItem],
        currentIndex: Int?,
        elapsed: TimeInterval,
        repeatMode: PlaybackRepeatMode = .off,
        isShuffleEnabled: Bool = false,
        originalItems: [PlaybackItem]? = nil
    ) {
        itemsByID = Self.indexItemsByID(items)
        queue = PlaybackQueue(
            items: items.map(PlaybackQueueItem.init),
            currentIndex: currentIndex,
            currentPosition: elapsed,
            repeatMode: repeatMode,
            isShuffleEnabled: isShuffleEnabled,
            originalItems: originalItems?.map(PlaybackQueueItem.init)
        )
        restoredWithoutBackend = queue.currentItem != nil
        queueGeneration &+= 1
        resetPreloadTracking()

        if let item = currentPlaybackItem {
            publish(snapshot(status: .paused, currentItem: item, elapsed: elapsed))
        } else {
            publish(.idle)
        }
    }

    func playNext(_ item: PlaybackItem) async {
        let queueWasEmpty = queue.currentItem == nil
        itemsByID[item.id] = item
        queue.playNext(PlaybackQueueItem(item))
        if queueWasEmpty { restoredWithoutBackend = true }
        await refreshPreload()
        publishCurrentState(status: queueWasEmpty ? .paused : nil)
        persistQueue()
    }

    func addLast(_ item: PlaybackItem) async {
        let queueWasEmpty = queue.currentItem == nil
        itemsByID[item.id] = item
        queue.addLast(PlaybackQueueItem(item))
        if queueWasEmpty { restoredWithoutBackend = true }
        await refreshPreload()
        publishCurrentState(status: queueWasEmpty ? .paused : nil)
        persistQueue()
    }

    private static func indexItemsByID(_ items: [PlaybackItem]) -> [String: PlaybackItem] {
        var result: [String: PlaybackItem] = [:]
        for item in items {
            result[item.id] = item
        }
        return result
    }

    func resume() async throws {
        guard let item = currentPlaybackItem else { return }

        do {
            var sampleRateWarning: String?
            if restoredWithoutBackend {
                sampleRateWarning = requestPreferredSampleRate(for: item)
                try await equalizerService?.updatePlaybackContext(
                    sampleRate: item.sourceSampleRate,
                    replayGainMetadata: item.replayGainMetadata
                )
                resetPreloadTracking()
                try playback.play(url: item.url)
                if queue.currentPosition > 0 {
                    try playback.seek(to: queue.currentPosition)
                }
                try await preloadRemainingItems()
                restoredWithoutBackend = false
            } else {
                try playback.resume()
            }
            var playing = snapshot(
                status: .playing,
                currentItem: item,
                elapsed: queue.currentPosition
            )
            playing.failureMessage = sampleRateWarning
            publish(playing)
            startProgressUpdates()
        } catch {
            stopProgressUpdates()
            publish(failureSnapshot(error))
            throw error
        }
    }

    func pause() async {
        guard currentSnapshot.status == .playing else { return }
        playback.pause()
        stopProgressUpdates()
        publishCurrentState(status: .paused)
        persistQueue()
    }

    func stop() async {
        playback.stop()
        resetPreloadTracking()
        stopProgressUpdates()
        queue = PlaybackQueue()
        queueGeneration &+= 1
        itemsByID.removeAll()
        restoredWithoutBackend = false
        publish(.idle)
        do {
            try queuePersistence?.clear()
        } catch {
            publishPersistenceFailure(
                String(localized: "Unable to clear the saved queue"),
                error: error
            )
        }
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        playback.stop()
        (playback as? any PlaybackBackendEventSource)?
            .setPlaybackEventHandler(nil)
        (playback as? any SpectrumAnalysisControlling)?
            .setSpectrumAnalysisEnabled(false, bitPerfect: false)
        stopProgressUpdates()
        equalizerObservationTask?.cancel()
        equalizerObservationTask = nil
        resetPreloadTracking()
        queueGeneration &+= 1
        restoredWithoutBackend = currentPlaybackItem != nil
        publishCurrentState(
            status: currentPlaybackItem == nil ? .idle : .paused
        )
        persistQueue()
        observers.values.forEach { $0.finish() }
        observers.removeAll()
    }

    func seek(to time: TimeInterval) async throws {
        let position = max(0, time)
        do {
            if !restoredWithoutBackend {
                try playback.seek(to: position)
            }
            queue.updateCurrentPosition(position)
            publishCurrentState()
            persistQueue()
        } catch {
            publish(failureSnapshot(error))
            throw error
        }
    }

    func next() async throws -> Bool {
        try await transitionQueue { $0.advanceToNext() }
    }

    func previous() async throws -> Bool {
        if queue.currentPosition > 5 {
            try await seek(to: 0)
            return true
        }
        return try await transitionQueue { $0.moveToPrevious() }
    }

    func finishCurrent() async throws -> Bool {
        let previousQueue = queue
        let nextItem = queue.finishCurrent()
        guard nextItem != nil else {
            playback.stop()
            stopProgressUpdates()
            restoredWithoutBackend = false
            publishCurrentState(status: .idle)
            persistQueue()
            return false
        }
        do {
            return try await startCurrentQueueItem()
        } catch {
            playback.stop()
            queue = previousQueue
            publish(failureSnapshot(error))
            throw error
        }
    }

    func removeFromQueue(id: String) async {
        let removedCurrentItem = queue.currentItem?.id == id
        queue.removeItem(id: id)
        itemsByID[id] = nil
        if removedCurrentItem {
            guard currentPlaybackItem != nil else {
                playback.stop()
                stopProgressUpdates()
                publishCurrentState(status: .idle)
                persistQueue()
                return
            }
            do {
                _ = try await startCurrentQueueItem()
            } catch {
                playback.stop()
                stopProgressUpdates()
                publish(failureSnapshot(error))
            }
            return
        }
        await refreshPreload()
        publishCurrentState()
        persistQueue()
    }

    func removeFromQueue(at index: Int) async {
        let removedID = queue.items.indices.contains(index) ? queue.items[index].id : nil
        let removedCurrentItem = queue.currentIndex == index
        queue.removeItem(at: index)
        if let removedID, !queue.items.contains(where: { $0.id == removedID }) {
            itemsByID[removedID] = nil
        }
        if removedCurrentItem {
            guard currentPlaybackItem != nil else {
                playback.stop()
                stopProgressUpdates()
                publishCurrentState(status: .idle)
                persistQueue()
                return
            }
            do {
                _ = try await startCurrentQueueItem()
            } catch {
                playback.stop()
                stopProgressUpdates()
                publish(failureSnapshot(error))
            }
            return
        }
        await refreshPreload()
        publishCurrentState()
        persistQueue()
    }

    func moveQueueItem(from sourceIndex: Int, to destinationIndex: Int) async {
        queue.moveItem(from: sourceIndex, to: destinationIndex)
        await refreshPreload()
        publishCurrentState()
        persistQueue()
    }

    func setRepeatMode(_ mode: PlaybackRepeatMode) async {
        queue.setRepeatMode(mode)
        publishCurrentState()
        persistQueue()
    }

    func setShuffleEnabled(_ enabled: Bool) async {
        queue.setShuffleEnabled(enabled)
        await refreshPreload()
        publishCurrentState()
        persistQueue()
    }

    func handleInterruptionBegan() {
        wasPlayingBeforeInterruption = currentSnapshot.status == .playing
        if wasPlayingBeforeInterruption {
            playback.pause()
            stopProgressUpdates()
            publishCurrentState(status: .interrupted)
        }
    }

    func handleInterruptionEnded(shouldResume: Bool) async {
        let shouldActuallyResume = shouldResume && wasPlayingBeforeInterruption
        wasPlayingBeforeInterruption = false
        if shouldActuallyResume {
            try? await resume()
        } else if currentSnapshot.status == .interrupted {
            publishCurrentState(status: .paused)
        }
    }

    func handleRouteLoss() {
        if currentSnapshot.status == .playing {
            playback.pause()
            stopProgressUpdates()
            publishCurrentState(status: .paused)
        }
    }

    func handleRouteChange(diagnostics: AudioRouteDiagnostics) {
        (playback as? any RouteChangeReconfiguring)?
            .reconfigureAfterRouteChange(diagnostics: diagnostics)
    }

    func handleMediaServicesReset() {
        playback.stop()
        resetPreloadTracking()
        stopProgressUpdates()
        restoredWithoutBackend = currentPlaybackItem != nil
        do {
            try (playback as? any MediaServicesResetRecovering)?
                .recoverAfterMediaServicesReset()
            publishCurrentState(status: currentPlaybackItem == nil ? .idle : .paused)
        } catch {
            var current = snapshot(
                status: currentPlaybackItem == nil ? .idle : .paused,
                currentItem: currentPlaybackItem,
                elapsed: queue.currentPosition
            )
            current.failureMessage = LocalizedFormat.string(
                "Audio system recovery failed: %@",
                error.localizedDescription
            )
            publish(current)
        }
    }

    private var currentPlaybackItem: PlaybackItem? {
        guard let id = queue.currentItem?.id else { return nil }
        return itemsByID[id]
    }

    private func handleBackendEvent(_ event: PlaybackBackendEvent) async {
        switch event {
        case .renderingComplete(let url):
            guard url == nil || url == currentPlaybackItem?.url else { return }
            await advanceAfterBackendCompletion()
        case .endOfAudio:
            return
        }
    }

    private func advanceAfterBackendCompletion() async {
        let previousQueue = queue
        let previousIndex = queue.currentIndex
        guard queue.finishCurrent() != nil, let item = currentPlaybackItem else {
            stopProgressUpdates()
            restoredWithoutBackend = false
            publishCurrentState(status: .idle)
            persistQueue()
            return
        }

        let requiresManualStart = queue.currentIndex == previousIndex
            || queue.currentIndex != previousIndex.map { $0 + 1 }
            || item.id != preloadedNextItemID
        do {
            var sampleRateWarning: String?
            try await equalizerService?.updatePlaybackContext(
                sampleRate: item.sourceSampleRate,
                replayGainMetadata: item.replayGainMetadata
            )
            if requiresManualStart {
                sampleRateWarning = requestPreferredSampleRate(for: item)
                resetPreloadTracking()
                try playback.play(url: item.url)
                try await preloadRemainingItems()
            } else {
                try await preloadRemainingItems()
            }
            restoredWithoutBackend = false
            var playing = snapshot(status: .playing, currentItem: item, elapsed: 0)
            playing.failureMessage = sampleRateWarning
            publish(playing)
            startProgressUpdates()
            persistQueue()
        } catch {
            playback.stop()
            queue = previousQueue
            publish(failureSnapshot(error))
        }
    }

    private func transitionQueue(
        _ mutation: (inout PlaybackQueue) -> Bool
    ) async throws -> Bool {
        let previousQueue = queue
        guard mutation(&queue), let item = currentPlaybackItem else { return false }

        do {
            return try await startCurrentQueueItem()
        } catch {
            playback.stop()
            queue = previousQueue
            publish(failureSnapshot(error))
            throw error
        }
    }

    private func startCurrentQueueItem() async throws -> Bool {
        guard let item = currentPlaybackItem else { return false }

        let sampleRateWarning = requestPreferredSampleRate(for: item)
        try await equalizerService?.updatePlaybackContext(
            sampleRate: item.sourceSampleRate,
            replayGainMetadata: item.replayGainMetadata
        )
        resetPreloadTracking()
        try playback.play(url: item.url)
        try await preloadRemainingItems()
        restoredWithoutBackend = false
        var playing = snapshot(status: .playing, currentItem: item, elapsed: 0)
        playing.failureMessage = sampleRateWarning
        publish(playing)
        startProgressUpdates()
        persistQueue()
        return true
    }

    private func startProgressUpdates() {
        guard progressTask == nil,
              let provider = playback as? any PlaybackProgressProviding else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await self?.refreshProgress(from: provider)
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func refreshProgress(from provider: any PlaybackProgressProviding) {
        guard currentSnapshot.status == .playing,
              let time = provider.currentPlaybackTime,
              time.isFinite else { return }
        queue.updateCurrentPosition(max(0, time))
        publishCurrentState(status: .playing)
        if abs(time - lastPersistedProgress) >= 10 {
            lastPersistedProgress = time
            persistQueue()
        }
    }

    private func snapshot(
        status: PlaybackStatus,
        currentItem: PlaybackItem?,
        elapsed: TimeInterval
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            status: status,
            currentItem: currentItem,
            elapsed: elapsed,
            queue: queue.items.compactMap { itemsByID[$0.id] },
            currentIndex: queue.currentIndex,
            failureMessage: nil,
            repeatMode: queue.repeatMode,
            isShuffleEnabled: queue.isShuffleEnabled
        )
    }

    private func failureSnapshot(_ error: Error) -> PlaybackSnapshot {
        var result = snapshot(
            status: .failed,
            currentItem: currentPlaybackItem,
            elapsed: queue.currentPosition
        )
        result.failureMessage = LocalizedFormat.string(
            "Playback failed: %@",
            error.localizedDescription
        )
        return result
    }

    private func publishCurrentState(status: PlaybackStatus? = nil) {
        let resolvedStatus: PlaybackStatus
        if currentPlaybackItem == nil {
            resolvedStatus = .idle
        } else {
            resolvedStatus = status ?? currentSnapshot.status
        }
        publish(snapshot(
            status: resolvedStatus,
            currentItem: currentPlaybackItem,
            elapsed: queue.currentPosition
        ))
    }

    private func persistQueue() {
        guard let queuePersistence else { return }
        let persisted = PersistedQueueSnapshot(
            itemIDs: queue.items.map(\.id),
            originalItemIDs: queue.originalOrderIDs,
            currentIndex: queue.currentIndex,
            currentPosition: queue.currentPosition,
            repeatMode: queue.repeatMode,
            isShuffleEnabled: queue.isShuffleEnabled
        )
        do {
            try queuePersistence.save(persisted)
        } catch {
            publishPersistenceFailure(
                String(localized: "Unable to save the playback queue"),
                error: error
            )
        }
    }

    private func publishPersistenceFailure(_ message: String, error: Error) {
        var snapshot = currentSnapshot
        snapshot.failureMessage = LocalizedFormat.string(
            "%@: %@",
            message,
            error.localizedDescription
        )
        publish(snapshot)
    }

    private func preloadRemainingItems() async throws {
        guard let preloader = playback as? any QueuePreloadingPlaybackBackend else {
            resetPreloadTracking()
            return
        }
        queueGeneration &+= 1
        let remaining: [PlaybackItem]
        if let currentIndex = queue.currentIndex {
            remaining = queue.items
                .dropFirst(currentIndex + 1)
                .prefix(2)
                .compactMap { itemsByID[$0.id] }
        } else {
            remaining = []
        }
        var compatible: [PlaybackItem] = []
        var previous = currentPlaybackItem
        for item in remaining {
            guard let current = previous else { break }
            let canPreload: Bool
            if let equalizerService {
                canPreload = await equalizerService.isGaplessTransitionCompatible(
                    from: current,
                    to: item
                )
            } else {
                canPreload = current.sourceSampleRate == item.sourceSampleRate
            }
            guard canPreload else { break }
            compatible.append(item)
            previous = item
        }
        let desiredIDs = compatible.map(\.id)
        guard desiredIDs != preloadedItemIDs else { return }
        resetPreloadTracking()
        try preloader.preload(urls: compatible.map(\.url), generation: queueGeneration)
        preloadedItemIDs = desiredIDs
        preloadedNextItemID = desiredIDs.first
    }

    private func refreshPreload() async {
        do {
            try await preloadRemainingItems()
        } catch {
            var current = currentSnapshot
            current.failureMessage = LocalizedFormat.string(
                "Unable to preload the next track: %@",
                error.localizedDescription
            )
            publish(current)
        }
    }

    private func ensureEqualizerObservation() {
        guard equalizerObservationTask == nil, let equalizerService else { return }
        equalizerObservationTask = Task { [weak self, equalizerService] in
            let snapshots = await equalizerService.configurationChanges()
            for await _ in snapshots {
                guard !Task.isCancelled else { return }
                await self?.refreshPreload()
            }
        }
    }

    private func resetPreloadTracking() {
        preloadedItemIDs = []
        preloadedNextItemID = nil
    }

    private func requestPreferredSampleRate(for item: PlaybackItem) -> String? {
        guard let sampleRate = item.sourceSampleRate,
              sampleRate.isFinite,
              sampleRate > 0,
              let requester = playback as? any PreferredSampleRateRequesting else {
            return nil
        }
        do {
            try requester.requestPreferredSampleRate(sampleRate)
            return nil
        } catch {
            return LocalizedFormat.string(
                "Preferred sample-rate request failed: %@",
                error.localizedDescription
            )
        }
    }

    private func publish(_ snapshot: PlaybackSnapshot) {
        currentSnapshot = snapshot
        observers.values.forEach { $0.yield(snapshot) }
    }

    private func removeObserver(_ observerID: UUID) {
        observers[observerID] = nil
    }
}

private extension PlaybackQueueItem {
    init(_ item: PlaybackItem) {
        self.init(id: item.id, url: item.url, title: item.metadata.title ?? item.metadata.fileName)
    }
}
