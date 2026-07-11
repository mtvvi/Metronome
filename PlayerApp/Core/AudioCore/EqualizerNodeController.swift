import AVFoundation
import Foundation

struct EqualizerBandNodeConfiguration: Equatable, Sendable {
    var frequencyHz: Float
    var gainDB: Float
    var bandwidthOctaves: Float
    var isBypassed: Bool
    var filterType: PEQFilterType

    static let bypassed = EqualizerBandNodeConfiguration(
        frequencyHz: 1_000,
        gainDB: 0,
        bandwidthOctaves: 1,
        isBypassed: true,
        filterType: .peaking
    )
}

protocol EqualizerNodeApplying: AnyObject {
    var isBypassed: Bool { get set }
    var globalGainDB: Float { get set }

    func configureBand(
        at index: Int,
        configuration: EqualizerBandNodeConfiguration
    )
}

final class EqualizerNodeController {
    private let node: any EqualizerNodeApplying

    init(node: any EqualizerNodeApplying = AVAudioUnitEQNodeAdapter()) {
        self.node = node
    }

    func apply(state: EqualizerState) {
        node.isBypassed = state.isEffectivelyBypassed
        node.globalGainDB = Self.nativeGain(state.effectivePreampGainDB)

        let effectiveBands = Array(state.effectiveBands.prefix(16))

        for index in 0..<16 {
            guard effectiveBands.indices.contains(index) else {
                node.configureBand(at: index, configuration: .bypassed)
                continue
            }

            let band = effectiveBands[index]
            node.configureBand(
                at: index,
                configuration: EqualizerBandNodeConfiguration(
                    frequencyHz: Float(band.source.frequencyHz),
                    gainDB: Float(band.isBypassed ? 0 : band.source.gainDB),
                    bandwidthOctaves: Float(EQBandwidthConverter.bandwidthOctaves(forQ: band.source.q)),
                    isBypassed: band.isBypassed,
                    filterType: band.source.filterType
                )
            )
        }
    }

    func apply(snapshot: DSPConfigurationSnapshot) {
        node.isBypassed = snapshot.isEqualizerBypassed
            && abs(snapshot.gainPlan.resultingGainDB) <= 0.000_001
        node.globalGainDB = Self.nativeGain(snapshot.gainPlan.resultingGainDB)
        let bands = Array(snapshot.bands.prefix(16))

        for index in 0..<16 {
            guard bands.indices.contains(index) else {
                node.configureBand(at: index, configuration: .bypassed)
                continue
            }
            let band = bands[index]
            node.configureBand(
                at: index,
                configuration: EqualizerBandNodeConfiguration(
                    frequencyHz: Float(band.frequencyHz),
                    gainDB: Float(band.filterType.usesGain ? band.gainDB : 0),
                    bandwidthOctaves: Float(
                        band.filterType.usesBandwidth
                            ? EQBandwidthConverter.bandwidthOctaves(forQ: band.q)
                            : 1
                    ),
                    isBypassed: snapshot.isEqualizerBypassed || band.isBypassed,
                    filterType: band.filterType
                )
            )
        }
    }

    private static func nativeGain(_ value: Double) -> Float {
        guard value.isFinite else { return 0 }
        return Float(min(max(value, -96), 24))
    }
}

final class AVAudioUnitEQNodeAdapter: EqualizerNodeApplying {
    let equalizer: AVAudioUnitEQ

    init(equalizer: AVAudioUnitEQ = AVAudioUnitEQ(numberOfBands: 16)) {
        self.equalizer = equalizer
    }

    var isBypassed: Bool {
        get { equalizer.bypass }
        set { equalizer.bypass = newValue }
    }

    var globalGainDB: Float {
        get { equalizer.globalGain }
        set { equalizer.globalGain = newValue }
    }

    func configureBand(
        at index: Int,
        configuration: EqualizerBandNodeConfiguration
    ) {
        guard equalizer.bands.indices.contains(index) else { return }

        let parameters = equalizer.bands[index]
        parameters.filterType = configuration.filterType.avAudioUnitEQFilterType
        parameters.frequency = configuration.frequencyHz
        parameters.gain = configuration.gainDB
        parameters.bandwidth = configuration.bandwidthOctaves
        parameters.bypass = configuration.isBypassed
    }
}

extension PEQFilterType {
    var avAudioUnitEQFilterType: AVAudioUnitEQFilterType {
        switch self {
        case .peaking:
            return .parametric
        case .lowPass:
            return .lowPass
        case .highPass:
            return .highPass
        case .resonantLowPass:
            return .resonantLowPass
        case .resonantHighPass:
            return .resonantHighPass
        case .bandPass:
            return .bandPass
        case .bandStop:
            return .bandStop
        case .lowShelf:
            return .lowShelf
        case .highShelf:
            return .highShelf
        case .resonantLowShelf:
            return .resonantLowShelf
        case .resonantHighShelf:
            return .resonantHighShelf
        }
    }
}
