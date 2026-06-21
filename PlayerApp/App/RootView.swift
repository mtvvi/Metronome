import SwiftUI

struct RootView: View {
    let container: DependencyContainer
    @State private var selectedTab: AppTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView(viewModel: container.makeLibraryViewModel())
            }
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }
            .tag(AppTab.library)

            NavigationStack {
                SourcesView(viewModel: container.makeSourcesViewModel())
            }
            .tabItem {
                Label("Sources", systemImage: "externaldrive")
            }
            .tag(AppTab.sources)

            NavigationStack {
                EqualizerView()
            }
            .tabItem {
                Label("EQ", systemImage: "slider.horizontal.3")
            }
            .tag(AppTab.equalizer)

            NavigationStack {
                OutputRouteView()
            }
            .tabItem {
                Label("Output", systemImage: "airplayaudio")
            }
            .tag(AppTab.output)
        }
    }
}

private enum AppTab: Hashable {
    case library
    case sources
    case equalizer
    case output
}
