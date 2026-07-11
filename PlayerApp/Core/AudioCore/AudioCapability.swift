import Foundation

enum AudioCapabilityStatus: String, Codable, Equatable, Sendable {
    case supported
    case conditional
    case unavailable
    case unverified

    var displayName: String {
        switch self {
        case .supported: String(localized: "Supported")
        case .conditional: String(localized: "Conditional")
        case .unavailable: String(localized: "Unavailable")
        case .unverified: String(localized: "Unverified")
        }
    }
}

struct AudioCapability: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var status: AudioCapabilityStatus
    var detail: String
}

enum AudioContainerCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case mp3, aac, alac, flac, wav, aiff, ogg, opus, dsd
}
