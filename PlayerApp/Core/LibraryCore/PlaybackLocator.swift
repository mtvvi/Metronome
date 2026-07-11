import Foundation

enum PlaybackLocatorKind: String, Codable, CaseIterable, Sendable {
    case appRelativePath
    case securityScopedSource
    case musicPersistentID
}

enum PlaybackLocator: Equatable, Sendable {
    case appRelativePath(String)
    case securityScopedSource(sourceRootID: String, relativePath: String)
    case musicPersistentID(Int64)
}

enum PlaybackUnavailabilityReason: Equatable, Sendable {
    case protectedAsset
    case cloudOnly
    case assetUnavailable
    case missingLocator
    case sourceUnavailable
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "protectedAsset": self = .protectedAsset
        case "cloudOnly": self = .cloudOnly
        case "assetUnavailable": self = .assetUnavailable
        case "missingLocator": self = .missingLocator
        case "sourceUnavailable": self = .sourceUnavailable
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .protectedAsset: "protectedAsset"
        case .cloudOnly: "cloudOnly"
        case .assetUnavailable: "assetUnavailable"
        case .missingLocator: "missingLocator"
        case .sourceUnavailable: "sourceUnavailable"
        case .unknown(let value): value
        }
    }

    var message: String {
        switch self {
        case .protectedAsset:
            String(localized: "This DRM-protected Music Library item cannot be played.")
        case .cloudOnly:
            String(localized: "Download this track in Music before playing it here.")
        case .assetUnavailable:
            String(localized: "The audio asset is currently unavailable.")
        case .missingLocator:
            String(localized: "This track has no valid playback location.")
        case .sourceUnavailable:
            String(localized: "Reconnect or add the source folder again.")
        case .unknown:
            String(localized: "This track is currently unavailable.")
        }
    }

    var actionTitle: String? {
        switch self {
        case .cloudOnly: String(localized: "Open Music")
        case .sourceUnavailable: String(localized: "Open Sources")
        case .protectedAsset, .assetUnavailable, .missingLocator, .unknown: nil
        }
    }
}

enum PlaybackAvailability: Equatable, Sendable {
    case playable(PlaybackLocator)
    case unavailable(PlaybackUnavailabilityReason)

    var isPlayable: Bool {
        if case .playable = self { return true }
        return false
    }
}

enum PlaybackLocatorError: Error, Equatable, Sendable {
    case missingRelativePath
    case missingPersistentID
    case invalidLocatorKind(String)
    case missingSourceRoot(String)
    case pathOutsideSourceRoot
    case applicationFilesDirectoryUnavailable
}

extension TrackRecord {
    var playbackAvailability: PlaybackAvailability {
        if let availabilityReason {
            return .unavailable(PlaybackUnavailabilityReason(rawValue: availabilityReason))
        }

        do {
            return .playable(try playbackLocator())
        } catch {
            return .unavailable(.missingLocator)
        }
    }

    func playbackLocator() throws -> PlaybackLocator {
        guard let kind = PlaybackLocatorKind(rawValue: playbackLocatorKind) else {
            throw PlaybackLocatorError.invalidLocatorKind(playbackLocatorKind)
        }

        switch kind {
        case .appRelativePath:
            guard let relativePath, !relativePath.isEmpty else {
                throw PlaybackLocatorError.missingRelativePath
            }
            return .appRelativePath(relativePath)
        case .securityScopedSource:
            guard let relativePath, !relativePath.isEmpty else {
                throw PlaybackLocatorError.missingRelativePath
            }
            return .securityScopedSource(
                sourceRootID: sourceRootID,
                relativePath: relativePath
            )
        case .musicPersistentID:
            guard let mediaPersistentID else {
                throw PlaybackLocatorError.missingPersistentID
            }
            return .musicPersistentID(mediaPersistentID)
        }
    }
}
