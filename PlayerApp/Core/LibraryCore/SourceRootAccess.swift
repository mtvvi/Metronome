import Foundation

enum SourceAccessError: Error, Equatable {
    case missingBookmarkData
    case staleBookmark
    case permissionDenied
}

protocol SourceRootAccessing: Sendable {
    func makeSecurityScopedSource(from url: URL) throws -> SourceRootRecord
    func resolve(_ sourceRoot: SourceRootRecord) throws -> SecurityScopedResource
}

struct SourceRootAccess: SourceRootAccessing {
    func makeSecurityScopedSource(from url: URL) throws -> SourceRootRecord {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return SourceRootRecord(
            id: UUID().uuidString,
            kind: "securityScopedFolder",
            displayName: displayName(for: url),
            bookmarkData: bookmarkData,
            baseURL: url.absoluteString,
            isEnabled: true,
            lastScanDate: nil
        )
    }

    func resolve(_ sourceRoot: SourceRootRecord) throws -> SecurityScopedResource {
        guard let bookmarkData = sourceRoot.bookmarkData else {
            throw SourceAccessError.missingBookmarkData
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard !isStale else {
            throw SourceAccessError.staleBookmark
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        guard didStartAccessing else {
            throw SourceAccessError.permissionDenied
        }

        return SecurityScopedResource(url: url, didStartAccessing: didStartAccessing)
    }

    private func displayName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }
}

final class SecurityScopedResource {
    let url: URL
    private var didStartAccessing: Bool

    init(url: URL, didStartAccessing: Bool) {
        self.url = url
        self.didStartAccessing = didStartAccessing
    }

    func stopAccessing() {
        guard didStartAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        didStartAccessing = false
    }

    deinit {
        stopAccessing()
    }
}
