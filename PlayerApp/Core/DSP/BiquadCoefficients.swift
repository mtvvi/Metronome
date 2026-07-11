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
            sampleRate.isFinite,
            frequencyHz.isFinite,
            gainDB.isFinite,
            q.isFinite,
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
        let amplitude = pow(10, gainDB / 40)
        let alpha: Double
        switch filterType {
        case .lowPass, .highPass:
            alpha = sine / (2 * sqrt(0.5))
        case .lowShelf, .highShelf:
            alpha = sine * sqrt(2) / 2
        case .peaking, .resonantLowPass, .resonantHighPass, .bandPass,
             .bandStop, .resonantLowShelf, .resonantHighShelf:
            alpha = sine / (2 * q)
        }

        if [.peaking, .lowShelf, .highShelf, .resonantLowShelf, .resonantHighShelf]
            .contains(filterType), abs(gainDB) <= 0.000_001 {
            return .identity
        }

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

        case .lowPass, .resonantLowPass:
            return normalized(
                b0: (1 - cosine) / 2,
                b1: 1 - cosine,
                b2: (1 - cosine) / 2,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )

        case .highPass, .resonantHighPass:
            return normalized(
                b0: (1 + cosine) / 2,
                b1: -(1 + cosine),
                b2: (1 + cosine) / 2,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )

        case .bandPass:
            return normalized(
                b0: alpha,
                b1: 0,
                b2: -alpha,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )

        case .bandStop:
            return normalized(
                b0: 1,
                b1: -2 * cosine,
                b2: 1,
                a0: 1 + alpha,
                a1: -2 * cosine,
                a2: 1 - alpha
            )

        case .lowShelf, .resonantLowShelf:
            let rootAmplitude = sqrt(amplitude)
            return normalized(
                b0: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + 2 * rootAmplitude * alpha),
                b1: 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
                b2: amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - 2 * rootAmplitude * alpha),
                a0: (amplitude + 1) + (amplitude - 1) * cosine + 2 * rootAmplitude * alpha,
                a1: -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
                a2: (amplitude + 1) + (amplitude - 1) * cosine - 2 * rootAmplitude * alpha
            )

        case .highShelf, .resonantHighShelf:
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
