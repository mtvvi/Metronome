import Foundation

struct CustomBiquadDSPConfiguration: Equatable, Sendable {
    var isFeatureEnabled: Bool
    var sampleRate: Double
    var bands: [PEQBand]

    init(
        isFeatureEnabled: Bool = false,
        sampleRate: Double,
        bands: [PEQBand]
    ) {
        self.isFeatureEnabled = isFeatureEnabled
        self.sampleRate = sampleRate
        self.bands = bands
    }

    var activeBands: [PEQBand] {
        guard isFeatureEnabled else { return [] }
        return bands.filter { band in
            band.isEnabled && abs(band.gainDB) > 0.000_001
        }
    }
}

struct CustomBiquadDSPPrototype: Sendable {
    private let configuration: CustomBiquadDSPConfiguration
    private let channelCount: Int

    init(
        configuration: CustomBiquadDSPConfiguration,
        channelCount: Int
    ) {
        self.configuration = configuration
        self.channelCount = channelCount
    }

    func render(_ pcmBuffer: [[Double]]) -> [[Double]] {
        let activeBands = configuration.activeBands

        guard !activeBands.isEmpty else {
            return pcmBuffer
        }

        let renderChannelCount = min(max(channelCount, 0), pcmBuffer.count)
        guard renderChannelCount > 0 else {
            return pcmBuffer
        }

        var output = pcmBuffer
        var filters = activeBands.map { band in
            BiquadFilter(
                coefficients: BiquadCoefficients.make(
                    filterType: band.filterType,
                    sampleRate: configuration.sampleRate,
                    frequencyHz: band.frequencyHz,
                    gainDB: band.gainDB,
                    q: band.q
                ),
                channelCount: renderChannelCount
            )
        }
        let frameCount = output.prefix(renderChannelCount).map(\.count).min() ?? 0

        for frameIndex in 0..<frameCount {
            var frame = (0..<renderChannelCount).map { channelIndex in
                output[channelIndex][frameIndex]
            }

            for filterIndex in filters.indices {
                frame = filters[filterIndex].processFrame(frame)
            }

            for channelIndex in 0..<renderChannelCount {
                output[channelIndex][frameIndex] = frame[channelIndex]
            }
        }

        return output
    }
}
