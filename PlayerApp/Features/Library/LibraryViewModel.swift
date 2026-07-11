import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    enum Section: CaseIterable, Identifiable {
        case tracks
        case albums
        case artists
        var id: Self { self }
        var title: String {
            switch self {
            case .tracks: String(localized: "Tracks")
            case .albums: String(localized: "Albums")
            case .artists: String(localized: "Artists")
            }
        }
    }

    @Published var searchText: String = ""
    @Published var selectedSection: Section = .tracks
    @Published private(set) var state: LoadableState<[LibraryTrackRow]> = .idle
    @Published private(set) var notice: LibraryNotice?
    @Published private(set) var currentlyPlayingTrackID: String?
    @Published private(set) var albums: [AlbumSummary] = []
    @Published private(set) var artists: [ArtistSummary] = []
    @Published private(set) var hasMoreTracks = false

    private let searchRepository: (any SearchRepository)?
    private let playbackStarter: (any LibraryTrackPlaybackStarting)?
    private let browsingRepository: (any LibraryBrowsingRepository)?
    let artworkLoader: (any ArtworkThumbnailLoading)?
    private let resultLimit: Int
    private var playbackObservationTask: Task<Void, Never>?
    private var libraryObservationTask: Task<Void, Never>?

    init(
        searchRepository: (any SearchRepository)? = nil,
        playbackStarter: (any LibraryTrackPlaybackStarting)? = nil,
        artworkLoader: (any ArtworkThumbnailLoading)? = nil,
        playbackCoordinator: PlaybackCoordinator? = nil,
        resultLimit: Int = 200
    ) {
        self.searchRepository = searchRepository
        self.playbackStarter = playbackStarter
        self.browsingRepository = searchRepository as? any LibraryBrowsingRepository
        self.artworkLoader = artworkLoader
        self.resultLimit = resultLimit
        if let observer = searchRepository as? any LibraryChangeObservingRepository {
            let changes = observer.libraryChanges()
            libraryObservationTask = Task { [weak self] in
                for await _ in changes {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        }
        if let playbackCoordinator {
            playbackObservationTask = Task { [weak self] in
                let snapshots = await playbackCoordinator.snapshots()
                for await snapshot in snapshots {
                    guard !Task.isCancelled else { return }
                    self?.currentlyPlayingTrackID = snapshot.currentItem?.id
                }
            }
        }
    }

    deinit {
        playbackObservationTask?.cancel()
        libraryObservationTask?.cancel()
    }

    var rows: [LibraryTrackRow] {
        state.currentValue ?? []
    }

    var isLoading: Bool {
        state.isLoading
    }

    var loadError: AppError? {
        state.error
    }

    var emptyStateMessage: String? {
        guard case .loaded(let rows) = state, rows.isEmpty else { return nil }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return String(localized: "No tracks imported yet.")
        }

        return LocalizedFormat.string(
            "No tracks match \"%@\".",
            trimmedQuery
        )
    }

    func refresh() async {
        let previousRows = rows
        let previous = previousRows.isEmpty ? nil : previousRows

        guard let searchRepository else {
            state = .failed(.libraryUnavailable, previous: previous)
            return
        }

        state = .loading(previous: previous)

        do {
            let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let results: [TrackSearchResult]
            if trimmedQuery.isEmpty {
                if let browsingRepository {
                    let pageSize = resultLimit
                    let loaded = try await Task.detached {
                        (
                            try browsingRepository.fetchTrackPage(after: nil, limit: pageSize),
                            try browsingRepository.fetchAlbums(),
                            try browsingRepository.fetchArtists()
                        )
                    }.value
                    guard !Task.isCancelled else { return }
                    results = loaded.0.tracks.map(TrackSearchResult.init(track:))
                    hasMoreTracks = loaded.0.hasMore
                    albums = loaded.1
                    artists = loaded.2
                } else {
                    let limit = resultLimit
                    results = try await Task.detached {
                        try searchRepository.fetchLibraryTracks(limit: limit)
                    }.value
                    hasMoreTracks = false
                }
            } else {
                let limit = resultLimit + 1
                let searchResults = try await Task.detached {
                    try searchRepository.searchTracks(matching: trimmedQuery, limit: limit)
                }.value
                guard !Task.isCancelled else { return }
                results = Array(searchResults.prefix(resultLimit))
                hasMoreTracks = searchResults.count > resultLimit
            }

            guard !Task.isCancelled else { return }
            state = .loaded(results.map { LibraryTrackRow(track: $0.track) })
        } catch {
            state = .failed(
                .libraryLoadFailed(diagnostic: String(describing: error)),
                previous: previous
            )
        }
    }

    func loadMoreTracks() async {
        guard hasMoreTracks else { return }
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty, let searchRepository {
            do {
                let requestedCount = rows.count + resultLimit
                let results = try await Task.detached {
                    try searchRepository.searchTracks(
                        matching: trimmedQuery,
                        limit: requestedCount + 1
                    )
                }.value
                state = .loaded(
                    results.prefix(requestedCount).map { LibraryTrackRow(track: $0.track) }
                )
                hasMoreTracks = results.count > requestedCount
            } catch {
                notice = LibraryNotice(
                    kind: .error,
                    message: String(localized: "Unable to load more search results.")
                )
            }
            return
        }
        guard let browsingRepository, let last = rows.last?.track else { return }
        let cursor = LibraryTrackCursor(
            albumSort: last.album ?? "",
            discNumber: last.discNumber ?? 0,
            trackNumber: last.trackNumber ?? 0,
            fileName: last.fileName,
            id: last.id
        )
        do {
            let limit = resultLimit
            let page = try await Task.detached {
                try browsingRepository.fetchTrackPage(after: cursor, limit: limit)
            }.value
            state = .loaded(rows + page.tracks.map(LibraryTrackRow.init(track:)))
            hasMoreTracks = page.hasMore
        } catch {
            notice = LibraryNotice(
                kind: .error,
                message: String(localized: "Unable to load more tracks.")
            )
        }
    }

    func tracks(for album: AlbumSummary) async -> [LibraryTrackRow] {
        guard let browsingRepository else { return [] }
        do {
            let tracks = try await Task.detached {
                try browsingRepository.fetchTracks(
                    album: album.title,
                    albumArtist: album.albumArtist
                )
            }.value
            return tracks.map(LibraryTrackRow.init(track:))
        } catch {
            notice = LibraryNotice(
                kind: .error,
                message: String(localized: "Unable to load this album.")
            )
            return []
        }
    }

    func tracks(for artist: ArtistSummary) async -> [LibraryTrackRow] {
        guard let browsingRepository else { return [] }
        do {
            let tracks = try await Task.detached {
                try browsingRepository.fetchTracks(artist: artist.name)
            }.value
            return tracks.map(LibraryTrackRow.init(track:))
        } catch {
            notice = LibraryNotice(
                kind: .error,
                message: String(localized: "Unable to load this artist.")
            )
            return []
        }
    }

    func play(rows: [LibraryTrackRow], collectionName: String) async {
        guard let collectionPlayback = playbackStarter as? any LibraryCollectionPlaybackStarting else {
            notice = LibraryNotice(
                kind: .error,
                message: String(localized: "Collection playback is unavailable.")
            )
            return
        }
        do {
            let summary = try await collectionPlayback.play(tracks: rows.map(\.track))
            currentlyPlayingTrackID = summary.firstPlayedTrackID
            if summary.skippedCount > 0 {
                let queuedUnit = summary.playableCount == 1
                    ? String(localized: "track")
                    : String(localized: "tracks")
                let skippedUnit = summary.skippedCount == 1
                    ? String(localized: "track")
                    : String(localized: "tracks")
                notice = LibraryNotice(
                    kind: .information,
                    message: LocalizedFormat.string(
                        "Playing %@. %lld %@ queued; %lld unavailable %@ skipped.",
                        collectionName,
                        Int64(summary.playableCount),
                        queuedUnit,
                        Int64(summary.skippedCount),
                        skippedUnit
                    )
                )
            } else {
                notice = LibraryNotice(
                    kind: .information,
                    message: LocalizedFormat.string("Playing %@.", collectionName)
                )
            }
        } catch {
            notice = LibraryNotice(
                kind: .error,
                message: LocalizedFormat.string("Unable to play %@.", collectionName)
            )
        }
    }

    func playNext(row: LibraryTrackRow) async {
        guard let queue = playbackStarter as? any LibraryQueuePlaybackStarting else { return }
        do {
            try await queue.playNext(track: row.track)
            notice = LibraryNotice(
                kind: .information,
                message: LocalizedFormat.string("Playing next: %@.", row.title)
            )
        } catch {
            notice = LibraryNotice(
                kind: .error,
                message: LocalizedFormat.string("Unable to add %@ next.", row.title)
            )
        }
    }

    func addLast(row: LibraryTrackRow) async {
        guard let queue = playbackStarter as? any LibraryQueuePlaybackStarting else { return }
        do {
            try await queue.addLast(track: row.track)
            notice = LibraryNotice(
                kind: .information,
                message: LocalizedFormat.string("Added %@ to queue.", row.title)
            )
        } catch {
            notice = LibraryNotice(
                kind: .error,
                message: LocalizedFormat.string("Unable to add %@ to queue.", row.title)
            )
        }
    }

    func play(row: LibraryTrackRow) async {
        guard case .playable = row.playbackAvailability else {
            if case .unavailable(let reason) = row.playbackAvailability {
                notice = LibraryNotice(kind: .error, message: reason.message)
            }
            return
        }

        guard let playbackStarter else {
            notice = LibraryNotice(
                kind: .error,
                message: String(localized: "Playback is unavailable.")
            )
            return
        }

        do {
            try await playbackStarter.play(track: row.track)
            currentlyPlayingTrackID = row.id
            notice = LibraryNotice(
                kind: .information,
                message: LocalizedFormat.string("Playing %@.", row.title)
            )
        } catch MusicItemAssetResolutionError.unavailable(let reason) {
            markUnavailable(rowID: row.id, reason: reason)
            notice = LibraryNotice(kind: .error, message: reason.message)
        } catch {
            notice = LibraryNotice(
                kind: .error,
                message: LocalizedFormat.string("Unable to play %@.", row.title)
            )
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func markUnavailable(
        rowID: String,
        reason: PlaybackUnavailabilityReason
    ) {
        let updatedRows = rows.map { row in
            guard row.id == rowID else { return row }
            var updatedRow = row
            updatedRow.playbackAvailability = .unavailable(reason)
            return updatedRow
        }
        state = .loaded(updatedRows)
    }
}

struct LibraryNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case information
        case error
    }

    var kind: Kind
    var message: String
}

struct LibraryTrackRow: Identifiable, Equatable, Sendable {
    var id: String
    var track: TrackRecord
    var title: String
    var subtitle: String
    var technicalSummary: String
    var playbackAvailability: PlaybackAvailability

    init(track: TrackRecord) {
        id = track.id
        self.track = track
        title = nonEmpty(track.title) ?? track.fileName
        subtitle = Self.subtitle(for: track)
        technicalSummary = Self.technicalSummary(for: track)
        playbackAvailability = track.playbackAvailability
    }

    private static func subtitle(for track: TrackRecord) -> String {
        let artist = nonEmpty(track.artist) ?? nonEmpty(track.albumArtist)
        let album = nonEmpty(track.album)
        let parts = [artist, album].compactMap(\.self)
        return parts.isEmpty ? track.fileName : parts.joined(separator: " - ")
    }

    private static func technicalSummary(for track: TrackRecord) -> String {
        let format = nonEmpty(track.containerFormat)
            ?? nonEmpty(track.codec)
            ?? String(localized: "Audio")
        var parts: [String] = [format]

        if track.isLossless {
            parts.append(String(localized: "Lossless"))
        }

        if let sampleRate = track.sampleRate, let bitDepth = track.bitDepth {
            parts.append(LocalizedFormat.string(
                "%lld kHz / %lld-bit",
                Int64((sampleRate / 1_000).rounded()),
                Int64(bitDepth)
            ))
        } else if let sampleRate = track.sampleRate {
            parts.append(LocalizedFormat.string(
                "%lld kHz",
                Int64((sampleRate / 1_000).rounded())
            ))
        } else if let bitDepth = track.bitDepth {
            parts.append(LocalizedFormat.string("%lld-bit", Int64(bitDepth)))
        }

        if let duration = track.duration {
            parts.append(formatDuration(duration))
        }

        return parts.joined(separator: " - ")
    }

    private static func formatDuration(_ duration: Double) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
