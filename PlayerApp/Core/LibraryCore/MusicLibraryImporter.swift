import Foundation

enum MusicLibraryAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

protocol MusicLibraryAuthorizationProviding: Sendable {
    var currentStatus: MusicLibraryAuthorizationStatus { get }
    func requestAuthorization() async -> MusicLibraryAuthorizationStatus
}

protocol MusicLibraryQuerying: Sendable {
    func songs() -> [MusicLibraryMediaItem]
}

protocol MusicLibraryImporting: Sendable {
    func importLocalMusicLibrary() async throws -> MusicLibraryImportSummary
}

struct MusicLibraryMediaItem: Equatable, Sendable {
    var persistentID: Int64
    var assetURL: URL?
    var hasProtectedAsset: Bool
    var title: String?
    var albumTitle: String?
    var albumArtist: String?
    var artist: String?
    var composer: String?
    var genre: String?
    var releaseYear: Int?
    var discNumber: Int?
    var trackNumber: Int?
    var duration: TimeInterval?

    init(
        persistentID: Int64,
        assetURL: URL?,
        hasProtectedAsset: Bool,
        title: String? = nil,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        artist: String? = nil,
        composer: String? = nil,
        genre: String? = nil,
        releaseYear: Int? = nil,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        self.persistentID = persistentID
        self.assetURL = assetURL
        self.hasProtectedAsset = hasProtectedAsset
        self.title = title
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.artist = artist
        self.composer = composer
        self.genre = genre
        self.releaseYear = releaseYear
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.duration = duration
    }
}

struct MusicLibraryImportSummary: Equatable, Sendable {
    var authorizationStatus: MusicLibraryAuthorizationStatus
    var importedCount: Int
    var protectedSkippedCount: Int
    var unavailableSkippedCount: Int
}

struct MusicLibraryImporter: MusicLibraryImporting {
    static let sourceRootID = "music-library"
    static let sourceKind = "musicLibrary"

    private let authorization: any MusicLibraryAuthorizationProviding
    private let query: any MusicLibraryQuerying
    private let sourceRootRepository: any SourceRootRepository
    private let trackRepository: any TrackRepository

    init(
        authorization: any MusicLibraryAuthorizationProviding = MediaPlayerMusicLibraryClient(),
        query: any MusicLibraryQuerying = MediaPlayerMusicLibraryClient(),
        sourceRootRepository: any SourceRootRepository,
        trackRepository: any TrackRepository
    ) {
        self.authorization = authorization
        self.query = query
        self.sourceRootRepository = sourceRootRepository
        self.trackRepository = trackRepository
    }

    func importLocalMusicLibrary() async throws -> MusicLibraryImportSummary {
        let authorizationStatus = await resolvedAuthorizationStatus()

        guard authorizationStatus == .authorized else {
            return MusicLibraryImportSummary(
                authorizationStatus: authorizationStatus,
                importedCount: 0,
                protectedSkippedCount: 0,
                unavailableSkippedCount: 0
            )
        }

        var protectedSkippedCount = 0
        var unavailableSkippedCount = 0
        var importedTracks: [TrackRecord] = []

        for item in query.songs() {
            guard !item.hasProtectedAsset else {
                protectedSkippedCount += 1
                continue
            }

            guard let assetURL = item.assetURL else {
                unavailableSkippedCount += 1
                continue
            }

            importedTracks.append(trackRecord(from: item, assetURL: assetURL))
        }

        try sourceRootRepository.upsertSourceRoots([Self.musicLibrarySourceRoot()])
        try trackRepository.upsertTracks(importedTracks)

        return MusicLibraryImportSummary(
            authorizationStatus: authorizationStatus,
            importedCount: importedTracks.count,
            protectedSkippedCount: protectedSkippedCount,
            unavailableSkippedCount: unavailableSkippedCount
        )
    }

    private func resolvedAuthorizationStatus() async -> MusicLibraryAuthorizationStatus {
        switch authorization.currentStatus {
        case .notDetermined:
            return await authorization.requestAuthorization()
        case .denied, .restricted, .authorized:
            return authorization.currentStatus
        }
    }

    private static func musicLibrarySourceRoot() -> SourceRootRecord {
        SourceRootRecord(
            id: sourceRootID,
            kind: sourceKind,
            displayName: "Music Library",
            bookmarkData: nil,
            baseURL: nil,
            isEnabled: true,
            lastScanDate: Date().timeIntervalSince1970
        )
    }

    private func trackRecord(
        from item: MusicLibraryMediaItem,
        assetURL: URL
    ) -> TrackRecord {
        TrackRecord(
            id: "\(Self.sourceRootID)-\(item.persistentID)",
            sourceRootID: Self.sourceRootID,
            sourceKind: Self.sourceKind,
            bookmarkData: nil,
            mediaPersistentID: item.persistentID,
            relativePath: nil,
            fileName: fileName(for: assetURL, fallbackTitle: item.title),
            fileSize: nil,
            modifiedDate: nil,
            contentHash: nil,
            containerFormat: containerFormat(for: assetURL),
            codec: nil,
            sampleRate: nil,
            bitDepth: nil,
            channelCount: nil,
            duration: item.duration,
            totalFrames: nil,
            bitrate: nil,
            isLossless: false,
            isDSD: false,
            dsdRate: nil,
            title: item.title,
            album: item.albumTitle,
            albumArtist: item.albumArtist,
            artist: item.artist,
            composer: item.composer,
            genre: item.genre,
            year: item.releaseYear,
            discNumber: item.discNumber,
            discTotal: nil,
            trackNumber: item.trackNumber,
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

    private func fileName(for assetURL: URL, fallbackTitle: String?) -> String {
        let fileName = assetURL.lastPathComponent
        if !fileName.isEmpty {
            return fileName
        }

        return fallbackTitle ?? "Music Library Item"
    }

    private func containerFormat(for assetURL: URL) -> String? {
        let pathExtension = assetURL.pathExtension
        return pathExtension.isEmpty ? nil : pathExtension.uppercased()
    }
}
