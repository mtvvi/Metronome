import Foundation

struct RestoredPlaybackQueue: Equatable, Sendable {
    var items: [PlaybackItem]
    var originalItems: [PlaybackItem]
    var currentIndex: Int?
    var elapsed: TimeInterval
    var repeatMode: PlaybackRepeatMode
    var isShuffleEnabled: Bool
    var skippedItemCount = 0
}

protocol PlaybackQueueRestoring: Sendable {
    func restoreQueue() async throws -> RestoredPlaybackQueue?
}

actor LibraryPlaybackQueueRestorer: PlaybackQueueRestoring {
    private let queueRepository: any QueuePersisting
    private let trackRepository: any TrackLookupRepository
    private let locatorResolver: any PlaybackLocatorResolving
    private var retainedLocations: [String: ResolvedPlaybackLocation] = [:]

    init(
        queueRepository: any QueuePersisting,
        trackRepository: any TrackLookupRepository,
        locatorResolver: any PlaybackLocatorResolving
    ) {
        self.queueRepository = queueRepository
        self.trackRepository = trackRepository
        self.locatorResolver = locatorResolver
    }

    func restoreQueue() async throws -> RestoredPlaybackQueue? {
        guard let snapshot = try queueRepository.load(), !snapshot.itemIDs.isEmpty else {
            releaseLocations()
            return nil
        }

        let allIDs = Array(Set(snapshot.itemIDs + snapshot.originalItemIDs))
        let tracks = try trackRepository.fetchTracks(ids: allIDs)
        var tracksByID: [String: TrackRecord] = [:]
        for track in tracks {
            tracksByID[track.id] = track
        }
        var itemsByID: [String: PlaybackItem] = [:]
        var newLocations: [String: ResolvedPlaybackLocation] = [:]

        for id in allIDs {
            guard let track = tracksByID[id],
                  case .playable(let locator) = track.playbackAvailability else { continue }
            do {
                let location = try await locatorResolver.resolve(locator)
                itemsByID[id] = PlaybackItem(track: track, url: location.url)
                newLocations[id] = location
            } catch {
                continue
            }
        }

        releaseLocations()
        retainedLocations = newLocations

        let items = snapshot.itemIDs.compactMap { itemsByID[$0] }
        guard !items.isEmpty else { return nil }
        let originalIDs = snapshot.originalItemIDs.isEmpty
            ? snapshot.itemIDs
            : snapshot.originalItemIDs
        let originalItems = originalIDs.compactMap { itemsByID[$0] }
        let currentID = snapshot.currentIndex.flatMap { index in
            snapshot.itemIDs.indices.contains(index) ? snapshot.itemIDs[index] : nil
        }
        let currentIndex = currentID.flatMap { id in items.firstIndex { $0.id == id } }

        return RestoredPlaybackQueue(
            items: items,
            originalItems: originalItems,
            currentIndex: currentIndex,
            elapsed: snapshot.currentPosition,
            repeatMode: snapshot.repeatMode,
            isShuffleEnabled: snapshot.isShuffleEnabled,
            skippedItemCount: snapshot.itemIDs.count - items.count
        )
    }

    private func releaseLocations() {
        retainedLocations.values.forEach { $0.stopAccessing() }
        retainedLocations.removeAll()
    }
}
