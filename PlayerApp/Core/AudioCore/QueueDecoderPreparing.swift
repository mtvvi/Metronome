import Foundation

struct PreparedQueueStream: Equatable, Sendable {
    var item: PlaybackQueueItem
    var estimatedDuration: TimeInterval?
    var format: AudioStreamFormatSnapshot?
    var generation: UInt64

    init(
        item: PlaybackQueueItem,
        estimatedDuration: TimeInterval? = nil,
        format: AudioStreamFormatSnapshot? = nil,
        generation: UInt64 = 0
    ) {
        self.item = item
        self.estimatedDuration = estimatedDuration
        self.format = format ?? item.format
        self.generation = generation
    }
}

protocol QueueDecoderPreparing: Sendable {
    func prepareStream(for item: PlaybackQueueItem) throws -> PreparedQueueStream
    func prepareStream(
        for item: PlaybackQueueItem,
        generation: UInt64
    ) throws -> PreparedQueueStream
}

extension QueueDecoderPreparing {
    func prepareStream(
        for item: PlaybackQueueItem,
        generation: UInt64
    ) throws -> PreparedQueueStream {
        var stream = try prepareStream(for: item)
        stream.generation = generation
        return stream
    }
}
