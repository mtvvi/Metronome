import SwiftUI

struct RootView: View {
    let container: DependencyContainer

    var body: some View {
        NavigationStack {
            SourcesView()
        }
    }
}
