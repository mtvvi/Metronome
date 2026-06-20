import Foundation

enum PlaybackEngineError: Error, Equatable {
    case nonFileURL(URL)
}

protocol LocalAudioPlaybackBackend: Sendable {
    func play(url: URL) throws
    func stop()
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

    func stop() {
        backend.stop()
        try? session.deactivate()
    }
}
