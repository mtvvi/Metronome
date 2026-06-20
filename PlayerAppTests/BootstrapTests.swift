import XCTest
@testable import PlayerApp

final class BootstrapTests: XCTestCase {
    func testDependencyContainerBootstraps() {
        let container = DependencyContainer.bootstrap()

        XCTAssertNotNil(Optional(container))
    }
}
