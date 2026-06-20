import SwiftUI

struct RootView: View {
    let container: DependencyContainer
    @State private var selectedTab: AppTab = .sources

    var body: some View {
        TabView(selection: $selectedTab) {
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
    case sources
    case equalizer
    case output
}
