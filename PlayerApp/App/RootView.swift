import SwiftUI

@MainActor
struct RootView: View {
    let container: DependencyContainer
    @StateObject private var playbackStore: PlaybackStore
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var sourcesViewModel: SourcesViewModel
    @StateObject private var equalizerViewModel: EqualizerViewModel
    @StateObject private var outputViewModel: OutputRouteViewModel
    @State private var selectedTab: AppTab = .library
    @State private var isNowPlayingPresented = false

    init(container: DependencyContainer) {
        self.container = container
        _playbackStore = StateObject(wrappedValue: container.makePlaybackStore())
        _libraryViewModel = StateObject(wrappedValue: container.makeLibraryViewModel())
        _sourcesViewModel = StateObject(wrappedValue: container.makeSourcesViewModel())
        _equalizerViewModel = StateObject(wrappedValue: container.makeEqualizerViewModel())
        _outputViewModel = StateObject(wrappedValue: container.makeOutputRouteViewModel())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView(viewModel: libraryViewModel)
            }
            .tabItem {
                Label("Library", systemImage: "music.note.list")
            }
            .tag(AppTab.library)

            NavigationStack {
                SourcesView(viewModel: sourcesViewModel)
            }
            .tabItem {
                Label("Sources", systemImage: "externaldrive")
            }
            .tag(AppTab.sources)

            NavigationStack {
                EqualizerView(viewModel: equalizerViewModel)
            }
            .tabItem {
                Label("EQ", systemImage: "slider.horizontal.3")
            }
            .tag(AppTab.equalizer)

            NavigationStack {
                OutputRouteView(viewModel: outputViewModel)
            }
            .tabItem {
                Label("Output", systemImage: "airplayaudio")
            }
            .tag(AppTab.output)

            NavigationStack {
                container.makeSettingsView {
                    selectedTab = .sources
                }
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playbackStore.snapshot.currentItem != nil {
                MiniPlayerView(store: playbackStore) {
                    isNowPlayingPresented = true
                }
            }
        }
        .sheet(isPresented: $isNowPlayingPresented) {
            NowPlayingView(store: playbackStore, artworkLoader: container.artworkLoader) {
                isNowPlayingPresented = false
                selectedTab = .output
            }
        }
        .task {
            playbackStore.start()
            equalizerViewModel.setPlaybackActive(
                playbackStore.snapshot.status == .playing
            )
            await sourcesViewModel.loadSources()
            sourcesViewModel.startAutomaticScans()
        }
        .onChange(of: playbackStore.snapshot.status) { _, status in
            equalizerViewModel.setPlaybackActive(status == .playing)
        }
    }
}

private enum AppTab: Hashable {
    case library
    case sources
    case equalizer
    case output
    case settings
}
