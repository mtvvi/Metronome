import Foundation

enum EqualizerAssignmentScope: Hashable, Codable, Sendable {
    case global
    case output(String)
    case headphones(String)

    var storageKey: String {
        switch self {
        case .global: "global"
        case .output(let id): "output:\(id)"
        case .headphones(let id): "headphones:\(id)"
        }
    }
}

struct EqualizerAssignment: Codable, Equatable, Sendable {
    var scope: EqualizerAssignmentScope
    var presetID: UUID
}

struct DSPSettings: Codable, Equatable, Sendable {
    var masterGainDB: Double = 0
    var bitPerfectModeEnabled = false
    var analyzerEnabled = true
    var replayGainEnabled = false
    var replayGainMode: ReplayGainMode = .album
    var replayGainPreampDB: Double = 0
    var replayGainNoMetadataPreampDB: Double = 0
    var replayGainPreventClipping = true
    var lastSelectedBandID: UUID?
}
