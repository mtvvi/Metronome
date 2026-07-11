import XCTest
@testable import PlayerApp

final class LibraryScanImportTests: XCTestCase {
    func testScanProgressTreatsReconciliationAsCancellableWork() {
        XCTAssertTrue(ScanProgress.Phase.enumerating.isRunning)
        XCTAssertTrue(ScanProgress.Phase.readingMetadata.isRunning)
        XCTAssertTrue(ScanProgress.Phase.reconciling.isRunning)
        XCTAssertFalse(ScanProgress.Phase.completed.isRunning)
        XCTAssertFalse(ScanProgress.Phase.cancelled.isRunning)
    }

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
        XCTAssertNotNil(try repository.fetchSourceRoot(id: sourceRoot.id)?.lastScanDate)
    }

    func testScanSessionPublishesProgressStreamAndCompletion() async throws {
        let sourceRoot = Self.sourceRoot()
        let fileURL = URL(fileURLWithPath: "/music/readable.flac")
        let importer = LibraryScanImporter(
            scanner: FakeLibraryScanner(files: [
                ScannedAudioFile(
                    url: fileURL,
                    relativePath: "readable.flac",
                    fileName: "readable.flac",
                    fileExtension: "flac"
                )
            ]),
            metadataReader: FakeMetadataReader(results: [
                fileURL: .success(Self.metadata())
            ]),
            trackRepository: FakeTrackRepository()
        )

        let session = importer.startImport(
            sourceRoot,
            rootURL: URL(fileURLWithPath: "/music")
        )
        var progress: [ScanProgress] = []
        for await update in session.progress {
            progress.append(update)
        }
        let summary = try await session.value

        XCTAssertEqual(progress.first?.phase, .enumerating)
        XCTAssertTrue(progress.contains { $0.phase == .readingMetadata })
        XCTAssertTrue(progress.contains { $0.phase == .reconciling })
        XCTAssertEqual(progress.last?.phase, .completed)
        XCTAssertTrue(progress.allSatisfy { $0.scanID == session.scanID })
        XCTAssertTrue(progress.allSatisfy { $0.sourceRootID == sourceRoot.id })
        XCTAssertEqual(summary.importedTrackCount, 1)
    }

    func testCancellingScanSessionPublishesCancelledTerminalProgress() async {
        let sourceRoot = Self.sourceRoot()
        let importer = LibraryScanImporter(
            scanner: BlockingLibraryScanner(),
            metadataReader: FakeMetadataReader(results: [:]),
            trackRepository: FakeTrackRepository()
        )
        let session = importer.startImport(
            sourceRoot,
            rootURL: URL(fileURLWithPath: "/music")
        )
        var iterator = session.progress.makeAsyncIterator()

        let first = await iterator.next()
        session.cancel()
        do {
            _ = try await session.value
            XCTFail("Expected the scan session to be cancelled.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
        var terminal = first
        while let progress = await iterator.next() {
            terminal = progress
        }

        XCTAssertEqual(first?.phase, .enumerating)
        XCTAssertEqual(terminal?.phase, .cancelled)
    }

    func testImporterDeduplicatesIdenticalArtworkBeforePersistence() async throws {
        let artwork = AudioArtwork(data: Data([1, 2, 3]), mimeType: "image/png")
        var metadata = Self.metadata()
        metadata.artwork = artwork
        let firstURL = URL(fileURLWithPath: "/music/first.flac")
        let secondURL = URL(fileURLWithPath: "/music/second.flac")
        let artworkRepository = FakeArtworkRepository()
        let importer = LibraryScanImporter(
            scanner: FakeLibraryScanner(files: [
                ScannedAudioFile(url: firstURL, relativePath: "first.flac", fileName: "first.flac", fileExtension: "flac"),
                ScannedAudioFile(url: secondURL, relativePath: "second.flac", fileName: "second.flac", fileExtension: "flac")
            ]),
            metadataReader: FakeMetadataReader(results: [
                firstURL: .success(metadata),
                secondURL: .success(metadata)
            ]),
            trackRepository: FakeTrackRepository(),
            artworkRepository: artworkRepository
        )

        _ = try await importer.importSource(Self.sourceRoot(), rootURL: URL(fileURLWithPath: "/music"))

        XCTAssertEqual(artworkRepository.records.count, 1)
        XCTAssertEqual(artworkRepository.records.first?.data, artwork.data)
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

private actor BlockingLibraryScanner: LibraryScanning {
    func scan(rootURL: URL) async throws -> [ScannedAudioFile] {
        try await Task.sleep(for: .seconds(60))
        return []
    }
}

private struct FakeMetadataReader: MetadataReading {
    var results: [URL: Result<AudioFileMetadata, Error>]

    func readMetadata(from url: URL) async throws -> AudioFileMetadata {
        try results[url]?.get() ?? LibraryScanImportTests.metadata()
    }
}

private final class FakeTrackRepository: TrackRepository, SourceRootRepository, @unchecked Sendable {
    private(set) var tracks: [TrackRecord] = []
    private var sourceRoots: [String: SourceRootRecord] = [:]

    func upsertTracks(_ tracks: [TrackRecord]) throws {
        self.tracks = tracks
    }

    func fetchSourceRoot(id: String) throws -> SourceRootRecord? {
        sourceRoots[id]
    }

    func fetchSourceRoots() throws -> [SourceRootRecord] {
        Array(sourceRoots.values)
    }

    func upsertSourceRoots(_ sourceRoots: [SourceRootRecord]) throws {
        for sourceRoot in sourceRoots {
            self.sourceRoots[sourceRoot.id] = sourceRoot
        }
    }
}

private final class FakeArtworkRepository: ArtworkRepository, @unchecked Sendable {
    private(set) var records: [ArtworkRecord] = []

    func upsertArtwork(_ artworkRecords: [ArtworkRecord]) throws {
        records = artworkRecords
    }

    func fetchArtwork(id: String) throws -> ArtworkRecord? {
        records.first { $0.id == id }
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
