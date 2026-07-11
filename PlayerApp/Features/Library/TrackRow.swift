import SwiftUI

struct TrackRow: View {
    var row: LibraryTrackRow
    var isPlaying: Bool
    var artworkLoader: (any ArtworkThumbnailLoading)? = nil
    var play: () -> Void
    var playNext: () -> Void
    var addLast: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artworkID: row.track.artworkID, loader: artworkLoader)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).lineLimit(1)
                Text(row.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(row.technicalSummary).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                if case .unavailable(let reason) = row.playbackAvailability {
                    Label(reason.message, systemImage: "exclamationmark.circle")
                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if case .playable = row.playbackAvailability {
                Button(action: play) {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(LocalizedFormat.string("Play %@", row.title))
            }
        }
        .contextMenu {
            if row.playbackAvailability.isPlayable {
                Button("Play", action: play)
                Button("Play Next", action: playNext)
                Button("Add to Queue", action: addLast)
            }
        }
    }
}
