import XCTest
@testable import PlayerApp

final class ClippingProtectionTests: XCTestCase {
    func testPredictedPeakAddsMasterReplayGainAndLargestBandBoost() {
        let result = ClippingProtectionController().evaluate(
            sourceSamplePeak: 0.8,
            userGainDB: 2,
            replayGainDB: 1,
            maximumEnabledBandBoostDB: 3,
            preventClipping: true
        )

        XCTAssertGreaterThan(try XCTUnwrap(result.predictedSamplePeak), 1)
        XCTAssertLessThan(result.automaticHeadroomDB, 0)
        XCTAssertTrue(result.isProtectionActive)
        XCTAssertEqual(result.measurementKind, "Predicted sample peak, not true peak")
    }

    func testDisabledProtectionDoesNotApplyHeadroom() {
        let result = ClippingProtectionController().evaluate(
            sourceSamplePeak: 1,
            userGainDB: 12,
            replayGainDB: 0,
            maximumEnabledBandBoostDB: 6,
            preventClipping: false
        )

        XCTAssertEqual(result.automaticHeadroomDB, 0)
        XCTAssertFalse(result.isProtectionActive)
    }

    func testMissingPeakIsReportedWithoutClaimingTruePeakProtection() {
        let result = ClippingProtectionController().evaluate(
            sourceSamplePeak: nil,
            userGainDB: 6,
            replayGainDB: 0,
            maximumEnabledBandBoostDB: 0,
            preventClipping: true
        )

        XCTAssertNil(result.predictedSamplePeak)
        XCTAssertFalse(result.isProtectionActive)
        XCTAssertTrue(result.measurementKind.contains("unavailable"))
    }
}
