import Combine
import Foundation

protocol DependencyContainerBootstrapping: Sendable {
    func bootstrap() async -> Result<DependencyContainer, AppError>
}

protocol LibraryDatabaseResetting: Sendable {
    func resetLibraryDatabase() async throws
}

actor LiveDependencyContainerBootstrapper: DependencyContainerBootstrapping {
    func bootstrap() async -> Result<DependencyContainer, AppError> {
        do {
            return .success(try DependencyContainer.bootstrap())
        } catch {
            return .failure(
                .databaseBootstrapFailed(diagnostic: String(describing: error))
            )
        }
    }
}

actor LiveLibraryDatabaseResetter: LibraryDatabaseResetting {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resetLibraryDatabase() async throws {
        let path = try DependencyContainer.databasePath(fileManager: fileManager)
        for suffix in ["", "-wal", "-shm"] {
            let candidate = path + suffix
            if fileManager.fileExists(atPath: candidate) {
                try fileManager.removeItem(atPath: candidate)
            }
        }
    }
}

@MainActor
final class AppBootstrapStore: ObservableObject {
    @Published private(set) var state: LoadableState<DependencyContainer> = .idle

    private let bootstrapper: any DependencyContainerBootstrapping
    private let databaseResetter: any LibraryDatabaseResetting
    private var resetDatabaseBeforeFirstLoad: Bool

    init(
        bootstrapper: any DependencyContainerBootstrapping = LiveDependencyContainerBootstrapper(),
        databaseResetter: any LibraryDatabaseResetting = LiveLibraryDatabaseResetter(),
        resetDatabaseBeforeFirstLoad: Bool = false
    ) {
        self.bootstrapper = bootstrapper
        self.databaseResetter = databaseResetter
        self.resetDatabaseBeforeFirstLoad = resetDatabaseBeforeFirstLoad
    }

    var container: DependencyContainer? {
        state.currentValue
    }

    var error: AppError? {
        state.error
    }

    var isLoading: Bool {
        state.isLoading
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        if resetDatabaseBeforeFirstLoad {
            resetDatabaseBeforeFirstLoad = false
            do {
                try await databaseResetter.resetLibraryDatabase()
            } catch {
                state = .failed(
                    .databaseBootstrapFailed(diagnostic: "UI test reset failed: \(error)"),
                    previous: nil
                )
                return
            }
        }
        await load()
    }

    func retry() async {
        await load()
    }

    func resetLibrary() async {
        let activeContainer = container
        state = .loading(previous: nil)
        do {
            await activeContainer?.playbackCoordinator.shutdown()
            try await databaseResetter.resetLibraryDatabase()
            await load()
        } catch {
            state = .failed(
                .databaseBootstrapFailed(diagnostic: "Database reset failed: \(error)"),
                previous: nil
            )
        }
    }

    func shutdown() async {
        await container?.playbackCoordinator.shutdown()
    }

    private func load() async {
        state = .loading(previous: container)

        switch await bootstrapper.bootstrap() {
        case .success(let container):
            state = .loaded(container)
        case .failure(let error):
            state = .failed(error, previous: container)
        }
    }
}
