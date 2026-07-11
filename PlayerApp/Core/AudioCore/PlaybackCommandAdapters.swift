import Foundation

final class PlaybackRemoteCommandHandler: RemotePlaybackCommandHandling, @unchecked Sendable {
    private let playback: any PlaybackControlling

    init(playback: any PlaybackControlling) {
        self.playback = playback
    }

    func play() -> RemoteCommandResult {
        do {
            try playback.resume()
            return .success
        } catch {
            return .commandFailed
        }
    }

    func pause() -> RemoteCommandResult {
        playback.pause()
        return .success
    }

    func next() -> RemoteCommandResult {
        .commandFailed
    }

    func previous() -> RemoteCommandResult {
        .commandFailed
    }

    func seek(to time: TimeInterval) -> RemoteCommandResult {
        do {
            try playback.seek(to: time)
            return .success
        } catch {
            return .commandFailed
        }
    }
}

final class PlaybackCoordinatorRemoteCommandHandler: RemotePlaybackCommandHandling, @unchecked Sendable {
    private let coordinator: PlaybackCoordinator

    init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    func play() -> RemoteCommandResult {
        Task { try? await coordinator.resume() }
        return .success
    }

    func pause() -> RemoteCommandResult {
        Task { await coordinator.pause() }
        return .success
    }

    func next() -> RemoteCommandResult {
        Task { _ = try? await coordinator.next() }
        return .success
    }

    func previous() -> RemoteCommandResult {
        Task { _ = try? await coordinator.previous() }
        return .success
    }

    func seek(to time: TimeInterval) -> RemoteCommandResult {
        Task { try? await coordinator.seek(to: time) }
        return .success
    }
}

final class PlaybackAudioSessionEventHandler: AudioSessionEventHandling, @unchecked Sendable {
    private let playback: any PlaybackControlling
    private let diagnosticsProvider: any AudioRouteDiagnosticsProviding
    private let routeChangeReconfigurer: (any RouteChangeReconfiguring)?
    private let isPlaybackActive: @Sendable () -> Bool
    private var wasPlayingBeforeInterruption = false

    private(set) var latestDiagnostics: AudioRouteDiagnostics?

    init(
        playback: any PlaybackControlling,
        diagnosticsProvider: any AudioRouteDiagnosticsProviding,
        routeChangeReconfigurer: (any RouteChangeReconfiguring)? = nil,
        isPlaybackActive: @escaping @Sendable () -> Bool = { true }
    ) {
        self.playback = playback
        self.diagnosticsProvider = diagnosticsProvider
        self.routeChangeReconfigurer = routeChangeReconfigurer
        self.isPlaybackActive = isPlaybackActive
    }

    func handleAudioSessionEvent(_ event: AudioSessionEvent) {
        switch event {
        case .interruption(.began):
            wasPlayingBeforeInterruption = isPlaybackActive()
            if wasPlayingBeforeInterruption {
                playback.pause()
            }
        case .interruption(.ended(let shouldResume)):
            if shouldResume && wasPlayingBeforeInterruption {
                try? playback.resume()
            }
            wasPlayingBeforeInterruption = false
        case .routeChanged(let event):
            if event.reason == .oldDeviceUnavailable, isPlaybackActive() {
                playback.pause()
            }
            let diagnostics = diagnosticsProvider.currentRouteDiagnostics()
            latestDiagnostics = diagnostics
            routeChangeReconfigurer?.reconfigureAfterRouteChange(diagnostics: diagnostics)
        case .mediaServicesWereReset:
            playback.stop()
            let diagnostics = diagnosticsProvider.currentRouteDiagnostics()
            latestDiagnostics = diagnostics
            routeChangeReconfigurer?.reconfigureAfterRouteChange(diagnostics: diagnostics)
        }
    }
}

final class PlaybackCoordinatorAudioSessionEventHandler: AudioSessionEventHandling, @unchecked Sendable {
    private let coordinator: PlaybackCoordinator
    private let equalizerRuntime: EqualizerRuntimeController?
    private let diagnosticsProvider: (any AudioRouteDiagnosticsProviding)?

    init(
        coordinator: PlaybackCoordinator,
        equalizerRuntime: EqualizerRuntimeController? = nil,
        diagnosticsProvider: (any AudioRouteDiagnosticsProviding)? = nil
    ) {
        self.coordinator = coordinator
        self.equalizerRuntime = equalizerRuntime
        self.diagnosticsProvider = diagnosticsProvider
    }

    func handleAudioSessionEvent(_ event: AudioSessionEvent) {
        Task {
            switch event {
            case .interruption(.began):
                await coordinator.handleInterruptionBegan()
            case .interruption(.ended(let shouldResume)):
                await coordinator.handleInterruptionEnded(shouldResume: shouldResume)
            case .routeChanged(let routeEvent):
                if routeEvent.reason == .oldDeviceUnavailable {
                    await coordinator.handleRouteLoss()
                }
                if let diagnostics = diagnosticsProvider?.currentRouteDiagnostics() {
                    await coordinator.handleRouteChange(diagnostics: diagnostics)
                }
                await equalizerRuntime?.refreshAfterRouteChange()
            case .mediaServicesWereReset:
                await coordinator.handleMediaServicesReset()
                if let diagnostics = diagnosticsProvider?.currentRouteDiagnostics() {
                    await coordinator.handleRouteChange(diagnostics: diagnostics)
                }
                await equalizerRuntime?.refreshAfterRouteChange()
            }
        }
    }
}

protocol RouteChangeReconfiguring: Sendable {
    func reconfigureAfterRouteChange(diagnostics: AudioRouteDiagnostics)
}
