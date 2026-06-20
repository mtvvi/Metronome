import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

struct SpotlightIndexItem: Equatable, Sendable {
    var uniqueIdentifier: String
    var domainIdentifier: String
    var title: String
    var displayName: String
    var contentDescription: String?
    var keywords: [String]
}

protocol SpotlightSearchIndexing: Sendable {
    func indexItems(_ items: [SpotlightIndexItem]) async throws
    func deleteItems(withIdentifiers identifiers: [String]) async throws
    func deleteItems(withDomainIdentifiers domainIdentifiers: [String]) async throws
}

protocol LibraryTrackSearchIndexing: Sendable {
    func indexTracks(_ tracks: [TrackRecord]) async throws
}

enum SpotlightTrackItemMapper {
    static let trackDomainIdentifier = "tracks"

    static func makeItem(from track: TrackRecord) -> SpotlightIndexItem {
        let title = nonEmpty(track.title) ?? track.fileName
        let primaryArtist = nonEmpty(track.albumArtist) ?? nonEmpty(track.artist)
        let contentDescription = [primaryArtist, nonEmpty(track.album)]
            .compactMap(\.self)
            .joined(separator: " - ")

        return SpotlightIndexItem(
            uniqueIdentifier: identifier(forTrackID: track.id),
            domainIdentifier: trackDomainIdentifier,
            title: title,
            displayName: title,
            contentDescription: contentDescription.isEmpty ? nil : contentDescription,
            keywords: orderedUnique([
                title,
                track.fileName,
                track.album,
                track.albumArtist,
                track.artist,
                track.composer,
                track.genre,
                track.containerFormat,
                track.codec
            ].compactMap { nonEmpty($0) })
        )
    }

    static func identifier(forTrackID trackID: String) -> String {
        "track:\(trackID)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var uniqueValues: [String] = []

        for value in values where seen.insert(value).inserted {
            uniqueValues.append(value)
        }

        return uniqueValues
    }
}

final class LibrarySpotlightIndexer: LibraryTrackSearchIndexing, @unchecked Sendable {
    private let searchIndex: any SpotlightSearchIndexing

    init(searchIndex: any SpotlightSearchIndexing = CoreSpotlightSearchIndex()) {
        self.searchIndex = searchIndex
    }

    func indexTracks(_ tracks: [TrackRecord]) async throws {
        let items = tracks.map { SpotlightTrackItemMapper.makeItem(from: $0) }
        try await searchIndex.indexItems(items)
    }

    func deleteTracks(withIDs trackIDs: [String]) async throws {
        let identifiers = trackIDs.map { SpotlightTrackItemMapper.identifier(forTrackID: $0) }
        try await searchIndex.deleteItems(withIdentifiers: identifiers)
    }

    func deleteAllTracks() async throws {
        try await searchIndex.deleteItems(
            withDomainIdentifiers: [SpotlightTrackItemMapper.trackDomainIdentifier]
        )
    }
}

final class CoreSpotlightSearchIndex: SpotlightSearchIndexing, @unchecked Sendable {
    private let index: CSSearchableIndex

    init(index: CSSearchableIndex = CSSearchableIndex(name: "PlayerAppTracks")) {
        self.index = index
    }

    func indexItems(_ items: [SpotlightIndexItem]) async throws {
        let searchableItems = items.map { Self.makeSearchableItem(from: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(searchableItems) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func deleteItems(withIdentifiers identifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func deleteItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: domainIdentifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func makeSearchableItem(from item: SpotlightIndexItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(itemContentType: UTType.audio.identifier)
        attributes.title = item.title
        attributes.displayName = item.displayName
        attributes.contentDescription = item.contentDescription
        attributes.keywords = item.keywords

        return CSSearchableItem(
            uniqueIdentifier: item.uniqueIdentifier,
            domainIdentifier: item.domainIdentifier,
            attributeSet: attributes
        )
    }
}
