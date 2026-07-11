import Foundation

protocol PlaybackLocatorResolving: Sendable {
    func resolve(_ locator: PlaybackLocator) async throws -> ResolvedPlaybackLocation
}

final class ResolvedPlaybackLocation: @unchecked Sendable {
    let url: URL
    private let stateLock = NSLock()
    private var securityScopedResource: SecurityScopedResource?

    init(url: URL, securityScopedResource: SecurityScopedResource? = nil) {
        self.url = url
        self.securityScopedResource = securityScopedResource
    }

    func stopAccessing() {
        stateLock.lock()
        let resource = securityScopedResource
        securityScopedResource = nil
        stateLock.unlock()
        resource?.stopAccessing()
    }

    deinit {
        stopAccessing()
    }
}

struct PlaybackLocatorResolver: PlaybackLocatorResolving {
    private let sourceRootRepository: any SourceRootRepository
    private let sourceAccess: any SourceRootAccessing
    private let musicItemResolver: any MusicItemAssetResolving
    private let appFilesRoot: @Sendable () throws -> URL

    init(
        sourceRootRepository: any SourceRootRepository,
        sourceAccess: any SourceRootAccessing = SourceRootAccess(),
        musicItemResolver: any MusicItemAssetResolving = MusicItemAssetResolver(),
        appFilesRoot: @escaping @Sendable () throws -> URL = Self.defaultAppFilesRoot
    ) {
        self.sourceRootRepository = sourceRootRepository
        self.sourceAccess = sourceAccess
        self.musicItemResolver = musicItemResolver
        self.appFilesRoot = appFilesRoot
    }

    func resolve(_ locator: PlaybackLocator) async throws -> ResolvedPlaybackLocation {
        switch locator {
        case .appRelativePath(let relativePath):
            let rootURL = try appFilesRoot()
            return ResolvedPlaybackLocation(
                url: try Self.containedURL(rootURL: rootURL, relativePath: relativePath)
            )

        case .securityScopedSource(let sourceRootID, let relativePath):
            guard var sourceRoot = try sourceRootRepository.fetchSourceRoot(id: sourceRootID) else {
                throw PlaybackLocatorError.missingSourceRoot(sourceRootID)
            }

            let resource = try sourceAccess.resolve(sourceRoot)
            do {
                let url = try Self.containedURL(
                    rootURL: resource.url,
                    relativePath: relativePath
                )

                if let refreshedBookmarkData = resource.refreshedBookmarkData {
                    sourceRoot.bookmarkData = refreshedBookmarkData
                    sourceRoot.baseURL = resource.url.absoluteString
                    try sourceRootRepository.upsertSourceRoots([sourceRoot])
                }

                return ResolvedPlaybackLocation(
                    url: url,
                    securityScopedResource: resource
                )
            } catch {
                resource.stopAccessing()
                throw error
            }

        case .musicPersistentID(let persistentID):
            let url = try await musicItemResolver.resolveAssetURL(for: persistentID)
            return ResolvedPlaybackLocation(url: url)
        }
    }

    static func defaultAppFilesRoot() throws -> URL {
        guard let rootURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw PlaybackLocatorError.applicationFilesDirectoryUnavailable
        }
        return rootURL
    }

    private static func containedURL(rootURL: URL, relativePath: String) throws -> URL {
        let components = try validatedComponents(relativePath)
        let candidate = components.reduce(rootURL) { url, component in
            url.appendingPathComponent(component, isDirectory: false)
        }

        let canonicalRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = canonicalRoot.pathComponents
        let candidateComponents = canonicalCandidate.pathComponents

        guard candidateComponents.count > rootComponents.count,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            throw PlaybackLocatorError.pathOutsideSourceRoot
        }

        return canonicalCandidate
    }

    private static func validatedComponents(_ relativePath: String) throws -> [String] {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("\\"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0") else {
            throw PlaybackLocatorError.pathOutsideSourceRoot
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PlaybackLocatorError.pathOutsideSourceRoot
        }

        return components.map(String.init)
    }
}
