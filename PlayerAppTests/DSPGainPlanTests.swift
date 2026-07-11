import XCTest
@testable import PlayerApp

final class DSPGainPlanTests: XCTestCase {
    func testUnifiedPlanSumsMasterReplayGainAndAutomaticHeadroom() {
        let clipping = ClippingProtectionResult(
            predictedSamplePeak: 1.5,
            automaticHeadroomDB: -3.52,
            isProtectionActive: true,
            measurementKind: "Predicted sample peak, not true peak"
        )
        let plan = DSPGainPlan.protectedPlan(
            userMasterGainDB: -2,
            replayGainDB: 4,
            clippingResult: clipping
        )

        XCTAssertEqual(plan.resultingGainDB, -1.52, accuracy: 0.001)
    }

    func testBitPerfectPlanIsExactlyUnityGain() {
        XCTAssertEqual(DSPGainPlan.bypassed.resultingGainDB, 0)
        XCTAssertEqual(DSPGainPlan.bypassed.replayGainDB, 0)
        XCTAssertEqual(DSPGainPlan.bypassed.clippingAdjustmentDB, 0)
    }
}
