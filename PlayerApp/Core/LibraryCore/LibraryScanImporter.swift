import Foundation

struct LibraryScanImportSummary: Equatable, Sendable {
    var sourceRootID: String
    var scannedFileCount: Int
    var importedTrackCount: Int
    var failedMetadataCount: Int
}

protocol LibraryScanImporting: Sendable {
    func importSource(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL
    ) async throws -> LibraryScanImportSummary
}

struct LibraryScanImporter: LibraryScanImporting {
    private let scanner: any LibraryScanning
    private let metadataReader: any MetadataReading
    private let trackRepository: any TrackRepository
    private let spotlightIndexer: (any LibraryTrackSearchIndexing)?

    init(
        scanner: any LibraryScanning = LibraryScanner(),
        metadataReader: any MetadataReading = SFBAudioMetadataReader(),
        trackRepository: any TrackRepository,
        spotlightIndexer: (any LibraryTrackSearchIndexing)? = nil
    ) {
        self.scanner = scanner
        self.metadataReader = metadataReader
        self.trackRepository = trackRepository
        self.spotlightIndexer = spotlightIndexer
    }

    func importSource(
        _ sourceRoot: SourceRootRecord,
        rootURL: URL
    ) async throws -> LibraryScanImportSummary {
        try Task.checkCancellation()

        let scannedFiles = try await scanner.scan(rootURL: rootURL)
        var tracks: [TrackRecord] = []
        var failedMetadataCount = 0

        for scannedFile in scannedFiles {
            try Task.checkCancellation()

            do {
                let metadata = try await metadataReader.readMetadata(from: scannedFile.url)
                tracks.append(ScannedTrackRecordMapper.makeTrack(
                    sourceRoot: sourceRoot,
                    scannedFile: scannedFile,
                    metadata: metadata
                ))
            } catch {
                if error is CancellationError {
                    throw error
                }

                failedMetadataCount += 1
            }
        }

        try trackRepository.upsertTracks(tracks)
        try? await spotlightIndexer?.indexTracks(tracks)

        return LibraryScanImportSummary(
            sourceRootID: sourceRoot.id,
            scannedFileCount: scannedFiles.count,
            importedTrackCount: tracks.count,
            failedMetadataCount: failedMetadataCount
        )
    }
}

enum ScannedTrackRecordMapper {
    static func makeTrack(
        sourceRoot: SourceRootRecord,
        scannedFile: ScannedAudioFile,
        metadata: AudioFileMetadata
    ) -> TrackRecord {
        let fileValues = fileResourceValues(for: scannedFile.url)
        let tags = metadata.tags

        return TrackRecord(
            id: trackID(sourceRootID: sourceRoot.id, relativePath: scannedFile.relativePath),
            sourceRootID: sourceRoot.id,
            sourceKind: sourceRoot.kind,
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
            artworkID: nil
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
