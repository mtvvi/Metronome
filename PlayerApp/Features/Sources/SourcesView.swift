import SwiftUI

struct SourcesView: View {
    @StateObject private var viewModel: SourcesViewModel
    @State private var isShowingFolderPicker = false
    @State private var reconnectingSource: SourceRootRecord?
    @State private var sourcePendingRemoval: SourceRootRecord?

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

                Button {
                    Task {
                        await viewModel.importMusicLibrary()
                    }
                } label: {
                    Label("Import Music Library", systemImage: "music.note.list")
                }
                .disabled(!viewModel.canImportMusicLibrary)
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
                            trackCount: viewModel.trackCountBySourceID[source.id] ?? 0,
                            progress: viewModel.scanProgressBySourceID[source.id],
                            onRescan: {
                                viewModel.startRescan(source)
                            },
                            onCancel: { viewModel.cancelScan(sourceID: source.id) },
                            onReconnect: {
                                reconnectingSource = source
                                isShowingFolderPicker = true
                            },
                            onRemove: { sourcePendingRemoval = source }
                        )
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    HStack {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: viewModel.dismissStatusMessage) {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Dismiss")
                    }
                }
            }
        }
        .navigationTitle("Sources")
        .task {
            await viewModel.loadSources()
        }
        .sheet(isPresented: $isShowingFolderPicker) {
            FolderPicker(
                onPick: { url in
                    if let source = reconnectingSource {
                        Task { await viewModel.reconnect(source, with: url) }
                    } else {
                        Task { await viewModel.addFolder(url: url) }
                    }
                    reconnectingSource = nil
                    isShowingFolderPicker = false
                },
                onCancel: {
                    reconnectingSource = nil
                    isShowingFolderPicker = false
                }
            )
        }
        .confirmationDialog(
            "Remove Source",
            isPresented: Binding(
                get: { sourcePendingRemoval != nil },
                set: { if !$0 { sourcePendingRemoval = nil } }
            ),
            presenting: sourcePendingRemoval
        ) { source in
            if source.kind == "securityScopedFolder" {
                Button("Remove Index Only", role: .destructive) {
                    Task { await viewModel.removeIndex(source) }
                    sourcePendingRemoval = nil
                }
                Button("Remove Index and Forget Access", role: .destructive) {
                    Task { await viewModel.removeSource(source) }
                    sourcePendingRemoval = nil
                }
            } else {
                Button("Remove Index Only", role: .destructive) {
                    Task { await viewModel.removeIndex(source) }
                    sourcePendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { sourcePendingRemoval = nil }
        } message: { source in
            if source.kind == "securityScopedFolder" {
                Text(LocalizedFormat.string(
                    "Choose whether Metronome should retain permission to %@. Audio files are never deleted.",
                    source.displayName
                ))
            } else {
                Text(LocalizedFormat.string(
                    "Remove indexed tracks from %@. Audio files are never deleted.",
                    source.displayName
                ))
            }
        }
    }
}

private struct SourceRow: View {
    let source: SourceRootRecord
    let trackCount: Int
    let progress: ScanProgress?
    let onRescan: () -> Void
    let onCancel: () -> Void
    let onReconnect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(.body)
                Text(sourceKindDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(LocalizedFormat.string("%lld tracks", Int64(trackCount)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastScanDate = source.lastScanDate {
                    Text(LocalizedFormat.string(
                        "Last scan: %@",
                        Date(timeIntervalSince1970: lastScanDate)
                            .formatted(date: .abbreviated, time: .shortened)
                    ))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let progress {
                    ProgressView(
                        value: Double(progress.completedCount),
                        total: Double(max(progress.totalCount ?? progress.completedCount + 1, 1))
                    )
                    .accessibilityLabel("Scan progress")
                }
            }

            Spacer()

            if progress?.phase.isRunning == true {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .frame(width: 44, height: 44)
                }
                    .accessibilityLabel("Cancel scan")
            } else {
                Button(action: onRescan) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                    .accessibilityLabel(LocalizedFormat.string(
                        "Rescan %@",
                        source.displayName
                    ))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Rescan", action: onRescan)
            if source.kind == "securityScopedFolder" {
                Button("Reconnect Folder", action: onReconnect)
            }
            Button("Remove…", role: .destructive, action: onRemove)
        }
    }

    private var sourceKindDescription: LocalizedStringKey {
        switch source.kind {
        case "musicLibrary": "Music Library"
        case "appDocuments": "App Documents"
        default: "Files folder"
        }
    }
}
