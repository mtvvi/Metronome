import Foundation

struct EqualizerState: Equatable, Sendable {
    var preset: EQPreset
    var bitPerfectModeEnabled: Bool
    var clippingStatus: EqualizerClippingStatus

    var isEffectivelyBypassed: Bool {
        bitPerfectModeEnabled || !preset.isEnabled
    }

    var effectivePreampGainDB: Double {
        isEffectivelyBypassed ? 0 : preset.preampGainDB
    }

    var effectiveBands: [EffectivePEQBand] {
        preset.bands.map { band in
            EffectivePEQBand(
                source: band,
                isBypassed: isEffectivelyBypassed || !band.isEnabled
            )
        }
    }
}

struct EffectivePEQBand: Equatable, Sendable {
    var source: PEQBand
    var isBypassed: Bool
}

enum EqualizerClippingStatus: String, Codable, Equatable, Sendable {
    case notChecked
    case nominal
    case clippingRisk

    var title: String {
        switch self {
        case .notChecked:
            return "Not checked"
        case .nominal:
            return "No clipping detected"
        case .clippingRisk:
            return "Clipping risk"
        }
    }
}
