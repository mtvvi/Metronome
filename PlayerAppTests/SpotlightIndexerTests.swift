import XCTest
@testable import PlayerApp

final class SpotlightIndexerTests: XCTestCase {
    func testTrackMapperUsesStableIdentifierAndReadableTitle() {
        let item = SpotlightTrackItemMapper.makeItem(from: Self.track(title: "So What"))

        XCTAssertEqual(item.uniqueIdentifier, "track:track-1")
        XCTAssertEqual(item.domainIdentifier, "tracks")
        XCTAssertEqual(item.title, "So What")
        XCTAssertEqual(item.displayName, "So What")
    }

    func testTrackMapperFallsBackToFileNameAndBuildsSearchMetadata() {
        let item = SpotlightTrackItemMapper.makeItem(from: Self.track(title: nil))

        XCTAssertEqual(item.title, "01 So What.flac")
        XCTAssertEqual(item.displayName, "01 So What.flac")
        XCTAssertEqual(item.contentDescription, "Miles Davis - Kind of Blue")
        XCTAssertEqual(
            item.keywords,
            [
                "01 So What.flac",
                "Kind of Blue",
                "Miles Davis",
                "Miles Davis Quintet",
                "Bill Evans",
                "Jazz",
                "FLAC"
            ]
        )
    }

    func testIndexerIndexesTracksAndDeletesByStableIdentifiers() async throws {
        let searchIndex = FakeSpotlightSearchIndex()
        let indexer = LibrarySpotlightIndexer(searchIndex: searchIndex)

        try await indexer.indexTracks([Self.track(title: "So What")])
        try await indexer.deleteTracks(withIDs: ["track-1", "track-2"])
        try await indexer.deleteAllTracks()

        XCTAssertEqual(searchIndex.indexedItems.map(\.uniqueIdentifier), ["track:track-1"])
        XCTAssertEqual(searchIndex.deletedIdentifiers, ["track:track-1", "track:track-2"])
        XCTAssertEqual(searchIndex.deletedDomainIdentifiers, ["tracks"])
    }

    private static func track(title: String?) -> TrackRecord {
        TrackRecord(
            id: "track-1",
            sourceRootID: "source-1",
            sourceKind: "appDocuments",
            bookmarkData: nil,
            mediaPersistentID: nil,
            relativePath: "Albums/Kind of Blue/01 So What.flac",
            fileName: "01 So What.flac",
            fileSize: 128,
            modifiedDate: 1_803_000_000,
            contentHash: nil,
            containerFormat: "FLAC",
            codec: "FLAC",
            sampleRate: 96_000,
            bitDepth: 24,
            channelCount: 2,
            duration: 545,
            totalFrames: nil,
            bitrate: nil,
            isLossless: true,
            isDSD: false,
            dsdRate: nil,
            title: title,
            album: "Kind of Blue",
            albumArtist: "Miles Davis",
            artist: "Miles Davis Quintet",
            composer: "Bill Evans",
            genre: "Jazz",
            year: 1959,
            discNumber: nil,
            discTotal: nil,
            trackNumber: 1,
            trackTotal: nil,
            sortTitle: nil,
            sortAlbum: nil,
            sortArtist: nil,
            musicBrainzID: nil,
            replayGainTrackGain: nil,
            replayGainAlbumGain: nil,
            replayGainTrackPeak: nil,
            replayGainAlbumPeak: nil,
            artworkID: nil
        )
    }
}

private final class FakeSpotlightSearchIndex: SpotlightSearchIndexing, @unchecked Sendable {
    private(set) var indexedItems: [SpotlightIndexItem] = []
    private(set) var deletedIdentifiers: [String] = []
    private(set) var deletedDomainIdentifiers: [String] = []

    func indexItems(_ items: [SpotlightIndexItem]) async throws {
        indexedItems = items
    }

    func deleteItems(withIdentifiers identifiers: [String]) async throws {
        deletedIdentifiers = identifiers
    }

    func deleteItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        deletedDomainIdentifiers = domainIdentifiers
    }
}
