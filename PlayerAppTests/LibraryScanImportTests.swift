import XCTest
@testable import PlayerApp

final class LibraryScanImportTests: XCTestCase {
    func testMapperPersistsMetadataReplayGainAndSourceIdentity() throws {
        let sourceRoot = Self.sourceRoot()
        let scannedFile = ScannedAudioFile(
            url: URL(fileURLWithPath: "/music/Albums/Kind of Blue/01 So What.flac"),
            relativePath: "Albums/Kind of Blue/01 So What.flac",
            fileName: "01 So What.flac",
            fileExtension: "flac"
        )
        let metadata = Self.metadata()

        let track = ScannedTrackRecordMapper.makeTrack(
            sourceRoot: sourceRoot,
            scannedFile: scannedFile,
            metadata: metadata
        )

        XCTAssertEqual(track.id, "file:source-1:Albums/Kind of Blue/01 So What.flac")
        XCTAssertEqual(track.sourceRootID, "source-1")
        XCTAssertEqual(track.sourceKind, "securityScopedFolder")
        XCTAssertEqual(track.relativePath, "Albums/Kind of Blue/01 So What.flac")
        XCTAssertEqual(track.fileName, "01 So What.flac")
        XCTAssertEqual(track.containerFormat, "FLAC")
        XCTAssertEqual(track.codec, "FLAC")
        XCTAssertEqual(try XCTUnwrap(track.sampleRate), 96_000)
        XCTAssertEqual(track.bitDepth, 24)
        XCTAssertEqual(track.channelCount, 2)
        XCTAssertEqual(try XCTUnwrap(track.duration), 545)
        XCTAssertEqual(track.isLossless, true)
        XCTAssertEqual(track.isDSD, false)
        XCTAssertEqual(track.title, "So What")
        XCTAssertEqual(track.album, "Kind of Blue")
        XCTAssertEqual(track.albumArtist, "Miles Davis")
        XCTAssertEqual(track.artist, "Miles Davis Quintet")
        XCTAssertEqual(track.genre, "Jazz")
        XCTAssertEqual(track.trackNumber, 1)
        XCTAssertEqual(track.trackTotal, 5)
        XCTAssertEqual(track.rawTagsJSON, "{\"replaygain\":true}")
        XCTAssertEqual(try XCTUnwrap(track.replayGainTrackGain), -7.23)
        XCTAssertEqual(try XCTUnwrap(track.replayGainAlbumGain), -6.10)
        XCTAssertEqual(try XCTUnwrap(track.replayGainTrackPeak), 0.987654)
        XCTAssertEqual(try XCTUnwrap(track.replayGainAlbumPeak), 1.125)
    }

    func testImporterWritesReadableTracksAndIndexesSuccessfulImports() async throws {
        let sourceRoot = Self.sourceRoot()
        let readableURL = URL(fileURLWithPath: "/music/readable.flac")
        let brokenURL = URL(fileURLWithPath: "/music/broken.flac")
        let repository = FakeTrackRepository()
        let spotlightIndexer = FakeLibraryTrackSearchIndexer()
        let importer = LibraryScanImporter(
            scanner: FakeLibraryScanner(files: [
                ScannedAudioFile(
                    url: readableURL,
                    relativePath: "readable.flac",
                    fileName: "readable.flac",
                    fileExtension: "flac"
                ),
                ScannedAudioFile(
                    url: brokenURL,
                    relativePath: "broken.flac",
                    fileName: "broken.flac",
                    fileExtension: "flac"
                )
            ]),
            metadataReader: FakeMetadataReader(results: [
                readableURL: .success(Self.metadata()),
                brokenURL: .failure(TestError.metadataFailed)
            ]),
            trackRepository: repository,
            spotlightIndexer: spotlightIndexer
        )

        let summary = try await importer.importSource(
            sourceRoot,
            rootURL: URL(fileURLWithPath: "/music")
        )

        XCTAssertEqual(summary.scannedFileCount, 2)
        XCTAssertEqual(summary.importedTrackCount, 1)
        XCTAssertEqual(summary.failedMetadataCount, 1)
        XCTAssertEqual(repository.tracks.map(\.id), ["file:source-1:readable.flac"])
        XCTAssertEqual(spotlightIndexer.indexedTracks.map(\.id), ["file:source-1:readable.flac"])
    }

    @MainActor
    func testSourcesViewModelUsesScanImporterWhenAvailable() async {
        let sourceRoot = Self.sourceRoot()
        let viewModel = SourcesViewModel(
            access: FakeSourceRootAccess(resource: SecurityScopedResource(
                url: URL(fileURLWithPath: "/music"),
                didStartAccessing: false
            )),
            libraryScanImporter: FakeLibraryScanImporter(summary: LibraryScanImportSummary(
                sourceRootID: sourceRoot.id,
                scannedFileCount: 3,
                importedTrackCount: 2,
                failedMetadataCount: 1
            ))
        )

        await viewModel.rescan(sourceRoot)

        XCTAssertEqual(
            viewModel.statusMessage,
            "Imported 2 of 3 audio files from Music. Failed metadata for 1."
        )
    }

    fileprivate static func sourceRoot() -> SourceRootRecord {
        SourceRootRecord(
            id: "source-1",
            kind: "securityScopedFolder",
            displayName: "Music",
            bookmarkData: nil,
            baseURL: nil,
            isEnabled: true,
            lastScanDate: nil
        )
    }

    fileprivate static func metadata() -> AudioFileMetadata {
        AudioFileMetadata(
            fileName: "01 So What.flac",
            containerFormat: "FLAC",
            codec: "FLAC",
            duration: 545,
            sampleRate: 96_000,
            bitDepth: 24,
            channelCount: 2,
            tags: AudioMetadataTags(
                title: "So What",
                album: "Kind of Blue",
                albumArtist: "Miles Davis",
                artist: "Miles Davis Quintet",
                composer: nil,
                genre: "Jazz",
                year: 1959,
                discNumber: nil,
                discTotal: nil,
                trackNumber: 1,
                trackTotal: 5,
                replayGainTrackGain: -7.23,
                replayGainAlbumGain: -6.10,
                replayGainTrackPeak: 0.987654,
                replayGainAlbumPeak: 1.125
            ),
            artwork: nil,
            rawTagsJSON: "{\"replaygain\":true}"
        )
    }
}

private enum TestError: Error {
    case metadataFailed
}

private actor FakeLibraryScanner: LibraryScanning {
    private let files: [ScannedAudioFile]

    init(files: [ScannedAudioFile]) {
        self.files = files
    }

    func scan(rootURL: URL) async throws -> [ScannedAudioFile] {
        files
    }
}

private struct FakeMetadataReader: MetadataReading {
    var results: [URL: Result<AudioFileMetadata, Error>]

    func readMetadata(from url: URL) async throws -> AudioFileMetadata {
        try results[url]?.get() ?? LibraryScanImportTests.metadata()
    }
}

private final class FakeTrackRepository: TrackRepository, @unchecked Sendable {
    private(set) var tracks: [TrackRecord] = []

    func upsertTracks(_ tracks: [TrackRecord]) throws {
        self.tracks = tracks
    }
}

private final class FakeLibraryTrackSearchIndexer: LibraryTrackSearchIndexing, @unchecked Sendable {
    private(set) var indexedTracks: [TrackRecord] = []

    func indexTracks(_ tracks: [TrackRecord]) async throws {
        indexedTracks = tracks
    }
}

private struct FakeLibraryScanImporter: LibraryScanImporting {
    var summary: LibraryScanImportSummary

    func importSource(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL
    ) async throws -> LibraryScanImportSummary {
        summary
    }
}

private struct FakeSourceRootAccess: SourceRootAccessing, @unchecked Sendable {
    var resource: SecurityScopedResource

    func makeSecurityScopedSource(from url: URL) throws -> SourceRootRecord {
        LibraryScanImportTests.sourceRoot()
    }

    func resolve(_ sourceRoot: SourceRootRecord) throws -> SecurityScopedResource {
        resource
    }
}
