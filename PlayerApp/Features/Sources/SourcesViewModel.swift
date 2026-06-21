import Combine
import Foundation

@MainActor
final class SourcesViewModel: ObservableObject {
    @Published private(set) var sources: [SourceRootRecord] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var latestMusicLibraryImportSummary: MusicLibraryImportSummary?

    private let access: any SourceRootAccessing
    private let repository: (any SourceRootRepository)?
    private let scanner: any LibraryScanning
    private let musicLibraryImporter: (any MusicLibraryImporting)?
    private let libraryScanImporter: (any LibraryScanImporting)?

    init(
        access: any SourceRootAccessing = SourceRootAccess(),
        repository: (any SourceRootRepository)? = nil,
        scanner: any LibraryScanning = LibraryScanner(),
        musicLibraryImporter: (any MusicLibraryImporting)? = nil,
        libraryScanImporter: (any LibraryScanImporting)? = nil
    ) {
        self.access = access
        self.repository = repository
        self.scanner = scanner
        self.musicLibraryImporter = musicLibraryImporter
        self.libraryScanImporter = libraryScanImporter
    }

    var canImportMusicLibrary: Bool {
        musicLibraryImporter != nil
    }

    func loadSources() {
        guard let repository else { return }

        do {
            sources = try repository.fetchSourceRoots()
        } catch {
            statusMessage = "Unable to load sources."
        }
    }

    func addFolder(url: URL) {
        do {
            let sourceRoot = try access.makeSecurityScopedSource(from: url)
            try repository?.upsertSourceRoots([sourceRoot])
            sources.append(sourceRoot)
            sources.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            statusMessage = "Added \(sourceRoot.displayName)."
        } catch {
            statusMessage = "Unable to add folder."
        }
    }

    func rescan(_ sourceRoot: SourceRootRecord) async {
        do {
            let resource = try access.resolve(sourceRoot)
            defer { resource.stopAccessing() }

            if let libraryScanImporter {
                let summary = try await libraryScanImporter.importSource(sourceRoot, rootURL: resource.url)
                statusMessage = statusMessage(for: summary, sourceRoot: sourceRoot)
                return
            }

            let files = try await scanner.scan(rootURL: resource.url)
            statusMessage = "Found \(files.count) audio files in \(sourceRoot.displayName)."
        } catch SourceAccessError.staleBookmark {
            statusMessage = "Folder permission is stale. Add the folder again."
        } catch SourceAccessError.permissionDenied {
            statusMessage = "Folder permission was denied."
        } catch is CancellationError {
            statusMessage = "Scan cancelled."
        } catch {
            statusMessage = "Unable to scan \(sourceRoot.displayName)."
        }
    }

    func importMusicLibrary() async {
        guard let musicLibraryImporter else {
            statusMessage = "Music Library import is unavailable."
            return
        }

        do {
            let summary = try await musicLibraryImporter.importLocalMusicLibrary()
            latestMusicLibraryImportSummary = summary
            statusMessage = statusMessage(for: summary)
        } catch {
            statusMessage = "Unable to import Music Library."
        }
    }

    private func statusMessage(for summary: MusicLibraryImportSummary) -> String {
        guard summary.authorizationStatus == .authorized else {
            return "Music Library access was not granted."
        }

        return "Imported \(summary.importedCount) Music Library tracks. Skipped \(summary.protectedSkippedCount) protected and \(summary.unavailableSkippedCount) unavailable."
    }

    private func statusMessage(
        for summary: LibraryScanImportSummary,
        sourceRoot: SourceRootRecord
    ) -> String {
        if summary.failedMetadataCount == 0 {
            return "Imported \(summary.importedTrackCount) audio files from \(sourceRoot.displayName)."
        }

        return "Imported \(summary.importedTrackCount) of \(summary.scannedFileCount) audio files from \(sourceRoot.displayName). Failed metadata for \(summary.failedMetadataCount)."
    }
}
