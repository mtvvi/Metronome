import Foundation

struct EQFrequencyResponsePoint: Equatable, Sendable {
    let frequencyHz: Double
    let gainDB: Double
}

struct EQFrequencyResponse: Equatable, Sendable {
    let sampleRate: Double
    let points: [EQFrequencyResponsePoint]
}

extension BiquadCoefficients {
    func magnitudeDB(frequencyHz: Double, sampleRate: Double) -> Double {
        guard frequencyHz.isFinite, sampleRate.isFinite,
              frequencyHz >= 0, sampleRate > 0 else { return 0 }
        let omega = 2 * Double.pi * min(frequencyHz, sampleRate / 2) / sampleRate
        let cos1 = cos(omega)
        let sin1 = sin(omega)
        let cos2 = cos(2 * omega)
        let sin2 = sin(2 * omega)
        let numeratorReal = b0 + b1 * cos1 + b2 * cos2
        let numeratorImaginary = -b1 * sin1 - b2 * sin2
        let denominatorReal = 1 + a1 * cos1 + a2 * cos2
        let denominatorImaginary = -a1 * sin1 - a2 * sin2
        let numeratorPower = numeratorReal * numeratorReal
            + numeratorImaginary * numeratorImaginary
        let denominatorPower = denominatorReal * denominatorReal
            + denominatorImaginary * denominatorImaginary
        guard numeratorPower.isFinite, denominatorPower.isFinite,
              numeratorPower > 0, denominatorPower > 0 else { return -160 }
        let value = 10 * log10(numeratorPower / denominatorPower)
        return value.isFinite ? min(160, max(-160, value)) : -160
    }
}
