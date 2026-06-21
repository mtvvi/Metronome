import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var rows: [LibraryTrackRow] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var isLoading = false

    private let searchRepository: (any SearchRepository)?
    private let resultLimit: Int

    init(
        searchRepository: (any SearchRepository)? = nil,
        resultLimit: Int = 200
    ) {
        self.searchRepository = searchRepository
        self.resultLimit = resultLimit
    }

    func refresh() async {
        guard let searchRepository else {
            rows = []
            statusMessage = "Library database is unavailable."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let results: [TrackSearchResult]
            if trimmedQuery.isEmpty {
                results = try searchRepository.fetchLibraryTracks(limit: resultLimit)
            } else {
                results = try searchRepository.searchTracks(matching: trimmedQuery, limit: resultLimit)
            }

            rows = results.map { LibraryTrackRow(track: $0.track) }
            statusMessage = statusMessage(resultCount: rows.count, query: trimmedQuery)
        } catch {
            rows = []
            statusMessage = "Unable to load library."
        }
    }

    private func statusMessage(resultCount: Int, query: String) -> String? {
        guard resultCount == 0 else { return nil }

        if query.isEmpty {
            return "No tracks imported yet."
        }

        return "No tracks match \"\(query)\"."
    }
}

struct LibraryTrackRow: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var technicalSummary: String

    init(track: TrackRecord) {
        id = track.id
        title = nonEmpty(track.title) ?? track.fileName
        subtitle = Self.subtitle(for: track)
        technicalSummary = Self.technicalSummary(for: track)
    }

    private static func subtitle(for track: TrackRecord) -> String {
        let artist = nonEmpty(track.artist) ?? nonEmpty(track.albumArtist)
        let album = nonEmpty(track.album)
        let parts = [artist, album].compactMap(\.self)
        return parts.isEmpty ? track.fileName : parts.joined(separator: " - ")
    }

    private static func technicalSummary(for track: TrackRecord) -> String {
        let format = nonEmpty(track.containerFormat) ?? nonEmpty(track.codec) ?? "Audio"
        var parts: [String] = [format]

        if track.isLossless {
            parts.append("Lossless")
        }

        if let sampleRate = track.sampleRate, let bitDepth = track.bitDepth {
            parts.append("\(Int((sampleRate / 1_000).rounded())) kHz / \(bitDepth)-bit")
        } else if let sampleRate = track.sampleRate {
            parts.append("\(Int((sampleRate / 1_000).rounded())) kHz")
        } else if let bitDepth = track.bitDepth {
            parts.append("\(bitDepth)-bit")
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
