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
