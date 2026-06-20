import SwiftUI

struct SourcesView: View {
    @StateObject private var viewModel: SourcesViewModel
    @State private var isShowingFolderPicker = false

    init(viewModel: SourcesViewModel = SourcesViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                Button {
                    isShowingFolderPicker = true
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }

            Section("Sources") {
                if viewModel.sources.isEmpty {
                    ContentUnavailableView(
                        "No Sources",
                        systemImage: "externaldrive",
                        description: Text("Add a folder from Files to begin scanning.")
                    )
                } else {
                    ForEach(viewModel.sources, id: \.id) { source in
                        SourceRow(
                            source: source,
                            onRescan: {
                                Task {
                                    await viewModel.rescan(source)
                                }
                            }
                        )
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sources")
        .task {
            viewModel.loadSources()
        }
        .sheet(isPresented: $isShowingFolderPicker) {
            FolderPicker(
                onPick: { url in
                    viewModel.addFolder(url: url)
                    isShowingFolderPicker = false
                },
                onCancel: {
                    isShowingFolderPicker = false
                }
            )
        }
    }
}

private struct SourceRow: View {
    let source: SourceRootRecord
    let onRescan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(.body)
                Text(source.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRescan) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Rescan \(source.displayName)")
        }
        .padding(.vertical, 4)
    }
}
