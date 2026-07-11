import Foundation
import CryptoKit

struct LibraryScanImportSummary: Equatable, Sendable {
    var sourceRootID: String
    var scannedFileCount: Int
    var importedTrackCount: Int
    var failedMetadataCount: Int
    var deletedTrackIDs: [String] = []
    var searchIndexWarning = false
}

protocol LibraryScanImporting: Sendable {
    func importSource(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL
    ) async throws -> LibraryScanImportSummary
}

protocol ProgressReportingLibraryScanImporting: LibraryScanImporting {
    func importSource(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL,
        progress: @escaping @Sendable (ScanProgress.Phase, Int, Int?) async -> Void
    ) async throws -> LibraryScanImportSummary

    func startImport(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL,
        scanID: UUID
    ) -> LibraryScanSession
}

extension ProgressReportingLibraryScanImporting {
    func startImport(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL,
        scanID: UUID = UUID()
    ) -> LibraryScanSession {
        let pair = AsyncStream<ScanProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        pair.continuation.yield(ScanProgress(
            scanID: scanID,
            sourceRootID: sourceRoot.id,
            phase: .enumerating,
            completedCount: 0,
            totalCount: nil
        ))
        let resultTask = Task {
            do {
                let summary = try await importSource(
                    sourceRoot,
                    rootURL: rootURL
                ) { phase, completedCount, totalCount in
                    pair.continuation.yield(ScanProgress(
                        scanID: scanID,
                        sourceRootID: sourceRoot.id,
                        phase: phase,
                        completedCount: completedCount,
                        totalCount: totalCount
                    ))
                }
                pair.continuation.yield(ScanProgress(
                    scanID: scanID,
                    sourceRootID: sourceRoot.id,
                    phase: .completed,
                    completedCount: summary.importedTrackCount,
                    totalCount: summary.scannedFileCount
                ))
                pair.continuation.finish()
                return summary
            } catch is CancellationError {
                pair.continuation.yield(ScanProgress(
                    scanID: scanID,
                    sourceRootID: sourceRoot.id,
                    phase: .cancelled,
                    completedCount: 0,
                    totalCount: nil
                ))
                pair.continuation.finish()
                throw CancellationError()
            } catch {
                pair.continuation.yield(ScanProgress(
                    scanID: scanID,
                    sourceRootID: sourceRoot.id,
                    phase: .failed(String(describing: error)),
                    completedCount: 0,
                    totalCount: nil
                ))
                pair.continuation.finish()
                throw error
            }
        }
        return LibraryScanSession(
            scanID: scanID,
            progress: pair.stream,
            resultTask: resultTask
        )
    }
}

struct LibraryScanImporter: ProgressReportingLibraryScanImporting {
    private let scanner: any LibraryScanning
    private let metadataReader: any MetadataReading
    private let trackRepository: any TrackRepository
    private let artworkRepository: (any ArtworkRepository)?
    private let spotlightIndexer: (any LibraryTrackSearchIndexing)?

    init(
        scanner: any LibraryScanning = LibraryScanner(),
        metadataReader: any MetadataReading = SFBAudioMetadataReader(),
        trackRepository: any TrackRepository,
        artworkRepository: (any ArtworkRepository)? = nil,
        spotlightIndexer: (any LibraryTrackSearchIndexing)? = nil
    ) {
        self.scanner = scanner
        self.metadataReader = metadataReader
        self.trackRepository = trackRepository
        self.artworkRepository = artworkRepository ?? (trackRepository as? any ArtworkRepository)
        self.spotlightIndexer = spotlightIndexer
    }

    func importSource(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL
    ) async throws -> LibraryScanImportSummary {
        try await importSource(sourceRoot, rootURL: rootURL) { _, _, _ in }
    }

    func importSource(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL,
        progress: @escaping @Sendable (ScanProgress.Phase, Int, Int?) async -> Void
    ) async throws -> LibraryScanImportSummary {
        try Task.checkCancellation()

        let scannedFiles = try await scanner.scan(rootURL: rootURL)
        await progress(.readingMetadata, 0, scannedFiles.count)
        let scanID = UUID().uuidString
        var tracks: [TrackRecord] = []
        var failedMetadataCount = 0
        var artworkRecords: [ArtworkRecord] = []
        var completedCount = 0

        for chunkStart in stride(from: 0, to: scannedFiles.count, by: 4) {
            try Task.checkCancellation()
            let chunkEnd = min(chunkStart + 4, scannedFiles.count)
            let chunk = scannedFiles[chunkStart..<chunkEnd]
            let results = try await withThrowingTaskGroup(
                of: MetadataScanResult.self
            ) { group in
                for scannedFile in chunk {
                    group.addTask {
                        try await Self.readTrack(
                            sourceRoot: sourceRoot,
                            scannedFile: scannedFile,
                            metadataReader: metadataReader
                        )
                    }
                }
                var values: [MetadataScanResult] = []
                for try await value in group { values.append(value) }
                return values
            }
            for result in results {
                if let track = result.track { tracks.append(track) }
                if let artwork = result.artwork { artworkRecords.append(artwork) }
                if result.didFail { failedMetadataCount += 1 }
            }
            completedCount += results.count
            await progress(.readingMetadata, completedCount, scannedFiles.count)
        }

        tracks.sort {
            ($0.relativePath ?? $0.id).localizedStandardCompare(
                $1.relativePath ?? $1.id
            ) == .orderedAscending
        }

        var uniqueArtworkByID: [String: ArtworkRecord] = [:]
        for artwork in artworkRecords {
            uniqueArtworkByID[artwork.id] = artwork
        }
        try artworkRepository?.upsertArtwork(Array(uniqueArtworkByID.values))
        await progress(.reconciling, tracks.count, scannedFiles.count)
        let reconciliation: SourceReconciliationResult
        if let repository = trackRepository as? any TrackReconciliationRepository {
            reconciliation = try repository.reconcileSource(
                sourceRootID: sourceRoot.id,
                scanID: scanID,
                tracks: tracks
            )
        } else {
            try trackRepository.upsertTracks(tracks)
            reconciliation = SourceReconciliationResult(deletedTrackIDs: [])
        }
        var searchIndexWarning = false
        do {
            try await spotlightIndexer?.indexTracks(tracks)
        } catch {
            searchIndexWarning = true
        }
        if !reconciliation.deletedTrackIDs.isEmpty {
            do {
                try await spotlightIndexer?.deleteTracks(withIDs: reconciliation.deletedTrackIDs)
            } catch {
                searchIndexWarning = true
            }
        }
        if let sourceRepository = trackRepository as? any SourceRootRepository {
            var updatedSource = sourceRoot
            updatedSource.lastScanDate = Date().timeIntervalSince1970
            try sourceRepository.upsertSourceRoots([updatedSource])
        }

        return LibraryScanImportSummary(
            sourceRootID: sourceRoot.id,
            scannedFileCount: scannedFiles.count,
            importedTrackCount: tracks.count,
            failedMetadataCount: failedMetadataCount,
            deletedTrackIDs: reconciliation.deletedTrackIDs,
            searchIndexWarning: searchIndexWarning
        )
    }

    private static func artworkRecord(_ artwork: AudioArtwork) -> ArtworkRecord {
        let digest = SHA256.hash(data: artwork.data).map { String(format: "%02x", $0) }.joined()
        return ArtworkRecord(
            id: digest,
            mimeType: artwork.mimeType ?? "application/octet-stream",
            data: artwork.data,
            width: nil,
            height: nil,
            createdAt: Date().timeIntervalSince1970
        )
    }

    private static func readTrack(
        sourceRoot: SourceRootRecord,
        scannedFile: ScannedAudioFile,
        metadataReader: any MetadataReading
    ) async throws -> MetadataScanResult {
        do {
            let metadata = try await metadataReader.readMetadata(from: scannedFile.url)
            let artwork = metadata.artwork.map(artworkRecord)
            return MetadataScanResult(
                track: ScannedTrackRecordMapper.makeTrack(
                    sourceRoot: sourceRoot,
                    scannedFile: scannedFile,
                    metadata: metadata,
                    artworkID: artwork?.id
                ),
                artwork: artwork,
                didFail: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return MetadataScanResult(track: nil, artwork: nil, didFail: true)
        }
    }
}

private struct MetadataScanResult: Sendable {
    var track: TrackRecord?
    var artwork: ArtworkRecord?
    var didFail: Bool
}

enum ScannedTrackRecordMapper {
    static func makeTrack(
        sourceRoot: SourceRootRecord,
        scannedFile: ScannedAudioFile,
        metadata: AudioFileMetadata,
        artworkID: String? = nil
    ) -> TrackRecord {
        let fileValues = fileResourceValues(for: scannedFile.url)
        let tags = metadata.tags

        return TrackRecord(
            id: trackID(sourceRootID: sourceRoot.id, relativePath: scannedFile.relativePath),
            sourceRootID: sourceRoot.id,
            sourceKind: sourceRoot.kind,
            playbackLocatorKind: sourceRoot.kind == "appDocuments"
                ? PlaybackLocatorKind.appRelativePath.rawValue
                : PlaybackLocatorKind.securityScopedSource.rawValue,
            bookmarkData: nil,
            mediaPersistentID: nil,
            relativePath: scannedFile.relativePath,
            fileName: scannedFile.fileName,
            fileSize: fileValues.fileSize,
            modifiedDate: fileValues.modifiedDate,
            contentHash: nil,
            containerFormat: metadata.containerFormat ?? scannedFile.fileExtension.uppercased(),
            codec: metadata.codec,
            sampleRate: metadata.sampleRate,
            bitDepth: metadata.bitDepth,
            channelCount: metadata.channelCount,
            duration: metadata.duration,
            totalFrames: nil,
            bitrate: nil,
            isLossless: isLossless(containerFormat: metadata.containerFormat, codec: metadata.codec),
            isDSD: isDSD(containerFormat: metadata.containerFormat, codec: metadata.codec),
            dsdRate: nil,
            title: tags.title,
            album: tags.album,
            albumArtist: tags.albumArtist,
            artist: tags.artist,
            composer: tags.composer,
            genre: tags.genre,
            year: tags.year,
            discNumber: tags.discNumber,
            discTotal: tags.discTotal,
            trackNumber: tags.trackNumber,
            trackTotal: tags.trackTotal,
            rawTagsJSON: metadata.rawTagsJSON,
            sortTitle: nil,
            sortAlbum: nil,
            sortArtist: nil,
            musicBrainzID: nil,
            replayGainTrackGain: tags.replayGainTrackGain,
            replayGainAlbumGain: tags.replayGainAlbumGain,
            replayGainTrackPeak: tags.replayGainTrackPeak,
            replayGainAlbumPeak: tags.replayGainAlbumPeak,
            artworkID: artworkID
        )
    }

    static func trackID(sourceRootID: String, relativePath: String) -> String {
        "file:\(sourceRootID):\(relativePath)"
    }

    private static func fileResourceValues(for url: URL) -> (fileSize: Int64?, modifiedDate: Double?) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (
            values?.fileSize.map(Int64.init),
            values?.contentModificationDate?.timeIntervalSince1970
        )
    }

    private static func isLossless(containerFormat: String?, codec: String?) -> Bool {
        let values = normalizedFormatValues(containerFormat: containerFormat, codec: codec)
        return !values.isDisjoint(with: [
            "FLAC",
            "ALAC",
            "WAV",
            "WAVE",
            "AIFF",
            "AIF",
            "DSF",
            "DFF",
            "DSD",
            "WAVPACK",
            "WV",
            "APE",
            "MONKEYSAUDIO",
            "TTA"
        ])
    }

    private static func isDSD(containerFormat: String?, codec: String?) -> Bool {
        let values = normalizedFormatValues(containerFormat: containerFormat, codec: codec)
        return !values.isDisjoint(with: ["DSF", "DFF", "DSD", "DSDIFF"])
    }

    private static func normalizedFormatValues(containerFormat: String?, codec: String?) -> Set<String> {
        Set([containerFormat, codec]
            .compactMap { $0?.uppercased() }
            .map { value in
                value
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "_", with: "")
            })
    }
}
