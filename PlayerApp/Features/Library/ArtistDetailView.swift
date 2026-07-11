import SwiftUI

struct ArtistDetailView: View {
    var artist: ArtistSummary
    @ObservedObject var viewModel: LibraryViewModel
    @State private var rows: [LibraryTrackRow] = []

    var body: some View {
        List {
            Button {
                Task { await viewModel.play(rows: rows, collectionName: displayName) }
            } label: {
                Label("Play All", systemImage: "play.fill")
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
        .navigationTitle(displayName)
        .task { rows = await viewModel.tracks(for: artist) }
    }

    private var displayName: String {
        artist.name == "Unknown Artist"
            ? String(localized: "Unknown Artist")
            : artist.name
    }
}
