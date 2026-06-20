import Foundation

struct BiquadCoefficients: Equatable, Sendable {
    var b0: Double
    var b1: Double
    var b2: Double
    var a1: Double
    var a2: Double

    static let identity = BiquadCoefficients(
        b0: 1,
        b1: 0,
        b2: 0,
        a1: 0,
        a2: 0
    )

    static func make(
        filterType: PEQFilterType,
        sampleRate: Double,
        frequencyHz: Double,
        gainDB: Double,
        q: Double
    ) -> BiquadCoefficients {
        guard
            abs(gainDB) > 0.000_001,
            sampleRate > 0,
            frequencyHz > 0,
            q > 0
        else {
            return .identity
        }

        let nyquist = sampleRate / 2
        let clampedFrequency = min(max(frequencyHz, 1), nyquist - 1)
        let omega = 2 * Double.pi * clampedFrequency / sampleRate
        let cosine = cos(omega)
        let sine = sin(omega)
        let alpha = sine / (2 * q)
        let amplitude = pow(10, gainDB / 40)

        switch filterType {
        case .peaking:
            return normalized(
                b0: 1 + alpha * amplitude,
                b1: -2 * cosine,
                b2: 1 - alpha * amplitude,
                a0: 1 + alpha / amplitude,
                a1: -2 * cosine,
                a2: 1 - alpha / amplitude
            )

        case .lowShelf:
            let rootAmplitude = sqrt(amplitude)
            return normalized(
                b0: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + 2 * rootAmplitude * alpha),
                b1: 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
                b2: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - 2 * rootAmplitude * alpha),
                a0: (amplitude + 1) + (amplitude - 1) * cosine + 2 * rootAmplitude * alpha,
                a1: -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
                a2: (amplitude + 1) + (amplitude - 1) * cosine - 2 * rootAmplitude * alpha
            )

        case .highShelf:
            let rootAmplitude = sqrt(amplitude)
            return normalized(
                b0: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + 2 * rootAmplitude * alpha),
                b1: -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
                b2: amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - 2 * rootAmplitude * alpha),
                a0: (amplitude + 1) - (amplitude - 1) * cosine + 2 * rootAmplitude * alpha,
                a1: 2 * ((amplitude - 1) - (amplitude + 1) * cosine),
                a2: (amplitude + 1) - (amplitude - 1) * cosine - 2 * rootAmplitude * alpha
            )
        }
    }

    private static func normalized(
        b0: Double,
        b1: Double,
        b2: Double,
        a0: Double,
        a1: Double,
        a2: Double
    ) -> BiquadCoefficients {
        guard a0 != 0 else { return .identity }

        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}
