import Foundation

struct ClippingProtectionResult: Equatable, Sendable {
    let predictedSamplePeak: Double?
    let automaticHeadroomDB: Double
    let isProtectionActive: Bool
    let measurementKind: String
}

struct ClippingProtectionController: Sendable {
    func evaluate(
        sourceSamplePeak: Double?,
        userGainDB: Double,
        replayGainDB: Double,
        maximumEnabledBandBoostDB: Double,
        preventClipping: Bool
    ) -> ClippingProtectionResult {
        guard let sourceSamplePeak, sourceSamplePeak.isFinite, sourceSamplePeak > 0 else {
            return ClippingProtectionResult(
                predictedSamplePeak: nil,
                automaticHeadroomDB: 0,
                isProtectionActive: false,
                measurementKind: "Sample peak estimate; source peak unavailable"
            )
        }
        let totalBoost = userGainDB + replayGainDB + max(0, maximumEnabledBandBoostDB)
        let predicted = sourceSamplePeak * pow(10, totalBoost / 20)
        let requiredHeadroom = preventClipping && predicted > 1
            ? -20 * log10(predicted)
            : 0
        return ClippingProtectionResult(
            predictedSamplePeak: predicted,
            automaticHeadroomDB: requiredHeadroom,
            isProtectionActive: requiredHeadroom < 0,
            measurementKind: "Predicted sample peak, not true peak"
        )
    }
}
