import Foundation

enum LibraryTrackPlaybackError: Error, Equatable {
    case missingRelativePath
    case missingSourceRoot(String)
}

protocol LibraryTrackPlaybackStarting: Sendable {
    func play(track: TrackRecord) throws
}

final class LibraryTrackPlaybackCoordinator: LibraryTrackPlaybackStarting, @unchecked Sendable {
    private let sourceRootRepository: any SourceRootRepository
    private let sourceAccess: any SourceRootAccessing
    private let playback: any PlaybackControlling
    private var currentResource: SecurityScopedResource?

    init(
        sourceRootRepository: any SourceRootRepository,
        sourceAccess: any SourceRootAccessing = SourceRootAccess(),
        playback: any PlaybackControlling = PlaybackEngine()
    ) {
        self.sourceRootRepository = sourceRootRepository
        self.sourceAccess = sourceAccess
        self.playback = playback
    }

    func play(track: TrackRecord) throws {
        guard let relativePath = track.relativePath, !relativePath.isEmpty else {
            throw LibraryTrackPlaybackError.missingRelativePath
        }

        guard let sourceRoot = try sourceRootRepository.fetchSourceRoot(id: track.sourceRootID) else {
            throw LibraryTrackPlaybackError.missingSourceRoot(track.sourceRootID)
        }

        let resource = try sourceAccess.resolve(sourceRoot)
        let trackURL = Self.trackURL(rootURL: resource.url, relativePath: relativePath)

        do {
            try playback.play(url: trackURL)
            currentResource?.stopAccessing()
            currentResource = resource
        } catch {
            resource.stopAccessing()
            throw error
        }
    }

    func stop() {
        playback.stop()
        currentResource?.stopAccessing()
        currentResource = nil
    }

    private static func trackURL(rootURL: URL, relativePath: String) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(rootURL) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }
    }
}
