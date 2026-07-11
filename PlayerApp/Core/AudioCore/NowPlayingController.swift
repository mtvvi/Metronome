import Foundation
@preconcurrency import MediaPlayer
import UIKit

struct NowPlayingTrackMetadata: Equatable, Sendable {
    var fileName: String
    var title: String?
    var artist: String?
    var albumTitle: String?
    var duration: TimeInterval?
    var artworkID: String?

    init(
        fileName: String,
        title: String? = nil,
        artist: String? = nil,
        albumTitle: String? = nil,
        duration: TimeInterval? = nil,
        artworkID: String? = nil
    ) {
        self.fileName = fileName
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.duration = duration
        self.artworkID = artworkID
    }
}

@MainActor
protocol NowPlayingInfoWriting: AnyObject {
    var nowPlayingInfo: [String: Any]? { get set }
}

@MainActor
protocol NowPlayingUpdating: AnyObject {
    func update(
        track: NowPlayingTrackMetadata,
        elapsed: TimeInterval,
        playbackRate: Double
    )
    func update(snapshot: PlaybackSnapshot)
    func clear()
}

protocol NowPlayingArtworkLoading: Sendable {
    func artworkData(id: String) async -> Data?
}

extension NowPlayingUpdating {
    func update(snapshot: PlaybackSnapshot) {
        guard let item = snapshot.currentItem else { return }
        update(
            track: item.metadata,
            elapsed: snapshot.elapsed,
            playbackRate: snapshot.status == .playing ? 1 : 0
        )
    }
}

@MainActor
final class SystemNowPlayingInfoWriter: NowPlayingInfoWriting {
    private let center: MPNowPlayingInfoCenter

    init(center: MPNowPlayingInfoCenter = .default()) {
        self.center = center
    }

    var nowPlayingInfo: [String: Any]? {
        get { center.nowPlayingInfo }
        set { center.nowPlayingInfo = newValue }
    }
}

@MainActor
final class NowPlayingController {
    private let infoWriter: any NowPlayingInfoWriting
    private let artworkLoader: (any NowPlayingArtworkLoading)?
    private var currentArtworkID: String?
    private var currentArtwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    init(
        infoWriter: any NowPlayingInfoWriting = SystemNowPlayingInfoWriter(),
        artworkLoader: (any NowPlayingArtworkLoading)? = nil
    ) {
        self.infoWriter = infoWriter
        self.artworkLoader = artworkLoader
    }

    func update(
        track: NowPlayingTrackMetadata,
        elapsed: TimeInterval,
        playbackRate: Double
    ) {
        updateArtworkIfNeeded(id: track.artworkID)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title ?? track.fileName,
            MPMediaItemPropertyArtist: track.artist ?? "",
            MPMediaItemPropertyAlbumTitle: track.albumTitle ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate
        ]

        if let duration = track.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let currentArtwork { info[MPMediaItemPropertyArtwork] = currentArtwork }

        infoWriter.nowPlayingInfo = info
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        currentArtworkID = nil
        currentArtwork = nil
        infoWriter.nowPlayingInfo = nil
    }

    func update(snapshot: PlaybackSnapshot) {
        guard let item = snapshot.currentItem else { return }
        update(
            track: item.metadata,
            elapsed: snapshot.elapsed,
            playbackRate: snapshot.status == .playing ? 1 : 0
        )

        var info = infoWriter.nowPlayingInfo ?? [:]
        if let currentIndex = snapshot.currentIndex {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentIndex
        }
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = snapshot.queue.count
        infoWriter.nowPlayingInfo = info
    }

    private func updateArtworkIfNeeded(id: String?) {
        guard id != currentArtworkID else { return }
        artworkTask?.cancel()
        artworkTask = nil
        currentArtworkID = id
        currentArtwork = nil
        guard let id, let artworkLoader else { return }
        artworkTask = Task { [weak self] in
            guard let data = await artworkLoader.artworkData(id: id),
                  !Task.isCancelled,
                  let image = UIImage(data: data),
                  self?.currentArtworkID == id else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self?.currentArtwork = artwork
            var info = self?.infoWriter.nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            self?.infoWriter.nowPlayingInfo = info
        }
    }
}

extension NowPlayingController: NowPlayingUpdating {}
