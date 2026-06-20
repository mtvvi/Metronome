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

final class PlaybackAudioSessionEventHandler: AudioSessionEventHandling, @unchecked Sendable {
    private let playback: any PlaybackControlling
    private let diagnosticsProvider: any AudioRouteDiagnosticsProviding
    private let routeChangeReconfigurer: (any RouteChangeReconfiguring)?

    private(set) var latestDiagnostics: AudioRouteDiagnostics?

    init(
        playback: any PlaybackControlling,
        diagnosticsProvider: any AudioRouteDiagnosticsProviding,
        routeChangeReconfigurer: (any RouteChangeReconfiguring)? = nil
    ) {
        self.playback = playback
        self.diagnosticsProvider = diagnosticsProvider
        self.routeChangeReconfigurer = routeChangeReconfigurer
    }

    func handleAudioSessionEvent(_ event: AudioSessionEvent) {
        switch event {
        case .interruption(.began):
            playback.pause()
        case .interruption(.ended(let shouldResume)):
            if shouldResume {
                try? playback.resume()
            }
        case .routeChanged:
            let diagnostics = diagnosticsProvider.currentRouteDiagnostics()
            latestDiagnostics = diagnostics
            routeChangeReconfigurer?.reconfigureAfterRouteChange(diagnostics: diagnostics)
        }
    }
}

protocol RouteChangeReconfiguring: Sendable {
    func reconfigureAfterRouteChange(diagnostics: AudioRouteDiagnostics)
}
