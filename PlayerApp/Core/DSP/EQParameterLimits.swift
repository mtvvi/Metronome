import Foundation

enum EQParameterLimits {
    static let maximumBandCount = 16
    static let frequencyRange = 10.0...40_000.0
    static let gainRange = -96.0...24.0
    static let qRange = 0.1...18.0
    static let preampRange = -96.0...24.0

    static func runtimeFrequency(
        requestedHz: Double,
        sampleRate: Double
    ) -> Double {
        guard sampleRate.isFinite, sampleRate > 2 else {
            return frequencyRange.lowerBound
        }
        let nyquistCeiling = min(20_000, max(1, sampleRate * 0.5 * 0.999))
        let lowerBound = min(20, nyquistCeiling)
        return min(max(requestedHz, lowerBound), nyquistCeiling)
    }
}
