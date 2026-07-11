import SwiftUI

struct ArtistsView: View {
    var artists: [ArtistSummary]
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        List(artists) { artist in
            NavigationLink {
                ArtistDetailView(artist: artist, viewModel: viewModel)
            } label: {
                VStack(alignment: .leading) {
                    Text(artist.name == "Unknown Artist"
                         ? String(localized: "Unknown Artist")
                         : artist.name)
                    Text(LocalizedFormat.string(
                        "%lld albums • %lld tracks",
                        Int64(artist.albumCount),
                        Int64(artist.trackCount)
                    ))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }
}
