import SwiftUI

struct QueueView: View {
    @ObservedObject var store: PlaybackStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(store.snapshot.queue.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: index == store.snapshot.currentIndex
                              ? "speaker.wave.2.fill"
                              : "line.3.horizontal")
                            .foregroundStyle(index == store.snapshot.currentIndex
                                             ? Color.accentColor
                                             : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.metadata.title ?? item.metadata.fileName)
                                .lineLimit(1)
                            Text(item.metadata.artist ?? item.metadata.albumTitle ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete(perform: store.removeQueueItems)
                .onMove(perform: store.moveQueueItem)
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }
}
