import Foundation

struct DependencyContainer: Sendable {
    private let repository: GRDBTrackRepository?

    init(repository: GRDBTrackRepository? = nil) {
        self.repository = repository
    }

    static func bootstrap(fileManager: FileManager = .default) -> DependencyContainer {
        do {
            let database = try PlayerDatabase.open(at: databasePath(fileManager: fileManager))
            return DependencyContainer(repository: GRDBTrackRepository(database: database))
        } catch {
            return DependencyContainer()
        }
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
            )
        )
    }

    private static func databasePath(fileManager: FileManager) throws -> String {
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
