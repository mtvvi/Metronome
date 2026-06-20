import Foundation
import SFBAudioEngine

final class SFBAudioPlaybackBackend: LocalAudioPlaybackBackend, @unchecked Sendable {
    private let player: AudioPlayer

    init(player: AudioPlayer = AudioPlayer()) {
        self.player = player
    }

    func play(url: URL) throws {
        try player.play(url)
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
        player.stop()
    }

    func seek(to time: TimeInterval) throws {
        guard player.seek(time: time) else {
            throw PlaybackEngineError.playbackCommandFailed("SFBAudioEngine seek failed.")
        }
    }
}
