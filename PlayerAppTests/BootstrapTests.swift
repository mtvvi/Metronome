import XCTest
@testable import PlayerApp

final class BootstrapTests: XCTestCase {
    func testDependencyContainerBootstraps() {
        let container = DependencyContainer.bootstrap()

        XCTAssertNotNil(Optional(container))
    }

    @MainActor
    func testDependencyContainerBuildsSourcesViewModelWithMusicImportAvailable() {
        let database = try? PlayerDatabase.inMemory()
        let repository = database.map(GRDBTrackRepository.init(database:))
        let container = DependencyContainer(repository: repository)

        let viewModel = container.makeSourcesViewModel()

        XCTAssertEqual(viewModel.canImportMusicLibrary, repository != nil)
    }
}
