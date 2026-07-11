import Foundation

struct PlaybackItem: Equatable, Identifiable, Sendable {
    var id: String
    var url: URL
    var metadata: NowPlayingTrackMetadata
    var sourceSampleRate: Double? = nil
    var replayGainMetadata: ReplayGainMetadata = ReplayGainMetadata()
}

enum PlaybackStatus: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case interrupted
    case failed
}

struct PlaybackSnapshot: Equatable, Sendable {
    var status: PlaybackStatus
    var currentItem: PlaybackItem?
    var elapsed: TimeInterval
    var queue: [PlaybackItem]
    var currentIndex: Int?
    var failureMessage: String?
    var repeatMode: PlaybackRepeatMode = .off
    var isShuffleEnabled: Bool = false

    static let idle = PlaybackSnapshot(
        status: .idle,
        currentItem: nil,
        elapsed: 0,
        queue: [],
        currentIndex: nil,
        failureMessage: nil,
        repeatMode: .off,
        isShuffleEnabled: false
    )
}
