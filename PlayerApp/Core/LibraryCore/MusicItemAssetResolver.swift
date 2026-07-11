import Foundation
@preconcurrency import MediaPlayer

enum MusicItemAssetResolutionError: Error, Equatable, Sendable {
    case itemNotFound(Int64)
    case unavailable(PlaybackUnavailabilityReason)
}

@MainActor
protocol MusicItemAssetResolving: Sendable {
    func resolveAssetURL(for persistentID: Int64) async throws -> URL
}

struct MusicItemAssetResolver: MusicItemAssetResolving {
    func resolveAssetURL(for persistentID: Int64) async throws -> URL {
        let query = MPMediaQuery.songs()
        let unsignedID = UInt64(bitPattern: persistentID)
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: NSNumber(value: unsignedID),
            forProperty: MPMediaItemPropertyPersistentID,
            comparisonType: .equalTo
        ))

        guard let item = query.items?.first else {
            throw MusicItemAssetResolutionError.itemNotFound(persistentID)
        }

        guard !item.hasProtectedAsset else {
            throw MusicItemAssetResolutionError.unavailable(.protectedAsset)
        }

        guard let assetURL = item.assetURL else {
            let reason: PlaybackUnavailabilityReason = item.isCloudItem
                ? .cloudOnly
                : .assetUnavailable
            throw MusicItemAssetResolutionError.unavailable(reason)
        }

        return assetURL
    }
}
