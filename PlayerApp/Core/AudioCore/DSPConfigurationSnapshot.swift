import Foundation

struct RuntimeEQBand: Equatable, Sendable {
    let id: UUID
    let filterType: PEQFilterType
    let frequencyHz: Double
    let gainDB: Double
    let q: Double
    let isBypassed: Bool
}

struct DSPConfigurationSnapshot: Equatable, Sendable {
    let presetID: UUID?
    let presetName: String?
    let assignmentScope: EqualizerAssignmentScope?
    let sampleRate: Double
    let bands: [RuntimeEQBand]
    let gainPlan: DSPGainPlan
    let isEqualizerBypassed: Bool
    let isReplayGainBypassed: Bool
    let isLimiterEnabled: Bool
    let isBitPerfect: Bool

    static func bypassed(
        sampleRate: Double,
        bitPerfect: Bool = false,
        presetID: UUID? = nil,
        presetName: String? = nil,
        assignmentScope: EqualizerAssignmentScope? = nil
    ) -> DSPConfigurationSnapshot {
        DSPConfigurationSnapshot(
            presetID: presetID,
            presetName: presetName,
            assignmentScope: assignmentScope,
            sampleRate: sampleRate,
            bands: [],
            gainPlan: .bypassed,
            isEqualizerBypassed: true,
            isReplayGainBypassed: true,
            isLimiterEnabled: false,
            isBitPerfect: bitPerfect
        )
    }
}

protocol DSPConfigurationApplying: Sendable {
    func applyDSPConfiguration(_ snapshot: DSPConfigurationSnapshot)
}
