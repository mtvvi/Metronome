import Foundation

enum PlaybackEngineError: Error, Equatable {
    case nonFileURL(URL)
    case playbackCommandFailed(String)
}

protocol LocalAudioPlaybackBackend: Sendable {
    func play(url: URL) throws
    func resume() throws
    func pause()
    func stop()
    func seek(to time: TimeInterval) throws
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
        try backend.resume()
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
