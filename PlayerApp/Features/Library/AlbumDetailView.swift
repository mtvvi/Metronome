import SwiftUI

struct AlbumDetailView: View {
    var album: AlbumSummary
    @ObservedObject var viewModel: LibraryViewModel
    @State private var rows: [LibraryTrackRow] = []

    var body: some View {
        List {
            Button {
                Task { await viewModel.play(rows: rows, collectionName: displayTitle) }
            } label: {
                Label("Play Album", systemImage: "play.fill")
            }
            .disabled(!rows.contains(where: { $0.playbackAvailability.isPlayable }))
            ForEach(rows) { row in
                TrackRow(
                    row: row, isPlaying: viewModel.currentlyPlayingTrackID == row.id,
                    artworkLoader: viewModel.artworkLoader,
                    play: { Task { await viewModel.play(row: row) } },
                    playNext: { Task { await viewModel.playNext(row: row) } },
                    addLast: { Task { await viewModel.addLast(row: row) } }
                )
            }
        }
        .navigationTitle(displayTitle)
        .task { rows = await viewModel.tracks(for: album) }
    }

    private var displayTitle: String {
        album.title == "Unknown Album"
            ? String(localized: "Unknown Album")
            : album.title
    }
}
