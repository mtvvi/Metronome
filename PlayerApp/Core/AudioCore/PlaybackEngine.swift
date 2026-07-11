import Foundation

enum PlaybackEngineError: Error, Equatable, LocalizedError {
    case nonFileURL(URL)
    case playbackCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .nonFileURL:
            String(localized: "Only local audio files can be played.")
        case .playbackCommandFailed(let message):
            message
        }
    }
}

protocol LocalAudioPlaybackBackend: Sendable {
    func play(url: URL) throws
    func resume() throws
    func pause()
    func stop()
    func seek(to time: TimeInterval) throws
}

protocol QueuePreloadingPlaybackBackend: Sendable {
    func preload(urls: [URL], generation: UInt64) throws
}

protocol PlaybackProgressProviding: Sendable {
    var currentPlaybackTime: TimeInterval? { get }
}

protocol MediaServicesResetRecovering: Sendable {
    func recoverAfterMediaServicesReset() throws
}

protocol SpectrumAnalysisControlling: Sendable {
    func makeSpectrumAnalyzer() -> SpectrumAnalyzerWorker?
    func setSpectrumAnalysisEnabled(_ enabled: Bool, bitPerfect: Bool)
}

enum PlaybackBackendEvent: Sendable {
    case renderingComplete(URL?)
    case endOfAudio
}

protocol PlaybackBackendEventSource: Sendable {
    func setPlaybackEventHandler(
        _ handler: (@Sendable (PlaybackBackendEvent) -> Void)?
    )
}

final class PlaybackEngine: PlaybackControlling, @unchecked Sendable {
    private let session: any AudioSessionControlling
    private let backend: any LocalAudioPlaybackBackend

    init(
        session: any AudioSessionControlling = AudioSessionController(),
        backend: any LocalAudioPlaybackBackend = SFBAudioPlaybackBackend()
    ) {
        self.session = session
        self.backend = backend
    }

    func play(url: URL) throws {
        guard url.isFileURL else {
            throw PlaybackEngineError.nonFileURL(url)
        }

        try session.configureForPlayback()
        try session.activate()

        do {
            try backend.play(url: url)
        } catch {
            try? session.deactivate()
            throw error
        }
    }

    func resume() throws {
        try session.configureForPlayback()
        try session.activate()
        do {
            try backend.resume()
        } catch {
            try? session.deactivate()
            throw error
        }
    }

    func pause() {
        backend.pause()
    }

    func stop() {
        backend.stop()
        try? session.deactivate()
    }

    func seek(to time: TimeInterval) throws {
        try backend.seek(to: time)
    }
}

extension PlaybackEngine: QueuePreloadingPlaybackBackend {
    func preload(urls: [URL], generation: UInt64) throws {
        guard let queueBackend = backend as? any QueuePreloadingPlaybackBackend else {
            return
        }
        try queueBackend.preload(urls: urls, generation: generation)
    }
}

extension PlaybackEngine: DSPConfigurationApplying {
    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot) {
        guard let applicator = backend as? any DSPConfigurationApplying else { return }
        applicator.applyDSPConfiguration(snapshot)
    }
}

extension PlaybackEngine: AudioRouteDiagnosticsProviding {
    func currentRouteDiagnostics() -> AudioRouteDiagnostics {
        guard let provider = session as? any AudioRouteDiagnosticsProviding else {
            return AudioRouteDiagnostics(
                actualSampleRate: 0,
                outputs: [],
                isSessionActive: false
            )
        }
        var diagnostics = provider.currentRouteDiagnostics()
        if let formatProvider = backend as? any AudioFormatSnapshotProviding {
            let format = formatProvider.currentAudioFormatSnapshot()
            diagnostics.sourceFormat = format.source
            diagnostics.processingFormat = format.processing
            diagnostics.actualOutputFormat = format.actualOutput
            diagnostics.conversionReason = format.conversionReason
        }
        return diagnostics
    }
}

extension PlaybackEngine: PreferredSampleRateRequesting {
    func requestPreferredSampleRate(_ sampleRate: Double) throws {
        try (session as? any PreferredSampleRateRequesting)?
            .requestPreferredSampleRate(sampleRate)
    }
}

extension PlaybackEngine: PlaybackBackendEventSource {
    func setPlaybackEventHandler(
        _ handler: (@Sendable (PlaybackBackendEvent) -> Void)?
    ) {
        (backend as? any PlaybackBackendEventSource)?.setPlaybackEventHandler(handler)
    }
}

extension PlaybackEngine: PlaybackProgressProviding {
    var currentPlaybackTime: TimeInterval? {
        (backend as? any PlaybackProgressProviding)?.currentPlaybackTime
    }
}

extension PlaybackEngine: SpectrumAnalysisControlling {
    func makeSpectrumAnalyzer() -> SpectrumAnalyzerWorker? {
        (backend as? any SpectrumAnalysisControlling)?.makeSpectrumAnalyzer()
    }

    func setSpectrumAnalysisEnabled(_ enabled: Bool, bitPerfect: Bool) {
        (backend as? any SpectrumAnalysisControlling)?
            .setSpectrumAnalysisEnabled(enabled, bitPerfect: bitPerfect)
    }
}

extension PlaybackEngine: RouteChangeReconfiguring {
    func reconfigureAfterRouteChange(diagnostics: AudioRouteDiagnostics) {
        (backend as? any RouteChangeReconfiguring)?
            .reconfigureAfterRouteChange(diagnostics: diagnostics)
    }
}

extension PlaybackEngine: MediaServicesResetRecovering {
    func recoverAfterMediaServicesReset() throws {
        try (backend as? any MediaServicesResetRecovering)?
            .recoverAfterMediaServicesReset()
    }
}
