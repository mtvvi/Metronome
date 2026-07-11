import Foundation

enum GaplessTransitionExpectation: Equatable, Sendable {
    case none
    case gapless
    case graphReconfiguration(AudioFormatConversionReason)
}

struct GaplessPlaybackDiagnostics: Equatable, Sendable {
    var currentTrackTitle: String?
    var nextTrackTitle: String?
    var currentPosition: TimeInterval
    var isNextTrackPrebuffered: Bool
    var transitionExpectation: GaplessTransitionExpectation
    var generation: UInt64
}

struct GaplessPlaybackCoordinator: Sendable {
    private(set) var queue: PlaybackQueue
    private let decoder: any QueueDecoderPreparing
    private(set) var currentStream: PreparedQueueStream?
    private(set) var nextStream: PreparedQueueStream?
    private(set) var generation: UInt64 = 0

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
            isNextTrackPrebuffered: nextStream != nil,
            transitionExpectation: transitionExpectation,
            generation: generation
        )
    }

    mutating func replaceQueue(_ queue: PlaybackQueue) {
        generation &+= 1
        self.queue = queue
        currentStream = nil
        nextStream = nil
    }

    mutating func start() throws {
        generation &+= 1
        guard let currentItem = queue.currentItem else {
            currentStream = nil
            nextStream = nil
            return
        }

        currentStream = try decoder.prepareStream(
            for: currentItem,
            generation: generation
        )
        try prepareNextTrack()
    }

    mutating func prepareNextTrack() throws {
        guard let nextItem = queue.nextItem else {
            nextStream = nil
            return
        }

        if nextStream?.item.id == nextItem.id,
           nextStream?.generation == generation {
            return
        }

        let prepared = try decoder.prepareStream(
            for: nextItem,
            generation: generation
        )
        guard prepared.generation == generation else { return }
        nextStream = prepared
    }

    mutating func transitionToNextTrack() throws -> Bool {
        let previousQueue = queue
        let previousCurrent = currentStream
        let previousNext = nextStream
        let prebufferedStream = nextStream

        guard let finishedItem = queue.finishCurrent() else {
            currentStream = nil
            nextStream = nil
            return false
        }

        do {
            if prebufferedStream?.item.id == finishedItem.id,
               prebufferedStream?.generation == generation {
                currentStream = prebufferedStream
            } else {
                currentStream = try decoder.prepareStream(
                    for: finishedItem,
                    generation: generation
                )
            }

            nextStream = nil
            try prepareNextTrack()
            return true
        } catch {
            queue = previousQueue
            currentStream = previousCurrent
            nextStream = previousNext
            throw error
        }
    }

    mutating func updateCurrentPosition(_ position: TimeInterval) {
        queue.updateCurrentPosition(position)
    }

    private var transitionExpectation: GaplessTransitionExpectation {
        guard let currentFormat = currentStream?.format,
              let nextFormat = nextStream?.format else { return .none }
        return currentFormat.isGaplessCompatible(with: nextFormat)
            ? .gapless
            : .graphReconfiguration(.incompatibleGaplessTransition)
    }
}

enum GaplessContinuityAnalyzer {
    static func nearZeroSampleCount(
        samples: [Float],
        boundaryIndex: Int,
        radius: Int,
        threshold: Float = 0.000_1
    ) -> Int {
        guard !samples.isEmpty else { return 0 }
        let lower = max(0, boundaryIndex - max(0, radius))
        let upper = min(samples.count, boundaryIndex + max(0, radius))
        guard lower < upper else { return 0 }
        return samples[lower..<upper].filter { abs($0) <= threshold }.count
    }
}
