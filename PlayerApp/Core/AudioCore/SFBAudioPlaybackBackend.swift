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

    func stop() {
        player.stop()
    }
}
