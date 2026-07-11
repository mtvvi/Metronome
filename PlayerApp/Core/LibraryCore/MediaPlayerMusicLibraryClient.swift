import Foundation
import MediaPlayer

struct MediaPlayerMusicLibraryClient: MusicLibraryAuthorizationProviding, MusicLibraryQuerying {
    var currentStatus: MusicLibraryAuthorizationStatus {
        MusicLibraryAuthorizationStatus(status: MPMediaLibrary.authorizationStatus())
    }

    func requestAuthorization() async -> MusicLibraryAuthorizationStatus {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: MusicLibraryAuthorizationStatus(status: status))
            }
        }
    }

    func songs() -> [MusicLibraryMediaItem] {
        MPMediaQuery.songs().items?.map(MusicLibraryMediaItem.init(mediaItem:)) ?? []
    }
}

enum MusicLibraryChange: Sendable {
    case changed
}

@MainActor
protocol MusicLibraryChangeObserving: AnyObject {
    func changes() -> AsyncStream<MusicLibraryChange>
    func stop()
}

@MainActor
final class MediaPlayerMusicLibraryChangeObserver: MusicLibraryChangeObserving {
    private let library: MPMediaLibrary
    private var notificationToken: NSObjectProtocol?
    private var isGeneratingNotifications = false

    init(library: MPMediaLibrary = .default()) {
        self.library = library
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        if isGeneratingNotifications {
            library.endGeneratingLibraryChangeNotifications()
        }
    }

    func changes() -> AsyncStream<MusicLibraryChange> {
        stop()
        let pair = AsyncStream<MusicLibraryChange>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        library.beginGeneratingLibraryChangeNotifications()
        isGeneratingNotifications = true
        notificationToken = NotificationCenter.default.addObserver(
            forName: .MPMediaLibraryDidChange,
            object: library,
            queue: .main
        ) { _ in
            pair.continuation.yield(.changed)
        }
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        return pair.stream
    }

    func stop() {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
            self.notificationToken = nil
        }
        if isGeneratingNotifications {
            library.endGeneratingLibraryChangeNotifications()
            isGeneratingNotifications = false
        }
    }
}

private extension MusicLibraryAuthorizationStatus {
    init(status: MPMediaLibraryAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .authorized:
            self = .authorized
        @unknown default:
            self = .denied
        }
    }
}

private extension MusicLibraryMediaItem {
    init(mediaItem: MPMediaItem) {
        self.init(
            persistentID: Int64(mediaItem.persistentID),
            assetURL: mediaItem.assetURL,
            hasProtectedAsset: mediaItem.hasProtectedAsset,
            isCloudItem: mediaItem.isCloudItem,
            title: mediaItem.title,
            albumTitle: mediaItem.albumTitle,
            albumArtist: mediaItem.albumArtist,
            artist: mediaItem.artist,
            composer: mediaItem.composer,
            genre: mediaItem.genre,
            releaseYear: nil,
            discNumber: mediaItem.discNumber,
            trackNumber: mediaItem.albumTrackNumber,
            duration: mediaItem.playbackDuration > 0 ? mediaItem.playbackDuration : nil
        )
    }
}
