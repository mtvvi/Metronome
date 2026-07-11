import SwiftUI

struct AlbumsView: View {
    var albums: [AlbumSummary]
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        List(albums) { album in
            NavigationLink {
                AlbumDetailView(album: album, viewModel: viewModel)
            } label: {
                HStack {
                    ArtworkView(
                        artworkID: album.artworkID,
                        loader: viewModel.artworkLoader,
                        size: 56
                    )
                    VStack(alignment: .leading) {
                        Text(album.title == "Unknown Album"
                             ? String(localized: "Unknown Album")
                             : album.title)
                        Text(LocalizedFormat.string(
                            "%@ • %lld tracks",
                            album.albumArtist,
                            Int64(album.trackCount)
                        ))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
