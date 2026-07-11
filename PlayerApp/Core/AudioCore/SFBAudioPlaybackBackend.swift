import Foundation
import SFBAudioEngine

final class SFBAudioPlaybackBackend: LocalAudioPlaybackBackend, QueuePreloadingPlaybackBackend, DSPConfigurationApplying, AudioFormatSnapshotProviding, PlaybackBackendEventSource, PlaybackProgressProviding, SpectrumAnalysisControlling, RouteChangeReconfiguring, MediaServicesResetRecovering, @unchecked Sendable {
    let graphController: AudioGraphController

    private let player: AudioPlayer
    private var preloadGeneration: UInt64 = 0

    init(
        player: AudioPlayer = AudioPlayer(),
        graphController: AudioGraphController? = nil
    ) {
        self.player = player
        self.graphController = graphController ?? AudioGraphController(player: player)
        self.graphController.install()
    }

    func play(url: URL) throws {
        try player.play(url)
        graphController.updateFormatSnapshot(conversionReason: .none)
    }

    func preload(urls: [URL], generation: UInt64) throws {
        preloadGeneration = generation
        player.clearQueue()

        for url in urls {
            guard generation == preloadGeneration else { return }
            try player.enqueue(url)
        }
    }

    func resume() throws {
        guard player.resume() else {
            throw PlaybackEngineError.playbackCommandFailed("SFBAudioEngine resume failed.")
        }
    }

    func pause() {
        _ = player.pause()
    }

    func stop() {
        preloadGeneration &+= 1
        player.stop()
    }

    func seek(to time: TimeInterval) throws {
        guard player.seek(time: time) else {
            throw PlaybackEngineError.playbackCommandFailed("SFBAudioEngine seek failed.")
        }
    }

    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot) {
        graphController.applyDSPConfiguration(snapshot)
    }

    func currentAudioFormatSnapshot() -> AudioFormatSnapshot {
        graphController.formatSnapshot
    }

    func setPlaybackEventHandler(
        _ handler: (@Sendable (PlaybackBackendEvent) -> Void)?
    ) {
        graphController.onRenderingComplete = { url in
            handler?(.renderingComplete(url))
        }
        graphController.onEndOfAudio = {
            handler?(.endOfAudio)
        }
    }

    var currentPlaybackTime: TimeInterval? { player.currentTime }

    func makeSpectrumAnalyzer() -> SpectrumAnalyzerWorker? {
        graphController.makeSpectrumAnalyzer()
    }

    func setSpectrumAnalysisEnabled(_ enabled: Bool, bitPerfect: Bool) {
        graphController.setSpectrumAnalysisEnabled(enabled, bitPerfect: bitPerfect)
    }

    func reconfigureAfterRouteChange(diagnostics: AudioRouteDiagnostics) {
        graphController.updateFormatSnapshot(conversionReason: .routeChange)
    }

    func recoverAfterMediaServicesReset() throws {
        graphController.install()
        graphController.updateFormatSnapshot(conversionReason: .routeChange)
    }
}
