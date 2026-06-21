import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel

    init(viewModel: LibraryViewModel = LibraryViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if let statusMessage = viewModel.statusMessage {
                ContentUnavailableView(
                    statusMessage,
                    systemImage: viewModel.searchText.isEmpty ? "music.note.list" : "magnifyingglass"
                )
            } else {
                ForEach(viewModel.rows) { row in
                    LibraryTrackRowView(row: row)
                }
            }
        }
        .navigationTitle("Library")
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search tracks")
        .task(id: viewModel.searchText) {
            await viewModel.refresh()
        }
    }
}

private struct LibraryTrackRowView: View {
    var row: LibraryTrackRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.body)
                .lineLimit(1)
            Text(row.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(row.technicalSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
}
