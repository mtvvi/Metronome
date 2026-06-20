import Foundation

struct PreparedQueueStream: Equatable, Sendable {
    var item: PlaybackQueueItem
    var estimatedDuration: TimeInterval?

    init(
        item: PlaybackQueueItem,
        estimatedDuration: TimeInterval? = nil
    ) {
        self.item = item
        self.estimatedDuration = estimatedDuration
    }
}

protocol QueueDecoderPreparing: Sendable {
    func prepareStream(for item: PlaybackQueueItem) throws -> PreparedQueueStream
}
