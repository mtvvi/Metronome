import SwiftUI

@main
struct PlayerAppApp: App {
    private let container = DependencyContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
