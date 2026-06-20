import Foundation

struct GaplessPlaybackDiagnostics: Equatable, Sendable {
    var currentTrackTitle: String?
    var nextTrackTitle: String?
    var currentPosition: TimeInterval
    var isNextTrackPrebuffered: Bool
}

struct GaplessPlaybackCoordinator: Sendable {
    private(set) var queue: PlaybackQueue
    private let decoder: any QueueDecoderPreparing
    private(set) var currentStream: PreparedQueueStream?
    private(set) var nextStream: PreparedQueueStream?

    init(
        queue: PlaybackQueue,
        decoder: any QueueDecoderPreparing
    ) {
        self.queue = queue
        self.decoder = decoder
    }

    var diagnostics: GaplessPlaybackDiagnostics {
        GaplessPlaybackDiagnostics(
            currentTrackTitle: queue.currentItem?.title,
            nextTrackTitle: nextStream?.item.title,
            currentPosition: queue.currentPosition,
            isNextTrackPrebuffered: nextStream != nil
        )
    }

    mutating func start() throws {
        guard let currentItem = queue.currentItem else {
            currentStream = nil
            nextStream = nil
            return
        }

        currentStream = try decoder.prepareStream(for: currentItem)
        try prepareNextTrack()
    }

    mutating func prepareNextTrack() throws {
        guard let nextItem = queue.nextItem else {
            nextStream = nil
            return
        }

        if nextStream?.item.id == nextItem.id {
            return
        }

        nextStream = try decoder.prepareStream(for: nextItem)
    }

    mutating func transitionToNextTrack() -> Bool {
        guard queue.nextItem != nil else {
            return false
        }

        let prebufferedStream = nextStream
        guard queue.advanceToNext() else {
            return false
        }

        if prebufferedStream?.item.id == queue.currentItem?.id {
            currentStream = prebufferedStream
        } else if let currentItem = queue.currentItem {
            currentStream = try? decoder.prepareStream(for: currentItem)
        } else {
            currentStream = nil
        }

        nextStream = nil
        try? prepareNextTrack()
        return true
    }

    mutating func updateCurrentPosition(_ position: TimeInterval) {
        queue.updateCurrentPosition(position)
    }
}
