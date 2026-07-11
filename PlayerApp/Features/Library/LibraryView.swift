import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel

    init(viewModel: LibraryViewModel = LibraryViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library Section", selection: $viewModel.selectedSection) {
                ForEach(LibraryViewModel.Section.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            content
        }
        .navigationTitle("Library")
        .searchable(text: $viewModel.searchText, prompt: "Search tracks")
        .safeAreaInset(edge: .bottom) {
            if let notice = viewModel.notice {
                LibraryNoticeBanner(notice: notice, dismiss: viewModel.dismissNotice)
            }
        }
        .task(id: viewModel.searchText) {
            if !viewModel.searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.loadError, viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label(error.title, systemImage: "exclamationmark.triangle")
            } description: { Text(error.message) } actions: {
                Button("Try Again") { Task { await viewModel.refresh() } }
            }
        } else if viewModel.isLoading && viewModel.rows.isEmpty {
            ProgressView()
        } else {
            switch viewModel.selectedSection {
            case .tracks:
                tracksList
            case .albums:
                AlbumsView(albums: viewModel.albums, viewModel: viewModel)
            case .artists:
                ArtistsView(artists: viewModel.artists, viewModel: viewModel)
            }
        }
    }

    private var tracksList: some View {
        List {
            if let message = viewModel.emptyStateMessage {
                ContentUnavailableView(message, systemImage: "music.note.list")
            }
            ForEach(viewModel.rows) { row in
                TrackRow(
                    row: row,
                    isPlaying: viewModel.currentlyPlayingTrackID == row.id,
                    artworkLoader: viewModel.artworkLoader,
                    play: { Task { await viewModel.play(row: row) } },
                    playNext: { Task { await viewModel.playNext(row: row) } },
                    addLast: { Task { await viewModel.addLast(row: row) } }
                )
                .onAppear {
                    if row.id == viewModel.rows.last?.id, viewModel.hasMoreTracks {
                        Task { await viewModel.loadMoreTracks() }
                    }
                }
            }
            if viewModel.hasMoreTracks {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .listStyle(.plain)
    }
}

private struct LibraryNoticeBanner: View {
    var notice: LibraryNotice
    var dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: notice.kind == .error ? "exclamationmark.circle" : "checkmark.circle")
            Text(notice.message).font(.subheadline)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial)
    }
}
