import Combine
import Foundation

@MainActor
final class PlaybackStore: ObservableObject {
    @Published private(set) var snapshot: PlaybackSnapshot = .idle
    @Published private(set) var noticeMessage: String?

    private let coordinator: PlaybackCoordinator
    private let nowPlayingUpdater: any NowPlayingUpdating
    private let remoteCommandController: RemoteCommandController?
    private let queueRestorer: (any PlaybackQueueRestoring)?
    private let equalizerRuntime: EqualizerRuntimeController?
    private let audioSessionEventHandler: PlaybackCoordinatorAudioSessionEventHandler
    private let audioSessionObserver: AudioSessionEventObserver
    private var observationTask: Task<Void, Never>?
    private var equalizerRuntimeTask: Task<Void, Never>?
    private var queueRestorationTask: Task<Void, Never>?

    init(
        coordinator: PlaybackCoordinator,
        nowPlayingUpdater: any NowPlayingUpdating = NowPlayingController(),
        remoteCommandController: RemoteCommandController? = nil,
        queueRestorer: (any PlaybackQueueRestoring)? = nil,
        equalizerRuntime: EqualizerRuntimeController? = nil,
        diagnosticsProvider: (any AudioRouteDiagnosticsProviding)? = nil
    ) {
        self.coordinator = coordinator
        self.nowPlayingUpdater = nowPlayingUpdater
        self.remoteCommandController = remoteCommandController
        self.queueRestorer = queueRestorer
        self.equalizerRuntime = equalizerRuntime
        let audioSessionEventHandler = PlaybackCoordinatorAudioSessionEventHandler(
            coordinator: coordinator,
            equalizerRuntime: equalizerRuntime,
            diagnosticsProvider: diagnosticsProvider
        )
        self.audioSessionEventHandler = audioSessionEventHandler
        self.audioSessionObserver = AudioSessionEventObserver(
            handler: audioSessionEventHandler
        )
    }

    deinit {
        observationTask?.cancel()
        equalizerRuntimeTask?.cancel()
        queueRestorationTask?.cancel()
    }

    func start() {
        guard observationTask == nil else { return }

        if let remoteCommandController {
            remoteCommandController.install(
                playback: PlaybackCoordinatorRemoteCommandHandler(coordinator: coordinator),
                capabilities: RemoteCommandCapabilities(snapshot: snapshot)
            )
        }
        audioSessionObserver.start()

        if let equalizerRuntime, equalizerRuntimeTask == nil {
            equalizerRuntimeTask = Task { [weak self] in
                await equalizerRuntime.run { message in
                    Task { @MainActor [weak self] in self?.noticeMessage = message }
                }
            }
        }

        observationTask = Task { [weak self, coordinator] in
            let snapshots = await coordinator.snapshots()
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                self?.consume(snapshot)
            }
        }


        if let queueRestorer, queueRestorationTask == nil {
            queueRestorationTask = Task { [weak self, coordinator] in
                do {
                    guard let self,
                          let restored = try await queueRestorer.restoreQueue() else { return }
                    let current = await coordinator.currentSnapshot
                    guard current == .idle else { return }
                    await coordinator.restoreQueue(
                        items: restored.items,
                        currentIndex: restored.currentIndex,
                        elapsed: restored.elapsed,
                        repeatMode: restored.repeatMode,
                        isShuffleEnabled: restored.isShuffleEnabled,
                        originalItems: restored.originalItems
                    )
                    if restored.skippedItemCount > 0 {
                        noticeMessage = LocalizedFormat.string(
                            "Skipped %lld unavailable saved queue items.",
                            Int64(restored.skippedItemCount)
                        )
                    }
                } catch {
                    self?.noticeMessage = String(localized: "Unable to restore the saved queue.")
                }
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        equalizerRuntimeTask?.cancel()
        equalizerRuntimeTask = nil
        queueRestorationTask?.cancel()
        queueRestorationTask = nil
        remoteCommandController?.uninstall()
        audioSessionObserver.stop()
    }

    func togglePlayPause() {
        Task {
            if snapshot.status == .playing {
                await coordinator.pause()
            } else {
                try? await coordinator.resume()
            }
        }
    }

    func seek(to time: TimeInterval) {
        Task { try? await coordinator.seek(to: time) }
    }

    func next() {
        Task { _ = try? await coordinator.next() }
    }

    func previous() {
        Task { _ = try? await coordinator.previous() }
    }

    func stop() {
        Task { await coordinator.stop() }
    }

    func setRepeatMode(_ mode: PlaybackRepeatMode) {
        Task { await coordinator.setRepeatMode(mode) }
    }

    func toggleShuffle() {
        Task { await coordinator.setShuffleEnabled(!snapshot.isShuffleEnabled) }
    }

    func dismissNotice() {
        noticeMessage = nil
    }

    func removeQueueItem(id: String) {
        Task { await coordinator.removeFromQueue(id: id) }
    }

    func removeQueueItems(at offsets: IndexSet) {
        Task {
            for index in offsets.sorted(by: >) {
                await coordinator.removeFromQueue(at: index)
            }
        }
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        Task { await coordinator.moveQueueItem(from: sourceIndex, to: destination) }
    }

    private func consume(_ snapshot: PlaybackSnapshot) {
        self.snapshot = snapshot
        if let failureMessage = snapshot.failureMessage {
            noticeMessage = failureMessage
        }
        remoteCommandController?.updateCapabilities(
            RemoteCommandCapabilities(snapshot: snapshot)
        )

        guard let item = snapshot.currentItem else {
            if snapshot.status == .idle || snapshot.status == .failed {
                nowPlayingUpdater.clear()
            }
            return
        }

        switch snapshot.status {
        case .playing, .paused, .interrupted:
            nowPlayingUpdater.update(snapshot: snapshot)
        case .idle, .loading, .failed:
            break
        }
    }
}
