import XCTest
@testable import PlayerApp

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testLoadsLibraryRowsFromRepository() async {
        let repository = FakeLibrarySearchRepository(
            libraryResults: [
                TrackSearchResult(track: Self.track(
                    id: "track-1",
                    title: "So What",
                    album: "Kind of Blue",
                    artist: "Miles Davis",
                    fileName: "01 So What.flac",
                    sampleRate: 96_000,
                    bitDepth: 24,
                    duration: 545,
                    isLossless: true
                ))
            ]
        )
        let viewModel = LibraryViewModel(searchRepository: repository)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.rows.map(\.id), ["track-1"])
        XCTAssertEqual(viewModel.rows.map(\.title), ["So What"])
        XCTAssertEqual(viewModel.rows.map(\.subtitle), ["Miles Davis - Kind of Blue"])
        XCTAssertEqual(viewModel.rows.map(\.technicalSummary), ["FLAC Lossless - 96 kHz / 24-bit - 9:05"])
        XCTAssertNil(viewModel.statusMessage)
    }

    func testSearchUsesQueryAndShowsEmptyState() async {
        let repository = FakeLibrarySearchRepository(searchResults: [])
        let viewModel = LibraryViewModel(searchRepository: repository)
        viewModel.searchText = "coltrane"

        await viewModel.refresh()

        XCTAssertEqual(repository.searchQueries, ["coltrane"])
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(viewModel.statusMessage, "No tracks match \"coltrane\".")
    }

    private static func track(
        id: String,
        title: String?,
        album: String?,
        artist: String?,
        fileName: String,
        sampleRate: Double?,
        bitDepth: Int?,
        duration: Double?,
        isLossless: Bool
    ) -> TrackRecord {
        TrackRecord(
            id: id,
            sourceRootID: "source-1",
            sourceKind: "securityScopedFolder",
            bookmarkData: nil,
            mediaPersistentID: nil,
            relativePath: fileName,
            fileName: fileName,
            fileSize: nil,
            modifiedDate: nil,
            contentHash: nil,
            containerFormat: "FLAC",
            codec: "FLAC",
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: 2,
            duration: duration,
            totalFrames: nil,
            bitrate: nil,
            isLossless: isLossless,
            isDSD: false,
            dsdRate: nil,
            title: title,
            album: album,
            albumArtist: nil,
            artist: artist,
            composer: nil,
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

private final class FakeLibrarySearchRepository: SearchRepository, @unchecked Sendable {
    private let libraryResults: [TrackSearchResult]
    private let searchResults: [TrackSearchResult]
    private(set) var searchQueries: [String] = []

    init(
        libraryResults: [TrackSearchResult] = [],
        searchResults: [TrackSearchResult] = []
    ) {
        self.libraryResults = libraryResults
        self.searchResults = searchResults
    }

    func fetchLibraryTracks(limit: Int) throws -> [TrackSearchResult] {
        libraryResults
    }

    func searchTracks(matching query: String, limit: Int) throws -> [TrackSearchResult] {
        searchQueries.append(query)
        return searchResults
    }
}
