import Foundation

struct EQResponseCalculator: Sendable {
    func response(
        preset: EQPreset,
        sampleRate: Double,
        pointCount: Int = 256,
        minimumFrequency: Double = 20,
        maximumFrequency: Double = 20_000
    ) -> EQFrequencyResponse {
        guard sampleRate.isFinite, sampleRate > 0, pointCount > 1 else {
            return EQFrequencyResponse(sampleRate: max(0, sampleRate), points: [])
        }
        let upper = min(maximumFrequency, sampleRate * 0.5 * 0.999)
        let lower = min(max(minimumFrequency, 1), upper)
        guard lower > 0, upper > lower else {
            return EQFrequencyResponse(sampleRate: sampleRate, points: [])
        }
        let frequencies = Self.logarithmicFrequencies(
            minimum: lower,
            maximum: upper,
            count: pointCount
        )
        let activeBands = preset.isEnabled ? preset.bands.filter(\.isEnabled) : []
        let coefficients = activeBands.map { band in
            BiquadCoefficients.make(
                filterType: band.filterType,
                sampleRate: sampleRate,
                frequencyHz: EQParameterLimits.runtimeFrequency(
                    requestedHz: band.frequencyHz,
                    sampleRate: sampleRate
                ),
                gainDB: band.gainDB,
                q: band.q
            )
        }
        let preamp = preset.isEnabled && preset.preampGainDB.isFinite
            ? preset.preampGainDB
            : 0
        let points = frequencies.map { frequency in
            let bandGain = coefficients.reduce(0) { result, coefficients in
                result + coefficients.magnitudeDB(
                    frequencyHz: frequency,
                    sampleRate: sampleRate
                )
            }
            let gain = preamp + bandGain
            return EQFrequencyResponsePoint(
                frequencyHz: frequency,
                gainDB: gain.isFinite ? gain : 0
            )
        }
        return EQFrequencyResponse(sampleRate: sampleRate, points: points)
    }

    static func logarithmicFrequencies(
        minimum: Double,
        maximum: Double,
        count: Int
    ) -> [Double] {
        guard minimum > 0, maximum > minimum, count > 1 else { return [] }
        let start = log10(minimum)
        let span = log10(maximum) - start
        return (0..<count).map { index in
            pow(10, start + span * Double(index) / Double(count - 1))
        }
    }
}
