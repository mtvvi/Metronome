import Combine
import Foundation

@MainActor
final class SourcesViewModel: ObservableObject {
    @Published private(set) var sources: [SourceRootRecord] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var latestMusicLibraryImportSummary: MusicLibraryImportSummary?
    @Published private(set) var scanProgressBySourceID: [String: ScanProgress] = [:]
    @Published private(set) var trackCountBySourceID: [String: Int] = [:]

    private let access: any SourceRootAccessing
    private let repository: (any SourceRootRepository)?
    private let scanner: any LibraryScanning
    private let musicLibraryImporter: (any MusicLibraryImporting)?
    private let libraryScanImporter: (any LibraryScanImporting)?
    private let musicLibraryChangeObserver: (any MusicLibraryChangeObserving)?
    private let spotlightIndexer: (any LibraryTrackSearchIndexing)?
    private var scanTasks: [String: Task<Void, Never>] = [:]
    private var musicLibraryObservationTask: Task<Void, Never>?

    init(
        access: any SourceRootAccessing = SourceRootAccess(),
        repository: (any SourceRootRepository)? = nil,
        scanner: any LibraryScanning = LibraryScanner(),
        musicLibraryImporter: (any MusicLibraryImporting)? = nil,
        libraryScanImporter: (any LibraryScanImporting)? = nil,
        musicLibraryChangeObserver: (any MusicLibraryChangeObserving)? = nil,
        spotlightIndexer: (any LibraryTrackSearchIndexing)? = nil
    ) {
        self.access = access
        self.repository = repository
        self.scanner = scanner
        self.musicLibraryImporter = musicLibraryImporter
        self.libraryScanImporter = libraryScanImporter
        self.musicLibraryChangeObserver = musicLibraryChangeObserver
        self.spotlightIndexer = spotlightIndexer
    }

    deinit {
        scanTasks.values.forEach { $0.cancel() }
        musicLibraryObservationTask?.cancel()
    }

    var canImportMusicLibrary: Bool {
        musicLibraryImporter != nil
    }

    func dismissStatusMessage() {
        statusMessage = nil
    }

    func loadSources() async {
        guard let repository else { return }

        do {
            let result = try await Task.detached {
                let sources = try repository.fetchSourceRoots()
                let counts: [String: Int]
                if let statistics = repository as? any SourceStatisticsRepository {
                    counts = try statistics.fetchTrackCountsBySourceRoot()
                } else {
                    counts = [:]
                }
                return (sources, counts)
            }.value
            sources = result.0
            trackCountBySourceID = result.1
            reconcileMusicLibraryObservation()
        } catch {
            statusMessage = String(localized: "Unable to load sources.")
        }
    }

    func addFolder(url: URL) async {
        let currentSources = sources
        let access = access
        let repository = repository
        do {
            let sourceRoot = try await Task.detached {
                try SourceReconciler.validateCandidate(url, against: currentSources)
                let sourceRoot = try access.makeSecurityScopedSource(from: url)
                try repository?.upsertSourceRoots([sourceRoot])
                return sourceRoot
            }.value
            sources.append(sourceRoot)
            sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            statusMessage = LocalizedFormat.string("Added %@.", sourceRoot.displayName)
        } catch SourceRootConflict.duplicate {
            statusMessage = String(localized: "This folder is already added.")
        } catch SourceRootConflict.nested {
            statusMessage = String(
                localized: "This folder overlaps an existing source and would duplicate tracks."
            )
        } catch {
            statusMessage = String(localized: "Unable to add folder.")
        }
    }

    func startRescan(_ sourceRoot: SourceRootRecord) {
        scanTasks[sourceRoot.id]?.cancel()
        scanTasks[sourceRoot.id] = Task { [weak self] in
            await self?.rescan(sourceRoot)
        }
    }

    func startAutomaticScans() {
        for source in sources where source.kind == "appDocuments" {
            startRescan(source)
        }
    }

    func cancelScan(sourceID: String) {
        scanTasks[sourceID]?.cancel()
        scanTasks[sourceID] = nil
    }

    func rescan(_ sourceRoot: SourceRootRecord) async {
        let scanID = UUID()
        defer { scanTasks[sourceRoot.id] = nil }
        scanProgressBySourceID[sourceRoot.id] = ScanProgress(
            scanID: scanID,
            sourceRootID: sourceRoot.id,
            phase: .enumerating,
            completedCount: 0,
            totalCount: nil
        )
        do {
            let resource = try access.resolve(sourceRoot)
            defer { resource.stopAccessing() }

            if let libraryScanImporter {
                let summary: LibraryScanImportSummary
                if let progressiveImporter = libraryScanImporter as? any ProgressReportingLibraryScanImporting {
                    let session = progressiveImporter.startImport(
                        sourceRoot,
                        rootURL: resource.url,
                        scanID: scanID
                    )
                    let progressTask = Task { [weak self] in
                        for await progress in session.progress {
                            guard !Task.isCancelled else { return }
                            self?.scanProgressBySourceID[sourceRoot.id] = progress
                        }
                    }
                    defer {
                        progressTask.cancel()
                        session.cancel()
                    }
                    summary = try await withTaskCancellationHandler {
                        try await session.value
                    } onCancel: {
                        session.cancel()
                    }
                    await progressTask.value
                } else {
                    summary = try await libraryScanImporter.importSource(
                        sourceRoot,
                        rootURL: resource.url
                    )
                }
                scanProgressBySourceID[sourceRoot.id] = ScanProgress(
                    scanID: scanID,
                    sourceRootID: sourceRoot.id,
                    phase: .completed,
                    completedCount: summary.importedTrackCount,
                    totalCount: summary.scannedFileCount
                )
                await loadSources()
                statusMessage = statusMessage(for: summary, sourceRoot: sourceRoot)
                return
            }

            let files = try await scanner.scan(rootURL: resource.url)
            scanProgressBySourceID[sourceRoot.id] = ScanProgress(
                scanID: scanID,
                sourceRootID: sourceRoot.id,
                phase: .completed,
                completedCount: files.count,
                totalCount: files.count
            )
            statusMessage = LocalizedFormat.string(
                "Found %lld audio files in %@.",
                Int64(files.count),
                sourceRoot.displayName
            )
        } catch SourceAccessError.staleBookmark {
            statusMessage = String(localized: "Folder permission is stale. Add the folder again.")
        } catch SourceAccessError.permissionDenied {
            statusMessage = String(localized: "Folder permission was denied.")
        } catch is CancellationError {
            scanProgressBySourceID[sourceRoot.id]?.phase = .cancelled
            statusMessage = String(localized: "Scan cancelled.")
        } catch {
            scanProgressBySourceID[sourceRoot.id]?.phase = .failed(String(describing: error))
            statusMessage = LocalizedFormat.string(
                "Unable to scan %@.",
                sourceRoot.displayName
            )
        }
    }

    func reconnect(_ sourceRoot: SourceRootRecord, with url: URL) async {
        let access = access
        let repository = repository
        do {
            let replacement = try await Task.detached {
                var replacement = try access.makeSecurityScopedSource(from: url)
                replacement.id = sourceRoot.id
                try repository?.upsertSourceRoots([replacement])
                return replacement
            }.value
            await loadSources()
            statusMessage = LocalizedFormat.string(
                "Reconnected %@.",
                replacement.displayName
            )
        } catch {
            statusMessage = String(localized: "Unable to reconnect this source.")
        }
    }

    func removeSource(_ sourceRoot: SourceRootRecord) async {
        do {
            guard let sourceManager = repository as? any SourceManagingRepository else {
                statusMessage = String(localized: "This library cannot remove sources.")
                return
            }
            let deletedIDs = try await Task.detached {
                try sourceManager.removeSourceRoot(id: sourceRoot.id)
            }.value
            let searchWarning = await deleteFromSystemSearch(deletedIDs)
            sources.removeAll { $0.id == sourceRoot.id }
            trackCountBySourceID[sourceRoot.id] = nil
            reconcileMusicLibraryObservation()
            statusMessage = LocalizedFormat.string(
                "Removed the index and forgot access to %@. Files were not deleted.",
                sourceRoot.displayName
            ) + searchWarning
        } catch {
            statusMessage = String(localized: "Unable to remove source.")
        }
    }

    func removeIndex(_ sourceRoot: SourceRootRecord) async {
        do {
            guard let sourceManager = repository as? any SourceManagingRepository else {
                statusMessage = String(localized: "This library cannot remove source indexes.")
                return
            }
            let deletedIDs = try await Task.detached {
                try sourceManager.removeSourceIndex(id: sourceRoot.id)
            }.value
            let searchWarning = await deleteFromSystemSearch(deletedIDs)
            trackCountBySourceID[sourceRoot.id] = 0
            statusMessage = LocalizedFormat.string(
                "Removed indexed tracks for %@. Folder access is retained.",
                sourceRoot.displayName
            ) + searchWarning
        } catch {
            statusMessage = String(localized: "Unable to remove the source index.")
        }
    }

    func importMusicLibrary() async {
        guard let musicLibraryImporter else {
            statusMessage = String(localized: "Music Library import is unavailable.")
            return
        }

        do {
            let summary = try await musicLibraryImporter.importLocalMusicLibrary()
            latestMusicLibraryImportSummary = summary
            await loadSources()
            statusMessage = statusMessage(for: summary)
        } catch {
            statusMessage = String(localized: "Unable to import Music Library.")
        }
    }

    private func statusMessage(for summary: MusicLibraryImportSummary) -> String {
        guard summary.authorizationStatus == .authorized else {
            return String(localized: "Music Library access was not granted.")
        }

        let searchWarning = summary.searchIndexWarning
            ? String(localized: " System search could not be updated.")
            : ""
        return LocalizedFormat.string(
            "Imported %lld playable Music Library tracks. Kept %lld protected and %lld unavailable items with playback disabled.",
            Int64(summary.importedCount),
            Int64(summary.protectedSkippedCount),
            Int64(summary.unavailableSkippedCount)
        ) + searchWarning
    }

    private func statusMessage(
        for summary: LibraryScanImportSummary,
        sourceRoot: SourceRootRecord
    ) -> String {
        let searchWarning = summary.searchIndexWarning
            ? String(localized: " System search could not be updated.")
            : ""
        if summary.failedMetadataCount == 0 {
            return LocalizedFormat.string(
                "Imported %lld audio files from %@.",
                Int64(summary.importedTrackCount),
                sourceRoot.displayName
            ) + searchWarning
        }

        return LocalizedFormat.string(
            "Imported %lld of %lld audio files from %@. Failed metadata for %lld.",
            Int64(summary.importedTrackCount),
            Int64(summary.scannedFileCount),
            sourceRoot.displayName,
            Int64(summary.failedMetadataCount)
        ) + searchWarning
    }

    private func startMusicLibraryObservationIfNeeded() {
        guard musicLibraryObservationTask == nil,
              sources.contains(where: { $0.kind == "musicLibrary" }),
              let musicLibraryChangeObserver,
              let musicLibraryImporter else { return }
        musicLibraryObservationTask = Task { [weak self] in
            let changes = musicLibraryChangeObserver.changes()
            for await _ in changes {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                do {
                    let summary = try await musicLibraryImporter.importLocalMusicLibrary()
                    guard let self else { return }
                    latestMusicLibraryImportSummary = summary
                    await loadSources()
                    statusMessage = statusMessage(for: summary)
                } catch {
                    self?.statusMessage = String(localized: "Unable to refresh Music Library changes.")
                }
            }
        }
    }

    private func reconcileMusicLibraryObservation() {
        guard sources.contains(where: { $0.kind == "musicLibrary" }) else {
            musicLibraryObservationTask?.cancel()
            musicLibraryObservationTask = nil
            musicLibraryChangeObserver?.stop()
            return
        }
        startMusicLibraryObservationIfNeeded()
    }

    private func deleteFromSystemSearch(_ trackIDs: [String]) async -> String {
        guard !trackIDs.isEmpty, let spotlightIndexer else { return "" }
        do {
            try await spotlightIndexer.deleteTracks(withIDs: trackIDs)
            return ""
        } catch {
            return String(localized: " System search could not be updated.")
        }
    }
}
