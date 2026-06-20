import Foundation
@preconcurrency import MediaPlayer

struct NowPlayingTrackMetadata: Equatable, Sendable {
    var fileName: String
    var title: String?
    var artist: String?
    var albumTitle: String?
    var duration: TimeInterval?
}

@MainActor
protocol NowPlayingInfoWriting: AnyObject {
    var nowPlayingInfo: [String: Any]? { get set }
}

@MainActor
final class SystemNowPlayingInfoWriter: NowPlayingInfoWriting {
    private let center: MPNowPlayingInfoCenter

    init(center: MPNowPlayingInfoCenter = .default()) {
        self.center = center
    }

    var nowPlayingInfo: [String: Any]? {
        get { center.nowPlayingInfo }
        set { center.nowPlayingInfo = newValue }
    }
}

@MainActor
final class NowPlayingController {
    private let infoWriter: any NowPlayingInfoWriting

    init(infoWriter: any NowPlayingInfoWriting = SystemNowPlayingInfoWriter()) {
        self.infoWriter = infoWriter
    }

    func update(
        track: NowPlayingTrackMetadata,
        elapsed: TimeInterval,
        playbackRate: Double
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title ?? track.fileName,
            MPMediaItemPropertyArtist: track.artist ?? "",
            MPMediaItemPropertyAlbumTitle: track.albumTitle ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate
        ]

        if let duration = track.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        infoWriter.nowPlayingInfo = info
    }

    func clear() {
        infoWriter.nowPlayingInfo = nil
    }
}
