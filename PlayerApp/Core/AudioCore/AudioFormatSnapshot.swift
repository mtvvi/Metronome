import AVFoundation
import Foundation

struct AudioStreamFormatSnapshot: Codable, Equatable, Sendable {
    var sampleRate: Double
    var channelCount: UInt32
    var commonFormat: String
    var isInterleaved: Bool

    init(
        sampleRate: Double,
        channelCount: UInt32,
        commonFormat: String,
        isInterleaved: Bool
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.commonFormat = commonFormat
        self.isInterleaved = isInterleaved
    }

    init(_ format: AVAudioFormat) {
        sampleRate = format.sampleRate
        channelCount = format.channelCount
        commonFormat = String(describing: format.commonFormat)
        isInterleaved = format.isInterleaved
    }

    func isGaplessCompatible(with other: AudioStreamFormatSnapshot) -> Bool {
        sampleRate == other.sampleRate && channelCount == other.channelCount
    }
}

enum AudioFormatConversionReason: Codable, Equatable, Sendable {
    case none
    case sourceToProcessing
    case processingToOutput
    case routeChange
    case incompatibleGaplessTransition

    var displayName: String {
        switch self {
        case .none: String(localized: "No known conversion")
        case .sourceToProcessing: String(localized: "Source converted for processing")
        case .processingToOutput: String(localized: "Processing converted for output")
        case .routeChange: String(localized: "Output route changed")
        case .incompatibleGaplessTransition:
            String(localized: "Incompatible gapless formats")
        }
    }
}

struct AudioFormatSnapshot: Codable, Equatable, Sendable {
    var source: AudioStreamFormatSnapshot?
    var processing: AudioStreamFormatSnapshot?
    var actualOutput: AudioStreamFormatSnapshot?
    var conversionReason: AudioFormatConversionReason
}

protocol AudioFormatSnapshotProviding: Sendable {
    func currentAudioFormatSnapshot() -> AudioFormatSnapshot
}
