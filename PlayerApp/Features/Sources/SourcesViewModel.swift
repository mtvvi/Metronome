import Combine
import Foundation

@MainActor
final class SourcesViewModel: ObservableObject {
    @Published private(set) var sources: [SourceRootRecord] = []
    @Published private(set) var statusMessage: String?

    private let access: any SourceRootAccessing
    private let repository: (any SourceRootRepository)?
    private let scanner: any LibraryScanning

    init(
        access: any SourceRootAccessing = SourceRootAccess(),
        repository: (any SourceRootRepository)? = nil,
        scanner: any LibraryScanning = LibraryScanner()
    ) {
        self.access = access
        self.repository = repository
        self.scanner = scanner
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
}
