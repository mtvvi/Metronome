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
    private let appDocumentsRoot: @Sendable () throws -> URL

    init(
        appDocumentsRoot: @escaping @Sendable () throws -> URL = PlaybackLocatorResolver.defaultAppFilesRoot
    ) {
        self.appDocumentsRoot = appDocumentsRoot
    }

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
        if sourceRoot.kind == "appDocuments" {
            return SecurityScopedResource(
                url: try appDocumentsRoot(),
                didStartAccessing: false
            )
        }
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

        let refreshedBookmarkData = isStale ? try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) : nil

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        guard didStartAccessing else {
            throw SourceAccessError.permissionDenied
        }

        return SecurityScopedResource(
            url: url,
            didStartAccessing: didStartAccessing,
            refreshedBookmarkData: refreshedBookmarkData
        )
    }

    private func displayName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }
}

final class SecurityScopedResource: @unchecked Sendable {
    let url: URL
    let refreshedBookmarkData: Data?
    private var didStartAccessing: Bool
    private let stateLock = NSLock()
    private let stopAccessingHandler: (() -> Void)?

    init(
        url: URL,
        didStartAccessing: Bool,
        refreshedBookmarkData: Data? = nil,
        stopAccessingHandler: (() -> Void)? = nil
    ) {
        self.url = url
        self.didStartAccessing = didStartAccessing
        self.refreshedBookmarkData = refreshedBookmarkData
        self.stopAccessingHandler = stopAccessingHandler
    }

    func stopAccessing() {
        stateLock.lock()
        guard didStartAccessing else {
            stateLock.unlock()
            return
        }
        didStartAccessing = false
        stateLock.unlock()
        if let stopAccessingHandler {
            stopAccessingHandler()
        } else {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        stopAccessing()
    }
}
