import Foundation

struct DependencyContainer: Sendable {
    private let repository: GRDBTrackRepository?
    private let queueRestorer: (any PlaybackQueueRestoring)?
    private let equalizerService: EqualizerService?
    private let equalizerRepository: (any EQPresetRepository)?
    private let equalizerRuntime: EqualizerRuntimeController?
    private let audioDiagnosticsProvider: (any AudioRouteDiagnosticsProviding)?
    let artworkLoader: (any ArtworkThumbnailLoading)?
    let playbackCoordinator: PlaybackCoordinator

    init(
        repository: GRDBTrackRepository? = nil,
        playbackCoordinator: PlaybackCoordinator = PlaybackCoordinator(),
        queueRestorer: (any PlaybackQueueRestoring)? = nil,
        equalizerService: EqualizerService? = nil,
        equalizerRepository: (any EQPresetRepository)? = nil,
        equalizerRuntime: EqualizerRuntimeController? = nil,
        audioDiagnosticsProvider: (any AudioRouteDiagnosticsProviding)? = nil,
        artworkLoader: (any ArtworkThumbnailLoading)? = nil
    ) {
        self.repository = repository
        self.playbackCoordinator = playbackCoordinator
        self.queueRestorer = queueRestorer
        self.equalizerService = equalizerService
        self.equalizerRepository = equalizerRepository
        self.equalizerRuntime = equalizerRuntime
        self.audioDiagnosticsProvider = audioDiagnosticsProvider
        self.artworkLoader = artworkLoader
    }

    static func bootstrap(fileManager: FileManager = .default) throws -> DependencyContainer {
        try bootstrap(
            databasePath: databasePath(fileManager: fileManager),
            databaseOpener: LivePlayerDatabaseOpener()
        )
    }

    static func bootstrap(
        databasePath: String,
        databaseOpener: any PlayerDatabaseOpening
    ) throws -> DependencyContainer {
        let database = try databaseOpener.open(at: databasePath)
        let repository = GRDBTrackRepository(database: database)
        if try repository.fetchSourceRoot(id: "app-documents") == nil,
           let documentsURL = try? PlaybackLocatorResolver.defaultAppFilesRoot() {
            try repository.upsertSourceRoots([SourceRootRecord(
                id: "app-documents",
                kind: "appDocuments",
                displayName: "App Documents",
                bookmarkData: nil,
                baseURL: documentsURL.absoluteString,
                isEnabled: true,
                lastScanDate: nil
            )])
        }
        let queueRepository = GRDBQueueRepository(database: database)
        let locatorResolver = PlaybackLocatorResolver(sourceRootRepository: repository)
        let audioSessionController = AudioSessionController()
        let playbackEngine = PlaybackEngine(session: audioSessionController)
        let equalizerService = EqualizerService(applicator: playbackEngine)
        let equalizerRepository = GRDBEQPresetRepository(database: database)
        let equalizerRuntime = EqualizerRuntimeController(
            service: equalizerService,
            repository: equalizerRepository,
            routeProvider: playbackEngine
        )
        let artworkLoader = ArtworkThumbnailLoader(repository: repository)
        return DependencyContainer(
            repository: repository,
            playbackCoordinator: PlaybackCoordinator(
                playback: playbackEngine,
                queuePersistence: queueRepository,
                equalizerService: equalizerService
            ),
            queueRestorer: LibraryPlaybackQueueRestorer(
                queueRepository: queueRepository,
                trackRepository: repository,
                locatorResolver: locatorResolver
            ),
            equalizerService: equalizerService,
            equalizerRepository: equalizerRepository,
            equalizerRuntime: equalizerRuntime,
            audioDiagnosticsProvider: playbackEngine,
            artworkLoader: artworkLoader
        )
    }

    @MainActor
    func makeLibraryViewModel() -> LibraryViewModel {
        guard let repository else {
            return LibraryViewModel()
        }

        return LibraryViewModel(
            searchRepository: repository,
            playbackStarter: LibraryTrackPlaybackCoordinator(
                locatorResolver: PlaybackLocatorResolver(
                    sourceRootRepository: repository
                ),
                playback: playbackCoordinator
            ),
            artworkLoader: artworkLoader,
            playbackCoordinator: playbackCoordinator
        )
    }

    @MainActor
    func makePlaybackStore() -> PlaybackStore {
        PlaybackStore(
            coordinator: playbackCoordinator,
            nowPlayingUpdater: NowPlayingController(
                artworkLoader: repository.map { RepositoryNowPlayingArtworkLoader(repository: $0) }
            ),
            remoteCommandController: RemoteCommandController(),
            queueRestorer: queueRestorer,
            equalizerRuntime: equalizerRuntime,
            diagnosticsProvider: audioDiagnosticsProvider
        )
    }

    @MainActor
    func makeEqualizerViewModel() -> EqualizerViewModel {
        EqualizerViewModel(
            equalizerService: equalizerService,
            repository: equalizerRepository,
            routeProvider: audioDiagnosticsProvider ?? AudioSessionController(),
            spectrumController: audioDiagnosticsProvider as? any SpectrumAnalysisControlling
        )
    }

    @MainActor
    func makeOutputRouteViewModel() -> OutputRouteViewModel {
        OutputRouteViewModel(
            diagnosticsProvider: audioDiagnosticsProvider ?? AudioSessionController(),
            equalizerService: equalizerService
        )
    }

    @MainActor
    func makeSettingsView(
        openSources: @escaping @MainActor () -> Void = {}
    ) -> SettingsView {
        SettingsView(
            repository: equalizerRepository,
            diagnosticsProvider: audioDiagnosticsProvider ?? AudioSessionController(),
            openSources: openSources
        )
    }

    @MainActor
    func makeSourcesViewModel() -> SourcesViewModel {
        guard let repository else {
            return SourcesViewModel()
        }

        let spotlightIndexer = LibrarySpotlightIndexer()
        return SourcesViewModel(
            repository: repository,
            musicLibraryImporter: MusicLibraryImporter(
                sourceRootRepository: repository,
                trackRepository: repository,
                spotlightIndexer: spotlightIndexer
            ),
            libraryScanImporter: LibraryScanImporter(
                trackRepository: repository,
                spotlightIndexer: spotlightIndexer
            ),
            musicLibraryChangeObserver: MediaPlayerMusicLibraryChangeObserver(),
            spotlightIndexer: spotlightIndexer
        )
    }

    static func databasePath(fileManager: FileManager) throws -> String {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDirectory = directory.appendingPathComponent("Metronome", isDirectory: true)
        try fileManager.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )

        return appDirectory
            .appendingPathComponent("Library.sqlite")
            .path
    }
}

protocol PlayerDatabaseOpening: Sendable {
    func open(at path: String) throws -> PlayerDatabase
}

private struct LivePlayerDatabaseOpener: PlayerDatabaseOpening {
    func open(at path: String) throws -> PlayerDatabase {
        try PlayerDatabase.open(at: path)
    }
}

private actor RepositoryNowPlayingArtworkLoader: NowPlayingArtworkLoading {
    private let repository: any ArtworkRepository

    init(repository: any ArtworkRepository) {
        self.repository = repository
    }

    func artworkData(id: String) async -> Data? {
        try? repository.fetchArtwork(id: id)?.data
    }
}
