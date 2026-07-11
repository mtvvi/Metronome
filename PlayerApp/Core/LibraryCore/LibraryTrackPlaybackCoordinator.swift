import Foundation

enum LibraryTrackPlaybackError: Error, Equatable, Sendable {
    case unavailable(PlaybackUnavailabilityReason)
}

protocol LibraryTrackPlaybackStarting: Sendable {
    func play(track: TrackRecord) async throws
}

protocol LibraryQueuePlaybackStarting: Sendable {
    func playNext(track: TrackRecord) async throws
    func addLast(track: TrackRecord) async throws
}

struct LibraryCollectionPlaybackSummary: Equatable, Sendable {
    var playableCount: Int
    var skippedCount: Int
    var firstPlayedTrackID: String?
}

protocol LibraryCollectionPlaybackStarting: Sendable {
    func play(tracks: [TrackRecord]) async throws -> LibraryCollectionPlaybackSummary
}

actor LibraryTrackPlaybackCoordinator: LibraryTrackPlaybackStarting, LibraryQueuePlaybackStarting, LibraryCollectionPlaybackStarting {
    private let locatorResolver: any PlaybackLocatorResolving
    private let playback: any PlaybackCoordinating
    private var currentLocation: ResolvedPlaybackLocation?
    private var currentLocationID: String?
    private var queuedLocations: [String: ResolvedPlaybackLocation] = [:]
    private var leaseObservationTask: Task<Void, Never>?

    init(
        locatorResolver: any PlaybackLocatorResolving,
        playback: any PlaybackCoordinating
    ) {
        self.locatorResolver = locatorResolver
        self.playback = playback
    }

    func play(track: TrackRecord) async throws {
        ensureLeaseObservation()
        guard case .playable(let locator) = track.playbackAvailability else {
            if case .unavailable(let reason) = track.playbackAvailability {
                throw LibraryTrackPlaybackError.unavailable(reason)
            }
            throw LibraryTrackPlaybackError.unavailable(.missingLocator)
        }

        let location = try await locatorResolver.resolve(locator)

        do {
            try await playback.play(item: PlaybackItem(track: track, url: location.url))
            currentLocation?.stopAccessing()
            currentLocation = location
            currentLocationID = track.id
        } catch {
            location.stopAccessing()
            throw error
        }
    }

    func stop() async {
        await playback.stop()
        currentLocation?.stopAccessing()
        currentLocation = nil
        currentLocationID = nil
    }

    func playNext(track: TrackRecord) async throws {
        ensureLeaseObservation()
        guard let queuePlayback = playback as? any PlaybackQueueCoordinating else {
            throw LibraryTrackPlaybackError.unavailable(.sourceUnavailable)
        }
        let resolved = try await resolve(track: track)
        await queuePlayback.playNext(resolved.item)
        queuedLocations[track.id]?.stopAccessing()
        queuedLocations[track.id] = resolved.location
    }

    func addLast(track: TrackRecord) async throws {
        ensureLeaseObservation()
        guard let queuePlayback = playback as? any PlaybackQueueCoordinating else {
            throw LibraryTrackPlaybackError.unavailable(.sourceUnavailable)
        }
        let resolved = try await resolve(track: track)
        await queuePlayback.addLast(resolved.item)
        queuedLocations[track.id]?.stopAccessing()
        queuedLocations[track.id] = resolved.location
    }

    func play(tracks: [TrackRecord]) async throws -> LibraryCollectionPlaybackSummary {
        ensureLeaseObservation()
        guard let queuePlayback = playback as? any PlaybackQueueCoordinating else {
            throw LibraryTrackPlaybackError.unavailable(.sourceUnavailable)
        }
        var items: [PlaybackItem] = []
        var locations: [String: ResolvedPlaybackLocation] = [:]
        var skippedCount = 0
        for track in tracks {
            guard case .playable = track.playbackAvailability else {
                skippedCount += 1
                continue
            }
            do {
                let resolved = try await resolve(track: track)
                items.append(resolved.item)
                locations[track.id] = resolved.location
            } catch is CancellationError {
                locations.values.forEach { $0.stopAccessing() }
                throw CancellationError()
            } catch {
                skippedCount += 1
                continue
            }
        }
        guard !items.isEmpty else {
            throw LibraryTrackPlaybackError.unavailable(.sourceUnavailable)
        }
        do {
            try await queuePlayback.play(items: items, startingAt: 0)
            currentLocation?.stopAccessing()
            currentLocation = nil
            currentLocationID = nil
            queuedLocations.values.forEach { $0.stopAccessing() }
            queuedLocations = locations
            return LibraryCollectionPlaybackSummary(
                playableCount: items.count,
                skippedCount: skippedCount,
                firstPlayedTrackID: items.first?.id
            )
        } catch {
            locations.values.forEach { $0.stopAccessing() }
            throw error
        }
    }

    private func resolve(track: TrackRecord) async throws -> (
        item: PlaybackItem,
        location: ResolvedPlaybackLocation
    ) {
        guard case .playable(let locator) = track.playbackAvailability else {
            if case .unavailable(let reason) = track.playbackAvailability {
                throw LibraryTrackPlaybackError.unavailable(reason)
            }
            throw LibraryTrackPlaybackError.unavailable(.missingLocator)
        }
        let location = try await locatorResolver.resolve(locator)
        return (PlaybackItem(track: track, url: location.url), location)
    }

    private func ensureLeaseObservation() {
        guard leaseObservationTask == nil,
              let coordinator = playback as? PlaybackCoordinator else { return }
        leaseObservationTask = Task { [weak self] in
            let snapshots = await coordinator.snapshots()
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                await self?.reconcileLeases(with: snapshot)
            }
        }
    }

    private func reconcileLeases(with snapshot: PlaybackSnapshot) {
        if currentLocationID != snapshot.currentItem?.id {
            currentLocation?.stopAccessing()
            currentLocation = nil
            currentLocationID = nil
        }
        let retainedQueueIDs = Set(snapshot.queue.map(\.id))
        let releasedIDs = queuedLocations.keys.filter { !retainedQueueIDs.contains($0) }
        for id in releasedIDs {
            queuedLocations[id]?.stopAccessing()
            queuedLocations[id] = nil
        }
    }
}

extension PlaybackItem {
    init(track: TrackRecord, url: URL) {
        self.init(
            id: track.id,
            url: url,
            metadata: NowPlayingTrackMetadata(
                fileName: track.fileName,
                title: Self.nonEmpty(track.title),
                artist: Self.nonEmpty(track.artist) ?? Self.nonEmpty(track.albumArtist),
                albumTitle: Self.nonEmpty(track.album),
                duration: track.duration,
                artworkID: track.artworkID
            ),
            sourceSampleRate: track.sampleRate,
            replayGainMetadata: ReplayGainMetadata(track: track)
        )
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
