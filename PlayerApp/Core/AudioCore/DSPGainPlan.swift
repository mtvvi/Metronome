import Foundation

struct DSPGainPlan: Equatable, Sendable {
    let userMasterGainDB: Double
    let replayGainDB: Double
    let clippingAdjustmentDB: Double
    let resultingGainDB: Double

    static let bypassed = DSPGainPlan(
        userMasterGainDB: 0,
        replayGainDB: 0,
        clippingAdjustmentDB: 0,
        resultingGainDB: 0
    )

    init(
        userMasterGainDB: Double,
        replayGainDB: Double,
        clippingAdjustmentDB: Double
    ) {
        self.userMasterGainDB = userMasterGainDB
        self.replayGainDB = replayGainDB
        self.clippingAdjustmentDB = clippingAdjustmentDB
        resultingGainDB = userMasterGainDB + replayGainDB + clippingAdjustmentDB
    }

    static func protectedPlan(
        userMasterGainDB: Double,
        replayGainDB: Double,
        clippingResult: ClippingProtectionResult
    ) -> DSPGainPlan {
        DSPGainPlan(
            userMasterGainDB: userMasterGainDB,
            replayGainDB: replayGainDB,
            clippingAdjustmentDB: clippingResult.automaticHeadroomDB
        )
    }
}
